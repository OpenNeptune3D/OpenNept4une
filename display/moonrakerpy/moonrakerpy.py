from requests import get, post

class MoonrakerPrinter(object):
    '''Moonraker API interface.
    Args
    ----
    address (str): e.g. 'http://192.168.1.17'
    '''
    def __init__(self, address:str):
        self.addr = address.strip('/')

        configfile = self.get('/printer/objects/query?configfile')
        self.settings = configfile['result']['status']['configfile']['settings']
        self.config = configfile['result']['status']['configfile']['config']

        self.cmd_qgl = 'QUAD_GANTRY_LEVEL'
        self.cmd_bed_mesh = 'BED_MESH_CALIBRATE'
        self.temp_sensors = self.list_temp_sensors()

    def send_gcode(self, cmd:str):
        resp = self.post('/printer/gcode/script?script=%s' % cmd)
        if 'result' in resp:
            return True
        return False

    def get_gcode(self, count:int=1, simplify:bool=True, msg_type:str='response'):
        '''
        Query the gcode store.

        Args
        ----------
        count : int, default=1
            Numbers of cached items to retrieve from the gcode store
        simplify : bool, default=True
            Return only the message portion of each item, as a list
        msg_type : str, default='response'
            One of 'response', 'command', or 'both' to return

        Returns
        -------
        list - cached gcode strings if simplified, dict of each item if not
        '''
        resp = self.get('/server/gcode_store?count=%i' % count)
        store = resp['result']['gcode_store']
        responses = []
        for obj in store:
            if msg_type == 'both':
                responses.append(obj)
            else:
                if obj['type'] == msg_type:
                    responses.append(obj)
        if simplify:
            return [obj['message'] for obj in responses]
        return responses

    def query_status(self, object:str=''):
        '''
        Query a single printer object.
        
        Args
        ----
        object : str
            Printer status object
        
        Returns
        -------
        dict, printer object status
        '''
        query = '/printer/objects/query?%s' % object
        return self.get(query)['result']['status'][object]

    def set_bed_temp(self, target:float=0.):
        cmd = 'SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET=%.1f' % target
        if self.send_gcode(cmd):
            return True
        return False

    def set_extruder_temp(self, target:float=0.):
        cmd = 'SET_HEATER_TEMPERATURE HEATER=extruder TARGET=%.1f' % target
        if self.send_gcode(cmd):
            return True
        return False    

    def qgl(self):
        if 'quad_gantry_level' in self.config:
            return self.send_gcode(self.cmd_qgl)
        err_msg = 'Cannot QGL: "quad_gantry_level" not configured in Klipper'
        raise RuntimeError(err_msg)

    def bed_mesh_cal(self):
        if 'bed_mesh' in self.config:
            return self.send_gcode(self.cmd_bed_mesh)
        err_msg = 'Cannot bed mesh: "bed_mesh" not configured in Klipper'
        raise RuntimeError(err_msg)

    def bed_mesh_query(self):
        if 'bed_mesh' in self.config:
            url = '/printer/objects/query?bed_mesh'
            resp = self.get(url)['result']['status']['bed_mesh']
            return resp
        err_msg = 'Cannot query bed mesh: "bed_mesh" not configured in Klipper'
        raise RuntimeError(err_msg)

    def bed_mesh_clear(self):
        if 'bed_mesh' in self.config:
            return self.send_gcode('BED_MESH_CLEAR')
        err_msg = 'Cannot clear mesh: "bed_mesh" not configured in Klipper'
        raise RuntimeError(err_msg)

    def query_temperatures(self):
        url = '/printer/objects/query?' + '&'.join(self.temp_sensors)
        resp = self.get(url)['result']['status']
        keys = [key.replace('temperature_sensor ', '') for key in list(resp.keys())]
        items = list(resp.values())
        renamed = dict(zip(keys, items))
        return renamed

    def list_temp_sensors(self):
        sensor_sections = ('temperature_sensor',
                           'extruder',
                           'heater_bed')
        sensors = []
        for heading in self.config:
            if heading.startswith(sensor_sections):
                sensors.append(heading)
        return sensors

    def get(self, url:str):
        '''`response.get` wrapper. `url` concatenated to printer base address
        Returns .json response dict.'''
        return get(self.addr + url).json()

    def post(self, url:str, *args, **kwargs):
        '''`response.set` wrapper. `url` is concatenated to printer base address.
        Returns .json response dict.'''
        return post(self.addr + url, *args, **kwargs).json()
