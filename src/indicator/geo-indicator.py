import gi
import os
import signal
import time
import subprocess
import webbrowser

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')

from gi.repository import Gtk, GLib
from gi.repository import AppIndicator3 as appindicator
from gi.repository import Notify as notify

APPINDICATOR_ID = 'geo-cli'

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
print(BASE_DIR)
GEO_SRC_DIR = os.path.dirname(BASE_DIR)
print(GEO_SRC_DIR)
GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '

icon_green_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green.svg')
icon_green_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green-update.svg')
icon_grey_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey.svg')
icon_grey_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey-update.svg')
icon_red_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red.svg')
icon_red_update_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red-update.svg')
print(icon_green_path)

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
            self.indicator.set_icon(img_path)
        elif self.cur_icon == ICON_GREEN:
            img_path = icon_green_update_path if self.update_available else icon_green_path
            self.indicator.set_icon(img_path)

    def set_icon(self, icon_type):
        icon_changed = self.cur_icon is not icon_type
        self.cur_icon = icon_type
        if icon_changed:
            self.update_icon()


class Indicator(object):
    def __init__(self):
        self.indicator = appindicator.Indicator.new(APPINDICATOR_ID, icon_green_path, appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
        self.icon_manager = IconManager(self.indicator)
        # indicator.set_icon(icon_green_path)
        # self.ind.set_icon(icon_green_path)
        # indicator.set_icon_full(icon_green_path, '')
        self.menu = Gtk.Menu()
        self.build_menu(self.menu)
        self.indicator.set_menu(self.menu)
        # self.ind.set_menu(self.build_menu())
        Gtk.main()

    def build_menu(self, menu):
        item_running_db = RunningDbMenuItem(self)
        item_running_db.connect('activate', item_running_db.show_stop_menu)
        item_running_db.set_submenu(item_running_db.stop_menu)
        # item_separator = Gtk.SeparatorMenuItem()

        # item_disable = Gtk.MenuItem(label='Disable')
        # self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        # label = Gtk.Label()
        # label.set_text('Box Label')
        # self.box.pack_start(label, True, True, 5)
        # item_disable.append(self.box)
        item_start_db = Gtk.MenuItem(label='Start DB')
        db_submenu = DbMenu(item_running_db) #self.build_db_submenu(item_running_db)
        self.db_submenu = db_submenu
        item_start_db.connect('activate', lambda _: self.show_db_menu())
        # item_start_db.connect('activate', lambda _: db_submenu.show_all())
        item_start_db.set_submenu(db_submenu)

        item_quit = Gtk.MenuItem(label='Quit')
        item_quit.connect('activate', self.quit)
        # item_disable.connect('activate', self.disable)
        # self.item_disable = item_disable

        item_update = self.build_update_item()
        item_help = self.build_help_item()

        menu.append(item_running_db)
        menu.append(Gtk.SeparatorMenuItem())
        # menu.append(item_disable)

        menu.append(item_start_db)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_update)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_help)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_quit)
        menu.show_all()

    def show_db_menu(self):
        print('show_db_menu')
        self.db_submenu.show_all()


    def build_help_item(self):
        help = Gtk.MenuItem(label="Help")
        submenu = Gtk.Menu()
        help.connect('activate', lambda w: submenu.show_all())

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

    def build_db_submenu(self, item_running_db):
        menu = Gtk.Menu()
        db_names = get_geo_db_names()
        for n in db_names:
            # print(n)
            db_item = DbMenuItem(n, item_running_db)
            menu.append(db_item)
        return menu

    def build_box(self):
        self.box_outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.label = Gtk.Label()
        self.label.set_text("geo-cli")
        self.label.set_justify(Gtk.Justification.CENTER)
        self.box_outer.pack_start(self.label, True, True, 0)
        # self.box_outer.append(self.label)
        return self.box_outer

    def quit(self, source):
        Gtk.main_quit()

    # def disable(self, source):
    #     self.ind.set_icon(icon_red_path)
    #     cmd = 'docker ps --filter name="geo_cli_db_" --filter status=running -a --format="{{ .Names }}"'
    #     output = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    #     # Trim off new line.
    #     name = output.stdout[0:-1]
    #     self.item_disable.set_label(name)
    #     print(output.stdout)

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

class DbMenu(Gtk.Menu):
    def __init__(self, item_running_db):
        self.item_running_db = item_running_db
        super().__init__()
        self.db_names = set(get_geo_db_names())
        self.item_lookup = dict()
        self.build_db_items()
        GLib.timeout_add(5*1000, self.db_monitor)

    def build_db_items(self):
        self.db_names = set(get_geo_db_names())
        self.item_lookup = {}
        for n in self.db_names:
            # print(n)
            db_item = DbMenuItem(n, self.item_running_db)
            self.item_lookup[n] = db_item
            self.append(db_item)
        self.queue_draw()

    def remove_items(self):
        for item in self.get_children():
            if item.name is None: continue
            self.remove(item)
            item.destroy()
        self.queue_draw()

    def db_monitor(self):
        new_db_names = set(get_geo_db_names())
        if new_db_names != self.db_names:
            self.update_items(new_db_names)
            # self.remove_items()
            # self.build_db_items()
        self.db_names = new_db_names
        return True

    def update_items(self, new_db_names):
        removed = self.db_names - new_db_names
        print('Removed: ' + str(removed))
        added = new_db_names - self.db_names
        print('Added: ' + str(added))
        for db in removed:
            if db not in self.item_lookup: continue
            item = self.item_lookup.pop(db)
            self.remove(item)
        for db in added:
            if db in self.item_lookup: continue
            item = DbMenuItem(db, self.item_running_db)
            self.item_lookup[db] = item
            self.append(item)
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
    def __init__(self, name, item_running_db):
        self.item_running_db = item_running_db
        super().__init__(label=name)
        self.name = name
        self.set_label(name)
        self.connect('activate', self.start_geo_db)

    def start_geo_db(self, obj):
        # self.item_running_db.set_label('Starting db...')
        self.item_running_db.set_db_label_markup('<span foreground="green">Starting db...</span>')

        def run_after_label_update():
            start_db(self.name)
            running_db = get_running_db_name()
            if self.name != running_db:
                self.item_running_db.set_label('Failed to start db')
            else:
                # self.item_running_db.set_label('Running DB: ' + self.name)
                self.item_running_db.set_db_label_markup(get_running_db_label_markup(self.name))

        # Add timeout to allow event loop to update label name while the db start command runs.
        GLib.timeout_add(10, run_after_label_update)


class RunningDbMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__(label='Running DB: ')
        self.app = app
        running_db = get_running_db_name()
        msg = 'Running DB: '
        if len(running_db) == 0:
            self.is_db_running = False
            msg = msg + "None"
            self.set_db_label_markup(get_running_db_none_label_markup())
            self.try_start_last_db()
        else:
            self.is_db_running = True
            msg = msg + running_db
            self.running_db = running_db
            self.set_db_label_markup(get_running_db_label_markup(running_db))

        # super().__init__(label=msg)

        self.stop_menu = Gtk.Menu()
        item_stop_db = Gtk.MenuItem(label='Stop')
        item_stop_db.connect('activate', stop_db)
        self.activate_event_id = self.connect('activate', self.show_stop_menu)
        self.stop_menu.append(item_stop_db)
        # self.name = name
        # self.set_label(name)

        GLib.timeout_add(1000, self.start_monitoring_dbs)

    def try_start_last_db(self):
        last_db = get_geo_setting('LAST_DB_VERSION')
        if last_db is not None:
            start_db(last_db)

    def stop_db(self, source):
        # self.set_db_label_markup('Stopping DB')
        self.set_label('Stopping DB...')
        def run():
            stop_db()
            # self.set_label('Running DB: None')
            self.set_db_label_markup(get_running_db_none_label_markup())
        # stop_db()
        # self.set_db_label_markup(get_running_db_none_label_markup())
        # self.set_label('Running DB: None')
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

    def start_monitoring_dbs(self):
        # if self.activate_event_id is not None:
        #     self.disconnect(self.activate_event_id)

        # poll for running db name, if it doesn't equal self
        running_db = get_running_db_name()
        if len(running_db) == 0:
            self.set_submenu()
            # self.connect('activate', self.no_op)
            self.app.icon_manager.set_icon(ICON_RED)
            # self.set_label('Running DB: None')
            self.set_db_label_markup(get_running_db_none_label_markup())
        else:
            self.set_submenu(self.stop_menu)
            # self.activate_event_id = self.connect('activate', self.show_stop_menu)
            self.app.icon_manager.set_icon(ICON_GREEN)
        return True


class UpdateMenuItem(Gtk.ImageMenuItem):
    def __init__(self, indicator):
        super().__init__(label='Updates')
        self.update_available = False
        self.item_update_activate_event_id = None
        self.indicator = indicator
        self.img_update_available = Gtk.Image(stock=Gtk.STOCK_OK)
        self.submenu = Gtk.Menu()
        self.item_update = Gtk.ImageMenuItem(label="Checking for updates...")
        self.submenu.append(self.item_update)
        self.set_submenu(self.submenu)
        self.connect('activate', self.show_submenu)
        self.item_update.connect('activate', self.update_geo_cli)

        self.set_update_status()
        GLib.timeout_add(5000, self.set_update_status)

    def set_update_status(self, source=None):
        update_available = is_update_available()
        self.update_available = update_available
        # if self.item_update_activate_event_id is not None:
        #     self.disconnect(self.item_update_activate_event_id)
        if update_available:
            self.set_image(self.img_update_available)
            self.item_update.set_label('Update Now')
            self.indicator.icon_manager.set_update_available(True)
            # self.item_update_activate_event_id = self.item_update.connect('activate', self.update_geo_cli)
        else:
            self.set_image(None)
            self.item_update.set_label('No update available')
            self.indicator.icon_manager.set_update_available(False)
            # self.item_update_activate_event_id = self.item_update.connect('activate', None)
        return True

    def update_geo_cli(self, source=None):
        update_cmd = GEO_CMD_BASE + 'update -f'
        cmd = "gnome-terminal -- bash -c \"bash %s; exec bash\"" % update_cmd
        # print(cmd)
        os.system(cmd)

    def no_op(self, source):
        pass

    def show_submenu(self, source):
        # print('stop menu clicked')
        self.submenu.show_all()


def get_geo_setting(key):
    value = geo('get ' + key)
    return value


def is_update_available():
    ret = geo('dev update-available')
    return ret == 'true'

def get_running_db_label_text(db):
    return 'Running DB:\n' + db

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
    return names_a


def get_running_db_name():
    cmd = 'docker container ls --filter name="geo_cli_db_" --filter status=running  -a --format="{{ .Names }}"'
    full_name = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
    name = full_name.replace('geo_cli_db_postgres_', '')
    # print(full_name)
    # print(name)
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

# def init_config():

# test()
# geo('-v')

def main():
    indicator = Indicator()
    Gtk.main()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
