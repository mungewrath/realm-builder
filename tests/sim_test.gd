extends SceneTree

func _initialize() -> void:
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(42)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.attach_world(WorldC)
	var failed := false

	if sim.gold != 50 or sim.pop != 5 or sim.pop_cap != 5:
		failed = true
		print("FAIL: bad starting state")
	if not sim.buildings.has(sim.keep_pos) or sim.buildings[sim.keep_pos] != "castle":
		failed = true
		print("FAIL: keep not placed")

	var spot: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not sim.can_build_at(spot):
		failed = true
		print("FAIL: grass tile refused")
	if not sim.build_at("house", spot):
		failed = true
		print("FAIL: house build failed")
	if sim.gold != 35 or sim.houses != 1 or sim.pop_cap != 8:
		failed = true
		print("FAIL: house cost/cap not applied")
	if sim.can_build_at(spot):
		failed = true
		print("FAIL: occupied tile buildable")

	var water: Vector2i = WorldC.find_terrain(2)
	if water.x >= 0 and sim.build_at("farm", water):
		failed = true
		print("FAIL: built on water")

	sim.gold = 0
	var spot2: Vector2i = sim.keep_pos + Vector2i(2, 2)
	if sim.build_at("farm", spot2):
		failed = true
		print("FAIL: bought without gold")
	sim.gold = 50
	if not sim.build_at("farm", spot2):
		failed = true
		print("FAIL: valid farm build refused")

	for i in 10:
		sim.update()
	if sim.tick != 10:
		failed = true
		print("FAIL: ticks wrong")
	if sim.pop < 1 or sim.food < 0 or sim.gold <= 0:
		failed = true
		print("FAIL: economy out of range: food=%d pop=%d gold=%d" % [sim.food, sim.pop, sim.gold])

	print("RESULT: %s (gold=%d food=%d pop=%d/%d farms=%d houses=%d)" % ["PASS" if not failed else "FAIL", sim.gold, sim.food, sim.pop, sim.pop_cap, sim.farms, sim.houses])
	quit(1 if failed else 0)
