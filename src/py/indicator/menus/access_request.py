from indicator import *


class AccessRequestMenuItem(Gtk.MenuItem):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.set_label('Access Request')
        submenu = Gtk.Menu()

        item_create = Gtk.MenuItem(label='Create Access Request')
        item_create.connect('activate', lambda _: geo.run('ar create'))

        item_iap = Gtk.MenuItem(label='IAP Tunnel')
        iap_menu = Gtk.Menu()
        item_iap_start_new = Gtk.MenuItem(label='Start New')
        item_iap_start_new_bind = Gtk.MenuItem(label='Start New & Bind pgAdmin Port 5433')
        item_iap_start_new.connect('activate', lambda _: geo.run_in_terminal('ar tunnel --prompt'))
        item_iap_start_new_bind.connect('activate', lambda _: geo.run_in_terminal('ar tunnel --prompt -L'))
        item_iap_start_prev = Gtk.MenuItem(label='Start Previous')
        self.item_iap_start_prev = item_iap_start_prev
        item_iap_start_prev.set_submenu(Gtk.Menu())
        
        iap_menu.append(item_iap_start_new)
        iap_menu.append(item_iap_start_new_bind)
        iap_menu.append(item_iap_start_prev)
        iap_menu.show_all()
        item_iap.set_submenu(iap_menu)

        item_open_tunnels = OpenIapTunnelMenu()

        submenu.append(item_create)
        submenu.append(item_iap)
        submenu.append(item_open_tunnels)
        self.set_submenu(submenu)
        submenu.show_all()

        GLib.timeout_add(2000, self.monitor)

    def monitor(self):
        menu = self.item_iap_start_prev.get_submenu()
        prev_cmds_str = geo.get_config('AR_IAP_CMDS')
        if not prev_cmds_str:
            prev_cmds_str = geo.get_config('AR_IAP_CMD')
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
        return True


class OpenIapTunnelMenuItem(Gtk.MenuItem):
    def __init__(self, ar_name, iap_port):
    # def __init__(self, ar_name, iap_port, geo_command):
        super().__init__(label=f'{ar_name} ({iap_port})')
        self.ar_name = ar_name
        self.iap_port = iap_port
        self.menu = Gtk.Menu()
        sshItem = Gtk.MenuItem('SSH')
        bindItem = Gtk.MenuItem('Bind Port 5433 to 5432 (for pgAdmin)')
        sshItem.connect('activate', lambda _: geo.run_in_terminal(f'ar ssh -p {iap_port}'))
        bindItem.connect('activate', lambda _: geo.run_in_terminal(f'ar ssh -Lp {iap_port}'))
        self.menu.append(sshItem)
        self.menu.append(bindItem)
        self.menu.show_all()
        self.set_submenu(self.menu)
        
        
class OpenIapTunnelMenu(Gtk.MenuItem):
    items = set()
    init_rebuild = False
    def __init__(self):
        super().__init__(label='Open IAP Tunnels')
        self.open_tunnels = {}
        self.prev_tunnel_str = ''
        self.prev_tunnels = set()
        self.empty_item = Gtk.MenuItem(label='There are no open IAP tunnels')
        self.empty_item.set_sensitive(False)
        self.menu = Gtk.Menu()
        self.menu.append(self.empty_item)
        self.menu.show_all()
        # self.items.add(self.empty_item)
        self.set_submenu(self.menu)
        self.show_all()
    
        GLib.timeout_add(2000, self.monitor)
        
    def log(self, msg):
        print(f'OpenIapTunnelMenu: {msg}')

    def monitor(self):
        try:
            open_tunnels_str=geo.run('dev open-iap-tunnels')
            
            # This is needed so that multiple instances of this class render correctly; the menu needs to be built twice (for some reason).
            if self.prev_tunnel_str and not self.init_rebuild or (self.empty_item in self.items and not self.init_rebuild):
                self.prev_tunnel_str = ''
                self.prev_tunnels = set()
                self.init_rebuild = True
            cur_tunnels = set(open_tunnels_str.split('|'))
            if not cur_tunnels or cur_tunnels == self.prev_tunnels:
                return True
            print(f'{open_tunnels_str} == {self.prev_tunnel_str} = {open_tunnels_str == self.prev_tunnel_str}')
            self.prev_tunnels = cur_tunnels
            self.prev_tunnel_str = open_tunnels_str
            self.remove_all()
            # tunnels = open_tunnels_str.split('|')
            for tunnel_str in cur_tunnels:
                if not tunnel_str or '=' not in tunnel_str:
                    continue
                self.log(tunnel_str)
                ar_name, iap_port = tunnel_str.split('=')
                # print(ar_name, iap_port)
                if len(ar_name) < 3:
                    print(f'ar_name is too short: {ar_name}')
                    continue
                item = OpenIapTunnelMenuItem(ar_name, iap_port)
                # item = OpenIapTunnelMenuItem(ar_name, iap_port, self.geo_command)
                # print(f'{ar_name} ({iap_port})')
                item.show()
                self.items.add(item)
                self.menu.append(item)
            if not self.items:
                self.log('adding empty item')
                # self.menu.append(self.empty_item)
                self.empty_item.show()
                # self.menu.show_all()
                # self.menu.remove(self.empty_item)
                # Don't know why I need to do this for it to actually get rendered...
                def delayed():
                    # self.menu.append(self.empty_item)
                    self.empty_item.show()
                    self.menu.show_all()
                    self.set_submenu(self.menu)
                GLib.timeout_add(1000, delayed)
            else:
                self.empty_item.hide()
            # for child in self.menu.get_children():
            #     if child == self.empty_item:
            #         self.menu.remove(child)
            # self.menu.show_all()
            # self.show_all()
                
        except Exception as err:
            print('SshOverOpenTunnelMenuItem: ERROR: ' + err)
        return True
    
    def remove_all(self):
        if not self.items:
            self.empty_item.show()
            # self.menu.remove(self.empty_item)
            # self.menu.show_all()
            # self.show_all()
            # self.items.add(self.empty_item)
            return
        for item in self.items:
            self.menu.remove(item)
        self.show_all()
        self.items = set()


class SshOverOpenTunnelMenu(OpenIapTunnelMenu):
    def __init__(self):
        super().__init__(label='SSH Over Open IAP', geo_command='ar ssh -p ')

class BindOverOpenTunnelMenu(OpenIapTunnelMenu):
    def __init__(self):
        super().__init__(label='Bind Port 5433:5432 Over IAP', geo_command='ar ssh -Lp ')