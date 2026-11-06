extends SceneTree
## 連擊特效各階段：build/combo_<n>.png
var _f := 0
var _vp: SubViewport
var _game: Node2D
const TIERS := [12, 22, 32, 42, 52]
var _i := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_game = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_game)


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var step: int = (_f - 3) % 40
	var idx: int = (_f - 3) / 40
	if idx >= TIERS.size():
		quit()
		return true
	if step == 0:
		_game.get_node("HUD/Menu").visible = false
		_game.get_node("HUD").dev_mode = false
		_game.start_game("endless")
		_game.debug_freeze = true
		_game.state = "air"
		_game.ball_h = 0.25
		_game.v_up = -2.0
		_game.streak = TIERS[idx]
		_game.score = TIERS[idx] * 2
		_game.counter_visible = true
		_game._t_apex = _game._now() + 100.0   ## 不畫收縮環
		_game._wave_level = 1.0
	elif step < 39:
		## 讓球緩慢橫移，軌跡才看得出來
		_game.ball_pos.x += 3.0
	elif step == 39:
		_vp.get_texture().get_image().save_png("res://build/combo_%d.png" % TIERS[idx])
		print("saved combo_", TIERS[idx])
	return false
