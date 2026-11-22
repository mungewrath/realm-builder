extends Control

# M5 minimap: the whole map in miniature, showing only what the realm has
# charted. Reads sim fog state directly (view reads sim state, no logic);
# tapping it jumps the main map view.

signal tile_jump(p: Vector2i)

const PX := 3.0 # pixels per tile
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

func setup(w, sim_ref, view_ref: Node2D) -> void:
	world = w
	sim = sim_ref
	map_view = view_ref
	custom_minimum_size = Vector2(w.SIZE_X * PX, w.SIZE_Y * PX)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if world == null or map_view == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var p := Vector2i(floori(event.position.x / PX), floori(event.position.y / PX))
		if world.in_bounds(p):
			tile_jump.emit(p)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		var p := Vector2i(floori(event.position.x / PX), floori(event.position.y / PX))
		if world.in_bounds(p):
			tile_jump.emit(p)
		accept_event()

func _draw() -> void:
	if world == null or sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), UNCHARTED)
	for x in world.SIZE_X:
		for y in world.SIZE_Y:
			var i: int = y * world.SIZE_X + x
			if sim.fog_enabled and sim.explored[i] == 0:
				continue
			var t: int = world.tiles[i]
			draw_rect(Rect2(Vector2(x * PX, y * PX), Vector2(PX, PX)), TERRAIN_COLORS[t])
	var buildings: Dictionary = sim.buildings
	for p in buildings:
		var kind: String = buildings[p].kind
		var col := Color(0.2, 0.2, 0.2)
		if kind == "castle":
			col = GOLD
		for q in sim.building_tiles(p, kind):
			if sim.fog_enabled and sim.explored[q.y * world.SIZE_X + q.x] == 0:
				continue
			draw_rect(Rect2(Vector2(q) * PX, Vector2(PX, PX)), col)
	if sim.get("dens") != null:
		for p in sim.dens:
			# Landmarks appear on the minimap only once charted. Hostile
			# dens burn red; wild lairs read as earthy ground.
			if sim.fog_enabled and sim.explored[p.y * world.SIZE_X + p.x] == 0:
				continue
			var hostile: bool = sim.DEN_KINDS[sim.dens[p].get("kind", "goblin_den")].hostile
			draw_rect(Rect2(Vector2(p) * PX, Vector2(PX, PX)),
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
		draw_rect(Rect2(Vector2(a.tile()) * PX, Vector2(PX, PX)), col)
	# Viewport outline, in tile space.
	if map_view != null:
		var vp := get_viewport_rect().size
		var tl: Vector2 = map_view.to_local(Vector2.ZERO)
		var br: Vector2 = map_view.to_local(vp)
		var r := Rect2(tl / map_view.TILE * PX, (br - tl) / map_view.TILE * PX)
		draw_rect(r, Color(1.0, 0.95, 0.6, 0.9), false, 1.0)
