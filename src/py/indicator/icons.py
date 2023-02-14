import os
from common.config import INDICATOR_DIR

GEO_CLI = os.path.join(INDICATOR_DIR, 'res', 'geo-cli-logo.png')

# Green icons mean that a geo-cli db is running. The variants of if are to communicate additional state information.
GREEN_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green.svg')
# A geo-cli db is running AND an instance MyGeotab is running.
GREEN_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-myg.svg')
GREEN_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-gw.svg')
GREEN_MYG_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-myg-gw.svg')
# A geo-cli db is running AND there is an update available.
GREEN_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update.svg')
# A geo-cli db is running AND there is an update available AND an instance MyGeotab is running.
GREEN_UPDATE_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update-myg.svg')
GREEN_UPDATE_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update-gw.svg')
GREEN_UPDATE_MYG_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update-myg-gw.svg')

# Red icons mean that NO geo-cli db is running. The variants of if are to communicate additional state information.
RED_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red.svg')
# NO geo-cli db is running AND an instance MyGeotab is running.
RED_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-myg.svg')
# NO geo-cli db is running AND there is an update available.
RED_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update.svg')
# NO geo-cli db is running AND there is an update available AND an instance MyGeotab is running.
RED_UPDATE_MYG_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update-myg.svg')

RED_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-gw.svg')
RED_MYG_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-myg-gw.svg')
RED_UPDATE_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update-gw.svg')
RED_UPDATE_MYG_GW_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update-myg-gw.svg')

# Not used at the moment.
GREY_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey.svg')
GREY_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey-update.svg')
ORANGE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-orange.svg')
ORANGE_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-orange-update.svg')
SPINNER_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-spinner.svg')

RED = 'red'
GREEN = 'green'
ORANGE = 'orange'

class IconPaths():
    def __init__(self, normal, myg, gw, update, myg_update, gw_update, myg_gw, myg_gw_update):
        self.normal = normal
        self.myg = myg
        self.gw = gw
        self.update = update
        self.myg_update = myg_update
        self.gw_update = gw_update
        self.myg_gw = myg_gw
        self.myg_gw_update = myg_gw_update
        
green_icon_paths = IconPaths(GREEN_PATH, GREEN_MYG_PATH, GREEN_GW_PATH, GREEN_UPDATE_PATH, GREEN_UPDATE_MYG_PATH, GREEN_UPDATE_GW_PATH, GREEN_MYG_GW_PATH, GREEN_UPDATE_MYG_GW_PATH)
red_icon_paths = IconPaths(RED_PATH, RED_MYG_PATH, RED_GW_PATH, RED_UPDATE_PATH, RED_UPDATE_MYG_PATH, RED_UPDATE_GW_PATH, RED_MYG_GW_PATH, RED_UPDATE_MYG_GW_PATH)

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
        if self.update_available != update_available: 
            print(f'IconManager.set_update_available: update_available: {update_available}')
        self.update_icon()

    def set_myg_running(self, myg_running):
        if self.myg_running != myg_running: 
            print(f'IconManager.set_myg_running: myg_running: {myg_running}')
        self.myg_running = myg_running
        self.update_icon()

    def set_gateway_running(self, gateway_running):
        if self.gateway_running != gateway_running: 
            print(f'IconManager.set_gateway_running: gateway_running: {gateway_running}')
        self.gateway_running = gateway_running
        self.update_icon()

    def update_icon(self):
        message = ''
        if self.cur_icon == RED:
            # img_path = RED_UPDATE_PATH if self.update_available else RED_PATH
            img_path = self.get_state_icon_path(red_icon_paths)
            message = 'geo-cli: No DB running'
            # self.indicator.set_icon_full(img_path, "geo-cli: No DB running")
        elif self.cur_icon == GREEN:
            # # img_path = GREEN_UPDATE_PATH if self.update_available else GREEN_PATH
            # if self.update_available:
            #     img_path = GREEN_MYG_UPDATE_PATH if self.myg_running else GREEN_UPDATE_PATH
            # else:
            #     img_path = GREEN_MYG_PATH if self.myg_running else GREEN_PATH
            img_path = self.get_state_icon_path(green_icon_paths)
            message = 'geo-cli: DB running'
            # self.indicator.set_icon_full(img_path, 'geo-cli: DB running')
            # self.indicator.set_attention_icon_full(img_path, 'geo-cli: DB running')
        elif self.cur_icon == ORANGE:
            img_path = ORANGE_UPDATE_PATH if self.update_available else ORANGE_PATH
            message = 'geo-cli: DB Error'
            # self.indicator.set_icon_full(img_path, 'geo-cli: DB Error')
        
        # Only set icon if it's changed.
        if img_path != self.cur_icon_path:
            self.cur_icon_path = img_path
            self.indicator.set_icon_full(img_path, message)
            print(f'IconManager.update_icon: {message}. Path: {img_path}')

    def set_icon(self, icon_type):
        icon_changed = self.cur_icon is not icon_type
        self.cur_icon = icon_type
        if icon_changed:
            self.update_icon()
            
    def get_state_icon_path(self, icons):
        if self.update_available:
            if self.myg_running and self.gateway_running:
                return icons.myg_gw_update
            if self.myg_running:
                return icons.myg_update
            if self.gateway_running:
                return icons.gw_update
            return icons.update
        if self.myg_running and self.gateway_running:
            return icons.myg_gw
        if self.myg_running:
            return icons.myg
        if self.gateway_running:
            return icons.gw
        return icons.normal

