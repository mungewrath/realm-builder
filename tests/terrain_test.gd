extends SceneTree

# M6.3 terrain-action tests: drain marsh / clear woods costs and effects,
# the marsh chain (frog habitats collapse, owlbears turn to the farms),
# den migration off lost habitat, and the druid's protect/depart reaction.

var failed := false

func _initialize() -> void:
	_test_drain_and_clear()
	_test_terrain_labour()
	_test_terrain_refusals()
	_test_frog_habitat_collapse()
	_test_forest_ripple()
	_test_owlbear_chain()
	_test_druid_reaction()
	_test_long_run()
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)

func _make_sim(seed_value: int, wild := false):
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(seed_value)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.wild_ecology = wild
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # existing fixtures stay 1x1; footprint checks live in sim_test
	sim.set_fog_enabled(false)
	sim.keep_trickle = 0
	sim.heroes_enabled = false
	sim.raids_enabled = false
	sim.wild_spawn_chance = 0.0
	sim.wild_respawn_rest_left = 999999
	return sim

func _dens_of_kind(sim, kind_key: String) -> Array:
	var out := []
	for p in sim.dens:
		if sim.dens[p].get("kind", "") == kind_key:
			out.append(p)
	return out

func _clear_wilds(sim) -> void:
	# Strip the seeded dens and their beasts so staged chains are exact.
	for p in sim.dens.keys():
		sim.dens.erase(p)
	var kept := []
	for a in sim.agents:
		if a.kind != "creature" and a.kind != "bandit":
			kept.append(a)
	sim.agents = kept

func _swamp_with_habitat(sim, need := 3) -> Vector2i:
	# A marsh tile with enough wet ground around it for a frog pond.
	for y in sim.world.SIZE_Y:
		for x in sim.world.SIZE_X:
			var p := Vector2i(x, y)
			if sim.world.get_terrain(p) != sim.world.SWAMP:
				continue
			var wet := 0
			for dy in range(-6, 7):
				for dx in range(-6, 7):
					if dx * dx + dy * dy > 36:
						continue
					if sim.world.get_terrain(p + Vector2i(dx, dy)) == sim.world.SWAMP:
						wet += 1
			if wet >= need + 2:
				return p
	return Vector2i(-1, -1)

func _forest_tile(sim) -> Vector2i:
	return sim.world.find_terrain(sim.world.FOREST)

func _test_drain_and_clear() -> void:
	var sim = _make_sim(501)
	sim.gold = 200
	var bog := _swamp_with_habitat(sim)
	if bog.x < 0:
		_fail("no marsh to drain")
		return
	if not sim.can_drain_swamp(bog):
		_fail("marsh tile not drainable")
		return
	var before: int = sim.gold
	if not sim.drain_swamp(bog):
		_fail("drain refused")
		return
	if sim.world.get_terrain(bog) != sim.world.SWAMP:
		_fail("marsh changed before any labour was spent")
	if not sim.terrain_works.has(bog):
		_fail("drain order left no worksite")
	if sim.gold != before - sim.drain_cost:
		_fail("drain did not charge gold: %d -> %d" % [before, sim.gold])
	if sim.tiles_drained != 0 or sim.pollution != 0:
		_fail("drain counted before completion")
	if sim.can_drain_swamp(bog) or sim.drain_swamp(bog):
		_fail("ordered the same marsh twice")
	for i in sim.TERRAIN_WORK_TICKS - 1:
		if sim.tick_terrain(bog):
			_fail("drain finished early")
	if not sim.tick_terrain(bog):
		_fail("drain never completed")
	if sim.world.get_terrain(bog) != sim.world.GRASS:
		_fail("drained marsh did not become grass")
	if sim.terrain_works.has(bog):
		_fail("completed worksite not cleared")
	if sim.tiles_drained != 1 or sim.pollution != 2:
		_fail("drain not counted: drained=%d pollution=%d"
			% [sim.tiles_drained, sim.pollution])
	if not sim.can_build_at(bog):
		_fail("drained marsh is not buildable")
	if sim.drain_swamp(bog):
		_fail("drained tile drained twice")
	var woods := _forest_tile(sim)
	if woods.x < 0:
		_fail("no forest to clear")
		return
	if not sim.can_clear_forest(woods):
		_fail("forest tile not clearable")
		return
	before = sim.gold
	if not sim.clear_forest(woods):
		_fail("clear refused")
		return
	if sim.world.get_terrain(woods) != sim.world.FOREST:
		_fail("woods changed before any labour was spent")
	if sim.gold != before - sim.clear_cost:
		_fail("clear did not charge gold")
	for i in sim.TERRAIN_WORK_TICKS:
		sim.tick_terrain(woods)
	if sim.world.get_terrain(woods) != sim.world.GRASS:
		_fail("cleared woods did not become grass")
	if sim.tiles_cleared != 1 or sim.pollution != 3:
		_fail("clear not counted: cleared=%d pollution=%d"
			% [sim.tiles_cleared, sim.pollution])

func _test_terrain_labour() -> void:
	# Peasants pick up ordered terrain work the same way they pick up a
	# construction site, and the land only changes when they finish.
	var sim = _make_sim(502)
	sim.gold = 200
	var bog := _swamp_with_habitat(sim)
	if bog.x < 0 or not sim.drain_swamp(bog):
		_fail("no ordered marsh for the labour test")
		return
	var worker = null
	for a in sim.agents:
		if a.kind == "peasant":
			worker = a
			break
	if worker == null:
		_fail("no peasant to drain the marsh")
		return
	worker.pos = Vector2(bog) + Vector2(0.5, 0.5)
	worker.state = "idle"
	worker.purpose = ""
	worker.target = Vector2i(-1, -1)
	for a in sim.agents:
		if a.kind == "peasant" and a != worker:
			a.state = "acting"
			a.work_left = 100 # keep other hands off the worksite
	sim._assign_jobs()
	if worker.purpose != "terrain" or worker.target != bog:
		_fail("peasant did not take the terrain work: %s %s"
			% [worker.purpose, worker.target])
		return
	for i in 40:
		worker.update()
		if sim.world.get_terrain(bog) == sim.world.GRASS:
			break
	if sim.world.get_terrain(bog) != sim.world.GRASS:
		_fail("peasant labour never finished the drain")
	if sim.tiles_drained != 1:
		_fail("labour drain not counted")

func _test_terrain_refusals() -> void:
	var sim = _make_sim(503)
	sim.gold = 0
	var bog := _swamp_with_habitat(sim)
	if bog.x < 0:
		_fail("no marsh for refusal test")
		return
	if sim.drain_swamp(bog):
		_fail("drained marsh without gold")
	if sim.world.get_terrain(bog) != sim.world.SWAMP:
		_fail("failed drain still changed terrain")
	if sim.clear_forest(_forest_tile(sim)):
		_fail("cleared woods without gold")
	# Dens and buildings cannot be worked over.
	sim.gold = 200
	sim.dens[bog] = {"kind": "frog_den", "level": 1, "hp": 5, "food": 3,
		"gold": 0, "unmet": 0, "regrow": 0}
	if sim.can_drain_swamp(bog) or sim.drain_swamp(bog):
		_fail("drained marsh under a den")
	sim.dens.erase(bog)
	var woods := _forest_tile(sim)
	sim.buildings[woods] = {"kind": "house", "complete": true, "tax": 0}
	if sim.can_clear_forest(woods) or sim.clear_forest(woods):
		_fail("cleared woods under a building")

func _test_frog_habitat_collapse() -> void:
	var sim = _make_sim(505, true)
	_clear_wilds(sim)
	var bog := _swamp_with_habitat(sim)
	if bog.x < 0:
		_fail("no marsh for the frog chain")
		return
	sim._place_wild_den("frog_den", bog, 8)
	sim.den_migrate_ticks = 4
	# Wet ground intact: a fed pond stays put even when the clock runs.
	for i in 6:
		sim.update()
	if not sim.dens.has(bog):
		_fail("fed frog pond moved with its marsh intact")
		return
	# Drain the pond's claim dry: habitat loss drives it out even with food.
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if dx * dx + dy * dy > 36:
				continue
			var q := bog + Vector2i(dx, dy)
			if sim.world.get_terrain(q) == sim.world.SWAMP:
				sim.world.set_terrain(q, sim.world.GRASS)
	for i in 6:
		sim.update()
		if not sim.dens.has(bog):
			break
	if sim.dens.has(bog):
		_fail("frog pond outlived its drained marsh")
	if sim.dens_migrated + sim.dens_starved <= 0:
		_fail("frog collapse was not accounted")

func _test_forest_ripple() -> void:
	# Felling the woods under a forest lair drives it out, same as draining
	# a marsh under the frogs.
	var sim = _make_sim(506, true)
	_clear_wilds(sim)
	var wood := Vector2i(-1, -1)
	for y in sim.world.SIZE_Y:
		for x in sim.world.SIZE_X:
			var p := Vector2i(x, y)
			if sim.world.get_terrain(p) != sim.world.FOREST:
				continue
			var trees := 0
			for dy in range(-6, 7):
				for dx in range(-6, 7):
					if dx * dx + dy * dy > 36:
						continue
					if sim.world.get_terrain(p + Vector2i(dx, dy)) == sim.world.FOREST:
						trees += 1
			if trees >= 5:
				wood = p
				break
		if wood.x >= 0:
			break
	if wood.x < 0:
		_fail("no deep woods for the forest ripple")
		return
	sim._place_wild_den("wolf_den", wood, 8)
	sim.den_migrate_ticks = 4
	for i in 6:
		sim.update()
	if not sim.dens.has(wood):
		_fail("fed wolf den moved with its woods intact")
		return
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if dx * dx + dy * dy > 36:
				continue
			var q := wood + Vector2i(dx, dy)
			if sim.world.get_terrain(q) == sim.world.FOREST:
				sim.world.set_terrain(q, sim.world.GRASS)
	for i in 6:
		sim.update()
		if not sim.dens.has(wood):
			break
	if sim.dens.has(wood):
		_fail("wolf den outlived its felled woods")

func _test_owlbear_chain() -> void:
	var sim = _make_sim(507, true)
	_clear_wilds(sim)
	var bog := _swamp_with_habitat(sim)
	var forest := _forest_tile(sim)
	if bog.x < 0 or forest.x < 0:
		_fail("no marsh/forest for the owlbear chain")
		return
	var farm: Vector2i = sim.keep_pos + Vector2i(2, 2)
	sim.buildings[farm] = {"kind": "farm", "complete": true, "tax": 0}
	sim._place_wild_den("frog_den", bog, 6)
	sim._place_wild_den("owlbear_den", forest, 0)
	var owl = null
	for a in sim.agents:
		if a.kind == "creature" and a.species == "owlbear":
			owl = a
			break
	if owl == null:
		_fail("owlbear den spawned no owlbear")
		return
	sim._roll_creature_behavior(owl)
	if owl.purpose != "hunt" or owl.target != bog:
		_fail("hungry owlbear did not stalk the frog pond: %s %s"
			% [owl.purpose, owl.target])
	# Frogs gone: with no wild prey left, the hunt turns to the farm stores.
	sim.dens.erase(bog)
	var quarry: Vector2i = sim._hunt_target(owl)
	if quarry != farm:
		_fail("owlbear did not fall back to the farm: %s" % quarry)

func _test_druid_reaction() -> void:
	var sim = _make_sim(509, true)
	sim._spawn_hero("druid")
	var h = null
	for a in sim.agents:
		if a.kind == "hero" and a.hero_class == "druid":
			h = a
			break
	if h == null:
		_fail("druid never arrived")
		return
	if sim._wilds_known_to_realm().is_empty():
		_fail("no wilds for the druid to protect")
		return
	var scores: Dictionary = sim.hero_goal_scores(h)
	if not scores.has("protect") or int(scores["protect"]) < 9:
		_fail("druid protect_wilderness did not score: %s" % scores)
	if sim._best_hero_goal(scores) != "protect":
		_fail("druid favored something over the wilds: %s" % scores)
	sim.pollution = 4
	scores = sim.hero_goal_scores(h)
	var calm: int = int(scores.get("protect", 0))
	sim.pollution = 7
	if int(sim.hero_goal_scores(h).get("protect", 0)) <= calm:
		_fail("protect score did not rise with pollution")
	# Tending a wild lair feeds it.
	var wilds: Array = sim._wilds_known_to_realm()
	var den: Vector2i = wilds[0]
	sim.dens[den].food = 1
	h.target = den
	sim.hero_protect(h)
	if int(sim.dens[den].food) != 2 or sim.wilderness_tended != 1:
		_fail("druid tending did not feed the wilds")
	# Defile enough of the land and the druid walks away.
	sim.pollution = sim.druid_pollution_limit
	sim._assign_heroes()
	if not sim._removals.has(h) or sim.druids_departed != 1:
		_fail("druid did not depart a defiled realm")
	sim._reap()
	if sim.agents.has(h):
		_fail("departed druid still in the sim")
	# ...and no fresh druid is drawn to a realm past the pollution limit.
	var grove: Vector2i = sim.keep_pos + Vector2i(1, 0)
	sim.buildings[grove] = {"kind": "herbalist_grove", "complete": true,
		"tax": 0, "progress": 0}
	sim.pollution = 0
	if not sim._attraction_mix().has("druid"):
		_fail("groves stopped drawing druids from a clean realm")
	sim.pollution = sim.druid_pollution_limit
	if sim._attraction_mix().has("druid"):
		_fail("a defiled realm still drew a druid")

func _test_long_run() -> void:
	var sim = _make_sim(511, true)
	sim.heroes_enabled = true
	sim.gold = 200
	for p in sim.dens:
		sim.dens[p].hp = 999
	for i in 900:
		sim.update()
	if sim.pollution < 0:
		_fail("negative pollution")
	for p in sim.dens:
		if not sim.DEN_KINDS.has(sim.dens[p].get("kind", "")):
			_fail("unknown den kind after terrain soak")
		if sim.world.get_terrain(p) != sim.world.SWAMP \
				and sim.world.get_terrain(p) != sim.world.FOREST \
				and sim.world.get_terrain(p) != sim.world.MOUNTAIN \
				and sim.world.get_terrain(p) != sim.world.GRASS:
			_fail("den on impossible terrain after soak")
	if sim.pop < 1:
		_fail("realm died in the terrain soak")
