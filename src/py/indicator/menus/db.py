import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib, Gio, Notify, GdkPixbuf

from common import geo
from indicator import icons

def get_running_db_label_text(db):
    return 'Running DB [%s]' % db


def get_running_db_none_label_text():
    return 'Running DB [None]'


class RunningDbMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__(label='Checking for DB')
        self.app = app
        self.running_db = ''
        self.current_myg_release_db = geo.try_get_db_name_for_current_myg_release()
        self.auto_switch_db_based_on_myg_release = geo.get_config('AUTO_SWITCH_DB') != 'false'
        self.db_monitor()
        self.stop_menu = Gtk.Menu()
        item_stop_db = Gtk.MenuItem(label='Stop')
        item_ssh = Gtk.MenuItem(label='SSH')
        item_psql = Gtk.MenuItem(label='PSQL')
        item_stop_db.connect('activate', self.stop_db)
        item_ssh.connect('activate', lambda _: geo.run_in_terminal('db ssh'))
        item_psql.connect('activate', lambda _: geo.run_in_terminal('db psql'))
        self.stop_menu.append(item_stop_db)
        self.stop_menu.append(item_ssh)
        self.stop_menu.append(item_psql)
        self.set_submenu(self.stop_menu)
        self.show_all()
        GLib.timeout_add(1000, self.db_monitor)

    def stop_db(self, source):
        self.set_db_label('Stopping DB...')
        self.set_sensitive(False)
        def run():
            geo.stop_db()
            self.set_db_label(get_running_db_none_label_text())

        GLib.timeout_add(10, run)

    def set_db_label(self, text):
        # print('Running db text: ' + text)
        self.set_label(text)
        # print('Set label: ' + self.get_label())

        # self.set_use_underline(True)
        self.show()
        self.queue_draw()

    def db_monitor(self):
        # poll for running db name, if it doesn't equal self
        cur_running_db = geo.get_running_db_name()
        if cur_running_db == self.running_db and 'Stopping' in self.get_label():
            pass
        elif len(cur_running_db) == 0:
            if 'Failed' in self.get_label():
                self.set_sensitive(False)
                self.app.icon_manager.set_icon(icons.ORANGE)
            else:
                self.set_sensitive(False)
                self.app.icon_manager.set_icon(icons.RED)
                self.set_db_label('No DB running')
        elif self.running_db != cur_running_db:
            self.set_sensitive(True)
            label = get_running_db_label_text(cur_running_db)
            self.set_db_label(label)
            # self.set_db_label(get_running_db_label_markup(cur_running_db))
            self.app.icon_manager.set_icon(icons.GREEN)
            self.app.show_quick_notification('DB Started: ' + cur_running_db)
        self.running_db = cur_running_db
        self.update_db_start_items()
        self.change_db_if_myg_release_changed()
        return True

    def change_db_if_myg_release_changed(self):
        if self.app.item_auto_switch_db_toggle and not self.app.item_auto_switch_db_toggle.enabled:
            return
        cur_db_release = geo.try_get_db_name_for_current_myg_release()
        if cur_db_release is not None and cur_db_release != self.current_myg_release_db:
            if self.current_myg_release_db is not None:
                geo.start_db(cur_db_release)
            self.current_myg_release_db = cur_db_release

    def update_db_start_items(self):
        if self.app.item_databases is None:
            return
        submenu = self.app.item_databases.get_submenu()
        for item in submenu.items.values():
            if item.name == self.running_db:
                item.item_start.set_sensitive(False)
            else:
                item.item_start.set_sensitive(True)
            item.show()


class DbMenu(Gtk.Menu):
    def __init__(self, app):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__()
        self.db_names = set(geo.get_geo_db_names())
        self.items = dict()
        self.build_db_items()
        GLib.timeout_add(2 * 1000, self.db_monitor)

    def build_db_items(self):
        dbs = geo.get_geo_db_names()
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
        new_db_names = set(geo.get_geo_db_names())
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
            geo.db('rm ' + self.name)
            self.app.item_databases.get_submenu().remove(self)
            self.set_sensitive(False)
            return False
        GLib.timeout_add(5, lambda: run())

    def start_geo_db(self, obj):
        self.item_running_db.set_label('Starting DB...')
        def run_after_label_update():
            return_msg = geo.start_db(self.name)
            if "Port error" in return_msg:
                geo.run_in_terminal('db start ' + self.name)
            running_db = geo.get_running_db_name()
            if self.name != running_db:
                self.item_running_db.set_label('Failed to start DB')
            else:
                self.item_start.set_sensitive(False)
                self.item_running_db.set_db_label(get_running_db_label_text(self.name))

        # Add timeout to allow event loop to update label name while the db start command runs.
        GLib.timeout_add(10, run_after_label_update)