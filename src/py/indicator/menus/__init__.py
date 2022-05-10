import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib

# from .db import UpdateMenuItem

# import db
# from .db import *
# from .help import *
# from .update import *
from src.py.indicator.menus.db import RunningDbMenuItem, DbMenu, DbMenuItem
from src.py.indicator.menus.update import UpdateMenuItem
from src.py.indicator.menus.help import HelpMenuItem

# def get_running_db_label_text(db):
#     return 'Running DB [%s]' % db
#
#
# def get_running_db_none_label_text():
#     return 'Running DB [None]'

