import gi

from common import geo

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib, Gio, GdkPixbuf
from gi.repository import AppIndicator3 as appindicator

class UpdateMenuItem(Gtk.MenuItem):
    added_to_menu = False

    def __init__(self, app, update_interval):
        self.update_interval = update_interval
        super().__init__(label='Checking for updates...')
        self.update_available = False
        self.app = app
        self.separator = Gtk.SeparatorMenuItem()
        self.connect('activate', self.update)
        self.app.menu.append(self.separator)
        self.app.menu.append(self)

        # Run once later so that 'Checking for updates' is initially displayed.
        GLib.timeout_add(2000, lambda: not self.set_update_status())
        GLib.timeout_add(update_interval, self.set_update_status)

    def update(self, source):
        geo.update()
        self.set_update_status()

    def set_update_status(self, source=None):
        self.update_available = geo.is_update_available()
        version = geo.get_config('VERSION')
        if version:
            self.app.set_state('version', version)
        if not self.added_to_menu:
            self.app.menu.append(self.separator)
            self.app.menu.append(self)
            self.added_to_menu = True
        if self.update_available:
            self.set_label('●   Update Now')
            # self.app.menu.append(self.separator)
            # self.app.menu.append(self)
            self.set_sensitive(True)
            self.app.menu.show_all()
            self.app.icon_manager.set_update_available(True)
            self.show()
        elif version:
            self.set_label(f'v{version}')
            self.set_sensitive(False)
            self.app.icon_manager.set_update_available(False)
            self.show()
        else:
            self.set_label('geo-cli is up-to-date')
            self.app.icon_manager.set_update_available(False)
            self.set_sensitive(False)
            # self.app.menu.remove(self.separator)
            # self.app.menu.remove(self)
            self.hide()
        return True

    def show_submenu(self, source):
        self.submenu.show_all()