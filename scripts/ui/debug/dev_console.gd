class_name DevConsole
extends CanvasLayer
## Debug-only command console, toggled with F2.
##
## Supports `LOCALE <code>`, `BENCHMARK` and `HELP`. The node frees itself
## immediately in release builds, so it can never ship as a live surface.

const TOGGLE_KEY := KEY_F2

@onready var _panel: PanelContainer = %Panel
@onready var _command_input: LineEdit = %CommandInput
@onready var _output: Label = %Output

var _open := false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_command_input.text_submitted.connect(_on_submitted)
	_panel.visible = false
	_print_line(Loc.t_key("DEV_HINT"))


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode != TOGGLE_KEY:
		return
	toggle()
	get_viewport().set_input_as_handled()


## Shows or hides the console, focusing the prompt when opened.
func toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _open:
		_command_input.grab_focus()
		_command_input.clear()
	else:
		_command_input.release_focus()


## True while the prompt is visible.
func is_open() -> bool:
	return _open


## Runs one command line and returns the console reply.
func run_command(line: String) -> String:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return ""
	var parts := trimmed.split(" ", false)
	var command := str(parts[0]).to_upper()
	var args := parts.slice(1)
	var reply := ""
	match command:
		"HELP":
			reply = Loc.t_key("DEV_HELP")
		"LOCALE":
			reply = _command_locale(args)
		"BENCHMARK":
			reply = _command_benchmark()
		_:
			reply = Loc.t_key("DEV_UNKNOWN", {"name": command})
	return reply


func _command_locale(args: PackedStringArray) -> String:
	var target := str(args[0]).to_lower() if args.size() > 0 else _next_locale()
	Loc.set_locale(target)
	return Loc.t_key("DEV_LOCALE_SET", {"locale": Loc.get_locale()})


func _next_locale() -> String:
	return "uk" if Loc.get_locale() == "en" else "en"


func _command_benchmark() -> String:
	var scene := get_tree().current_scene
	if scene is Battle:
		(scene as Battle).run_benchmark()
		return Loc.t_key("DEV_BENCH_RUNNING")
	return Loc.t_key("DEV_BENCH_BATTLE_ONLY")


func _on_submitted(line: String) -> void:
	var reply := run_command(line)
	if not reply.is_empty():
		_print_line(reply)
	_command_input.clear()
	if _open:
		_command_input.grab_focus()


func _print_line(text: String) -> void:
	_output.text = text
