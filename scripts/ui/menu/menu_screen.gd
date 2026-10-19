class_name MenuScreen
extends Control
## Base class for the six menu tabs.
##
## `MainMenu` calls `refresh()` every time a screen is shown and whenever meta
## data changes behind it. `main_menu` is intentionally untyped: typing it as
## `MainMenu` would create a cyclic script dependency between the shell and tabs.

## Set by `MainMenu` before the screen enters the tree.
var main_menu


## Re-reads meta state and updates every label. Must be safe to call repeatedly.
func refresh() -> void:
	pass
