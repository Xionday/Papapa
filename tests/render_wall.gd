extends SceneTree
## 離線渲染撞牆雷射光，輸出 PNG 供檢查。
## 用法：godot --path . -s tests/render_wall.gd   （不能 --headless，需要渲染；在 CI 用 xvfb）

var _frames := 0
var _vp: SubViewport
var _game: Node2D
var _shots := [[0.06, "wall_corner_a.png"], [0.18, "wall_corner_b.png"], [0.35, "wall_corner_c.png"]]
var _shot_i := 0
var _t := 0.0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate()
	_vp.add_child(_game)


func _capture(name: String, t: float) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png("res://build/" + name)
	print("saved ", name, " at t=", t)


func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_game.get_node("HUD/Menu").visible = false
		_game.start_game("endless")
		_game.debug_freeze = true
		_game.state = "air"
		_game.ball_h = 0.4
		_game.v_up = 2.0
		_game.ball_pos = Vector2(200.0, 300.0)
		_game.debug_wall_hit(720.0 - 40.0, 1280.0 - 60.0)
		_game.debug_wall_hit(0.0, 400.0)
		_t = 0.0
		return false
	if _frames > 3:
		_t += delta
		if _shot_i < _shots.size() and _t >= _shots[_shot_i][0]:
			var name: String = _shots[_shot_i][1]
			_shot_i += 1
			_capture(name, _t)
		if _shot_i >= _shots.size():
			quit()
			return true
	return false
