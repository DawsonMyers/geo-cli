from src.py.indicator import *


class AccessRequestMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.set_label('Access Request')
        submenu = Gtk.Menu()

        item_create = Gtk.MenuItem(label='Create')
        # item_create.connect('activate', lambda _: )
        item_iap = Gtk.MenuItem(label='Open IAP Tunnel')
        item_ssh = Gtk.MenuItem(label='SSH Over IAP')
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