# import gi
#
# gi.require_version('Gtk', '3.0')
# gi.require_version('AppIndicator3', '0.1')
# gi.require_version('Notify', '0.7')
# gi.require_version('Gio', '2.0')
# from gi.repository import Gtk, GLib, Gio, Notify, GdkPixbuf

from indicator import *
from indicator.geo_indicator import IndicatorApp
# from common import geo
from indicator import icons
from indicator.menus.components import PersistentCheckMenuItem


def get_running_db_label_text(db):
    return 'Running DB [%s]' % db


def get_running_db_none_label_text():
    return 'Running DB [None]'


def to_key(str):
    return str.replace('.', '_').replace('/', '_').replace(' ', '_')


class RunningDbMenuItem(Gtk.MenuItem):
    starting_up = True
    current_myg_release_db = ''

    def __init__(self, app: IndicatorApp):
        super().__init__(label='Checking for DB')
        self.app = app
        self.running_db = ''
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
            if self.starting_up:
                self.starting_up = False
            else:
                self.app.show_quick_notification('DB Started: ' + cur_running_db)
        self.running_db = cur_running_db
        self.update_db_start_items()
        self.change_db_if_myg_release_changed()
        return True

    def change_db_if_myg_release_changed(self):
        auto_switch_db_enabled = self.app.get_state('auto-db')
        cur_db_release = self.app.db_for_myg_release

        if cur_db_release and cur_db_release != self.current_myg_release_db:
            # print(f'MYG release changed from {self.current_myg_release_db} to {cur_db_release}')
            if auto_switch_db_enabled and self.current_myg_release_db:
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
    db_names = set()

    def __init__(self, app: IndicatorApp):
        self.app = app
        self.item_running_db = app.item_running_db
        super().__init__()
        self.items = dict()
        GLib.timeout_add(1000, self.db_monitor)

    def build_db_items(self):
        dbs = geo.get_geo_db_names()
        self.db_names = set(dbs)
        for db in dbs:
            db_item = DbMenuItem(db, self.app)
            self.items[db] = db_item
            self.append(db_item)
        # self.queue_draw()
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
        if new_db_names != self.db_names:
            self.update_items(new_db_names)
        self.db_names = new_db_names
        return True

    def update_items(self, new_db_names):
        removed = self.db_names - new_db_names
        print('Removed: ' + str(removed))
        added = new_db_names - self.db_names
        print('Added: ' + str(added))
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
        sorted_items = sorted(self.items, reverse=True)
        for db in added:
            if db in self.items: continue
            item = DbMenuItem(db, self.app)
            item.show()
            i = 0
            # Find index to insert the db item so that it is sorted in descending order.
            while i < len(sorted_items) and db < sorted_items[i]:
                i += 1
            self.insert(item, i)
            sorted_items.insert(i, item.name)
            self.items[db] = item
        if not added:
            self.show_all()
            return

        self.show_all()
        self.queue_draw()


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
        self.submenu.append(self.item_start)
        self.submenu.append(self.item_remove)
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
            geo.db('rm ' + self.name)
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


class AutoSwitchDbMenuItem(Gtk.MenuItem):
    cur_myg_release = ''
    prev_myg_release = ''
    auto_switch_tasks = set()

    def __init__(self, app: IndicatorApp):
        super().__init__(label='Auto-Switch DB')
        self.app = app
        self.enabled = geo.get_config('AUTO_SWITCH_DB') != 'false'
        self.app.state['auto-db'] = geo.get_config('AUTO_SWITCH_DB') != 'false'
        self.app.state['auto-npm'] = geo.get_config('AUTO_NPM_INSTALL') != 'false'
        self.build_submenu(app)
        self.show_all()
        GLib.timeout_add(1000, self.myg_release_monitor)

    def build_submenu(self, app):
        submenu = Gtk.Menu()
        item_toggle = AutoSwitchDbEnableCheckMenuItem(app, self)
        item_npm_toggle = AutoNpmInstallCheckMenuItem(app, self)
        item_cur_release = CheckedOutMygReleaseMenuItem(app, self)
        item_db_for_release = DbForMygReleaseMenuItem(app, self)
        item_set_db_for_release = SetDbForMygReleaseMenuItem(app, self)
        submenu.append(item_toggle)
        submenu.append(item_npm_toggle)
        submenu.append(item_cur_release)
        submenu.append(item_db_for_release)
        submenu.append(item_set_db_for_release)
        self.set_submenu(submenu)
        submenu.show_all()

    def myg_release_monitor(self):
        self.cur_myg_release = self.app.get_state('myg_release')
        if self.cur_myg_release and self.prev_myg_release and self.cur_myg_release != self.prev_myg_release:
            self.app.set_state('myg_release', self.cur_myg_release)
            print(f'AutoSwitchDbMenuItem: MYG version changed from {self.prev_myg_release} to {self.cur_myg_release}')
        self.prev_myg_release = self.cur_myg_release
        return True

    def run_auto_switch_tasks(self):
        for task in self.auto_switch_tasks:
            task(self.cur_myg_release, self.prev_myg_release)

    def add_auto_switch_task(self, task):
        self.auto_switch_tasks.add(task)

    def remove_auto_switch_task(self, task):
        self.auto_switch_tasks.remove(task)


class SetDbForMygReleaseMenuItem(Gtk.MenuItem):
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        self.parent = parent
        self.app = app
        super().__init__(label='Set DB for MYG Release')
        self.connect('activate', lambda _: self.set_db_for_release())
        GLib.timeout_add(2000, self.monitor)

    def monitor(self):
        if self.app.db and self.app.db != self.app.db_for_myg_release:
            self.set_sensitive(True)
            self.set_label('Set DB for MYG Release')
            self.show()
        else:
            self.set_sensitive(False)
            self.set_label('Configured DB Running')
            self.show()
        return True

    def set_db_for_release(self):
        if not self.app.db or not self.app.myg_release:
            return
        release_key = 'DB_FOR_RELEASE_' + to_key(self.app.myg_release)
        geo.set_config(release_key, self.app.db)
        self.app.db_for_myg_release = self.app.db


class CheckedOutMygReleaseMenuItem(Gtk.MenuItem):
    cur_myg_release = ''

    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        self.parent = parent
        self.app = app
        super().__init__(label='MYG Release: Unknown')
        self.set_sensitive(False)
        self.update_label(self.cur_myg_release)
        GLib.timeout_add(2000, self.monitor)

    def update_label(self, label):
        self.set_label('MYG Release: %s' % label)
        self.show()

    def monitor(self):
        cur_release = geo.get_myg_release()
        if self.cur_myg_release != cur_release:
            self.cur_myg_release = cur_release
            self.app.state['myg_release'] = self.cur_myg_release
            self.app.myg_release = self.cur_myg_release
            self.update_label(self.cur_myg_release)
        return True

    def get_db_for_release(self):
        if self.cur_myg_release is None:
            return
        release_key = 'DB_FOR_RELEASE_' + self.cur_myg_release.replace('.', '_').replace('/', '_').replace(' ', '_')
        return geo.get_config(release_key)


class DbForMygReleaseMenuItem(Gtk.MenuItem):
    db_for_release = ''

    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        self.parent = parent
        self.app = app
        super().__init__(label='Configured DB: None')
        self.set_sensitive(False)
        GLib.timeout_add(2000, self.monitor)

    def update_label(self):
        if not self.db_for_release:
            label = 'None'
        else:
            label = self.db_for_release
        if len(label) == 0:
            label = 'None'
        self.set_label('Configured DB: %s' % label)
        self.show()

    def monitor(self):
        db_for_release = self.get_db_for_release()

        if self.db_for_release != db_for_release:
            self.db_for_release = db_for_release
            self.app.db_for_myg_release = db_for_release
            self.update_label()
        return True

    def has_db_for_release(self):
        return self.get_db_for_release() is not None

    def get_db_for_release(self):
        if not self.app.myg_release or not self.app.db:
            return ''
        release_key = 'DB_FOR_RELEASE_' + to_key(self.app.myg_release)
        return geo.get_config(release_key)


class AutoSwitchDbEnableCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app, label='Auto-Switch DB', config_id='AUTO_SWITCH_DB', app_state_id='auto-db', default_state=True)
        self.parent = parent
        self.app = app


class AutoNpmInstallCheckMenuItem(PersistentCheckMenuItem):
    enabled = True
    prev_myg_release = None
    
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app, label='Auto-Install npm', config_id='AUTO_NPM_INSTALL', app_state_id='auto-npm', default_state=False)
        self.parent = parent
        self.app = app

        # GLib.timeout_add(1000, self.myg_release_monitor)

    # def handle_toggle(self, src):
    #     auto_npm_install_enabled = geo.get_config('AUTO_NPM_INSTALL') != 'false'
    #     new_state = not auto_npm_install_enabled
    #     self.enabled = new_state
    #     self.set_active(new_state)
    #     new_state_str = 'true' if new_state else 'false'
    #     geo.set_config('AUTO_NPM_INSTALL', new_state_str)
    #
    #     # if self.enabled:
    #     #     self.set_label('Auto-npm Install (Enabled)')
    #     # else:
    #     #     self.set_label('Auto-npm Install (Disabled)')
    #     self.app.item_auto_switch_db_toggle.auto_npm_install_enabled = new_state
    #     self.app.state['auto-npm'] = new_state
    #     self.show()

    # def monitor(self):
    #     auto_npm_install_enabled = geo.get_config('AUTO_NPM_INSTALL') != 'false'
    #     if self.enabled != auto_npm_install_enabled:
    #         self.enabled = auto_npm_install_enabled
    #         self.set_active(auto_npm_install_enabled)
    #         self.app.state['auto-npm'] = self.enabled
    #
    #     # if self.enabled:
    #     #     self.set_label('Auto-npm Install (Enabled)')
    #     # else:
    #     #     self.set_label('Auto-npm Install (Disabled)')
    #     self.show()
    #     # if self.enabled:
    #     #     self.myg_release_monitor()
    #     return True

    # def myg_release_monitor(self):
    #     cur_myg_release = self.app.get_state('myg_release')
    #     if cur_myg_release and self.prev_myg_release and cur_myg_release != self.prev_myg_release:
    #         print(f'AutoNpmInstallCheckMenuItem.npm_install_if_myg_release_changed: installing npm. MYG version changed from {self.prev_myg_release} to {cur_myg_release}')
    #         self.npm_install()
    #     self.prev_myg_release = cur_myg_release
    #     return True

    def npm_install(self, cur_myg_release=None, prev_myg_release=None):
        if not self.enabled:
            return
        error = geo.geo('init npm', return_error=True)
        if 'ERR' in error:
            self.app.show_quick_notification('npm install failed')
            geo.run_in_terminal('init npm')
            return True
        self.app.show_quick_notification('npm install successful')

# class AutoNpmInstallCheckMenuItem(Gtk.CheckMenuItem):
#     enabled = True
#     prev_myg_release = None
#
#     def __init__(self, app: IndicatorApp):
#         super().__init__(label='Auto-Install npm')
#         self.app = app
#         self.enabled = geo.get_config('AUTO_NPM_INSTALL') != 'false'
#         # if not self.enabled:
#         #     self.set_label("Disabled")
#         self.set_active(self.enabled)
#         self.app.state['auto-npm'] = self.enabled
#         self.connect('toggled', self.handle_toggle)
#         self.show_all()
#         GLib.timeout_add(1000, self.monitor)
#         GLib.timeout_add(1000, self.myg_release_monitor)
#
#     def handle_toggle(self, src):
#         auto_npm_install_enabled = geo.get_config('AUTO_NPM_INSTALL') != 'false'
#         new_state = not auto_npm_install_enabled
#         self.enabled = new_state
#         self.set_active(new_state)
#         new_state_str = 'true' if new_state else 'false'
#         geo.set_config('AUTO_NPM_INSTALL', new_state_str)
#
#         # if self.enabled:
#         #     self.set_label('Auto-npm Install (Enabled)')
#         # else:
#         #     self.set_label('Auto-npm Install (Disabled)')
#         self.app.item_auto_switch_db_toggle.auto_npm_install_enabled = new_state
#         self.app.state['auto-npm'] = new_state
#         self.show()
#
#     def monitor(self):
#         auto_npm_install_enabled = geo.get_config('AUTO_NPM_INSTALL') != 'false'
#         if self.enabled != auto_npm_install_enabled:
#             self.enabled = auto_npm_install_enabled
#             self.set_active(auto_npm_install_enabled)
#             self.app.state['auto-npm'] = self.enabled
#
#         # if self.enabled:
#         #     self.set_label('Auto-npm Install (Enabled)')
#         # else:
#         #     self.set_label('Auto-npm Install (Disabled)')
#         self.show()
#         # if self.enabled:
#         #     self.myg_release_monitor()
#         return True
#
#     def myg_release_monitor(self):
#         cur_myg_release = self.app.get_state('myg_release')
#         if cur_myg_release and self.prev_myg_release and cur_myg_release != self.prev_myg_release:
#             print(f'AutoNpmInstallCheckMenuItem.npm_install_if_myg_release_changed: installing npm. MYG version changed from {self.prev_myg_release} to {cur_myg_release}')
#             self.npm_install()
#         self.prev_myg_release = cur_myg_release
#         return True
#
#     def npm_install(self):
#         error = geo.geo('init npm', return_error=True)
#         if 'ERR' in error:
#             self.app.show_quick_notification('npm install failed')
#             geo.run_in_terminal('init npm')
#             return True
#         self.app.show_quick_notification('npm install successful')


