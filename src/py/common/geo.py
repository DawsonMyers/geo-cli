import os
import subprocess
from . import util
from . import config

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
GEO_SRC_DIR = os.path.dirname(BASE_DIR)
GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '


def start_db(name):
    # '-n' option is the 'no prompt' option. It causes geo to exit instead of waiting for user input.
    return geo('db start -n ' + name)


def stop_db(arg=None):
    geo('db stop')
    # print('Stopping DB')


def run(arg_str):
    return geo(arg_str)


def geo(arg_str):
    geo_path = config.GEO_SRC_DIR + '/geo-cli.sh '
    cmd = geo_path + ' --raw-output ' + arg_str
    process = subprocess.Popen("bash %s" % (cmd), shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    # print(result)
    return result[0]


def get_myg_release():
    return geo('dev release')


def try_start_last_db():
    last_db = get_config('LAST_DB_VERSION')
    if last_db is not None:
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
    value = geo('get ' + key)
    return value


def set_config(key, value):
    geo('set %s "%s"' % (key, value))
    return value


def notifications_are_allowed():
    return get_config('SHOW_NOTIFICATIONS') != 'false'


def is_update_available():
    ret = geo('dev update-available')
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


def run_in_terminal(arg_str, title='geo-cli', stay_open_after=True):
    if stay_open_after:
        util.run_in_terminal(get_geo_cmd(arg_str), title)
    else:
        util.run_in_terminal_then_close(get_geo_cmd(arg_str), title)


def db(args):
    geo('db ' + args)

