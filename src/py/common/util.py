import os
import subprocess
import time
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk


def mklog(stub):
    def logfn(msg): print(f'{stub}: {msg}')
    logfn.extent = lambda stub1: mklog(f'{stub}:{stub1}:')
    return logfn

def run_in_terminal_then_close(cmd_to_run, title=''):
    # print(f"geo.run_in_terminal_then_close: cmd = {cmd}")
    if title:
        title = "--title='%s'" % title
    cmd = f"gnome-terminal {title} --geometry=100x30 -- bash -i -c \"{cmd_to_run};\""
    # cmd = f"gnome-terminal {title} --geometry=80x30 -- bash -i -c \"bash -i -c '{cmd_to_run}'; cd $HOME\""
    try:
        os.system(cmd)
    except Exception as err:
        print(f'Error running run_in_terminal_then_close("{cmd_to_run}", "{title}"): {err}')


def run_in_terminal(cmd_to_run, title=''):
    if title:
        title = "--title='%s'" % title
    cmd = f"gnome-terminal {title} --geometry=100x30 -- bash -i -c \"echo '{cmd_to_run}' >> $HOME/.bash_history; {cmd_to_run}; cd $HOME; exec bash\";"
    # print(f"geo.run_in_terminal: cmd = {cmd}")
    # cmd = f"gnome-terminal {title} --geometry=80x30 -- bash -i -c \"echo '{cmd_to_run}' >> $HOME/.bash_history; bash {cmd_to_run}; cd $HOME; exec bash\"; exec bash"
    try:
        os.system(cmd)
    except Exception as err:
        print(f'Error running run_in_terminal("{cmd_to_run}", "{title}"): {err}')



def run_shell_cmd(cmd):
    try:
        return subprocess.run(cmd, shell=True, text=True, capture_output=True, executable="/bin/bash", timeout=10).stdout[0:-1]
    except Exception as err:
        print(f'Error running run_shell_cmd("{cmd}"): {err}')
    return 'error'


def run_cmd_and_wait(cmd):
    try:
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
        process.wait(timeout=15)
        result = process.communicate()
        print(result)
        return result
    except Exception as err:
        print(f'Error run_cmd_and_wait run_shell_cmd("{cmd}"): {err}')
    return 'error'


def current_time_ms():
    return round(time.time() * 1000)
# UI Utils
def get_item_with_submenu(self, menu, label='EMPTY'):
        item = Gtk.MenuItem(label=label)
        item.set_submenu(menu)
        item.show_all()
        return item

def add_menu_item(self, menu, label='EMPTY', on_activate=lambda _: print('add_menu_item: on_activate empty')):
    item = Gtk.MenuItem(label=label)
    item.connect('activate', on_activate)
    menu.append(item)

def str2bool(str):
    if not str or str.lower() in ['false', 'no', 'n', '0']:
        return False
    return True

# Returns the original string if it doesn't appear to be a bool.
def try_convert_str2bool(str: str):
    if str.lower() in [None, '', 'false', 'no', 'n', '0']:
        return False
    elif str.lower() in ['true', 'yes', 'y', '1']:
        return True
    return str
