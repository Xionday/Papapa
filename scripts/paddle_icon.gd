@tool
extends Control
## 小球拍示意圖，純 _draw。mode: red | black | alternate（斜線分兩色）

@export var mode: String = "red":
	set(v):
		mode = v
		queue_redraw()
@export var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()

const RED := Color(0.91, 0.42, 0.40)
const BLACK := Color(0.16, 0.16, 0.17)
const WOOD := Color(0.78, 0.62, 0.42)
const WOOD_DARK := Color(0.55, 0.40, 0.25)


func _draw() -> void:
	if mode.begins_with("ball_"):
		_draw_ball()
		return
	var c := size * 0.5
	var r: float = min(size.x, size.y) * 0.34
	var head := c + Vector2(0, -r * 0.25)

	## 選中：外圈光暈
	if selected:
		draw_circle(head, r + 10.0, Color(1.0, 0.92, 0.7, 0.35))
		draw_arc(head, r + 7.0, 0.0, TAU, 48, Color(1.0, 0.92, 0.7, 0.9), 3.0)

	## 握把（在拍面後面）
	var hw: float = r * 0.42
	var hl: float = r * 1.05
	var handle := PackedVector2Array([
		head + Vector2(-hw * 0.5, r * 0.75),
		head + Vector2(hw * 0.5, r * 0.75),
		head + Vector2(hw * 0.62, r * 0.75 + hl),
		head + Vector2(-hw * 0.62, r * 0.75 + hl),
	])
	draw_colored_polygon(handle, WOOD)
	draw_polyline(handle + PackedVector2Array([handle[0]]), WOOD_DARK, 2.0)

	## 拍面
	draw_circle(head, r + 3.0, WOOD_DARK)
	match mode:
		"red":
			draw_circle(head, r, RED)
		"black":
			draw_circle(head, r, BLACK)
		_:
			## 斜線分色：左上紅、右下黑
			draw_circle(head, r, BLACK)
			var pts := PackedVector2Array()
			var n := 40
			## 從 135° 到 315° 的半圓（左上那半邊）
			for i in n + 1:
				var a: float = deg_to_rad(135.0) + PI * i / n
				pts.append(head + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, RED)
			var d := Vector2(cos(deg_to_rad(135.0)), sin(deg_to_rad(135.0))) * r
			draw_line(head + d, head - d, Color(1, 1, 1, 0.5), 2.0)
	## 高光
	draw_circle(head + Vector2(-r * 0.35, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.18))


func _draw_ball() -> void:
	var c := size * 0.5
	var r: float = min(size.x, size.y) * 0.3
	var col := Color(1.0, 0.87, 0.2) if mode == "ball_yellow" else Color(0.98, 0.98, 0.95)
	if selected:
		draw_circle(c, r + 10.0, Color(1.0, 0.92, 0.7, 0.35))
		draw_arc(c, r + 7.0, 0.0, TAU, 48, Color(1.0, 0.92, 0.7, 0.9), 3.0)
	draw_circle(c + Vector2(0, r * 0.08), r, col.darkened(0.25))
	draw_circle(c, r * 0.96, col)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.32), r * 0.28, Color(1, 1, 1, 0.55))
