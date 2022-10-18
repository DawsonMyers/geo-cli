import concurrent.futures
import os
import shutil
import time

from indicator import *
from indicator.geo_indicator import IndicatorApp
from indicator.menus.components import PersistentCheckMenuItem


def to_key(key_str):
    return key_str.replace('.', '_').replace('/', '_').replace(' ', '_')


class MyGeotabMenuItem(Gtk.MenuItem):
    cur_myg_release = ''
    prev_myg_release = ''
    auto_switch_tasks = set()
    items = {}
    conditional_items = set()
    submenu = None
    def __init__(self, app: IndicatorApp):
        super().__init__(label='MyGeotab')
        self.app = app
        self.build_submenu(app)
        self.show_all()
        GLib.timeout_add(1000, self.monitor)

    def build_submenu(self, app):
        self.submenu = submenu = Gtk.Menu()
        
        start_item = Gtk.MenuItem(label='Start')
        start_item.connect('activate', lambda _: geo.run_in_terminal('myg start'))
        stop_item = Gtk.MenuItem(label='Stop')
        stop_item.connect('activate', lambda _: geo.run('myg stop'))
        restart_item = Gtk.MenuItem(label='Restart')
        restart_item.connect('activate', lambda _: geo.run_in_terminal('myg restart'))
        build_item = Gtk.MenuItem(label='Build')
        build_item.connect('activate', lambda _: geo.run_in_terminal('myg build'))
        submenu.append(start_item)
        submenu.append(stop_item)
        submenu.append(build_item)
        submenu.append(restart_item)
        self.set_submenu(submenu)
        submenu.show_all()
        self.items = {
            "start": start_item,
            "stop": stop_item,
            "restart": restart_item,
            "build": build_item,
        }
    def restart_myg(self):
        geo.run('myg restart')
        time.sleep(3)
        geo.run_in_terminal('myg start')

    def monitor(self):
        is_running = geo.run('myg is-running')
        if is_running:
            self.items['start'].hide()
            self.items['build'].hide()
            self.items['restart'].show()
            self.items['stop'].show()
        else:
            self.items['start'].show()
            self.items['build'].show()
            self.items['restart'].hide()
            self.items['stop'].hide()
        return True

