extends CanvasLayer
## HUD：分數、除錯數值、參數滑桿。文字先用英文（Web 版沒有 CJK 字型）。

@onready var _game: Node2D = get_parent()
@onready var _sensor: Node = get_parent().get_node("SensorBridge")
@onready var _score: Label = $Top/Score
@onready var _debug: Label = $Top/Debug
@onready var _panel: PanelContainer = $Panel
@onready var _sliders_box: VBoxContainer = $Panel/VBox/Sliders
@onready var _tune_btn: Button = $Buttons/Tune
@onready var _zero_btn: Button = $Buttons/Zero
@onready var _msg: Label = $Top/Msg

## name, property, min, max, step
const PARAMS := [
	["hit threshold m/s²", "hit_threshold", 1.0, 15.0, 0.5],
	["hit window s", "hit_window", 0.05, 0.4, 0.01],
	["push threshold m/s²", "push_threshold", 1.0, 10.0, 0.5],
	["push distance px", "push_distance", 100.0, 600.0, 10.0],
	["decay (no swing)", "decay", 0.5, 0.95, 0.05],
	["full launch m/s", "full_launch", 3.0, 9.0, 0.1],
	["lateral gain", "lateral_gain", 0.0, 400.0, 10.0],
	["show height m", "show_height", 0.2, 1.5, 0.05],
]

var _value_labels: Dictionary = {}
var _msg_timer: float = 0.0
var _last_event: String = ""


func _ready() -> void:
	_panel.visible = false
	_tune_btn.pressed.connect(func(): _panel.visible = not _panel.visible)
	_zero_btn.pressed.connect(func():
		_game.calibrate_tilt()
		_show_msg("tilt zeroed"))
	_game.hit.connect(_on_hit)
	_game.missed.connect(_on_missed)
	_game.pushed.connect(_on_pushed)
	_build_sliders()


func _build_sliders() -> void:
	for p in PARAMS:
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = p[0]
		name_l.custom_minimum_size.x = 300
		name_l.add_theme_font_size_override("font_size", 22)
		var slider := HSlider.new()
		slider.min_value = p[2]
		slider.max_value = p[3]
		slider.step = p[4]
		slider.value = _game.get(p[1])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 44
		var val_l := Label.new()
		val_l.custom_minimum_size.x = 90
		val_l.add_theme_font_size_override("font_size", 22)
		val_l.text = _fmt(slider.value)
		_value_labels[p[1]] = val_l
		var prop: String = p[1]
		slider.value_changed.connect(func(v: float):
			_game.set(prop, v)
			val_l.text = _fmt(v))
		row.add_child(name_l)
		row.add_child(slider)
		row.add_child(val_l)
		_sliders_box.add_child(row)


func _fmt(v: float) -> String:
	return "%.2f" % v if v < 10.0 else "%.0f" % v


func _on_hit(strong: bool, streak: int) -> void:
	_last_event = "HIT %s  peak %.1f  launch %.1f" % ["strong" if strong else "weak", _game.last_hit_peak, _game.last_launch]
	if not strong:
		_show_msg("weak hit, swing up harder")


func _on_missed(streak: int) -> void:
	_last_event = "MISS after %d" % streak
	_show_msg("missed  (%d)" % streak)


func _on_pushed(dir: Vector2) -> void:
	_last_event = "PUSH (%+.1f, %+.1f)" % [dir.x, dir.y]


func _show_msg(t: String) -> void:
	_msg.text = t
	_msg_timer = 1.2


func _process(delta: float) -> void:
	_msg_timer -= delta
	if _msg_timer <= 0.0:
		_msg.text = ""
	_score.text = "%d   best %d" % [_game.streak, _game.best]
	_debug.text = "\n".join([
		"sensor %s  %d Hz  fps %d" % [_sensor.status, _sensor.hz, Engine.get_frames_per_second()],
		"up accel %+5.1f   horiz %4.1f" % [_game.up_accel, _game.horiz_accel.length()],
		"tilt x %+4.1f y %+4.1f   height %.2f m" % [_game.tilt.x, _game.tilt.y, _game.ball_h],
		_last_event,
	])
