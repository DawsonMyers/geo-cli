import os
import subprocess
import time


def run_in_terminal_then_close(cmd_to_run, title=''):
    if title:
        title = "--title='%s'" % title
    cmd = "gnome-terminal %s --geometry=80x30 -- bash -c \"bash %s; cd $HOME\"" % (title, cmd_to_run)
    try:
        os.system(cmd)
    except Exception as err:
        print(f'Error running run_in_terminal_then_close("{cmd_to_run}", "{title}"): {err}')


def run_in_terminal(cmd_to_run, title=''):
    if title:
        title = "--title='%s'" % title
    cmd = "gnome-terminal %s --geometry=80x30 -- bash -c \"bash %s; cd $HOME; exec bash\"" % (title, cmd_to_run)
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