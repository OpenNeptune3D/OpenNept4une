import json
import sys
import logging
import pathlib
import requests
import serial
import serial_asyncio
import time
import re
import os, os.path
import asyncio
import traceback

from response_actions import response_actions, response_errors

logger = logging.getLogger(__name__)

log_file = "/home/mks/printer_data/logs/display_connector.log"

def format_temp(value):
    if value is None:
        return "N/A"
    return f"{value:3.1f}°C"

def format_time(seconds):
    if seconds is None:
            return "N/A"
    if seconds < 3600:
        return time.strftime("%Mm %Ss", time.gmtime(seconds))
    return time.strftime("%Hh %Mm", time.gmtime(seconds))

def format_percent(value):
    if value is None:
        return "N/A"
    return f"{value * 100:2.0f}%"

class MappingLeaf:
    def __init__(self, fields, field_type="txt", formatter=None):
        self.fields = fields
        self.field_type = field_type
        self.formatter = formatter

    def format(self, value):
        if self.formatter is not None:
            return self.formatter(value)
        if isinstance(value, float):
            return f"{value:3.2f}"
        return str(value)

DATA_MAPPING = {
    "extruder": {
        "temperature": [MappingLeaf(["p[1].nozzletemp", "p[6].nozzletemp", "p[19].nozzletemp", "p[27].nozzletemp", "p[28].nozzletemp"], formatter=format_temp)],
        "target": [MappingLeaf(["p[27].nozzletemp_t", "p[28].nozzletemp_t"], formatter=format_temp)]
    },
    "heater_bed": {
        "temperature": [MappingLeaf(["p[1].bedtemp", "p[6].bedtemp", "p[19].bedtemp", "p[27].bedtemp", "p[28].bedtemp"], formatter=format_temp)],
        "target": [MappingLeaf(["p[27].bedtemp_t", "p[28].bedtemp_t"], formatter=format_temp)]
    },
    "heater_generic heater_bed_outer": {
        "temperature": [MappingLeaf(["p[1].out_bedtemp", "p[6].out_bedtemp", "p[27].out_bedtemp"], formatter=format_temp)],
        "target": [MappingLeaf(["p[27].out_bedtemp_t", "p[28].out_bedtemp_t"], formatter=format_temp)]
    },
    "motion_report": {
        "live_position": {
            0: [MappingLeaf(["p[1].x_pos"]), MappingLeaf(["p[19].x_pos"], formatter=lambda x: f"X[{x:3.2f}]")],
            1: [MappingLeaf(["p[1].y_pos"]), MappingLeaf(["p[19].y_pos"], formatter=lambda y: f"Y[{y:3.2f}]")],
            2: [MappingLeaf(["p[1].z_pos", "p[19].zvalue"])],
        },
        "live_velocity": [MappingLeaf(["p[19].pressure_val"], formatter=lambda x: f"{x:3.2f}mm/s")],
    },
    "print_stats": {
        "print_duration": [MappingLeaf(["p[19].b[6]"], formatter=format_time)],
        "filename": [MappingLeaf(["p[19].t0"])],
    },
    "gcode_move": {
        "extrude_factor": [MappingLeaf(["p[19].flow_speed"], formatter=format_percent)],
        "speed_factor": [MappingLeaf(["p[19].printspeed"], formatter=format_percent)],
        "homing_origin": {
            2: [MappingLeaf(["p[127].b[15]"], formatter=lambda x: f"{x:.3f}")],
        }
    },
    "fan": {
        "speed": [MappingLeaf(["p[19].fanspeed"], formatter=format_percent), MappingLeaf(["p[11].b[12]"], field_type="pic", formatter=lambda x: "77" if int(x) == 1 else "76")]
    },
    "display_status": {
        "progress": [MappingLeaf(["p[19].printvalue"], formatter=lambda x: f"{x * 100:2.1f}"), MappingLeaf(["p[19].printprocess"], field_type="val", formatter=lambda x: f"{x * 100:2.0f}")]
    },
    "output_pin Part_Light": {"value": [MappingLeaf(["p[84].led1"], field_type="pic", formatter=lambda x: "77" if int(x) == 1 else "76")]},
    "output_pin Frame_Light": {"value": [MappingLeaf(["p[84].led2"], field_type="pic", formatter= lambda x: "77" if int(x) == 1 else "76")]},
    "filament_switch_sensor fila": {"enabled": [MappingLeaf(["p[11].b[11]", "p[127].b[16]"], field_type="pic", formatter= lambda x: "77" if int(x) == 1 else "76")]}
}

PRINTING_PAGES = [
    "page 19",
    "page 27",
    "page 127",
    "page 135",
    "page 106",
    "page 25",
    "page 26",
    "page 84",
]

TABBED_PAGES = [
    "page 6",
    "page 8",
    "page 9",
    "page 27",
    "page 28",
    "page 29",
    "page 30",
]

TRANSITION_PAGES = [
    "page 130",
]

MODEL_REGULAR = 'N4'
MODEL_PRO = 'N4Pro'
MODEL_PLUS = 'N4Plus'
MODEL_MAX = 'N4Max'

BACKGROUND_GRAY = 10665

SOCKET_LIMIT = 20 * 1024 * 1024
class DisplayController:

    def __init__(self):
        self.connected = False
        self.part_light_state = False
        self.frame_light_state = False
        self.fan_state = False
        self.filament_sensor_state = False
        self.is_blocking_serial = False
        self.move_distance = '1'
        self.z_offset_distance = '0.01'
        self.out_fd = sys.stdout.fileno()
        os.set_blocking(self.out_fd, False)
        self.pending_req = {}
        self.pending_reqs = {}
        self.history = []
        padding = [0xFF, 0xFF, 0xFF]
        self.serial_padding = serial.to_bytes(padding)
        self.current_state = "booting"

        self.printer_model = self.get_printer_model_from_file()

        self.dir_contents = []
        self.current_dir = ""
        self.files_page = 0

        self.printing_selected_heater = "extruder"
        self.printing_target_temps = {
            "extruder": 0,
            "heater_bed": 0,
            "heater_bed_outer": 0
        }
        self.printing_selected_temp_increment = "10"
        self.printing_selected_speed_type = "print"
        self.printing_target_speeds = {
            "print": 1.0,
            "flow": 1.0,
            "fan": 1.0
        }
        self.printing_selected_speed_increment = "10"

        self.ips = "--"

        self.current_filename = None

        self.klipper_restart_event = asyncio.Event()

    async def monitor_log(self):
        log_file_path = "/home/mks/printer_data/logs/klippy.log"

        try:
            # Open the log file for reading in text mode
            with open(log_file_path, 'r') as log_file:
                # Move the file pointer to the end of the file
                log_file.seek(0, os.SEEK_END)

                while True:
                    line = log_file.readline()
                    if not line:
                        await asyncio.sleep(0.1)  # Sleep briefly if no new data
                        continue

                    # Strip the line and check if it contains "Starting Klippy..."
                    line = line.strip()
                    if "Restarting printer" in line or "Starting Klippy..." in line:
                        logger.info("Klipper is restarting.")
                        self.klipper_restart_event.set()
                        # Add your desired action here for Klipper restart detection

        except FileNotFoundError:
            logger.error(f"Klipper log file not found at {log_file_path}.")
        except Exception as e:
            logger.error(f"Error while monitoring Klipper log: {e}")

    def get_printer_model_from_file(self):
        try:
            with open('/boot/.OpenNept4une.txt', 'r') as file:
                for line in file:
                    if line.startswith(tuple([MODEL_REGULAR, MODEL_PRO, MODEL_PLUS, MODEL_MAX])):
                        model_part = line.split('-')[0]
                        logger.info(f"Extracted Model: {model_part}")
                        return model_part
        except FileNotFoundError:
            logger.error("File not found")
        except Exception as e:
            logger.error(f"Error reading file: {e}")
        return None

    def get_device_name(self):
        model_map = {
            MODEL_REGULAR: "Neptune 4",
            MODEL_PRO: "Neptune 4 Pro",
            MODEL_PLUS: "Neptune 4 Plus",
            MODEL_MAX: "Neptune 4 Max",
        }

    def initialize_display(self):
        if self.printer_model == MODEL_REGULAR:
            self._write(f'p[1].q4.picc=213') # 213=N4
        elif self.printer_model == MODEL_PRO:
            self._write(f'p[1].q4.picc=214') #214=N4Pro
            self._write(f'p[1].disp_q5.val=1') # N4Pro Outer Bed Symbol (Bottom Rig>
            self._write(f'vis out_bedtemp,1') # Only N4Pro
        elif self.printer_model == MODEL_PLUS:
            self._write(f'p[1].q4.picc=213') # 213=N4
        elif self.printer_model == MODEL_MAX:
            self._write(f'p[1].q4.picc=213') # 213=N4

        self._write(f'p[35].b[8].txt="{self.get_device_name()}"')

    def send_gcode(self, gcode):
        logger.debug("Sending GCODE: " + gcode)
        self._loop.create_task(self._send_moonraker_request("printer.gcode.script", {"script": gcode}))

    def move_axis(self, axis, distance):
        self.send_gcode(f'G91\nG1 {axis}{distance}\nG90')

    def special_page_handling(self):
        current_page = self._get_current_page()
        if current_page == "page 2":
            self.show_files_page()
        elif current_page == "page 35":
            self._write('fill 0,400,320,60,' + str(BACKGROUND_GRAY))
            self._write('xstr 0,400,320,30,1,65535,' + str(BACKGROUND_GRAY) + ',1,1,1,"OpenNept4une"')
            self._write('xstr 0,430,320,30,2,GRAY,' + str(BACKGROUND_GRAY) + ',1,1,1,"github.com/halfmanbear/OpenNept4une"')
        elif current_page == "page 27":
            self.update_printing_heater_settings_ui()
            self.update_printing_temperature_increment_ui()
        elif current_page == "page 127":
            self.update_printing_zoffset_increment_ui()
            self._write("p[127].b[20].txt=\"" + self.ips + "\"")
        elif current_page == "page 135":
            self.update_printing_speed_settings_ui()
            self.update_printing_speed_increment_ui()

    def _navigate_to_page(self, page):
        if len(self.history) == 0 or self.history[-1] != page:
            if page in TABBED_PAGES and self.history[-1] in TABBED_PAGES:
                self.history[-1] = page
            elif page not in TRANSITION_PAGES:
                self.history.append(page)
            self._write(page)
            logger.info(f"Navigating {page}")

            self.special_page_handling()

    def execute_action(self, action):
        if action.startswith("move_"):
            parts = action.split('_')
            axis = parts[1].upper()
            direction = parts[2]
            self.move_axis(axis, direction + self.move_distance)
        elif action.startswith("set_distance_"):
            parts = action.split('_')
            self.move_distance = parts[2]
        if action.startswith("zoffset_"):
            parts = action.split('_')
            direction = parts[1]
            self.send_gcode(f"SET_GCODE_OFFSET Z_ADJUST={direction}{self.z_offset_distance} MOVE=1")
        elif action.startswith("zoffsetchange_"):
            parts = action.split('_')
            self.z_offset_distance = parts[1]
            self.update_printing_zoffset_increment_ui()
        elif action == "toggle_part_light":
            self.part_light_state = not self.part_light_state
            self._set_light("Part_Light", self.part_light_state)
        elif action == "toggle_frame_light":
            self.frame_light_state = not self.frame_light_state
            self._set_light("Frame_Light", self.frame_light_state)
        elif action == "toggle_filament_sensor":
            self.filament_sensor_state = not self.filament_sensor_state
            self._toggle_filament_sensor(self.filament_sensor_state)
        elif action == "toggle_fan":
            self.fan_state = not self.fan_state
            self._toggle_fan(self.fan_state)
        elif action.startswith("printer.send_gcode"):
            gcode = action.split("'")[1]
            self.send_gcode(gcode)
        elif action == "go_back":
            self._go_back()
        elif action.startswith("page"):
            self._navigate_to_page(action)
        elif action == "emergency_stop":
            logger.info("Executing emergency stop!")
            self._loop.create_task(self._send_moonraker_request("printer.emergency_stop"))
        elif action == "pause_print_button":
            if self.current_state == "paused":
                logger.info("Resuming print")
                self._loop.create_task(self._send_moonraker_request("printer.print.resume"))
            else:
                self._go_back()
                self._navigate_to_page("page 25")        
        elif action == "pause_print_confirm": 
            self._go_back()
            logger.info("Pausing print")
        elif action == "resume_print":
            self._go_back()
            self._loop.create_task(self._send_moonraker_request("printer.print.pause"))
        elif action == "stop_print":
            self._go_back()
            self._navigate_to_page('page 130')
            logger.info("Stopping print")
            self._loop.create_task(self._send_moonraker_request("printer.print.cancel"))
        elif action == "files_picker":
            self._navigate_to_page(f'page 2')
            self._loop.create_task(self._load_files())
        elif action.startswith("temp_heater_"):
            parts = action.split('_')
            self.printing_selected_heater = "_".join(parts[2:])
            self.update_printing_heater_settings_ui()
        elif action.startswith("temp_increment_"):
            parts = action.split('_')
            self.printing_selected_temp_increment = parts[2]
            self.update_printing_temperature_increment_ui()
        elif action.startswith("temp_adjust_"):
            parts = action.split('_')
            direction = parts[2]
            current_temp = self.printing_target_temps[self.printing_selected_heater]
            self.send_gcode(f"SET_HEATER_TEMPERATURE HEATER=" + self.printing_selected_heater + " TARGET=" + 
                            str(current_temp + (int(direction + self.printing_selected_temp_increment) * (1 if direction == '+' else -1))))
        elif action == "temp_reset":
            self.send_gcode(f"SET_HEATER_TEMPERATURE HEATER=" + self.printing_selected_heater + " TARGET=0")
        elif action.startswith("speed_type_"):
            parts = action.split('_')
            self.printing_selected_speed_type = parts[2]
            self.update_printing_speed_settings_ui()
        elif action.startswith("speed_increment_"):
            parts = action.split('_')
            self.printing_selected_speed_increment = parts[2]
            self.update_printing_speed_increment_ui()
        elif action.startswith("speed_adjust_"):
            parts = action.split('_')
            direction = parts[2]
            current_speed = self.printing_target_speeds[self.printing_selected_speed_type]
            change = (int(self.printing_selected_speed_increment) * (1 if direction == '+' else -1))
            self.send_speed_update(self.printing_selected_speed_type, (current_speed + (change / 100.0)) * 100)
        elif action == "speed_reset":
            self.send_speed_update(self.printing_selected_speed_type, 1.0)
        elif action.startswith("files_page_"):
            parts = action.split('_')
            direction = parts[2]
            self.files_page = int(max(0, min((len(self.dir_contents)/5), self.files_page + (1 if direction == 'next' else -1))))
            self.show_files_page()
        elif action.startswith("open_file_"):
            parts = action.split('_')
            index = int(parts[2])
            selected = self.dir_contents[(self.files_page * 5) + index]
            if selected["type"] == "dir":
                self.current_dir = selected["path"]
                self.files_page = 0
                self._loop.create_task(self._load_files())
            else:
                self.current_filename = selected["path"]
                self._navigate_to_page(f'page 18')
                self._write(f'p[18].b[2].txt="{self.current_filename.replace(".gcode", "").split("/")[-1]}"')
                self._loop.create_task(self.load_thumbnail_for_page(self.current_filename, "18"))
        elif action == "print_opened_file":
            self._go_back()
            self._navigate_to_page('page 130')
            self._loop.create_task(self._send_moonraker_request("printer.print.start", {"filename": self.current_filename}))
        elif action == "confirm_complete":
            logger.info("Clearing SD Card")
            self.send_gcode("SDCARD_RESET_FILE")

    def _write(self, data, forced = False):
        if self.is_blocking_serial and not forced:
            return
        message = str.encode(data)
        self.serial_writer.write(message)
        self.serial_writer.write(self.serial_padding)

    def _set_light(self, light_name, new_state):
        gcode = f"{light_name}_{'ON' if new_state else 'OFF'}"
        self.send_gcode(gcode)

    def _toggle_filament_sensor(self, state):
        gcode = f"SET_FILAMENT_SENSOR SENSOR=fila ENABLE={'1' if state else '0'}"
        self.send_gcode(gcode)

    def update_printing_heater_settings_ui(self):
        self._write(f'p[27].b0.picc=' + str(90 if self.printing_selected_heater == "extruder" else 89))
        self._write(f'p[27].b1.picc=' + str(90 if self.printing_selected_heater == "heater_bed" else 89))
        self._write(f'p[27].b2.picc=' + str(90 if self.printing_selected_heater == "heater_bed_outer" else 89))
        self._write(f'p[27].targettemp.val=' + str(self.printing_target_temps[self.printing_selected_heater]))

    def update_printing_temperature_increment_ui(self):
        self._write(f'p[27].p1.pic={56 + ["1", "5", "10"].index(self.printing_selected_temp_increment)}')

    def update_printing_speed_settings_ui(self):
        self._write(f'p[135].b0.picc=' + str(59 if self.printing_selected_speed_type == "print" else 58))
        self._write(f'p[135].b1.picc=' + str(59 if self.printing_selected_speed_type == "flow" else 58))
        self._write(f'p[135].b2.picc=' + str(59 if self.printing_selected_speed_type == "fan" else 58))
        self._write(f'p[135].targetspeed.val={self.printing_target_speeds[self.printing_selected_speed_type]*100:.0f}')

    def update_printing_speed_increment_ui(self):
        self._write(f'p[135].b[14].picc=' + str(59 if self.printing_selected_speed_increment == "1" else 58))
        self._write(f'p[135].b[15].picc=' + str(59 if self.printing_selected_speed_increment == "5" else 58))
        self._write(f'p[135].b[16].picc=' + str(59 if self.printing_selected_speed_increment == "10" else 58))

    def update_printing_zoffset_increment_ui(self):
        self._write(f'p[127].b[23].picc=' + str(36 if self.z_offset_distance == "0.01" else 65))
        self._write(f'p[127].b[24].picc=' + str(36 if self.z_offset_distance == "0.1" else 65))
        self._write(f'p[127].b[25].picc=' + str(36 if self.z_offset_distance == "1" else 65))

    def send_speed_update(self, speed_type, new_speed):
        if speed_type == "print":
            self.send_gcode(f"M220 S{new_speed:.0f}")
        elif speed_type == "flow":
            self.send_gcode(f"M221 S{new_speed:.0f}")
        elif speed_type == "fan":
            self.send_gcode(f"SET_FAN_SPEED FAN=fan SPEED={new_speed}")

    def _toggle_fan(self, state):
        gcode = f"M106 S{'255' if state else '0'}"
        self.send_gcode(gcode)

    def _build_path(self, *components):
        path = ""
        for component in components:
            if component is None or component == "" or component == "/":
                continue
            path += f"/{component}"
        return path[1:]

    async def _load_files(self):
        data = (await self._send_moonraker_request("server.files.get_directory", {"path": "/".join(["gcodes", self.current_dir])}))
        dir_info = data["result"]
        self.dir_contents = []
        for item in dir_info["dirs"]:
            if not item["dirname"].startswith("."):
                self.dir_contents.append({
                    "type": "dir",
                    "path": self._build_path(self.current_dir, item["dirname"]),
                    "name": item["dirname"]
                })
        for item in dir_info["files"]:
            if item["filename"].endswith(".gcode"):
                self.dir_contents.append({
                    "type": "file",
                    "path": self._build_path(self.current_dir, item["filename"]),
                    "name": item["filename"]
                })
        self.show_files_page()

    def show_files_page(self):
        page_size = 5
        self._write(f'p[2].b[11].txt="Files ({(self.files_page * page_size) + 1}-{(self.files_page * page_size) + page_size}/{len(self.dir_contents)})"')
        component_index = 0
        for index in range(self.files_page * page_size, min(len(self.dir_contents), (self.files_page + 1) * page_size)):
            file = self.dir_contents[index]
            self._write(f'p[2].b[{component_index + 18}].txt="{file["name"].replace(".gcode", "")}"')
            if file["type"] == "dir":
                self._write(f'p[2].b[{component_index + 13}].pic=194')
            else:
                self._write(f'p[2].b[{component_index + 13}].pic=193')
            component_index += 1
        for index in range(component_index, page_size):
            self._write(f'p[2].b[{index + 13}].pic=195')
            self._write(f'p[2].b[{index + 18}].txt=""')

    def _go_back(self):
        if len(self.history) > 1:
            if self._get_current_page() == "page 2":
                self.current_dir = "/".join(self.current_dir.split("/")[:-1])
                self.files_page = 0
                self._loop.create_task(self._load_files())
                return
            self.history.pop()
            back_page = self.history[-1]
            self._write(back_page)
            self.special_page_handling()
        else:
            logger.info("Already at the main page.")

    def start_listening(self):
        loop.create_task(self.listen())

    async def listen(self):
        self.serial_reader, self.serial_writer = await serial_asyncio.open_serial_connection(url='/dev/ttyS1', baudrate=115200)
        self._loop.create_task(self._process_serial(self.serial_reader))
        await self._connect()
        ret = await self._send_moonraker_request("printer.objects.subscribe", {"objects": {
            "gcode_move": ["extrude_factor", "speed_factor", "homing_origin"],
            "motion_report": ["live_position", "live_velocity"],
            "fan": ["speed"],
            "heater_bed": ["temperature", "target"],
            "extruder": ["temperature", "target"],
            "heater_generic heater_bed_outer": ["temperature", "target"],
            "display_status": ["progress"],
            "print_stats": ["state", "print_duration", "filename", "total_duration"],
            "output_pin Part_Light": ["value"],
            "output_pin Frame_Light": ["value"],
            "configfile": ["config"],
            "filament_switch_sensor fila": ["enabled"]
        }})
        data = ret["result"]["status"]
        logger.info("Printer Model: " + str(self.printer_model))
        self.initialize_display()
        self.handle_status_update(data)

    async def _send_moonraker_request(
        self, method, params={}):
        message = self._make_rpc_msg(method, **params)
        fut = self._loop.create_future()
        self.pending_reqs[message["id"]] = fut
        data = json.dumps(message).encode() + b"\x03"
        try:
            self.writer.write(data)
            await self.writer.drain()
        except asyncio.CancelledError:
            raise
        except Exception:
            await self.close()
        return await fut

    def _find_ips(self, network):
        ips = []
        for key in network:
            if "ip_addresses" in network[key]:
                for ip in network[key]["ip_addresses"]:
                    if ip["family"] == "ipv4":
                        ips.append(ip["address"])
        return ips

    async def _connect(self) -> None:
        sockfile = "/home/mks/printer_data/comms/moonraker.sock"
        sockpath = pathlib.Path(sockfile).expanduser().resolve()
        logger.info(f"Connecting to Moonraker at {sockpath}")
        while True:
            try:
                reader, writer = await asyncio.open_unix_connection(
                    sockpath, limit=SOCKET_LIMIT
                )
            except asyncio.CancelledError:
                raise
            except Exception:
                await asyncio.sleep(1.)
                continue
            break
        self.writer = writer
        self._loop.create_task(self._process_stream(reader))
        asyncio.create_task(self.monitor_log())
        self.connected = True
        logger.info("Connected to Moonraker")
        ret = await self._send_moonraker_request("server.connection.identify", {
                "client_name": "OpenNept4une Display Connector",
                "version": "0.0.1",
                "type": "other",
                "url": "https://github.com/halfbearman/opennept4une"
            })
        logger.debug(f"Client Identified With Moonraker: {ret}")

        system = (await self._send_moonraker_request("machine.system_info"))["result"]["system_info"]
        self.ips = ", ".join(self._find_ips(system["network"]))
        self._write("p[35].b[16].txt=\"" + self.ips + "\"")
        self._write("p[127].b[20].txt=\"" + self.ips + "\"")
        software_version = (await self._send_moonraker_request("printer.info"))["result"]["software_version"]
        self._write("p[35].b[10].txt=\"" + software_version.split("-")[0] + "\"")

    def _make_rpc_msg(self, method: str, **kwargs):
        msg = {"jsonrpc": "2.0", "method": method}
        uid = id(msg)
        msg["id"] = uid
        self.pending_req = msg
        if kwargs:
            msg["params"] = kwargs
        return msg

    def generate_key(self, readData):
        return ''.join(readData)

    def match_key(self, pattern, key):
        return re.match(pattern.replace('??', '..'), key) is not None

    def handle_response(self, readData):
        action_key = self.generate_key(readData)
        for key in response_actions.keys():
            if self.match_key(key, action_key):
                self.execute_action(response_actions[key])
                break
        else:
            for key in response_errors.keys():
                if self.match_key(key, action_key):
                    logger.error(response_errors[key])
                    return
            logger.debug("No action for response: " + readData)

    async def _process_serial(self, reader):
        while True:
            data = await reader.readuntil(self.serial_padding)
            message = data.rstrip().hex()
            logger.debug(f"=> {message}")
            self.handle_response(message)

    async def _process_stream(
        self, reader: asyncio.StreamReader
    ) -> None:
        errors_remaining: int = 10
        while not reader.at_eof():
            if self.klipper_restart_event.is_set():
                await self._attempt_reconnect()
                self.klipper_restart_event.clear()
            try:
                data = await reader.readuntil(b'\x03')
                decoded = data[:-1].decode(encoding="utf-8")
                item = json.loads(decoded)
            except (ConnectionError, asyncio.IncompleteReadError):
                await self._attempt_reconnect()
                break
            except asyncio.CancelledError:
                raise
            except Exception:
                errors_remaining -= 1
                if not errors_remaining or not self.connected:
                    await self._attempt_reconnect()
                continue
            errors_remaining = 10
            if "id" in item:
                fut = self.pending_reqs.pop(item["id"], None)
                if fut is not None:
                    fut.set_result(item)
            elif item["method"] == "notify_status_update":
                self.handle_status_update(item["params"][0])
        logger.info("Unix Socket Disconnection from _process_stream()")
        await self.close()

    def handle_config_change(self, new_data):
        max_x, max_y, max_z = 0, 0, 0
        if "config" in new_data:
            if "stepper_x" in new_data["config"]:
                if "position_max" in new_data["config"]["stepper_x"]:
                    max_x = int(new_data["config"]["stepper_x"]["position_max"])
            if "stepper_y" in new_data["config"]:
                if "position_max" in new_data["config"]["stepper_x"]:
                    max_y = int(new_data["config"]["stepper_y"]["position_max"])
            if "stepper_z" in new_data["config"]:
                if "position_max" in new_data["config"]["stepper_x"]:
                    max_z = int(new_data["config"]["stepper_z"]["position_max"])

            if max_x > 0 and max_y > 0 and max_z > 0:
                self._write(f'p[35].b[9].txt="{max_x}x{max_y}x{max_z}"')

    async def _attempt_reconnect(self):
        logger.info("Attempting to reconnect to Moonraker...")
        await asyncio.sleep(20)  # A delay before attempting to reconnect
        self.start_listening()

    def _get_current_page(self):
        if len(self.history) > 0:
            return self.history[-1]
        return None

    async def load_thumbnail_for_page(self, filename, page_number):
        logger.info("Loading new GCode for " + filename)
        gcode = requests.get(f"http://127.0.0.1/server/files/gcodes/{requests.utils.quote(filename)}").text
        lines = gcode.splitlines()
        logger.debug("GCode Lines: " + str(len(lines)))
        if len(lines) < 100:
            logger.error("GCode too short to parse")
            logger.debug(gcode)
            return
        for line in lines:
            if line.startswith(";gimage:"):
                logger.info("Found thumbnail in GCode")
                image = line[8:]

                parts = []
                start = 0
                end = 1024
                while (start + 1024 < len(image)):
                    parts.append(image[start:end])
                    start = start + 1024
                    end = end + 1024

                parts.append(image[start:len(image)])
                self.is_blocking_serial = True
                self._write("p[" + str(page_number) + "].vis cp0,1", True)
                self._write("p[" + str(page_number) + "].cp0.close()", True)
                for part in parts:
                    self._write("p[" + str(page_number) + "].cp0.write(\"" + str(part) + "\")", True)
                self.is_blocking_serial = False
                return

    def handle_status_update(self, new_data, data_mapping=DATA_MAPPING):
        if "print_stats" in new_data:
            if "filename" in new_data["print_stats"]:
                filename = new_data["print_stats"]["filename"]
                if filename != self.current_filename:
                    self.current_filename = filename
                    if filename is not None and filename != "":
                        self._loop.create_task(self.load_thumbnail_for_page(self.current_filename, "19"))
            if "state" in new_data["print_stats"]:
                state = new_data["print_stats"]["state"]
                self.current_state = state
                logger.info(f"Status Update: {state}")
                current_page = self._get_current_page()
                if state == "printing" or state == "paused":
                    if state == "printing":
                        self._write(f'p[19].b[44]].pic=68')
                    elif state == "paused":
                        self._write(f'p[19].b[44]].pic=69')
                    if current_page == None or current_page not in PRINTING_PAGES:
                        self._navigate_to_page(f'page 19')
                elif state == "complete":
                    if current_page == None or current_page != "page 24":
                        self._navigate_to_page(f'page 24')
                else:
                    if current_page == None or current_page in PRINTING_PAGES or current_page == "page 24":
                        self._navigate_to_page(f'page 1')

            if "display_status" in new_data and "progress" in new_data["display_status"] and "print_duration" in new_data["print_stats"]:
                if new_data["display_status"]["progress"] > 0:
                    total_time = new_data["print_stats"]["print_duration"] / new_data["display_status"]["progress"]
                    self._write(f'p[19].b[37].txt="{format_time(total_time - new_data["print_stats"]["print_duration"])}"')

        if "output_pin Part_Light" in new_data:
            self.part_light_state = int(new_data["output_pin Part_Light"]["value"]) == 1
        if "output_pin Frame_Light" in new_data:
            self.part_light_state = int(new_data["output_pin Frame_Light"]["value"]) == 1
        if "fan" in new_data:
            self.fan_state = float(new_data["fan"]["speed"]) > 0
            self.printing_target_speeds["fan"] = float(new_data["fan"]["speed"])
            self.update_printing_speed_settings_ui()
        if "filament_switch_sensor fila" in new_data:
            self.filament_sensor_state = int(new_data["filament_switch_sensor fila"]["enabled"]) == 1
        if "configfile" in new_data:
            self.handle_config_change(new_data["configfile"])

        if "extruder" in new_data:
            if "target" in new_data["extruder"]:
                self.printing_target_temps["extruder"] = new_data["extruder"]["target"]
        if "heater_generic heater_bed" in new_data:
            if "target" in new_data["heater_bed"]:
                self.printing_target_temps["heater_bed"] = new_data["heater_generic heater_bed"]["target"]
        if "heater_generic heater_bed_outer" in new_data:
            if "target" in new_data["heater_generic heater_bed_outer"]:
                self.printing_target_temps["heater_bed_outer"] = new_data["heater_generic heater_bed_outer"]["target"]

        if "gcode_move" in new_data:
            if "extrude_factor" in new_data["gcode_move"]:
                self.printing_target_speeds["flow"] = float(new_data["gcode_move"]["extrude_factor"])
                self.update_printing_speed_settings_ui()
            if "speed_factor" in new_data["gcode_move"]:
                self.printing_target_speeds["print"] = float(new_data["gcode_move"]["speed_factor"])
                self.update_printing_speed_settings_ui()

        is_dict = isinstance(new_data, dict)
        for key in new_data if is_dict else range(len(new_data)):
            if key in data_mapping:
                value = new_data[key]
                mapping_value = data_mapping[key]
                if isinstance(mapping_value, dict):
                    self.handle_status_update(value, mapping_value)
                elif isinstance(mapping_value, list):
                    for mapping_leaf in mapping_value:
                        for mapped_key in mapping_leaf.fields:
                            if mapping_leaf.field_type == "txt":
                                self._write(f'{mapped_key}.{mapping_leaf.field_type}="{mapping_leaf.format(value)}"')
                            else:
                                self._write(f'{mapped_key}.{mapping_leaf.field_type}={mapping_leaf.format(value)}')

    async def close(self):
        if not self.connected:
            return
        self.connected = False
        self.writer.close()
        await self.writer.wait_closed()


try:
    ch_log = logging.StreamHandler(sys.stdout)
    ch_log.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    ch_log.setFormatter(formatter)
    logger.addHandler(ch_log)
    file_log = logging.FileHandler(log_file)
    file_log.setLevel(logging.ERROR)
    file_log.setFormatter(formatter)
    logger.addHandler(file_log)
    logger.setLevel(logging.DEBUG)

    loop = asyncio.get_event_loop()
    controller = DisplayController()
    controller._loop = loop
    loop.call_later(1, controller.start_listening)
    loop.run_forever()
except Exception as e:
    logger.error("Error communicating...: " + str(e))
    logger.error(traceback.format_exc())
