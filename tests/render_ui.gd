extends SceneTree
## 離線渲染三張檢查圖：選單、遊戲中(撞牆光)、結算。輸出到 build/ui_*.png

var _f := 0
var _vp: SubViewport
var _game: Node2D
var _t := 0.0
var _stage := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_game = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_game)


func _cap(name: String) -> void:
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("res://build/" + name)
	print("saved ", name)


func _process(delta: float) -> bool:
	_f += 1
	_t += delta
	match _stage:
		0:
			if _f == 3:
				_stage = 1
				_t = 0.0
				_cap("ui_menu.png")
		1:
			if _t > 0.1:
				_game.get_node("HUD/Menu").visible = false
				_game.start_game("endless")
				_game.debug_freeze = true
				_game.state = "air"
				_game.ball_h = 0.1
				_game.v_up = -1.0
				_game._t_apex = _game._now() - 0.45
				_game._t_land_pred = _game._now() + 0.3
				_game.ball_pos = Vector2(40.0, 180.0)
				_game.streak = 23
				_game.best_streak = 111
				_game.get_node("HUD").dev_mode = false
				_game.debug_wall_hit(720.0, 500.0)
				_game.debug_wall_hit(300.0, 1280.0)
				_stage = 2
				_t = 0.0
		2:
			if _t > 0.14:
				_cap("ui_game.png")
				_stage = 3
				_t = 0.0
		3:
			if _t > 0.3:
				_game.get_node("HUD")._on_stopped(23, 50, {"counts": {"perfect": 12, "good": 8, "bad": 2, "miss": 1}, "hits": 22, "dt_avg": -0.04, "dt_med": -0.05, "dt_min": -0.2, "dt_max": 0.06, "peak_avg": 7.1})
				_game.counter_visible = false
				_stage = 4
				_t = 0.0
		4:
			if _t > 0.1:
				_cap("ui_results.png")
				_stage = 5
		5:
			if _t > 0.3:
				quit()
				return true
	return false
