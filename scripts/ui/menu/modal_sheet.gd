class_name ModalSheet
extends Control
## Bottom sheet used for every confirmation and detail popup in the menu.
##
## One instance lives in `MainMenu`; callers open it with a callback instead of
## awaiting a signal, so a double-tap cannot queue two actions.

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _content: VBoxContainer = %Content
@onready var _confirm: Button = %ConfirmButton
@onready var _cancel: Button = %CancelButton
@onready var _dim: ColorRect = %Dim

var _on_confirm: Callable
var _tween: Tween


func _ready() -> void:
	visible = false
	_confirm.pressed.connect(_on_confirm_pressed)
	_cancel.pressed.connect(_on_cancel_pressed)
	_dim.gui_input.connect(_on_dim_input)


## Opens the sheet. Empty `confirm_key` hides the confirm button (detail mode).
func open(
	title: String,
	body: String,
	confirm_key := "",
	cancel_key := "COMMON_CLOSE",
	on_confirm := Callable()
) -> void:
	_title.text = title
	_body.text = body
	_body.visible = not body.is_empty()
	_clear_content()
	_on_confirm = on_confirm
	_confirm.visible = not confirm_key.is_empty()
	_confirm.text = Loc.t_key(confirm_key) if not confirm_key.is_empty() else ""
	_cancel.text = Loc.t_key(cancel_key)
	_confirm.disabled = false
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)


## Hides the sheet.
func close() -> void:
	if not visible:
		return
	visible = false
	_on_confirm = Callable()
	_clear_content()


## Adds a node between the body and the buttons (modifier rows, choices).
func add_content(control: Control) -> void:
	_content.add_child(control)
	_content.visible = true


func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.visible = false


func _on_confirm_pressed() -> void:
	var callback := _on_confirm
	close()
	if callback.is_valid():
		callback.call()


func _on_cancel_pressed() -> void:
	close()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
