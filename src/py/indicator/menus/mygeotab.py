import concurrent.futures
import os
import shutil

from indicator import *
from indicator.geo_indicator import IndicatorApp
from indicator.menus.components import PersistentCheckMenuItem


def to_key(key_str):
    return key_str.replace('.', '_').replace('/', '_').replace(' ', '_')


class MyGeotabMenuItem(Gtk.MenuItem):
    cur_myg_release = ''
    prev_myg_release = ''
    auto_switch_tasks = set()

    def __init__(self, app: IndicatorApp):
        super().__init__(label='MyGeotab')
        self.app = app
        self.build_submenu(app)
        self.show_all()
        # GLib.timeout_add(1000, self.monitor)

    def build_submenu(self, app):
        submenu = Gtk.Menu()
        
        start_item = Gtk.MenuItem(label='Start')
        start_item.connect('activate', lambda _: geo.run_in_terminal('myg start'))
        build_item = Gtk.MenuItem(label='Build')
        build_item.connect('activate', lambda _: geo.run_in_terminal('myg build'))
        submenu.append(start_item)
        submenu.append(build_item)
        self.set_submenu(submenu)
        submenu.show_all()

    # def monitor(self):

    #     return True

    # def run_auto_switch_ta

