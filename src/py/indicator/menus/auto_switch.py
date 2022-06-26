import concurrent.futures
import os
import shutil

from indicator import *
from indicator.geo_indicator import IndicatorApp
from indicator.menus.components import PersistentCheckMenuItem


def to_key(key_str):
    return key_str.replace('.', '_').replace('/', '_').replace(' ', '_')


class AutoSwitchDbMenuItem(Gtk.MenuItem):
    cur_myg_release = ''
    prev_myg_release = ''
    auto_switch_tasks = set()

    def __init__(self, app: IndicatorApp):
        super().__init__(label='Auto-Switch')
        self.app = app
        self.build_submenu(app)
        self.show_all()
        GLib.timeout_add(1000, self.myg_release_monitor)

    def build_submenu(self, app):
        submenu = Gtk.Menu()
        item_auto_switch_help = Gtk.MenuItem(label='Help')
        item_auto_switch_help.connect('activate', lambda _: webbrowser.open('https://git.geotab.com/dawsonmyers/geo-cli#auto-switch-db', new=2))
        item_npm_task_toggle = AutoNpmInstallTaskCheckMenuItem(app, self)
        item_server_config_task_toggle = AutoServerConfigTaskCheckMenuItem(app, self)
        item_geotab_demo_data_task_toggle = AutoGeotabDemoCleanUpTaskCheckMenuItem(app, self)
        item_db_task_toggle = AutoSwitchDbTaskCheckMenuItem(app, self)
        item_cur_myg_release_display = CheckedOutMygReleaseMenuItem(app, self)
        item_db_for_myg_release_display = DbForMygReleaseMenuItem(app, self)
        item_set_db_for_release = SetDbForMygReleaseMenuItem(app, self)
        submenu.append(item_npm_task_toggle)
        submenu.append(item_server_config_task_toggle)
        submenu.append(item_geotab_demo_data_task_toggle)
        submenu.append(Gtk.SeparatorMenuItem())
        submenu.append(item_db_task_toggle)
        submenu.append(item_cur_myg_release_display)
        submenu.append(item_db_for_myg_release_display)
        submenu.append(item_set_db_for_release)
        submenu.append(Gtk.SeparatorMenuItem())
        submenu.append(item_auto_switch_help)
        self.set_submenu(submenu)
        submenu.show_all()

    def myg_release_monitor(self):
        self.cur_myg_release = self.app.get_state('myg_release')
        if self.cur_myg_release and self.prev_myg_release and self.cur_myg_release != self.prev_myg_release:
            self.app.set_state('myg_release', self.cur_myg_release)
            print(f'AutoSwitchDbMenuItem: MYG version changed from {self.prev_myg_release} to {self.cur_myg_release}')
            self.run_auto_switch_tasks()
        self.prev_myg_release = self.cur_myg_release
        return True

    def run_auto_switch_tasks(self):
        if not self.auto_switch_tasks:
            return
        start = time.time()
        # print("Time elapsed on working...")
        print('AutoSwitchDbMenuItem: Running auto-switch tasks')

        output = ""
        # output = "Auto switch tasks:\n"

        # 9.7, 9.4, 16.5, 15.6
        # for task in self.auto_switch_tasks:
        #     if not task.is_enabled:
        #         continue
        #     result = task(self.cur_myg_release, self.prev_myg_release)
        #     result = 'Fail' if not result else result
        #     output += f'{task.name}[{result}], \n'

        # Running with ThreadPoolExecutor seems to be slower, so comment out for now.
        #16.8, 14, 15.9, 14, 11
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_task = {executor.submit(task, self.cur_myg_release, self.prev_myg_release): task for task in self.auto_switch_tasks if task.is_enabled}
            for future in concurrent.futures.as_completed(future_to_task):
                task = future_to_task[future]
                try:
                    result = future.result()
                    result = 'Fail' if not result else result
                    output += f'{task.name}, \n'
                    # output += f'{task.name}[{result}], \n'
                except Exception as exc:
                    print('%r generated an exception: %s' % (task.name, exc))
                else:
                    print(f'AutoSwitchDbMenuItem: Done running auto-switch task: {task.name}')

        self.app.show_notification(output, 'Auto-Switch Tasks Complete', 4000)
        end = time.time()
        print(f'Auto-Switch Tasks Completed in {end - start} seconds')

    def add_auto_switch_task(self, task):
        self.auto_switch_tasks.add(task)

    def register_auto_switch_task(self, task_name: str, task, is_enabled_func):
        self.add_auto_switch_task(AutoSwitchTask(task_name, task, is_enabled_func))

    def remove_auto_switch_task(self, task):
        self.auto_switch_tasks.remove(task)


class AutoSwitchTask:
    def __init__(self, name: str, task, is_enabled_func):
        self.is_enabled_func = is_enabled_func
        self.name = name
        self.task = task

    def __call__(self, *args, **kwargs):
        print(f'Running auto-switch task: {self.name}')
        return self.task(*args, **kwargs)

    @property
    def is_enabled(self):
        if self.is_enabled_func and callable(self.is_enabled_func):
            return self.is_enabled_func()
        return True
    

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
        if cur_release and self.cur_myg_release != cur_release:
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


class AutoSwitchDbTaskCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app,
                         label='Auto-Switch DB',
                         config_id='AUTO_SWITCH_DB',
                         app_state_id='auto-db',
                         default_state=True)
        self.parent = parent
        self.app = app
        parent.register_auto_switch_task('DB', self.change_db_when_myg_release_changed, self.is_enabled)

    def change_db_when_myg_release_changed(self, cur_myg_release=None, prev_myg_release=None):
        auto_switch_db_enabled = self.app.get_state('auto-db')
        if auto_switch_db_enabled and self.app.db_for_myg_release:
            print(f'AutoSwitchDbTaskCheckMenuItem: Starting db: {self.app.db_for_myg_release}')
            self.app.item_running_db.skip_next_notification = True
            geo.start_db(self.app.db_for_myg_release)
        return 'Done'


class AutoNpmInstallTaskCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app,
                         label='Auto-Install npm',
                         config_id='AUTO_NPM_INSTALL',
                         app_state_id='auto-npm',
                         default_state=True)
        self.parent = parent
        self.app = app
        parent.register_auto_switch_task('npm install', self.npm_install, self.is_enabled)

    def npm_install(self, cur_myg_release=None, prev_myg_release=None):
        if not self.enabled:
            return
        error = geo.geo('init npm', return_error=True)
        if 'ERR' in error:
            geo.run_in_terminal('init npm')
            return 'Fail'
        return 'Done'


class AutoServerConfigTaskCheckMenuItem(PersistentCheckMenuItem):
    prev_myg_release = None

    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app,
                         label='Auto-Switch server.config',
                         config_id='AUTO_SERVER_CONFIG',
                         app_state_id='auto-server-config', default_state=False)
        self.parent = parent
        parent.register_auto_switch_task('server.config', self.auto_switch_server_config, self.is_enabled)

    def auto_switch_server_config(self, cur_myg_release=None, prev_myg_release=None):
        if not self.enabled:
            return
        try:
            output = geo.geo(f'dev auto-switch {cur_myg_release} {prev_myg_release}', return_all=True)
            if 'Error' in output:
                print(f'Failed to switch server.config: {output}')
                return 'Fail'
        except Exception as err:
            print(f'Error running auto_switch_server_config(): {err}')

        return 'Done'


class AutoGeotabDemoCleanUpTaskCheckMenuItem(PersistentCheckMenuItem):
    def __init__(self, app: IndicatorApp, parent: AutoSwitchDbMenuItem):
        super().__init__(app,
                         label='Auto-Clean GeotabDemo Data',
                         config_id='AUTO_CLEAN_GEOTAB_DEMO_DATA',
                         app_state_id='auto-demo-data',
                         default_state=True)
        self.parent = parent
        self.app = app
        parent.register_auto_switch_task('GeotabDemo Data', self.auto_clean_geotab_demo_data, self.is_enabled)

    def auto_clean_geotab_demo_data(self, cur_myg_release=None, prev_myg_release=None):
        if not self.enabled:
            return
        try:
            geotabdemo_data_dir = os.environ['HOME'] + '/GEOTAB/Checkmate/geotabdemo_data'
            # Delete the geotabdemo_data directory if it exists.
            if os.path.exists(geotabdemo_data_dir):
                shutil.rmtree(geotabdemo_data_dir)
        except Exception as err:
            print(f'Error running auto_clean_geotab_demo_data(): {err}')
            return 'Fail'

        return 'Done'
