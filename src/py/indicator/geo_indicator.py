
import os
import signal
import time
import subprocess

import sys
# Add local packages to python search path.
sys.path.insert(0, os.path.join(sys.path[0], '..'))

try:
    import setproctitle
    setproctitle.setproctitle('geo-cli')
except ImportError as e:
    pass

from indicator import *
from indicator import icons, menus
from common import geo

APPINDICATOR_ID = 'geo.indicator'

# Check for updates every 10 minutes.
UPDATE_INTERVAL = 10*60*1000


class IndicatorApp(object):
    notification = None
    notifications_allowed = False
    myg_release = None
    db_for_myg_release = None
    db = None
    state = {}
    last_notification_time = 0

    def __init__(self):
        Notify.init(APPINDICATOR_ID)
        self.indicator = appindicator.Indicator.new(APPINDICATOR_ID, icons.GREEN_PATH, appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title('geo-cli')
        # self.indicator.set_label('geo-cli', 'geo-cli')
        self.db_submenu = None
        self.item_databases = None
        self.item_running_db = None
        self.item_auto_switch_db_toggle = None
        self.icon_manager = icons.IconManager(self.indicator)
        self.show_quick_notification('Starting up...')
        self.menu = MainMenu(self)
        self.build_menu(self.menu)
        self.indicator.set_menu(self.menu)

    def get_state(self, key):
        return self.state[key] if key in self.state else None

    def set_state(self, key, value):
        self.state[key] = value

    def show_notification_with_action(self, body, title='geo-cli', timeout=1500, urgency=None):
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

        current_time = util.current_time_ms()
        # Make sure only one notification is occuring at a time.
        if current_time - self.last_notification_time < 1500:
            GLib.timeout_add(1500, lambda: self.show_quick_notification(body, title))
            return
        self.last_notification_time = current_time

        n = Notify.Notification.new(title, body, icons.GEO_CLI)
        n.set_urgency(Notify.Urgency.LOW)
        n.set_timeout(300)
        n.show()

        def close():
            n.close()
        GLib.timeout_add(1500, close)

    def show_notification(self, body, title='geo-cli', timeout=1500):
        if not geo.notifications_are_allowed():
            return

        current_time = util.current_time_ms()
        # Make sure only one notification is occuring at a time.
        if current_time - self.last_notification_time < 1500:
            GLib.timeout_add(1500, lambda: self.show_notification(body, title, timeout))
            return
        self.last_notification_time = current_time

        n = Notify.Notification.new(title, body, icons.GEO_CLI)
        n.set_urgency(Notify.Urgency.LOW)
        n.set_timeout(timeout)
        n.show()

        def close():
            n.close()
        GLib.timeout_add(timeout, close)

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
        item_npm.connect('activate', lambda _: geo.run_in_terminal('init npm -c', stay_open_after=False))
        item_id = Gtk.MenuItem(label='Convert Long/Guid Ids')
        item_id_clipboard = Gtk.MenuItem(label='Convert Id From Clipboard')
        item_run_tests = Gtk.MenuItem(label='Run Tests')
        # Run 'geo id -i' in terminal. This causes geo id to run interactively (-i), first trying to convert the contents of the clipboard.
        item_id.connect('activate', lambda _: geo.run_in_terminal('id -i'))
        item_id_clipboard.connect('activate', lambda _: geo.run_in_terminal('id -c', stay_open_after=False))
        item_run_tests.connect('activate', lambda _: geo.run_in_terminal('test -i', stay_open_after=True))
        # Configure the id item to be activated when the app indicator is middle clicked on.
        self.indicator.set_secondary_activate_target(item_id_clipboard)

        item_quit = Gtk.MenuItem(label='Quit')
        item_quit.connect('activate', self.quit)

        item_help = menus.HelpMenuItem(self)

        menu.append(item_running_db)

        menu.append(item_databases)
        menu.append(item_create_db)
        menu.append(item_auto_switch_db_toggle)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_run_analyzers)
        menu.append(item_npm)
        menu.append(item_id)
        menu.append(item_id_clipboard)
        menu.append(menus.AccessRequestMenuItem(self))
        menu.append(item_run_tests)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_help)
        menu.append(item_quit)

        item_update = self.build_update_item()
        menu.append(item_update)
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

    def get_database_item(self):
        item_databases = Gtk.MenuItem(label='Databases')
        db_submenu = menus.DbMenu(self)
        item_databases.set_submenu(db_submenu)
        return item_databases

    @staticmethod
    def get_analyzer_item():
        menu = Gtk.Menu()
        item = Gtk.MenuItem(label='Run Analyzers')
        item_run_all = Gtk.MenuItem(label='All')
        item_choose = Gtk.MenuItem(label='Choose')
        item_previous = Gtk.MenuItem(label='Previous')
        item_run_all.connect('activate', lambda _: geo.run_in_terminal('analyze -b -a'))
        item_choose.connect('activate', lambda _: geo.run_in_terminal('analyze -b'))
        item_previous.connect('activate', lambda _: geo.run_in_terminal('analyze -b -'))
        menu.append(item_run_all)
        menu.append(item_choose)
        menu.append(item_previous)
        item.set_submenu(menu)
        menu.show_all()
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