const GRASS := 0
const FOREST := 1
const WATER := 2
const MOUNTAIN := 3

const SIZE_X := 48
const SIZE_Y := 32

var tiles := PackedByteArray()
var rng := RandomNumberGenerator.new()

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
	for i in 4:
		var center := Vector2i(rng.randi_range(3, SIZE_X - 4), rng.randi_range(3, SIZE_Y - 5))
		for j in 10:
			var p := center + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			if get_terrain(p) == GRASS:
				set_terrain(p, FOREST)
	var lake := Vector2i(rng.randi_range(4, SIZE_X - 5), rng.randi_range(4, SIZE_Y - 5))
	for j in 8:
		var p := lake + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if get_terrain(p) == GRASS:
			set_terrain(p, WATER)
	for x in range(SIZE_X / 2 - 2, SIZE_X / 2 + 3):
		for y in range(SIZE_Y / 2 - 2, SIZE_Y / 2 + 3):
			set_terrain(Vector2i(x, y), GRASS)

func get_terrain(p: Vector2i) -> int:
	if not in_bounds(p):
		return MOUNTAIN
	return tiles[p.y * SIZE_X + p.x]

func set_terrain(p: Vector2i, t: int) -> void:
	if in_bounds(p):
		tiles[p.y * SIZE_X + p.x] = t

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < SIZE_X and p.y < SIZE_Y

func is_buildable(p: Vector2i) -> bool:
	return in_bounds(p) and get_terrain(p) == GRASS

func find_terrain(t: int) -> Vector2i:
	for y in SIZE_Y:
		for x in SIZE_X:
			if tiles[y * SIZE_X + x] == t:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
