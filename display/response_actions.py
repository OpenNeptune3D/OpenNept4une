from mapping import *

response_actions = {
    1: {
        1: "files_picker",
        2: "page " + PAGE_PREPARE_MOVE,
        3: "page " + PAGE_SETTINGS,
        4: "page " + PAGE_LEVELING,
    },
    2: {
        2: "files_page_next",
        1: "files_page_prev",
        7: "open_file_0",
        8: "open_file_1",
        9: "open_file_2",
        10: "open_file_3",
        11: "open_file_4",
    },
    3: {
        7: "page " + PAGE_LEVELING_SCREW_ADJUST,
        8: "page " + PAGE_LEVELING_Z_OFFSET_ADJUST,
    },
    6: {
        1: "printer.send_gcode('SET_HEATER_TEMPERATURE HEATER=extruder')",
        2: "printer.send_gcode('SET_HEATER_TEMPERATURE HEATER=heater_bed')",
        3: 'set_preset_temp_PLA',
        4: 'set_preset_temp_ABS',
        5: 'set_preset_temp_PETG',
        6: 'set_preset_temp_TPU',
        7: "page " + PAGE_PREPARE_MOVE,
        8: "page " + PAGE_PREPARE_EXTRUDER,
        9: "printer.send_gcode('SET_HEATER_TEMPERATURE HEATER=heater_bed_outer')",
    },
    8: {
        1: 'set_distance_0.1',
        2: 'set_distance_1',
        3: 'set_distance_10',
        4: "printer.send_gcode('G28 X')",
        5: "printer.send_gcode('G28 Y')",
        6: 'move_z_+',
        7: 'move_y_-',
        8: 'move_x_+',
        9: 'move_x_-',
        10: 'move_y_+',
        11: 'move_z_-',
        12: "printer.send_gcode('G28')",
        13: "printer.send_gcode('G28 Z')",
        14: "printer.send_gcode('M84')",
        15: 'page ' + PAGE_PREPARE_TEMP,
        16: 'page ' + PAGE_PREPARE_EXTRUDER,
    },
    9: {
        1: 'extrude_+',
        2: 'extrude_-',
        3: "page " + PAGE_PREPARE_MOVE,
        4: "page " + PAGE_PREPARE_TEMP,
    },
    11: {
        1: "page " + PAGE_SETTINGS_LANGUAGE,
        2: "page " + PAGE_SETTINGS_TEMPERATURE,
        3: "page " + PAGE_LIGHTS,
        4: 'toggle_fan',
        5: "printer.send_gcode('M84')",
        6: 'toggle_filament_sensor',
        8: "page " + PAGE_SETTINGS_ABOUT,
        9: "page " + PAGE_SETTINGS_ADVANCED,
    },
    18: {
        0: 'print_opened_file',
        1: 'go_back'
    },
    19: {
        0: "page " + PAGE_PRINTING_FILAMENT,
        1: 'pause_print_button',
        2: "page " + PAGE_PRINTING_STOP,
        3: "page " + PAGE_LIGHTS,
        4: "page " + PAGE_PRINTING_EMERGENCY_STOP,

    },
    24: {
        0: 'confirm_complete',
        1: 'print_opened_file',
    },
    25: {
        0: "pause_print_confirm",
        1: 'go_back'
    },
    26: {
        0: "stop_print",
        1: 'go_back'
    },
    27: {
        1: 'temp_heater_extruder',
        2: 'temp_heater_heater_bed',
        3: 'temp_increment_1',
        4: 'temp_increment_5',
        5: 'temp_increment_10',
        6: 'temp_adjust_-',
        7: 'temp_adjust_+',
        8: 'temp_reset',
        9: 'temp_heater_heater_bed_outer',
        12: "page " + PAGE_PRINTING_SPEED,
        13: "page " + PAGE_PRINTING_ADJUST
    },
    28: {
        1: 'temp_heater_extruder',
        2: 'temp_heater_heater_bed',
        3: 'temp_increment_1',
        4: 'temp_increment_5',
        5: 'temp_increment_10',
        6: 'temp_adjust_-',
        7: 'temp_adjust_+',
        8: 'temp_reset',
        12: "page " + PAGE_PRINTING_SPEED,
        13: "page " + PAGE_PRINTING_ADJUST
    },
    32: {
        1: "start_temp_preset_pla",
        2: "start_temp_preset_abs",
        3: "start_temp_preset_petg",
        4: "start_temp_preset_tpu",
    },
    33: {
        0: 'save_temp_preset',
        1: 'preset_temp_step_1',
        2: 'preset_temp_step_5',
        3: 'preset_temp_step_10',
        4: "preset_temp_extruder_down",
        5: "preset_temp_extruder_up",
        6: "preset_temp_bed_down",
        7: "preset_temp_bed_up",
    },
    84: {
        1: "toggle_part_light",
        2: "toggle_frame_light",
    },
    94: {
        5: 'retry_screw_leveling'
    },
    95: {
        1: "printer.send_gcode('SET_HEATER_TEMPERATURE HEATER=extruder')",
        2: "printer.send_gcode('SET_HEATER_TEMPERATURE HEATER=heater_bed')",
        3: 'preset_temp_PLA',
        4: 'preset_temp_ABS',
        5: 'preset_temp_PETG',
        6: 'preset_temp_TPU',
        7: "page " + PAGE_PREPARE_MOVE,
        8: "page " + PAGE_PREPARE_EXTRUDER,
    },
    106: {
        0: "emergency_stop",
        1: 'go_back'
    },
    127: {
        1: 'zoffsetchange_0.01',
        2: 'zoffsetchange_0.1',
        3: 'zoffsetchange_1',
        4: 'zoffset_+',
        5: 'zoffset_-',
        7: 'page ' + PAGE_LIGHTS,
        8: 'toggle_filament_sensor'
    },
    135: {
        1: 'speed_type_print',
        2: 'speed_type_flow',
        3: 'speed_type_fan',
        4: 'speed_increment_1',
        5: 'speed_increment_5',
        6: 'speed_increment_10',
        7: 'speed_adjust_-',
        8: 'speed_adjust_+',
        9: 'speed_reset',
    },
    137: {
        0: 'abort_zprobe',
        1: 'zprobe_step_0.01',
        2: 'zprobe_step_0.1',
        3: 'zprobe_step_1',
        5: 'zprobe_+',
        6: 'zprobe_-',
        7: 'save_zprobe',
    },
}

input_actions = {
    6: {
        0: "set_temp_extruder_$",
        1: "set_temp_heater_bed_$",
        2: "set_temp_heater_bed_outer_$",
    },
    9: {
        2: "set_extrude_amount_$",
        3: "set_extrude_speed_$",
    },
    95: {
        0: "set_temp_extruder_$",
        1: "set_temp_heater_bed_$",
    },
}