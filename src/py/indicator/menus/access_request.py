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
        self.item_iap_start_prev = item_iap_start_prev
        item_iap_start_prev.set_submenu(Gtk.Menu())
        
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

        GLib.timeout_add(1000, self.monitor)

    def monitor(self):
        menu = self.item_iap_start_prev.get_submenu()
        prev_cmds_str = geo.get_config('AR_IAP_CMDS')
        items = [item for item in menu.get_children()]
        items_dict = {item.cmd: item for item in menu.get_children()}
        cur_cmds = [item.cmd for item in items]
        cur_cmds_set = set(cur_cmds)
        if not prev_cmds_str:
            if not items:
                return True
            for item in items:
                menu.remove(item)
                item.destroy()

        cmds = prev_cmds_str.split('@')
        cmds_set = set(cmds)

        to_remove = cur_cmds_set - cmds_set
        to_add = cmds_set - cur_cmds_set
        if not to_remove and not to_add:
            return True

        for cmd in to_remove:
            item = items_dict[cmd]
            menu.remove(item)
            item.destroy()
            cur_cmds.remove(cmd)

        try:
            for i in range(len(cmds)):
                cmd = cmds[i]
                if cmd not in cur_cmds:
                    tag = cmd.split(' ')[3]
                    item = IapCommandMenuItem(tag, cmd)
                    menu.insert(item, i)
                    cur_cmds.insert(i, cmd)
                if cmd in cur_cmds and i != cur_cmds.index(cmd):
                    item = items_dict[cmd]
                    menu.remove(item)
                    menu.insert(item, i)
        except:
            print('Error while parsing geo ar commands')
        menu.show_all()
        return True


class IapCommandMenuItem(Gtk.MenuItem):
    def __init__(self, tag, cmd):
        super().__init__(label=tag)
        self.tag = tag
        self.cmd = cmd
        self.connect('activate', self.start_tunnel)

    def start_tunnel(self, w):
        geo.run_in_terminal('ar tunnel %s' % self.cmd)
