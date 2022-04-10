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
icon_green_path = os.path.join(BASE_DIR, 'res', 'geo-icon-green.svg')
icon_grey_path = os.path.join(BASE_DIR, 'res', 'geo-icon-grey.svg')
icon_red_path = os.path.join(BASE_DIR, 'res', 'geo-icon-red1.svg')
print(icon_green_path)

indicator = None


class Indicator(object):
    def __init__(self):
        self.ind = appindicator.Indicator.new(APPINDICATOR_ID, icon_green_path, appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.ind.set_status(appindicator.IndicatorStatus.ACTIVE)
        # indicator.set_icon(icon_green_path)
        self.ind.set_icon(icon_green_path)
        # indicator.set_icon_full(icon_green_path, '')
        self.menu = Gtk.Menu()
        self.build_menu(self.menu)
        self.ind.set_menu(self.menu)
        # self.ind.set_menu(self.build_menu())
        Gtk.main()

    def build_menu(self, menu):
        item_running_db = RunningDbMenuItem(self.ind)
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
        db_submenu = self.build_db_submenu(item_running_db)
        show_db_menu = lambda _: db_submenu.show_all()
        item_start_db.connect('activate', show_db_menu)
        item_start_db.set_submenu(db_submenu)

        item_quit = Gtk.MenuItem(label='Quit')
        item_quit.connect('activate', self.quit)
        # item_disable.connect('activate', self.disable)
        # self.item_disable = item_disable

        item_help = self.build_help_item()

        menu.append(item_running_db)
        menu.append(Gtk.SeparatorMenuItem())
        # menu.append(item_disable)
        menu.append(item_start_db)
        menu.append(Gtk.SeparatorMenuItem())

        menu.append(item_help)
        menu.append(Gtk.SeparatorMenuItem())
        menu.append(item_quit)
        menu.show_all()

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

        # item_disable = Gtk.MenuItem(label='Disable')
        # self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        # label = Gtk.Label()
        # label.set_text('Box Label')
        # self.box.pack_start(label, True, True, 5)
        # item_disable.append(self.box)
        # item_quit = Gtk.MenuItem(label='Quit')
        # item_quit.connect('activate', self.quit)
        # item_disable.connect('activate', self.disable)
        # self.item_disable = item_disable
        # menu.append(item_quit)
        # menu.append(item_disable)
        # menu.show_all()
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
        # print('db-item: ' + name)
        super().__init__(label=name)
        self.name = name
        self.set_label(name)
        # start = lambda _ : start_db(name)
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
    def __init__(self, indicator):
        super().__init__(label='Running DB: ')
        self.indicator = indicator
        running_db = get_running_db_name()
        msg = 'Running DB: '
        if len(running_db) == 0:
            msg = msg + "None"
            self.set_db_label_markup(get_running_db_none_label_markup())
        else:
            msg = msg + running_db
            self.running_db = running_db
            self.set_db_label_markup(get_running_db_label_markup(running_db))

        # super().__init__(label=msg)

        self.stop_menu = Gtk.Menu()
        item_stop_db = Gtk.MenuItem(label='Stop')
        item_stop_db.connect('activate', stop_db)
        self.connect('activate', self.show_stop_menu)
        self.stop_menu.append(item_stop_db)
        # self.name = name
        # self.set_label(name)

        GLib.timeout_add(1000, self.start_monitoring_dbs)

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
        self.stop_menu.show_all()

    def start_monitoring_dbs(self):
        # print('ran')
        # poll for running db name, if it doesn't equal self
        running_db = get_running_db_name()
        if len(running_db) == 0:
            self.set_submenu()
            self.connect('activate', self.no_op)
            self.indicator.set_icon(icon_red_path)
            # self.set_label('Running DB: None')
            self.set_db_label_markup(get_running_db_none_label_markup())
        else:
            self.set_submenu(self.stop_menu)
            self.connect('activate', self.show_stop_menu)
            self.indicator.set_icon(icon_green_path)

        # if self.running_db != running_db:
        #     msg = 'Running DB: '
        #     if len(running_db) == 0:
        #         msg = msg + 'None'
        #     else:
        #         msg = msg + running_db
        #     self.set_label(msg)
        return True

def get_running_db_label_text(db):
    return 'Running DB:\n' + db

def get_running_db_label_markup(db):
    return '<span size="smaller">Running DB:</span>\n' + '<span>    <b>%s</b></span>' % db

def get_running_db_none_label_markup():
    return '<span size="smaller">Running DB:</span>\n' + '<span foreground="grey"><b>    None</b></span>'

def get_geo_db_names():
    cmd = 'docker container ls --filter name="geo_cli_db_"  -a --format="{{ .Names }}"'
    full_names = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
    names = full_names.replace('geo_cli_db_postgres_', '')
    # print(full_names)
    # print(names)
    full_names_a = full_names.split('\n')
    names_a = names.split('\n')

    # for fn in range(len(full_names_a)):
    # print(names_a)
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
    # process = subprocess.Popen(["geo db start " + name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # process = subprocess.Popen(["geo", "db", "start", name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    print(result)

def start_db(name):
    geo('db start ' + name)
    # process = subprocess.Popen("bash $GEO_CLI_SRC_DIR/geo-cli.sh db start " + name, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # # process = subprocess.Popen(["geo db start " + name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # # process = subprocess.Popen(["geo", "db", "start", name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # process.wait()
    # result = process.communicate()
    # print(result)


def stop_db(arg=None):
    geo('db stop')
    # print('Stopping DB')
    # process = subprocess.Popen("bash -c '$GEO_CLI_SRC_DIR/geo-cli.sh db stop'", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # # process = subprocess.Popen(["geo db start " + name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # # process = subprocess.Popen(["geo", "db", "start", name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    # process.wait()
    # result = process.communicate()
    # print(result)
    # # print(process.stdout.read())


# start_db('81')
# get_running_db_name()
# get_geo_db_names()

def main():
    indicator = Indicator()
    # indicator = appindicator.Indicator.new(APPINDICATOR_ID, icon_green_path, appindicator.IndicatorCategory.SYSTEM_SERVICES)
    # indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
    # # indicator.set_icon(icon_green_path)
    # indicator.set_icon(os.path.join(BASE_DIR, 'res', 'geo-icon-green.svg'))
    # # indicator.set_icon_full(icon_green_path, '')

    # indicator.set_menu(build_menu())
    Gtk.main()


# def build_menu():
#     menu = Gtk.Menu()
#     item_disable = Gtk.MenuItem(label='Disable')
#     item_quit = Gtk.MenuItem(label='Quit')
#     item_quit.connect('activate', quit)
#     item_quit.connect('activate', disable)
#     menu.append(item_quit)
#     menu.append(item_disable)
#     menu.show_all()
#     return menu

# def quit(source):
#     Gtk.main_quit()

# def disable(source):
#     indicator.set_icon(os.path.join(BASE_DIR, 'res', 'geo-icon-red.svg'))

# def test():
#     print('test')
#     process = subprocess.Popen("bash -c 'source ~/.bashrc; echo $GEO_CLI_SRC_DIR'", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
#     # process = subprocess.Popen(["geo db start " + name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
#     # process = subprocess.Popen(["geo", "db", "start", name], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
#     process.wait()
#     result = process.communicate()
#     print(result)


def geo(arg_str):
    geo_path = GEO_SRC_DIR + '/geo-cli.sh '
    cmd = geo_path + arg_str
    process = subprocess.Popen("bash %s" % (cmd), shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    print(result)

# def init_config():

# test()
# geo('-v')
if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
