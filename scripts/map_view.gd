extends Node2D

signal tile_clicked(p: Vector2i)

const TILE := 32
const MIN_SCALE := 0.6
const MAX_SCALE := 2.5
const TAP_SLOP := 14.0
const EDGE_SLACK := 64.0

const TERRAIN_COLORS := {
	0: Color(0.36, 0.55, 0.25),
	1: Color(0.2, 0.38, 0.18),
	2: Color(0.18, 0.34, 0.58),
	3: Color(0.5, 0.48, 0.46),
}

const BUILDING_COLORS := {
	"castle": Color(0.72, 0.68, 0.58),
	"farm": Color(0.78, 0.62, 0.2),
	"house": Color(0.55, 0.3, 0.2),
}

var world
var sim
var buildings := {}
var selected := Vector2i(-1, -1)

var _mouse_down := false
var _mouse_moved := false
var _last_screen := Vector2.ZERO
var _press_screen := Vector2.ZERO
var _touches := {}
var _tap_index := -1
var _tap_pos := Vector2.ZERO
var _tap_valid := false
var _pinch_dist := 0.0

func setup(w, sim_ref) -> void:
	world = w
	sim = sim_ref
	buildings = sim.buildings
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_mouse_down = true
		_mouse_moved = false
		_press_screen = event.position
		_last_screen = event.position
	elif _mouse_down:
		_mouse_down = false
		if not _mouse_moved:
			_tap(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_down:
		return
	var delta := event.position - _last_screen
	_last_screen = event.position
	if _press_screen.distance_to(event.position) > TAP_SLOP:
		_mouse_moved = true
	if _mouse_moved:
		_pan(delta)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_pos = event.position
			_tap_valid = true
		elif _touches.size() == 2:
			_tap_valid = false
			_pinch_dist = _pinch_distance()
	else:
		_touches.erase(event.index)
		_pinch_dist = 0.0 if _touches.size() < 2 else _pinch_dist
		if _touches.is_empty() and _tap_valid and event.index == _tap_index:
			_tap(_tap_pos)

func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		var d := _pinch_distance()
		if _pinch_dist > 0.0 and d > 0.0:
			var pts := _touches.values()
			_zoom_at((pts[0] + pts[1]) / 2.0, d / _pinch_dist)
		_pinch_dist = d
	else:
		_tap_valid = false
		_pan(event.relative)

func _tap(screen_pos: Vector2) -> void:
	var local := to_local(screen_pos)
	var p := Vector2i(floori(local.x / TILE), floori(local.y / TILE))
	if world.in_bounds(p):
		tile_clicked.emit(p)

func _pan(screen_delta: Vector2) -> void:
	position += screen_delta
	_clamp_position()

func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var local := to_local(screen_point)
	var s: float = clampf(scale.x * factor, MIN_SCALE, MAX_SCALE)
	scale = Vector2(s, s)
	position = screen_point - local * s
	_clamp_position()

func _clamp_position() -> void:
	if world == null:
		return
	var view := get_viewport_rect().size
	var content := Vector2(world.SIZE_X, world.SIZE_Y) * TILE * scale.x
	position.x = _clamp_axis(position.x, content.x, view.x)
	position.y = _clamp_axis(position.y, content.y, view.y)

func _clamp_axis(pos: float, content: float, view: float) -> float:
	if content + EDGE_SLACK * 2.0 < view:
		var center := (view - content) / 2.0
		return clampf(pos, center - EDGE_SLACK, center + EDGE_SLACK)
	return clampf(pos, view - content - EDGE_SLACK, EDGE_SLACK)

func _pinch_distance() -> float:
	var pts := _touches.values()
	if pts.size() < 2:
		return 0.0
	return pts[0].distance_to(pts[1])

func _hash(x: int, y: int, n: int) -> float:
	return fposmod(float((x * 73856093) ^ (y * 19349663) ^ (n * 83492791)) / 1000.0, 1.0)

func _draw() -> void:
	if world == null:
		return
	for x in world.SIZE_X:
		for y in world.SIZE_Y:
			var t: int = world.tiles[y * world.SIZE_X + x]
			var origin := Vector2(x * TILE, y * TILE)
			draw_rect(Rect2(origin, Vector2(TILE - 1, TILE - 1)), TERRAIN_COLORS[t])
			match t:
				0:
					_draw_grass(origin, x, y)
				1:
					_draw_forest(origin, x, y)
				2:
					_draw_water(origin, x, y)
				3:
					_draw_mountain(origin, x, y)
	for p in buildings:
		_draw_building(p, buildings[p])
	if sim != null:
		_draw_agents()
	if selected.x >= 0:
		draw_rect(Rect2(Vector2(selected * TILE), Vector2(TILE - 1, TILE - 1)), Color(0.95, 0.8, 0.3), false, 2.0)

func _draw_grass(origin: Vector2, x: int, y: int) -> void:
	var dark := Color(0.28, 0.46, 0.2)
	for n in 2:
		var px := origin + Vector2(_hash(x, y, n) * (TILE - 8) + 4, _hash(x, y, n + 10) * (TILE - 8) + 4)
		draw_rect(Rect2(px, Vector2(2, 4)), dark)

func _draw_forest(origin: Vector2, x: int, y: int) -> void:
	for n in 3:
		var px := origin + Vector2(_hash(x, y, n) * (TILE - 12) + 4, _hash(x, y, n + 5) * (TILE - 14) + 6)
		draw_rect(Rect2(px + Vector2(2, 8), Vector2(2, 4)), Color(0.3, 0.2, 0.1))
		var crown := PackedVector2Array([
			px + Vector2(3, 0), px + Vector2(-1, 8), px + Vector2(7, 8),
		])
		draw_colored_polygon(crown, Color(0.3, 0.5, 0.22))

func _draw_water(origin: Vector2, x: int, y: int) -> void:
	var light := Color(0.3, 0.48, 0.7)
	for n in 2:
		var py := origin + Vector2(4 + _hash(x, y, n) * 8, 8 + n * 10)
		draw_line(py, py + Vector2(10 + _hash(x, y, n + 3) * 8, 0), light, 2.0)

func _draw_mountain(origin: Vector2, x: int, y: int) -> void:
	var base := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 4)
	var peak := PackedVector2Array([
		base + Vector2(0, -22), base + Vector2(-11, 0), base + Vector2(11, 0),
	])
	draw_colored_polygon(peak, Color(0.36, 0.34, 0.33))
	var cap := PackedVector2Array([
		base + Vector2(0, -22), base + Vector2(-4, -14), base + Vector2(4, -14),
	])
	draw_colored_polygon(cap, Color(0.85, 0.85, 0.85))

func _draw_building(p: Vector2i, b: Dictionary) -> void:
	if not b.complete:
		_draw_site(p, b.kind)
		return
	var kind: String = b.kind
	var origin := Vector2(p.x * TILE, p.y * TILE)
	match kind:
		"farm":
			draw_rect(Rect2(origin + Vector2(4, 10), Vector2(TILE - 8, TILE - 16)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(4, 14), Vector2(TILE - 8, 3)), Color(0.55, 0.75, 0.3))
			draw_rect(Rect2(origin + Vector2(4, 20), Vector2(TILE - 8, 3)), Color(0.55, 0.75, 0.3))
		"house":
			draw_rect(Rect2(origin + Vector2(6, 14), Vector2(TILE - 12, TILE - 18)), BUILDING_COLORS[kind])
			var roof := PackedVector2Array([
				origin + Vector2(TILE / 2.0, 4), origin + Vector2(4, 15), origin + Vector2(TILE - 4, 15),
			])
			draw_colored_polygon(roof, Color(0.35, 0.18, 0.12))
		"castle":
			draw_rect(Rect2(origin + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), BUILDING_COLORS[kind])
			for n in 3:
				draw_rect(Rect2(origin + Vector2(4 + n * 8, -2), Vector2(5, 6)), BUILDING_COLORS[kind])
			draw_line(origin + Vector2(TILE / 2.0, -4), origin + Vector2(TILE / 2.0, -14), Color(0.2, 0.2, 0.2), 2.0)
			var flag := PackedVector2Array([
				origin + Vector2(TILE / 2.0, -14), origin + Vector2(TILE / 2.0 + 8, -11), origin + Vector2(TILE / 2.0, -8),
			])
			draw_colored_polygon(flag, Color(0.75, 0.2, 0.2))

func _draw_site(p: Vector2i, kind: String) -> void:
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var frame := Color(0.5, 0.37, 0.22)
	draw_rect(Rect2(origin + Vector2(4, 10), Vector2(TILE - 8, TILE - 16)), frame, false, 2.0)
	draw_line(origin + Vector2(6, 12), origin + Vector2(TILE - 6, TILE - 8), frame, 2.0)
	draw_line(origin + Vector2(TILE - 6, 12), origin + Vector2(6, TILE - 8), frame, 2.0)
	var pole := origin + Vector2(TILE / 2.0, 8)
	draw_line(pole, pole + Vector2(0, -12), Color(0.25, 0.18, 0.12), 2.0)
	var flag := PackedVector2Array([
		pole + Vector2(0, -12), pole + Vector2(9, -9), pole + Vector2(0, -6),
	])
	draw_colored_polygon(flag, Color(0.92, 0.75, 0.25))

func _draw_agents() -> void:
	for a in sim.agents:
		var c: Vector2 = a.pos * float(TILE)
		if a.kind == "collector":
			draw_circle(c, 5.0, Color(0.35, 0.25, 0.15))
			if a.pouch > 0:
				draw_circle(c + Vector2(5.0, -5.0), 2.5, Color(0.92, 0.78, 0.2))
		else:
			draw_circle(c, 4.0, Color(0.85, 0.72, 0.55))
			if a.carrying > 0:
				draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.5, 0.7, 0.3))
			elif a.purpose == "build":
				draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.85, 0.65, 0.2))
