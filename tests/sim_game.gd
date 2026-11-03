extends SceneTree
## 整個遊戲場景的模擬：用合成的感測器資料驅動 game.gd，驗證位移在畫面上的效果。
## 用法：godot --headless --path . -s tests/sim_game.gd

var game: Node2D
var DT := 1.0 / 60.0
var rng := RandomNumberGenerator.new()


var _ran := false


func _initialize() -> void:
	rng.seed = 7
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)


## 等場景真的進樹、跑過第一幀之後再測
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	for cfg in [[0.7, 0.05]]:
		game.move_deadzone = cfg[0]
		game.move_lowpass = cfg[1]
		print("==== deadzone %.1f  lowpass %.2f ====" % [cfg[0], cfg[1]])
		_suite()
	quit()


func _suite() -> void:
	game.start_game("zone")

	print("viewport %s   球起始螢幕位置 %s" % [root.get_visible_rect().size, game._to_screen(game.ball_pos)])
	print("")
	print("A. 手機往右平穩移動，不同距離與時間（含手持雜訊 σ=0.4）")
	print("%-10s %-8s %10s %10s %10s" % ["距離", "時間", "paddle px", "球畫面移", "理想 px"])
	for d in [0.05, 0.10, 0.20, 0.30]:
		for T in [0.3, 0.5]:
			game.start_game("zone")
			var before_paddle: Vector2 = game.paddle_pos
			var before_ball: Vector2 = game._to_screen(game.ball_pos)
			_move(Vector2(d, 0.0), T, 0.4)
			_hold(0.6, 0.4)
			var dp: float = (game.paddle_pos - before_paddle).x
			var db: float = (game._to_screen(game.ball_pos) - before_ball).x
			print("%-10s %-8s %10.0f %10.0f %10.0f" % ["%.0f cm" % (d * 100.0), "%.1f s" % T, dp, db, d * PI / 4.0 * game.px_per_m])

	print("")
	print("B. 靜止手持 5 秒，雜訊 σ=0.4 / 0.6 / 0.8，paddle 飄移：")
	for n in [0.4, 0.6, 0.8]:
		game.start_game("zone")
		var p0: Vector2 = game.paddle_pos
		_hold(5.0, n)
		print("  σ=%.1f  飄移 %.0f px" % [n, (game.paddle_pos - p0).length()])

	print("")
	print("C. 往右移 15 cm 再往左移回 15 cm（各 0.4 s），淨位移：")
	game.start_game("zone")
	var q0: Vector2 = game.paddle_pos
	_move(Vector2(0.15, 0.0), 0.4, 0.4)
	_hold(0.4, 0.4)
	var q1: Vector2 = game.paddle_pos
	_move(Vector2(-0.15, 0.0), 0.4, 0.4)
	_hold(0.6, 0.4)
	print("  去程 %.0f px，回程後淨 %.0f px" % [(q1 - q0).x, (game.paddle_pos - q0).x])

	print("")
	print("D. 光圈模式：圈在球右邊 300 px，手機往左移約 15 cm 後球是否在圈內")
	game.start_game("zone")
	game.zone_pos = game._to_screen(game.ball_pos) + Vector2(300.0, 0.0)
	_move(Vector2(-0.153, 0.0), 0.4, 0.4)   ## 手機往左移，球在畫面上往右
	_hold(0.3, 0.4)
	print("  球螢幕位置 %s  圈 %s  距離 %.0f  半徑 %.0f  → %s" % [
		game._to_screen(game.ball_pos), game.zone_pos,
		game._to_screen(game.ball_pos).distance_to(game.zone_pos), game.zone_r,
		"在圈內" if game._in_zone() else "圈外"])


## 餵一幀感測器資料並推進遊戲一幀
func _feed(linear_screen: Vector2, noise: float) -> void:
	## 螢幕座標 (x 右, y 下) → 裝置座標 (x 右, y 上, z 出螢幕)；平放時物理重力 = (0,0,-9.8)
	var lin := Vector3(linear_screen.x, -linear_screen.y, 0.0)
	lin += Vector3(rng.randfn(0.0, noise), rng.randfn(0.0, noise), rng.randfn(0.0, noise))
	var grav := Vector3(0.0, 0.0, -9.8)
	game._on_sample(lin, grav)
	game._process(DT)


## 平穩移動：加速度 = sin 一個週期，位移 = D·π/4
func _move(D: Vector2, T: float, noise: float) -> void:
	var t := 0.0
	while t < T:
		var a: Vector2 = D * (PI * PI / (T * T)) * sin(2.0 * PI * t / T) / 2.0
		_feed(a, noise)
		t += DT


func _hold(T: float, noise: float) -> void:
	var t := 0.0
	while t < T:
		_feed(Vector2.ZERO, noise)
		t += DT
