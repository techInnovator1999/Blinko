# dmgbuild settings for the Blinko install window. Driven by scripts/make-dmg.sh via -D defines:
#   app=<path to Blinko.app>  background=<bg.tiff>  icon=<AppIcon.icns>
import os.path

app = defines["app"]
appname = os.path.basename(app)

WINDOW_W = int(defines.get("w", 920)); WINDOW_H = int(defines.get("h", 400))
format = defines.get("format", "UDZO")
compression_level = 9
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")
badge_icon = None

background = defines["background"]
window_rect = ((200, 140), (WINDOW_W, WINDOW_H))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    appname: (300, 190),
    "Applications": (620, 190),
}
hide_extension = [appname]
