@tool
extends Control
## PLPL 標誌：若 res://assets/logo.png 存在就顯示它，否則用程式畫一個佔位版（同一風格）。

var _tex: Texture2D = null


func _ready() -> void:
	if ResourceLoader.exists("res://assets/logo.png"):
		_tex = load("res://assets/logo.png")
	queue_redraw()


func _draw() -> void:
	var s: float = min(size.x, size.y)
	var o: Vector2 = (size - Vector2(s, s)) * 0.5
	if _tex != null:
		draw_texture_rect(_tex, Rect2(o, Vector2(s, s)), false)
		return
	## 佔位：奶油色圓角方塊 + 紅拍面 + 黃球 + PLPL
	var r := s * 0.22
	_rounded(Rect2(o, Vector2(s, s)), r, Color(1.0, 0.95, 0.85))
	var c := o + Vector2(s * 0.5, s * 0.42)
	var pr := s * 0.21
	draw_circle(c + Vector2(0, pr * 0.1), pr + 4.0, Color(0.55, 0.40, 0.25))
	draw_circle(c, pr, Color(0.91, 0.42, 0.40))
	var handle := PackedVector2Array([
		c + Vector2(-pr * 0.22, pr * 0.8), c + Vector2(pr * 0.22, pr * 0.8),
		c + Vector2(pr * 0.3, pr * 1.55), c + Vector2(-pr * 0.3, pr * 1.55)])
	draw_colored_polygon(handle, Color(0.78, 0.62, 0.42))
	var bc := c + Vector2(pr * 0.95, -pr * 0.9)
	draw_circle(bc + Vector2(0, 3), pr * 0.42, Color(0.75, 0.62, 0.1))
	draw_circle(bc, pr * 0.4, Color(1.0, 0.87, 0.2))
	draw_circle(bc + Vector2(-pr * 0.12, -pr * 0.13), pr * 0.12, Color(1, 1, 1, 0.6))
	var font := ThemeDB.fallback_font
	var fs := int(s * 0.19)
	var txt := "PLPL"
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, o + Vector2(s * 0.5 - w * 0.5, s * 0.9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.2, 0.16, 0.1))


func _rounded(rect: Rect2, radius: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)
