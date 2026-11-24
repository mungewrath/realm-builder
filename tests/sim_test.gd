extends SceneTree

func _initialize() -> void:
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(42)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.seed_starting_buildings = false
	sim.wild_ecology = false # exact starting-state accounting; ecology tested separately
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # existing fixtures stay 1x1; footprint checks live in sim_test
	sim.set_fog_enabled(false) # exact starting-state accounting; fog tested separately
	sim.raids_enabled = false # exact starting-state accounting; raids tested separately
	sim.heroes_enabled = false
	sim.keep_trickle = 0 # exact starting-state accounting; trickle checked below
	var failed := false

	if sim.gold != 50 or sim.pop != 5 or sim.pop_cap != 5:
		failed = true
		print("FAIL: bad starting state")
	if sim.agents.size() != 4:
		failed = true
		print("FAIL: starting visible peasants not capped: %d" % sim.agents.size())
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
	broke.seed_starting_buildings = false
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
	var farm := Vector2i(-1, -1)
	var best_d := INF
	for y in w2.SIZE_Y:
		for x in w2.SIZE_X:
			var p := Vector2i(x, y)
			if not broke.can_build_at(p):
				continue
			var d := Vector2(p).distance_squared_to(Vector2(broke.keep_pos))
			if d < best_d:
				best_d = d
				farm = p
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

	# Building footprints: halls span several tiles, and every structure keeps
	# a full one-tile ring of open ground. Construction sites count immediately.
	var expected_sizes := {
		"castle": Vector2i(3, 3),
		"tavern": Vector2i(2, 1),
		"herbalist_grove": Vector2i(2, 2),
		"wizard_tower": Vector2i(1, 2),
		"market": Vector2i(2, 1),
		"shrine": Vector2i(2, 1),
		"blacksmith": Vector2i(2, 1),
		"ranger_hut": Vector2i(2, 1),
		"mead_hall": Vector2i(2, 1),
		"guardhouse": Vector2i(2, 1),
		"farm": Vector2i(1, 1),
		"house": Vector2i(1, 1),
	}
	var KingdomC = load("res://scripts/kingdom.gd")
	for kind in expected_sizes:
		if KingdomC.BUILDING_SIZES.get(kind, Vector2i.ZERO) != expected_sizes[kind]:
			failed = true
			print("FAIL: wrong footprint for %s: %s" % [kind, KingdomC.BUILDING_SIZES.get(kind, Vector2i.ZERO)])

	var w4 = load("res://scripts/world.gd").new()
	w4.generate(42)
	var pad = load("res://scripts/kingdom.gd").new()
	pad.wild_ecology = false
	pad.attach_world(w4)
	pad.building_padding = true
	pad.building_footprints = true
	pad.set_fog_enabled(false)
	pad.keep_trickle = 0
	pad.raids_enabled = false
	pad.heroes_enabled = false
	pad.gold = 500
	var castle: Rect2i = pad.building_rect(pad.keep_pos, "castle")
	if castle.size != Vector2i(3, 3) or castle.position != pad.keep_pos - Vector2i.ONE:
		failed = true
		print("FAIL: keep footprint not centred 3x3: %s" % castle)
	# The castle occupies its 3x3; its outer 5x5 ring is all padding.
	for y in range(castle.position.y - 1, castle.position.y + castle.size.y + 1):
		for x in range(castle.position.x - 1, castle.position.x + castle.size.x + 1):
			var q := Vector2i(x, y)
			if castle.has_point(q):
				if pad.can_build_at(q):
					failed = true
					print("FAIL: built on the keep footprint at %s" % q)
				elif pad.build_block_reason(q) != "Something already stands there":
					failed = true
					print("FAIL: wrong footprint reason: %s" % pad.build_block_reason(q))
			else:
				if pad.can_build_at(q):
					failed = true
					print("FAIL: built in the keep's padding ring at %s" % q)
				elif pad.build_block_reason(q) != "Leave a one-tile gap between buildings":
					failed = true
					print("FAIL: wrong padding reason: %s" % pad.build_block_reason(q))

	# The grove and ranger hut may root in forest or marsh; other halls
	# require grass.
	var w5 = load("res://scripts/world.gd").new()
	w5.generate(42)
	w5.tiles.fill(w5.GRASS) # deterministic empty canvas for footprint geometry
	var layout = load("res://scripts/kingdom.gd").new()
	layout.wild_ecology = false
	layout.attach_world(w5)
	layout.building_padding = true
	layout.building_footprints = true
	layout.set_fog_enabled(false)
	layout.keep_trickle = 0
	layout.raids_enabled = false
	layout.heroes_enabled = false
	layout.gold = 500
	var grove := Vector2i(8, 8)
	w5.set_terrain(grove, w5.FOREST)
	w5.set_terrain(grove + Vector2i(1, 0), w5.SWAMP)
	w5.set_terrain(grove + Vector2i(0, 1), w5.GRASS)
	w5.set_terrain(grove + Vector2i(1, 1), w5.FOREST)
	if layout.can_build_at(grove, "house"):
		failed = true
		print("FAIL: ordinary hall allowed on wild grove ground")
	if not layout.can_build_at(grove, "herbalist_grove"):
		failed = true
		print("FAIL: grove refused on mixed forest/marsh")
	elif not layout.build_at("herbalist_grove", grove):
		failed = true
		print("FAIL: grove build failed")
	else:
		for q in layout.building_tiles(grove, "herbalist_grove"):
			if layout.building_origin_at(q) != grove:
				failed = true
				print("FAIL: grove footprint not occupied at %s" % q)
		var beside_grove: Vector2i = grove + Vector2i(2, 0)
		if layout.can_build_at(beside_grove, "tavern"):
			failed = true
			print("FAIL: built in the grove's padding")
		elif layout.build_block_reason(beside_grove, "tavern") != "Leave a one-tile gap between buildings":
			failed = true
			print("FAIL: wrong grove padding reason: %s" % layout.build_block_reason(beside_grove, "tavern"))
		var tavern: Vector2i = grove + Vector2i(5, 0)
		if not layout.can_build_at(tavern, "tavern"):
			failed = true
			print("FAIL: valid 2x1 tavern refused")
		elif not layout.build_at("tavern", tavern):
			failed = true
			print("FAIL: 2x1 tavern build failed")
		else:
			if layout.building_rect(tavern, "tavern").size != Vector2i(2, 1):
				failed = true
				print("FAIL: tavern footprint wrong")
			if layout.building_origin_at(tavern + Vector2i(1, 0)) != tavern:
				failed = true
				print("FAIL: tavern's second tile not occupied")
			if layout.can_build_at(tavern + Vector2i(0, 1), "house"):
				failed = true
				print("FAIL: built directly below the tavern footprint")
	# The ranger hut shares the grove's wild-ground allowance.
	var ranger := Vector2i(15, 12)
	w5.set_terrain(ranger, w5.FOREST)
	w5.set_terrain(ranger + Vector2i(1, 0), w5.SWAMP)
	if layout.can_build_at(ranger, "house"):
		failed = true
		print("FAIL: house allowed on the ranger hut's wild ground")
	if not layout.can_build_at(ranger, "ranger_hut"):
		failed = true
		print("FAIL: ranger hut refused on forest/marsh")
	elif not layout.build_at("ranger_hut", ranger):
		failed = true
		print("FAIL: ranger hut build failed on wild ground")

	# Event log scrollback: every announcement is recorded with a monotonic
	# id and timestamp, and the ring is capped.
	var logsim = load("res://scripts/kingdom.gd").new()
	logsim.seed_starting_buildings = false
	logsim.wild_ecology = false
	logsim.raids_enabled = false
	logsim.heroes_enabled = false
	var w3 = load("res://scripts/world.gd").new()
	w3.generate(42)
	logsim.attach_world(w3)
	var log_before: int = logsim.event_log.size()
	logsim.last_event = "Test event A"
	logsim.update()
	logsim.last_event = "Test event B"
	if logsim.event_log.size() != log_before + 2:
		failed = true
		print("FAIL: event log missed announcements")
	elif logsim.event_log[-1].text != "Test event B":
		failed = true
		print("FAIL: event log kept the wrong last entry")
	elif int(logsim.event_log[-1].id) <= int(logsim.event_log[-2].id):
		failed = true
		print("FAIL: event log ids not monotonic")
	for i in logsim.EVENT_LOG_MAX + 20:
		logsim.last_event = "spam %d" % i
	if logsim.event_log.size() != logsim.EVENT_LOG_MAX:
		failed = true
		print("FAIL: event log not capped at %d (%d)" \
			% [logsim.EVENT_LOG_MAX, logsim.event_log.size()])

	print("RESULT: %s (gold=%d pop=%d/%d farms=%d houses=%d delivered=%d)" % ["PASS" if not failed else "FAIL", sim.gold, sim.pop, sim.pop_cap, sim.farms, sim.houses, sim.food_delivered])
	quit(1 if failed else 0)

func _wait_complete(sim, p: Vector2i, limit: int) -> bool:
	for i in limit:
		if sim.buildings[p].complete:
			return true
		sim.update()
	return sim.buildings[p].complete
