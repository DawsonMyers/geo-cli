import gi
import webbrowser

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib

from src.py.common import geo


class HelpMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.set_label('Help')
        submenu = Gtk.Menu()

        item_show_notifications = ShowNotificationsMenuItem(self)
        # Gtk.CheckMenuItem(label='Show Notifications')

        item_disable = Gtk.MenuItem(label='Disable')
        item_disable.connect('activate', self.show_disable_dialog)

        item_readme = Gtk.MenuItem(label='View Readme')
        item_readme.connect('activate', self.show_readme)

        submenu.append(item_show_notifications)
        submenu.append(Gtk.SeparatorMenuItem())
        submenu.append(item_readme)
        submenu.append(item_disable)
        self.set_submenu(submenu)

    def show_disable_dialog(self, widget):
        dialog = Gtk.MessageDialog(
            transient_for=None,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Disable geo-cli app indicator?",
        )
        dialog.format_secondary_text(
            "The indicator can be re-enabled by running 'geo indicator enable' in a terminal."
        )
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            print("WARN dialog closed by clicking OK button")
            self.disable()
        elif response == Gtk.ResponseType.CANCEL:
            print("WARN dialog closed by clicking CANCEL button")

        dialog.destroy()

    def show_readme(self, source):
        webbrowser.open('https://git.geotab.com/dawsonmyers/geo-cli', new=2)

    def disable(self):
        geo.run('indicator disable')
        self.app.quit(None)


class ShowNotificationsMenuItem(Gtk.CheckMenuItem):
    def __init__(self, app):
        super().__init__(label='Show Notification')
        self.app = app
        self.enabled = geo.get_config('SHOW_NOTIFICATIONS') != 'false'
        # if not self.enabled:
        #     self.set_label("Disable DB Auto-Switch")
        self.set_active(self.enabled)
        self.connect('toggled', self.handle_toggle)
        self.show_all()
        GLib.timeout_add(1000, self.monitor)

    def handle_toggle(self, src):
        notifications_setting = geo.get_config('SHOW_NOTIFICATIONS') != 'false'
        new_state = not notifications_setting
        new_state_str = 'true' if new_state else 'false'
        geo.set_config('SHOW_NOTIFICATIONS', new_state_str)
        self.enabled = new_state
        self.set_active(new_state)

    def monitor(self):
        notifications_setting = geo.get_config('SHOW_NOTIFICATIONS') != 'false'
        if self.enabled != notifications_setting:
            self.enabled = notifications_setting
            self.set_active(notifications_setting)
