# import gi
#
# gi.require_version('Gtk', '3.0')
# gi.require_version('AppIndicator3', '0.1')
# gi.require_version('Notify', '0.7')
# gi.require_version('Gio', '2.0')
# from gi.repository import Gtk, GLib, Gio, Notify, GdkPixbuf

import re

from indicator import *
from indicator.geo_indicator import IndicatorApp
# from common import geo
from indicator import icons
from indicator.menus.components import PersistentCheckMenuItem
from .auto_switch import to_key

def get_running_db_label_text(db):
    return '⛀ Running DB [%s]' % db
# ⛃⛀⛁

def get_running_db_none_label_text():
    return ' Running DB [None]'


class RunningDbMenuItem(Gtk.MenuItem):
    starting_up = True
    skip_next_notification = False
    current_myg_release_db = ''

    def __init__(self, app: IndicatorApp):
        super().__init__(label='Checking for DB')
        self.app = app
        self.running_db = ''
        # self.auto_switch_db_based_on_myg_release = geo.get_config('AUTO_SWITCH_DB') != 'false'
        self.db_monitor()
        self.stop_menu = Gtk.Menu()
        item_stop_db = Gtk.MenuItem(label='Stop')
        item_ssh = Gtk.MenuItem(label='SSH')
        item_psql = Gtk.MenuItem(label='PSQL')
        # item_rm = Gtk.MenuItem(label='Remove')
        item_copy_db = CopyDatabaseMenuItem(app=app)
        item_init_db = InitDatabaseMenuItem(app=app)
        item_stop_db.connect('activate', self.stop_db)
        item_ssh.connect('activate', lambda _: geo.run_in_terminal('db ssh'))
        item_psql.connect('activate', lambda _: geo.run_in_terminal('db psql'))
        # item_rm.connect('activate', lambda _: geo.db(f'rm {self.app.db}'))
        self.stop_menu.append(item_stop_db)
        self.stop_menu.append(item_ssh)
        self.stop_menu.append(item_psql)
        self.stop_menu.append(item_copy_db)
        self.stop_menu.append(item_init_db)
        # self.stop_menu.append(item_rm)
        self.set_submenu(self.stop_menu)
        self.show_all()
        GLib.timeout_add(2000, self.db_monitor)

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
        self.show()
        self.queue_draw()

    def db_monitor(self):
        # Poll for running db name, if it doesn't equal self
        cur_running_db = geo.get_running_db_name()
        self.app.db = cur_running_db
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
            self.app.icon_manager.set_icon(icons.GREEN)
            if self.starting_up or self.skip_next_notification:
                self.starting_up = False
                self.skip_next_notification = False
            else:
                self.app.show_quick_notification('DB Started: ' + cur_running_db)
        self.running_db = cur_running_db
        self.update_db_start_items()
        return True

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
    db_names = set()
    prev_sort_descending = None
    prev_sort_by_myg_version = None

    def __init__(self, app: IndicatorApp):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__()
        self.items = dict()
        GLib.timeout_add(2000, self.db_monitor)

    def build_db_items(self):
        dbs = geo.get_geo_db_names()
        dbs = self.sorted(dbs)
        self.db_names = set(dbs)
        for db in dbs:
            db_item = DbMenuItem(db, self.app)
            self.items[db] = db_item
            self.append(db_item)
        # self.queue_draw()
        self.append(SortLexicalCheckMenuItem(self.app))
        self.append(SortMygVersionCheckMenuItem(self.app))
        self.append(SortDirectionCheckMenuItem(self.app))
        self.show_all()

    def remove_items(self):
        for item in self.get_children():
            if not item.name:
                continue
            self.remove(item)
            self.items.pop(item)
            item.destroy()
        # self.queue_draw()
        self.show_all()

    def db_monitor(self):
        new_db_names = set(geo.get_geo_db_names())
        self.app.set_state('dbs', new_db_names)
        if new_db_names != self.db_names:
            self.update_items(new_db_names)
        else:
            self.check_sort()
        self.db_names = new_db_names
        return True

    def update_items(self, new_db_names):
        removed = self.db_names - new_db_names
        if removed:
            print(f'DbMenu.update_items: Removed: {removed}')
        added = new_db_names - self.db_names
        if added:
            print(f'DbMenu.update_items: Added: {added}')
        if not removed and not added:
            return
        if not self.items:
            self.build_db_items()
            return
        for db in removed:
            if db not in self.items: continue
            item = self.items.pop(db)
            item.hide()
            item.set_sensitive(False)
            self.remove(item)
            item.destroy()
        sorted_items = self.sorted(self.items)
        # sorted_items = sorted(self.items, reverse=True, key=db_name_sorter)
        for db in added:
            if db in self.items: continue
            item = DbMenuItem(db, self.app)
            item.show()
            i = 0
            # Find index to insert the db item so that it is sorted in descending order.
            while i < len(sorted_items) and self.db_compare(db, sorted_items[i]) < 0:
            # while i < len(sorted_items) and db_name_comparer(db, sorted_items[i]) < 0:
            # while i < len(sorted_items) and db < sorted_items[i]:
                i += 1
            self.insert(item, i)
            sorted_items.insert(i, item.name)
            self.items[db] = item
        if not added:
            self.show_all()
            return

        self.show_all()
        self.queue_draw()

    def check_sort(self):
        sort_by_myg_release = self.app.get_state('sort_myg_version', False)
        sort_descending = self.app.get_state('sort_direction', True)
        if sort_descending == self.prev_sort_descending and sort_by_myg_release == self.prev_sort_by_myg_version:
            return

        self.prev_sort_descending = sort_descending
        self.prev_sort_by_myg_version = sort_by_myg_release

        sorted_dbs = self.sorted(self.items)
        for db in sorted_dbs:
            self.remove(self.items[db])
        db_order = zip(range(len(sorted_dbs)), sorted_dbs)
        for i, db in db_order:
            self.insert(self.items[db], i)

    def sorted(self, items):
        sort_by_myg_release = self.app.get_state('sort_myg_version', False)
        sort_descending = self.app.get_state('sort_direction', True)
        if sort_by_myg_release:
            return sorted(items, reverse=sort_descending, key=db_name_sorter)
        return sorted(items, reverse=sort_descending)

    def db_compare(self, a, b):
        sort_by_myg_release = self.app.get_state('sort_myg_version')
        sort_descending = self.app.get_state('sort_direction')
        sort_by_myg_release = True if sort_by_myg_release else False
        sort_descending = True if sort_descending else False

        if sort_by_myg_release:
            return db_name_comparer(a, b, sort_descending)
        direction = -1 if sort_descending else 1
        return 1 * direction if a > b else -1 * direction if a < b else 0



class SortLexicalCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp):
        super().__init__(app,
                         label='Sort: Lexical',
                         config_id='SORT_LEXICAL',
                         app_state_id='sort_lexical',
                         default_state=True)
        self.app = app

    def on_state_changed(self, new_state):
        geo.set_config('SORT_MYG_VERSION', self.bool_to_string(False if new_state else True))


class SortMygVersionCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp):
        super().__init__(app,
                         label='Sort: MyG Version',
                         config_id='SORT_MYG_VERSION',
                         app_state_id='sort_myg_version',
                         default_state=False)
        self.app = app

    def on_state_changed(self, new_state):
        geo.set_config('SORT_LEXICAL', self.bool_to_string(False if new_state else True))


class SortDirectionCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp):
        super().__init__(app,
                         label='Sort Direction: Descending',
                         config_id='SORT_DIRECTION',
                         app_state_id='sort_direction',
                         default_state=True,
                         label_unchecked='Sort Direction: Ascending')
        self.app = app


# num_pattern = re.compile(r'^[1-9]\d+\.\d+', re.UNICODE)
num_pattern = re.compile(r'^[1-9]\d+([.-_]\d+)?', re.UNICODE)
# num_pattern = re.compile(r'^\d+\.\d+', re.UNICODE)
# num_pattern = re.compile(r'^\d+(\.\d+)?', re.UNICODE)
# suffix_pattern = re.compile(r'(?<=[\w-]+$', re.UNICODE)

def db_name_sorter(a):
    # Remove trailing 0s.
    a = re.sub('^0+','', a)
    match = re.search(num_pattern, a)
    suffix = ''
    prefix = 0
    if match:
        prefix = 1
        group = match.group()
        if '.' not in group:
            n = int(group)
            if n >= 60 and n < 100 or n < 10 or n >= 1900:
                prefix = 0
    # print((prefix, a))
    return (prefix, a)


def db_name_comparer(a, b, reverse=False):
    a_comp = db_name_sorter(a)
    b_comp = db_name_sorter(b)
    # print(f'{a_comp}:{b_comp}')
    result = 0
    if a_comp[0] > b_comp[0]:
        result = 1
    elif a_comp[0] < b_comp[0]:
        result = -1
    else:
        if a_comp[1] > b_comp[1]:
            result = 1
        elif a_comp[1] < b_comp[1]:
            result = -1
        else:
            result = 0
    result = result * -1 if reverse else result
    return result

class DbMenuItem(Gtk.MenuItem):
    def __init__(self, name, app: IndicatorApp):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__(label=name)
        self.name = name
        self.set_label(name)
        self.submenu = Gtk.Menu()
        self.item_start = Gtk.MenuItem(label='Start')
        self.item_remove = Gtk.MenuItem(label='Remove')
        self.item_copy_db = CopyDatabaseMenuItem(db_name=name)
        self.submenu.append(self.item_start)
        self.submenu.append(self.item_remove)
        self.submenu.append(self.item_copy_db)
        self.item_remove.connect('activate', self.remove_geo_db)
        self.item_start.connect('activate', self.start_geo_db)
        self.set_submenu(self.submenu)
        self.show_all()

    def remove_geo_db(self, src=None):
        if '(removing)' in self.name:
            return
        if not self.user_confirmed_removal(self.name):
            return
        self.set_label(self.name + ' (removing)')
        def run():
            config_cleanup_required = self.app.db_for_myg_release == self.name
            # print(f'remove_geo_db: {self.app.db_for_myg_release} == {self.name}')
            # print('config_cleanup_required: ' + str(config_cleanup_required))
            release_key = 'DB_FOR_RELEASE_' + to_key(self.app.myg_release)
            geo.db('rm ' + self.name)
            if config_cleanup_required:
                print('remove_geo_db: Removing release key: ' + release_key)
                geo.rm_config(release_key)
                self.app.db_for_myg_release = ''
                self.app.set_state('configured_db_for_myg_release', '')
            self.app.item_databases.get_submenu().remove(self)
            self.set_sensitive(False)
            return False
        # GLib.idle_add(run)
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

    def user_confirmed_removal(self, db):
        dialog = Gtk.MessageDialog(
            transient_for=None,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Remove database container '%s'?" % db,
        )
        dialog.format_secondary_text(
            "This cannot be undone."
        )
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK


class CopyDatabaseMenuItem(Gtk.MenuItem):
    def __init__(self, app: IndicatorApp = None, db_name: str = None):
        super().__init__(label='Make Copy')
        self.db_name = db_name
        self.app = app
        self.connect('activate', self.on_activate)

    def on_activate(self, widget):
        db_name = self.db_name if self.db_name else self.app.db
        geo.db(f'cp -i {db_name}', terminal=True)

class InitDatabaseMenuItem(Gtk.MenuItem):
    def __init__(self, app: IndicatorApp = None, db_name: str = None):
        super().__init__(label='Init GeotabDemo')
        self.db_name = db_name
        self.app = app
        self.connect('activate', self.on_activate)

    def on_activate(self, widget):
        geo.db('init', terminal=True )
