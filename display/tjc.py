from nextion import Nextion, EventType
from nextion.protocol.nextion import NextionProtocol
from nextion.exceptions import CommandFailed, CommandTimeout, ConnectionFailed

from collections import namedtuple
import struct
import binascii
from enum import IntEnum

TJCTouchDataPayload = namedtuple("Touch", "page_id component_id")
TJCStringInputPayload = namedtuple("String", "page_id component_id string")
TJCNumericInputPayload = namedtuple("Numeric", "page_id component_id value")

class EventType(IntEnum):
    TOUCH = 0x65  # Touch event
    TOUCH_COORDINATE = 0x67  # Touch coordinate
    TOUCH_IN_SLEEP = 0x68  # Touch event in sleep mode
    SLIDER_INPUT = 0x69
    NUMERIC_INPUT = 0x72  # Numeric input
    AUTO_SLEEP = 0x86  # Device automatically enters into sleep mode
    AUTO_WAKE = 0x87  # Device automatically wake up
    STARTUP = 0x88  # System successful start up
    SD_CARD_UPGRADE = 0x89  # Start SD card upgrade
    RECONNECTED = 0x666  # Device reconnected

JUNK_DATA = b'Z\xa5\x06\x83\x10>\x01\x00'

class TJCProtocol(NextionProtocol):
    PACKET_LENGTH_MAP = {
        0x00: 6,  # Nextion Startup
        0x24: 4,  # Serial Buffer Overflow
        0x65: 6,  # Touch Event
        0x66: 5,  # Current Page Number
        0x67: 9,  # Touch Coordinate(awake)
        0x68: 9,  # Touch Coordinate(sleep)
        0x69: 8,  # Slider Value
        0x71: 5,  # Numeric Data Enclosed
        0x86: 4,  # Auto Entered Sleep Mode
        0x87: 4,  # Auto Wake from Sleep
        0x88: 4,  # Nextion Ready
        0x89: 4,  # Start microSD Upgrade
        0xFD: 4,  # Transparent Data Finished
        0xFE: 4,  # Transparent Data Ready
    }
    
    def is_event(self, message):
        return len(message) > 0 and message[0] in EventType.__members__.values()
    
    def data_received(self, data):
        self.buffer += data

        while True:
            (message, was_keyboard_input) = self._extract_packet()

            if message is None:  # EOL not found
                break

            self._reset_dropped_buffer()

            if self.is_event(message) or was_keyboard_input:
                self.event_message_handler(message)
            else:
                self.queue.put_nowait(message)

    def _extract_packet(self):
        if len(self.buffer) < 3:
            return None, False

        expected_packet_length = self.PACKET_LENGTH_MAP.get(self.buffer[0])
        if expected_packet_length is None:
            return self._extract_varied_length_packet()
        else:
            return self._extract_fixed_length_packet(expected_packet_length)

    def _extract_fixed_length_packet(self, expected_packet_length):
        was_keyboard_input = False
        buffer_len = len(self.buffer)
        if buffer_len < expected_packet_length:
            return None, was_keyboard_input

        full_message = self.buffer[:expected_packet_length]

        if full_message[0] == 0x71 and not full_message.endswith(self.EOL):
            # Keyboard input does not result in correct packet length
            full_message += self.EOL
            full_message = b'0x72' + full_message[1:]
            was_keyboard_input = True

        if  not full_message.endswith(self.EOL):
            if self.buffer[0] == 0x65:
                # Touch event that might have the press/release byte
                full_message = self.buffer[:expected_packet_length + 1]
                if full_message.endswith(self.EOL):
                    self.buffer = self.buffer[expected_packet_length + 1:]
                    return full_message[:-3], was_keyboard_input
            message = self._extract_varied_length_packet()
            if message is None:
                return None, was_keyboard_input

            self.dropped_buffer += message + self.EOL
            return self._extract_packet()
        self.buffer = self.buffer[expected_packet_length:]
        if self.buffer.startswith(self.EOL):
            # in case the 0x71 command did send the EOL
            self.buffer = self.buffer[3:]
            was_keyboard_input = False

        return full_message[:-3], was_keyboard_input
        
    def _extract_varied_length_packet(self):
        message, eol, leftover = self.buffer.partition(self.EOL)
        if eol == b"":
            if message.startswith(JUNK_DATA):
                self.buffer = leftover
                return None, False
            return None, False

        self.buffer = leftover
        return message, False

class TJCClient(Nextion):
    is_reconnecting = False

    def _make_protocol(self):
        return TJCProtocol(event_message_handler=self.event_message_handler)
    
    def event_message_handler(self, message):
        typ = message[0]
        if typ == EventType.TOUCH:  # Touch event
            self._schedule_event_message_handler(
                EventType(typ),
                TJCTouchDataPayload._make(struct.unpack("BB", message[1:])),
            )
            return
        elif typ == EventType.NUMERIC_INPUT:
            self._schedule_event_message_handler(
                EventType(typ),
                TJCNumericInputPayload._make(struct.unpack("BBH", message[1:])),
            )
            return
        elif typ == EventType.SLIDER_INPUT:
            self._schedule_event_message_handler(
                EventType(typ),
                TJCNumericInputPayload._make(struct.unpack("BBH", message[1:])),
            )
            return
        super().event_message_handler(message)

    async def reconnect(self):
        await self._connection.close()
        self.is_reconnecting = True
        await self.connect()

    async def connect(self) -> None:
        try:
            result = await self._try_connect_on_different_baudrates()

            try:
                await self._command("bkcmd=3", attempts=1)
            except CommandTimeout as e:
                pass  # it is fine

            await self._update_sleep_status()
            if self.is_reconnecting:
                self.is_reconnecting = False
                self._schedule_event_message_handler(EventType.RECONNECTED, None)
        except ConnectionFailed:
            raise
        except:
            raise