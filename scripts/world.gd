const GRASS := 0
const FOREST := 1
const WATER := 2
const MOUNTAIN := 3
const SWAMP := 4

const SIZE_X := 48
const SIZE_Y := 32

# Each type should end up near a third of the open land.
const FOREST_BLOBS := 9
const FOREST_BLOB_SIZE := 48
const SWAMP_BLOBS := 9
const SWAMP_BLOB_SIZE := 48

const DIRS_ALL := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var tiles := PackedByteArray()
var rng := RandomNumberGenerator.new()
# Godot's native A* handles real travel routes in C++; the scripted BFS is
# kept for depth-capped speculative searches (hero target probes).
var _astar: AStarGrid2D
var _astar_dirty := true

func generate(seed_value: int) -> void:
	rng.seed = seed_value
	tiles.resize(SIZE_X * SIZE_Y)
	tiles.fill(GRASS)
	for x in SIZE_X:
		for y in SIZE_Y:
			var border := x == 0 or y == 0 or x == SIZE_X - 1 or y == SIZE_Y - 1
			var inner := x == 1 or y == 1 or x == SIZE_X - 2 or y == SIZE_Y - 2
			if border or (inner and rng.randf() < 0.5):
				set_terrain(Vector2i(x, y), MOUNTAIN)
	var lake := Vector2i(rng.randi_range(4, SIZE_X - 5), rng.randi_range(4, SIZE_Y - 5))
	for j in 8:
		var p := lake + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if get_terrain(p) == GRASS:
			set_terrain(p, WATER)
	# Woods and marshes each claim roughly a third of the open land, so
	# clearing ground is a standing tradeoff rather than a rare luxury.
	# Seeds are chosen first, then the blobs grow together so neither type
	# can crowd the other out.
	var blobs: Array = []
	_seed_blobs(blobs, FOREST, FOREST_BLOBS, FOREST_BLOB_SIZE)
	_seed_blobs(blobs, SWAMP, SWAMP_BLOBS, SWAMP_BLOB_SIZE)
	_grow_blobs(blobs)
	for x in range(SIZE_X / 2 - 2, SIZE_X / 2 + 3):
		for y in range(SIZE_Y / 2 - 2, SIZE_Y / 2 + 3):
			set_terrain(Vector2i(x, y), GRASS)

func _seed_blobs(blobs: Array, terrain: int, count: int, size: int) -> void:
	var centers: Array = []
	for i in count:
		var c := Vector2i(-1, -1)
		for attempt in 80:
			var p := Vector2i(rng.randi_range(3, SIZE_X - 4), rng.randi_range(3, SIZE_Y - 4))
			if get_terrain(p) != GRASS:
				continue
			var clear := true
			for q in centers:
				if Vector2(p).distance_to(Vector2(q)) < 5.0:
					clear = false
					break
			if clear:
				c = p
				break
		if c.x < 0:
			continue
		centers.append(c)
		set_terrain(c, terrain)
		blobs.append({"terrain": terrain, "size": size, "center": c, "cells": [c]})

func _grow_blobs(blobs: Array) -> void:
	# Eden-style growth: expand each blob from its own frontier, one cell
	# per blob per round, so the three terrains end up in roughly equal
	# shares. Radius keeps each wood/marsh a region rather than a stain.
	var max_rounds := 0
	for b in blobs:
		max_rounds = maxi(max_rounds, int(b.size) * 8)
	for round in max_rounds:
		var progress := false
		for b in blobs:
			if b.cells.size() >= int(b.size):
				continue
			for attempt in 16:
				var base: Vector2i = b.cells[rng.randi_range(0, b.cells.size() - 1)]
				var d: Vector2i = DIRS_ALL[rng.randi_range(0, DIRS_ALL.size() - 1)]
				var p := base + d
				if not in_bounds(p) or get_terrain(p) != GRASS:
					continue
				if Vector2(p).distance_to(Vector2(b.center)) > 10.0:
					continue
				set_terrain(p, int(b.terrain))
				b.cells.append(p)
				progress = true
				break
		if not progress:
			break

func get_terrain(p: Vector2i) -> int:
	if not in_bounds(p):
		return MOUNTAIN
	return tiles[p.y * SIZE_X + p.x]

func set_terrain(p: Vector2i, t: int) -> void:
	if in_bounds(p):
		tiles[p.y * SIZE_X + p.x] = t
		_astar_dirty = true

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < SIZE_X and p.y < SIZE_Y

func is_buildable(p: Vector2i) -> bool:
	return in_bounds(p) and get_terrain(p) == GRASS

func _walkable(p: Vector2i) -> bool:
	var t := get_terrain(p)
	return t == GRASS or t == FOREST or t == SWAMP

func _ensure_astar() -> void:
	if _astar != null and not _astar_dirty:
		return
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(0, 0, SIZE_X, SIZE_Y)
		_astar.cell_size = Vector2.ONE
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_astar.update()
	for y in SIZE_Y:
		for x in SIZE_X:
			var p := Vector2i(x, y)
			_astar.set_point_solid(p, not _walkable(p))
	_astar_dirty = false

func find_path(from: Vector2i, to: Vector2i, max_depth := -1) -> Array:
	# Real travel uses Godot's native A*; a non-negative `max_depth` asks for
	# a small speculative BFS instead (hero target probes) so those never
	# flood the map. Both return the tile list after `from` through `to`.
	var result: Array = []
	if from == to or not in_bounds(to) or not _walkable(from) or not _walkable(to):
		return result
	if max_depth == 0:
		return result
	if _adjacent_walk(from, to):
		return [to]
	if max_depth < 0:
		_ensure_astar()
		var routed: Array = _astar.get_id_path(from, to)
		if not routed.is_empty():
			routed.pop_front()
		return routed
	var prev := {}
	var depth := {from: 0}
	prev[from] = from
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var next_depth: int = int(depth[cur]) + 1
		if max_depth >= 0 and next_depth > max_depth:
			continue
		for d in DIRS_ALL:
			var n: Vector2i = cur + d
			if not in_bounds(n) or prev.has(n) or not _walkable(n):
				continue
			# Diagonal moves must not squeeze between two blocked tiles.
			if d.x != 0 and d.y != 0:
				if not _walkable(cur + Vector2i(d.x, 0)) \
						or not _walkable(cur + Vector2i(0, d.y)):
					continue
			prev[n] = cur
			depth[n] = next_depth
			if n == to:
				cur = n
				while cur != from:
					result.push_front(cur)
					cur = prev[cur]
				return result
			queue.append(n)
	if not prev.has(to):
		return result
	var cur := to
	while cur != from:
		result.push_front(cur)
		cur = prev[cur]
	return result

func _adjacent_walk(from: Vector2i, to: Vector2i) -> bool:
	# One-step shortcut: a hop to a neighbouring walkable tile needs no
	# search at all.
	for d in DIRS_ALL:
		if from + d == to and _walkable(from + d):
			return true
	return false

func mountain_edge_sites() -> Array:
	# Mountain tiles with at least one walkable neighbour — where dens can
	# squat and send warbands down into the realm.
	var sites: Array = []
	for y in SIZE_Y:
		for x in SIZE_X:
			var p := Vector2i(x, y)
			if get_terrain(p) != MOUNTAIN:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _walkable(p + d):
					sites.append(p)
					break
	return sites

func find_terrain(t: int) -> Vector2i:
	for y in SIZE_Y:
		for x in SIZE_X:
			if tiles[y * SIZE_X + x] == t:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
