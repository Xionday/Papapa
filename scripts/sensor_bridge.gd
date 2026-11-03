extends Node
## 統一的感測器入口。
## Web：讀 window.papapaMotion（由 web/motion.js 更新）。
## 原生 iOS/Android：讀 Input.get_accelerometer / get_gravity。
## 之後 Ball 只跟這個節點講話，不管底層是哪個平台。

## 每幀發出。linear 不含重力，gravity 含重力方向，兩者都是 m/s²。
signal sample(linear: Vector3, gravity: Vector3)

var _js: JavaScriptObject = null
var _last_seq: int = -1

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
	gravity = Vector3(float(_js.gx), float(_js.gy), float(_js.gz)) - linear
	rotation_rate = Vector3(float(_js.rx), float(_js.ry), float(_js.rz))
	hz = int(_js.hz)
	interval_ms = float(_js.interval)


func _read_native() -> void:
	var accel := Input.get_accelerometer()
	gravity = Input.get_gravity()
	linear = accel - gravity
	rotation_rate = Input.get_gyroscope()
	hz = Engine.get_frames_per_second()
