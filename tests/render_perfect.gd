extends SceneTree
## PERFECT 特效的三個時間點：build/perfect_a.png (0.15s) / _b (0.45s) / _c (0.8s)
var _f := 0
var _vp: SubViewport
var _game: Node2D
const SHOTS := [[9, "perfect_a.png"], [27, "perfect_b.png"], [48, "perfect_c.png"]]


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_game = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_game)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		_game.get_node("HUD/Menu").visible = false
		_game.get_node("HUD").dev_mode = false
		_game.start_game("endless")
		_game.debug_freeze = true
		_game.state = "air"
		_game.ball_h = 0.9
		_game.v_up = 3.0
		_game.streak = 12
		_game.counter_visible = true
		_game._spawn_ash()
	for sh in SHOTS:
		if _f == 3 + sh[0]:
			_vp.get_texture().get_image().save_png("res://build/" + sh[1])
			print("saved ", sh[1])
	if _f > 3 + 50:
		quit()
		return true
	return false
