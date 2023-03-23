import os
import subprocess
import time

from . import util
from . import config

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
GEO_SRC_DIR = os.path.dirname(BASE_DIR)
GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '

geo_config_file_modified_time = 0
prev_config_file_str = ''
GEO_CONFIG_FILE_PATH = os.environ['HOME'] + '/.geo-cli/.geo.conf'
geo_config_cache = {}

def make_cached_property(get_value_func, delay=1, default=None):
    value = default
    last_refresh_time = time.time()
    def get_value():
        nonlocal last_refresh_time
        nonlocal value
        now = time.time()
        if now - last_refresh_time > delay:
            value = get_value_func()
            last_refresh_time = time.time()
        return value
    return get_value


def start_db(name):
    dbs = get_geo_db_names()
    # Make sure there is a db name and that it exists (otherwise we will recreate a deleted db get running 'geo db start -n <db name>')
    if name and name in dbs:
        # '-n' option is the 'no prompt' option. It causes geo to exit instead of waiting for user input.
        return geo('db start -n ' + name)


def stop_db(arg=None):
    geo('db stop')
    # print('Stopping DB')


def run(arg_str, terminal=False, return_error=False, return_all=False, return_success_status=False):
    if terminal:
        run_in_terminal(arg_str)
    else:
        return geo(arg_str, return_error, return_all, terminal, return_success_status)


def geo(arg_str, return_error=False, return_all=False, terminal=False, return_success_status=False):
    if terminal:
        run_in_terminal(arg_str)
        return
    geo_path = config.GEO_SRC_DIR + '/geo-cli.sh '
    cmd = geo_path + ' --raw-output --no-update-check ' + arg_str
    result = ['', '']
    return_code = ''
    
    try:
        process = subprocess.Popen("bash %s" % (cmd), shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
        return_code = process.wait()
        result = process.communicate()
        # if result[1]:
        #     print(f'geo: Error running command {arg_str}: {result}')
    except Exception as err:
        print(f'Error running geo("{arg_str}", {return_error}, {return_all}). result = {result}: err = {err}')
    if return_error: return result[1]
    if return_success_status: return False if result[1] or process.returncode != 0 or 'false' in result[0] else True
    if return_all: return result
    return result[0]


def get_myg_release():
    release = geo('dev release')
    if len(release) > 32 or ' ' in release or '\n\n' in release or 'MyGeotab' in release or 'repo' in release or 'geo-cli' in release or 'cli-handlers' in release:
        return ''
    return release


def try_start_last_db():
    last_db = get_config('LAST_DB_VERSION')
    start_db(last_db)


def get_geo_cmd(geo_cmd):
    return config.GEO_CMD_BASE + geo_cmd


def try_get_db_name_for_current_myg_release():
    db_names = get_geo_db_names()
    release = get_myg_release()
    if release is None:
        return
    release = release.replace('.', '_')
    tmp_matches = []

    for db in db_names:
        if release in db:
            tmp_matches.append(db)
    if len(tmp_matches) == 0:
        return ''
    # Use the shortest name.
    shortest_name = sorted(tmp_matches, key=len)[0]
    return shortest_name


def get_config(key):
    load_geo_config_if_required()
    key = key.upper()
    if key in geo_config_cache:
        return geo_config_cache[key]
    value = geo(f"get '{key}'")
    return value


def set_config(key, value):
    geo("set '%s' '%s'" % (key, value))
    return value


def rm_config(key):
    geo("rm '%s'" % key)


def notifications_are_allowed():
    return get_config('SHOW_NOTIFICATIONS') != 'false'


def is_update_available():
    ret = geo('dev update-available')
    # print('is_update_available ' + ret)
    return ret == 'true'


def update():
    update_cmd = get_geo_cmd('update')
    util.run_in_terminal(update_cmd, title='geo-cli Update')


def get_running_db_label_text(db):
    return 'Running DB [%s]' % db


def get_running_db_none_label_text():
    return 'Running DB [None]'


def get_geo_db_names():
    cmd = 'docker container ls --filter name="geo_cli_db_"  -a --format="{{ .Names }}"'
    names_a = []
    try:
        full_names = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
        names = full_names.replace('geo_cli_db_postgres_', '')
        full_names_a = full_names.split('\n')
        names_a = names.split('\n')
        names_a.sort(reverse=True)
    except Exception as err:
        print(f'Error running get_geo_db_names(): {err}')
    names_a = [] if not names_a else names_a
    return names_a
        
        
def get_running_db_name():
    cmd = 'docker container ls --filter name="geo_cli_db_" --filter status=running  -a --format="{{ .Names }}"'
    name = ''
    # get_name = make_cached_property(lambda: subprocess.run(cmd, shell=True, text=True, capture_output=True))
    try:
        # full_name = get_name().stdout[0:-1]
        full_name = subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]
        name = full_name.replace('geo_cli_db_postgres_', '')
    except Exception as err:
        print(f'Error running get_running_db_name(): {err}')

    return name


def run_in_terminal(arg_str, title='geo-cli', stay_open_after=True):
    if stay_open_after:
        util.run_in_terminal(get_geo_cmd(arg_str), title)
    else:
        util.run_in_terminal_then_close(get_geo_cmd(arg_str), title)


def db(args, terminal=False):
    cmd = 'db ' + args
    if terminal:
        run_in_terminal(cmd)
    else:
        geo(cmd)


def get_geo_config_modified_time():
    try:
        if not os.path.exists(GEO_CONFIG_FILE_PATH):
            return 0
        return os.path.getmtime(GEO_CONFIG_FILE_PATH)
    except Exception as err:
        print(f'Error running get_geo_config_modified_time(): {err}')


def load_geo_config_if_required():
    global geo_config_file_modified_time
    global geo_config_cache
    global prev_config_file_str
    try:
        if not os.path.exists(GEO_CONFIG_FILE_PATH):
            return
        last_modified_time = get_geo_config_modified_time()
        if last_modified_time <= geo_config_file_modified_time:
            return

        loading = 'Loading' if geo_config_file_modified_time == 0 else 'Reloading'
        seconds_since_last_load = last_modified_time - geo_config_file_modified_time
        time_since = f'{seconds_since_last_load:.3f} seconds since last load' if geo_config_file_modified_time > 0 else ''
        print(f'load_geo_config_if_required: {loading} config. {time_since}')
        geo_config_file_modified_time = last_modified_time

        with open(GEO_CONFIG_FILE_PATH, 'r') as f:
            lines = f.readlines()
        if not lines:
            print(f'load_geo_config_if_required: Config file was empty.')
            return
        if prev_config_file_str == lines:
            print(f'load_geo_config_if_required: No change config file contents')
        prev_config_file_str = lines

        for line in lines:
            line = line.replace('\n', '')
            index_of_delimiter = line.index('=')
            key = line[0:index_of_delimiter]
            value = line[index_of_delimiter + 1:]
            if key in geo_config_cache and geo_config_cache[key] != value:
                print(f'load_geo_config_if_required: {key} updated: {geo_config_cache[key]} => {value}')
            geo_config_cache[key] = value
            geo_config_cache[key.replace('GEO_CLI_', '')] = value
    except Exception as err:
        print(f'Error running load_geo_config(): {err}')

