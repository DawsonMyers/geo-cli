import gi
import webbrowser

from indicator.menus.components import PersistentCheckMenuItem

gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, GLib

from common import geo


class HelpMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.set_label('Help')
        submenu = Gtk.Menu()

        item_show_notifications = ShowNotificationsMenuItem(app)

        item_disable = Gtk.MenuItem(label='Disable')
        item_disable.connect('activate', self.show_disable_dialog)

        item_readme = Gtk.MenuItem(label='View Readme')
        item_readme.connect('activate', self.show_readme)

        item_force_update = Gtk.MenuItem(label='Force Update')
        item_force_update.connect('activate', lambda _: geo.run_in_terminal('update -f', stay_open_after=True))
        item_restart_ui = Gtk.MenuItem(label='Restart geo-ui')
        item_restart_ui.connect('activate', lambda _: geo.run('indicator restart'))
         
        submenu.append(item_show_notifications)
        # submenu.append(Gtk.SeparatorMenuItem())
        submenu.append(item_readme)
        submenu.append(item_force_update)
        submenu.append(item_restart_ui)
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


class ShowNotificationsMenuItem(PersistentCheckMenuItem):
    def __init__(self, app):
        super().__init__(app,
                         label='Show Notifications',
                         config_id='SHOW_NOTIFICATIONS',
                         app_state_id='show-notification', default_state=True)
