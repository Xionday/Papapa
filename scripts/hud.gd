extends CanvasLayer
## 第 1 步：只顯示感測器原始值，用來驗證 Safari 的 DeviceMotion 有沒有在動、頻率多少。

@onready var _sensor: Node = $"../SensorBridge"
@onready var _label: Label = $Margin/Label

var _peak_linear: float = 0.0


func _process(_delta: float) -> void:
	var l: Vector3 = _sensor.linear
	var g: Vector3 = _sensor.gravity
	var r: Vector3 = _sensor.rotation_rate
	_peak_linear = max(_peak_linear * 0.995, l.length())

	_label.text = "\n".join([
		"Papapa 感測器測試",
		"狀態: %s" % _sensor.status,
		"事件頻率: %d Hz  (interval %.1f ms)" % [_sensor.hz, _sensor.interval_ms],
		"",
		"線性加速度 m/s²",
		"  x %+6.2f  y %+6.2f  z %+6.2f" % [l.x, l.y, l.z],
		"  大小 %.2f   近期峰值 %.2f" % [l.length(), _peak_linear],
		"",
		"重力 m/s²",
		"  x %+6.2f  y %+6.2f  z %+6.2f" % [g.x, g.y, g.z],
		"",
		"旋轉速率 deg/s",
		"  x %+6.1f  y %+6.1f  z %+6.1f" % [r.x, r.y, r.z],
		"",
		"FPS: %d" % Engine.get_frames_per_second(),
		"",
		_sensor.user_agent,
	])
