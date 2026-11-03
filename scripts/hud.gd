extends CanvasLayer
## HUD：連擊(小、上)、分數(大)、判定字樣、除錯數值、參數滑桿。文字先用英文（Web 版沒有 CJK 字型）。

@onready var _game: Node2D = get_parent()
@onready var _sensor: Node = get_parent().get_node("SensorBridge")
@onready var _combo: Label = $Top/Combo
@onready var _score: Label = $Top/Score
@onready var _judge: Label = $Top/Judge
@onready var _msg: Label = $Top/Msg
@onready var _debug: Label = $Top/Debug
@onready var _panel: PanelContainer = $Panel
@onready var _sliders_box: VBoxContainer = $Panel/VBox/Sliders
@onready var _tune_btn: Button = $Buttons/Tune
@onready var _zero_btn: Button = $Buttons/Zero
@onready var _results: PanelContainer = $Results
@onready var _results_text: Label = $Results/VBox/Text
@onready var _again_btn: Button = $Results/VBox/PlayAgain
@onready var _menu_btn: Button = $Results/VBox/Menu
@onready var _menu: PanelContainer = $Menu
@onready var _endless_btn: Button = $Menu/VBox/Endless
@onready var _zone_mode_btn: Button = $Menu/VBox/Zone
@onready var _test_haptic: Button = $Panel/VBox/Tests/TestHaptic
@onready var _show_switch: Button = $Panel/VBox/Tests/ShowSwitch
@onready var _test_sound: Button = $Panel/VBox/Tests/TestSound
@onready var _zone_btn: Button = $Panel/VBox/Tests/ZoneToggle

## name, property, min, max, step
const PARAMS := [
	["zone size x", "zone_scale", 0.5, 2.0, 0.1],
	["zone distance x", "zone_dist_scale", 0.3, 2.0, 0.1],
	["hit threshold m/s²", "hit_threshold", 0.5, 10.0, 0.25],
	["timing bias s", "timing_bias", -0.2, 0.2, 0.01],
	["perfect window s", "perfect_dt", 0.02, 0.2, 0.01],
	["good window s", "good_dt", 0.05, 0.4, 0.01],
	["grace after land s", "grace_after", 0.0, 0.3, 0.01],
	["move px per m", "px_per_m", 0.0, 4000.0, 100.0],
	["move damping", "move_damping", 0.0, 6.0, 0.25],
	["move deadzone m/s²", "move_deadzone", 0.2, 2.0, 0.1],
	["move zupt s", "move_zupt", 0.05, 0.5, 0.01],
	["center strength", "center_strength", 0.0, 1.0, 0.05],
	["bad launch x", "bad_launch", 0.3, 0.95, 0.05],
	["full launch m/s (this mode)", "full_launch", 3.0, 9.0, 0.1],
	["lateral gain (this mode)", "lateral_gain", 0.0, 400.0, 10.0],
	["show height m", "show_height", 0.2, 1.5, 0.05],
]

const GRADE_COLOR := {
	"perfect": Color(0.36, 0.79, 0.65),
	"good": Color(0.53, 0.72, 0.92),
	"bad": Color(0.98, 0.78, 0.46),
	"miss": Color(0.98, 0.6, 0.3),
}

var _msg_timer: float = 0.0
var _judge_timer: float = 0.0
var _last_event: String = ""


func _ready() -> void:
	_panel.visible = false
	_tune_btn.pressed.connect(func(): _panel.visible = not _panel.visible)
	_zero_btn.pressed.connect(func():
		_game.calibrate_tilt()
		_show_msg("tilt zeroed"))
	_results.visible = false
	_menu.visible = true
	_endless_btn.pressed.connect(func():
		_menu.visible = false
		_game.start_game("endless"))
	_zone_mode_btn.pressed.connect(func():
		_menu.visible = false
		_game.start_game("zone"))
	_menu_btn.pressed.connect(func():
		_results.visible = false
		_game.to_menu()
		_menu.visible = true)
	_again_btn.pressed.connect(func():
		_results.visible = false
		_game.play_again())
	_game.judged.connect(_on_judged)
	_game.stopped.connect(_on_stopped)
	_test_haptic.pressed.connect(func():
		_sensor.haptic(3)
		_show_msg("haptic x3 (%s)" % _sensor.haptic_mode))
	_show_switch.pressed.connect(func():
		_sensor.show_haptic_switch()
		_show_msg("tap the switch at bottom-left"))
	_zone_btn.text = "zone: on" if _game.zone_mode else "zone: off"
	_zone_btn.pressed.connect(func():
		_game.zone_mode = not _game.zone_mode
		_zone_btn.text = "zone: on" if _game.zone_mode else "zone: off")
	_test_sound.pressed.connect(func():
		_game.get_node("Sfx").play("perfect")
		_show_msg("sound: perfect"))
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


func _on_judged(grade: String, dt: float, streak: int, score: int) -> void:
	_judge.text = grade.to_upper()
	_judge.add_theme_color_override("font_color", GRADE_COLOR[grade])
	_judge_timer = 0.7
	_last_event = "%s  dt %+.0f ms  peak %.1f  launch %.1f" % [grade, dt * 1000.0, _game.last_peak, _game.last_launch]


func _on_stopped(streak: int, score: int, st: Dictionary) -> void:
	_judge.text = "STOPPED"
	_judge.add_theme_color_override("font_color", Color(0.89, 0.29, 0.29))
	_judge_timer = 1.5
	_last_event = "STOPPED  last %s  peak %.1f" % [_game.last_grade, _game.last_peak]
	var c: Dictionary = st["counts"]
	var reason: String = "fell outside the zone" if _game.fell_outside else "two bad hits in a row"
	_results_text.text = "\n".join([
		"ROUND OVER - " + reason,
		"zones reached %d" % (_game.zone_index + 1) if _game.zone_mode else "",
		"",
		"score   %d   (best %d)" % [score, _game.best_score],
		"combo   %d   (best %d)" % [streak, _game.best_streak],
		"",
		"perfect %d   good %d   bad %d   miss %d" % [c["perfect"], c["good"], c["bad"], c["miss"]],
		"",
		"timing offset (swing - landing), %d hits" % st["hits"],
		"  - = early, + = late",
		"  avg %+.0f ms   median %+.0f ms" % [st["dt_avg"] * 1000.0, st["dt_med"] * 1000.0],
		"  min %+.0f ms   max %+.0f ms" % [st["dt_min"] * 1000.0, st["dt_max"] * 1000.0],
		"swing peak avg %.1f m/s²" % st["peak_avg"],
		"",
		"windows: bias %+.0f ms, perfect <= %.0f ms, good <= %.0f ms" % [_game.timing_bias * 1000.0, _game.perfect_dt * 1000.0, _game.good_dt * 1000.0],
	])
	_results.visible = true


func _show_msg(t: String) -> void:
	_msg.text = t
	_msg_timer = 1.5


func _process(delta: float) -> void:
	_msg_timer -= delta
	if _msg_timer <= 0.0:
		_msg.text = ""
	_judge_timer -= delta
	if _judge_timer <= 0.0:
		_judge.text = ""
	_debug.visible = not _results.visible and not _menu.visible
	$Top.visible = not _menu.visible
	_combo.text = "combo %d   (best %d)" % [_game.streak, _game.best_streak]
	_score.text = "%d" % _game.score
	_debug.text = "\n".join([
		"sensor %s  %d Hz  fps %d  haptic %s" % [_sensor.status, _sensor.hz, Engine.get_frames_per_second(), _sensor.haptic_mode],
		"up accel %+5.1f   horiz %4.1f   h %.2f m   zone %d left %d" % [_game.up_accel, _game.horiz_accel.length(), _game.ball_h, _game.zone_index, _game.zone_left],
		"tilt %+4.1f %+4.1f   vel %+.2f %+.2f   last move %.0f px" % [_game.tilt.x, _game.tilt.y, _game.phone_vel.x, _game.phone_vel.y, _game.last_move_px],
		_last_event,
	])
