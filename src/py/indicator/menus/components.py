
from indicator import *
from indicator.geo_indicator import IndicatorApp


class PersistentCheckMenuItem(Gtk.CheckMenuItem):
    enabled = True
    monitor_update = False
    label_checked = None
    label_unchecked = None

    def __init__(self, app: IndicatorApp, label: str, config_id: str, app_state_id: str, default_state=False, label_unchecked:str=''):
        super().__init__(label=label)
        self.label = label
        self.label_checked = label
        self.label_unchecked = label_unchecked
        self.default_state = default_state
        self.app_state_id = app_state_id
        self.config_id = config_id
        self.app = app
        self.enabled = default_state
        self.set_active(self.enabled)
        # self.set_draw_as_radio(True)
        self.show_all()
        GLib.timeout_add(50, self.init)
        GLib.timeout_add(1000, self.monitor)

    def init(self):
        state = self.get_config_state()
        self.enabled = state
        self.set_app_state(state)
        # Set the active state before connecting the toggled signal to handle_toggle. This is needed because setting the
        #  active state causes handle_toggle to be called.
        self.set_active(state)
        self.connect('toggled', self.handle_toggle)

    # To be overridden by subclasses.
    def on_state_changed(self, new_state):
        pass

    def is_enabled(self):
        return self.enabled

    def bool_to_string(self, state: bool):
        return 'true' if state else 'false'

    def string_to_bool(self, bool_string: str):
        return bool_string.lower() == 'true'

    def get_config_state(self):
        state = geo.get_config(self.config_id)
        # Return true if there isn't a state in the config yet and the default_state is true.
        if not state:
            return self.default_state
        return self.string_to_bool(state)

    def set_config_state(self, state: bool):
        geo.set_config(self.config_id, self.bool_to_string(state))

    def set_app_state(self, state: bool):
        self.app.set_state(self.app_state_id, state)

    def handle_toggle(self, src):
        new_state = self.get_active()
        print(f'{self.get_label()} toggle = ' + str(new_state))
        if self.monitor_update:
            self.monitor_update = False
            return
        enabled = self.get_config_state()
        if new_state == enabled:
            return
        if self.label_unchecked:
            self.set_label(self.label_checked if new_state else self.label_unchecked)
        self.enabled = new_state
        self.set_config_state(new_state)
        self.set_app_state(new_state)
        self.on_state_changed(new_state)
        self.show()

    def monitor(self):
        enabled = self.get_config_state()
        if self.enabled != enabled:
            # The active state of the check item determines if the checkmark is shown on it. For some reason, setting this
            # will also fire the toggled signal. So use monitor_update to stop an infinite loop.
            self.monitor_update = True
            self.enabled = enabled
            # self.set_config_state(enabled)
            self.app.set_state(self.app_state_id, enabled)
            self.set_active(enabled)
            self.on_state_changed(enabled)
            self.show()
        return True
