
# Advanced Bash-Scripting Guide:
# Chapter 20. I/O Redirection
# 20.1. Using exec
# https://tldp.org/LDP/abs/html/x17974.html
f() {
    # Link stdin to fd 6, essentially saving a reference to it.
    exec 6<&1;
    # Redirect all further input to stdin to /dev/null.
    exec > /dev/null;
    # This still prints out because it's through sdterr (fd 2).
    echo errrr >&2

    # This is redirected to /dev/null.
    echo to /dev/null
#    echo error #2>&1

     # Restore stdout and close file descriptor #6.
    exec 1>&6 6>&-

    # This will print to stdout.
    echo to stdout
}
f
