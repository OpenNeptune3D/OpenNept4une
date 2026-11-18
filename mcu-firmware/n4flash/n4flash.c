// n4flash.c -- firmware updater for Elegoo Neptune 4 with USB-C toolhead
//
// https://codeberg.org/gggcodes/n4flash
//
// Usage: ./n4flash <firmware.bin> </dev/ttyACM0>
//
// NOTE:
//   This tool was originally designed to flash the USB-C toolhead firmware but
//   can flash the main MCU over serial as well since it speaks the same
//   bootloader protocol (although runs a different firmware because it is
//   actual serial not serial over USB).
//
// NOTE:
//   The easiest way to put the USB-C toolhead into the bootloader is to just
//   lower gpio82 (power off the toolhead) and then power it on again. The
//   bootloader is entered for 10s on startup before going into the application
//   firmware. You should see /dev/serial/by-id/usb-MKS_DRIVER_BOOT_*
//
// PROTOCOL
//
// The bootloader shows up as a tty (ex /dev/ttyACM0) via USB-CDC ACM.
//   wire messages:
//     [0xA5][cmd][len_hi][len_lo][N payload bytes][crc_hi][crc_lo]
//
//   - 0xA5 is a fixed sync byte
//   - len is the payload length, big-endian
//   - crc is CRC16 0x8005
//
// There are 3 main commands (and one with subcommands)
//
//   cmd 0x00  HELLO   payload = {0x01, 0x00}
//
//     The bootloader sends this same framing on its own, periodically,
//     whenever it's idle
//
//   cmd 0x01  CONTROL payload = u16 subcommand little-endian
//
//     sub 0x0001  START   + u32 total_image_size (big-endian)
//       MCU records the size, then  mass erases the entir* 96KB app partition
//       (0x08008000-0x08020000) before a single data byte has arrived. At this
//       point the device has no bootable application until a transfer
//       completes successfully.
//
//     sub 0x0102  END
//       Sent once the whole file has been streamed successfully. MCU checks
//       the received byte count against the declared size in START, if all
//       good boots the application after a short delay (so host can get ACK)
//
//     sub 0x0202  ABORT
//       Sent if the transfer failed, MCU erases just the first 2KB page of the
//       app region, which is enough to signify for the bootloader to know
//       there is no app and not try to boot into app. Then will reboot (back
//       into bootloader again).
//
//   cmd 0x02  DATA    payload = u32 page_index big-endian
//                             + u16 chunk_len  big-endian
//                             + up to 1024 bytes of firmware data
//
//    MCU checks the CRC and writes the chunk to flash, then does read-back
//    verify one 32-bit word at a time. Replies the page index and length,
//    followed by a status byte: 1 = ok, 2 = failed. If failed will resend the
//    same chunk again. If no response also sends the same chunk again (not
//    sure why this should ever happen, and why just sending again should be
//    the right thing to do).

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <termios.h>

#define FRAME_SYNC      0xA5

#define CMD_HELLO       0x00
#define CMD_CONTROL     0x01
#define CMD_DATA        0x02

#define SUB_START       0x0001
#define SUB_END         0x0102
#define SUB_ABORT       0x0202

#define CHUNK_SIZE      1024
#define MAX_FRAME       (6 + 6 + CHUNK_SIZE)

#define HELLO_RETRIES   3
#define START_RETRIES   3
#define CHUNK_RETRIES   8
#define END_RETRIES     3
#define ACK_TIMEOUT_MS  1500

// crc16 poly 0x8005
static uint16_t crc16_usb(const uint8_t *data, size_t len) {
  uint16_t crc = 0xFFFFu;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; bit++)
      crc = (crc & 1) ? (crc >> 1) ^ 0xA001u : (crc >> 1);
  }
  return crc ^ 0xFFFFu; // ~crc without int promotion
}

static size_t build_frame(uint8_t *buf, uint8_t cmd, const uint8_t *payload, uint16_t paylen) {
  buf[0] = FRAME_SYNC;
  buf[1] = cmd;
  buf[2] = (uint8_t)(paylen >> 8);
  buf[3] = (uint8_t)(paylen & 0xFF);
  if (paylen) {
    memcpy(buf + 4, payload, paylen);
  }
  uint16_t crc = crc16_usb(buf + 1, 3u + paylen);
  buf[4 + paylen] = (uint8_t)(crc >> 8);
  buf[5 + paylen] = (uint8_t)(crc & 0xFF);
  return 6u + paylen;
}

// Validates sync/length/CRC and points *payload / *paylen into buf in place.
// Returns 0 success otherwise -1
static int parse_frame(const uint8_t *buf, size_t n, uint8_t *cmd,
                       const uint8_t **payload, uint16_t *paylen) {
  if (n < 6 || buf[0] != FRAME_SYNC) {
    return -1;
  }
  uint16_t len = (uint16_t)((buf[2] << 8) | buf[3]);
  if (n < (size_t)(6 + len)) {
    return -1;
  }
  uint16_t crc_rx = (uint16_t)((buf[4 + len] << 8) | buf[5 + len]);
  if (crc_rx != crc16_usb(buf + 1, 3u + len)) {
    return -1;
  }

  *cmd = buf[1];
  *payload = buf + 4;
  *paylen = len;
  return 0;
}

// Set 115200 8N1, doesn't matter for USB but need it for the main MCU.
static int open_serial(const char *path) {
  int fd = open(path, O_RDWR | O_NOCTTY);
  if (fd < 0) {
    fprintf(stderr, "open(%s): %s\n", path, strerror(errno));
    return -1;
  }

  struct termios tio;
  if (tcgetattr(fd, &tio) < 0) {
    fprintf(stderr, "tcgetattr(%s): %s\n", path, strerror(errno));
    close(fd);
    return -1;
  }

  tio.c_iflag &= ~(IXON | IXOFF | IXANY | INLCR | IGNCR | ICRNL);
  tio.c_cflag &= ~(CSIZE | CSTOPB | PARENB);
  tio.c_cflag |= CS8 | CLOCAL | CREAD;
  tio.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
  tio.c_oflag = 0;

  if (cfsetspeed(&tio, B115200) < 0) {
    fprintf(stderr, "cfsetspeed(%s): %s\n", path, strerror(errno));
    close(fd);
    return -1;
  }

  tio.c_cc[VMIN] = 0;
  tio.c_cc[VTIME] = 1; // 100ms read granularity, but also we select()

  if (tcsetattr(fd, TCSANOW, &tio) < 0) {
    fprintf(stderr, "tcsetattr(%s): %s\n", path, strerror(errno));
    close(fd);
    return -1;
  }
  tcflush(fd, TCIOFLUSH);
  return fd;
}

static long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

// This is fairly overkill as we only get really simple frames back in practice
// but whatever might as well do the real thing.
static size_t recv_frame(int fd, uint8_t *buf, size_t bufsz, int timeout_ms) {
  size_t got = 0;
  long deadline = now_ms() + timeout_ms;

  while (got < bufsz) {
    long remain = deadline - now_ms();
    if (remain <= 0)
      break;

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    struct timeval tv = { remain / 1000, (remain % 1000) * 1000 };
    if (select(fd + 1, &fds, NULL, NULL, &tv) <= 0)
      break;

    ssize_t n = read(fd, buf + got, bufsz - got);
    if (n <= 0)
      break;
    got += (size_t)n;

    if (got >= 4) {
      uint16_t declared = (uint16_t)((buf[2] << 8) | buf[3]);
      if (got >= (size_t)(6 + declared))
        break; // have at least a whole frame
    }
  }
  return got;
}

// Sends a frame and waits for any valid reply
static int send_and_wait(int fd, uint8_t cmd, const uint8_t *payload, uint16_t paylen,
                         int retries, uint8_t *rcmd, const uint8_t **rpayload, uint16_t *rlen) {
  static uint8_t txbuf[MAX_FRAME];
  static uint8_t rxbuf[MAX_FRAME];

  size_t flen = build_frame(txbuf, cmd, payload, paylen);

  for (int attempt = 0; attempt < retries; attempt++) {
    if (write(fd, txbuf, flen) != (ssize_t)flen) {
      fprintf(stderr, "serial write failed: %s\n", strerror(errno));
      return -1;
    }
    size_t n = recv_frame(fd, rxbuf, sizeof(rxbuf), ACK_TIMEOUT_MS);
    if (parse_frame(rxbuf, n, rcmd, rpayload, rlen) == 0)
      return 0;
    // timeout or bad frame, loop around and resend
  }
  return -1;
}

static int do_hello(int fd) {
  uint8_t version[2] = { 0x01, 0x00 };
  uint8_t rcmd; const uint8_t *rpay; uint16_t rlen; uint16_t i;
  printf("> hello...\n");
  if (send_and_wait(fd, CMD_HELLO, version, sizeof(version), HELLO_RETRIES, &rcmd, &rpay, &rlen) < 0) {
    fprintf(stderr, "  no response from bootloader\n");
    return -1;
  }
  // send_and_wait checks for a proper frame (CRC etc), we expect payload
  // 0x01 0x12 as the only proper response to hello
  if (rlen != 2 || rpay[0] != 0x01 || rpay[1] != 0x12) {
    fprintf(stderr, "Unexpected reply to hello:");
    for (i = 0; i < rlen; i++) {
      fprintf(stderr, "%02x", rpay[i]);
    }
    fprintf(stderr, "\n");
    return -1;
  }
  return 0;
}

static int do_start(int fd, uint32_t file_size) {
  uint8_t payload[6];
  payload[0] = (uint8_t)(SUB_START & 0xFF);
  payload[1] = (uint8_t)(SUB_START >> 8);
  payload[2] = (uint8_t)(file_size >> 24);
  payload[3] = (uint8_t)(file_size >> 16);
  payload[4] = (uint8_t)(file_size >> 8);
  payload[5] = (uint8_t)(file_size);

  uint8_t rcmd; const uint8_t *rpay; uint16_t rlen;
  printf("> start update (%u bytes) -- device is mass-erasing app region now\n", file_size);
  if (send_and_wait(fd, CMD_CONTROL, payload, sizeof(payload), START_RETRIES, &rcmd, &rpay, &rlen) < 0) {
    fprintf(stderr, "  no response to start command\n");
    return -1;
  }
  return 0;
}

// Sends one 1KB (or less) chunk at the given page index
static int send_chunk(int fd, uint32_t page_index, const uint8_t *data, uint16_t len) {
  uint8_t payload[6 + CHUNK_SIZE];
  payload[0] = (uint8_t)(page_index >> 24);
  payload[1] = (uint8_t)(page_index >> 16);
  payload[2] = (uint8_t)(page_index >> 8);
  payload[3] = (uint8_t)(page_index);
  payload[4] = (uint8_t)(len >> 8);
  payload[5] = (uint8_t)(len);
  memcpy(payload + 6, data, len);

  for (int attempt = 0; attempt < CHUNK_RETRIES; attempt++) {
    uint8_t rcmd; const uint8_t *rpay; uint16_t rlen;
    if (send_and_wait(fd, CMD_DATA, payload, (uint16_t)(6 + len), 1, &rcmd, &rpay, &rlen) < 0)
      continue; // timeout, resend the same chunk
    if (rcmd == CMD_DATA && rlen > 6) {
      if (rpay[6] == 1)
        return 0; // written and verified
      if (rpay[6] == 2)
        continue; // verify failed, resend the same chunk
    }
    // something unexpected, resend the same chunk
  }
  return -1;
}

static int do_end_or_abort(int fd, int success) {
  uint16_t sub = success ? SUB_END : SUB_ABORT;
  uint8_t payload[2] = { (uint8_t)(sub & 0xFF), (uint8_t)(sub >> 8) };
  uint8_t rcmd; const uint8_t *rpay; uint16_t rlen;

  printf("> sending %s\n", success ? "end" : "abort");
  if (send_and_wait(fd, CMD_CONTROL, payload, sizeof(payload), END_RETRIES, &rcmd, &rpay, &rlen) < 0) {
    fprintf(stderr, "  no response to %s -- device should timeout and reboot\n", success ? "end" : "abort");
    return -1;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <firmware.bin> <serial-port>\n", argv[0]);
    return 1;
  }
  const char *fw_path = argv[1];
  const char *port_path = argv[2];

  struct stat st;
  if (stat(fw_path, &st) != 0) {
    fprintf(stderr, "stat(%s): %s\n", fw_path, strerror(errno));
    return 1;
  }
  uint32_t file_size = (uint32_t)st.st_size;

  FILE *fw = fopen(fw_path, "rb");
  if (!fw) {
    fprintf(stderr, "fopen(%s): %s\n", fw_path, strerror(errno));
    return 1;
  }

  int fd = open_serial(port_path);
  if (fd < 0) {
    fclose(fw);
    return 1;
  }

  int rc = 1;
  if (do_hello(fd) < 0)
    goto out;
  if (do_start(fd, file_size) < 0)
    goto out;

  // From here on the app partition is erased, try to at least send end or
  // abort no matter what.
  int ok = 1;
  uint32_t page = 0;
  uint8_t chunk[CHUNK_SIZE];
  size_t n;
  while ((n = fread(chunk, 1, sizeof(chunk), fw)) > 0) {
    printf("> chunk %u (%zu bytes)\n", page, n);
    if (send_chunk(fd, page, chunk, (uint16_t)n) < 0) {
      fprintf(stderr, "  chunk %u failed after %d attempts\n", page, CHUNK_RETRIES);
      ok = 0;
      break;
    }
    page++;
  }

  do_end_or_abort(fd, ok);
  rc = ok ? 0 : 1;

out:
  close(fd);
  fclose(fw);
  printf(rc == 0 ? "> done\n" : "> failed\n");
  return rc;
}
