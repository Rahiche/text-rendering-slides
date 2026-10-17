"""Installs MakeHuman asset packs (CC0 zips from makehumancommunity.org,
assets/people/CREDITS.md) into MPFB's user data, headless, without touching
Blender's preferences: MPFB (the MakeHuman plugin for Blender, installed
with `blender -c extension install-file -r user_default --no-prefs`) is
enabled for this run only (factory settings, never saved).

  Blender -b --factory-startup -P tool/blender/mpfb_setup.py -- <pack.zip>...
"""

import sys

import addon_utils

argv = sys.argv[sys.argv.index("--") + 1:]
# (Enabled in this session's preferences, which MPFB reads; a factory-startup
# background run never saves them.)
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)

from bl_ext.user_default.mpfb.services.assetservice import AssetService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402

target = LocationService.get_user_data()
print(f"MPFB user data: {target}")
for z in argv:
    problem = AssetService.check_asset_pack_zip(z)
    if problem:
        print(f"PACK {z}: check says {problem}; extracting anyway (fixes structure)")
    result = AssetService.fix_and_extract_asset_pack_zip(z, target)
    print(f"PACK {z}: {result or 'installed'}")
