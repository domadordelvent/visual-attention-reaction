extends Control
const Stimuli = preload("res://stimuli.gd")
var item: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func display(value: Dictionary) -> void:
	item = value
	queue_redraw()

func _draw() -> void:
	if item.is_empty(): return
	var center := size / 2.0
	var radius := minf(111.0, minf(size.x, size.y) * 0.45)
	var color: Color = Stimuli.COLORS[item.color]
	match item.shape:
		"square": draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), color)
		"circle": draw_circle(center, radius, color)
		"diamond":
			# A regular square rotated 45 degrees, with equal diagonals.
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius), center + Vector2(radius, 0),
				center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)
		_:
			var sides: int = {"triangle": 3, "pentagon": 5}[item.shape]
			var vertices := PackedVector2Array()
			for i in sides:
				vertices.append(center + Vector2.from_angle(-PI / 2.0 + TAU * i / sides) * radius)
			draw_colored_polygon(vertices, color)
