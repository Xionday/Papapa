extends Node
## 程式合成的音效，不需要音檔。原生與 Web 都能用。
## Web 版：瀏覽器要在使用者點過畫面後才允許出聲，Godot 會在第一次觸控時自動解鎖。

const RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	## 名稱: [頻率列表, 長度秒, 音量 0~1, 波形 sine|square|noise]
	_streams["perfect"] = _tone([880.0, 1320.0], 0.18, 0.5, "sine")
	_streams["good"] = _tone([660.0], 0.12, 0.45, "sine")
	_streams["bad"] = _tone([220.0], 0.14, 0.45, "square")
	_streams["miss"] = _tone([160.0], 0.2, 0.4, "square")
	_streams["stop"] = _tone([140.0, 100.0], 0.4, 0.5, "square")
	_streams["tick"] = _tone([1200.0], 0.03, 0.25, "sine")
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String) -> void:
	if not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.play()


## 產生一段 16-bit 單聲道 WAV：多個頻率依序接起來（琶音），指數衰減包絡
func _tone(freqs: Array, length: float, vol: float, wave: String) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var seg: float = float(n) / freqs.size()
	for i in n:
		var f: float = freqs[int(i / seg)]
		var t: float = float(i) / RATE
		var env: float = exp(-5.0 * t / length) * (1.0 - exp(-t * 400.0))
		var v: float
		match wave:
			"square":
				v = 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
				v *= 0.6
			"noise":
				v = randf_range(-1.0, 1.0)
			_:
				v = sin(TAU * f * t)
		var s := int(clamp(v * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
