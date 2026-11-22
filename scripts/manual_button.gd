extends Button

# A small hand-drawn reference book. The button keeps the normal theme box so
# it reads as tappable; this only adds the book glyph on top.

func _ready() -> void:
	custom_minimum_size = Vector2(60, 56)
	toggle_mode = true
	text = ""
	tooltip_text = "Open the player manual"

func _draw() -> void:
	var c := size * 0.5
	# Dark cover, page block, spine, page lines and a little brass clasp.
	draw_rect(Rect2(c + Vector2(-13, -14), Vector2(26, 28)),
		Color(0.34, 0.15, 0.12))
	draw_rect(Rect2(c + Vector2(-10, -11), Vector2(19, 23)),
		Color(0.9, 0.85, 0.7))
	draw_rect(Rect2(c + Vector2(7, -11), Vector2(3, 23)),
		Color(0.7, 0.64, 0.49))
	draw_rect(Rect2(c + Vector2(-13, -14), Vector2(4, 28)),
		Color(0.5, 0.19, 0.16))
	for i in 3:
		draw_line(c + Vector2(-6, -6 + i * 6), c + Vector2(5, -6 + i * 6),
			Color(0.45, 0.4, 0.32), 1.2)
	draw_rect(Rect2(c + Vector2(5, -2), Vector2(3, 5)),
		Color(0.86, 0.69, 0.25))
