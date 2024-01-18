response_actions = {
    '651200ffffff': "print_opened_file", # Confirm Print File
    '651201ffffff': 'go_back', # cancel print file
    '651300ffffff': "page 27", # Printing Page > Settings
    '651900ffffff': "pause_print_confirm", # Printing Page > Confirm Pause
    '651a00ffffff': "stop_print", # Printing Page > Confirm Stop
    '656a00ffffff': "emergency_stop", # Printing Page > Confirm Emergency Stop
    '656a01ffffff': "go_back", # cancel emergency stop
    '651901ffffff': "go_back", # cancel pause
    '651a01ffffff': "go_back", # cancel stop
    '651800ffffff': "confirm_complete",
    '65??00ffffff': "go_back",  # Return to Previous Page
    # MAIN PAGE OPTIONS (page 1)
    '650101ffffff': "files_picker",  # Page 1 > Print Files Page 1
    '650102ffffff': "page 8",  # Page 1 > Prepare Page (Move)
    '650103ffffff': "page 11", # Page 1 > Settings Page
    '650104ffffff': "page 14", # Page 1 > Level Page
    # PRINT PAGE OPTIONS
    '650202ffffff': "files_page_next",  # Next Page Print Files ->
    '650201ffffff': "files_page_prev",  # Previous Print Files Page <-
    '650207ffffff': "open_file_0",  # Print Files Page > Print File 0
    '650208ffffff': "open_file_1",  # Print Files Page > Print File 1
    '650209ffffff': "open_file_2",  # Print Files Page > Print File 2
    '65020affffff': "open_file_3",  # Print Files Page > Print File 3
    '65020bffffff': "open_file_4",  # Print Files Page > Print File 4
    # PREPARE PAGE OPTIONS
    '65080cffffff': "printer.send_gcode('G28')", # Home Printer > Moonraker command
    '65080dffffff': "printer.send_gcode('G28 Z')", # Home Z Axis > Moonraker command
    '650805ffffff': "printer.send_gcode('G28 Y')", # Home Y Axis > Moonraker command
    '650804ffffff': "printer.send_gcode('G28 X')", # Home X Axis > Moonraker command
    '65080effffff': "printer.send_gcode('M84')", # Disable Motors > Moonraker command
    '650808ffffff': "move_x_+", # X+ 1mm
    '650809ffffff': "move_x_-", # X- 1mm
    '65080affffff': "move_y_+", # Y+ 1mm
    '650807ffffff': "move_y_-", # Y- 1mm
    '650806ffffff': "move_z_+", # Z+ 1mm
    '65080bffffff': "move_z_-", # Z- 1mm
    '650801ffffff': 'set_distance_0.1', # 0.1mm Move Page
    '650802ffffff': "set_distance_1", # 1mm Move Page
    '650803ffffff': "set_distance_10", # 10mm Move Page
    '65080fffffff': "page 6",  # Prepare Page (Move) > Prepare Page (Temp)
    '650607ffffff': "page 8",  # Prepare Page (Temp) > Prepare Page (Move)
    '650608ffffff': "page 9",  # Prepare Page (Temp) > Prepare Page (Extruder)
    # SETTINGS PAGE OPTIONS
    # LANGUAGE SELECT
    '650b01ffffff': "page 12", # Settings Page > Language
    # TEMPERATURE SETTINGS (Material)
    '650b02ffffff': "page 32", # Settings Page > Temperature Settings
    '652001ffffff': "page 33", # Temperature Settings > PLA
    '652002ffffff': "page 33", # Temperature Settings > ABS
    '652003ffffff': "page 33", # Temperature Settings > PETG
    '652004ffffff': "page 33", # Temperature Settings > TPU
    '652005ffffff': "page 33", # Temperature Settings > LEVEL
    '652104ffffff': 'temp_extruder_down', # Temperature Settings > MATERIAL > Extruder Temp Down
    '652105ffffff': 'temp_extruder_up', # Temperature Settings > MATERIAL > Extruder Temp Up
    '652106ffffff': 'temp_bed_down', # Temperature Settings > MATERIAL > Bed Temp Down
    '652107ffffff': 'temp_bed_up', # Temperature Settings > MATERIAL > Bed Temp Up
    # ABOUT MACHINE
    '650b08ffffff': "page 35", # Settings Page > About Machine
    # ADVANCED SETTINGS
    '650b09ffffff': "page 42", # Settings Page > Advanced Settings
    # LIGHT CONTROL
    '650b03ffffff': "page 84", # Settings Page > Light Control
    '655401ffffff': "toggle_part_light", # Light Control > Part Light toggle
    '655402ffffff': "toggle_frame_light", # Light Control > Frame Light toggle
    # FAN CONTROL
    '5aa50683103e010007650b04ffffff': "toggle_fan", # Settings Page > Fan Control Toggle printer.send_gcode('M106 S255')
    'ffffff5aa506': "toggle_fan_OFF", # Settings Page > Fan Control Toggle printer.send_gcode('M106 S0')
    # MOTORS OFF
    '650b05ffffff': "printer.send_gcode('M84')", # Settings Page > Motor-off
    # FILAMENT DETECTOR 
    '650b06ffffff': "toggle_filament_sensor", # Settings Page > Filament Detector Toggle
    # FACTORY SETTINGS
    '650b07ffffff': "factorysettingspage", # Settings Page > Factory Settings

    # PRINTING SCREEN
    '651304ffffff': "page 106", # Printing Page > Halt
    '651301ffffff': "pause_print_button", # Printing Page > Pause
    '651302ffffff': "page 26", # Printing Page > Stop
    '651303ffffff': "page 84", # Printing Page > LED Control

    '657f07ffffff': "page 84", # Printing Page > Adjust > LED Control
    '657f08ffffff': "toggle_filament_sensor", # Printing Page > Adjust > Filament Sensor Toggle
    # '657f06ffffff': "toggle_speed_adaptive", # Printing Page > Adjust > Adaptive Speed Toggle
    '657f04ffffff': "zoffset_+", # Printing Page > Adjust > Z Offset Up
    '657f05ffffff': "zoffset_-", # Printing Page > Adjust > Z Offset Down
    '657f01ffffff': 'zoffsetchange_0.01', # Printing Page > Adjust > Z Offset Change 0.1mm
    '657f02ffffff': 'zoffsetchange_0.1', # Printing Page > Adjust > Z Offset Change 1mm
    '657f03ffffff': 'zoffsetchange_1', # Printing Page > Adjust > Z Offset Change 10mm

    '651b01ffffff': "temp_heater_extruder",
    '651b02ffffff': "temp_heater_heater_bed",
    '651b09ffffff': "temp_heater_heater_bed_outer",
    '651b03ffffff': "temp_increment_1",
    '651b04ffffff': "temp_increment_5",
    '651b05ffffff': "temp_increment_10",
    '651b06ffffff': "temp_adjust_-",
    '651b07ffffff': "temp_adjust_+",
    '651b08ffffff': "temp_reset",

    '658701ffffff': "speed_type_print",
    '658702ffffff': "speed_type_flow",
    '658703ffffff': "speed_type_fan",
    '658704ffffff': "speed_increment_1",
    '658705ffffff': "speed_increment_5",
    '658706ffffff': "speed_increment_10",
    '658707ffffff': "speed_adjust_-",
    '658708ffffff': "speed_adjust_+",
    '658709ffffff': "speed_reset",

    '651801ffffff': 'print_opened_file', # Completed Print Page > Print Again

    '65??09ffffff': "page 27", # Printing Page > Filament
    '65??0affffff': "page 135", # Printing Page > Speed
    '651b0cffffff': "page 135", # Printing Page > Speed
    '65??0dffffff': "page 127", # Printing Page > Adjust
}

response_errors = {
    '00ffffff': 'Invalid Instruction',
    '02ffffff': 'Invalid Component ID',
    '03ffffff': 'Invalid Page ID',
    '04ffffff': 'Invalid Picture ID',
    '05ffffff': 'Invalid Font ID',
    '11ffffff': 'Invalid Baud Rate',
    '1affffff': "Invalid Variable name or attribute",
    '1bffffff': "Invalid Variable operation",
    '1cffffff': "Assignment failed to assign",
    '1effffff': "Invalid Quantity of Parameters",
}