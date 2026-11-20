extends SceneTree

func _initialize() -> void:
	var WorldC = load("res://scripts/world.gd").new()
	var failed := false

	WorldC.generate(1234)
	var first: PackedByteArray = WorldC.tiles.duplicate()
	var other = load("res://scripts/world.gd").new()
	other.generate(1234)
	if first != other.tiles:
		failed = true
		print("FAIL: generation not deterministic")

	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for t in first:
		counts[t] += 1
	if counts[0] == 0 or counts[1] == 0 or counts[2] == 0 or counts[3] == 0 \
			or counts[4] == 0:
		failed = true
		print("FAIL: missing terrain type: %s" % [counts])

	if WorldC.get_terrain(Vector2i(-1, -1)) != 3:
		failed = true
		print("FAIL: out of bounds should be mountain")
	if WorldC.is_buildable(Vector2i(-1, -1)):
		failed = true
		print("FAIL: out of bounds buildable")

	var center := Vector2i(WorldC.SIZE_X / 2, WorldC.SIZE_Y / 2)
	if WorldC.get_terrain(center) != 0:
		failed = true
		print("FAIL: keep site not grass")

	var water: Vector2i = WorldC.find_terrain(2)
	if water.x >= 0 and WorldC.is_buildable(water):
		failed = true
		print("FAIL: water buildable")

	var mountain: Vector2i = WorldC.find_terrain(3)
	if mountain.x >= 0 and WorldC.is_buildable(mountain):
		failed = true
		print("FAIL: mountain buildable")

	if WorldC.is_buildable(WorldC.find_terrain(4)):
		failed = true
		print("FAIL: swamp buildable")

	# Pathfinding can be depth-capped for speculative searches, while real
	# travel still uses the full BFS.
	var far := Vector2i(-1, -1)
	for y in WorldC.SIZE_Y:
		for x in WorldC.SIZE_X:
			var p := Vector2i(x, y)
			if Vector2(p).distance_to(Vector2(center)) < 8:
				continue
			if not WorldC.find_path(center, p).is_empty():
				far = p
				break
		if far.x >= 0:
			break
	if far.x < 0:
		failed = true
		print("FAIL: no distant reachable target for path test")
	elif not WorldC.find_path(center, far, 2).is_empty():
		failed = true
		print("FAIL: depth-capped path escaped its budget")

	print("RESULT: %s (grass=%d forest=%d water=%d mountain=%d swamp=%d)" % ["PASS" if not failed else "FAIL", counts[0], counts[1], counts[2], counts[3], counts[4]])
	quit(1 if failed else 0)
