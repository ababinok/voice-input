"""Compact, drag-to-Applications Finder window; no installer UI or README."""

format = "UDZO"
filesystem = "HFS+"
files = [(defines["app"], "Voice Input.app")]
symlinks = {"Программы": "/Applications"}
background = defines["background"]
window_rect = ((200, 200), (540, 300))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 54
icon_size = 96
text_size = 14
label_pos = "bottom"
icon_locations = {"Voice Input.app": (130, 135), "Программы": (410, 135)}
