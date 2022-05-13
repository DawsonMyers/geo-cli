import gi
import os
import sys
import signal
import time
import subprocess
import webbrowser

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')

from gi.repository import Gtk, GLib, Gio, Notify, GdkPixbuf
from gi.repository import AppIndicator3 as appindicator

from src.py.common import geo
from src.py.common import util
from src.py.common import config