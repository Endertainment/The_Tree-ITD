class_name BossBar
extends Control
## Top-of-screen boss bar: name, HP percentage and a pulsing enraged state.

const ROMAN: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var _boss: Boss
var _pulse := 0.0

@onready var _name: Label = %NameLabel
@onready var _bar: ProgressBar = %BossHpBar
@onready var _percent: Label = %PercentLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## Binds the bar to a boss that just spawned.
func show_boss(boss: Boss) -> void:
	_boss = boss
	if _boss == null:
		visible = false
		return
	_name.text = "%s %s" % [Loc.t_key(_boss.data.display_name_key), _roman(_boss.boss_index)]
	_bar.value = 100.0
	_percent.text = "100%"
	_pulse = 0.0
	visible = true


## Hides the bar and forgets the boss.
func hide_boss() -> void:
	_boss = null
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _boss == null or not is_instance_valid(_boss):
		hide_boss()
		return
	if not _boss.is_alive:
		return
	var ratio := _boss.get_hp_ratio()
	_bar.value = clampf(ratio * 100.0, 0.0, 100.0)
	_percent.text = Loc.format_percent(ratio * 100.0)
	if _boss.is_enraged():
		_pulse += delta * 6.0
		_name.modulate = Color(1.0, 0.55, 0.45).lerp(Color(1.0, 0.8, 0.7), 0.5 + 0.5 * sin(_pulse))
	else:
		_name.modulate = Color.WHITE


func _roman(index: int) -> String:
	if index >= 1 and index <= ROMAN.size():
		return ROMAN[index - 1]
	return str(index)
