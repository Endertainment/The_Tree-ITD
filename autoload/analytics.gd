extends Node
## Debug-only analytics facade. No SDK ships in the MVP.
##
## Every call is safe in release builds: `log_event` simply returns.

var _screen := ""


## Logs an event. Prints in debug builds only, prefixed with `[analytics]`.
func log_event(name: String, params: Dictionary = {}) -> void:
	if not OS.is_debug_build():
		return
	if params.is_empty():
		print("[analytics] ", name)
	else:
		print("[analytics] ", name, " ", JSON.stringify(params))


## Records and logs the currently visible screen.
func set_screen(screen_name: String) -> void:
	_screen = screen_name
	log_event("screen_view", {"screen": screen_name})


## Returns the last screen passed to `set_screen`.
func get_screen() -> String:
	return _screen
