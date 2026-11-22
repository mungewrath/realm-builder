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
	4: Color(0.28, 0.35, 0.26),
}

const BUILDING_COLORS := {
	"castle": Color(0.72, 0.68, 0.58),
	"farm": Color(0.78, 0.62, 0.2),
	"house": Color(0.55, 0.3, 0.2),
	"guardhouse": Color(0.58, 0.6, 0.66),
	"tavern": Color(0.45, 0.3, 0.18),
	"market": Color(0.55, 0.42, 0.26),
	"shrine": Color(0.8, 0.78, 0.72),
	"blacksmith": Color(0.42, 0.38, 0.4),
	"wizard_tower": Color(0.45, 0.36, 0.62),
	"ranger_hut": Color(0.34, 0.46, 0.28),
	"mead_hall": Color(0.62, 0.45, 0.24),
	"herbalist_grove": Color(0.38, 0.62, 0.36),
	"graveyard": Color(0.36, 0.37, 0.35),
	"sewers": Color(0.3, 0.34, 0.31),
}

const HERO_COLORS := {
	"rogue": Color(0.55, 0.4, 0.65),
	"warrior": Color(0.75, 0.4, 0.3),
	"paladin": Color(0.9, 0.85, 0.55),
	"druid": Color(0.4, 0.7, 0.45),
	"dwarf": Color(0.65, 0.52, 0.36),
	"wizard": Color(0.45, 0.5, 0.85),
	"ranger": Color(0.42, 0.62, 0.32),
	"barbarian": Color(0.78, 0.38, 0.2),
	"necromancer": Color(0.38, 0.3, 0.5),
}

const GOLD := Color(0.92, 0.78, 0.2)
const FOG_DARK := Color(0.03, 0.04, 0.07)

# Terrain is baked in 16x16-tile chunks. Only chunks near the camera are kept,
# so texture memory tracks the view rather than the whole map — that is what
# lets a 5x map fit. Big worlds bake at 1x to keep the visible set small.
const CHUNK_TILES := 16
const CHUNK_CREATE_MARGIN := 1
const CHUNK_KEEP_MARGIN := 2

class TerrainPainter extends Node2D:
	var view
	var rect := Rect2i()
	func _draw() -> void:
		if view != null:
			view._paint_terrain(self, rect)

var world
var sim
var buildings := {}
var selected := Vector2i(-1, -1)

var _chunks := {}
var _bake_scale := 2.0
var _terrain_version := -1
var _fog_version := -1
var _fog_enabled := false
var _fog_texture: ImageTexture

# Placement preview: a translucent ghost of the selected building plus its
# one-tile padding ring. Green means the tile can be confirmed; red means
# blocked by terrain, fog, another structure, or the treasury.
var placement_kind := ""
var placement_tile := Vector2i(-1, -1)
var placement_valid := false

var _mouse_down := false
var _mouse_moved := false
var _last_screen := Vector2.ZERO
var _press_screen := Vector2.ZERO
var _touches := {}
var _tap_index := -1
var _tap_pos := Vector2.ZERO
var _tap_valid := false
var _pinch_start_dist := 0.0
var _pinch_start_scale := 1.0
var _pinch_anchor := Vector2.ZERO
var _pinch_world := Vector2.ZERO

func setup(w, sim_ref) -> void:
	world = w
	sim = sim_ref
	buildings = sim.buildings
	_bake_scale = 2.0 if world.SIZE_X <= 96 else 1.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	if world == null:
		return
	if world.version != _terrain_version:
		_terrain_version = world.version
		_dirty_all_chunks()
	_sync_chunks()
	if sim != null:
		var fv: int = sim.fog_version if sim.fog_enabled else -1
		if fv != _fog_version or sim.fog_enabled != _fog_enabled:
			_fog_version = fv
			_fog_enabled = sim.fog_enabled
			_rebuild_fog()
			queue_redraw()
	_update_chunk_bakes()

func _chunk_cols() -> int:
	return (world.SIZE_X + CHUNK_TILES - 1) / CHUNK_TILES

func _chunk_rows() -> int:
	return (world.SIZE_Y + CHUNK_TILES - 1) / CHUNK_TILES

func _sync_chunks() -> void:
	# Keep a small ring of baked chunks around the camera. Chunks are baked on
	# demand and dropped once far outside the view, so the working set stays
	# bounded no matter how large the map grows.
	var view := get_viewport_rect().size
	var a := to_local(Vector2.ZERO)
	var b := to_local(view)
	var min_px := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var max_px := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var chunk_px := float(TILE * CHUNK_TILES)
	var cols := _chunk_cols()
	var rows := _chunk_rows()
	var cmin := Vector2i(floori(min_px.x / chunk_px), floori(min_px.y / chunk_px))
	var cmax := Vector2i(floori(max_px.x / chunk_px), floori(max_px.y / chunk_px))
	var create_min := Vector2i(
		clampi(cmin.x - CHUNK_CREATE_MARGIN, 0, cols - 1),
		clampi(cmin.y - CHUNK_CREATE_MARGIN, 0, rows - 1))
	var create_max := Vector2i(
		clampi(cmax.x + CHUNK_CREATE_MARGIN, 0, cols - 1),
		clampi(cmax.y + CHUNK_CREATE_MARGIN, 0, rows - 1))
	for cy in range(create_min.y, create_max.y + 1):
		for cx in range(create_min.x, create_max.x + 1):
			var key := Vector2i(cx, cy)
			if not _chunks.has(key):
				_create_chunk(key)
	var drop := []
	for key in _chunks:
		if key.x < cmin.x - CHUNK_KEEP_MARGIN \
				or key.x > cmax.x + CHUNK_KEEP_MARGIN \
				or key.y < cmin.y - CHUNK_KEEP_MARGIN \
				or key.y > cmax.y + CHUNK_KEEP_MARGIN:
			drop.append(key)
	for key in drop:
		_free_chunk(key)

func _create_chunk(key: Vector2i) -> void:
	var chunk_px := CHUNK_TILES * TILE
	var vp := SubViewport.new()
	vp.size = Vector2i(int(chunk_px * _bake_scale),
		int(chunk_px * _bake_scale))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var painter := TerrainPainter.new()
	painter.view = self
	# One tile of overscan so decorations that overhang a tile (mountain
	# peaks) still bleed across the chunk seam instead of being clipped.
	painter.rect = Rect2i(key.x * CHUNK_TILES - 1, key.y * CHUNK_TILES - 1,
		CHUNK_TILES + 2, CHUNK_TILES + 2)
	painter.scale = Vector2(_bake_scale, _bake_scale)
	painter.position = -Vector2(key.x * chunk_px, key.y * chunk_px) * _bake_scale
	vp.add_child(painter)
	painter.queue_redraw()
	var sprite := Sprite2D.new()
	sprite.texture = vp.get_texture()
	sprite.centered = false
	sprite.position = Vector2(key.x * chunk_px, key.y * chunk_px)
	sprite.scale = Vector2(1.0 / _bake_scale, 1.0 / _bake_scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.show_behind_parent = true
	add_child(sprite)
	_chunks[key] = {"viewport": vp, "painter": painter, "sprite": sprite,
		"frames": 2}

func _free_chunk(key: Vector2i) -> void:
	var ch = _chunks.get(key)
	if ch == null:
		return
	ch.sprite.queue_free()
	ch.viewport.queue_free()
	_chunks.erase(key)

func _dirty_all_chunks() -> void:
	for key in _chunks:
		var ch = _chunks[key]
		ch.painter.queue_redraw()
		ch.frames = 2

func _update_chunk_bakes() -> void:
	for key in _chunks:
		var ch = _chunks[key]
		if ch.frames > 0:
			ch.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			ch.frames -= 1
		elif ch.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			ch.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _rebuild_fog() -> void:
	if world == null or sim == null:
		_fog_texture = null
		return
	var w: int = world.SIZE_X
	var h: int = world.SIZE_Y
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var r := int(roundf(FOG_DARK.r * 255.0))
	var g := int(roundf(FOG_DARK.g * 255.0))
	var b := int(roundf(FOG_DARK.b * 255.0))
	var fog_on: bool = sim.fog_enabled
	for y in h:
		for x in w:
			var a := 0
			if fog_on and sim.explored[y * w + x] == 0:
				a = int(roundf(_fog_alpha(Vector2i(x, y)) * 255.0))
			var i: int = (y * w + x) * 4
			data[i] = r
			data[i + 1] = g
			data[i + 2] = b
			data[i + 3] = a
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	_fog_texture = ImageTexture.create_from_image(img)

func set_placement(kind: String, p: Vector2i, valid: bool) -> void:
	placement_kind = kind
	placement_tile = p
	placement_valid = valid
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
			_begin_pinch()
	else:
		_touches.erase(event.index)
		if _touches.size() >= 2:
			_begin_pinch()
		else:
			_pinch_start_dist = 0.0
		if _touches.is_empty() and _tap_valid and event.index == _tap_index:
			_tap(_tap_pos)

func _begin_pinch() -> void:
	# Pin the world point under the pinch start. Scaling about this fixed
	# screen point means a pinch can never translate the view, so no drift
	# can build up from the fingers' midpoint wandering.
	_pinch_anchor = _pinch_midpoint()
	_pinch_start_dist = _pinch_distance()
	_pinch_start_scale = scale.x
	_pinch_world = to_local(_pinch_anchor)

func _handle_drag(event: InputEventScreenDrag) -> void:
	var old: Vector2 = _touches.get(event.index, event.position)
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		var d := _pinch_distance()
		if _pinch_start_dist > 0.0 and d > 0.0:
			var s: float = clampf(_pinch_start_scale * (d / _pinch_start_dist),
				MIN_SCALE, MAX_SCALE)
			scale = Vector2(s, s)
			position = _pinch_anchor - _pinch_world * s
			_clamp_position()
	else:
		_tap_valid = false
		_pan(event.position - old)

func _tap(screen_pos: Vector2) -> void:
	var local := to_local(screen_pos)
	var p := Vector2i(floori(local.x / TILE), floori(local.y / TILE))
	if world.in_bounds(p):
		tile_clicked.emit(p)

func _pan(screen_delta: Vector2) -> void:
	position += screen_delta
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

func _pinch_midpoint() -> Vector2:
	var pts := _touches.values()
	if pts.size() < 2:
		return Vector2.ZERO
	return (pts[0] + pts[1]) / 2.0

func _hash(x: int, y: int, n: int) -> float:
	return fposmod(float((x * 73856093) ^ (y * 19349663) ^ (n * 83492791)) / 1000.0, 1.0)

func _paint_terrain(c: CanvasItem, rect: Rect2i) -> void:
	# Baked per visible chunk; only the decorations that change (works,
	# buildings, dens, agents) are redrawn by the main view each frame.
	var x0 := maxi(rect.position.x, 0)
	var y0 := maxi(rect.position.y, 0)
	var x1 := mini(rect.end.x, world.SIZE_X)
	var y1 := mini(rect.end.y, world.SIZE_Y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var t: int = world.tiles[y * world.SIZE_X + x]
			var origin := Vector2(x * TILE, y * TILE)
			c.draw_rect(Rect2(origin, Vector2(TILE - 1, TILE - 1)), TERRAIN_COLORS[t])
			match t:
				0:
					_draw_grass(c, origin, x, y)
				1:
					_draw_forest(c, origin, x, y)
				2:
					_draw_water(c, origin, x, y)
				3:
					_draw_mountain(c, origin, x, y)
				4:
					_draw_swamp(c, origin, x, y)

func _draw() -> void:
	if world == null:
		return
	# M5 fog: a per-tile texture (one pixel per tile) rebuilt only when the
	# explored layer changes, so the veil costs a single quad per frame.
	if _fog_texture != null:
		draw_texture_rect(_fog_texture,
			Rect2(Vector2.ZERO, Vector2(world.SIZE_X, world.SIZE_Y) * TILE), false)
	if sim != null and sim.get("terrain_works") != null:
		for p in sim.terrain_works:
			if _fog_level(p) > 0:
				_draw_terrain_work(p, sim.terrain_works[p])
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
	if sim != null and sim.get("explore_bounties") != null:
		for p in sim.explore_bounties:
			_draw_explore_bounty_flag(p)
	if sim != null:
		_draw_agents()
	_draw_placement()
	if selected.x >= 0:
		var sel_rect := Rect2i(selected, Vector2i.ONE)
		if sim != null:
			var origin: Vector2i = sim.building_origin_at(selected)
			if origin.x >= 0:
				sel_rect = sim.building_rect(origin, sim.buildings[origin].kind)
		draw_rect(Rect2(Vector2(sel_rect.position * TILE),
			Vector2(sel_rect.size * TILE) - Vector2(1, 1)),
			Color(0.95, 0.8, 0.3), false, 2.0)

func _draw_placement() -> void:
	if placement_kind == "" or placement_tile.x < 0:
		return
	var rect: Rect2i = sim.building_rect(placement_tile, placement_kind) \
		if sim != null else Rect2i(placement_tile, Vector2i.ONE)
	var origin := Vector2(rect.position * TILE)
	var footprint := Vector2(rect.size * TILE)
	var tint := Color(0.35, 0.95, 0.45) if placement_valid \
		else Color(1.0, 0.28, 0.22)
	# Outline the footprint plus the required one-tile breathing room, with
	# small cut corners so the ghost reads as a placement card, not a slab.
	var pad_origin := origin - Vector2(TILE, TILE)
	var pad_size := footprint + Vector2(TILE * 2, TILE * 2)
	var pad_points := _beveled_rect(Rect2(pad_origin, pad_size), 6.0)
	draw_colored_polygon(pad_points, Color(tint.r, tint.g, tint.b, 0.12))
	_draw_closed_polyline(pad_points, Color(tint.r, tint.g, tint.b, 0.65))
	_draw_building(placement_tile, {"kind": placement_kind, "complete": true})
	var fill_points := _beveled_rect(
		Rect2(origin, footprint - Vector2(1, 1)), 4.0)
	draw_colored_polygon(fill_points, Color(tint.r, tint.g, tint.b, 0.38))
	var edge_points := _beveled_rect(
		Rect2(origin + Vector2(1, 1), footprint - Vector2(3, 3)), 3.0)
	_draw_closed_polyline(edge_points, tint)

func _beveled_rect(rect: Rect2, bevel: float) -> PackedVector2Array:
	var b: float = minf(bevel, minf(rect.size.x, rect.size.y) * 0.5)
	var right: float = rect.position.x + rect.size.x
	var bottom: float = rect.position.y + rect.size.y
	return PackedVector2Array([
		Vector2(rect.position.x + b, rect.position.y),
		Vector2(right - b, rect.position.y),
		Vector2(right, rect.position.y + b),
		Vector2(right, bottom - b),
		Vector2(right - b, bottom),
		Vector2(rect.position.x + b, bottom),
		Vector2(rect.position.x, bottom - b),
		Vector2(rect.position.x, rect.position.y + b),
	])

func _draw_closed_polyline(points: PackedVector2Array, color: Color) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, 2.0, true)

func _fog_level(p: Vector2i) -> int:
	# 0 unseen, 2 revealed (revealed ground stays lit permanently).
	# Fog off (dev) is level 2 everywhere.
	if sim == null or not sim.fog_enabled:
		return 2
	if not world.in_bounds(p):
		return 0
	return 2 if sim.explored[p.y * world.SIZE_X + p.x] == 1 else 0

func _fog_alpha(p: Vector2i) -> float:
	# Unseen ground is fully opaque; only tiles bordering charted land get a
	# lighter veil, so the frontier reads soft without leaking terrain.
	var best := 0
	for d in world.DIRS_ALL:
		best = maxi(best, _fog_level(p + d))
	return 0.75 if best == 2 else 1.0

func center_on(p: Vector2i) -> void:
	# Minimap jumps land the tapped tile in the middle of the viewport.
	var view := get_viewport_rect().size
	position = view / 2.0 - (Vector2(p) + Vector2(0.5, 0.5)) * TILE * scale.x
	_clamp_position()

func _draw_grass(c: CanvasItem, origin: Vector2, x: int, y: int) -> void:
	var dark := Color(0.28, 0.46, 0.2)
	for n in 2:
		var px := origin + Vector2(_hash(x, y, n) * (TILE - 8) + 4, _hash(x, y, n + 10) * (TILE - 8) + 4)
		c.draw_rect(Rect2(px, Vector2(2, 4)), dark)

func _draw_forest(c: CanvasItem, origin: Vector2, x: int, y: int) -> void:
	for n in 3:
		var px := origin + Vector2(_hash(x, y, n) * (TILE - 12) + 4, _hash(x, y, n + 5) * (TILE - 14) + 6)
		c.draw_rect(Rect2(px + Vector2(2, 8), Vector2(2, 4)), Color(0.3, 0.2, 0.1))
		var crown := PackedVector2Array([
			px + Vector2(3, 0), px + Vector2(-1, 8), px + Vector2(7, 8),
		])
		c.draw_colored_polygon(crown, Color(0.3, 0.5, 0.22))

func _draw_swamp(c: CanvasItem, origin: Vector2, x: int, y: int) -> void:
	# Wet ground: dark pools and a few reed tufts.
	for n in 2:
		var px := origin + Vector2(_hash(x, y, n + 20) * (TILE - 12) + 4, _hash(x, y, n + 30) * (TILE - 12) + 6)
		c.draw_circle(px, 4.0, Color(0.16, 0.26, 0.2))
	for n in 3:
		var rx := origin + Vector2(_hash(x, y, n + 40) * (TILE - 8) + 4, _hash(x, y, n + 50) * (TILE - 14) + 12)
		c.draw_line(rx, rx + Vector2(0, -7), Color(0.4, 0.52, 0.32), 1.4)

func _draw_water(c: CanvasItem, origin: Vector2, x: int, y: int) -> void:
	var light := Color(0.3, 0.48, 0.7)
	for n in 2:
		var py := origin + Vector2(4 + _hash(x, y, n) * 8, 8 + n * 10)
		c.draw_line(py, py + Vector2(10 + _hash(x, y, n + 3) * 8, 0), light, 2.0)

func _draw_mountain(c: CanvasItem, origin: Vector2, x: int, y: int) -> void:
	var base := Vector2(origin.x + TILE / 2.0, origin.y + TILE - 4)
	var peak := PackedVector2Array([
		base + Vector2(0, -22), base + Vector2(-11, 0), base + Vector2(11, 0),
	])
	c.draw_colored_polygon(peak, Color(0.36, 0.34, 0.33))
	var cap := PackedVector2Array([
		base + Vector2(0, -22), base + Vector2(-4, -14), base + Vector2(4, -14),
	])
	c.draw_colored_polygon(cap, Color(0.85, 0.85, 0.85))

func _draw_building(p: Vector2i, b: Dictionary) -> void:
	var kind: String = b.kind
	if not b.complete:
		_draw_site(p, kind)
		return
	var rect: Rect2i = sim.building_rect(p, kind) if sim != null \
		else Rect2i(p, Vector2i.ONE)
	var origin := Vector2(rect.position * TILE)
	var w := float(rect.size.x * TILE)
	var h := float(rect.size.y * TILE)
	match kind:
		"farm":
			draw_rect(Rect2(origin + Vector2(4, 10), Vector2(w - 8, h - 16)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(4, 14), Vector2(w - 8, 3)), Color(0.55, 0.75, 0.3))
			draw_rect(Rect2(origin + Vector2(4, 20), Vector2(w - 8, 3)), Color(0.55, 0.75, 0.3))
		"house":
			draw_rect(Rect2(origin + Vector2(6, 14), Vector2(w - 12, h - 18)), BUILDING_COLORS[kind])
			var roof := PackedVector2Array([
				origin + Vector2(w / 2.0, 4), origin + Vector2(4, 15), origin + Vector2(w - 4, 15),
			])
			draw_colored_polygon(roof, Color(0.35, 0.18, 0.12))
		"castle":
			# A walled keep: corner towers, crenellations, a central hall and
			# a gate wide enough for the realm's folk.
			draw_rect(Rect2(origin + Vector2(4, 4), Vector2(w - 8, h - 8)), BUILDING_COLORS[kind])
			for n in 7:
				draw_rect(Rect2(origin + Vector2(6 + n * 12, 0), Vector2(7, 8)), BUILDING_COLORS[kind])
			for corner in [Vector2(4, 4), Vector2(w - 22, 4), Vector2(4, h - 22), Vector2(w - 22, h - 22)]:
				draw_rect(Rect2(origin + corner, Vector2(18, 18)), Color(0.64, 0.6, 0.5))
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 16, h / 2.0 - 18), Vector2(32, 34)),
				Color(0.66, 0.62, 0.53))
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 11, h - 28), Vector2(22, 26)),
				Color(0.25, 0.22, 0.2))
			var pole := origin + Vector2(w / 2.0, h / 2.0 - 18)
			draw_line(pole, pole + Vector2(0, -22), Color(0.2, 0.2, 0.2), 2.0)
			var flag := PackedVector2Array([
				pole + Vector2(0, -22), pole + Vector2(10, -18), pole + Vector2(0, -14),
			])
			draw_colored_polygon(flag, Color(0.75, 0.2, 0.2))
		"guardhouse":
			# Stone watchtower and a short wall, with a pale-blue banner.
			draw_rect(Rect2(origin + Vector2(4, 12), Vector2(w - 8, h - 16)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(8, 6), Vector2(24, h - 10)), BUILDING_COLORS[kind])
			for n in 3:
				draw_rect(Rect2(origin + Vector2(9 + n * 8, 2), Vector2(5, 6)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(17, h - 15), Vector2(7, h - 17)),
				Color(0.3, 0.3, 0.34))
			var pole := origin + Vector2(w - 14, 10)
			draw_line(pole, pole + Vector2(0, -14), Color(0.2, 0.2, 0.2), 2.0)
			var pennant := PackedVector2Array([
				pole + Vector2(0, -14), pole + Vector2(9, -11), pole + Vector2(0, -8),
			])
			draw_colored_polygon(pennant, Color(0.45, 0.6, 0.85))
		"tavern":
			# Timber hall with a pitched roof and a hanging ale sign.
			draw_rect(Rect2(origin + Vector2(4, 14), Vector2(w - 8, h - 18)), BUILDING_COLORS[kind])
			var roof := PackedVector2Array([
				origin + Vector2(w / 2.0, 2), origin + Vector2(2, 15), origin + Vector2(w - 2, 15),
			])
			draw_colored_polygon(roof, Color(0.3, 0.2, 0.12))
			draw_line(origin + Vector2(6, 10), origin + Vector2(14, 10), Color(0.25, 0.18, 0.12), 2.0)
			draw_rect(Rect2(origin + Vector2(w - 23, 8), Vector2(6, 8)), GOLD)
			draw_rect(Rect2(origin + Vector2(w - 22, 16), Vector2(3, 3)), Color(0.85, 0.85, 0.85))
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 5, h - 15), Vector2(10, 13)),
				Color(0.32, 0.21, 0.13))
		"market":
			# A wider stall with a striped awning and coin scale.
			draw_rect(Rect2(origin + Vector2(5, 15), Vector2(w - 10, h - 19)), BUILDING_COLORS[kind])
			for n in int(w / 7.0):
				var stripe := Color(0.85, 0.25, 0.2) if n % 2 == 0 else Color(0.92, 0.88, 0.8)
				draw_rect(Rect2(origin + Vector2(3 + n * 7, 8), Vector2(7, 6)), stripe)
			draw_circle(origin + Vector2(w / 2.0, h - 10), 3.0, GOLD)
		"shrine":
			# Pale stone altar with a burning light, approached by wide steps.
			draw_rect(Rect2(origin + Vector2(4, h - 11), Vector2(w - 8, 7)), Color(0.7, 0.68, 0.62))
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 12, 13), Vector2(24, h - 23)),
				BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 4, 8), Vector2(8, 9)), Color(0.92, 0.9, 0.84))
			draw_circle(origin + Vector2(w / 2.0, 9), 3.5, GOLD)
		"blacksmith":
			# Squat forge with a hot orange mouth and a smoking chimney.
			draw_rect(Rect2(origin + Vector2(4, 12), Vector2(w - 8, h - 16)), BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 8, 17), Vector2(16, 8)),
				Color(0.95, 0.48, 0.16))
			draw_rect(Rect2(origin + Vector2(w - 18, 2), Vector2(6, 13)), Color(0.28, 0.26, 0.28))
			draw_circle(origin + Vector2(w - 15, 1), 3.5, Color(0.4, 0.4, 0.42, 0.7))
			draw_rect(Rect2(origin + Vector2(8, h - 11), Vector2(12, 5)), Color(0.34, 0.32, 0.34))
		"wizard_tower":
			# Tall violet spire with a glowing star, now two tiles deep.
			draw_rect(Rect2(origin + Vector2(9, 22), Vector2(w - 18, h - 28)), BUILDING_COLORS[kind])
			var spire := PackedVector2Array([
				origin + Vector2(w / 2.0, 0), origin + Vector2(6, 24), origin + Vector2(w - 6, 24),
			])
			draw_colored_polygon(spire, Color(0.32, 0.26, 0.48))
			draw_circle(origin + Vector2(w / 2.0, 34), 3.0, Color(0.9, 0.85, 0.95))
			draw_rect(Rect2(origin + Vector2(w / 2.0 - 4, h - 19), Vector2(8, 15)),
				Color(0.25, 0.2, 0.36))
		"ranger_hut":
			# Low cabin with a small bow-and-leaf mark.
			draw_rect(Rect2(origin + Vector2(5, 15), Vector2(w - 10, h - 19)), BUILDING_COLORS[kind])
			var thatch := PackedVector2Array([
				origin + Vector2(w / 2.0, 5), origin + Vector2(3, 17), origin + Vector2(w - 3, 17),
			])
			draw_colored_polygon(thatch, Color(0.34, 0.3, 0.16))
			draw_line(origin + Vector2(w - 14, 9), origin + Vector2(w - 8, 3), Color(0.55, 0.4, 0.2), 1.5)
			draw_circle(origin + Vector2(9, 10), 2.4, Color(0.45, 0.72, 0.35))
		"mead_hall":
			# Longhouse with horns over the door.
			draw_rect(Rect2(origin + Vector2(3, 14), Vector2(w - 6, h - 18)), BUILDING_COLORS[kind])
			var long_roof := PackedVector2Array([
				origin + Vector2(4, 15), origin + Vector2(w / 2.0, 3), origin + Vector2(w - 4, 15),
			])
			draw_colored_polygon(long_roof, Color(0.38, 0.25, 0.14))
			draw_line(origin + Vector2(9, 18), origin + Vector2(14, 14), Color(0.9, 0.85, 0.7), 2.0)
			draw_line(origin + Vector2(w - 9, 18), origin + Vector2(w - 14, 14), Color(0.9, 0.85, 0.7), 2.0)
		"herbalist_grove":
			# A wide green hut ringed by herb rows and two little trees.
			var hut_x := w / 2.0 - 13
			draw_rect(Rect2(origin + Vector2(hut_x, 30), Vector2(26, h - 35)), BUILDING_COLORS[kind])
			var grove_roof := PackedVector2Array([
				origin + Vector2(w / 2.0, 12), origin + Vector2(hut_x - 5, 32),
				origin + Vector2(hut_x + 31, 32),
			])
			draw_colored_polygon(grove_roof, Color(0.2, 0.4, 0.2))
			for n in 4:
				draw_circle(origin + Vector2(8 + n * 16, h - 8), 2.2, Color(0.55, 0.8, 0.4))
			draw_circle(origin + Vector2(10, 16), 7.0, Color(0.22, 0.42, 0.2))
			draw_rect(Rect2(origin + Vector2(9, 22), Vector2(2, 8)), Color(0.3, 0.2, 0.1))
			draw_circle(origin + Vector2(w - 10, 16), 7.0, Color(0.22, 0.42, 0.2))
			draw_rect(Rect2(origin + Vector2(w - 11, 22), Vector2(2, 8)), Color(0.3, 0.2, 0.1))
		"graveyard":
			# Dark consecrated ground, an iron rail and a row of leaning stones.
			draw_rect(Rect2(origin + Vector2(5, 8), Vector2(w - 10, h - 12)),
				Color(0.24, 0.27, 0.22))
			for n in 3:
				draw_line(origin + Vector2(8 + n * 18, 6),
					origin + Vector2(8 + n * 18, h - 4),
					Color(0.22, 0.2, 0.18), 1.4)
			draw_line(origin + Vector2(5, 7), origin + Vector2(w - 5, 7),
				Color(0.22, 0.2, 0.18), 1.4)
			for n in 4:
				var stone := origin + Vector2(16 + (n % 2) * 25, 24 + int(n / 2.0) * 22)
				draw_rect(Rect2(stone, Vector2(8, 15)), Color(0.62, 0.61, 0.55))
				draw_circle(stone + Vector2(4, 0), 4.0, Color(0.62, 0.61, 0.55))
				draw_line(stone + Vector2(4, 5), stone + Vector2(4, 11),
					Color(0.42, 0.42, 0.38), 1.2)
		"sewers":
			# A stone culvert and iron grate with a thin green trickle.
			draw_rect(Rect2(origin + Vector2(5, 9), Vector2(w - 10, h - 15)),
				BUILDING_COLORS[kind])
			draw_rect(Rect2(origin + Vector2(9, 13), Vector2(w - 18, h - 22)),
				Color(0.12, 0.15, 0.13))
			for n in 3:
				draw_line(origin + Vector2(11 + n * 8, 13),
					origin + Vector2(11 + n * 8, h - 9),
					Color(0.4, 0.44, 0.4), 1.5)
			draw_line(origin + Vector2(9, h - 10),
				origin + Vector2(w - 9, h - 10), Color(0.36, 0.55, 0.3), 2.0)

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
	elif kind_key == "frog_den":
		_draw_frog_pond(p)
	elif kind_key == "owlbear_den":
		_draw_owlbear_den(p)
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

func _draw_explore_bounty_flag(p: Vector2i) -> void:
	# This flag must read through fog: it marks ground the realm cannot see.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var center := origin + Vector2(TILE / 2.0, TILE / 2.0)
	draw_circle(center, 11.0, Color(0.95, 0.8, 0.3, 0.16))
	draw_arc(center, 11.0, 0.0, TAU, 24, Color(0.95, 0.8, 0.3, 0.8), 1.5, true)
	var pole := center + Vector2(1, 9)
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

func _draw_frog_pond(p: Vector2i) -> void:
	# A reedy pool with lily pads and a couple of bright eyes.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var hub := origin + Vector2(TILE / 2.0, TILE - 10)
	draw_circle(hub, 9.0, Color(0.16, 0.3, 0.24))
	draw_circle(hub + Vector2(-3, 0), 3.0, Color(0.3, 0.5, 0.3))
	draw_circle(hub + Vector2(4, 2), 2.0, Color(0.3, 0.5, 0.3))
	var eyes := hub + Vector2(0, -4)
	draw_circle(eyes + Vector2(-2, 0), 1.2, Color(0.9, 0.85, 0.35))
	draw_circle(eyes + Vector2(2, 0), 1.2, Color(0.9, 0.85, 0.35))
	for n in 2:
		var rx := origin + Vector2(6 + n * 17, TILE - 20 + n * 4)
		draw_line(rx, rx + Vector2(0, -8), Color(0.4, 0.52, 0.32), 1.4)

func _draw_owlbear_den(p: Vector2i) -> void:
	# A trampled hollow ringed with feathers and old bones.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var hollow := origin + Vector2(TILE / 2.0, TILE - 7)
	draw_circle(hollow, 10.0, Color(0.25, 0.22, 0.16))
	draw_circle(hollow + Vector2(0, 2), 6.5, Color(0.07, 0.06, 0.05))
	draw_line(hollow + Vector2(-7, -5), hollow + Vector2(-2, -9), Color(0.72, 0.64, 0.48), 2.0)
	draw_line(hollow + Vector2(7, -4), hollow + Vector2(3, -8), Color(0.72, 0.64, 0.48), 2.0)
	draw_circle(origin + Vector2(9, 11), 1.8, Color(0.85, 0.82, 0.7))

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

func _draw_terrain_work(p: Vector2i, work: Dictionary) -> void:
	# Staked-out ground: outline plus a progress bar, wet-blue for draining
	# and timber-brown for felling.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	var col := Color(0.35, 0.58, 0.55) if work.kind == "drain" \
		else Color(0.52, 0.36, 0.2)
	draw_rect(Rect2(origin + Vector2(4, 4), Vector2(TILE - 8, TILE - 8)),
		col, false, 1.5)
	draw_line(origin + Vector2(8, TILE - 14), origin + Vector2(TILE - 12, 8),
		col, 2.0)
	draw_line(origin + Vector2(8, 8), origin + Vector2(TILE - 12, TILE - 14),
		col, 1.0)
	var frac: float = clampf(float(work.progress) / float(sim.TERRAIN_WORK_TICKS),
		0.0, 1.0)
	draw_rect(Rect2(origin + Vector2(6, TILE - 7),
		Vector2((TILE - 12) * frac, 3)), col)

func _draw_loot_pile(p: Vector2i) -> void:
	# A spilled purse: a little heap of coins on the ground.
	var origin := Vector2(p.x * TILE, p.y * TILE)
	for i in 4:
		draw_circle(origin + Vector2(9 + (i % 2) * 7, 19 - int(i / 2.0) * 5), 2.5, GOLD)
	draw_circle(origin + Vector2(12, 17), 2.0, Color(0.75, 0.6, 0.12))

func _draw_site(p: Vector2i, kind: String) -> void:
	var rect: Rect2i = sim.building_rect(p, kind) if sim != null \
		else Rect2i(p, Vector2i.ONE)
	var origin := Vector2(rect.position * TILE)
	var w := float(rect.size.x * TILE)
	var h := float(rect.size.y * TILE)
	var frame := Color(0.5, 0.37, 0.22)
	draw_rect(Rect2(origin + Vector2(4, 9), Vector2(w - 8, h - 13)), frame, false, 2.0)
	draw_line(origin + Vector2(7, 11), origin + Vector2(w - 7, h - 6), frame, 2.0)
	draw_line(origin + Vector2(w - 7, 11), origin + Vector2(7, h - 6), frame, 2.0)
	var pole := origin + Vector2(w / 2.0, 8)
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
		if (a.kind == "goblin" or a.kind == "creature" or a.kind == "bandit" \
				or a.kind == "rat" \
				or (a.kind == "undead" and a.undead_side == "hostile")) \
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
			"undead":
				# Bone-pale servants have a faint loyal glint; hostile dead
				# burn with a red eye and a darker shroud.
				var ally: bool = a.undead_side == "ally"
				draw_circle(c, 5.4, Color(0.12, 0.12, 0.11))
				draw_circle(c, 4.4, Color(0.67, 0.72, 0.64) if ally \
					else Color(0.42, 0.46, 0.4))
				draw_circle(c + Vector2(-1.6, -1.0), 1.0,
					Color(0.45, 0.7, 0.85) if ally else Color(0.9, 0.2, 0.1))
				draw_circle(c + Vector2(1.6, -1.0), 1.0,
					Color(0.45, 0.7, 0.85) if ally else Color(0.9, 0.2, 0.1))
				draw_line(c + Vector2(-2, 2), c + Vector2(-4, 5),
					Color(0.5, 0.5, 0.45), 1.2)
				draw_line(c + Vector2(2, 2), c + Vector2(4, 5),
					Color(0.5, 0.5, 0.45), 1.2)
			"rat":
				draw_circle(c, 3.6, Color(0.34, 0.32, 0.3))
				draw_circle(c + Vector2(2.5, -1.2), 1.6, Color(0.42, 0.4, 0.37))
				draw_line(c + Vector2(-3, 1), c + Vector2(-7, 3),
					Color(0.45, 0.4, 0.37), 1.1)
				draw_circle(c + Vector2(3.4, -1.7), 0.7, Color(0.9, 0.2, 0.1))
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
				for i in clampi(int(a.gear), 0, 4):
					draw_circle(c + Vector2(-6 + i * 4, -13), 1.5,
						Color(0.72, 0.8, 0.9))
			_:
				draw_circle(c, 4.0, Color(0.85, 0.72, 0.55))
				if a.carrying > 0:
					draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.5, 0.7, 0.3))
				elif a.purpose == "build":
					draw_circle(c + Vector2(0.0, -7.0), 3.0, Color(0.85, 0.65, 0.2))
