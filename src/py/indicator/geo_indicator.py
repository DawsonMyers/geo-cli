
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
    notifications_allowed = False
    myg_release = None
    db_for_myg_release = None
    db = None

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
        item_auto_switch_db_toggle = menus.AutoSwitchDbMenuItem(self)
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

    @staticmethod
    def get_create_db_item():
        item = Gtk.MenuItem(label='Create Database')
        item.connect('activate', lambda s: geo.run_in_terminal('db start -p'))
        return item

    def build_update_item(self):
        return menus.UpdateMenuItem(self, UPDATE_INTERVAL)

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


def main():
    indicator = IndicatorApp()
    geo.try_start_last_db()
    Gtk.main()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
