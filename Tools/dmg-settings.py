# Layout of the Lanes disk image window, read by dmgbuild (release.sh runs it).
# Icon centers match Tools/render-dmg-background.swift, which draws the title,
# the arrow between the icons and the hint below them.
import os.path

app = defines["app"]
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [name]
icon = defines["volume_icon"]
background = defines["background"]

window_rect = ((200, 140), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {name: (160, 196), "Applications": (480, 196)}
