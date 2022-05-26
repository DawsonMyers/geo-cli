import os
from common.config import INDICATOR_DIR

GEO_CLI = os.path.join(INDICATOR_DIR, 'res', 'geo-cli-logo.png')
GREEN_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green.svg')
GREEN_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-green-update.svg')
GREY_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey.svg')
GREY_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-grey-update.svg')
RED_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red.svg')
RED_UPDATE_PATH = os.path.join(INDICATOR_DIR, 'res', 'geo-icon-red-update.svg')
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
        self.update_icon()

    def set_update_available(self, update_available):
        self.update_available = update_available
        self.update_icon()

    def update_icon(self):
        if self.cur_icon == RED:
            img_path = RED_UPDATE_PATH if self.update_available else RED_PATH
            self.indicator.set_icon_full(img_path, "geo-cli: No DB running")
        elif self.cur_icon == GREEN:
            img_path = GREEN_UPDATE_PATH if self.update_available else GREEN_PATH
            self.indicator.set_icon_full(img_path, 'geo-cli: DB running')
            # self.indicator.set_attention_icon_full(img_path, 'geo-cli: DB running')
        elif self.cur_icon == ORANGE:
            img_path = ORANGE_UPDATE_PATH if self.update_available else ORANGE_PATH
            self.indicator.set_icon_full(img_path, 'geo-cli: DB Error')

    def set_icon(self, icon_type):
        icon_changed = self.cur_icon is not icon_type
        self.cur_icon = icon_type
        if icon_changed:
            self.update_icon()