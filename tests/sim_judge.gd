extends SceneTree
## 驗證高度判定：在球下落到指定高度比例時給一個向上脈衝，看判定結果。
## 用法：godot --headless --path . -s tests/sim_judge.gd

var game: Node2D
var DT := 1.0 / 60.0
var _ran := false


func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _feed(up: float) -> void:
	game._on_sample(Vector3(0, 0, up), Vector3(0, 0, -9.8))
	game._process(DT)


## 等到球正在下落且高度比例 <= ratio，給 3 幀 6 m/s² 的脈衝；ratio < 0 = 落地後 grace 內揮
## 回傳這一球的判定（看 round_log 長度變化）
func _play_one(ratio: float) -> String:
	var swung := false
	var n0: int = game.round_log.size()
	var frames := 0
	while game.round_log.size() == n0 and game.state != "dead" and frames < 400:
		frames += 1
		var falling: bool = game.state == "air" and game.v_up < 0.0
		var h_ratio: float = game.ball_h / game._apex_h
		if not swung and ratio >= 0.0 and falling and h_ratio <= ratio:
			swung = true
			for i in 3:
				_feed(6.0)
			continue
		if not swung and ratio < 0.0 and game.state == "settle":
			swung = true
			for i in 3:
				_feed(6.0)
			continue
		_feed(0.0)
	if game.round_log.size() > n0:
		return game.round_log[-1]["grade"]
	return "timeout"


## 等到環離球 <= gap px 時揮擊
func _play_one_gap(gap: float) -> String:
	var swung := false
	var n0: int = game.round_log.size()
	var frames := 0
	while game.round_log.size() == n0 and game.state != "dead" and frames < 400:
		frames += 1
		var falling: bool = game.state == "air" and game._now() >= game._t_apex
		if not swung and gap >= 0.0 and falling and game._ring_gap_at(game._now()) <= gap:
			swung = true
			for i in 3:
				_feed(6.0)
			continue
		if not swung and gap < 0.0 and game.state == "settle":
			swung = true
			for i in 3:
				_feed(6.0)
			continue
		_feed(0.0)
	if game.round_log.size() > n0:
		return game.round_log[-1]["grade"]
	return "timeout"


func _run() -> void:
	print("門檻(gap px): perfect<=%.0f  good<=%.0f  bad<=%.0f" % [game.judge_perfect_gap, game.judge_good_gap, game.judge_bad_gap])
	for gap in [600.0, 480.0, 400.0, 300.0, 200.0, 120.0, 60.0, -1.0]:
		game.start_game("endless")
		var g := _play_one_gap(gap)
		var label := "落地後寬限內" if gap < 0.0 else "gap %.0f px" % gap
		print("  %-14s → %-8s (gap 實際 %.0f)" % [label, g, game.last_gap])
	## 早揮之後再揮：應以最後一次為準
	game.start_game("endless")
	var n0: int = game.round_log.size()
	var phase := 0
	var frames := 0
	while game.round_log.size() == n0 and frames < 400:
		frames += 1
		var falling: bool = game.state == "air" and game.v_up < 0.0
		var hr: float = game.ball_h / game._apex_h
		if phase == 0 and falling and game._ring_gap_at(game._now()) <= 550.0:
			phase = 1
			for i in 3: _feed(6.0)
			continue
		if phase == 1 and falling and game._ring_gap_at(game._now()) <= 60.0:
			phase = 2
			for i in 3: _feed(6.0)
			continue
		_feed(0.0)
	print("  早揮(gap550)再揮(gap60) → %s   (應為 perfect, gap %.0f)" % [game.round_log[-1]["grade"], game.last_gap])
	quit()
