extends SceneTree

# M7.1 hall tests: the remaining content buildings, what each attracts and
# produces, the new hero classes arriving at their own halls, and the
# fog-heavy watch effects (tower scrying, ranger patrols).

var failed := false

func _initialize() -> void:
	_test_costs_and_attraction()
	_test_hero_arrival_homes()
	_test_blacksmith_gear()
	_test_wizard_tower()
	_test_ranger_hut()
	_test_mead_hall()
	_test_herbalist_grove()
	_test_hall_soak()
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)

func _make_sim(seed_value: int, fog := false):
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(seed_value)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.wild_ecology = false
	sim.raids_enabled = false
	sim.keep_trickle = 0
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # existing fixtures stay 1x1; footprint checks live in sim_test
	if not fog:
		sim.set_fog_enabled(false)
	return sim

func _complete(sim, kind: String, p: Vector2i) -> bool:
	sim.gold = 500
	if not sim.build_at(kind, p):
		_fail("build %s at %s refused" % [kind, p])
		return false
	sim.complete_building(p)
	return true

func _far_grass(sim, min_dist: int) -> Vector2i:
	for y in range(3, sim.world.SIZE_Y - 3):
		for x in range(3, sim.world.SIZE_X - 3):
			var p := Vector2i(x, y)
			if sim.world.get_terrain(p) != sim.world.GRASS:
				continue
			if sim.buildings.has(p) or sim.dens.has(p):
				continue
			var d := Vector2(p).distance_to(Vector2(sim.keep_pos))
			if d >= min_dist and d <= min_dist + 3:
				return p
	_fail("no grass found at distance %d" % min_dist)
	return Vector2i(-1, -1)

func _test_costs_and_attraction() -> void:
	var costs := {
		"blacksmith": 40, "wizard_tower": 60, "ranger_hut": 30,
		"mead_hall": 45, "herbalist_grove": 35,
	}
	for kind in costs:
		if int(load("res://scripts/kingdom.gd").BUILD_COSTS.get(kind, -1)) \
				!= int(costs[kind]):
			_fail("%s cost wrong" % kind)
	var expects := {
		"blacksmith": ["dwarf", "warrior"],
		"wizard_tower": ["wizard"],
		"ranger_hut": ["ranger"],
		"mead_hall": ["barbarian"],
		"herbalist_grove": ["druid"],
	}
	for kind in expects:
		var sim = _make_sim(701)
		if not _complete(sim, kind, sim.keep_pos + Vector2i(1, 1)):
			return
		var mix: Dictionary = sim._attraction_mix()
		for cls in expects[kind]:
			if int(mix.get(cls, 0)) != 1:
				_fail("%s did not attract %s: %s" % [kind, cls, mix])
		# The hall is the only building, so no other class should appear.
		if mix.size() != expects[kind].size():
			_fail("%s attracted an unexpected mix: %s" % [kind, mix])
	# Unfinished halls attract nobody.
	var sim = _make_sim(709)
	sim.gold = 500
	sim.build_at("wizard_tower", sim.keep_pos + Vector2i(1, 1))
	if not sim._attraction_mix().is_empty():
		_fail("unfinished tower attracted a hero")

func _test_hero_arrival_homes() -> void:
	var sim = _make_sim(719)
	var hall: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not _complete(sim, "blacksmith", hall):
		return
	sim._spawn_hero("warrior")
	var found = null
	for a in sim.agents:
		if a.kind == "hero" and a.hero_class == "warrior":
			found = a
	if found == null or found.home != hall:
		_fail("warrior did not adopt the blacksmith as home")
	# A class with a list of halls still picks one that actually attracts it.
	var rogue = _make_sim(727)
	if not _complete(rogue, "tavern", rogue.keep_pos + Vector2i(1, 1)):
		return
	rogue._spawn_hero("rogue")
	for a in rogue.agents:
		if a.kind == "hero" and a.hero_class == "rogue":
			if a.home != rogue.keep_pos + Vector2i(1, 1):
				_fail("rogue did not adopt the tavern as home")

func _test_blacksmith_gear() -> void:
	var sim = _make_sim(733)
	var p: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not _complete(sim, "blacksmith", p):
		return
	var b: Dictionary = sim.buildings[p]
	for i in sim.GEAR_FORGE_TICKS:
		sim._halls_tick()
	if int(b.get("gear", 0)) != 1 or sim.gear_forged != 1:
		_fail("blacksmith gear cadence wrong: %s, forged %d" % [b, sim.gear_forged])
	for i in sim.GEAR_FORGE_TICKS * 20:
		sim._halls_tick()
	if int(b.get("gear", 0)) != sim.GEAR_STOCK_CAP:
		_fail("blacksmith stock did not cap: %d" % int(b.get("gear", 0)))
	if sim.gear_forged != sim.GEAR_STOCK_CAP:
		_fail("blacksmith forged while racks were full: %d" % sim.gear_forged)

func _test_wizard_tower() -> void:
	var sim = _make_sim(739, true)
	var p := _far_grass(sim, 9)
	if p.x < 0:
		return
	sim._stamp_explored(p, 0.0)
	var before: int = sim.tiles_explored
	if not _complete(sim, "wizard_tower", p):
		return
	var b: Dictionary = sim.buildings[p]
	for i in sim.MANA_TRICKLE_TICKS * 3:
		sim._halls_tick()
	if int(b.get("mana", 0)) != 3 or sim.mana_channeled != 3:
		_fail("wizard mana cadence wrong: %s, channeled %d" % [b, sim.mana_channeled])
	for i in sim.TOWER_SCRY_TICKS:
		sim._halls_tick()
	if sim.tiles_explored <= before:
		_fail("wizard tower never scried the wilds")
	for i in sim.MANA_TRICKLE_TICKS * 40:
		sim._halls_tick()
	if int(b.get("mana", 0)) != sim.MANA_STOCK_CAP:
		_fail("wizard mana did not cap: %d" % int(b.get("mana", 0)))

func _test_ranger_hut() -> void:
	var sim = _make_sim(743, true)
	var p := _far_grass(sim, 9)
	if p.x < 0:
		return
	sim._stamp_explored(p, 0.0)
	var before: int = sim.tiles_explored
	if not _complete(sim, "ranger_hut", p):
		return
	for i in sim.RANGER_WATCH_TICKS:
		sim._halls_tick()
	if sim.tiles_explored <= before:
		_fail("ranger hut never revealed the wilds")
	# Calm covers the settled fields around the hut, but not the far realm.
	var near: Vector2i = p + Vector2i(2, 0)
	var far: Vector2i = sim.keep_pos + Vector2i(-1, -1)
	sim.buildings[near] = {"kind": "farm", "complete": true, "tax": 0}
	sim.buildings[far] = {"kind": "farm", "complete": true, "tax": 0}
	if not sim._ranger_calm_at(near):
		_fail("ranger hut did not calm the nearby farm")
	if sim._ranger_calm_at(far):
		_fail("ranger hut calmed a farm across the realm")

func _test_mead_hall() -> void:
	var sim = _make_sim(751)
	var p: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not _complete(sim, "mead_hall", p):
		return
	var b: Dictionary = sim.buildings[p]
	for i in sim.MEAD_BREW_TICKS * 3:
		sim._halls_tick()
	if int(b.get("morale", 0)) != 3 or sim.mead_brewed != 3:
		_fail("mead brewing cadence wrong: %s, brewed %d" % [b, sim.mead_brewed])
	if sim._mead_morale_bonus() != 1:
		_fail("three casks did not hearten the realm")
	for i in sim.MEAD_BREW_TICKS * 10:
		sim._halls_tick()
	if int(b.get("morale", 0)) != sim.MEAD_STOCK_CAP:
		_fail("mead morale did not cap: %d" % int(b.get("morale", 0)))
	if sim._mead_morale_bonus() != 2:
		_fail("a full hall did not hearten the realm fully")

func _test_herbalist_grove() -> void:
	var sim = _make_sim(757)
	var p: Vector2i = sim.keep_pos + Vector2i(1, 1)
	if not _complete(sim, "herbalist_grove", p):
		return
	var b: Dictionary = sim.buildings[p]
	for i in sim.HERB_GROW_TICKS * 2:
		sim._halls_tick()
	if int(b.get("herbs", 0)) != 2 or sim.herbs_grown != 2:
		_fail("herb growth cadence wrong: %s, grown %d" % [b, sim.herbs_grown])
	# A cursed farm within reach is cured by the grove's herbs.
	var farm: Vector2i = sim.keep_pos + Vector2i(2, 1)
	sim.buildings[farm] = {"kind": "farm", "complete": true, "tax": 0,
		"cursed_until": sim.tick + 100}
	if not sim.is_cursed(farm):
		_fail("test farm was not cursed")
	for i in sim.HERB_CURE_TICKS:
		sim._halls_tick()
	if sim.is_cursed(farm):
		_fail("herbalist grove never lifted the curse")
	if sim.curses_cured != 1:
		_fail("curse cure not accounted: %d" % sim.curses_cured)
	if int(b.get("herbs", 0)) < 0:
		_fail("herbalist grove spent herbs it did not have")
	# A hero turns in at the grove when it is the nearer hearth.
	var AgentC = load("res://scripts/agents.gd")
	var h = AgentC.new()
	h.setup(sim, "hero", sim.keep_pos + Vector2i(2, 2))
	h.hero_class = "druid"
	if sim.hero_rest_spot(h) != p:
		_fail("hero did not choose the nearest herbalist grove to rest")

func _test_hall_soak() -> void:
	var sim = _make_sim(761, true)
	sim.heroes_enabled = true
	var homes := ["blacksmith", "wizard_tower", "ranger_hut", "mead_hall",
		"herbalist_grove", "tavern", "shrine"]
	var i := 0
	for kind in homes:
		var p := _far_grass(sim, 5 + i)
		if p.x < 0:
			return
		sim._stamp_explored(p, 2.0)
		if not _complete(sim, kind, p):
			return
		i += 2
	for n in 600:
		sim.update()
	if sim.tick < 600:
		_fail("hall soak did not advance the sim")
