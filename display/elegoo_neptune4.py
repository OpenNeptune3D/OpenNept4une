from mapping import *

class Neptune4Mapper(Mapper):
    page_mapping = {
        PAGE_MAIN: "1",
        PAGE_FILES: "2",
        PAGE_PREPARE_MOVE: "8",
        PAGE_PREPARE_TEMP: "6",
        PAGE_PREPARE_EXTRUDER: "9",

        PAGE_SETTINGS: "11",
        PAGE_SETTINGS_LANGUAGE: "12",
        PAGE_SETTINGS_TEMPERATURE: "32",
        PAGE_SETTINGS_TEMPERATURE_PLA: "33",
        PAGE_SETTINGS_TEMPERATURE_ABS: "33",
        PAGE_SETTINGS_TEMPERATURE_PETG: "33",
        PAGE_SETTINGS_TEMPERATURE_TPU: "33",
        PAGE_SETTINGS_TEMPERATURE_LEVEL: "33",
        PAGE_SETTINGS_ABOUT: "35",
        PAGE_SETTINGS_ADVANCED: "42",

        PAGE_LEVELING: "14",

        PAGE_CONFIRM_PRINT: "18",
        PAGE_PRINTING: "19",
        PAGE_PRINTING_SETTINGS: "27",
        PAGE_PRINTING_PAUSE: "25",
        PAGE_PRINTING_STOP: "26",
        PAGE_PRINTING_EMERGENCY_STOP: "106",
        PAGE_PRINTING_COMPLETE: "24",
        PAGE_PRINTING_FILAMENT: "27",
        PAGE_PRINTING_SPEED: "135",
        PAGE_PRINTING_ADJUST: "127",

        PAGE_OVERLAY_LOADING: "130",
        PAGE_LIGHTS: "84"
    }
    data_mapping = {
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
            "filename": [MappingLeaf(["p[19].t0"], formatter=lambda x: x.replace(".gcode", ""))],
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