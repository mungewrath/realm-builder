extends Control

# M5 minimap: the whole map in miniature, showing only what the realm has
# charted. Reads sim fog state directly (view reads sim state, no logic);
# tapping it jumps the main map view.

signal tile_jump(p: Vector2i)

const TERRAIN_COLORS := {
	0: Color(0.36, 0.55, 0.25),
	1: Color(0.2, 0.38, 0.18),
	2: Color(0.18, 0.34, 0.58),
	3: Color(0.5, 0.48, 0.46),
	4: Color(0.28, 0.35, 0.26),
}
const UNCHARTED := Color(0.05, 0.06, 0.09)
const GOLD := Color(0.92, 0.78, 0.2)

var world
var sim
var map_view: Node2D

var _px := 3.0 # pixels per tile, shrinks so a huge map still fits the corner
var _terrain_version := -1
var _explored_view := PackedByteArray()
var _map_texture: ImageTexture

func setup(w, sim_ref, view_ref: Node2D) -> void:
	world = w
	sim = sim_ref
	map_view = view_ref
	_px = clampf(288.0 / float(w.SIZE_X), 1.0, 3.0)
	custom_minimum_size = Vector2(w.SIZE_X * _px, w.SIZE_Y * _px)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if map_view != null and map_view.has_signal("fog_revealed"):
		map_view.fog_revealed.connect(_on_fog_revealed)
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	if world == null or sim == null:
		return
	if world.version != _terrain_version:
		_terrain_version = world.version
		_rebuild_map_texture()
		queue_redraw()

func _on_fog_revealed() -> void:
	_explored_view = sim.explored.duplicate()
	queue_redraw()

func _explored_at(i: int) -> bool:
	if _explored_view.size() > i:
		return _explored_view[i] == 1
	return sim.explored[i] == 1

func _rebuild_map_texture() -> void:
	var w: int = world.SIZE_X
	var h: int = world.SIZE_Y
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		var col: Color = TERRAIN_COLORS[world.tiles[i]]
		var j: int = i * 4
		data[j] = int(roundf(col.r * 255.0))
		data[j + 1] = int(roundf(col.g * 255.0))
		data[j + 2] = int(roundf(col.b * 255.0))
		data[j + 3] = 255
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if _map_texture == null or _map_texture.get_width() != w \
			or _map_texture.get_height() != h:
		_map_texture = ImageTexture.create_from_image(img)
	else:
		_map_texture.update(img)

func _gui_input(event: InputEvent) -> void:
	if world == null or map_view == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var p := Vector2i(floori(event.position.x / _px), floori(event.position.y / _px))
		if world.in_bounds(p):
			tile_jump.emit(p)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		var p := Vector2i(floori(event.position.x / _px), floori(event.position.y / _px))
		if world.in_bounds(p):
			tile_jump.emit(p)
		accept_event()

func _draw() -> void:
	if world == null or sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), UNCHARTED)
	if _map_texture != null:
		draw_texture_rect(_map_texture, Rect2(Vector2.ZERO, size), false)
	if sim.fog_enabled and map_view != null and map_view.has_method("fog_texture"):
		var fog_tex = map_view.fog_texture()
		if fog_tex != null:
			draw_texture_rect(fog_tex, Rect2(Vector2.ZERO, size), false, UNCHARTED)
	var buildings: Dictionary = sim.buildings
	for p in buildings:
		var kind: String = buildings[p].kind
		var col := Color(0.2, 0.2, 0.2)
		if kind == "castle":
			col = GOLD
		for q in sim.building_tiles(p, kind):
			if sim.fog_enabled and not _explored_at(q.y * world.SIZE_X + q.x):
				continue
			draw_rect(Rect2(Vector2(q) * _px, Vector2(_px, _px)), col)
	if sim.get("dens") != null:
		for p in sim.dens:
			# Landmarks appear on the minimap only once charted. Hostile
			# dens burn red; wild lairs read as earthy ground.
			if sim.fog_enabled and not _explored_at(p.y * world.SIZE_X + p.x):
				continue
			var hostile: bool = sim.DEN_KINDS[sim.dens[p].get("kind", "goblin_den")].hostile
			draw_rect(Rect2(Vector2(p) * _px, Vector2(_px, _px)),
				Color(0.7, 0.15, 0.12) if hostile else Color(0.5, 0.4, 0.24))
	for a in sim.agents:
		if a.kind == "goblin" or a.kind == "creature" or a.kind == "bandit" \
				or a.kind == "rat" \
				or (a.kind == "undead" and a.undead_side == "hostile"):
			continue
		if a.kind == "peasant":
			continue # too many dots; the realm folk live where you can see
		var col := Color(0.45, 0.55, 0.7)
		if a.kind == "hero":
			col = Color(0.95, 0.95, 0.95)
		elif a.kind == "undead":
			col = Color(0.62, 0.76, 0.7)
		draw_rect(Rect2(Vector2(a.tile()) * _px, Vector2(_px, _px)), col)
	# Viewport outline, in tile space.
	if map_view != null:
		var vp := get_viewport_rect().size
		var tl: Vector2 = map_view.to_local(Vector2.ZERO)
		var br: Vector2 = map_view.to_local(vp)
		var r := Rect2(tl / map_view.TILE * _px, (br - tl) / map_view.TILE * _px)
		draw_rect(r, Color(1.0, 0.95, 0.6, 0.9), false, 1.0)
