extends SceneTree

# M6.1 ecology tests: seeded wild lairs on the right ground, prey regrowth,
# the hunt chain (wolves → warrens, spiders → goblin dens), den needs —
# migration vs starvation — and the realm gating (no building or bounty on
# wild dens, heroes smite only dens of evil). Ends with a long-run sim and
# a headless tick budget with everything running.

var failed := false

func _initialize() -> void:
	_test_seeded_lairs()
	_test_prey_regrowth()
	_test_wolf_hunt_chain()
	_test_spider_chain()
	_test_wolf_migration()
	_test_starvation()
	_test_prey_migration()
	_test_gating()
	_test_hero_gating()
	_test_creatures_reveal_nothing()
	_test_fog_discovery()
	_test_long_run()
	_test_perf_budget()
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)

func _make_sim(seed_value: int, fog_on := false):
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(seed_value)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.wild_ecology = true # this is the ecology suite
	sim.attach_world(WorldC)
	if not fog_on:
		sim.set_fog_enabled(false) # deterministic accounting without fog gates
	sim.keep_trickle = 0 # exact gold accounting; trickle has its own check
	sim.heroes_enabled = false # hero hunts would thin the staged warrens
	return sim

func _wild_dens(sim) -> Dictionary:
	var out := {}
	for p in sim.dens:
		if sim.dens[p].get("kind", "goblin_den") != "goblin_den":
			out[p] = sim.dens[p]
	return out

func _dens_of_kind(sim, kind_key: String) -> Array:
	var out := []
	for p in sim.dens:
		if sim.dens[p].get("kind", "") == kind_key:
			out.append(p)
	return out

func _creatures(sim) -> Array:
	var out := []
	for a in sim.agents:
		if a.kind == "creature":
			out.append(a)
	return out

func _count(sim, kind: String) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == kind:
			n += 1
	return n

func _quiet_wilds(sim) -> void:
	# Freeze regrowth and migration for tests that stage their own dens.
	sim.wild_spawn_chance = 0.0
	sim.wild_respawn_rest_left = 999999

func _test_seeded_lairs() -> void:
	var sim = _make_sim(301)
	var wild := _wild_dens(sim)
	if wild.is_empty():
		_fail("no wild dens seeded")
		return
	var warrens := _dens_of_kind(sim, "rabbit_warren")
	var wolves := _dens_of_kind(sim, "wolf_den")
	if warrens.is_empty() or wolves.is_empty():
		_fail("starting wilds lack a warren or a wolf den: %s" % [wild.keys()])
		return
	for p in wild:
		var row = sim.DEN_KINDS[sim.dens[p].kind]
		var want: int = sim.world.GRASS if row.site == "grass" else sim.world.FOREST
		if sim.world.get_terrain(p) != want:
			_fail("wild den %s squatting on wrong terrain" % p)
		if Vector2(p).distance_to(Vector2(sim.keep_pos)) < 8:
			_fail("wild den %s too close to the keep" % p)
		for b in sim.buildings:
			if Vector2(b).distance_to(Vector2(p)) < 4:
				_fail("wild den %s too close to a building" % p)
				break
	var home: Vector2i = wolves[0]
	var pack := 0
	for a in _creatures(sim):
		if a.home == home and a.species == "wolf":
			pack += 1
	if pack < 1:
		_fail("wolf den has no wolves")

func _test_prey_regrowth() -> void:
	var sim = _make_sim(303)
	_quiet_wilds(sim)
	var warren: Vector2i = _dens_of_kind(sim, "rabbit_warren")[0]
	sim.dens[warren].food = 0
	var grew := false
	for i in 200:
		sim.update()
		if int(sim.dens[warren].food) > 0:
			grew = true
			break
	if not grew:
		_fail("prey larder never regrew from the land")

func _test_wolf_hunt_chain() -> void:
	# Rabbits → wolves: a hungry pack hunts the warren and hauls the kill
	# home to its own larder.
	var sim = _make_sim(307)
	_quiet_wilds(sim)
	var wolves: Array = _dens_of_kind(sim, "wolf_den")
	var warrens: Array = _dens_of_kind(sim, "rabbit_warren")
	if wolves.is_empty() or warrens.is_empty():
		_fail("chain test lacks its dens")
		return
	var wd: Vector2i = wolves[0]
	var warren: Vector2i = warrens[0]
	# Goblins forage concurrently and muddy den accounting; clear them out
	# (no new musters at this pacing) so only the wolf chain moves stores.
	for a in sim.agents.duplicate():
		if a.kind == "goblin":
			sim.agents.erase(a)
	sim.dens[wd].food = 1
	sim.dens[warren].food = 6
	var saw_hunt := false
	for i in 400:
		sim.update()
		for a in sim.agents:
			if a.kind == "creature" and a.purpose == "hunt":
				saw_hunt = true
		if int(sim.dens[wd].food) > 1:
			break
	if not saw_hunt:
		_fail("wolf pack never stalked its prey")
	if int(sim.dens[wd].food) <= 1:
		_fail("the kill never reached the wolf den's larder")
	if sim.hunts_made < 1:
		_fail("hunt not accounted")

func _test_spider_chain() -> void:
	# Goblins → giant spiders: the nest snares a goblin den's stores.
	var sim = _make_sim(309)
	_quiet_wilds(sim)
	sim.den_muster_ticks = 100000 # no new goblins during the window
	var gobs: Array = _dens_of_kind(sim, "goblin_den")
	if gobs.is_empty():
		_fail("no goblin den to prey on")
		return
	var gd: Vector2i = gobs[0]
	sim.dens[gd].food = 8
	for a in sim.agents.duplicate():
		if a.kind == "goblin":
			sim.agents.erase(a)
	# A forest tile within reach of the goblin den, or any forest at all.
	var site := Vector2i(-1, -1)
	var door: Vector2i = sim.den_doorstep(gd, sim.keep_pos)
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var q: Vector2i = door + Vector2i(dx, dy)
			if sim.world.in_bounds(q) and sim.world.get_terrain(q) == sim.world.FOREST \
					and not sim.dens.has(q) and not sim.buildings.has(q):
				site = q
				break
		if site.x >= 0:
			break
	if site.x < 0:
		_fail("no forest tile for the spider nest")
		return
	sim._place_wild_den("spider_den", site)
	var nest: Vector2i = site
	sim.dens[nest].food = 1
	var saw_hunt := false
	for i in 400:
		sim.update()
		for a in sim.agents:
			if a.kind == "creature" and a.purpose == "hunt":
				saw_hunt = true
		# Wait out the whole round trip: the strike alone is not supper.
		if int(sim.dens[nest].food) > 1:
			break
	if not saw_hunt:
		_fail("spider never stalked the goblin den")
	if int(sim.dens[gd].food) >= 8:
		_fail("goblin den's stores never raided by the spider")
	if int(sim.dens[nest].food) <= 1:
		_fail("the snared supper never fed the spider nest")

func _test_wolf_migration() -> void:
	# Warrens gone: the pack follows its fallback — toward the farm stores.
	var sim = _make_sim(311)
	_quiet_wilds(sim)
	sim.den_migrate_ticks = 10
	sim.den_muster_ticks = 100000
	var warrens: Array = _dens_of_kind(sim, "rabbit_warren")
	for w in warrens:
		sim.dens.erase(w)
	var wolves: Array = _dens_of_kind(sim, "wolf_den")
	if wolves.is_empty():
		_fail("no wolf den for migration test")
		return
	var wd: Vector2i = wolves[0]
	sim.build_at("farm", sim.keep_pos + Vector2i(1, 1))
	for i in 80:
		sim.update()
		if sim.buildings[sim.keep_pos + Vector2i(1, 1)].complete:
			break
	sim.dens[wd].food = 0
	var migrated := false
	for i in 200:
		sim.update()
		if sim.dens_migrated > 0:
			migrated = true
			break
	if not migrated:
		_fail("starving wolf pack never moved on")
		return
	var still := _dens_of_kind(sim, "wolf_den")
	if still.size() != 1 or still[0] == wd:
		_fail("wolf den migration did not relocate the den")
	for p in still:
		var row = sim.DEN_KINDS[sim.dens[p].kind]
		var want: int = sim.world.GRASS if row.site == "grass" else sim.world.FOREST
		if sim.world.get_terrain(p) != want:
			_fail("migrated den squats on wrong terrain")
	for a in sim.agents:
		if a.kind == "creature" and a.species == "wolf" and not sim.dens.has(a.home):
			_fail("wolf still homed to the abandoned den")

func _test_starvation() -> void:
	# A spider nest with no goblin dens left has nowhere to move: it starves
	# out of the wilds, and its nest-mates with it.
	var sim = _make_sim(313)
	_quiet_wilds(sim)
	sim.den_migrate_ticks = 10
	sim.den_muster_ticks = 100000
	var gobs: Array = _dens_of_kind(sim, "goblin_den")
	for g in gobs:
		sim.dens.erase(g)
	for a in sim.agents.duplicate():
		if a.kind == "goblin":
			sim.agents.erase(a)
	var spiders: Array = _dens_of_kind(sim, "spider_den")
	if spiders.is_empty():
		# Regrow one by hand at a far forest tile.
		var site: Vector2i = sim._wild_den_site("spider_den")
		if site.x < 0:
			_fail("no site to stage a spider nest")
			return
		sim._place_wild_den("spider_den", site)
		spiders = _dens_of_kind(sim, "spider_den")
	var nest: Vector2i = spiders[0]
	var nestmates := 0
	for a in _creatures(sim):
		if a.home == nest:
			nestmates += 1
	sim.dens[nest].food = 0
	var starved := false
	for i in 200:
		sim.update()
		if sim.dens_starved > 0:
			starved = true
			break
	if not starved:
		_fail("doomed nest never starved out")
		return
	if sim.dens.has(nest):
		_fail("starved nest still on the map")
	if _creatures(sim).size() > 0:
		var orphaned := false
		for a in _creatures(sim):
			if a.home == nest:
				orphaned = true
		if orphaned:
			_fail("creatures outlived their starved nest")

func _test_prey_migration() -> void:
	# A grazed-out warren seeks fresh meadows (regrowth off for the test).
	var sim = _make_sim(317)
	_quiet_wilds(sim)
	sim.den_migrate_ticks = 10
	sim.prey_regrow_ticks = 1000000
	var warren: Vector2i = _dens_of_kind(sim, "rabbit_warren")[0]
	sim.dens[warren].food = 0
	var migrated := false
	for i in 200:
		sim.update()
		if sim.dens_migrated > 0:
			migrated = true
			break
	if not migrated:
		_fail("grazed-out warren never moved on")
		return
	var still := _dens_of_kind(sim, "rabbit_warren")
	if still.size() != 1 or still[0] == warren:
		_fail("warren migration did not relocate")
	for p in still:
		if sim.world.get_terrain(p) != sim.world.GRASS:
			_fail("warren migrated off the meadows")

func _test_gating() -> void:
	# The realm does not build on warrens and does not bounty wild lairs.
	var sim = _make_sim(319)
	var warren: Vector2i = _dens_of_kind(sim, "rabbit_warren")[0]
	if sim.can_build_at(warren):
		_fail("build allowed on a wild den tile")
	var gold_before: int = sim.gold
	if sim.build_at("house", warren):
		_fail("built over a warren")
	if sim.gold != gold_before:
		_fail("failed build still charged gold")
	if sim.last_event != "Wild beasts den there":
		_fail("wrong blocked-build wording: %s" % sim.last_event)
	if sim.post_bounty(warren):
		_fail("bounty posted on a wild lair")
	if sim.gold != gold_before:
		_fail("failed bounty still charged gold")
	if sim.bounties.has(warren):
		_fail("wild lair carries a bounty flag")
	# Smite targets stay dens of evil even when a wild lair is closer.
	var nearest = sim._nearest_den(warren)
	if nearest.x < 0 or sim.dens[nearest].get("kind", "") != "goblin_den":
		_fail("smite targeting picked a wild lair")

func _test_hero_gating() -> void:
	# A paladin's incentive table must read wild lairs as no smiting matter.
	var sim = _make_sim(321)
	sim._spawn_hero("paladin")
	var pal = null
	for a in sim.agents:
		if a.kind == "hero" and a.hero_class == "paladin":
			pal = a
	if pal == null:
		_fail("paladin not spawned for gating test")
		return
	var scores: Dictionary = sim.hero_goal_scores(pal)
	if scores.has("smite"):
		var expected := 9 # smite_evil weight + the den's level of at least 1
		var top := 1
		for p in sim.dens:
			if sim.is_hostile_den(p):
				top = maxi(top, int(sim.dens[p].level))
		expected = int(sim.HERO_CLASSES.paladin.weights.smite_evil) + top
		if int(scores["smite"]) != expected:
			_fail("smite score polluted by wild lairs: %d vs %d"
				% [scores["smite"], expected])
	elif not _dens_of_kind(sim, "goblin_den").is_empty():
		_fail("smite option missing though dens of evil exist")

func _test_creatures_reveal_nothing() -> void:
	# The wild keeps its secrets: wolves and rabbits roam all they like,
	# but only the realm's folk chart the map — goblins and wild creatures
	# reveal nothing.
	var sim = _make_sim(331, true)
	var before: int = sim.tiles_explored
	for i in 400:
		sim.update()
	if sim.tiles_explored != before:
		_fail("wild creatures charted ground: %d -> %d"
			% [before, sim.tiles_explored])
	if _creatures(sim).is_empty():
		_fail("no wild creatures roaming in the reveal test")

func _test_fog_discovery() -> void:	# A roaming hero lights a wild lair up as a landmark of its own kind.
	var sim = _make_sim(323, true)
	var warren: Vector2i = _dens_of_kind(sim, "rabbit_warren")[0]
	if sim.explored_at(warren):
		_fail("warren already charted from the keep")
		return
	var AgentC = load("res://scripts/agents.gd")
	var h = AgentC.new()
	h.setup(sim, "hero", warren)
	h.hero_class = "rogue"
	h.max_hp = 10
	h.hp = h.max_hp
	h.home = sim.keep_pos
	sim.agents.append(h)
	var before: int = sim.landmarks_spotted
	var spotted := false
	for i in 5:
		sim.update()
		# A same-tick neighbour sighting can overwrite the event text, so
		# any landmark discovery wording counts.
		if sim.landmarks_spotted > before and sim.last_event.contains("is spied"):
			spotted = true
			break
	if not spotted:
		_fail("charting the warren raised no landmark")
	if not sim.explored_at(warren):
		_fail("warren ground never charted")

func _test_long_run() -> void:
	# ~10 game years with raids AND ecology on: the realm and the wilds both
	# keep running, nothing wedges, nothing goes negative. Heroes are out —
	# their own suite covers them, and here they would clear the goblin
	# dens long before the window ends.
	var sim = _make_sim(327)
	sim.heroes_enabled = false
	for p in sim.dens:
		sim.dens[p].hp = 999
	var spots := [
		sim.keep_pos + Vector2i(1, 1),
		sim.keep_pos + Vector2i(-1, 1),
		sim.keep_pos + Vector2i(1, -1),
		sim.keep_pos + Vector2i(-1, -1),
	]
	sim.gold = 100
	sim.build_at("farm", spots[0])
	sim.build_at("farm", spots[1])
	sim.build_at("house", spots[2])
	sim.build_at("guardhouse", spots[3])
	for i in 100:
		sim.update()
	var raids_mid: int = sim.raids_launched
	var hunts_mid: int = sim.hunts_made
	for i in 2600:
		sim.update()
	if sim.raids_launched == raids_mid:
		_fail("no raids in long run")
	var ecology_moves: int = sim.hunts_made - hunts_mid + sim.dens_migrated \
		+ sim.dens_starved + sim.wild_dens_spawned
	if ecology_moves <= 0:
		_fail("ecology never moved in the long run")
	if sim.pop < 1:
		_fail("total extinction in long run")
	if sim.gold < 0:
		_fail("negative gold in long run")
	for p in sim.dens:
		if int(sim.dens[p].food) < 0 or int(sim.dens[p].gold) < 0:
			_fail("negative den stores at %s" % p)
		if not sim.DEN_KINDS.has(sim.dens[p].get("kind", "")):
			_fail("den with unknown kind at %s" % p)
	var valid_states := ["idle", "to_target", "acting", "returning", "fleeing"]
	for a in sim.agents:
		if not sim.world.in_bounds(a.tile()):
			_fail("agent out of bounds at %s" % a.tile())
		if not valid_states.has(a.state):
			_fail("bad agent state: %s" % a.state)
		if a.state == "acting" and a.work_left < 0:
			_fail("agent stuck acting")
		if a.kind == "creature" and not sim.dens.has(a.home):
			_fail("creature homed to a vanished den at %s" % a.tile())

func _test_perf_budget() -> void:
	# Headless frame-budget check: full economy (raids, heroes, ecology and
	# fog stamping all on) must keep ticking well inside a frame.
	var sim = _make_sim(329, true)
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
	for i in 200:
		sim.update()
	var ticks := 800
	var t0 := Time.get_ticks_usec()
	for i in ticks:
		sim.update()
	var per_tick_ms := (Time.get_ticks_usec() - t0) / float(ticks) / 1000.0
	print("perf: %.3f ms/tick avg (ecology on, %d agents, %d dens)" \
		% [per_tick_ms, sim.agents.size(), sim.dens.size()])
	# The Pi budget: the whole tick must stay well under one frame (16.6ms);
	# headless timing runs faster than a Pi, so allow generous headroom.
	if per_tick_ms > 10.0:
		_fail("tick budget blown with ecology on: %.2f ms" % per_tick_ms)
