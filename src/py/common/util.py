import os
import subprocess


def run_in_terminal_then_close(cmd_to_run, title=''):
    if title:
        title = "--title='%s'" % title
    cmd = "gnome-terminal %s --geometry=80x30 -- bash -c \"bash %s; cd $HOME\"" % (title, cmd_to_run)
    os.system(cmd)


def run_in_terminal(cmd_to_run, title=''):
    if title:
        title = "--title='%s'" % title
    cmd = "gnome-terminal %s --geometry=80x30 -- bash -c \"bash %s; cd $HOME; exec bash\"" % (title, cmd_to_run)
    os.system(cmd)


def run_shell_cmd(cmd):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout[0:-1]


def run_cmd_and_wait(cmd):
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, executable='/bin/bash', text=True)
    process.wait()
    result = process.communicate()
    print(result)
