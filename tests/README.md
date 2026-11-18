# Tests and host sandbox

This folder has two jobs:

1. **CI / laptop smoke tests** — syntax and generated `printer.cfg` checks. No hardware.
2. **Host sandbox** — an Ubuntu or Raspberry Pi box that runs the Klipper *host* stack so we can test scripts, macros, and Fluidd without the Neptune 4 Max.

## What the sandbox is

The Max is three machines: Linux host (RK3328), STM32 motion MCU, and real heaters / probe / TMC drivers.

A Parallels Ubuntu ARM64 VM, or a Pi 4 / Pi 5, can stand in for the **Linux host only**. Same job as the board’s Armbian side: Klipper, Moonraker, Fluidd, `generate_conf.py`, installer scripts.

It cannot emulate:

- STM32 pins (`PC14`, `PA7`, …)
- Sensorless homing / StallGuard
- The bed probe, heaters, or input shaper
- The OpenNept4une Armbian image (that image is for the ZNP-K1)

Do not flash the OpenNept4une `.img` into Parallels. Do not use an `amd64` Ubuntu ISO on Apple Silicon.

## Smoke tests (laptop or CI)

From the repo root:

```bash
bash tests/smoke.sh
```

That checks:

- `bash -n` on every `.sh` file
- `shellcheck --severity=error` when installed
- installer paths referenced by `OpenNept4une.sh`
- `OpenNept4une.sh --help` (needs GNU `getopt`, i.e. Linux)
- `generate_conf.py` for N4 0.8/1.2, N4 Pro 0.8/1.2, Plus, and Max

GitHub Actions runs the same script from `.github/workflows/smoke.yml`.

## Parallels VM (Apple Silicon)

This is the path used for `OpenNept4une-pi` on an M1/M2/M3/M4 Mac.

### Create the VM

```bash
prlctl create OpenNept4une-pi -o linux -d ubuntu
prlctl set OpenNept4une-pi --cpus 4 --memsize 4096 --autostart off
```

Use ARM64 Ubuntu Server. A Pi 4/5 class box is 4 cores / 4 GB. The virtual disk can stay at 64 GB **expanding** — Parallels does not consume 64 GB on the Mac until the guest writes data.

ISO (ARM64 server, not desktop, not amd64):

```text
https://cdimage.ubuntu.com/ubuntu/releases/24.04.3/release/ubuntu-24.04.3-live-server-arm64.iso
```

Attach and boot:

```bash
prlctl set OpenNept4une-pi --device-set cdrom0 \
  --image /path/to/ubuntu-24.04.3-live-server-arm64.iso --connect
prlctl start OpenNept4une-pi
```

### Ubuntu installer choices

Pick **Ubuntu Server**, not **Ubuntu Server (minimized)**. Minimized drops tools Kiauh / Klipper / compilers expect. Disk space is not the constraint here.

| Screen | Choice |
|---|---|
| Language / keyboard | Your locale |
| Install type | **Ubuntu Server** (not minimized) |
| Network | Keep DHCP on `enp0s5`. Do **not** create a bond. Parallels typically assigns `10.211.55.x` |
| Proxy | Empty unless you need one |
| Mirror | Default |
| Disk | Use the **whole** 64 GB virtual disk. Default LVM/ext4 is fine |
| Hostname | `opennept4une-pi` |
| Username | `mks` |
| OpenSSH | **Install** |
| Featured snaps | **None**. Leave every snap unchecked |
| Desktop | Do not install one |

`10.211.55.x` is the address the Mac browser will use for Fluidd. It can change after reboot until you add a DHCP reservation.

After the installer reboots, log in and install Parallels Tools from the Parallels menu so `prlctl exec` and shared folders work.

## Raspberry Pi instead of Parallels

Use a **Pi 4 or Pi 5**. Skip Pi 2 and Pi Zero for Moonraker + Fluidd.

Install Raspberry Pi OS 64-bit (or Ubuntu Server 24.04 ARM64), enable SSH, then run `tests/setup.sh` the same way.

## Provision the host stack

On the new Ubuntu/Pi user (after first boot):

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/OpenNeptune3D/OpenNept4une.git ~/OpenNept4une
cd ~/OpenNept4une
sudo ./tests/setup.sh
```

`setup.sh` is safe to re-run. It:

- refuses to run on a real OpenNept4une printer image unless you pass `--force`
- installs apt packages needed to build Klipper and the Linux process MCU
- clones Klipper, Moonraker, Fluidd, KAMP, and Kiauh
- runs the upstream Klipper / Moonraker installers
- installs Fluidd behind nginx on port 80
- generates every model `printer.cfg` into `~/printer_data/config/generated/`
- installs a **sandbox** `printer.cfg` that talks to the Linux process MCU, not `/dev/ttyS0`

Open Fluidd at `https://<guest-ip>/` (Parallels example: `https://10.211.55.11/`). Moonraker stays on port `7125` behind nginx.

HTTPS uses a **self-signed** certificate. Let's Encrypt cannot sign a Parallels `10.211.55.x` address. The browser will warn; click Advanced → Proceed.

To add HTTPS to an already-provisioned sandbox:

```bash
sudo ./tests/enable-https.sh
```

To trust the cert on the Mac after that:

```bash
scp mks@10.211.55.11:/etc/ssl/opennept4une/opennept4une.crt /tmp/opennept4une.crt
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/opennept4une.crt
```

Kiauh is left in `~/kiauh` for later interactive updates. It is not required for the first boot.

## What you can test here vs on the printer

**On the sandbox**

- `tests/smoke.sh` and `generate_conf.py`
- Fluidd / Moonraker / Orca network upload
- Jinja macros that do not need a real toolhead
- Installer script edits (`bash -n`, `--help`)

**On the Max only**

- Homing, mesh, Z-offset, PID, pressure advance, input shaper
- MCU `.bin` flashes
- Heat-soak and first-layer

Keep live printer overrides in `user_settings.cfg`. Do not treat sandbox motion values as calibrated Max values.
