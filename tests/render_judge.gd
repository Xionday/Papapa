extends SceneTree
## 渲染四個判定門檻時的畫面（環與球的相對位置），輸出 build/judge_*.png

var _f := 0
var _vp: SubViewport
var _game: Node2D
var _shots: Array = []
var _i := 0
var _t := 0.0
var _busy := false


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_game = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_game)


func _setup_gap(gap: float) -> void:
	_game.get_node("HUD/Menu").visible = false
	_game.get_node("HUD").dev_mode = false
	_game.start_game("endless")
	_game.debug_freeze = true
	_game.state = "air"
	_game.v_up = -1.0
	_game.streak = 12
	_game.best_streak = 40
	_game.counter_visible = true
	## 讓 _ring_gap_at(now) == gap：u = 1 - gap/(start-R)
	var start: float = _game._ring_start()
	var u: float = 1.0 - gap / (start - _game.BALL_R_LAND)
	var T := 0.6
	## 截圖在設定後第 3 幀，時間會多走 3/60 s，先補回去
	var lead: float = 3.0 / 60.0
	_game._t_apex = _game._now() + lead - u * T
	_game._t_land_pred = _game._t_apex + T
	## 球高度：用落地前的時間估（自由落體，v_land ≈ 5.9）
	var t_left: float = (1.0 - u) * T
	_game.ball_h = min(0.59, 5.9 * t_left - 4.9 * t_left * t_left)
	_game.ball_pos = Vector2(0, 60)


func _cap(name: String) -> void:
	_vp.get_texture().get_image().save_png("res://build/" + name)
	print("saved ", name)


const CASES := [
	[380.0, "judge_bad_edge.png"],
	[200.0, "judge_good_edge.png"],
	[70.0, "judge_perfect_edge.png"],
	[0.0, "judge_land.png"],
]
var _phase := 0


func _process(_delta: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	## 每個案例：設定 → 等 3 幀 → 截圖
	var step: int = (_f - 3) % 4
	var idx: int = (_f - 3) / 4
	if idx >= CASES.size():
		quit()
		return true
	if step == 0:
		_setup_gap(CASES[idx][0])
	elif step == 3:
		_cap(CASES[idx][1])
	return false
