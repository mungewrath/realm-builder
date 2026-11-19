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
	"guardhouse": Color(0.58, 0.6, 0.66),
	"tavern": Color(0.45, 0.3, 0.18),
	"market": Color(0.55, 0.42, 0.26),
	"shrine": Color(0.8, 0.78, 0.72),
}

const HERO_COLORS := {
	"rogue": Color(0.55, 0.4, 0.65),
	"warrior": Color(0.75, 0.4, 0.3),
	"paladin": Color(0.9, 0.85, 0.55),
}

const GOLD := Color(0.92, 0.78, 0.2)
const FOG_DARK := Color(0.03, 0.04, 0.07)

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
			var p := Vector2i(x, y)
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
			# M5 fog: dark until charted; charted ground stays lit
			# permanently. Edges lighten a step so the veil reads soft.
			var lvl := _fog_level(p)
			if lvl < 2:
				draw_rect(Rect2(origin, Vector2(TILE, TILE)),
					FOG_DARK, _fog_alpha(p))
	for p in buildings:
		_draw_building(p, buildings[p])
	if sim != null and sim.get("dens") != null:
		for p in sim.dens:
			# Landmarks surface as the fog lifts, and stay remembered.
			if _fog_level(p) == 0:
				continue
			_draw_den(p, sim.dens[p])
	if sim != null and sim.get("loot_piles") != null:
		for p in sim.loot_piles:
			if _fog_level(p) == 0:
				continue
			_draw_loot_pile(p)
	if sim != null:
		_draw_agents()
	if selected.x >= 0:
		draw_rect(Rect2(Vector2(selected * TILE), Vector2(TILE - 1, TILE - 1)), Color(0.95, 0.8, 0.3), false, 2.0)

func _fog_level(p: Vector2i) -> int:
	# 0 unseen, 2 revealed (revealed ground stays lit permanently).
	# Fog off (dev) is level 2 everywhere.
	if sim == null or not sim.fog_enabled:
		return 2
	if not world.in_bounds(p):
		return 0
	return 2 if sim.explored[p.y * world.SIZE_X + p.x] == 1 else 0

func _fog_alpha(p: Vector2i) -> float:
	# Unseen tiles next to charted ground get a lighter veil: soft edge.
	var best := 0
	for d in world.DIRS_ALL:
		best = maxi(best, _fog_level(p + d))
	return 0.75 if best == 2 else 0.9

func center_on(p: Vector2i) -> void:
	# Minimap jumps land the tapped tile in the middle of the viewport.
	var view := get_viewport_rect().size
	position = view / 2.0 - (Vector2(p) + Vector2(0.5, 0.5)) * TILE * scale.x
	_clamp_position()

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
		"guardhouse":
			# Stone watch-tower with a pale-blue banner.
			draw_rect(Rect2(origin + Vector2(5, 10), Vector2(TILE - 10, TILE - 12)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(3, 6), Vector2(TILE - 6, 6)), BUILDING_COLORS[kind])
			for n in 2:
				draw_rect(Rect2(origin + Vector2(6 + n * 12, 3), Vector2(4, 4)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(TILE / 2.0 - 2, 16), Vector2(4, TILE - 18)), Color(0.3, 0.3, 0.34))
			draw_line(origin + Vector2(TILE / 2.0 + 5, 8), origin + Vector2(TILE / 2.0 + 5, -6), Color(0.2, 0.2, 0.2), 2.0)
			var pennant := PackedVector2Array([
				origin + Vector2(TILE / 2.0 + 5, -6), origin + Vector2(TILE / 2.0 + 13, -3), origin + Vector2(TILE / 2.0 + 5, 0),
			])
			draw_colored_polygon(pennant, Color(0.45, 0.6, 0.85))
		"tavern":
			# Timber hall with a pitched roof and a hanging ale sign.
			draw_rect(Rect2(origin + Vector2(4, 14), Vector2(TILE - 8, TILE - 18)), BUILDING_COLORS[kind])
			var roof := PackedVector2Array([
				origin + Vector2(TILE / 2.0, 4), origin + Vector2(3, 15), origin + Vector2(TILE - 3, 15),
			])
			draw_colored_polygon(roof, Color(0.3, 0.2, 0.12))
			draw_line(origin + Vector2(6, 10), origin + Vector2(13, 10), Color(0.25, 0.18, 0.12), 2.0)
			draw_rect(Rect2(origin + Vector2(7, 10), Vector2(5, 6)), GOLD)
			draw_rect(Rect2(origin + Vector2(7, 16), Vector2(2, 2)), Color(0.85, 0.85, 0.85))
		"market":
			# Stall with a striped awning.
			draw_rect(Rect2(origin + Vector2(5, 14), Vector2(TILE - 10, TILE - 18)), BUILDING_COLORS[kind])
			for n in 4:
				var stripe := Color(0.85, 0.25, 0.2) if n % 2 == 0 else Color(0.92, 0.88, 0.8)
				draw_rect(Rect2(origin + Vector2(3 + n * 7, 8), Vector2(7, 6)), stripe)
			draw_circle(Vector2(origin.x + TILE / 2.0, origin.y + 19), 2.5, GOLD)
		"shrine":
			# Pale stone altar with a burning light.
			draw_rect(Rect2(origin + Vector2(8, 12), Vector2(TILE - 16, TILE - 16)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(4, TILE - 10), Vector2(TILE - 8, 6)), Color(0.7, 0.68, 0.62))
			draw_circle(Vector2(origin.x + TILE / 2.0, origin.y + 12), 3.0, GOLD)

func _draw_den(p: Vector2i, den: Dictionary) -> void:
	var kind_key: String = den.get("kind", "goblin_den")
	if kind_key == "goblin_den":
		_draw_goblin_den(p, den)
	elif kind_key == "rabbit_warren":
		_draw_warren(p)
	elif kind_key == "wolf_den":
		_draw_wolf_den(p)
	elif kind_key == "spider_den":
		_draw_spider_den(p)
	elif kind_key == "kobold_den":
		_draw_kobold_den(p)
	elif kind_key == "gnome_enclave":
		_draw_gnome_enclave(p)
	elif kind_key == "bandit_camp":
		_draw_bandit_camp(p)
	else:
		_draw_hag_coven(p)
	_draw_bounty_flag(p)

func _draw_bounty_flag(p: Vector2i) -> void:
	# A posted bounty flies a gold pennant on any lair, not just goblin dens.
	if sim == null or sim.get("bounties") == null or not sim.bounties.has(p):
		return
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var pole := origin + Vector2(TILE - 10, TILE - 10)
	draw_line(pole, pole + Vector2(0, -18), Color(0.2, 0.15, 0.1), 2.0)
	var pennant := PackedVector2Array([
		pole + Vector2(0, -18), pole + Vector2(12, -15), pole + Vector2(0, -11),
	])
	draw_colored_polygon(pennant, GOLD)

func _draw_goblin_den(p: Vector2i, den: Dictionary) -> void:
	# Cave mouth with a tattered red pennant; level pips show how bold it is.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var mouth := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 5)
	draw_circle(mouth, 11.0, Color(0.1, 0.08, 0.08))
	draw_circle(mouth + Vector2(0, 2), 8.0, Color(0.04, 0.03, 0.03))
	var pole := mouth + Vector2(8, -4)
	draw_line(pole, pole + Vector2(0, -16), Color(0.2, 0.15, 0.1), 2.0)
	var pennant := PackedVector2Array([
		pole + Vector2(0, -16), pole + Vector2(-11, -13), pole + Vector2(0, -9),
	])
	draw_colored_polygon(pennant, Color(0.7, 0.15, 0.12))
	for i in int(den.level):
		draw_circle(mouth + Vector2(-9 + i * 7, -16), 2.2, GOLD)

func _draw_warren(p: Vector2i) -> void:
	# A rabbit warren: a sandy mound with burrow holes.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	draw_circle(origin + Vector2(TILE / 2.0, TILE - 8), 9.0, Color(0.62, 0.52, 0.36))
	draw_circle(origin + Vector2(TILE / 2.0, TILE - 6), 6.0, Color(0.12, 0.09, 0.06))
	draw_circle(origin + Vector2(10, TILE - 11), 3.0, Color(0.12, 0.09, 0.06))
	draw_circle(origin + Vector2(TILE - 10, TILE - 11), 3.0, Color(0.12, 0.09, 0.06))

func _draw_wolf_den(p: Vector2i) -> void:
	# A wolf den: a dark hollow under a leaning root, paw prints beside it.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var mouth := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 5)
	draw_circle(mouth, 10.0, Color(0.14, 0.12, 0.1))
	draw_circle(mouth + Vector2(0, 2), 7.0, Color(0.05, 0.04, 0.04))
	draw_circle(origin + Vector2(9, 12), 2.0, Color(0.2, 0.16, 0.13))
	draw_circle(origin + Vector2(TILE - 9, 15), 2.0, Color(0.2, 0.16, 0.13))

func _draw_spider_den(p: Vector2i) -> void:
	# A spider nest: a cave mouth veiled in web strands.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var mouth := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 5)
	draw_circle(mouth, 10.0, Color(0.09, 0.08, 0.1))
	for n in 4:
		var a := n * PI / 4.0 + 0.3
		draw_line(mouth, mouth + Vector2(cos(a), sin(a) * 0.7 - 0.5) * 13.0,
			Color(0.85, 0.85, 0.9, 0.55), 1.2)

func _draw_kobold_den(p: Vector2i) -> void:
	# A burrow mouth ringed with stolen trinkets.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var mouth := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 6)
	draw_circle(mouth, 8.0, Color(0.4, 0.32, 0.18))
	draw_circle(mouth + Vector2(0, 2), 5.5, Color(0.08, 0.06, 0.04))
	draw_circle(mouth + Vector2(-9, 2), 1.8, Color(0.85, 0.7, 0.25))
	draw_circle(mouth + Vector2(9, 3), 1.5, Color(0.7, 0.75, 0.8))
	draw_line(mouth + Vector2(6, 5), mouth + Vector2(10, 1), Color(0.8, 0.78, 0.7), 1.2)

func _draw_gnome_enclave(p: Vector2i) -> void:
	# A round-doored hill workshop with a lantern and a little gear.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var hub := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 8)
	draw_circle(hub, 9.0, Color(0.42, 0.45, 0.34))
	draw_circle(hub + Vector2(0, 2), 5.5, Color(0.25, 0.2, 0.14))
	draw_circle(hub + Vector2(0, 3), 3.5, Color(0.55, 0.42, 0.24))
	draw_circle(hub + Vector2(8, -5), 2.2, Color(0.95, 0.85, 0.45))
	draw_circle(hub + Vector2(-8, -4), 3.0, Color(0.6, 0.62, 0.55))

func _draw_bandit_camp(p: Vector2i) -> void:
	# A tent and a cookfire by the road.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var tent := PackedVector2Array([
		origin + Vector2(9, TILE - 6),
		origin + Vector2(20, TILE - 6),
		origin + Vector2(14.5, TILE - 18),
	])
	draw_colored_polygon(tent, Color(0.46, 0.32, 0.2))
	draw_line(origin + Vector2(9, TILE - 6), origin + Vector2(20, TILE - 6),
		Color(0.25, 0.18, 0.12), 1.5)
	var fire := origin + Vector2(24, TILE - 8)
	draw_circle(fire, 3.2, Color(0.9, 0.45, 0.15))
	draw_circle(fire, 1.6, Color(0.98, 0.85, 0.35))

func _draw_hag_coven(p: Vector2i) -> void:
	# A crooked hut with a smoking chimney and a hanging charm.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var hut := Rect2(origin + Vector2(8, TILE - 20), Vector2(16, 14))
	draw_rect(hut, Color(0.28, 0.22, 0.26))
	var roof := PackedVector2Array([
		origin + Vector2(5, TILE - 19),
		origin + Vector2(27, TILE - 19),
		origin + Vector2(19, TILE - 27),
	])
	draw_colored_polygon(roof, Color(0.2, 0.16, 0.2))
	draw_rect(Rect2(origin + Vector2(20, TILE - 26), Vector2(4, 6)),
		Color(0.18, 0.15, 0.17))
	draw_circle(origin + Vector2(24, TILE - 27), 2.0, Color(0.55, 0.55, 0.5))
	draw_line(origin + Vector2(9, TILE - 20), origin + Vector2(9, TILE - 14),
		Color(0.7, 0.6, 0.3), 1.4)
	draw_circle(origin + Vector2(9, TILE - 13), 1.6, Color(0.75, 0.65, 0.3))

func _draw_loot_pile(p: Vector2i) -> void:
	# A spilled purse: a little heap of coins on the ground.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	for i in 4:
		draw_circle(origin + Vector2(9 + (i % 2) * 7, 19 - int(i / 2.0) * 5), 2.5, GOLD)
	draw_circle(origin + Vector2(12, 17), 2.0, Color(0.75, 0.6, 0.12))

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

const CREATURE_COLORS := {
	"rabbit": Color(0.85, 0.8, 0.72),
	"wolf": Color(0.42, 0.4, 0.42),
	"spider": Color(0.12, 0.1, 0.14),
}

func _draw_agents() -> void:
	for a in sim.agents:
		# Goblins and wild creatures only show when someone from the realm
		# can actually see them; the realm's own folk are always drawn
		# (heroes are the explorers lighting the way).
		if (a.kind == "goblin" or a.kind == "creature" or a.kind == "bandit") \
				and _fog_level(a.tile()) < 2:
			continue
		var c: Vector2 = a.pos * float(TILE)
		match a.kind:
			"collector":
				draw_circle(c, 5.0, Color(0.35, 0.25, 0.15))
				if a.pouch > 0:
					draw_circle(c + Vector2(5.0, -5.0), 2.5, Color(0.92, 0.78, 0.2))
			"goblin":
				# Sickly lime with a dark rim: readable against both open
				# grass and forest shade, where a plain grass-green vanished.
				draw_circle(c, 5.6, Color(0.12, 0.14, 0.07))
				draw_circle(c, 4.5, Color(0.64, 0.76, 0.28))
				draw_circle(c + Vector2(1.5, -1.0), 1.0, Color(0.9, 0.2, 0.1))
				draw_circle(c + Vector2(-1.5, -1.0), 1.0, Color(0.9, 0.2, 0.1))
				if a.carrying > 0:
					# Foraged provisions (green) or plundered gold.
					var loot_col := Color(0.5, 0.7, 0.3) if a.purpose == "forage" \
						else Color(0.92, 0.78, 0.2)
					draw_circle(c + Vector2(5.0, -4.0), 2.5, loot_col)
			"bandit":
				# A rough brown figure with a dark bandana and a coin if he
				# has lifted one.
				draw_circle(c, 5.4, Color(0.2, 0.12, 0.1))
				draw_circle(c, 4.3, Color(0.56, 0.36, 0.22))
				draw_line(c + Vector2(-3.5, -2.0), c + Vector2(3.5, -2.0),
					Color(0.15, 0.1, 0.08), 2.0)
				if a.carrying > 0:
					draw_circle(c + Vector2(5.0, -4.0), 2.5, Color(0.92, 0.78, 0.2))
			"guard":
				draw_circle(c, 4.5, Color(0.45, 0.55, 0.7))
				draw_line(c + Vector2(3, 2), c + Vector2(-3, -6), Color(0.85, 0.85, 0.9), 1.5)
			"creature":
				var col: Color = CREATURE_COLORS.get(a.species, Color(0.7, 0.6, 0.5))
				draw_circle(c, 3.5, col)
				match a.species:
					"wolf":
						draw_line(c + Vector2(0, -3), c + Vector2(0, -6), col, 2.0)
					"spider":
						for n in 4:
							var leg_a := n * PI / 4.0
							draw_line(c, c + Vector2(cos(leg_a), sin(leg_a)) * 6.0, col, 1.2)
					"rabbit":
						draw_circle(c + Vector2(1.5, -4.0), 1.2, col)
						draw_circle(c + Vector2(-1.5, -4.0), 1.2, col)
				if a.carrying > 0:
					draw_circle(c + Vector2(5.0, -4.0), 2.5, Color(0.7, 0.75, 0.45))
			"hero":
				# Class-colored figure with a sword and level pips overhead.
				draw_circle(c, 5.0, HERO_COLORS.get(a.hero_class, Color(0.8, 0.8, 0.8)))
				draw_line(c + Vector2(3, 2), c + Vector2(-3, -6), Color(0.9, 0.9, 0.95), 1.5)
				if a.pouch > 0:
					draw_circle(c + Vector2(5.0, -5.0), 2.5, GOLD)
				for i in clampi(a.level, 0, 5):
					draw_circle(c + Vector2(-6 + i * 4, -9), 1.5, GOLD)
			_:
				draw_circle(c, 4.0, Color(0.85, 0.72, 0.55))
				if a.carrying > 0:
					draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.5, 0.7, 0.3))
				elif a.purpose == "build":
					draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.85, 0.65, 0.2))
