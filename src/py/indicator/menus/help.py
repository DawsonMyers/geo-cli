import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib

# def build_help_item(self):
#     help = Gtk.MenuItem(label="Help")
#     submenu = Gtk.Menu()
#
#     item_disable = Gtk.MenuItem(label='Disable')
#     item_disable.connect('activate', self.show_disable_dialog)
#
#     item_readme = Gtk.MenuItem(label='View Readme')
#     item_readme.connect('activate', self.show_readme)
#
#     submenu.append(item_readme)
#     submenu.append(item_disable)
#     help.set_submenu(submenu)
#     return help

class HelpMenuItem(Gtk.MenuItem):
    def __init__(self):
        super().__init__()
        self.set_label('Help')
        submenu = Gtk.Menu()

        item_show_notifications = Gtk.CheckMenuItem(label='Show Notifications')

        item_disable = Gtk.MenuItem(label='Disable')
        item_disable.connect('activate', self.show_disable_dialog)

        item_readme = Gtk.MenuItem(label='View Readme')
        item_readme.connect('activate', self.show_readme)

        submenu.append(item_show_notifications)
        submenu.append(Gtk.SeparatorMenuItem())
        submenu.append(item_readme)
        submenu.append(item_disable)
        self.set_submenu(submenu)
