response_actions = {
	('65', '01', '01', 'ff', 'ff', 'ff'): "page 2", # Page 1 > Print Files Page 1
	('65', '02', '02', 'ff', 'ff', 'ff'): "page 3", # Next Page Print Files ->
	('65', '02', '01', 'ff', 'ff', 'ff'): "page 2", # Return to Print Files Page 1 <-
	('65', '**', '00', 'ff', 'ff', 'ff'): "go_back", # Return to Previous Page
	('65', '01', '02', 'ff', 'ff', 'ff'): "page 8", # Page 1 > Prepare Page (Move)
	('65', '08', '0f', 'ff', 'ff', 'ff'): "page 6", # Prepare Page (Move) > Prepare Page (Temp)
	('65', '06', '07', 'ff', 'ff', 'ff'): "page 8", # Prepare Page (Temp) > Prepare Page (Move)
	('65', '06', '08', 'ff', 'ff', 'ff'): "page 9", # Prepare Page (Temp) > Prepare Page (Extruder)
	('65', '01', '03', 'ff', 'ff', 'ff'): "page 11", # Page 1 > Settings Page
	('65', '0b', '01', 'ff', 'ff', 'ff'): "page 12", # Settings Page > Language
	('65', '0b', '02', 'ff', 'ff', 'ff'): "page 32", # Settings Page > Temperature Settings
	('65', '0b', '08', 'ff', 'ff', 'ff'): "page 35", # Settings Page > About Machine
	('65', '0b', '09', 'ff', 'ff', 'ff'): "page 42", # Settings Page > Advanced Settings
	('65', '0b', '03', 'ff', 'ff', 'ff'): "page 84", # Settings Page > Light Control
	('65', '01', '04', 'ff', 'ff', 'ff'): "page 14", # Page 1 > Level Page #page 103 , 137?
}
