from nextion import Nextion, EventType
from nextion.protocol.nextion import NextionProtocol
from collections import namedtuple
import struct

TJCTouchDataPayload = namedtuple("Touch", "page_id component_id")

class TJCProtocol(NextionProtocol):
    PACKET_LENGTH_MAP = {
        0x00: 6,  # Nextion Startup
        0x24: 4,  # Serial Buffer Overflow
        0x65: 6,  # Touch Event
        0x66: 5,  # Current Page Number
        0x67: 9,  # Touch Coordinate(awake)
        0x68: 9,  # Touch Coordinate(sleep)
        0x71: 8,  # Numeric Data Enclosed
        0x86: 4,  # Auto Entered Sleep Mode
        0x87: 4,  # Auto Wake from Sleep
        0x88: 4,  # Nextion Ready
        0x89: 4,  # Start microSD Upgrade
        0xFD: 4,  # Transparent Data Finished
        0xFE: 4,  # Transparent Data Ready
    }

    def _extract_packet(self):
        if len(self.buffer) < 3:
            return None

        expected_packet_length = self.PACKET_LENGTH_MAP.get(self.buffer[0])
        if expected_packet_length is None:
            return self._extract_varied_length_packet()
        else:
            return self._extract_fixed_length_packet(expected_packet_length)
        
    def _extract_fixed_length_packet(self, expected_packet_length):
        buffer_len = len(self.buffer)
        if buffer_len < expected_packet_length:
            return None

        full_message = self.buffer[:expected_packet_length]
        if not full_message.endswith(self.EOL):
            if self.buffer[0] == 0x65:
                # Touch event that might have the press/release byte
                full_message = self.buffer[:expected_packet_length + 1]
                if full_message.endswith(self.EOL):
                    self.buffer = self.buffer[expected_packet_length:]
                    return full_message[:-3]
            message = self._extract_varied_length_packet()
            if message is None:
                return None

            self.dropped_buffer += message + self.EOL
            return self._extract_packet()
        self.buffer = self.buffer[expected_packet_length:]
        return full_message[:-3]
        
class TJCClient(Nextion):

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
        super.event_message_handler(message)