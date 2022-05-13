from indicator import *


class AccessRequestMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.set_label('Access Request')
        submenu = Gtk.Menu()

        item_create = Gtk.MenuItem(label='Create')
        item_create.connect('activate', lambda _: geo.run('ar create'))

        item_iap = Gtk.MenuItem(label='IAP Tunnel')
        iap_menu = Gtk.Menu()
        item_iap_start_new = Gtk.MenuItem(label='Start New')
        item_iap_start_new.connect('activate', lambda _: geo.run_in_terminal('ar tunnel --prompt'))
        item_iap_start_prev = Gtk.MenuItem(label='Start Previous')
        item_iap_start_prev.connect('activate', lambda _: geo.run_in_terminal('ar tunnel'))

        iap_menu.append(item_iap_start_new)
        iap_menu.append(item_iap_start_prev)
        iap_menu.show_all()
        item_iap.set_submenu(iap_menu)

        item_ssh = Gtk.MenuItem(label='SSH Over Open IAP')
        item_ssh.connect('activate', lambda _: geo.run_in_terminal('ar ssh'))

        submenu.append(item_create)
        submenu.append(item_iap)
        submenu.append(item_ssh)
        self.set_submenu(submenu)
        submenu.show_all()