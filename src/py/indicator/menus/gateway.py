import concurrent.futures
import os
import shutil
import time
import webbrowser

from indicator import *
from indicator.geo_indicator import IndicatorApp
from indicator.menus.components import PersistentCheckMenuItem
from gi.overrides.Gtk import Gtk

def to_key(key_str):
    return key_str.replace('.', '_').replace('/', '_').replace(' ', '_')


class GatewayMenuItem(Gtk.MenuItem):
    cur_myg_release = ''
    prev_myg_release = ''
    auto_switch_tasks = set()
    items = {}
    conditional_items = set()
    submenu = None
    running_items = set()
    stopped_items = set()
    gw_running = False
    def __init__(self, app: IndicatorApp):
        super().__init__(label='✉️ Gateway')
        self.app = app
        self.build_submenu(app)
        self.show_all()
        GLib.timeout_add(4000, self.monitor)

    def make_titles(self, title, include_version=False):
        window_title = f'{title} [ geo-cli ]'
        if include_version:
            version = geo.run('dev release')
            if version:
                window_title = f'{title} {version} [ geo-cli ]'
        return window_title
    
    def build_submenu(self, app):
        self.submenu = submenu = Gtk.Menu()

        start_item = Gtk.MenuItem(label='Start')
        start_item.connect('activate', lambda _: self.start_or_restart_gateway('start'))
        stop_item = Gtk.MenuItem(label='Stop')
        stop_item.connect('activate', lambda _: geo.run('gw stop'))
        restart_item = Gtk.MenuItem(label='Restart')
        restart_item.connect('activate', lambda _: self.start_or_restart_gateway('restart'))
        build_item = Gtk.MenuItem(label='Build')
        build_item.connect('activate', lambda _: geo.run_in_terminal('gw build'))
        build_sln_item = Gtk.MenuItem(label='Build Solution')
        build_sln_item.connect('activate', lambda _: geo.run_in_terminal('gw build sln'))
        clean_item = Gtk.MenuItem(label='Clean')
        clean_item.connect('activate', lambda _: geo.run_in_terminal('gw clean --interactive', stay_open_after=False))
        submenu.append(start_item)
        submenu.append(build_item)
        submenu.append(build_sln_item)
        submenu.append(clean_item)
        submenu.append(stop_item)
        submenu.append(restart_item)
        self.set_submenu(submenu)
        submenu.show_all()
        self.items = {
            "start": start_item,
            "build": build_item,
            "build_sln": build_sln_item,
            "clean": clean_item,
            "stop": stop_item,
            "restart": restart_item
        }
        
        self.running_items = {
            stop_item,
            restart_item
        }
        self.stopped_items = {
            start_item,
            build_item,
            build_sln_item,
            clean_item
        }
        
    def start_or_restart_gateway(self, cmd):
        title = self.make_titles('Gateway', include_version=True)
        geo.run_in_terminal(f'gw {cmd}', title=title)

    def monitor(self):
        gw_running = geo.run('gw is-running', return_success_status=True)
        if gw_running != self.app.get_state('gw_running'):
            self.app.set_state('gw_running', gw_running)
        self.gw_running = gw_running
        if gw_running:
            self.app.icon_manager.set_gateway_running(True)
            self.show_running_items()
        else:
            self.app.icon_manager.set_gateway_running(False)
            self.show_stopped_items()
        return True
    
    def show_running_items(self):
        [item.show() for item in self.running_items]
        [item.hide() for item in self.stopped_items]
    
    def show_stopped_items(self):
        [item.hide() for item in self.running_items]
        [item.show() for item in self.stopped_items]

