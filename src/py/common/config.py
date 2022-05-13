import os

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
BASE_DIR = os.path.dirname(BASE_DIR)
INDICATOR_DIR = os.path.join(BASE_DIR, 'indicator')
GEO_SRC_DIR = os.path.dirname(BASE_DIR)
# GEO_SRC_DIR = os.path.dirname(GEO_SRC_DIR)
GEO_CMD_BASE = GEO_SRC_DIR + '/geo-cli.sh '