import time

PAGE_MAIN = "main"
PAGE_FILES = "files"

PAGE_PREPARE_MOVE = "prepare_move"
PAGE_PREPARE_TEMP = "prepare_temp"
PAGE_PREPARE_EXTRUDER = "prepare_extruder"

PAGE_SETTINGS = "settings"
PAGE_SETTINGS_LANGUAGE = "settings_language"
PAGE_SETTINGS_TEMPERATURE = "settings_temperature"
PAGE_SETTINGS_TEMPERATURE_SET = "settings_temperature_set"
PAGE_SETTINGS_ABOUT = "settings_about"
PAGE_SETTINGS_ADVANCED = "settings_advanced"

PAGE_LEVELING = "leveling"

PAGE_CONFIRM_PRINT = "confirm_print"
PAGE_PRINTING = "printing"
PAGE_PRINTING_PAUSE = "printing_pause"
PAGE_PRINTING_STOP = "printing_stop"
PAGE_PRINTING_EMERGENCY_STOP = "printing_emergency_stop"
PAGE_PRINTING_COMPLETE = "printing_complete"
PAGE_PRINTING_FILAMENT = "printing_filament"
PAGE_PRINTING_SPEED = "printing_speed"
PAGE_PRINTING_ADJUST = "printing_adjust"

PAGE_OVERLAY_LOADING = "overlay_loading"

PAGE_LIGHTS = "lights"

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

    
def build_accessor(page, field):
    accessor = ""
    try:
        page_number = int(page)
        accessor += f"p[{page_number}]"
    except ValueError:
        accessor += page
    accessor += "."
    try:
        field_number = int(field)
        accessor += f"b[{field_number}]"
    except ValueError:
        accessor += field
    return accessor

class Mapper:
    data_mapping = {}
    page_mapping = {}

    def map_page(self, page):
        if page in self.page_mapping:
            return self.page_mapping[page]
        return None
