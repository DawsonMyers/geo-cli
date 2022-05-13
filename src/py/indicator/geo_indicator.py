
import os
import signal
import time
import subprocess

import sys
sys.path.insert(0, os.path.join(sys.path[0], '..'))
# sys.path.append(os.path.abspath(__file__))
# sys.path.insert(0, sys.path[0])
# sys.path.insert(0, os.path.join(sys.path[0], '..'))
# import gi
# gi.require_version('Gtk', '3.0')
# gi.require_version('AppIndicator3', '0.1')
# gi.require_version('Notify', '0.7')
# gi.require_version('Gio', '2.0')
#
# from gi.repository import Gtk, GLib, Gio, Notify, GdkPixbuf
# from gi.repository import AppIndicator3 as appindicator

# # sys.path.insert(1, os.path.join(sys.path[0], '..'))
#
# BASE_DIR = os.path.dirname(os.path.realpath(__file__))
# GEO_SRC_PY_DIR = os.path.dirname(BASE_DIR)
# # sys.path.insert(0, GEO_SRC_PY_DIR)
# # sys.path.append(GEO_SRC_PY_DIR)
# GEO_SRC_DIR = os.path.dirname(GEO_SRC_PY_DIR)
# GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '

# from menus.db import RunningDbMenuItem, DbMenu, DbMenuItem
# from menus.update import UpdateMenuItem
# from menus.help import HelpMenuItem
# from .menus.db import RunningDbMenuItem,
from indicator import *
from indicator import icons, menus
from common import geo




# from gi.repository import Notify as notify

APPINDICATOR_ID = 'geo.indicator'

UPDATE_INTERVAL = 10*60*1000



# icon_geo_cli = os.path.join(BASE_DIR, 'res', 'geo-cli-logo.png')
# icon_green_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green.svg')
# icon_green_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green-update.svg')
# icon_grey_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey.svg')
# icon_grey_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey-update.svg')
# icon_red_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red.svg')
# icon_red_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red-update.svg')
# icon_orange_path = os.path.join(BASE_DIR, 'res', 'geo-icon-orange.svg')
# icon_orange_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-orange-update.svg')
# icon_spinner_path = os.path.join(BASE_DIR, 'res', 'geo-spinner.svg')
#
# indicator = None
# ICON_RED = 'red'
# ICON_GREEN = 'green'
# ICON_ORANGE = 'orange'


class IndicatorApp(object):
    notification = None
    def __init__(self):
        Notify.init(APPINDICATOR_ID)
        self.indicator = appindicator.Indicator.new(APPINDICATOR_ID, icons.GREEN_PATH, appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title('geo-cli')
        # self.gtk_app = Gio.Application.new(APPINDICATOR_ID, Gio.ApplicationFlags.FLAGS_NONE)
        # self.gtk_app = Gio.Application.new(application_id=APPINDICATOR_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        # self.gtk_app.register()
        # self.indicator.set_label('geo-cli', 'geo-cli')
        self.db_submenu = None
        self.item_databases = None
        self.item_running_db = None
        self.item_auto_switch_db_toggle = None
        self.icon_manager = icons.IconManager(self.indicator)
        self.menu = MainMenu(self)
        self.build_menu(self.menu)
        self.indicator.set_menu(self.menu)

    def show_notification(self):
        if not geo.notifications_are_allowed():
            return
        if self.notification:
            self.notification.close()
        n=Notify.Notification.new("New mail", "You have  unread mails", icons.GEO_CLI)
        n.add_action('action', 'Show Action', self.notification_handler)
        n.set_urgency(Notify.Urgency.CRITICAL)
        n.show()
        # Notification ref has to be held for the action to work.
        return n

    def show_quick_notification(self, body, title='geo-cli'):
        if not geo.notifications_are_allowed():
            return
        n = Notify.Notification.new(title, body, icons.GEO_CLI)
        n.set_urgency(Notify.Urgency.LOW)
        n.set_timeout(300)
        n.show()
        GLib.timeout_add(1500, n.close)

    def notification_handler(self, notification=None, action=None, data=None):
        print('notification_handler pressed')

    def build_menu(self, menu):
        item_geo_header = Gtk.MenuItem(label='-------------------- geo-cli --------------------')
        item_geo_header.set_sensitive(False)
        menu.append(item_geo_header)
        sep = Gtk.SeparatorMenuItem()
        menu.append(sep)

        item_running_db = menus.RunningDbMenuItem(self)
        self.item_running_db = item_running_db

        item_databases = self.get_database_item()
        self.item_databases = item_databases
        item_create_db = self.get_create_db_item()
        item_auto_switch_db_toggle = AutoSwitchDbMenuItem(self)
        self.item_auto_switch_db_toggle = item_auto_switch_db_toggle

        item_run_analyzers = self.get_analyzer_item()

        item_npm = Gtk.MenuItem(label='npm install')
        item_npm.connect('activate', lambda _: geo.run_in_terminal('init npm'))

        item_quit = Gtk.MenuItem(label='Quit')
        item_quit.connect('activate', self.quit)

        item_help = menus.HelpMenuItem(self)
        # item_help = self.build_help_item()

        menu.append(item_running_db)

        menu.append(item_databases)
        menu.append(item_create_db)
        menu.append(item_auto_switch_db_toggle)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_run_analyzers)
        menu.append(item_npm)
        menu.append(menus.AccessRequestMenuItem(self))
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_help)
        menu.append(item_quit)

        item_update = self.build_update_item()
        menu.append(item_update)
        # item_label = Gtk.MenuItem(label="Test_label_1[a_a_b]")
        # menu.append(item_label)
        menu.show_all()

    # def build_help_item(self):
    #     help = Gtk.MenuItem(label="Help")
    #     submenu = Gtk.Menu()
    #
    #     item_disable = Gtk.MenuItem(label='Disable')
    #     item_disable.connect('activate', self.show_disable_dialog)
    #
    #     item_readme = Gtk.MenuItem(label='View Readme')
    #     item_readme.connect('activate', self.show_readme)
    #
    #     submenu.append(item_readme)
    #     submenu.append(item_disable)
    #     help.set_submenu(submenu)
    #     return help

    @staticmethod
    def get_create_db_item():
        item = Gtk.MenuItem(label='Create Database')
        item.connect('activate', lambda s: geo.run_in_terminal('db start -p'))
        return item

    def build_update_item(self):
        return menus.UpdateMenuItem(self, UPDATE_INTERVAL)

    # def show_readme(self, source):
    #     webbrowser.open('https://git.geotab.com/dawsonmyers/geo-cli', new=2)

    # def disable(self):
    #     geo('indicator disable')
    #     self.quit(None)

    def build_box(self):
        self.box_outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.label = Gtk.Label()
        self.label.set_text("geo-cli")
        self.label.set_justify(Gtk.Justification.CENTER)
        self.box_outer.pack_start(self.label, True, True, 0)
        # self.box_outer.append(self.label)
        return self.box_outer

    @staticmethod
    def quit(source=None):
        Gtk.main_quit()

    # def show_disable_dialog(self, widget):
    #     dialog = Gtk.MessageDialog(
    #         transient_for=None,
    #         flags=0,
    #         message_type=Gtk.MessageType.WARNING,
    #         buttons=Gtk.ButtonsType.OK_CANCEL,
    #         text="Disable geo-cli app indicator?",
    #     )
    #     dialog.format_secondary_text(
    #         "The indicator can be re-enabled by running 'geo indicator enable' in a terminal."
    #     )
    #     response = dialog.run()
    #     if response == Gtk.ResponseType.OK:
    #         print("WARN dialog closed by clicking OK button")
    #         self.disable()
    #     elif response == Gtk.ResponseType.CANCEL:
    #         print("WARN dialog closed by clicking CANCEL button")
    #
    #     dialog.destroy()

    def get_database_item(self):
        item_databases = Gtk.MenuItem(label='Databases')
        db_submenu = menus.DbMenu(self)
        item_databases.set_submenu(db_submenu)
        return item_databases

    @staticmethod
    def get_analyzer_item():
        item = Gtk.MenuItem(label='Run Analyzers')
        item.connect('activate', lambda _: geo.run_in_terminal('analyze -b'))
        return item


class MainMenu(Gtk.Menu):
    def __init__(self, app):
        super().__init__()
        self.items = set()

    def append(self, item):
        if item in self.items:
            return
        self.items.add(item)
        item.show()
        super().append(item)

    def remove(self, item):
        if item not in self.items:
            return
        self.items.remove(item)
        item.hide()
        super().remove(item)


# class DbMenu(Gtk.Menu):
#     def __init__(self, app):
#         self.app = app
#         self.item_running_db = app.item_running_db
#         super().__init__()
#         self.db_names = set(geo.get_geo_db_names())
#         self.items = dict()
#         self.build_db_items()
#         GLib.timeout_add(2 * 1000, self.db_monitor)
#
#     def build_db_items(self):
#         dbs = geo.get_geo_db_names()
#         self.db_names = set(dbs)
#         for db in dbs:
#             db_item = DbMenuItem(db, self.app)
#             self.items[db] = db_item
#             self.append(db_item)
#         self.queue_draw()
#
#     def remove_items(self):
#         for item in self.get_children():
#             if item.name is None: continue
#             self.remove(item)
#             self.items.pop(item)
#             item.destroy()
#         self.queue_draw()
#
#     def db_monitor(self):
#         new_db_names = set(geo.get_geo_db_names())
#         if new_db_names != self.db_names:
#             self.update_items(new_db_names)
#         self.db_names = new_db_names
#         return True
#
#     def update_items(self, new_db_names):
#         removed = self.db_names - new_db_names
#         print('Removed: ' + str(removed))
#         added = new_db_names - self.db_names
#         print('Added: ' + str(added))
#         for db in removed:
#             if db not in self.items: continue
#             item = self.items.pop(db)
#             item.hide()
#             item.set_sensitive(False)
#             self.remove(item)
#         for db in added:
#             if db in self.items: continue
#             item = DbMenuItem(db, self.app)
#             self.append(item)
#             item.show()
#             # self.show_all()
#             self.items[db] = item
#         self.queue_draw()
#
#
# class DbMenuItem(Gtk.MenuItem):
#     def __init__(self, name, app):
#         self.app = app
#         self.item_running_db = app.item_running_db
#         super().__init__(label=name)
#         self.name = name
#         self.set_label(name)
#         self.submenu = Gtk.Menu()
#         self.item_start = Gtk.MenuItem(label='Start')
#         self.item_remove = Gtk.MenuItem(label='Remove')
#         self.submenu.append(self.item_start)
#         self.submenu.append(self.item_remove)
#         self.item_remove.connect('activate', self.remove_geo_db)
#         self.item_start.connect('activate', self.start_geo_db)
#         self.set_submenu(self.submenu)
#         self.show_all()
#
#
#     def remove_geo_db(self, src=None):
#         if '(removing)' in self.name: return
#         self.set_label(self.name + ' (removing)')
#         def run():
#             geo('db rm ' + self.name)
#             self.app.item_databases.get_submenu().remove(self)
#             self.set_sensitive(False)
#             return False
#         GLib.timeout_add(5, lambda: run())
#
#     def start_geo_db(self, obj):
#         self.item_running_db.set_label('Starting DB...')
#         def run_after_label_update():
#             return_msg = geo.start_db(self.name)
#             if "Port error" in return_msg:
#                 geo.run_in_terminal('db start ' + self.name)
#             running_db = geo.get_running_db_name()
#             if self.name != running_db:
#                 self.item_running_db.set_label('Failed to start DB')
#             else:
#                 self.item_start.set_sensitive(False)
#                 self.item_running_db.set_db_label(get_running_db_label_text(self.name))
#
#         # Add timeout to allow event loop to update label name while the db start command runs.
#         GLib.timeout_add(10, run_after_label_update)

class AutoSwitchDbMenuItem(Gtk.CheckMenuItem):
    def __init__(self, app):
        super().__init__(label='Auto-Switch DB')
        self.app = app
        self.enabled = geo.get_config('AUTO_SWITCH_DB') != 'false'
        if not self.enabled:
            self.set_label("Disable DB Auto-Switch")
        self.set_active(self.enabled)
        self.connect('toggled', self.handle_toggle)
        self.show_all()
        GLib.timeout_add(1000, self.monitor)

    def handle_toggle(self, src):
        auto_switch_db_setting = geo.get_config('AUTO_SWITCH_DB') != 'false'
        new_state = not auto_switch_db_setting
        new_state_str = 'true' if new_state else 'false'
        geo.set_config('AUTO_SWITCH_DB', new_state_str)
        self.enabled = new_state
        self.set_active(new_state)

    def monitor(self):
        auto_switch_db_setting = geo.get_config('AUTO_SWITCH_DB') != 'false'
        if self.enabled != auto_switch_db_setting:
            self.enabled = auto_switch_db_setting
            self.set_active(auto_switch_db_setting)


# class RunningDbMenuItem(Gtk.MenuItem):
#     def __init__(self, app):
#         super().__init__(label='Checking for DB')
#         self.app = app
#         self.running_db = ''
#         self.current_myg_release_db = geo.try_get_db_name_for_current_myg_release()
#         self.auto_switch_db_based_on_myg_release = geo.get_config('AUTO_SWITCH_DB') != 'false'
#         self.db_monitor()
#         self.stop_menu = Gtk.Menu()
#         item_stop_db = Gtk.MenuItem(label='Stop')
#         item_ssh = Gtk.MenuItem(label='SSH')
#         item_psql = Gtk.MenuItem(label='PSQL')
#         item_stop_db.connect('activate', self.stop_db)
#         item_ssh.connect('activate', lambda _: geo.run_in_terminal('db ssh'))
#         item_psql.connect('activate', lambda _: geo.run_in_terminal('db psql'))
#         self.stop_menu.append(item_stop_db)
#         self.stop_menu.append(item_ssh)
#         self.stop_menu.append(item_psql)
#         self.set_submenu(self.stop_menu)
#         self.show_all()
#         GLib.timeout_add(1000, self.db_monitor)
#
#     def stop_db(self, source):
#         self.set_db_label('Stopping DB...')
#         self.set_sensitive(False)
#         def run():
#             geo.stop_db()
#             self.set_db_label(get_running_db_none_label_text())
#
#         GLib.timeout_add(10, run)
#
#     def set_db_label(self, text):
#         # print('Running db text: ' + text)
#         self.set_label(text)
#         # print('Set label: ' + self.get_label())
#
#         # self.set_use_underline(True)
#         self.show()
#         self.queue_draw()
#
#     def db_monitor(self):
#         # poll for running db name, if it doesn't equal self
#         cur_running_db = geo.get_running_db_name()
#         if cur_running_db == self.running_db and 'Stopping' in self.get_label():
#             pass
#         elif len(cur_running_db) == 0:
#             if 'Failed' in self.get_label():
#                 self.set_sensitive(False)
#                 self.app.icon_manager.set_icon(ICON_ORANGE)
#             else:
#                 self.set_sensitive(False)
#                 self.app.icon_manager.set_icon(ICON_RED)
#                 self.set_db_label('No DB running')
#         elif self.running_db != cur_running_db:
#             self.set_sensitive(True)
#             label = get_running_db_label_text(cur_running_db)
#             self.set_db_label(label)
#             # self.set_db_label(get_running_db_label_markup(cur_running_db))
#             self.app.icon_manager.set_icon(ICON_GREEN)
#             self.app.show_quick_notification('DB Started: ' + cur_running_db)
#         self.running_db = cur_running_db
#         self.update_db_start_items()
#         self.change_db_if_myg_release_changed()
#         return True
#
#     def change_db_if_myg_release_changed(self):
#         if self.app.item_auto_switch_db_toggle and not self.app.item_auto_switch_db_toggle.enabled:
#             return
#         cur_db_release = geo.try_get_db_name_for_current_myg_release()
#         if cur_db_release is not None and cur_db_release != self.current_myg_release_db:
#             if self.current_myg_release_db is not None:
#                 geo.start_db(cur_db_release)
#             self.current_myg_release_db = cur_db_release
#
#     def update_db_start_items(self):
#         if self.app.item_databases is None: return
#         for item in self.app.item_databases.get_submenu().items.values():
#             if item.name == self.running_db:
#                 item.item_start.set_sensitive(False)
#             else:
#                 item.item_start.set_sensitive(True)
#
#
# class UpdateMenuItem(Gtk.MenuItem):
#     def __init__(self, app):
#         global UPDATE_INTERVAL
#         super().__init__(label='Checking for updates...')
#         self.update_available = False
#         self.app = app
#         self.separator = Gtk.SeparatorMenuItem()
#         self.connect('activate', lambda _: geo.update())
#         self.app.menu.append(self.separator)
#         self.app.menu.append(self)
#
#         # Run once later so that 'Checking for updates' is initially displayed.
#         GLib.timeout_add(2000, lambda: not self.set_update_status())
#         self.set_update_status()
#         GLib.timeout_add(UPDATE_INTERVAL, self.set_update_status)
#
#     def set_update_status(self, source=None):
#         self.update_available = geo.is_update_available()
#         if self.update_available:
#             self.set_label('●   Update Now')
#             self.app.menu.append(self.separator)
#             self.app.menu.append(self)
#             self.set_sensitive(True)
#             self.app.menu.show_all()
#             self.app.icon_manager.set_update_available(True)
#             self.show()
#         else:
#             self.set_label('geo-cli is up-to-date')
#             self.app.icon_manager.set_update_available(False)
#             self.set_sensitive(False)
#             self.app.menu.remove(self.separator)
#             self.app.menu.remove(self)
#             self.hide()
#         return True
#
#
#     def show_submenu(self, source):
#         self.submenu.show_all()


class DialogExample(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(title="My Dialog", transient_for=parent, flags=0)
        self.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.OK
        )
        self.set_default_size(150, 100)
        label = Gtk.Label(label="This is a dialog to display additional information")
        box = self.get_content_area()
        box.add(label)
        self.show_all()

# def get_running_db_label_text(db):
#     return 'Running DB [%s]' % db
#
#
# def get_running_db_none_label_text():
#     return 'Running DB [None]'


def main():
    indicator = IndicatorApp()
    geo.try_start_last_db()
    Gtk.main()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
