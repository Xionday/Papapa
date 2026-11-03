extends Node
## 統一的感測器入口。
## Web：讀 window.papapaMotion（由 web/motion.js 更新）。
## 原生 iOS/Android：讀 Input.get_accelerometer / get_gravity。
## 之後 Ball 只跟這個節點講話，不管底層是哪個平台。

## 每幀發出。linear = 裝置真實加速度（不含重力）；gravity = 物理重力方向（平放時 z ≈ −9.8）。
## 都是裝置座標、m/s²。Web 端的值已由 motion.js 統一成 W3C 規格慣例。
signal sample(linear: Vector3, gravity: Vector3)

var _js: JavaScriptObject = null
var _haptic: JavaScriptObject = null
var _last_seq: int = -1
var haptic_mode: String = "native"

## 給 HUD 看的除錯資訊
var status: String = "native"
var hz: int = 0
var interval_ms: float = 0.0
var linear: Vector3 = Vector3.ZERO
var gravity: Vector3 = Vector3.ZERO
var rotation_rate: Vector3 = Vector3.ZERO
var user_agent: String = ""


func _ready() -> void:
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("papapaMotion")
		if _js == null:
			status = "no motion.js"
		else:
			user_agent = str(_js.ua)
		_haptic = JavaScriptBridge.get_interface("papapaHaptic")
		haptic_mode = str(_haptic.mode) if _haptic != null else "none"


## 震動：count 連點幾下。強擊 1、弱擊 2、漏接 3。
func haptic(count: int = 1, gap_ms: int = 70) -> void:
	if _haptic != null:
		haptic_mode = str(_haptic.mode)
		_haptic.tap(count, gap_ms)
	elif not OS.has_feature("web"):
		Input.vibrate_handheld(40 * count)


func _process(_delta: float) -> void:
	if _js != null:
		_read_web()
	elif OS.has_feature("web"):
		return
	else:
		_read_native()
	sample.emit(linear, gravity)


func _read_web() -> void:
	status = str(_js.status)
	var seq: int = int(_js.seq)
	if seq == _last_seq:
		return
	_last_seq = seq
	linear = Vector3(float(_js.ax), float(_js.ay), float(_js.az))
	## 規格：accelerationIncludingGravity = linear + 支撐力；支撐力 = −物理重力
	var reaction := Vector3(float(_js.gx), float(_js.gy), float(_js.gz)) - linear
	gravity = -reaction
	rotation_rate = Vector3(float(_js.rx), float(_js.ry), float(_js.rz))
	hz = int(_js.hz)
	interval_ms = float(_js.interval)


func _read_native() -> void:
	var accel := Input.get_accelerometer()
	gravity = Input.get_gravity()
	linear = accel - gravity
	rotation_rate = Input.get_gyroscope()
	hz = Engine.get_frames_per_second()
