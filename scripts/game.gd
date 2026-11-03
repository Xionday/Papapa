extends Node2D
## 核心玩法。
## 螢幕就是球拍面（俯視）。球在拍面上方彈跳，影子畫在拍面上。
## 所有「往上」「水平」都相對重力向量計算，不寫死感測器正負號。
##
## 判定：球「出現」(下落到 show_height 以下) 到「落地 + grace」之間，
## 向上加速度最大的那一刻就是你的揮擊時刻；和落地時刻的差距決定 PERFECT / GOOD / BAD。
## 這段期間沒有任何一筆超過 hit_threshold → MISS，當 BAD 算。BAD 連兩次 → 球停住、回合結束。

signal judged(grade: String, dt: float, streak: int, score: int)
signal stopped(streak: int, score: int)
signal pushed(step: Vector2)

## ---- 可調參數（HUD 的滑桿會改這些）----
@export var hit_threshold: float = 1.25     ## m/s²，向上加速度要超過這個才算有揮
@export var grace_after: float = 0.08       ## s，落地後再等多久才結算（讓晚一點揮也算得到）
@export var perfect_dt: float = 0.05        ## s，|揮擊 − 落地| 在這之內 = PERFECT
@export var good_dt: float = 0.12           ## s，在這之內 = GOOD；再外面 = BAD
## 手機位移（衝量版）：水平加速度積分成速度、再強力阻尼，位移 = 速度 × px_per_m
@export var move_enabled: bool = true
@export var move_deadzone: float = 0.6      ## m/s²，低於這個的水平加速度視為噪音
@export var move_damping: float = 5.0       ## 1/s，速度衰減；越大「推一下」越短促
@export var px_per_m: float = 1500.0        ## 手機移 10 cm ≈ 畫面移 150 px
@export var center_strength: float = 0.8    ## 每次拍起，球在飛行中回到螢幕中心的比例（0 = 不回中）
@export var edge_margin: float = 40.0       ## px，球離螢幕邊緣最少保留
@export var good_launch: float = 0.9        ## GOOD 的起跳速度倍率
@export var bad_launch: float = 0.6         ## BAD / MISS 的起跳速度倍率
@export var max_bad: int = 2                ## 連續幾次 BAD，球就停住
@export var full_launch: float = 5.9        ## m/s，PERFECT 的起跳速度（約 1.2 秒滯空）
@export var lateral_gain: float = 150.0     ## px/s per m/s² 的傾斜
@export var show_height: float = 0.6        ## m，球低於這個高度才看得到
@export var gravity_m: float = 9.8

const SCORE := {"perfect": 3, "good": 2, "bad": 1, "miss": 0}

## ---- 狀態 ----
var ball_pos: Vector2 = Vector2.ZERO        ## 世界座標，px
var ball_h: float = 0.0                     ## m
var v_up: float = 0.0                       ## m/s
var v_lat: Vector2 = Vector2.ZERO           ## px/s
var last_launch: float = 0.0
var paddle_pos: Vector2 = Vector2.ZERO      ## 球拍（螢幕中心）在世界裡的位置
var phone_vel: Vector2 = Vector2.ZERO       ## 估計的手機水平速度 m/s（螢幕座標）
var streak: int = 0
var score: int = 0
var best_streak: int = 0
var best_score: int = 0
var bad_count: int = 0                      ## 連續 BAD/MISS 次數，PERFECT/GOOD 歸零
var ball_stopped: bool = false
var state: String = "serve"                 ## air | settle | dead
var _dead_timer: float = 0.0
var _settle_timer: float = 0.0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE

## 時機
var _t_visible: float = -1.0                ## 球這次下落「出現」的時刻；-1 = 還沒出現
var _t_land: float = 0.0                    ## 這次落地時刻
var _t_apex: float = 0.0                    ## 這次彈起的理論最高點時刻（收縮環從這裡開始）
var _t_land_pred: float = 0.0               ## 理論落地時刻
var _ash: Array = []                        ## PERFECT 的灰燼粒子 {p, v, life, r}
var _ring_gold: float = 0.0                 ## PERFECT 後環變金色的殘留時間
var _ring_gold_pos: Vector2 = Vector2.ZERO
var last_grade: String = ""
var last_dt: float = 0.0
var last_peak: float = 0.0

## 感測器
var up_dir: Vector3 = Vector3(0, 0, 1)
var up_accel: float = 0.0
var horiz_accel: Vector2 = Vector2.ZERO
var tilt: Vector2 = Vector2.ZERO
var tilt_zero: Vector2 = Vector2.ZERO        ## 校正：把目前握持角度當成水平
var _up_hist: Array[Vector2] = []           ## (time, up_accel)，保留最近 1 秒
const HIST_KEEP := 1.0

@onready var _sensor: Node = $SensorBridge


func _ready() -> void:
	_sensor.sample.connect(_on_sample)
	_serve()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_sample(linear: Vector3, gravity: Vector3) -> void:
	if gravity.length() < 1.0:
		return
	up_dir = -gravity.normalized()
	up_accel = linear.dot(up_dir)
	var h3: Vector3 = linear - up_dir * up_accel
	## 裝置座標：x 向右、y 向上(手機頂端)、z 出螢幕。螢幕座標 y 向下，所以 y 取負。
	horiz_accel = Vector2(h3.x, -h3.y)
	## 傾斜：重力在拍面上的分量，哪邊低就往哪邊飄
	tilt = Vector2(gravity.x, -gravity.y) - tilt_zero
	var now := _now()
	_up_hist.append(Vector2(now, up_accel))
	while _up_hist.size() > 0 and now - _up_hist[0].x > HIST_KEEP:
		_up_hist.pop_front()


func calibrate_tilt() -> void:
	tilt_zero += tilt


## 在 [t0, t1] 之間找向上加速度最大的一筆，回傳 (時刻, 值)；沒有就 (−1, 0)
func _peak_between(t0: float, t1: float) -> Vector2:
	var best := Vector2(-1.0, 0.0)
	for s in _up_hist:
		if s.x >= t0 and s.x <= t1 and s.y > best.y:
			best = s
	return best


func _serve() -> void:
	state = "air"
	ball_pos = paddle_pos
	ball_h = 0.0
	last_launch = full_launch
	v_up = full_launch
	v_lat = Vector2.ZERO
	streak = 0
	score = 0
	bad_count = 0
	ball_stopped = false
	last_grade = ""
	_t_visible = -1.0
	_launch_timing()


## 起跳瞬間算出理論最高點與落地時刻（收縮環用）
func _launch_timing() -> void:
	var t_half: float = v_up / gravity_m
	_t_apex = _now() + t_half
	_t_land_pred = _now() + 2.0 * t_half


func _process(delta: float) -> void:
	_flash = max(0.0, _flash - delta * 3.0)
	_ring_gold = max(0.0, _ring_gold - delta)
	_step_move(delta)
	_step_ash(delta)

	match state:
		"air":
			_step_air(delta)
		"settle":
			_settle_timer -= delta
			if _settle_timer <= 0.0:
				_judge()
		"dead":
			_dead_timer -= delta
			if _dead_timer <= 0.0:
				_serve()
	queue_redraw()


## 手機位移：不是真的追蹤位置，是把「推一下」的衝量變成短暫的速度
func _step_move(delta: float) -> void:
	if not move_enabled:
		return
	var a := horiz_accel
	if a.length() < move_deadzone:
		a = Vector2.ZERO
	phone_vel += a * delta
	phone_vel *= exp(-move_damping * delta)
	if phone_vel.length() < 0.005:
		phone_vel = Vector2.ZERO
	var step := phone_vel * px_per_m * delta
	if step != Vector2.ZERO:
		paddle_pos += step
		pushed.emit(step)


func _step_air(delta: float) -> void:
	ball_h += v_up * delta
	v_up -= gravity_m * delta
	ball_pos += v_lat * delta
	_clamp_to_screen()

	## 下落中第一次進入可見高度 → 判定視窗開始
	if _t_visible < 0.0 and v_up < 0.0 and ball_h <= show_height:
		_t_visible = _now()

	if ball_h <= 0.0 and v_up < 0.0:
		ball_h = 0.0
		_t_land = _now()
		if _t_visible < 0.0:
			_t_visible = _t_land
		state = "settle"
		_settle_timer = grace_after


func _judge() -> void:
	var peak := _peak_between(_t_visible, _t_land + grace_after)
	last_peak = peak.y
	var grade: String
	if peak.x < 0.0 or peak.y < hit_threshold:
		grade = "miss"
		last_dt = 0.0
	else:
		last_dt = abs(peak.x - _t_land)
		if last_dt <= perfect_dt:
			grade = "perfect"
		elif last_dt <= good_dt:
			grade = "good"
		else:
			grade = "bad"
	last_grade = grade

	match grade:
		"perfect":
			bad_count = 0
			last_launch = full_launch
			_flash_color = Color(0.36, 0.79, 0.65)
			_sensor.haptic(1)
			_spawn_ash()
		"good":
			bad_count = 0
			last_launch = full_launch * good_launch
			_flash_color = Color(0.53, 0.72, 0.92)
			_sensor.haptic(1)
		_:
			bad_count += 1
			last_launch = last_launch * bad_launch
			_flash_color = Color(0.98, 0.78, 0.46)
			_sensor.haptic(2)
	_flash = 1.0

	if bad_count >= max_bad:
		state = "dead"
		_dead_timer = 1.5
		v_up = 0.0
		v_lat = Vector2.ZERO
		ball_stopped = true
		_flash_color = Color(0.89, 0.29, 0.29)
		_sensor.haptic(3)
		best_streak = max(best_streak, streak)
		best_score = max(best_score, score)
		stopped.emit(streak, score)
		return

	streak += 1
	score += SCORE[grade]
	best_streak = max(best_streak, streak)
	best_score = max(best_score, score)
	v_up = last_launch
	v_lat = tilt * lateral_gain
	## 回中：這次飛行結束時，球要回到螢幕中心 center_strength 的距離
	var flight_t: float = 2.0 * v_up / gravity_m
	v_lat += (paddle_pos - ball_pos) * center_strength / flight_t
	_t_visible = -1.0
	_launch_timing()
	state = "air"
	judged.emit(grade, last_dt, streak, score)


## PERFECT：環變金色，碎成灰燼飄散
func _spawn_ash() -> void:
	_ring_gold = 0.5
	_ring_gold_pos = ball_pos
	_ash.clear()
	var n := 36
	for i in n:
		var a: float = TAU * i / n + randf_range(-0.05, 0.05)
		var dir := Vector2(cos(a), sin(a))
		_ash.append({
			"p": ball_pos + dir * BALL_R_LAND,
			"v": dir * randf_range(40.0, 120.0) + Vector2(randf_range(-20.0, 20.0), randf_range(-90.0, -40.0)),
			"life": randf_range(0.5, 0.9),
			"max": 0.0,
			"r": randf_range(2.0, 4.5),
		})
	for d in _ash:
		d["max"] = d["life"]


func _step_ash(delta: float) -> void:
	if _ash.is_empty():
		return
	for d in _ash:
		d["life"] -= delta
		d["p"] += d["v"] * delta
		d["v"] = d["v"] * exp(-1.5 * delta) + Vector2(randf_range(-30.0, 30.0), -25.0) * delta
	_ash = _ash.filter(func(d): return d["life"] > 0.0)


## 球限制在螢幕內：撞到邊就停在邊上，橫向速度歸零
func _clamp_to_screen() -> void:
	var half := get_viewport_rect().size * 0.5 - Vector2(edge_margin, edge_margin)
	var d := ball_pos - paddle_pos
	var c := Vector2(clamp(d.x, -half.x, half.x), clamp(d.y, -half.y, half.y))
	if c.x != d.x:
		v_lat.x = 0.0
	if c.y != d.y:
		v_lat.y = 0.0
	ball_pos = paddle_pos + c


## ---- 畫面 ----
func _to_screen(world: Vector2) -> Vector2:
	return get_viewport_rect().size * 0.5 + (world - paddle_pos)


const BALL_R_LAND := 26.0
const BALL_R_HIGH := 70.0
const RING_R_MAX := 150.0


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.18, 0.18, 0.17))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(_flash_color, 0.35 * _flash))
	## 格線：讓推動時看得出世界在動
	var grid := 160.0
	var off := Vector2(fposmod(-paddle_pos.x, grid), fposmod(-paddle_pos.y, grid))
	var gc := Color(1, 1, 1, 0.06)
	var x := off.x
	while x < vp.x:
		draw_line(Vector2(x, 0), Vector2(x, vp.y), gc, 1.0)
		x += grid
	var y := off.y
	while y < vp.y:
		draw_line(Vector2(0, y), Vector2(vp.x, y), gc, 1.0)
		y += grid

	var sp := _to_screen(ball_pos)
	var max_h: float = max(0.01, (last_launch * last_launch) / (2.0 * gravity_m))
	var t: float = clamp(ball_h / max_h, 0.0, 1.0)

	## 影子：頭頂燈的模型 — 球越高影子越大越淡，落地時最小最實
	var shadow_r: float = lerp(28.0, 90.0, t)
	var shadow_a: float = lerp(0.55, 0.12, t)
	draw_circle(sp, shadow_r, Color(0, 0, 0, shadow_a))

	var visible_ball: bool = ball_h <= show_height and (state != "dead" or ball_stopped)
	var k: float = clamp(ball_h / show_height, 0.0, 1.0)
	var ball_r: float = lerp(BALL_R_LAND, BALL_R_HIGH, k)

	## 收縮環：從最高點開始、由螢幕外等速縮進來，落地瞬間剛好貼住球與影子
	var now := _now()
	if state == "air" and now >= _t_apex:
		var ring_start: float = vp.length() * 0.5 + 20.0
		var u: float = clamp((now - _t_apex) / max(0.01, _t_land_pred - _t_apex), 0.0, 1.0)
		var ring_r: float = lerp(ring_start, BALL_R_LAND, u)
		draw_arc(sp, ring_r, 0.0, TAU, 96, Color(1, 1, 1, 0.3), 3.0)
	elif state == "settle":
		draw_arc(sp, BALL_R_LAND, 0.0, TAU, 64, Color(1, 1, 1, 0.3), 3.0)

	## PERFECT 的金環殘影與灰燼
	if _ring_gold > 0.0:
		var gp := _to_screen(_ring_gold_pos)
		var f: float = _ring_gold / 0.5
		draw_arc(gp, BALL_R_LAND + (1.0 - f) * 30.0, 0.0, TAU, 64, Color(1.0, 0.84, 0.3, 0.8 * f), 3.0)
	for d in _ash:
		var f2: float = d["life"] / d["max"]
		draw_circle(_to_screen(d["p"]), d["r"] * f2, Color(1.0, 0.8, 0.3, 0.9 * f2))

	## 球：只有低於 show_height 才看得到，越高(越靠近眼睛)越大
	if visible_ball:
		draw_circle(sp, ball_r, Color(0.94, 0.6, 0.48))
		draw_circle(sp + Vector2(-ball_r * 0.3, -ball_r * 0.3), ball_r * 0.25, Color(1, 1, 1, 0.5))
