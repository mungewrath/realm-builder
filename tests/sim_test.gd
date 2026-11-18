extends SceneTree

func _initialize() -> void:
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(42)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.wild_ecology = false # exact starting-state accounting; ecology tested separately
	sim.attach_world(WorldC)
	sim.set_fog_enabled(false) # exact starting-state accounting; fog tested separately
	sim.raids_enabled = false # exact starting-state accounting; raids tested separately
	sim.heroes_enabled = false
	sim.keep_trickle = 0 # exact starting-state accounting; trickle checked below
	var failed := false

	if sim.gold != 50 or sim.pop != 5 or sim.pop_cap != 5:
		failed = true
		print("FAIL: bad starting state")
	if sim.agents.size() != 5:
		failed = true
		print("FAIL: starting peasants not spawned: %d" % sim.agents.size())
	if not sim.buildings.has(sim.keep_pos) or sim.buildings[sim.keep_pos].kind != "castle":
		failed = true
		print("FAIL: keep not placed")

	var spot: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not sim.can_build_at(spot):
		failed = true
		print("FAIL: grass tile refused")
	if not sim.build_at("house", spot):
		failed = true
		print("FAIL: house build failed")
	if sim.gold != 35:
		failed = true
		print("FAIL: house cost not applied: %d" % sim.gold)
	if sim.buildings[spot].complete or sim.houses != 0 or sim.pop_cap != 5:
		failed = true
		print("FAIL: house should start as a construction site")
	if not _wait_complete(sim, spot, 60):
		failed = true
		print("FAIL: house never finished")
	if sim.houses != 1 or sim.pop_cap != 8:
		failed = true
		print("FAIL: completion accounting: houses=%d cap=%d" % [sim.houses, sim.pop_cap])
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
	if not _wait_complete(sim, spot2, 60):
		failed = true
		print("FAIL: farm never finished")

	for i in 40:
		sim.update()
	if sim.pop < 1 or sim.gold < 0:
		failed = true
		print("FAIL: economy out of range: pop=%d gold=%d" % [sim.pop, sim.gold])
	if sim.food_delivered <= 0:
		failed = true
		print("FAIL: no food delivered by labor")
	for a in sim.agents:
		if not WorldC.in_bounds(a.tile()):
			failed = true
			print("FAIL: agent out of bounds at %s" % a.tile())

	# Keep trickle: a broke realm still earns pocket coin, so the player can
	# never be hard-stuck. 5g per minute (60 ticks) at normal pacing.
	var broke = load("res://scripts/kingdom.gd").new()
	var w2 = load("res://scripts/world.gd").new()
	w2.generate(42)
	broke.attach_world(w2)
	broke.set_fog_enabled(false)
	broke.raids_enabled = false
	broke.heroes_enabled = false
	broke.gold = 0
	var g0: int = broke.gold
	for i in 60:
		broke.update()
	if broke.gold - g0 != 5:
		failed = true
		print("FAIL: keep trickle wrong: %d over 60 ticks" % (broke.gold - g0))
	# With the trickle sped up, a hard-stuck realm recovers buildability.
	broke.keep_trickle_ticks = 2
	var farm: Vector2i = broke.keep_pos + Vector2i(3, 3)
	broke.gold = 0
	for i in 30:
		broke.update()
		if broke.gold >= broke.BUILD_COSTS["farm"]:
			break
	if broke.gold < broke.BUILD_COSTS["farm"]:
		failed = true
		print("FAIL: broke realm never dug out: gold=%d" % broke.gold)
	elif not broke.build_at("farm", farm):
		failed = true
		print("FAIL: recovered realm could not build")

	print("RESULT: %s (gold=%d pop=%d/%d farms=%d houses=%d delivered=%d)" % ["PASS" if not failed else "FAIL", sim.gold, sim.pop, sim.pop_cap, sim.farms, sim.houses, sim.food_delivered])
	quit(1 if failed else 0)

func _wait_complete(sim, p: Vector2i, limit: int) -> bool:
	for i in limit:
		if sim.buildings[p].complete:
			return true
		sim.update()
	return sim.buildings[p].complete
