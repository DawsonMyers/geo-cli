import gi
import os
import signal
import time
import subprocess
import webbrowser

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
# gi.require_version('Notify', '0.7')

from gi.repository import Gtk, GLib
from gi.repository import AppIndicator3 as appindicator

# from gi.repository import Notify as notify

APPINDICATOR_ID = 'geo-cli'

UPDATE_INTERVAL = 10*60*1000

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
GEO_SRC_DIR = os.path.dirname(BASE_DIR)
GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '

icon_green_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green.svg')
icon_green_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green-update.svg')
icon_grey_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey.svg')
icon_grey_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey-update.svg')
icon_red_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red.svg')
icon_red_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red-update.svg')
icon_spinner_path = os.path.join(BASE_DIR, 'res', 'geo-spinner.svg')

indicator = None
ICON_RED = 'red'
ICON_GREEN = 'green'


class IconManager:
    def __init__(self, indicator):
        self.indicator = indicator
        self.cur_icon = ICON_RED
        self.update_available = False
        self.update_icon()

    def set_update_available(self, update_available):
        self.update_available = update_available
        self.update_icon()

    def update_icon(self):
        if self.cur_icon == ICON_RED:
            img_path = icon_red_update_path if self.update_available else icon_red_path
            self.indicator.set_icon_full(img_path, "geo-cli: No DB running")
        elif self.cur_icon == ICON_GREEN:
            img_path = icon_green_update_path if self.update_available else icon_green_path
            self.indicator.set_icon_full(img_path, 'geo-cli: DB running')

    def set_icon(self, icon_type):
        icon_changed = self.cur_icon is not icon_type
        self.cur_icon = icon_type
        if icon_changed:
            self.update_icon()


class IndicatorApp(object):
    def __init__(self):
        self.indicator = appindicator.Indicator.new(APPINDICATOR_ID, icon_green_path, appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title('geo-cli')
        self.db_submenu = None
        self.item_databases = None
        self.item_running_db = None
        self.icon_manager = IconManager(self.indicator)
        self.menu = MainMenu(self)
        self.build_menu(self.menu)
        self.indicator.set_menu(self.menu)
        # Gtk.main()

    def build_menu(self, menu):
        item_geo_header = Gtk.MenuItem(label='-------------------- geo-cli --------------------')
        item_geo_header.set_sensitive(False)
        menu.append(item_geo_header)
        sep = Gtk.SeparatorMenuItem()
        menu.append(sep)

        item_running_db = RunningDbMenuItem(self)
        self.item_running_db = item_running_db

        item_databases = self.get_database_item()
        self.item_databases = item_databases
        item_create_db = self.get_create_db_item()

        item_run_analyzers = self.get_analyzer_item()

        item_quit = Gtk.MenuItem(label='Quit')
        item_quit.connect('activate', self.quit)

        item_help = self.build_help_item()

        menu.append(item_running_db)

        menu.append(item_databases)
        menu.append(item_create_db)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_run_analyzers)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_help)
        menu.append(item_quit)

        item_update = self.build_update_item()
        menu.append(item_update)
        menu.show_all()



    @staticmethod
    def get_create_db_item():
        item = Gtk.MenuItem(label='Create Database')
        item.connect('activate', lambda s: run_in_terminal(get_geo_cmd('db start -p')))
        return item

    def build_help_item(self):
        help = Gtk.MenuItem(label="Help")
        submenu = Gtk.Menu()

        item_disable = Gtk.MenuItem(label='Disable')
        item_disable.connect('activate', self.show_disable_dialog)

        item_readme = Gtk.MenuItem(label='View Readme')
        item_readme.connect('activate', self.show_readme)

        submenu.append(item_readme)
        submenu.append(item_disable)
        help.set_submenu(submenu)
        return help

    def build_update_item(self):
        return UpdateMenuItem(self)

    def show_readme(self, source):
        webbrowser.open('https://git.geotab.com/dawsonmyers/geo-cli', new=2)

    def disable(self):
        geo('indicator disable')
        self.quit(None)

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

    def show_disable_dialog(self, widget):
        dialog = Gtk.MessageDialog(
            transient_for=None,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Disable geo-cli app indicator?",
        )
        dialog.format_secondary_text(
            "The indicator can be re-enabled by running 'geo indicator enable' in a terminal."
        )
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            print("WARN dialog closed by clicking OK button")
            self.disable()
        elif response == Gtk.ResponseType.CANCEL:
            print("WARN dialog closed by clicking CANCEL button")

        dialog.destroy()

    def get_database_item(self):
        item_databases = Gtk.MenuItem(label='Databases')
        db_submenu = DbMenu(self)
        item_databases.set_submenu(db_submenu)
        return item_databases

    @staticmethod
    def get_analyzer_item():
        item = Gtk.MenuItem(label='Run Analyzers')
        item.connect('activate', lambda _: run_in_terminal(get_geo_cmd('analyze -b')))
        return item


class MainMenu(Gtk.Menu):
    def __init__(self, app):
        super().__init__()
        self.items = set()

    def append(self, item):
        if item in self.items: return
        self.items.add(item)
        item.show()
        super().append(item)

    def remove(self, item):
        if item not in self.items: return
        self.items.remove(item)
        item.hide()
        super().remove(item)


class DbMenu(Gtk.Menu):
    def __init__(self, app):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__()
        self.db_names = set(get_geo_db_names())
        self.items = dict()
        self.build_db_items()
        GLib.timeout_add(2 * 1000, self.db_monitor)

    def build_db_items(self):
        dbs = get_geo_db_names()
        self.db_names = set(dbs)
        for db in dbs:
            db_item = DbMenuItem(db, self.app)
            self.items[db] = db_item
            self.append(db_item)
        self.queue_draw()

    def remove_items(self):
        for item in self.get_children():
            if item.name is None: continue
            self.remove(item)
            self.items.pop(item)
            item.destroy()
        self.queue_draw()

    def db_monitor(self):
        new_db_names = set(get_geo_db_names())
        if new_db_names != self.db_names:
            self.update_items(new_db_names)
        self.db_names = new_db_names
        return True

    def update_items(self, new_db_names):
        removed = self.db_names - new_db_names
        print('Removed: ' + str(removed))
        added = new_db_names - self.db_names
        print('Added: ' + str(added))
        for db in removed:
            if db not in self.items: continue
            item = self.items.pop(db)
            item.hide()
            item.set_sensitive(False)
            self.remove(item)
        for db in added:
            if db in self.items: continue
            item = DbMenuItem(db, self.app)
            self.append(item)
            item.show()
            # self.show_all()
            self.items[db] = item
        self.queue_draw()


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


class DbMenuItem(Gtk.MenuItem):
    def __init__(self, name, app):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__(label=name)
        self.name = name
        self.set_label(name)
        self.submenu = Gtk.Menu()
        self.item_start = Gtk.MenuItem(label='Start')
        self.item_remove = Gtk.MenuItem(label='Remove')
        self.submenu.append(self.item_start)
        self.submenu.append(self.item_remove)
        self.item_remove.connect('activate', self.remove_geo_db)
        self.item_start.connect('activate', self.start_geo_db)
        self.set_submenu(self.submenu)
        self.show_all()


    def remove_geo_db(self, src=None):
        if '(removing)' in self.name: return
        self.set_label(self.name + ' (removing)')
        def run():
            geo('db rm ' + self.name)
            self.app.item_databases.get_submenu().remove(self)
            self.set_sensitive(False)
            return False
        GLib.timeout_add(5, lambda: run())

    def start_geo_db(self, obj):
        self.item_running_db.set_label('Starting db...')
        def run_after_label_update():
            start_db(self.name)
            running_db = get_running_db_name()
            if self.name != running_db:
                self.item_running_db.set_label('Failed to start db')
            else:
                self.item_start.set_sensitive(False)
                self.item_running_db.set_db_label_markup(get_running_db_label_markup(self.name))

        # Add timeout to allow event loop to update label name while the db start command runs.
        GLib.timeout_add(10, run_after_label_update)


class RunningDbMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__(label='Checking for DB')
        self.app = app
        self.running_db = ''
        self.db_monitor()
        self.stop_menu = Gtk.Menu()
        item_stop_db = Gtk.MenuItem(label='Stop')
        item_stop_db.connect('activate', stop_db)
        self.stop_menu.append(item_stop_db)
        self.set_submenu(self.stop_menu)

        GLib.timeout_add(1000, self.db_monitor)

    def stop_db(self, source):
        self.set_db_label('Stopping DB...')

        def run():
            stop_db()
            self.set_db_label(get_running_db_none_label_text())

        GLib.timeout_add(10, run)

    def set_db_label(self, text):
        self.set_label(text)
        self.queue_draw()

    def set_db_label_markup(self, text):
        label = self.get_children()[0]
        label.set_markup(text)
        self.queue_draw()

    def no_op(self, source):
        a = 1

    def show_stop_menu(self, source):
        # print('stop menu clicked')
        if not self.is_db_running: return
        self.stop_menu.show_all()

    def db_monitor(self):
        # poll for running db name, if it doesn't equal self
        cur_running_db = get_running_db_name()
        if len(cur_running_db) == 0:
            self.set_sensitive(False)
            self.app.icon_manager.set_icon(ICON_RED)
            self.set_db_label('No DB running')
        elif self.running_db != cur_running_db:
            self.set_sensitive(True)
            self.set_db_label(get_running_db_label_markup(cur_running_db))
            self.app.icon_manager.set_icon(ICON_GREEN)
        self.running_db = cur_running_db
        self.update_db_start_items()
        return True

    def update_db_start_items(self):
        if self.app.item_databases is None: return
        for item in self.app.item_databases.get_submenu().items.values():
            if item.name == self.running_db:
                item.item_start.set_sensitive(False)
            else:
                item.item_start.set_sensitive(True)


class UpdateMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        global UPDATE_INTERVAL
        super().__init__(label='Checking for updates...')
        self.update_available = False
        self.app = app
        self.separator = Gtk.SeparatorMenuItem()
        self.connect('activate', self.update_geo_cli)
        self.app.menu.append(self.separator)
        self.app.menu.append(self)

        # Run once later so that 'Checking for updates' is initially displayed.
        GLib.timeout_add(2000, lambda: not self.set_update_status())
        GLib.timeout_add(UPDATE_INTERVAL, self.set_update_status)

    def set_update_status(self, source=None):
        update_available = is_update_available()
        self.update_available = update_available
        if update_available:
            self.set_label('●   Update Now')
            self.app.menu.append(self.separator)
            self.app.menu.append(self)
            self.set_sensitive(True)
            self.app.menu.show_all()
            self.app.icon_manager.set_update_available(True)
            self.show()
        else:
            self.set_label('geo-cli is up-to-date')
            self.app.icon_manager.set_update_available(False)
            self.set_sensitive(False)
            self.app.menu.remove(self.separator)
            self.app.menu.remove(self)
            self.hide()
        return True

    def update_geo_cli(self, source=None):
        update_cmd = get_geo_cmd('update')
        run_in_terminal(update_cmd, title='geo-cli Update')

    def no_op(self, source):
        pass

    def show_submenu(self, source):
        self.submenu.show_all()


def try_start_last_db():
    last_db = get_geo_setting('LAST_DB_VERSION')
    if last_db is not None:
        start_db(last_db)

def get_geo_cmd(geo_cmd):
    return GEO_CMD_BASE + geo_cmd


def run_in_terminal(cmd_to_run, title=''):
    if len(title) > 0:
        title = "--title='%s'" % title
    cmd = "gnome-terminal %s --geometry=80x30 -- bash -c \"bash %s; cd $HOME; exec bash\"" % (title, cmd_to_run)
    os.system(cmd)


def get_geo_setting(key):
    value = geo('get ' + key)
    return value


def is_update_available():
    ret = geo('dev update-available')
    return ret == 'true'


def get_running_db_label_text(db):
    return 'Running DB [%s]' % db


def get_running_db_none_label_text():
    return 'Running DB [None]'


def get_running_db_label_markup(db):
    return 'Running DB [%s]' % db
    # return '<span size="smaller">Running DB:</span>\n' + '<span>   [<b>%s</b>]</span>' % db


def get_running_db_none_label_markup():
    return 'Running DB [None]'
    # return '<span size="smaller">Running DB:</span>\n' + '<span foreground="grey"><b>    [None]</b></span>'


def get_geo_db_names():
    cmd = 'docker container ls --filter name="geo_cli_db_"  -a --format="{{ .Names }}"'
    full_names = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
    names = full_names.replace('geo_cli_db_postgres_', '')
    full_names_a = full_names.split('\n')
    names_a = names.split('\n')
    names_a.sort(reverse=True)
    return names_a


def get_running_db_name():
    cmd = 'docker container ls --filter name="geo_cli_db_" --filter status=running  -a --format="{{ .Names }}"'
    full_name = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
    name = full_name.replace('geo_cli_db_postgres_', '')
    return name


def run_shell_cmd(cmd):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]


def run_cmd_and_wait(cmd):
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    print(result)


def start_db(name):
    geo('db start ' + name)


def stop_db(arg=None):
    geo('db stop')
    # print('Stopping DB')


def geo(arg_str):
    geo_path = GEO_SRC_DIR + '/geo-cli.sh '
    cmd = geo_path + ' --raw-output ' + arg_str
    process = subprocess.Popen("bash %s" % (cmd), shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    # print(result)
    return result[0]

def main():
    indicator = IndicatorApp()
    try_start_last_db()
    Gtk.main()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
