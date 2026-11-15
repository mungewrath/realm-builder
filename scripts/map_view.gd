extends Node2D

signal tile_clicked(p: Vector2i)

const TILE := 32

const TERRAIN_COLORS := {
	0: Color(0.36, 0.55, 0.25),
	1: Color(0.16, 0.32, 0.14),
	2: Color(0.18, 0.34, 0.58),
	3: Color(0.45, 0.44, 0.42),
}

const BUILDING_COLORS := {
	"castle": Color(0.72, 0.68, 0.58),
	"farm": Color(0.78, 0.62, 0.2),
	"house": Color(0.55, 0.3, 0.2),
}

var world
var buildings := {}

func setup(w, buildings_ref: Dictionary) -> void:
	world = w
	buildings = buildings_ref
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(event.position)
		var p := Vector2i(floori(local.x / TILE), floori(local.y / TILE))
		if world.in_bounds(p):
			tile_clicked.emit(p)

func _draw() -> void:
	if world == null:
		return
	for x in world.SIZE_X:
		for y in world.SIZE_Y:
			var t: int = world.tiles[y * world.SIZE_X + x]
			draw_rect(Rect2(x * TILE, y * TILE, TILE - 1, TILE - 1), TERRAIN_COLORS[t])
	for p in buildings:
		var kind: String = buildings[p]
		if BUILDING_COLORS.has(kind):
			var c: Color = BUILDING_COLORS[kind]
			var size := TILE - 6 if kind == "castle" else TILE - 10
			draw_rect(Rect2(p.x * TILE + (TILE - size) / 2.0, p.y * TILE + (TILE - size) / 2.0, size, size), c)
			draw_rect(Rect2(p.x * TILE + (TILE - size) / 2.0, p.y * TILE + (TILE - size) / 2.0, size, size), Color(0.1, 0.1, 0.1, 0.6), false, 1.0)
