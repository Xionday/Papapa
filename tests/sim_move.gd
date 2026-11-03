extends SceneTree
## 位移模型模擬：餵合成的「平穩移動 D 公尺、花 T 秒」加速度曲線，看畫面走幾 px。
## 用法：godot --headless --path . -s tests/sim_move.gd

const PX_PER_M := 2500.0


## 回傳 [畫面位移 px, 結束後 1 秒內的殘餘飄移 px]
func run_model(D: float, T: float, damping: float, deadzone: float, zupt: bool, noise: float) -> Array:
	var dt := 1.0 / 60.0
	var vel := 0.0
	var pos := 0.0
	var quiet := 0.0
	var lp := 0.0
	var pos_at_end := 0.0
	var t := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	while t < T + 1.0:
		## 真實加速度：半正弦推、半正弦煞，位移剛好 D
		var a := 0.0
		if t < T:
			a = (D * PI * PI / (T * T)) * sin(2.0 * PI * t / T) / 2.0
			## 上式積分兩次後位移 = D（sin 一個完整週期的加速度曲線）
		a += rng.randfn(0.0, noise)
		## 低通：先把雜訊濾掉再判斷死區（EMA，時間常數約 50 ms）
		lp += (a - lp) * (1.0 - exp(-dt / 0.05))
		a = lp
		## 遲滯：一旦動起來，低於死區的加速度照樣積分，直到安靜 0.15 秒才算停
		var a_used := a
		if abs(a) < deadzone:
			quiet += dt
			if zupt and vel == 0.0:
				a_used = 0.0
		else:
			quiet = 0.0
		vel += a_used * dt
		vel *= exp(-damping * dt)
		if zupt and quiet > 0.15:
			vel = 0.0
		pos += vel * PX_PER_M * dt
		t += dt
		if abs(t - T) < dt * 0.5:
			pos_at_end = pos
	return [pos_at_end, pos - pos_at_end]


func _init() -> void:
	## 加速度曲線是 sin 一個週期，兩次積分後的位移是 D·π/4，所以理想值是 0.785·D
	print("目標：移 0.20 m（曲線實際位移 %.3f m），理想畫面位移 = %.0f px" % [0.20 * PI / 4.0, 0.20 * PI / 4.0 * PX_PER_M])
	print("")
	print("%-34s %8s %8s %8s %8s" % ["模型", "T=0.25s", "T=0.4s", "T=0.6s", "T=1.0s"])
	var models := [
		["現在：damping 5, deadzone 0.6", 5.0, 0.6, false],
		["damping 0.5, deadzone 0.8, ZUPT", 0.5, 0.8, true],
		["damping 0, deadzone 0.8, ZUPT", 0.0, 0.8, true],
		["damping 0, deadzone 1.0, ZUPT", 0.0, 1.0, true],
	]
	for m in models:
		var row := "%-34s" % m[0]
		for T in [0.25, 0.4, 0.6, 1.0]:
			var r := run_model(0.20, T, m[1], m[2], m[3], 0.0)
			row += " %7.0f" % r[0]
		print(row)
	print("")
	for noise in [0.3, 0.5]:
		print("手持雜訊 σ=%.1f m/s²（0.4 秒移 20 cm）：" % noise)
		for m in models:
			var worst := 0.0
			var disp := 0.0
			for seed in 5:
				var r := run_model(0.20, 0.4, m[1], m[2], m[3], noise)
				disp = r[0]
				worst = max(worst, abs(r[1]))
			print("  %-34s 位移 %5.0f  結束後 1 秒最大飄移 %5.0f" % [m[0], disp, worst])
		## 完全靜止時 3 秒飄多少
		for m in models:
			var r := run_model(0.0, 0.01, m[1], m[2], m[3], noise)
			print("  %-34s 靜止 1 秒飄移 %5.0f" % [m[0], abs(r[1])])
	quit()
