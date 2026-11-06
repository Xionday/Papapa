extends Node2D
## 核心玩法。
## 螢幕就是球拍面（俯視）。球在拍面上方彈跳，影子畫在拍面上。
## 所有「往上」「水平」都相對重力向量計算，不寫死感測器正負號。
##
## 判定：球「出現」(下落到 show_height 以下) 到「落地 + grace」之間，
## 向上加速度最大的那一刻就是你的揮擊時刻；和落地時刻的差距決定 PERFECT / GOOD / BAD。
## 這段期間沒有任何一筆超過 hit_threshold → MISS，當 BAD 算。BAD 連兩次 → 球停住、回合結束。

signal judged(grade: String, dt: float, streak: int, score: int)
signal stopped(streak: int, score: int, stats: Dictionary)
signal zone_changed(index: int)
signal pushed(step: Vector2)

## ---- 可調參數（HUD 的滑桿會改這些）----
@export var hit_threshold: float = 1.25     ## m/s²，向上加速度要超過這個才算有揮
## 高度判定：揮擊那一刻球離地高度 / 這次最高點 的比例
@export var judge_miss_above: float = 0.5   ## 高於這個 → 太早(當 miss，之後再揮以最後一次為準)
@export var judge_bad_above: float = 0.22   ## 高於這個 → bad
@export var judge_good_above: float = 0.08  ## 高於這個 → good；更低(含落地後寬限) → perfect
@export var timing_bias: float = -0.05      ## (舊的時間判定用，保留給 dev 面板參考)       ## s，perfect 的中心點相對落地的偏移（負 = 允許提早揮）
@export var grace_after: float = 0.08       ## s，落地後再等多久才結算（讓晚一點揮也算得到）
@export var perfect_dt: float = 0.05        ## s，|揮擊 − 落地| 在這之內 = PERFECT
@export var good_dt: float = 0.12           ## s，在這之內 = GOOD；再外面 = BAD
## 手機位移（衝量版）：水平加速度積分成速度、再強力阻尼，位移 = 速度 × px_per_m
@export var move_enabled: bool = false     ## 手機位移暫時關閉，先測傾斜彈跳
@export var move_deadzone: float = 0.7      ## m/s²，低於這個的水平加速度視為手持雜訊（靜止時不起步）
@export var move_damping: float = 0.0       ## 1/s，速度衰減（0 = 純積分，靠 ZUPT 歸零）
@export var move_lowpass: float = 0.05      ## s，加速度低通時間常數
@export var move_zupt: float = 0.15         ## s，連續安靜這麼久就把速度歸零（zero-velocity update）
@export var px_per_m: float = 10300.0       ## 由 screen_width_cm 算出：要讓球釘在世界，1 cm 的位移必須等於螢幕上 1 cm 的像素
@export var screen_width_cm: float = 7.0    ## 螢幕實體寬度（iPhone 約 6.5–7.2），start_game 時用它算 px_per_m
@export var center_strength: float = 0.0    ## 每次拍起，球在飛行中回到螢幕中心的比例（0 = 不回中）
@export var edge_margin: float = 40.0       ## px，球離螢幕邊緣最少保留（endless 模式）
@export var wall_bounce: float = 0.6        ## 撞牆回彈係數：0 = 停住，1 = 全反彈
## 拍面顏色：red | black | alternate（每次撞牆換面，模擬正反拍）
@export var rubber_mode: String = "red"
const RUBBER_RED := Color(0.91, 0.42, 0.40)
const RUBBER_BLACK := Color(0.16, 0.16, 0.17)
var rubber_is_red: bool = true
## 球色：yellow | white
@export var ball_color_mode: String = "yellow"
const BALL_YELLOW := Color(1.0, 0.87, 0.2)
const BALL_WHITE := Color(0.98, 0.98, 0.95)
var _flip_timer: float = -1.0
var counter_visible: bool = false
## 待機球：首頁與結算頁上隨傾斜滾動的裝飾球（螢幕座標）
var idle_pos: Vector2 = Vector2.ZERO
var idle_vel: Vector2 = Vector2.ZERO
var idle_active: bool = false
@export var idle_gain: float = 900.0        ## px/s² per m/s² 的傾斜
@export var idle_friction: float = 1.2      ## 1/s               ## alternate 模式：拍到球後 0.5s 換面
var _rubber_blend: float = 1.0              ## 0 = 黑，1 = 紅，換面時漸變
@export var clamp_in_zone_mode: bool = false ## 光圈模式不鎖邊界：球釘在世界裡，鏡頭怎麼移都不會被推著走
@export var good_launch: float = 0.9        ## GOOD 的起跳速度倍率
@export var bad_launch: float = 0.6         ## BAD / MISS 的起跳速度倍率
@export var max_bad: int = 2                ## 連續幾次 BAD，球就停住
@export var full_launch: float = 5.9        ## m/s，PERFECT 的起跳速度（約 1.2 秒滯空）
@export var lateral_gain: float = 150.0     ## px/s per m/s² 的傾斜
@export var show_height: float = 0.6        ## m，球低於這個高度才看得到
@export var gravity_m: float = 9.8

## ---- 光圈模式 ----
@export var zone_mode: bool = true
## 依連擊數分階段；每階段：連擊門檻、每幾次彈跳換位置、半徑 px、出現距離最小/最大 px
const ZONE_STAGES := [
	[0, 2, 180.0, 150.0, 300.0],
	[10, 2, 140.0, 200.0, 400.0],
	[20, 1, 140.0, 200.0, 400.0],
	[30, 1, 110.0, 250.0, 500.0],
	[50, 1, 80.0, 300.0, 600.0],
]
## 光圈模式的物理：彈得更高（有時間瞄）、傾斜飄得更少（不會一下跑太遠）
@export var zone_launch: float = 7.2        ## m/s，滯空約 1.5 秒（endless 是 5.9 ≈ 1.2 秒）
@export var zone_lateral_gain: float = 0.0  ## 暫時關閉傾斜飄移，單獨測位移（endless 是 150）
@export var endless_launch: float = 5.9
@export var endless_lateral_gain: float = 150.0
@export var zone_scale: float = 1.0         ## 全部半徑的倍率（tune 用）
@export var zone_dist_scale: float = 1.0    ## 全部距離的倍率（tune 用）

const SCORE := {"perfect": 3, "good": 2, "bad": 1, "miss": 0}

## ---- 狀態 ----
var ball_pos: Vector2 = Vector2.ZERO        ## 世界座標，px
var ball_h: float = 0.0                     ## m
var v_up: float = 0.0                       ## m/s
var v_lat: Vector2 = Vector2.ZERO           ## px/s
var last_launch: float = 0.0
var paddle_pos: Vector2 = Vector2.ZERO      ## 球拍（螢幕中心）在世界裡的位置
var phone_vel: Vector2 = Vector2.ZERO       ## 估計的手機水平速度 m/s（螢幕座標）
var _accel_lp: Vector2 = Vector2.ZERO       ## 低通後的水平加速度
var _accel_buf: Array[Vector2] = []         ## 最近 0.2 秒被死區忽略的加速度（起步時補積分）
var _quiet_t: float = 0.0                   ## 連續安靜時間
var last_move_px: float = 0.0               ## 最近一次連續移動走了幾 px（HUD 用）
var _move_acc: float = 0.0
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
var zone_pos: Vector2 = Vector2.ZERO        ## 光圈「螢幕」座標：釘在畫面上、跟著鏡頭走
var zone_r: float = 180.0
var zone_left: int = 2                      ## 還有幾次彈跳會換位置
var zone_index: int = 0
var _zone_old_pos: Vector2 = Vector2.ZERO
var _zone_old_r: float = 0.0
var _zone_fade: float = 0.0                 ## 舊圈淡出剩餘時間
var _zone_grow: float = 0.0                 ## 新圈放大剩餘時間
var _zone_hit_flash: float = 0.0
var _wall_lights: Array = []                ## {side, at, t}  沿邊緣擴散的光
const WALL_LIGHT_T := 0.7                   ## 光跑完的時間
const WALL_LIGHT_SPEED := 2600.0            ## px/s，光沿邊緣跑的速度
const WALL_LIGHT_COL := Color(1.0, 0.92, 0.7)
var fell_outside: bool = false              ## 這局是因為落在圈外結束
var _ring_gold: float = 0.0                 ## PERFECT 後金環剩餘時間
var _ring_gold_total: float = 0.5           ## 金環總時長 = 這次彈起到最高點的時間
var _ring_gold_pos: Vector2 = Vector2.ZERO
var last_grade: String = ""
var last_dt: float = 0.0
var last_peak: float = 0.0
var last_h_ratio: float = -1.0              ## 最後一次揮擊時球高度/最高點（dev 用）
var round_log: Array = []                   ## 這局每一次判定 {grade, dt, peak}

## 感測器
var up_dir: Vector3 = Vector3(0, 0, 1)
var up_accel: float = 0.0
var horiz_accel: Vector2 = Vector2.ZERO
var tilt: Vector2 = Vector2.ZERO
var tilt_zero: Vector2 = Vector2.ZERO        ## 校正：把目前握持角度當成水平
var _up_hist: Array[Vector2] = []           ## (time, up_accel)，保留最近 1 秒
var _h_hist: Array[Vector2] = []            ## (time, ball_h)，每幀記，保留最近 1 秒
var _apex_h: float = 1.0                    ## 這次彈跳的理論最高點(m)
const HIST_KEEP := 1.0

@onready var _sensor: Node = $SensorBridge
@onready var _sfx: Node = $Sfx
var _apex_ticked: bool = false


func _ready() -> void:
	_sensor.sample.connect(_on_sample)
	if OS.has_feature("web"):
		var cb := JavaScriptBridge.create_callback(_js_debug)
		JavaScriptBridge.get_interface("window").papapaDebug = cb
		_js_cb_keep = cb
	state = "menu"
	score = 0
	streak = 0
	ball_pos = paddle_pos
	ball_h = 0.0
	last_launch = full_launch


## 從選單開始：mode = "endless" | "zone"
func start_game(mode: String) -> void:
	zone_mode = (mode == "zone")
	px_per_m = get_viewport_rect().size.x / (screen_width_cm / 100.0)
	rubber_is_red = rubber_mode != "black"
	_rubber_blend = 1.0 if rubber_is_red else 0.0
	if zone_mode:
		full_launch = zone_launch
		lateral_gain = zone_lateral_gain
	else:
		full_launch = endless_launch
		lateral_gain = endless_lateral_gain
	paddle_pos = Vector2.ZERO
	phone_vel = Vector2.ZERO
	_serve()


func to_menu() -> void:
	state = "menu"
	ball_stopped = false
	_ash.clear()
	_ring_gold = 0.0


var _game_time: float = 0.0                 ## 遊戲內時鐘（每幀累加 delta），不用壁鐘：暫停與模擬都正確


func _now() -> float:
	return _game_time


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


## 某個時刻球的高度（從歷史內插）
func _height_at(t: float) -> float:
	if _h_hist.is_empty():
		return 0.0
	if t <= _h_hist[0].x:
		return _h_hist[0].y
	for i in range(1, _h_hist.size()):
		if _h_hist[i].x >= t:
			var a := _h_hist[i - 1]
			var b := _h_hist[i]
			var u: float = (t - a.x) / max(b.x - a.x, 0.0001)
			return lerp(a.y, b.y, u)
	return 0.0


## 在 [t0, t1] 之間，找「最後一次」向上加速度超過門檻的揮擊；回傳該次的峰值 (時刻, 值)；沒有 → (−1, 0)
func _last_swing_between(t0: float, t1: float, threshold: float) -> Vector2:
	var best := Vector2(-1.0, 0.0)
	var in_swing := false
	for sm in _up_hist:
		if sm.x < t0 or sm.x > t1:
			continue
		if sm.y >= threshold:
			if not in_swing:
				in_swing = true
				best = sm
			elif sm.y > best.y:
				best = sm
		else:
			in_swing = false
	return best


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
	round_log = []
	fell_outside = false
	_t_visible = -1.0
	_apex_ticked = false
	_launch_timing()
	_zone_reset()


func play_again() -> void:
	if state == "dead":
		_serve()


## 這局的統計，給結算畫面
func round_stats() -> Dictionary:
	var counts := {"perfect": 0, "good": 0, "bad": 0, "miss": 0}
	var dts: Array[float] = []
	var peaks: Array[float] = []
	for e in round_log:
		counts[e["grade"]] += 1
		if e["grade"] != "miss":
			dts.append(e["dt"])
		if e["peak"] > 0.0:
			peaks.append(e["peak"])
	dts.sort()
	var st := {"counts": counts, "hits": dts.size(), "dt_avg": 0.0, "dt_med": 0.0, "dt_min": 0.0, "dt_max": 0.0, "peak_avg": 0.0}
	if dts.size() > 0:
		var sum := 0.0
		for d in dts:
			sum += d
		st["dt_avg"] = sum / dts.size()
		st["dt_med"] = dts[dts.size() / 2]
		st["dt_min"] = dts[0]
		st["dt_max"] = dts[dts.size() - 1]
	if peaks.size() > 0:
		var ps := 0.0
		for pk in peaks:
			ps += pk
		st["peak_avg"] = ps / peaks.size()
	return st


## ---- 光圈 ----
func _zone_stage() -> Array:
	var st: Array = ZONE_STAGES[0]
	for row in ZONE_STAGES:
		if streak >= row[0]:
			st = row
	return st


func _zone_reset() -> void:
	## 第一個圈放在拍面中心，讓開局不用追
	var st := _zone_stage()
	zone_index = 0
	zone_pos = get_viewport_rect().size * 0.5
	zone_r = st[2] * zone_scale
	zone_left = st[1]
	_zone_fade = 0.0
	_zone_grow = 0.25
	_zone_hit_flash = 0.0


func _zone_relocate() -> void:
	var st := _zone_stage()
	_zone_old_pos = zone_pos
	_zone_old_r = zone_r
	_zone_fade = 0.3
	_zone_grow = 0.3
	zone_r = st[2] * zone_scale
	## 新位置：螢幕上的隨機點，離球目前的螢幕位置 dist_min~dist_max，且整個圈要在畫面內
	var vp := get_viewport_rect().size
	var lo := Vector2(zone_r + 24.0, zone_r + 140.0)
	var hi := Vector2(vp.x - zone_r - 24.0, vp.y - zone_r - 150.0)
	var from := _to_screen(ball_pos)
	var best := zone_pos
	var best_err := INF
	for i in 24:
		var dist: float = randf_range(st[3], st[4]) * zone_dist_scale
		var ang: float = randf_range(0.0, TAU)
		var cand := from + Vector2(cos(ang), sin(ang)) * dist
		var cl := Vector2(clamp(cand.x, lo.x, hi.x), clamp(cand.y, lo.y, hi.y))
		var err: float = cand.distance_to(cl) + (100.0 if cl.distance_to(from) < st[3] * 0.6 else 0.0)
		if err < best_err:
			best_err = err
			best = cl
	zone_pos = best
	zone_left = st[1]
	zone_index += 1
	_sfx.play("zone")
	zone_changed.emit(zone_index)


func _in_zone() -> bool:
	return _to_screen(ball_pos).distance_to(zone_pos) <= zone_r


## 起跳瞬間算出理論最高點與落地時刻（收縮環用）
func _launch_timing() -> void:
	_apex_h = max(0.01, (v_up * v_up) / (2.0 * gravity_m))
	var t_half: float = v_up / gravity_m
	_t_apex = _now() + t_half
	_t_land_pred = _now() + 2.0 * t_half


func _process(delta: float) -> void:
	_game_time += delta
	_flash = max(0.0, _flash - delta * 3.0)
	_ring_gold = max(0.0, _ring_gold - delta)
	_zone_fade = max(0.0, _zone_fade - delta)
	_zone_grow = max(0.0, _zone_grow - delta)
	_zone_hit_flash = max(0.0, _zone_hit_flash - delta)
	for w in _wall_lights:
		w["t"] += delta
	_wall_lights = _wall_lights.filter(func(w): return w["t"] < WALL_LIGHT_T)
	if _flip_timer >= 0.0:
		_flip_timer -= delta
		if _flip_timer < 0.0:
			rubber_is_red = not rubber_is_red
	var target_blend: float = 1.0 if rubber_is_red else 0.0
	_rubber_blend += (target_blend - _rubber_blend) * (1.0 - exp(-10.0 * delta))
	_step_move(delta)
	_step_ash(delta)

	_step_idle(delta)
	match state:
		"air":
			if not debug_freeze:
				_step_air(delta)
		"settle":
			_settle_timer -= delta
			if _settle_timer <= 0.0:
				_judge()
		"dead", "menu":
			pass  ## 等 HUD 的按鈕
	queue_redraw()


## 待機球：首頁/結算頁上，傾斜就滾，撞邊反彈
func _step_idle(delta: float) -> void:
	var want: bool = state == "menu" or state == "dead"
	if want and not idle_active:
		idle_active = true
		idle_pos = get_viewport_rect().size * 0.5 + Vector2(0, 120)
		idle_vel = Vector2.ZERO
	idle_active = want
	if not idle_active:
		return
	var vp := get_viewport_rect().size
	idle_vel += tilt * idle_gain * delta
	idle_vel *= exp(-idle_friction * delta)
	idle_pos += idle_vel * delta
	var r := BALL_R_LAND
	if idle_pos.x < r:
		idle_pos.x = r
		idle_vel.x = -idle_vel.x * 0.6
	elif idle_pos.x > vp.x - r:
		idle_pos.x = vp.x - r
		idle_vel.x = -idle_vel.x * 0.6
	if idle_pos.y < r:
		idle_pos.y = r
		idle_vel.y = -idle_vel.y * 0.6
	elif idle_pos.y > vp.y - r:
		idle_pos.y = vp.y - r
		idle_vel.y = -idle_vel.y * 0.6


## 手機位移（衝量版 + 低通 + 遲滯 + ZUPT）
## 不是真的追蹤位置：加速度積分成速度，靠「安靜一段時間就把速度歸零」避免飄移。
## 一旦動起來，低於死區的加速度照樣積分，所以平穩的移動也會完整反映；
## 代價是超過 1 秒的極慢移動（峰值加速度 < 死區）不會起步。
func _step_move(delta: float) -> void:
	if not move_enabled:
		return
	_accel_lp += (horiz_accel - _accel_lp) * (1.0 - exp(-delta / max(0.001, move_lowpass)))
	var a := _accel_lp
	var moving := phone_vel != Vector2.ZERO
	if a.length() < move_deadzone:
		_quiet_t += delta
		if not moving:
			## 靜止中：不積分，但記下來，等真的動起來時補回去
			_accel_buf.append(a * delta)
			if _accel_buf.size() > 12:   ## 約 0.2 秒
				_accel_buf.pop_front()
			a = Vector2.ZERO
	else:
		_quiet_t = 0.0
		if not moving:
			## 起步：把剛才被死區吃掉的那段一次補進速度
			for d in _accel_buf:
				phone_vel += d
			_accel_buf.clear()
	phone_vel += a * delta
	if move_damping > 0.0:
		phone_vel *= exp(-move_damping * delta)
	if _quiet_t > move_zupt:
		phone_vel = Vector2.ZERO
		if _move_acc > 0.0:
			last_move_px = _move_acc
			_move_acc = 0.0
	var step := phone_vel * px_per_m * delta
	if step != Vector2.ZERO:
		paddle_pos += step
		_move_acc += step.length()
		pushed.emit(step)


func _step_air(delta: float) -> void:
	var now_h := _now()
	_h_hist.append(Vector2(now_h, ball_h))
	while _h_hist.size() > 0 and now_h - _h_hist[0].x > HIST_KEEP:
		_h_hist.pop_front()
	ball_h += v_up * delta
	v_up -= gravity_m * delta
	ball_pos += v_lat * delta
	_clamp_to_screen()

	## 最高點：收縮環出現的那一刻給一個 tick（用身體數拍子）
	if not _apex_ticked and _now() >= _t_apex:
		_apex_ticked = true
		_sfx.play("tick")

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
	## 光圈模式：沒落在圈內就直接結束
	if zone_mode and not _in_zone():
		fell_outside = true
		last_grade = "outside"
		round_log.append({"grade": "miss", "dt": 0.0, "peak": 0.0})
		_end_round(Color(0.89, 0.29, 0.29))
		return

	## 判定視窗：從最高點到落地 + 寬限；取「最後一次」揮擊
	var peak := _last_swing_between(_t_apex, _t_land + grace_after, hit_threshold)
	last_peak = peak.y
	var grade: String
	last_h_ratio = -1.0
	if peak.x < 0.0:
		grade = "miss"
		last_dt = 0.0
	else:
		last_dt = peak.x - _t_land
		## 落地後(寬限內)揮 → 高度視為 0
		var h: float = 0.0 if peak.x >= _t_land else _height_at(peak.x)
		last_h_ratio = h / _apex_h
		if last_h_ratio > judge_miss_above:
			grade = "miss"
		elif last_h_ratio > judge_bad_above:
			grade = "bad"
		elif last_h_ratio > judge_good_above:
			grade = "good"
		else:
			grade = "perfect"
	last_grade = grade
	round_log.append({"grade": grade, "dt": last_dt, "peak": last_peak, "h": last_h_ratio})

	match grade:
		"perfect":
			bad_count = 0
			last_launch = full_launch
			_flash_color = Color(0.36, 0.79, 0.65)
			_sensor.haptic(1)
			_sfx.play("perfect")
			_spawn_ash()
		"good":
			bad_count = 0
			last_launch = full_launch * good_launch
			_flash_color = Color(0.53, 0.72, 0.92)
			_sensor.haptic(1)
			_sfx.play("good")
		_:
			bad_count += 1
			last_launch = last_launch * bad_launch
			_flash_color = Color(0.98, 0.78, 0.46)
			_sensor.haptic(2)
			_sfx.play("miss" if grade == "miss" else "bad")
	_flash = 1.0

	if bad_count >= max_bad:
		_end_round(Color(0.89, 0.29, 0.29))
		return

	if rubber_mode == "alternate":
		_flip_timer = 0.5
	if zone_mode:
		_zone_hit_flash = 0.3
		zone_left -= 1
		if zone_left <= 0:
			_zone_relocate()

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
	_apex_ticked = false
	_launch_timing()
	state = "air"
	judged.emit(grade, last_dt, streak, score)


func _end_round(col: Color) -> void:
	state = "dead"
	v_up = 0.0
	v_lat = Vector2.ZERO
	ball_stopped = true
	_flash = 1.0
	_flash_color = col
	_sensor.haptic(3)
	_sfx.play("stop")
	best_streak = max(best_streak, streak)
	best_score = max(best_score, score)
	stopped.emit(streak, score, round_stats())


## PERFECT：環變金色，碎成灰燼飄散
func _spawn_ash() -> void:
	## 金環與灰燼用螢幕座標，固定在畫面上，不跟著手機位移
	## 金環時長 = 到最高點的時間，半徑跟著影子一起放大
	_ring_gold_total = max(0.2, last_launch / gravity_m)
	_ring_gold = _ring_gold_total
	_ring_gold_pos = _to_screen(ball_pos)
	_ash.clear()
	var n := 36
	for i in n:
		var a: float = TAU * i / n + randf_range(-0.05, 0.05)
		var dir := Vector2(cos(a), sin(a))
		_ash.append({
			"p": _ring_gold_pos + dir * BALL_R_LAND,
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
	if zone_mode and not clamp_in_zone_mode:
		return
	var half := get_viewport_rect().size * 0.5 - Vector2(edge_margin, edge_margin)
	var d := ball_pos - paddle_pos
	var c := Vector2(clamp(d.x, -half.x, half.x), clamp(d.y, -half.y, half.y))
	var hit_wall := false
	if c.x != d.x:
		v_lat.x = -v_lat.x * wall_bounce
		hit_wall = true
	if c.y != d.y:
		v_lat.y = -v_lat.y * wall_bounce
		hit_wall = true
	ball_pos = paddle_pos + c
	if hit_wall and v_lat.length() > 20.0:
		var spn := _to_screen(ball_pos)
		## 撞點投影到螢幕外框（邊界矩形）上，記成「沿周長的距離」
		_wall_lights.append({"s": _perimeter_pos(spn, get_viewport_rect().size), "t": 0.0})
		_sfx.play("wall")


## ---- 畫面 ----
func _to_screen(world: Vector2) -> Vector2:
	return get_viewport_rect().size * 0.5 + (world - paddle_pos)


const BALL_R_LAND := 46.0
const BALL_R_HIGH := 120.0
const RING_R_MAX := 150.0


func _draw() -> void:
	var vp := get_viewport_rect().size
	var bg := RUBBER_BLACK.lerp(RUBBER_RED, _rubber_blend)
	draw_rect(Rect2(Vector2.ZERO, vp), bg)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(_flash_color, 0.35 * _flash))
	if state == "menu":
		_draw_idle_ball()
		return
	## 格線：讓推動時看得出世界在動（位移關閉時不畫）
	var grid := 160.0
	if not move_enabled:
		grid = 0.0
	var off := Vector2(fposmod(-paddle_pos.x, grid), fposmod(-paddle_pos.y, grid)) if grid > 0.0 else Vector2.ZERO
	var gc := Color(1, 1, 1, 0.06)
	if grid > 0.0:
		var x := off.x
		while x < vp.x:
			draw_line(Vector2(x, 0), Vector2(x, vp.y), gc, 1.0)
			x += grid
		var y := off.y
		while y < vp.y:
			draw_line(Vector2(0, y), Vector2(vp.x, y), gc, 1.0)
			y += grid
	## 撞牆的光：從撞到的點沿邊緣往兩側跑、漸暗
	for w in _wall_lights:
		_draw_wall_light(vp, w)
	if zone_mode:
		_draw_zone(vp)

	## 置中計數：畫在球和影子之下、半透明
	if counter_visible:
		var font := ThemeDB.fallback_font
		var c := vp * 0.5
		var txt := "%d" % streak
		var fs := 260
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.45))
		var bt := "BEST %d" % best_streak
		var bw: float = font.get_string_size(bt, HORIZONTAL_ALIGNMENT_CENTER, -1, 30).x
		draw_string(font, Vector2(c.x - bw * 0.5, c.y + fs * 0.35 + 70.0), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.35))

	var sp := _to_screen(ball_pos)
	var max_h: float = max(0.01, (last_launch * last_launch) / (2.0 * gravity_m))
	var t: float = clamp(ball_h / max_h, 0.0, 1.0)

	## 影子：頭頂燈的模型 — 球越高影子越大越淡，落地時最小最實
	var shadow_r: float = lerp(28.0, 90.0, t)
	var shadow_a: float = lerp(0.55, 0.12, t)
	if state != "dead":
		draw_circle(sp, shadow_r, Color(0, 0, 0, shadow_a))

	var visible_ball: bool = ball_h <= show_height and state != "dead"
	var k: float = clamp(ball_h / show_height, 0.0, 1.0)
	var ball_r: float = lerp(BALL_R_LAND, BALL_R_HIGH, k)

	## 收縮環：從最高點開始、由螢幕外等速縮進來，落地瞬間剛好貼住球與影子
	var now := _now()
	if state == "air" and now >= _t_apex:
		var ring_start: float = vp.length() * 0.5 + 20.0
		var u: float = clamp((now - _t_apex) / max(0.01, _t_land_pred - _t_apex), 0.0, 1.0)
		var ring_r: float = lerp(ring_start, BALL_R_LAND, u)
		_draw_ring(sp, ring_r, Color(1, 1, 1, 0.85), u)
	elif state == "settle":
		_draw_ring(sp, BALL_R_LAND, Color(1, 1, 1, 0.85), 1.0)

	## PERFECT 的金環殘影與灰燼
	if _ring_gold > 0.0:
		var gp := _ring_gold_pos
		var f: float = _ring_gold / _ring_gold_total
		## 半徑 = 此刻影子的半徑（球越高影子越大），位置固定在畫面上
		draw_arc(gp, shadow_r, 0.0, TAU, 64, Color(0, 0, 0, 0.35 * f), 10.0)
		draw_arc(gp, shadow_r, 0.0, TAU, 64, Color(1.0, 0.84, 0.3, 0.95 * f), 4.0)
		draw_arc(gp, shadow_r, 0.0, TAU, 64, Color(1.0, 0.97, 0.8, 0.9 * f), 1.5)
	for d in _ash:
		var f2: float = d["life"] / d["max"]
		draw_circle(d["p"], d["r"] * f2, Color(1.0, 0.8, 0.3, 0.9 * f2))

	## 球的落點在畫面外：邊緣箭頭指向它
	if sp.x < 0.0 or sp.x > vp.x or sp.y < 0.0 or sp.y > vp.y:
		_draw_edge_arrow(vp, sp, _ball_col())

	## 球：只有低於 show_height 才看得到，越高(越靠近眼睛)越大
	if visible_ball:
		var bc := _ball_col()
		draw_circle(sp + Vector2(0, ball_r * 0.08), ball_r, bc.darkened(0.25))
		draw_circle(sp, ball_r * 0.96, bc)
		draw_circle(sp + Vector2(-ball_r * 0.3, -ball_r * 0.32), ball_r * 0.28, Color(1, 1, 1, 0.55))
	if state == "dead":
		_draw_idle_ball()


func _draw_idle_ball() -> void:
	if not idle_active:
		return
	var r := BALL_R_LAND
	var bc := _ball_col()
	draw_circle(idle_pos + Vector2(6, 10), r * 1.05, Color(0, 0, 0, 0.25))
	draw_circle(idle_pos + Vector2(0, r * 0.08), r, bc.darkened(0.25))
	draw_circle(idle_pos, r * 0.96, bc)
	draw_circle(idle_pos + Vector2(-r * 0.3, -r * 0.32), r * 0.28, Color(1, 1, 1, 0.55))


func _ball_col() -> Color:
	return BALL_WHITE if ball_color_mode == "white" else BALL_YELLOW


## ---- 光圈繪製 ----
const ZONE_COL := Color(0.55, 0.85, 1.0)


func _draw_zone(vp: Vector2) -> void:
	## 舊圈淡出（螢幕座標）
	if _zone_fade > 0.0:
		var f: float = _zone_fade / 0.3
		draw_arc(_zone_old_pos, _zone_old_r * (1.0 + (1.0 - f) * 0.3), 0.0, TAU, 64, Color(ZONE_COL, 0.4 * f), 3.0)
	## 現在的圈：剛出現時從小放大
	var zp := zone_pos
	var g: float = 1.0 - _zone_grow / 0.3
	g = 1.0 - (1.0 - g) * (1.0 - g)   ## ease-out
	var r: float = zone_r * clamp(g, 0.05, 1.0)
	var hit: float = _zone_hit_flash / 0.3
	draw_circle(zp, r, Color(ZONE_COL, 0.08 + 0.25 * hit))
	draw_arc(zp, r, 0.0, TAU, 64, Color(ZONE_COL, 0.7 + 0.3 * hit), 4.0 + 4.0 * hit)
	## 剩幾次換位置：圈下方小點
	for i in zone_left:
		draw_circle(zp + Vector2(-14.0 * (zone_left - 1) + 28.0 * i, r + 22.0), 5.0, Color(ZONE_COL, 0.9))


## 畫面邊緣的箭頭，指向畫面外的某個螢幕座標
func _draw_edge_arrow(vp: Vector2, target: Vector2, col: Color) -> void:
	var c := vp * 0.5
	var dir := (target - c).normalized()
	var margin := 36.0
	var half := c - Vector2(margin, margin)
	var tx: float = half.x / max(abs(dir.x), 0.0001)
	var ty: float = half.y / max(abs(dir.y), 0.0001)
	var ep: Vector2 = c + dir * min(tx, ty)
	var perp := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([ep + dir * 24.0, ep - dir * 10.0 + perp * 18.0, ep - dir * 10.0 - perp * 18.0])
	draw_colored_polygon(tri, col)
	draw_circle(ep - dir * 30.0, 8.0, Color(col, 0.6))


## 除錯：在指定螢幕座標製造一次撞牆光（截圖用）
var debug_freeze: bool = false
var _js_cb_keep: JavaScriptObject


## JS: window.papapaDebug(["wall", x, y]) / (["freeze", 1])
func _js_debug(args: Array) -> void:
	var a: Array = args[0] if args.size() > 0 and args[0] is Array else args
	if a.size() == 0:
		return
	match str(a[0]):
		"wall": debug_wall_hit(float(a[1]), float(a[2]))
		"freeze":
			debug_freeze = bool(int(a[1]))
			if debug_freeze:
				state = "air"
				ball_h = 0.4
				v_up = 2.0

func debug_wall_hit(x: float, y: float) -> void:
	_wall_lights.append({"s": _perimeter_pos(Vector2(x, y), get_viewport_rect().size), "t": 0.0})


## 把螢幕上一點投影到外框，回傳沿周長的距離（從左上角順時針：上、右、下、左）
func _perimeter_pos(p: Vector2, vp: Vector2) -> float:
	var dl := p.x
	var dr := vp.x - p.x
	var dt := p.y
	var db := vp.y - p.y
	var m: float = min(min(dl, dr), min(dt, db))
	if m == dt:
		return clamp(p.x, 0.0, vp.x)
	if m == dr:
		return vp.x + clamp(p.y, 0.0, vp.y)
	if m == db:
		return vp.x + vp.y + (vp.x - clamp(p.x, 0.0, vp.x))
	return 2.0 * vp.x + vp.y + (vp.y - clamp(p.y, 0.0, vp.y))


## 周長距離 → 螢幕座標（在外框上，往內縮 inset 讓光完整落在畫面內）
func _perimeter_point(s: float, vp: Vector2, inset: float = 0.0) -> Vector2:
	var P: float = 2.0 * (vp.x + vp.y)
	s = fposmod(s, P)
	if s < vp.x:
		return Vector2(clamp(s, inset, vp.x - inset), inset)
	s -= vp.x
	if s < vp.y:
		return Vector2(vp.x - inset, clamp(s, inset, vp.y - inset))
	s -= vp.y
	if s < vp.x:
		return Vector2(clamp(vp.x - s, inset, vp.x - inset), vp.y - inset)
	s -= vp.x
	return Vector2(inset, clamp(vp.y - s, inset, vp.y - inset))


## 雷射式邊光：從撞點沿外框往兩側跑，四邊連成一條路徑，轉角會自然繞過去
func _draw_wall_light(vp: Vector2, w: Dictionary) -> void:
	var t: float = w["t"]
	var fade: float = 1.0 - t / WALL_LIGHT_T
	fade = fade * fade
	var reach: float = WALL_LIGHT_SPEED * t
	var P: float = 2.0 * (vp.x + vp.y)
	reach = min(reach, P * 0.5)
	var s0: float = w["s"]
	var seg := 12.0
	var inset := 10.0
	## 兩個方向各畫一條 polyline，分段設透明度（越遠越暗）
	for dir in [1.0, -1.0]:
		var d := 0.0
		while d < reach:
			var d2: float = min(d + seg, reach)
			var a0: Vector2 = _perimeter_point(s0 + dir * d, vp, inset)
			var a1: Vector2 = _perimeter_point(s0 + dir * d2, vp, inset)
			var k: float = 1.0 - d / max(reach, 1.0)
			var alpha: float = fade * k
			## 轉角：兩點不在同一條邊時，補上角落點，讓線貼著框轉彎
			if a0.x != a1.x and a0.y != a1.y:
				var on_v0: bool = (a0.x == inset or a0.x == vp.x - inset)
				var on_h0: bool = (a0.y == inset or a0.y == vp.y - inset)
				var corner := Vector2(
					a0.x if on_v0 else a1.x,
					a0.y if on_h0 else a1.y)
				_laser_seg(a0, corner, alpha, k)
				_laser_seg(corner, a1, alpha, k)
			else:
				_laser_seg(a0, a1, alpha, k)
			d = d2
	## 前緣：光跑到的最前端有一小段更亮（像掃描頭）
	for dir in [1.0, -1.0]:
		var e0: Vector2 = _perimeter_point(s0 + dir * max(reach - 40.0, 0.0), vp, inset)
		var e1: Vector2 = _perimeter_point(s0 + dir * reach, vp, inset)
		if e0.x == e1.x or e0.y == e1.y:
			draw_line(e0, e1, Color(1.0, 1.0, 0.95, fade * 0.9), 3.0)


## 一段雷射：外層寬而淡（光暈）、內層細而亮（核心）
func _laser_seg(a: Vector2, b: Vector2, alpha: float, k: float) -> void:
	if a == b:
		return
	## 科技感：細而銳利的核心 + 兩圈有明確邊界的光帶（不是柔和漸層），外帶微微偏青
	draw_line(a, b, Color(0.95, 0.9, 0.7, alpha * 0.14), 48.0 + 12.0 * k)
	draw_line(a, b, Color(WALL_LIGHT_COL, alpha * 0.4), 22.0 + 8.0 * k)
	draw_line(a, b, Color(WALL_LIGHT_COL, alpha * 0.75), 9.0)
	draw_line(a, b, Color(1.0, 1.0, 0.96, alpha), 3.0)


## 判定環：原本的白線加粗，底下墊一圈很淡的暗邊讓紅底也看得清
func _draw_ring(c: Vector2, r: float, col: Color, _u: float) -> void:
	draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 0.18), 11.0)
	draw_arc(c, r, 0.0, TAU, 96, col, 6.0)
