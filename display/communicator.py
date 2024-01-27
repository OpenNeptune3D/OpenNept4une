from logging import Logger
from tjc import TJCClient

class DisplayCommunicator:
    supported_firmware_versions = []
    def __init__(self, logger: Logger, port: str, event_handler, baudrate: int = 115200, timeout: int = 5) -> None:
        self.logger = logger
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout

        self.display = TJCClient(port, baudrate, event_handler)
        self.display.encoding = 'utf-8'

    async def connect(self):
        await self.display.connect()

    async def write(self, data):
        await self.display.command(data, self.timeout)

    async def get_firmware_version(self) -> str:
        pass

    async def check_valid_version(self):
        version = await self.get_firmware_version()
        if version not in self.supported_firmware_versions:
            self.logger.error("Unsupported firmware version. Things may not work as expected. Consider updating to a supported version: " + ", ".join(self.supported_firmware_versions))
            return False
        return True