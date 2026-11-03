extends Node2D
## 第 2 步：核心玩法。
## 螢幕就是球拍面（俯視）。球在拍面上方彈跳，影子畫在拍面上。
## 所有「往上」「水平」都相對重力向量計算，不寫死感測器正負號。

signal hit(strong: bool, streak: int)
signal missed(streak: int)
signal pushed(dir: Vector2)

## ---- 可調參數（HUD 的滑桿會改這些）----
@export var hit_threshold: float = 5.0      ## m/s²，接球瞬間附近要有這麼大的向上加速度才算「有用力」
@export var hit_window: float = 0.15        ## s，往回看多久
@export var push_threshold: float = 3.0     ## m/s²，水平加速度超過就算「推一下」
@export var push_distance: float = 300.0    ## px，推一下球拍在世界裡移動多遠
@export var push_cooldown: float = 0.35     ## s
@export var decay: float = 0.8              ## 沒用力時，下一次起跳速度 = 上次 × decay
@export var full_launch: float = 5.9        ## m/s，用力時的起跳速度（約 1.2 秒滯空）
@export var min_launch: float = 2.0         ## m/s，衰減的下限
@export var lateral_gain: float = 150.0     ## px/s per m/s² 的傾斜
@export var show_height: float = 0.6        ## m，球低於這個高度才看得到
@export var gravity_m: float = 9.8

## ---- 狀態 ----
var ball_pos: Vector2 = Vector2.ZERO        ## 世界座標，px
var ball_h: float = 0.0                     ## m
var v_up: float = 0.0                       ## m/s
var v_lat: Vector2 = Vector2.ZERO           ## px/s
var last_launch: float = 0.0
var paddle_pos: Vector2 = Vector2.ZERO      ## 球拍（螢幕中心）在世界裡的位置
var _paddle_target: Vector2 = Vector2.ZERO
var streak: int = 0
var best: int = 0
var state: String = "serve"                 ## serve | air | dead
var _dead_timer: float = 0.0
var _push_timer: float = 0.0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE

## 感測器
var up_dir: Vector3 = Vector3(0, 0, 1)
var up_accel: float = 0.0
var horiz_accel: Vector2 = Vector2.ZERO
var tilt: Vector2 = Vector2.ZERO
var tilt_zero: Vector2 = Vector2.ZERO        ## 校正：把目前握持角度當成水平
var _up_hist: Array[Vector2] = []           ## (time, up_accel)
var last_hit_peak: float = 0.0

@onready var _sensor: Node = $SensorBridge


func _ready() -> void:
	_sensor.sample.connect(_on_sample)
	_serve()


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
	var now := Time.get_ticks_msec() / 1000.0
	_up_hist.append(Vector2(now, up_accel))
	while _up_hist.size() > 0 and now - _up_hist[0].x > hit_window:
		_up_hist.pop_front()


func calibrate_tilt() -> void:
	tilt_zero += tilt


func _recent_up_peak() -> float:
	var peak := 0.0
	for s in _up_hist:
		peak = max(peak, s.y)
	return peak


func _serve() -> void:
	state = "air"
	ball_pos = paddle_pos
	ball_h = 0.0
	last_launch = full_launch
	v_up = full_launch
	v_lat = Vector2.ZERO
	streak = 0


func _process(delta: float) -> void:
	_push_timer = max(0.0, _push_timer - delta)
	_flash = max(0.0, _flash - delta * 3.0)
	paddle_pos = paddle_pos.lerp(_paddle_target, 1.0 - exp(-12.0 * delta))

	match state:
		"air":
			_step_air(delta)
		"dead":
			_dead_timer -= delta
			if _dead_timer <= 0.0:
				_serve()
	queue_redraw()


func _step_air(delta: float) -> void:
	ball_h += v_up * delta
	v_up -= gravity_m * delta
	ball_pos += v_lat * delta

	## 推一下：球在空中、水平加速度夠大、冷卻結束
	if ball_h > 0.15 and _push_timer <= 0.0 and horiz_accel.length() >= push_threshold:
		var dir := horiz_accel.normalized()
		_paddle_target += dir * push_distance
		_push_timer = push_cooldown
		pushed.emit(dir)

	if ball_h <= 0.0 and v_up < 0.0:
		ball_h = 0.0
		if _on_paddle():
			var peak := _recent_up_peak()
			last_hit_peak = peak
			var strong := peak >= hit_threshold
			if strong:
				last_launch = full_launch
			else:
				last_launch = max(last_launch * decay, min_launch)
			v_up = last_launch
			v_lat = tilt * lateral_gain
			streak += 1
			best = max(best, streak)
			_flash = 1.0
			_flash_color = Color(0.36, 0.79, 0.65) if strong else Color(0.98, 0.78, 0.46)
			hit.emit(strong, streak)
		else:
			state = "dead"
			_dead_timer = 1.5
			_flash = 1.0
			_flash_color = Color(0.89, 0.29, 0.29)
			missed.emit(streak)


func _on_paddle() -> bool:
	var half := get_viewport_rect().size * 0.5
	var d := ball_pos - paddle_pos
	return abs(d.x) <= half.x and abs(d.y) <= half.y


## ---- 畫面 ----
func _to_screen(world: Vector2) -> Vector2:
	return get_viewport_rect().size * 0.5 + (world - paddle_pos)


func _draw() -> void:
	var vp := get_viewport_rect().size
	## 拍面
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
	var max_h: float = (full_launch * full_launch) / (2.0 * gravity_m)
	var t: float = clamp(ball_h / max_h, 0.0, 1.0)

	## 影子：頭頂燈的模型 — 球越高影子越大越淡，落地時最小最實
	var shadow_r: float = lerp(28.0, 90.0, t)
	var shadow_a: float = lerp(0.55, 0.12, t)
	draw_circle(sp, shadow_r, Color(0, 0, 0, shadow_a))

	## 球：只有低於 show_height 才看得到，越高(越靠近眼睛)越大
	if ball_h <= show_height and state != "dead":
		var k: float = clamp(ball_h / show_height, 0.0, 1.0)
		var r: float = lerp(26.0, 70.0, k)
		draw_circle(sp, r, Color(0.94, 0.6, 0.48))
		draw_circle(sp + Vector2(-r * 0.3, -r * 0.3), r * 0.25, Color(1, 1, 1, 0.5))
	elif state != "dead":
		## 球在視野外：畫一個指向落點的提示環
		draw_arc(sp, 100.0 + 40.0 * t, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 2.0)
