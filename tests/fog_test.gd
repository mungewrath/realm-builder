extends SceneTree

# M5 fog-of-war tests: starting reveal, reveal accounting (and that charted
# ground stays revealed permanently), landmark (den) discovery as fog lifts,
# hero exploration, build gating on unexplored land, the dev fog toggle,
# minimap data sync, and a headless perf budget with the whole sim running.

var failed := false

func _initialize() -> void:
	_test_starting_reveal()
	_test_reveal_accounting()
	_test_landmark_discovery()
	_test_hero_reveals()
	_test_build_gating()
	_test_fog_toggle()
	_test_minimap_sync()
	_test_hero_ignores_fog()
	_test_hero_explores()
	_test_perf_budget()
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)

func _make_sim(seed_value: int):
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(seed_value)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.attach_world(WorldC)
	sim.raids_enabled = false # fog behavior, not warband pacing
	return sim

func _count_explored(sim) -> int:
	var n := 0
	for v in sim.explored:
		if v == 1:
			n += 1
	return n

func _add_hero(sim, cls: String, spot: Vector2i):
	var AgentC = load("res://scripts/agents.gd")
	var h = AgentC.new()
	h.setup(sim, "hero", spot)
	h.hero_class = cls
	h.max_hp = sim.HERO_CLASSES[cls].hp
	h.hp = h.max_hp
	h.home = sim.keep_pos
	sim.agents.append(h)
	return h

func _test_starting_reveal() -> void:
	var sim = _make_sim(5)
	if sim.fog_enabled != true:
		_fail("fog should start enabled")
	if sim.tiles_explored <= 0 or sim.tiles_explored >= sim.explored.size():
		_fail("starting reveal should be partial: %d/%d" \
			% [sim.tiles_explored, sim.explored.size()])
	if not sim.explored_at(sim.keep_pos):
		_fail("keep tile not explored at start")
	# The wilds stay wild: at least one seeded den is unexplored.
	var hidden_dens := 0
	for p in sim.dens:
		if not sim.explored_at(p):
			hidden_dens += 1
	if hidden_dens == 0:
		_fail("all seed dens already explored; fog reveals too much")

func _test_reveal_accounting() -> void:
	var sim = _make_sim(5)
	if _count_explored(sim) != sim.tiles_explored:
		_fail("tiles_explored disagrees with the explored layer")
	var before: int = sim.tiles_explored
	sim._stamp_explored(sim.keep_pos + Vector2i(12, -12), 3.0)
	if sim.tiles_explored <= before:
		_fail("stamping a fresh area did not grow the count")
	# Restamping the same spot is idempotent for the count.
	var after: int = sim.tiles_explored
	sim._stamp_explored(sim.keep_pos + Vector2i(12, -12), 3.0)
	if sim.tiles_explored != after:
		_fail("re-stamp double-counted tiles")
	# Charted ground is permanent: a live sim never un-reveals it.
	for i in 40:
		sim.update()
	if _count_explored(sim) < after:
		_fail("revealed ground regressed back into fog")

func _test_landmark_discovery() -> void:
	var sim = _make_sim(5)
	var found_before: int = sim.landmarks_spotted
	var den: Vector2i = Vector2i(-1, -1)
	for p in sim.dens:
		if not sim.explored_at(p):
			den = p
			break
	if den.x < 0:
		_fail("no unexplored den to discover")
		return
	var doorstep: Vector2i = sim.den_doorstep(den, sim.keep_pos)
	_add_hero(sim, "warrior", doorstep)
	sim._fog_tick()
	if sim.landmarks_spotted <= found_before:
		_fail("walking to a den did not count a landmark")
	if not sim.last_event.contains("den is spied"):
		_fail("no discovery event: '%s'" % sim.last_event)

func _test_hero_reveals() -> void:
	var sim = _make_sim(5)
	var before: int = sim.tiles_explored
	var hero = _add_hero(sim, "rogue", sim.keep_pos)
	# March the hero into unexplored wilds.
	var far: Vector2i = sim.keep_pos + Vector2i(14, 10)
	if not sim.world.in_bounds(far):
		far = sim.keep_pos + Vector2i(-14, 8)
	hero.assign(far, "wander")
	for i in 20:
		sim.update()
		if sim.tiles_explored > before + 10:
			break
	if sim.tiles_explored <= before + 10:
		_fail("roaming hero revealed too little: %d -> %d" % [before, sim.tiles_explored])
	if not sim.explored_at(hero.tile()):
		_fail("hero's own tile left unexplored")
	# A worker reveals too, but with a smaller eye.
	var sim2 = _make_sim(5)
	var before2: int = sim2.tiles_explored
	var peasant = sim2.agents[0]
	var far2: Vector2i = sim2.keep_pos + Vector2i(10, 8)
	peasant.assign(far2, "wander")
	for i in 20:
		sim2.update()
		if sim2.tiles_explored > before2 + 10:
			break
	if sim2.tiles_explored <= before2 + 10:
		_fail("moving worker revealed nothing")

func _test_build_gating() -> void:
	var sim = _make_sim(5)
	# Find unexplored buildable grass beyond the starting reveal.
	var far: Vector2i = Vector2i(-1, -1)
	for y in sim.world.SIZE_Y:
		for x in sim.world.SIZE_X:
			var p := Vector2i(x, y)
			if sim.world.is_buildable(p) and not sim.explored_at(p):
				far = p
				break
		if far.x >= 0:
			break
	if far.x < 0:
		_fail("no unexplored grass tile to test against")
		return
	sim.gold = 500
	if sim.can_build_at(far):
		_fail("build allowed on unexplored land")
	if sim.build_at("farm", far):
		_fail("build succeeded on unexplored land")
	if sim.last_event != "That land is unexplored":
		_fail("wrong refusal message: '%s'" % sim.last_event)
	# Once charted, the same tile builds fine.
	sim._stamp_explored(far, 1.0)
	if not sim.can_build_at(far):
		_fail("build still refused after the land was charted")
	if not sim.build_at("farm", far):
		_fail("build refused after the land was charted")

func _test_fog_toggle() -> void:
	var sim = _make_sim(5)
	sim.set_fog_enabled(false)
	if sim.fog_enabled:
		_fail("fog toggle did not disable")
	if sim.tiles_explored != sim.explored.size():
		_fail("fog off should chart the whole map")
	if not sim.explored_at(Vector2i(0, 0)):
		_fail("corner unexplored with fog off")
	# Every den shows with fog off.
	for p in sim.dens:
		if not sim.explored_at(p):
			_fail("den hidden despite fog off")
	# Back on: state resets and re-charts from the realm's actual footing.
	sim.set_fog_enabled(true)
	if sim.tiles_explored == sim.explored.size():
		_fail("fog re-enable did not reset exploration")
	if not sim.explored_at(sim.keep_pos):
		_fail("keep not re-charted after re-enabling fog")
	for a in sim.agents:
		if a.kind == "goblin":
			continue
		if not sim.explored_at(a.tile()):
			_fail("friendly agent position not re-charted at %s" % a.tile())

func _test_minimap_sync() -> void:
	# The minimap is view-only; the data contract it reads must hold:
	# explored layer density matches the accounting, and explored tiles are
	# never outside the map.
	var sim = _make_sim(5)
	for i in 30:
		sim.update()
	var count := _count_explored(sim)
	if count != sim.tiles_explored:
		_fail("minimap source out of sync: layer=%d counter=%d" \
			% [count, sim.tiles_explored])
	for y in sim.world.SIZE_Y:
		for x in sim.world.SIZE_X:
			var v: int = sim.explored[y * sim.world.SIZE_X + x]
			if v != 0 and v != 1:
				_fail("explored layer holds a non-flag value %d" % v)

func _test_hero_ignores_fog() -> void:
	# Heroes are not omniscient: dens and loot in uncharted land are not
	# options in their scoring until the realm has charted them.
	var sim = _make_sim(5)
	sim.raids_enabled = false
	sim.heroes_enabled = false
	var warrior = _add_hero(sim, "warrior", sim.keep_pos)
	if sim.hero_goal_scores(warrior).has("smite"):
		_fail("hero smote a den hidden in fog")
	var den: Vector2i = Vector2i(-1, -1)
	for p in sim.dens:
		if not sim.explored_at(p):
			den = p
			break
	if den.x < 0:
		_fail("no unexplored den for the knowledge test")
		return
	sim._stamp_explored(den, 1.0)
	if not sim.hero_goal_scores(warrior).has("smite"):
		_fail("charted den not considered once known")
	# A dropped purse in unexplored wilds is no treasure until charted.
	var rogue = _add_hero(sim, "rogue", sim.keep_pos)
	var far: Vector2i = sim.keep_pos + Vector2i(14, 10)
	if not sim.explored_at(far):
		sim.loot_piles[far] = 50
		if sim.hero_goal_scores(rogue).has("treasure"):
			_fail("rogue chased loot hidden in fog")
		sim._stamp_explored(far, 1.0)
		if not sim.hero_goal_scores(rogue).has("treasure"):
			_fail("charted loot not considered once known")

func _test_hero_explores() -> void:
	# With no venture on the books and wilds left, a hero charts the
	# frontier some of the time (a coin-flip against patrolling).
	var sim = _make_sim(5)
	sim.raids_enabled = false
	sim.heroes_enabled = true # decision loop runs under this flag...
	sim.hero_arrival_chance = 0.0 # ...but no extra heroes wander in
	var before: int = sim.tiles_explored
	var h = _add_hero(sim, "paladin", sim.keep_pos)
	h.decision_left = 0
	for i in 300:
		sim.update()
		if sim.tiles_explored > before + 20:
			break
	if sim.tiles_explored <= before + 20:
		_fail("idle hero never explored: %d -> %d" % [before, sim.tiles_explored])
	if not sim.explored_at(h.tile()):
		_fail("hero stood in ground it never charted")

func _test_perf_budget() -> void:
	# Headless frame-budget check: a full economy (raiders and heroes on,
	# fog stamping every tick) must keep ticking well inside a frame's
	# budget even with lots of ground charted.
	var sim = _make_sim(5)
	sim.set_fog_enabled(false)
	sim.gold = 10000
	sim.raids_enabled = true
	sim.heroes_enabled = true
	var spots := [
		sim.keep_pos + Vector2i(1, 1), sim.keep_pos + Vector2i(-1, 1),
		sim.keep_pos + Vector2i(1, -1), sim.keep_pos + Vector2i(-1, -1),
	]
	sim.build_at("farm", spots[0])
	sim.build_at("farm", spots[1])
	sim.build_at("house", spots[2])
	sim.build_at("guardhouse", spots[3])
	sim.set_fog_enabled(true)
	for i in 200:
		sim.update()
	var ticks := 800
	var t0 := Time.get_ticks_usec()
	for i in ticks:
		sim.update()
	var per_tick_ms := (Time.get_ticks_usec() - t0) / float(ticks) / 1000.0
	print("perf: %.3f ms/tick avg (fog on, %d agents, %d/%d explored)" \
		% [per_tick_ms, sim.agents.size(), sim.tiles_explored, sim.explored.size()])
	# The Pi budget: the whole tick must stay well under one frame (16.6ms);
	# headless timing runs faster than a Pi, so allow generous headroom.
	if per_tick_ms > 10.0:
		_fail("tick too slow for the Pi budget: %.2f ms" % per_tick_ms)
