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
        start_item.connect('activate', lambda _: self.start_or_restart_myg('start'))
        stop_item = Gtk.MenuItem(label='Stop')
        stop_item.connect('activate', lambda _: geo.run('myg stop'))
        restart_item = Gtk.MenuItem(label='Restart')
        restart_item.connect('activate', lambda _: self.start_or_restart_myg('restart'))
        build_item = Gtk.MenuItem(label='Build')
        build_item.connect('activate', lambda _: geo.run_in_terminal('myg build'))
        build_sln_item = Gtk.MenuItem(label='Build Solution')
        build_sln_item.connect('activate', lambda _: geo.run_in_terminal('myg build sln'))
        browser_item = Gtk.MenuItem(label='Open In Browser')
        browser_item.connect('activate', lambda _: webbrowser.open('https://localhost:10001', new=2))
        api_item = Gtk.MenuItem(label='Open API Runner')
        api_item.connect('activate', lambda _: geo.run_in_terminal('myg api-runner', title=self.make_titles('API Runner')))
        clean_item = Gtk.MenuItem(label='Clean')
        clean_item.connect('activate', lambda _: geo.run_in_terminal('myg clean --interactive', stay_open_after=False))
        submenu.append(start_item)
        submenu.append(build_item)
        submenu.append(build_sln_item)
        submenu.append(clean_item)
        submenu.append(stop_item)
        submenu.append(restart_item)
        submenu.append(browser_item)
        # submenu.append(api_item)
        self.set_submenu(submenu)
        submenu.show_all()
        self.items = {
            "start": start_item,
            "build": build_item,
            "build_sln": build_sln_item,
            "clean": clean_item,
            "stop": stop_item,
            "restart": restart_item,
            "browser": browser_item,
            "api": api_item,
        }
        
    def start_or_restart_myg(self, cmd):
        title = self.make_titles('MyGeotab', include_version=True)
        geo.run_in_terminal(f'myg {cmd}', title=title)

    def monitor(self):
        is_running = geo.run('myg is-running')
        if is_running:
            self.items['start'].hide()
            self.items['build'].hide()
            self.items['build_sln'].hide()
            self.items['clean'].hide()
            
            self.items['stop'].show()
            self.items['restart'].show()
            self.items['browser'].show()
            # self.items['api'].show()
        else:
            self.items['start'].show()
            self.items['build'].show()
            self.items['build_sln'].show()
            self.items['clean'].show()
            
            self.items['stop'].hide()
            self.items['restart'].hide()
            self.items['browser'].hide()
            # self.items['api'].hide()
        return True
