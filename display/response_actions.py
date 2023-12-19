response_actions = {
	('65', '**', '00', 'ff', 'ff', 'ff'): "go_back", # Return to Previous Page
	# MAIN PAGE OPTIONS (page 1)
	('65', '01', '01', 'ff', 'ff', 'ff'): "page 2", # Page 1 > Print Files Page 1
	('65', '01', '02', 'ff', 'ff', 'ff'): "page 8", # Page 1 > Prepare Page (Move)
	('65', '01', '03', 'ff', 'ff', 'ff'): "page 11", # Page 1 > Settings Page
	('65', '01', '04', 'ff', 'ff', 'ff'): "page 14", # Page 1 > Level Page #page 103 , 137?
	# PRINT PAGE OPTIONS
	('65', '02', '02', 'ff', 'ff', 'ff'): "page 3", # Next Page Print Files ->
	('65', '02', '01', 'ff', 'ff', 'ff'): "page 2", # Previous Print Files Page <-
	# PREPARE PAGE OPTIONS
	('65', '08', '0c', 'ff', 'ff', 'ff'): "printer.send_gcode('G28')", # Home Printer > Moonraker command
	('65', '08', '0f', 'ff', 'ff', 'ff'): "page 6", # Prepare Page (Move) > Prepare Page (Temp)
	('65', '06', '07', 'ff', 'ff', 'ff'): "page 8", # Prepare Page (Temp) > Prepare Page (Move)
	('65', '06', '08', 'ff', 'ff', 'ff'): "page 9", # Prepare Page (Temp) > Prepare Page (Extruder)
	# SETTINGS PAGE OPTIONS
	# LANGUAGE SELECT
	('65', '0b', '01', 'ff', 'ff', 'ff'): "page 12", # Settings Page > Language ? page 31
	# TEMPERATURE SETTINGS (Material)
	('65', '0b', '02', 'ff', 'ff', 'ff'): "page 32", # Settings Page > Temperature Settings
	('65', '20', '01', 'ff', 'ff', 'ff'): "page 33", # Temperature Settings > PLA
	('65', '20', '02', 'ff', 'ff', 'ff'): "page 33", # Temperature Settings > ABS
	('65', '20', '03', 'ff', 'ff', 'ff'): "page 33", # Temperature Settings > PETG
	('65', '20', '04', 'ff', 'ff', 'ff'): "page 33", # Temperature Settings > TPU
	('65', '20', '05', 'ff', 'ff', 'ff'): "page 33", # Temperature Settings > LEVEL
	# ABOUT MACHINE
	('65', '0b', '08', 'ff', 'ff', 'ff'): "page 35", # Settings Page > About Machine
	# ADVANCED SETTINGS
	('65', '0b', '09', 'ff', 'ff', 'ff'): "page 42", # Settings Page > Advanced Settings
	# LIGHT CONTROL
	('65', '0b', '03', 'ff', 'ff', 'ff'): "page 84", # Settings Page > Light Control
	('65', '54', '01', 'ff', 'ff', 'ff'): "printer.send_gcode('Part_Light_ON')", # Light Control > Part Light toggle
	('65', '54', '02', 'ff', 'ff', 'ff'): "printer.send_gcode('Frame_Light_ON')", # Light Control > Frame Light toggle  
	# FAN CONTROL
	('5a', 'a5', '06', '83', '10', '3e'): "printer.send_gcode('M106 S255')", # Settings Page > Fan Control Toggle
	# MOTORS OFF
	('65', '0b', '05', 'ff', 'ff', 'ff'): "printer.send_gcode('M84')", # Settings Page > Motor-off
	# FILAMENT DETECTOR 
	('65', '0b', '06', 'ff', 'ff', 'ff'): "printer.send_gcode('SET_FILAMENT_SENSOR SENSOR=fila ENABLE=1')", # Settings Page > Filament Detector Toggle
	# FACTORY SETTINGS
	('65', '0b', '07', 'ff', 'ff', 'ff'): "factorysettingspage", # Settings Page >  Factory Settings
}
