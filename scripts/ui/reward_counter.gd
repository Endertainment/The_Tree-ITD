class_name RewardCounter
extends VBoxContainer
## Caption + animated number used by the results screen for Gold and Gems.

const COUNT_SECONDS := 0.9

var _tween: Tween

@onready var _caption: Label = %Caption
@onready var _value: Label = %Value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Sets the localized caption, e.g. CURRENCY_GOLD.
func setup(caption_key: String) -> void:
	_caption.text = Loc.t_key(caption_key)


## Shows `amount` immediately.
func set_value_now(amount: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_value.text = Loc.format_number(maxi(0, amount))


## Animates from zero (or the current value) up to `amount`.
func count_to(amount: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var start := 0.0
	if _value.text != "":
		start = float(_value.text.replace(Loc.THIN_SPACE, "").to_int())
	if start > float(amount):
		start = 0.0
	_tween = create_tween()
	_tween.tween_method(_set_display_value, start, float(maxi(0, amount)), COUNT_SECONDS)


func _set_display_value(value: float) -> void:
	_value.text = Loc.format_number(int(round(value)))
