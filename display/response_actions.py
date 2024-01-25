response_actions = {
    '65??00ffffff': "go_back",  # Return to Previous Page
    # MAIN PAGE OPTIONS (page 1)
    '650101ffffff': "page 2",  # Page 1 > Print Files Page 1
    '650102ffffff': "page 8",  # Page 1 > Prepare Page (Move)
    '650103ffffff': "page 11", # Page 1 > Settings Page
    '650104ffffff': "page 14", # Page 1 > Level Page
    # PRINT PAGE OPTIONS
    '650202ffffff': "page 3",  # Next Page Print Files ->
    '650201ffffff': "page 2",  # Previous Print Files Page <-
    # PREPARE PAGE OPTIONS
    '65080cffffff': "printer.send_gcode('G28')", # Home Printer > Moonraker command
    '650808ffffff': "move_x_1mm", # X+ 1mm
    '650809ffffff': "move_x_-1mm", # X- 1mm
    '65080affffff': "move_y_1mm", # Y+ 1mm
    '650807ffffff': "move_y_-1mm", # Y- 1mm
    '650806ffffff': "move_z_1mm", # Z+ 1mm
    '65080bffffff': "move_z_-1mm", # Z- 1mm
    '650803ffffff': "page 10mm", # 10mm Move Page
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
    # ABOUT MACHINE
    '650b08ffffff': "page 35", # Settings Page > About Machine
    # ADVANCED SETTINGS
    '650b09ffffff': "page 42", # Settings Page > Advanced Settings
    # LIGHT CONTROL
    '650b03ffffff': "page 84", # Settings Page > Light Control
    '655401ffffff': "toggle_part_light", # Light Control > Part Light toggle
    '655402ffffff': "toggle_frame_light", # Light Control > Frame Light toggle
    # FAN CONTROL
    '5aa50683103e': "toggle_fan_ON", # Settings Page > Fan Control Toggle printer.send_gcode('M106 S255')
    'ffffff5aa506': "toggle_fan_OFF", # Settings Page > Fan Control Toggle printer.send_gcode('M106 S0')
    # MOTORS OFF
    '650b05ffffff': "printer.send_gcode('M84')", # Settings Page > Motor-off
    # FILAMENT DETECTOR 
    '650b06ffffff': "toggle_filament_sensor", # Settings Page > Filament Detector Toggle
    # FACTORY SETTINGS
    '650b07ffffff': "factorysettingspage", # Settings Page > Factory Settings
}
