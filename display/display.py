import configparser
import json
import sys
import logging
import pathlib
import requests
import re
import os, os.path
import io
import asyncio
import traceback
from PIL import Image
from tjc import TJCClient, EventType
from urllib.request import pathname2url
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler
from math import ceil, floor

from response_actions import response_actions, input_actions, custom_touch_actions
from lib_col_pic import parse_thumbnail
from elegoo_neptune4 import *
from mapping import *
from colors import *

log_file = os.path.expanduser("~/printer_data/logs/display_connector.log")
logger = logging.getLogger(__name__)
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

config_file = os.path.expanduser("~/printer_data/config/display_connector.cfg")
comms_directory = os.path.expanduser("~/printer_data/comms")

TEMP_DEFAULTS = {
    "pla": [210, 60],
    "abs": [240, 110],
    "petg": [240, 80],
    "tpu": [240, 60]
}

PRINTING_PAGES = [
    PAGE_PRINTING,
    PAGE_PRINTING_FILAMENT,
    PAGE_PRINTING_PAUSE,
    PAGE_PRINTING_STOP,
    PAGE_PRINTING_EMERGENCY_STOP,
    PAGE_PRINTING_FILAMENT,
    PAGE_PRINTING_SPEED,
    PAGE_PRINTING_ADJUST,
]

TABBED_PAGES = [
    PAGE_PREPARE_EXTRUDER,
    PAGE_PREPARE_MOVE,
    PAGE_PREPARE_TEMP,
    PAGE_PRINTING_ADJUST,
    PAGE_PRINTING_FILAMENT,
    PAGE_PRINTING_SPEED
]

TRANSITION_PAGES = [
    PAGE_OVERLAY_LOADING
]

SUPPORTED_PRINTERS = [
    MODEL_N4_REGULAR,
    MODEL_N4_PRO,
    MODEL_N4_PLUS,
    MODEL_N4_MAX
]

SOCKET_LIMIT = 20 * 1024 * 1024
class DisplayController:
    last_config_change = 0

    def __init__(self, config):
        self.config = config
        self.display_name_override = None
        self.display_name_line_color = None
        self.z_display = "mm"
        self._handle_config()
        self.connected = False


        self.display = Neptune4DisplayCommunicator(logger, self.get_printer_model_from_file(), event_handler=self.display_event_handler)
        self.display.mapper.set_z_display(self.z_display)

        self.part_light_state = False
        self.frame_light_state = False
        self.fan_state = False
        self.filament_sensor_state = False

        self.is_blocking_serial = False
        self.move_distance = '1'
        self.xy_move_speed = 130
        self.z_move_speed = 10
        self.z_offset_distance = '0.01'
        self.out_fd = sys.stdout.fileno()
        os.set_blocking(self.out_fd, False)
        self.pending_req = {}
        self.pending_reqs = {}
        self.history = []
        self.current_state = "booting"

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

        self.extrude_amount = 50
        self.extrude_speed = 5

        self.temperature_preset_material = "pla"
        self.temperature_preset_step = 10
        self.temperature_preset_extruder = 0
        self.temperature_preset_bed = 0

        self.ips = "--"

        self.leveling_mode = None
        self.screw_probe_count = 0
        self.screw_levels = {}
        self.z_probe_step = "0.1"
        self.z_probe_distance = "0.0"

        self.current_filename = None

        self.full_bed_leveling_counts = [0, 0]
        self.bed_leveling_counts = [0, 0]
        self.bed_leveling_probed_count = 0
        self.bed_leveling_box_size = 0
        self.bed_leveling_last_position = None

        self.klipper_restart_event = asyncio.Event()

    def handle_config_change(self):
        if self.last_config_change + 5 > time.time():
            return
        self.last_config_change = time.time()
        logger.info("Config file changed, Reloading")
        self._navigate_to_page(PAGE_OVERLAY_LOADING)
        self.config.read(config_file)
        self._handle_config()
        self._go_back()

    def _handle_config(self):
        logger.info("Loading config")

        if "LOGGING" in self.config:
            if "file_log_level" in  self.config["LOGGING"]:
                file_log.setLevel( self.config["LOGGING"]["file_log_level"])
                logger.setLevel(logging.DEBUG)

        if "main_screen" in self.config:
            if "display_name" in self.config["main_screen"]:
                self.display_name_override = self.config["main_screen"]["display_name"]
            if "display_name_line_color" in self.config["main_screen"]:
                self.display_name_line_color = self.config["main_screen"]["display_name_line_color"]

        if "print_screen" in self.config:
            if "z_display" in self.config["print_screen"]:
                self.z_display = self.config["print_screen"]["z_display"]

        if "prepare" in self.config:
            prepare = self.config["prepare"]
            if "move_distance" in prepare:
                distance = prepare["move_distance"]
                if distance in ["0.1", "1", "10"]:
                    self.move_distance = distance
            self.xy_move_speed = prepare.getint("xy_move_speed", fallback=130)
            self.z_move_speed = prepare.getint("z_move_speed", fallback=10)
            self.extrude_amount = prepare.getint("extrude_amount", fallback=50)
            self.extrude_speed = prepare.getint("extrude_speed", fallback=5)

    def get_printer_model_from_file(self):
        try:
            with open('/boot/.OpenNept4une.txt', 'r') as file:
                for line in file:
                    if line.startswith(tuple(SUPPORTED_PRINTERS)):
                        model_part = line.split('-')[0].strip()
                        logger.info(f"Extracted Model: {model_part}")
                        return model_part
        except FileNotFoundError:
            logger.error("File not found")
        except Exception as e:
            logger.error(f"Error reading file: {e}")
        return None

    def get_device_name(self):
        model_map = {
            MODEL_N4_REGULAR: "Neptune 4",
            MODEL_N4_PRO: "Neptune 4 Pro",
            MODEL_N4_PLUS: "Neptune 4 Plus",
            MODEL_N4_MAX: "Neptune 4 Max",
        }
        return model_map[self.display.model]

    def initialize_display(self):
        self._write("sendxy=1")
        model_image_key = None
        if self.display.model == MODEL_N4_REGULAR:
            model_image_key = "213"
        elif self.display.model == MODEL_N4_PRO:
            model_image_key = "214"
            self._write(f'p[{self._page_id(PAGE_MAIN)}].disp_q5.val=1') # N4Pro Outer Bed Symbol (Bottom Rig>
        elif self.display.model == MODEL_N4_PLUS:
            model_image_key = "313"
        elif self.display.model == MODEL_N4_MAX:
            model_image_key = "314"

        if self.display_name_override is None:
            self._write(f'p[{self._page_id(PAGE_MAIN)}].q4.picc={model_image_key}')
        else:
            self._write(f'p[{self._page_id(PAGE_MAIN)}].q4.picc=137')

        self._write(f'p[{self._page_id(PAGE_SETTINGS_ABOUT)}].b[8].txt="{self.get_device_name()}"')

    async def send_gcodes_async(self, gcodes):
        for gcode in gcodes:
            logger.debug("Sending GCODE: " + gcode)
            await self._send_moonraker_request("printer.gcode.script", {"script": gcode})
            await asyncio.sleep(0.1)

    def send_gcode(self, gcode):
        logger.debug("Sending GCODE: " + gcode)
        self._loop.create_task(self._send_moonraker_request("printer.gcode.script", {"script": gcode}))

    def move_axis(self, axis, distance):
        speed = self.xy_move_speed if axis in ["X", "Y"] else self.z_move_speed
        self.send_gcode(f'G91\nG1 {axis}{distance} F{int(speed) * 60}\nG90')

    async def special_page_handling(self):
        current_page = self._get_current_page()
        if current_page == PAGE_MAIN:
            if self.display_name_override:
                display_name = self.display_name_override
                if display_name == "MODEL_NAME":
                    display_name = self.get_device_name()
                self._write('xstr 12,20,280,20,1,65535,' + str(BACKGROUND_GRAY) + ',0,1,1,"' + display_name + '"')
            if self.display_name_line_color:
                self._write('fill 13,47,24,4,' + str(self.display_name_line_color))

            if self.display.model == MODEL_N4_PRO:
                self._write(f'vis out_bedtemp,1')
        elif current_page == PAGE_FILES:
            self.show_files_page()
        elif current_page == PAGE_PREPARE_MOVE:
            self.update_prepare_move_ui()
        elif current_page == PAGE_PREPARE_EXTRUDER:
            self.update_prepare_extrude_ui()
        elif current_page == PAGE_SETTINGS_TEMPERATURE_SET:
            self.update_preset_temp_ui()
        elif current_page == PAGE_SETTINGS_ABOUT:
            self._write('fill 0,400,320,60,' + str(BACKGROUND_GRAY))
            self._write('xstr 0,400,320,30,1,65535,' + str(BACKGROUND_GRAY) + ',1,1,1,"OpenNept4une"')
            self._write('xstr 0,430,320,30,2,GRAY,' + str(BACKGROUND_GRAY) + ',1,1,1,"github.com/halfmanbear/OpenNept4une"')
        elif current_page == PAGE_PRINTING:
            self._write("printvalue.xcen=0")
            self._write("move printvalue,13,267,13,267,0,10")
            self._write("vis b[16],0")
        elif current_page == PAGE_PRINTING_FILAMENT:
            self.update_printing_heater_settings_ui()
            self.update_printing_temperature_increment_ui()
        elif current_page == PAGE_PRINTING_ADJUST:
            self.update_printing_zoffset_increment_ui()
            self._write("b[20].txt=\"" + self.ips + "\"")
        elif current_page == PAGE_PRINTING_SPEED:
            self.update_printing_speed_settings_ui()
            self.update_printing_speed_increment_ui()
        elif current_page == PAGE_LEVELING:
            self._write("b[12].txt=\"Leveling\"")
            self._write("b[18].txt=\"Screws Tilt Adjust\"")
            self._write("b[19].txt=\"Z-Probe Offset\"")
            self.leveling_mode = None
        elif current_page == PAGE_LEVELING_SCREW_ADJUST:
            self.draw_initial_screw_leveling()
            self._loop.create_task(self.handle_screw_leveling())
        elif current_page == PAGE_LEVELING_Z_OFFSET_ADJUST:
            self.draw_initial_zprobe_leveling()
            self._loop.create_task(self.handle_zprobe_leveling())
        elif current_page == PAGE_PRINTING_KAMP:
            self.draw_kamp_page()
        elif current_page == PAGE_PRINTING_DIALOG_SPEED:
            self._write("b[3].maxval=200")
        elif current_page == PAGE_PRINTING_DIALOG_FLOW:
            self._write("b[3].maxval=200")

    def _navigate_to_page(self, page):
        if len(self.history) == 0 or self.history[-1] != page:
            if page in TABBED_PAGES and self.history[-1] in TABBED_PAGES:
                self.history[-1] = page
            else:
                self.history.append(page)
            self._write(f"page {self.display.mapper.map_page(page)}")
            logger.debug(f"Navigating page {page}")
            self._loop.create_task(self.special_page_handling())

    def execute_action(self, action):
        if action.startswith("move_"):
            parts = action.split('_')
            axis = parts[1].upper()
            direction = parts[2]
            self.move_axis(axis, direction + self.move_distance)
        elif action.startswith("set_distance_"):
            parts = action.split('_')
            self.move_distance = parts[2]
            self.update_prepare_move_ui()
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
            self._navigate_to_page(action.split(' ')[1])
        elif action == "emergency_stop":
            logger.info("Executing emergency stop!")
            self._loop.create_task(self._send_moonraker_request("printer.emergency_stop"))
        elif action == "pause_print_button":
            if self.current_state == "paused":
                logger.info("Resuming print")
                self._loop.create_task(self._send_moonraker_request("printer.print.resume"))
            else:
                self._go_back()
                self._navigate_to_page(PAGE_PRINTING_PAUSE)
        elif action == "pause_print_confirm":
            self._go_back()
            logger.info("Pausing print")
        elif action == "resume_print":
            self._go_back()
            self._loop.create_task(self._send_moonraker_request("printer.print.pause"))
        elif action == "stop_print":
            self._go_back()
            self._navigate_to_page(PAGE_OVERLAY_LOADING)
            logger.info("Stopping print")
            self._loop.create_task(self._send_moonraker_request("printer.print.cancel"))
        elif action == "files_picker":
            self._navigate_to_page(PAGE_FILES)
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
                self._navigate_to_page(PAGE_CONFIRM_PRINT)
                self._write(f'p[{self._page_id(PAGE_CONFIRM_PRINT)}].b[2].txt="{self.current_filename.replace(".gcode", "").split("/")[-1]}"')
                self._loop.create_task(self.load_thumbnail_for_page(self.current_filename, "18"))
        elif action == "print_opened_file":
            self._go_back()
            self._navigate_to_page(PAGE_OVERLAY_LOADING)
            self._loop.create_task(self._send_moonraker_request("printer.print.start", {"filename": self.current_filename}))
        elif action == "confirm_complete":
            logger.info("Clearing SD Card")
            self.send_gcode("SDCARD_RESET_FILE")
        elif action.startswith("set_temp"):
            parts = action.split('_')
            target = parts[-1]
            heater = "_".join(parts[2:-1])
            self.send_gcode(f"SET_HEATER_TEMPERATURE HEATER=" + heater + " TARGET=" + target)
        elif action.startswith("set_preset_temp"):
            parts = action.split('_')
            material = parts[3].lower()

            if "temperatures." + material in self.config:
                extruder = self.config["temperatures." + material]["extruder"]
                heater_bed = self.config["temperatures." + material]["heater_bed"]
            else:
                extruder = TEMP_DEFAULTS[material][0]
                heater_bed = TEMP_DEFAULTS[material][1]
            gcodes = [
                f"SET_HEATER_TEMPERATURE HEATER=extruder TARGET={extruder}",
                f"SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET={heater_bed}"
            ]
            if self.display.model == MODEL_N4_PRO:
                gcodes.append(f"SET_HEATER_TEMPERATURE HEATER=heater_bed_outer TARGET={heater_bed}")
            self._loop.create_task(self.send_gcodes_async(gcodes))
        elif action.startswith("set_extrude_amount"):
            self.extrude_amount = int(action.split('_')[3])
            self.update_prepare_extrude_ui()
        elif action.startswith("set_extrude_speed"):
            self.extrude_speed = int(action.split('_')[3])
            self.update_prepare_extrude_ui()
        elif action.startswith("extrude_"):
            parts = action.split('_')
            direction = parts[1]
            self.send_gcode(f"M83\nG1 E{direction}{self.extrude_amount} F{self.extrude_speed * 60}")
        elif action.startswith("start_temp_preset_"):
            material = action.split('_')[3]
            self.temperature_preset_material = material
            if "temperatures." + material in self.config:
                self.temperature_preset_extruder = int(self.config["temperatures." + material]["extruder"])
                self.temperature_preset_bed = int(self.config["temperatures." + material]["heater_bed"])
            else:
                self.temperature_preset_extruder = TEMP_DEFAULTS[material][0]
                self.temperature_preset_bed = TEMP_DEFAULTS[material][1]
            self._navigate_to_page(PAGE_SETTINGS_TEMPERATURE_SET)
        elif action.startswith("preset_temp_step_"):
            size = int(action.split('_')[3])
            self.temperature_preset_step = size
        elif action.startswith("preset_temp_"):
            parts = action.split('_')
            heater = parts[2]
            change = self.temperature_preset_step if parts[3] == "up" else -self.temperature_preset_step
            if heater == "extruder":
                self.temperature_preset_extruder += change
            else:
                self.temperature_preset_bed += change
            self.update_preset_temp_ui()
        elif action == "save_temp_preset":
            logger.info("Saving temp preset")
            self.save_temp_preset()
        elif action == "retry_screw_leveling":
            self.draw_initial_screw_leveling()
            self._loop.create_task(self.handle_screw_leveling())
        elif action.startswith("zprobe_step_"):
            parts = action.split('_')
            self.z_probe_step = parts[2]
            self.update_zprobe_leveling_ui()
        elif action.startswith("zprobe_"):
            parts = action.split('_')
            direction = parts[1]
            self.send_gcode(f"TESTZ Z={direction}{self.z_probe_step}")
        elif action == "abort_zprobe":
            self.send_gcode("ABORT")
            self._go_back()
        elif action == "save_zprobe":
            self.send_gcode("ACCEPT")
            self.send_gcode("SAVE_CONFIG")
            self._go_back()
        elif action.startswith("set_speed_"):
            parts = action.split('_')
            speed = int(parts[2])
            self.send_speed_update("print", speed)
        elif action.startswith("set_flow_"):
            parts = action.split('_')
            speed = int(parts[2])
            self.send_speed_update("flow", speed)

    def _write(self, data, forced = False):
        if self.is_blocking_serial and not forced:
            return
        self._loop.create_task(self.display.write(data))

    def _set_light(self, light_name, new_state):
        gcode = f"{light_name}_{'ON' if new_state else 'OFF'}"
        self.send_gcode(gcode)

    def _toggle_filament_sensor(self, state):
        gcode = f"SET_FILAMENT_SENSOR SENSOR=fila ENABLE={'1' if state else '0'}"
        self.send_gcode(gcode)

    def save_temp_preset(self):
        if "temperatures." + self.temperature_preset_material not in self.config:
            self.config["temperatures." + self.temperature_preset_material] = {}
        self.config.set("temperatures." + self.temperature_preset_material, "extruder", str(self.temperature_preset_extruder))
        self.config.set("temperatures." + self.temperature_preset_material, "heater_bed", str(self.temperature_preset_bed))
        with open(config_file, 'w') as configfile:
            self.config.write(configfile)
        self._go_back()

    def update_printing_heater_settings_ui(self):
        if self.display.model == MODEL_N4_PRO:
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].b0.picc=' + str(90 if self.printing_selected_heater == "extruder" else 89))
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].b1.picc=' + str(90 if self.printing_selected_heater == "heater_bed" else 89))
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].b2.picc=' + str(90 if self.printing_selected_heater == "heater_bed_outer" else 89))
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].targettemp.val=' + str(self.printing_target_temps[self.printing_selected_heater]))

        else:
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].b[13].pic={54 + ["extruder", "heater_bed"].index(self.printing_selected_heater)}')
            self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].b[35].txt="' + str(self.printing_target_temps[self.printing_selected_heater]) + '"')


    def update_printing_temperature_increment_ui(self):
        self._write(f'p[{self._page_id(PAGE_PRINTING_FILAMENT)}].p1.pic={56 + ["1", "5", "10"].index(self.printing_selected_temp_increment)}')

    def update_printing_speed_settings_ui(self):
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b0.picc=' + str(59 if self.printing_selected_speed_type == "print" else 58))
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b1.picc=' + str(59 if self.printing_selected_speed_type == "flow" else 58))
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b2.picc=' + str(59 if self.printing_selected_speed_type == "fan" else 58))
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].targetspeed.val={self.printing_target_speeds[self.printing_selected_speed_type]*100:.0f}')

    def update_printing_speed_increment_ui(self):
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b[14].picc=' + str(59 if self.printing_selected_speed_increment == "1" else 58))
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b[15].picc=' + str(59 if self.printing_selected_speed_increment == "5" else 58))
        self._write(f'p[{self._page_id(PAGE_PRINTING_SPEED)}].b[16].picc=' + str(59 if self.printing_selected_speed_increment == "10" else 58))

    def update_printing_zoffset_increment_ui(self):
        self._write(f'p[{self._page_id(PAGE_PRINTING_ADJUST)}].b[23].picc=' + str(36 if self.z_offset_distance == "0.01" else 65))
        self._write(f'p[{self._page_id(PAGE_PRINTING_ADJUST)}].b[24].picc=' + str(36 if self.z_offset_distance == "0.1" else 65))
        self._write(f'p[{self._page_id(PAGE_PRINTING_ADJUST)}].b[25].picc=' + str(36 if self.z_offset_distance == "1" else 65))

    def update_preset_temp_ui(self):
        self._write(f'p[{self._page_id(PAGE_SETTINGS_TEMPERATURE_SET)}].b[7].pic={56 + [1, 5, 10].index(self.temperature_preset_step)}')
        self._write(f'p[{self._page_id(PAGE_SETTINGS_TEMPERATURE_SET)}].b[18].txt="{self.temperature_preset_extruder}"')
        self._write(f'p[{self._page_id(PAGE_SETTINGS_TEMPERATURE_SET)}].b[19].txt="{self.temperature_preset_bed}"')

    def update_prepare_move_ui(self):
        self._write(f'p[{self._page_id(PAGE_PREPARE_MOVE)}].p0.pic={10 + ["0.1", "1", "10"].index(self.move_distance)}')

    def update_prepare_extrude_ui(self):
        self._write(f'p[{self._page_id(PAGE_PREPARE_EXTRUDER)}].b[8].txt="{self.extrude_amount}"')
        self._write(f'p[{self._page_id(PAGE_PREPARE_EXTRUDER)}].b[9].txt="{self.extrude_speed}"')

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

    def sort_dir_contents(self, dir_contents):
        key = 'modified'
        reverse = True
        if 'files' in self.config:
            files_config = self.config['files']
            if 'sort_by' in files_config:
                key = files_config['sort_by']
            if 'sort_order' in files_config:
                reverse = files_config['sort_order'] == 'desc'
        return sorted(dir_contents, key=lambda k: k[key], reverse=reverse)

    async def _load_files(self):
        data = (await self._send_moonraker_request("server.files.get_directory", {"path": "/".join(["gcodes", self.current_dir])}))
        dir_info = data["result"]
        self.dir_contents = []
        dirs = []
        for item in dir_info["dirs"]:
            if not item["dirname"].startswith("."):
                dirs.append({
                    "type": "dir",
                    "path": self._build_path(self.current_dir, item["dirname"]),
                    "size": item["size"],
                    "modified": item["modified"],
                    "name": item["dirname"]
                })
        files = []
        for item in dir_info["files"]:
            if item["filename"].endswith(".gcode"):
                files.append({
                    "type": "file",
                    "path": self._build_path(self.current_dir, item["filename"]),
                    "size": item["size"],
                    "modified": item["modified"],
                    "name": item["filename"]
                })
        sort_folders_first = True
        if "files" in self.config:
            sort_folders_first = self.config["files"].getboolean("sort_folders_first", fallback=True)
        if sort_folders_first:
            self.dir_contents = self.sort_dir_contents(dirs) + self.sort_dir_contents(files)
        else:
            self.dir_contents = self.sort_dir_contents(dirs + files)
        self.show_files_page()

    def _page_id(self, page):
        return self.display.mapper.map_page(page)

    def show_files_page(self):
        page_size = 5
        title = self.current_dir.split("/")[-1]
        if title == "":
            title = "Files"
        file_count = len(self.dir_contents)
        if file_count == 0:
                self._write(f'p[{self._page_id(PAGE_FILES)}].b[11].txt="{title} (Empty)"')
        else:
            self._write(f'p[{self._page_id(PAGE_FILES)}].b[11].txt="{title} ({(self.files_page * page_size) + 1}-{min((self.files_page * page_size) + page_size, file_count)}/{file_count})"')
        component_index = 0
        for index in range(self.files_page * page_size, min(len(self.dir_contents), (self.files_page + 1) * page_size)):
            file = self.dir_contents[index]
            self._write(f'p[{self._page_id(PAGE_FILES)}].b[{component_index + 18}].txt="{file["name"].replace(".gcode", "")}"')
            if file["type"] == "dir":
                self._write(f'p[{self._page_id(PAGE_FILES)}].b[{component_index + 13}].pic=194')
            else:
                self._write(f'p[{self._page_id(PAGE_FILES)}].b[{component_index + 13}].pic=193')
            component_index += 1
        for index in range(component_index, page_size):
            self._write(f'p[{self._page_id(PAGE_FILES)}].b[{index + 13}].pic=195')
            self._write(f'p[{self._page_id(PAGE_FILES)}].b[{index + 18}].txt=""')

    def _go_back(self):
        if len(self.history) > 1:
            if self._get_current_page() == PAGE_FILES and self.current_dir != "":
                self.current_dir = "/".join(self.current_dir.split("/")[:-1])
                self.files_page = 0
                self._loop.create_task(self._load_files())
                return
            self.history.pop()
            while len(self.history) > 1 and self.history[-1] in TRANSITION_PAGES:
                self.history.pop()
            back_page = self.history[-1]
            self._write(f"page {self.display.mapper.map_page(back_page)}")
            logger.debug(f"Navigating back to {back_page}")
            self._loop.create_task(self.special_page_handling())
        else:
            logger.debug("Already at the main page.")

    def start_listening(self):
        self._loop.create_task(self.listen())

    async def listen(self):
        await self.display.connect()
        await self.display.check_valid_version()
        await self.connect_moonraker()
        ret = await self._send_moonraker_request("printer.objects.subscribe", {"objects": {
            "gcode_move": ["extrude_factor", "speed_factor", "homing_origin"],
            "motion_report": ["live_position", "live_velocity"],
            "fan": ["speed"],
            "heater_bed": ["temperature", "target"],
            "extruder": ["temperature", "target"],
            "heater_generic heater_bed_outer": ["temperature", "target"],
            "display_status": ["progress"],
            "print_stats": ["state", "print_duration", "filename", "total_duration", "info"],
            "output_pin Part_Light": ["value"],
            "output_pin Frame_Light": ["value"],
            "configfile": ["config"],
            "filament_switch_sensor fila": ["enabled"]
        }})
        data = ret["result"]["status"]
        logger.info("Printer Model: " + str(self.get_device_name()))
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

    async def connect_moonraker(self) -> None:
        sockfile = os.path.expanduser("~/printer_data/comms/moonraker.sock")
        sockpath = pathlib.Path(sockfile).expanduser().resolve()
        logger.info(f"Connecting to Moonraker at {sockpath}")
        while True:
            try:
                reader, writer = await asyncio.open_unix_connection(sockpath, limit=SOCKET_LIMIT)
                self.writer = writer
                self._loop.create_task(self._process_stream(reader))
                self.connected = True
                logger.info("Connected to Moonraker")

                try:
                    software_version_response = await self._send_moonraker_request("printer.info")
                    software_version = software_version_response["result"]["software_version"]
                    software_version = "-".join(software_version.split("-")[:2]) # clean up version string
                    # Process the software_version...
                    logger.info(f"Software Version: {software_version}")
                    self._write("p[" + self._page_id(PAGE_SETTINGS_ABOUT) + "].b[10].txt=\"" + software_version + "\"")
                    break

                except KeyError:
                    logger.error("KeyError encountered in software_version_response. Attempting to reconnect.")
                    await asyncio.sleep(5)  # Wait before reconnecting
                    continue  # Retry the connection loop

            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"Error connecting to Moonraker: {e}")
                await asyncio.sleep(5)  # Wait before reconnecting
                continue

        ret = await self._send_moonraker_request("server.connection.identify", {
                "client_name": "OpenNept4une Display Connector",
                "version": "0.0.1",
                "type": "other",
                "url": "https://github.com/halfbearman/opennept4une"
            })
        logger.debug(f"Client Identified With Moonraker: {ret['result']['connection_id']}")

        system = (await self._send_moonraker_request("machine.system_info"))["result"]["system_info"]
        self.ips = ", ".join(self._find_ips(system["network"]))
        self._write("p[" + self._page_id(PAGE_SETTINGS_ABOUT) +"].b[16].txt=\"" + self.ips + "\"")

    def _make_rpc_msg(self, method: str, **kwargs):
        msg = {"jsonrpc": "2.0", "method": method}
        uid = id(msg)
        msg["id"] = uid
        self.pending_req = msg
        if kwargs:
            msg["params"] = kwargs
        return msg

    def handle_response(self, page, component):
        if page in response_actions:
            if component in response_actions[page]:
                self.execute_action(response_actions[page][component])
                return
        if component == 0:
            self._go_back()
            return
        logger.info(f"Unhandled Response: {page} {component}")

    def handle_input(self, page, component, value):
        if page in input_actions:
            if component in input_actions[page]:
                self.execute_action(input_actions[page][component].replace("$", str(value)))
                return
            
    def handle_custom_touch(self, x, y):
        if self._get_current_page() in custom_touch_actions:
            pass

    async def display_event_handler(self, type, data):
        if type == EventType.TOUCH:
            self.handle_response(data.page_id, data.component_id)
        elif type == EventType.TOUCH_COORDINATE:
            if data.touch_event == 0:
                self.handle_custom_touch(data.x, data.y)
        elif type == EventType.SLIDER_INPUT:
            self.handle_input(data.page_id, data.component_id, data.value)
        elif type == EventType.NUMERIC_INPUT:
            self.handle_input(data.page_id, data.component_id, data.value)
        elif type == EventType.RECONNECTED:
            logger.info("Reconnected to Display")
            self.history = []
            self.initialize_display()
            self._navigate_to_page(PAGE_MAIN)
        else:
            logger.info(f"Unhandled Event: {type} {data}")

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
            elif item["method"] == "notify_gcode_response":
                self.handle_gcode_response(item["params"][0])
        logger.info("Unix Socket Disconnection from _process_stream()")
        await self.close()

    def handle_machine_config_change(self, new_data):
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
                self._write(f'p[{self._page_id(PAGE_SETTINGS_ABOUT)}].b[9].txt="{max_x}x{max_y}x{max_z}"')
            if "bed_mesh" in new_data["config"]:
                if "probe_count" in new_data["config"]["bed_mesh"]:
                    parts = new_data["config"]["bed_mesh"]["probe_count"].split(",")
                    self.full_bed_leveling_counts = [int(parts[0]), int(parts[1])]
                    self.bed_leveling_counts = self.full_bed_leveling_counts

    async def _attempt_reconnect(self):
        logger.info("Attempting to reconnect to Moonraker...")
        await asyncio.sleep(1)  # A delay before attempting to reconnect
        self.start_listening()

    def _get_current_page(self):
        if len(self.history) > 0:
            return self.history[-1]
        return None

    async def load_thumbnail_for_page(self, filename, page_number):
        logger.info("Loading thumbnail for " + filename)
        metadata = await self._send_moonraker_request("server.files.metadata", {"filename": filename})
        best_thumbnail = None
        for thumbnail in metadata["result"]["thumbnails"]:
            if thumbnail["width"] == 160:
                best_thumbnail = thumbnail
                break
            if best_thumbnail is None or thumbnail["width"] > best_thumbnail["width"]:
                best_thumbnail = thumbnail
        if best_thumbnail is None:
            self._write("vis cp0,0", True)
            return

        path = "/".join(filename.split("/")[:-1])
        if path != "":
            path = path + "/"
        path += best_thumbnail["relative_path"]

        img = requests.get("http://localhost/server/files/gcodes/" + pathname2url(path))
        thumbnail = Image.open(io.BytesIO(img.content))
        background = "29354a"
        if "thumbnails" in self.config:
            if "background_color" in self.config["thumbnails"]:
                background = self.config["thumbnails"]["background_color"]
        image = parse_thumbnail(thumbnail, 160, 160, background)

        parts = []
        start = 0
        end = 1024
        while (start + 1024 < len(image)):
            parts.append(image[start:end])
            start = start + 1024
            end = end + 1024

        parts.append(image[start:len(image)])
        self.is_blocking_serial = True
        self._write("vis cp0,1", True)
        self._write("p[" + str(page_number) + "].cp0.close()", True)
        for part in parts:
            self._write("p[" + str(page_number) + "].cp0.write(\"" + str(part) + "\")", True)
        self.is_blocking_serial = False

    def handle_status_update(self, new_data, data_mapping=None):
        if data_mapping is None:
            data_mapping = self.display.mapper.data_mapping
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
                        self._write(f'p[{self._page_id(PAGE_PRINTING)}].b[44].pic=68')
                    elif state == "paused":
                        self._write(f'p[{self._page_id(PAGE_PRINTING)}].b[44].pic=69')
                    if current_page == None or current_page not in PRINTING_PAGES:
                        self._navigate_to_page(PAGE_PRINTING)
                elif state == "complete":
                    if current_page == None or current_page != PAGE_PRINTING_COMPLETE:
                        self._navigate_to_page(PAGE_PRINTING_COMPLETE)
                else:
                    if current_page == None or current_page in PRINTING_PAGES or current_page == PAGE_PRINTING_COMPLETE:
                        self._navigate_to_page(PAGE_MAIN)

            if "display_status" in new_data and "progress" in new_data["display_status"] and "print_duration" in new_data["print_stats"]:
                if new_data["display_status"]["progress"] > 0:
                    total_time = new_data["print_stats"]["print_duration"] / new_data["display_status"]["progress"]
                    self._write(f'p[{self._page_id(PAGE_PRINTING)}].b[37].txt="{format_time(total_time - new_data["print_stats"]["print_duration"])}"')

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
            self.handle_machine_config_change(new_data["configfile"])

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

    def draw_initial_screw_leveling(self):
        self._write("b[1].txt=\"Screws Tilt Adjust\"")
        self._write("b[2].txt=\"Please Wait...\"")
        self._write("b[3].txt=\"Heating...\"")
        self._write("vis b[4],0")
        self._write("vis b[5],0")
        self._write("vis b[6],0")
        self._write("vis b[7],0")
        self._write("vis b[8],0")
        self._write("fill 0,110,320,290,10665")

    def draw_completed_screw_leveling(self):
        self._write("b[1].txt=\"Screws Tilt Adjust\"")
        self._write("b[2].txt=\"Adjust the screws as indicated\"")
        self._write("b[3].txt=\"01:20 means 1  turn and 20 mins\\rCW=clockwise\\rCCW=counter-clockwise\"")
        self._write("vis b[4],0")
        self._write("vis b[5],0")
        self._write("vis b[6],0")
        self._write("vis b[7],0")
        self._write("vis b[8],1")
        self._write("fill 0,110,320,290,10665")
        green = 26347
        red = 10665
        self._write("xstr 12,320,100,20,1,65535,10665,1,1,1,\"front left\"")
        self.draw_screw_level_info_at("12,340,100,20", self.screw_levels["front left"], green, red)

        self._write("xstr 170,320,100,20,1,65535,10665,1,1,1,\"front right\"")
        self.draw_screw_level_info_at("170,340,100,20", self.screw_levels["front right"], green, red)

        self._write("xstr 170,120,100,20,1,65535,10665,1,1,1,\"rear right\"")
        self.draw_screw_level_info_at("170,140,100,20", self.screw_levels["rear right"], green, red)

        self._write("xstr 12,120,100,20,1,65535,10665,1,1,1,\"rear left\"")
        self.draw_screw_level_info_at("12,140,100,20", self.screw_levels["rear left"], green, red)

        if 'center right' in self.screw_levels:
            self._write("xstr 12,220,100,30,1,65535,10665,1,1,1,\"center\\rright\"")
            self.draw_screw_level_info_at("170,240,100,20", self.screw_levels["center right"], green, red)
        if 'center left' in self.screw_levels:
            self._write("xstr 12,120,100,20,1,65535,10665,1,1,1,\"center\\rleft\"")
            self.draw_screw_level_info_at("12,240,100,20", self.screw_levels["center left"], green, red)

        self._write("xstr 96,215,100,50,1,65535,15319,1,1,1,\"Retry\"")

    def draw_screw_level_info_at(self, position, level, green, red):
        if level == "base":
            self._write(f"xstr {position},0,65535,10665,1,1,1,\"base\"")
        else:
            color = green if int(level[-2:]) < 5 else red
            self._write(f"xstr {position},0,{color},10665,1,1,1,\"{level}\"")

    async def handle_screw_leveling(self):
        self.leveling_mode = "screw"
        self.screw_levels = {}
        self.screw_probe_count = 0
        response = await self._send_moonraker_request("printer.gcode.script", {"script": "BED_LEVEL_SCREWS_TUNE"})
        self.draw_completed_screw_leveling()

    def draw_initial_zprobe_leveling(self):
        self._write("p[137].b[19].txt=\"Z-Probe\"")
        self._write("fill 0,250,320,320,10665")
        self._write("fill 0,50,320,80,10665")
        self.update_zprobe_leveling_ui()

    def update_zprobe_leveling_ui(self):
        self._write("p[137].b[19].txt=\"Z-Probe\"")
        self._write(f'p[137].b[11].pic={7 + ["0.01", "0.1", "1"].index(self.z_probe_step)}')
        self._write(f'p[137].b[20].txt=\"{self.z_probe_distance}\"')

    async def handle_zprobe_leveling(self):
        if self.leveling_mode == "zprobe":
            return
        self.leveling_mode = "zprobe"
        self.z_probe_step = "0.1"
        self.z_probe_distance = "0.0"
        self._navigate_to_page(PAGE_OVERLAY_LOADING)
        response = await self._send_moonraker_request("printer.gcode.script", {"script": "CALIBRATE_PROBE_Z_OFFSET"})
        self._go_back()

    def draw_kamp_page(self):
        self._write(f'fill 0,45,272,340,10665')
        self._write('xstr 0,0,272,50,1,65535,10665,1,1,1,"Creating Bed Mesh"')
        max_size = 264 # display width - 4px padding
        x_probes = self.bed_leveling_counts[0]
        y_probes = self.bed_leveling_counts[1]
        spacing = 2
        self.bed_leveling_box_size = min(40, int(min(max_size / x_probes, max_size / y_probes) - spacing))
        total_width = (x_probes * (self.bed_leveling_box_size + spacing)) - spacing
        total_height = (y_probes * (self.bed_leveling_box_size + spacing)) - spacing
        self.bed_leveling_x_offset = 4 + (max_size - total_width) / 2
        self.bed_leveling_y_offset = 45 + (max_size - total_height) / 2
        for x in range(0, x_probes):
         for y in range(0, y_probes):
             self.draw_kamp_box(x, y, 17037)
    
    def draw_kamp_box_index(self, index, color):
        if self.bed_leveling_counts[0] == 0:
            return
        row = (self.bed_leveling_counts[0]-1) - int(index / self.bed_leveling_counts[0])
        col = index % self.bed_leveling_counts[0]
        if row % 2 == 1:
          col = self.bed_leveling_counts[1] - 1 - col
        self.draw_kamp_box(col, row, color)

    def draw_kamp_box(self, x, y, color):
        box_size = self.bed_leveling_box_size
        if box_size > 0:
            self._write(f'fill {int(self.bed_leveling_x_offset+x*(box_size+2))},{47+y*(box_size+2)},{box_size},{box_size},{color}')

    def handle_gcode_response(self, response):
        if self.leveling_mode == "screw":
            if "probe at" in response:
                self.screw_probe_count += 1
                self._write(f"b[3].txt=\"Probing Screws ({ceil(self.screw_probe_count/2)}/4)...\"")
            if "screw (base) :" in response:
                self.screw_levels[response.split("screw")[0][3:].strip()] = "base"
            if "screw :" in response:
                self.screw_levels[response.split("screw")[0][3:].strip()] = response.split("adjust")[1].strip()
        elif self.leveling_mode == "zprobe":
            if "Z position:" in response:
                self.z_probe_distance = response.split("->")[1].split("<-")[0].strip()
                self.update_zprobe_leveling_ui()
        elif "Adapted probe count:" in response:
            parts = response.split(":")[1].split(",")
            x_count = int(parts[0].strip())
            y_count = int(parts[1][:-1].strip())
            self.bed_leveling_counts = [x_count, y_count]
        elif response.startswith("// bed_mesh: generated points"):
            if self._get_current_page() != PAGE_PRINTING_KAMP:
                self._navigate_to_page(PAGE_PRINTING_KAMP)
        elif response.startswith("// probe at "):
            new_position = response.split(" ")[3]
            if self.bed_leveling_last_position != new_position:
                self.bed_leveling_last_position = new_position
                if self.bed_leveling_probed_count > 0:
                    self.draw_kamp_box_index(self.bed_leveling_probed_count - 1, BACKGROUND_SUCCESS)
                self.bed_leveling_probed_count += 1
                self.draw_kamp_box_index(self.bed_leveling_probed_count - 1, BACKGROUND_WARNING)
                self._write(f'xstr 0,310,320,50,1,65535,10665,1,1,1,"Probing... ({self.bed_leveling_probed_count}/{self.bed_leveling_counts[0]*self.bed_leveling_counts[1]})"')
        elif response.startswith("// Mesh Bed Leveling Complete"):
            self.bed_leveling_probed_count = 0
            self.bed_leveling_counts = self.full_bed_leveling_counts
            if self._get_current_page() == PAGE_PRINTING_KAMP:
                self._go_back()

loop = asyncio.get_event_loop()
config_observer = Observer()

try:
    config = configparser.ConfigParser(allow_no_value=True)
    if not os.path.exists(config_file):
        logger.info("Creating config file")
        config.add_section('LOGGING')
        config.set('LOGGING', 'file_log_level', 'ERROR')

        config.add_section('files')
        config.set('files', 'sort_by', 'modified')
        config.set('files', 'sort_order', 'desc')
        config.set('files', 'sort_folders_first', 'true')

        config.add_section('main_screen')
        config.set('main_screen', '; set to MODEL_NAME for built in model name. Remove to use Elegoo model images.')
        config.set('main_screen', 'display_name', 'MODEL_NAME')
        config.set('main_screen', '; color for the line below the model name. As RGB565 value.')
        config.set('main_screen', 'display_name_line_color', '1725')

        config.add_section('print_screen')
        config.set('print_screen', 'z_display', 'mm')

        config.add_section('thumbnails')
        config.set('main_screen', '; Background color for thumbnails. As RGB Hex value. Remove for default background color.')
        config.set('thumbnails', 'background_color', '29354a')

        config.add_section('temperatures.pla')
        config.set('temperatures.pla', 'extruder', str(TEMP_DEFAULTS["pla"][0]))
        config.set('temperatures.pla', 'heater_bed', str(TEMP_DEFAULTS["pla"][1]))
        config.add_section('temperatures.petg')
        config.set('temperatures.petg', 'extruder', str(TEMP_DEFAULTS["petg"][0]))
        config.set('temperatures.petg', 'heater_bed', str(TEMP_DEFAULTS["petg"][1]))
        config.add_section('temperatures.abs')
        config.set('temperatures.abs', 'extruder', str(TEMP_DEFAULTS["abs"][0]))
        config.set('temperatures.abs', 'heater_bed', str(TEMP_DEFAULTS["abs"][1]))
        config.add_section('temperatures.tpu')
        config.set('temperatures.tpu', 'extruder', str(TEMP_DEFAULTS["tpu"][0]))
        config.set('temperatures.tpu', 'heater_bed', str(TEMP_DEFAULTS["tpu"][1]))

        config.add_section('prepare')
        config.set('prepare', 'move_distance', '1')
        config.set('prepare', 'xy_move_speed', '130')
        config.set('prepare', 'z_move_speed', '10')
        config.set('prepare', 'extrude_amount', '10')
        config.set('prepare', 'extrude_speed', '5')

        with open(config_file, 'w') as configfile:
            config.write(configfile)
    config.read(config_file)

    controller = DisplayController(config)
    controller._loop = loop

    def handle_wd_callback(notifier):
        controller.handle_config_change()

    def handle_sock_changes(notifier):
        if notifier.event_type == "created":
            logger.info(f"{notifier.src_path.split('/')[-1]} created. Attempting to reconnect...")
            controller.klipper_restart_event.set()

    config_patterns = ["display_connector.cfg"]
    config_event_handler = PatternMatchingEventHandler(config_patterns, None, True, True)
    config_event_handler.on_modified = handle_wd_callback
    config_event_handler.on_created = handle_wd_callback

    socket_patterns = ["klippy.sock", "moonraker.sock"]
    socket_event_handler = PatternMatchingEventHandler(socket_patterns, None, True, True)
    socket_event_handler.on_modified = handle_sock_changes
    socket_event_handler.on_created = handle_sock_changes
    socket_event_handler.on_deleted = handle_sock_changes

    config_observer.schedule(config_event_handler, config_file, recursive=False)
    config_observer.schedule(socket_event_handler, comms_directory, recursive=False)
    config_observer.start()


    loop.call_later(1, controller.start_listening)
    loop.run_forever()
except Exception as e:
    logger.error("Error communicating...: " + str(e))
    logger.error(traceback.format_exc())
finally:
    config_observer.stop()
    config_observer.join()
    loop.close()
