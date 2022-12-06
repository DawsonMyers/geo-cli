import os
from common.config import INDICATOR_DIR

GEO_CLI = os.path.join(INDICATOR_DIR, 'res', 'geo-cli-logo.png')

# Green icons mean that a geo-cli db is running. The variants of if are to communicate additional state information.
GREEN_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green.svg')
# A geo-cli db is running AND an instance MyGeotab is running.
GREEN_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-myg.svg')
# A geo-cli db is running AND there is an update available.
GREEN_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update.svg')
# A geo-cli db is running AND there is an update available AND an instance MyGeotab is running.
GREEN_UPDATE_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update-myg.svg')

# Red icons mean that NO geo-cli db is running. The variants of if are to communicate additional state information.
RED_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red.svg')
# NO geo-cli db is running AND an instance MyGeotab is running.
RED_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-myg.svg')
# NO geo-cli db is running AND there is an update available.
RED_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update.svg')
# NO geo-cli db is running AND there is an update available AND an instance MyGeotab is running.
RED_UPDATE_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update-myg.svg')

# Not used at the moment.
GREY_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey.svg')
GREY_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey-update.svg')
ORANGE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-orange.svg')
ORANGE_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-orange-update.svg')
SPINNER_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-spinner.svg')

RED = 'red'
GREEN = 'green'
ORANGE = 'orange'


class IconManager:
    def __init__(self, indicator):
        self.indicator = indicator
        self.cur_icon = RED
        self.update_available = False
        self.myg_running = False
        self.gateway_running = False
        self.cur_icon_path = None
        self.update_icon()

    def set_update_available(self, update_available):
        self.update_available = update_available
        self.update_icon()

    def set_myg_running(self, myg_running):
        self.myg_running = myg_running
        self.update_icon()

    def set_gateway_running(self, gateway_running):
        self.gateway_running = gateway_running
        self.update_icon()

    def update_icon(self):
        message = ''
        if self.cur_icon == RED:
            # img_path = RED_UPDATE_PATH if self.update_available else RED_PATH
            img_path = self.get_state_icon_path(RED_PATH, RED_MYG_PATH, RED_UPDATE_PATH, RED_UPDATE_MYG_PATH)
            message = 'geo-cli: No DB running'
            # self.indicator.set_icon_full(img_path, "geo-cli: No DB running")
        elif self.cur_icon == GREEN:
            # # img_path = GREEN_UPDATE_PATH if self.update_available else GREEN_PATH
            # if self.update_available:
            #     img_path = GREEN_MYG_UPDATE_PATH if self.myg_running else GREEN_UPDATE_PATH
            # else:
            #     img_path = GREEN_MYG_PATH if self.myg_running else GREEN_PATH
            img_path = self.get_state_icon_path(GREEN_PATH, GREEN_MYG_PATH, GREEN_UPDATE_PATH, GREEN_UPDATE_MYG_PATH)
            message = 'geo-cli: DB running'
            # self.indicator.set_icon_full(img_path, 'geo-cli: DB running')
            # self.indicator.set_attention_icon_full(img_path, 'geo-cli: DB running')
        elif self.cur_icon == ORANGE:
            img_path = ORANGE_UPDATE_PATH if self.update_available else ORANGE_PATH
            message = 'geo-cli: DB Error'
            # self.indicator.set_icon_full(img_path, 'geo-cli: DB Error')
        
        # Only set icon if it's changed.
        if img_path != self.cur_icon_path:
            self.indicator.set_icon_full(img_path, message)

    def set_icon(self, icon_type):
        icon_changed = self.cur_icon is not icon_type
        self.cur_icon = icon_type
        if icon_changed:
            self.update_icon()
            
    def get_state_icon_path(self, icon, icon_myg, icon_update, icon_myg_update):
        if self.update_available:
                return icon_myg_update if self.myg_running else icon_update
        return icon_myg if self.myg_running else icon
            