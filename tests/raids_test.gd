extends SceneTree

# M3 raid tests: den placement, the den mood machine (weighted lurk/prowl/
# forage/raid with durations and post-raid rest), goblin behavior states,
# razes (soft-fail recovery), den growth on successful raids, guard
# spawning/interception, den clearing, and a long-run sim without deadlock
# or extinction.

var failed := false

func _initialize() -> void:
	_test_dens_spawned()
	_test_raid_pacing()
	_test_goblin_behaviors()
	_test_raid_razes_and_recovery()
	_test_den_growth()
	_test_guards_spawn_and_intercept()
	_test_combat_interrupts_behavior()
	_test_guard_leash_and_no_siege()
	_test_guard_respawn()
	_test_den_respawn()
	_test_long_run()
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
	return sim

# Bias the den to raid as soon as its mood expires; speed up musters. The
# long rest must span the whole march so "one raid at a time" holds.
func _raid_only(sim) -> void:
	sim.den_intent_weights = {"lurk": 0, "prowl": 0, "forage": 0, "raid": 100}
	sim.den_raid_rest = 200
	sim.den_muster_ticks = 5

func _only_den(sim) -> void:
	var keep: Vector2i = sim.dens.keys()[0]
	for p in sim.dens.keys():
		if p != keep:
			sim.dens.erase(p)

func _count(sim, kind: String) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == kind:
			n += 1
	return n

func _count_raiders(sim) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == "goblin" and a.purpose == "raid":
			n += 1
	return n

func _build_farm(sim, spot: Vector2i = Vector2i(-99, -99)) -> Vector2i:
	var farm: Vector2i = spot if spot.x > -90 else sim.keep_pos + Vector2i(1, 1)
	sim.build_at("farm", farm)
	for i in 60:
		sim.update()
		if sim.buildings[farm].complete:
			break
	if not sim.buildings[farm].complete:
		_fail("farm never completed at %s" % farm)
	return farm

func _test_dens_spawned() -> void:
	var sim = _make_sim(101)
	if sim.dens.is_empty():
		_fail("no dens spawned on mountain edges")
		return
	for p in sim.dens:
		if sim.world.get_terrain(p) != 3:
			_fail("den not on mountain at %s" % p)
		if int(sim.dens[p].level) < 1 or int(sim.dens[p].hp) <= 0:
			_fail("den at %s has bad level/hp" % p)
		if int(sim.dens[p].food) <= 0:
			_fail("den at %s starts with no provisions" % p)
		if sim.dens[p].intent == "":
			_fail("den at %s has no initial mood" % p)
		# The den must have a way down into the realm.
		var door: Vector2i = sim.den_doorstep(p, sim.keep_pos)
		if door == p:
			_fail("den at %s has no walkable doorstep" % p)
	if _count(sim, "goblin") != 0:
		_fail("goblins should muster over time, not at world creation")

func _test_raid_pacing() -> void:
	var sim = _make_sim(103)
	_raid_only(sim)
	_build_farm(sim)
	var saw_raid := false
	for i in 300:
		sim.update()
		if _count_raiders(sim) > 0:
			saw_raid = true
			# While a den's own raiders are out, it must be resting — no
			# second warband from the same den.
			for p in sim.dens:
				var out := 0
				for a in sim.agents:
					if a.kind == "goblin" and a.home == p and a.purpose == "raid":
						out += 1
				if out > 0 and sim.dens[p].intent != "rest":
					_fail("den %s raided without entering its rest mood" % p)
					return
	if not saw_raid:
		_fail("no raid launched under raid-only mood bias")
		return
	# Give the warband time to come home before judging.
	for i in 300:
		sim.update()
		if _count_raiders(sim) == 0:
			break
	var raiders_left := _count_raiders(sim)
	if raiders_left != 0:
		_fail("raiders never came home: %d still out" % raiders_left)

func _test_goblin_behaviors() -> void:
	# Default weights: over a long window the den must show every mood, and
	# individual goblins must be seen in personal states.
	var sim = _make_sim(107)
	_build_farm(sim)
	var moods := {}
	var behaviors := {}
	var max_food := 0
	for i in 900:
		sim.update()
		for p in sim.dens:
			max_food = maxi(max_food, int(sim.dens[p].food))
			if sim.dens[p].intent == "rest":
				moods["rest"] = true
		for k in sim.intents_seen:
			moods[k] = true
		for a in sim.agents:
			if a.kind == "goblin":
				behaviors[a.behavior] = true
	# The raid mood shows up in intents_seen the moment it is rolled; the
	# den's live intent flips straight to "rest" while the warband is out.
	for m in ["lurk", "prowl", "forage", "raid", "rest"]:
		if not moods.has(m):
			_fail("den mood %s never occurred in 900 ticks (seen %s)" % [m, moods.keys()])
	for b in ["lurk", "wander", "prowl", "forage"]:
		if not behaviors.has(b):
			_fail("goblin behavior %s never occurred (seen %s)" % [b, behaviors.keys()])
	# Hungry dens must actually attack, not just skulk: with default weights
	# a live raid must happen within the window.
	if sim.raids_launched == 0:
		_fail("no raid ever launched under default hunger weights")
	# Foraging must actually stock the den's larder at least once.
	if max_food <= 8:
		_fail("foragers never added to the den's provisions (max food %d)" % max_food)

func _test_raid_razes_and_recovery() -> void:
	var sim = _make_sim(109)
	_raid_only(sim)
	sim.goblin_hp = 99
	var farm: Vector2i = _build_farm(sim)
	if sim.farms != 1:
		_fail("farm not ready for raze test")
		return
	for i in 400:
		sim.update()
		if not sim.buildings.has(farm):
			break
	if sim.buildings.has(farm):
		_fail("farm never razed by warband")
	else:
		if sim.farms != 0:
			_fail("farm count not decremented on raze")
		if not sim.can_build_at(farm):
			_fail("razed tile not rebuildable")
		if sim.buildings_razed < 1:
			_fail("raze not accounted")
		# Wait for the warband to finish its business and go home.
		sim.shortage_grace = 10000
		for i in 300:
			sim.update()
			if _count_raiders(sim) == 0:
				break
		# Recovery: rebuild the farm; economy resumes.
		sim.gold = 100
		if not sim.build_at("farm", farm):
			_fail("rebuild on razed tile refused")
		for i in 80:
			sim.update()
			if sim.buildings.has(farm) and sim.buildings[farm].complete:
				break
		if not (sim.buildings.has(farm) and sim.buildings[farm].complete):
			_fail("farm never rebuilt after raze")

func _test_den_growth() -> void:
	var sim = _make_sim(131)
	_raid_only(sim)
	sim.goblin_hp = 99
	_build_farm(sim)
	var levels := {}
	for p in sim.dens:
		levels[p] = int(sim.dens[p].level)
	var grew := false
	for i in 500:
		sim.update()
		for p in sim.dens:
			if int(sim.dens[p].level) > levels.get(p, 0):
				grew = true
				break
		if grew:
			break
	if not grew:
		_fail("successful raid did not grow any den")

func _test_guards_spawn_and_intercept() -> void:
	var sim = _make_sim(137)
	# Strong guards (set before the guardhouse spawns them) must repel raids.
	sim.guard_hp = 99
	sim.goblin_hp = 2
	_raid_only(sim)
	var gh1: Vector2i = sim.keep_pos + Vector2i(1, 1)
	var gh2: Vector2i = sim.keep_pos + Vector2i(-1, -1)
	sim.gold = 100
	sim.build_at("guardhouse", gh1)
	sim.build_at("guardhouse", gh2)
	for i in 60:
		sim.update()
		if sim.buildings.has(gh1) and sim.buildings[gh1].complete \
				and sim.buildings.has(gh2) and sim.buildings[gh2].complete:
			break
	if not (sim.buildings.has(gh1) and sim.buildings[gh1].complete \
			and sim.buildings.has(gh2) and sim.buildings[gh2].complete):
		_fail("guardhouse never completed")
		return
	if _count(sim, "guard") != 2 * sim.GUARDS_PER_GUARDHOUSE:
		_fail("guardhouse did not spawn guards")
	# Keep a single den: two dens raiding in sync are meant to overwhelm
	# even a strong watch; that pressure belongs to the long-run test.
	_only_den(sim)
	_build_farm(sim, sim.keep_pos + Vector2i(2, 2))
	var saw_intercept := false
	for i in 600:
		sim.update()
		for a in sim.agents:
			if a.kind == "guard" and a.purpose == "intercept":
				saw_intercept = true
				break
	if not saw_intercept:
		_fail("guards never moved to intercept")
	# With strong guards, no building should survive razed.
	if sim.buildings_razed > 0:
		_fail("guards failed to protect buildings: razed=%d" % sim.buildings_razed)

func _test_combat_interrupts_behavior() -> void:
	var sim = _make_sim(139)
	var gh: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("guardhouse", gh)
	for i in 60:
		sim.update()
		if sim.buildings.has(gh) and sim.buildings[gh].complete:
			break
	# Put a goblin mid-walk next to a guard: it must stop and fight, then
	# resume once the threat is gone.
	var a = load("res://scripts/agents.gd").new()
	a.setup(sim, "goblin", gh)
	a.home = sim.dens.keys()[0]
	sim.agents.append(a)
	# Keep the test goblin out of the flee/behavior machinery: pinned in
	# place, unkillable, so only the interrupt logic is under test.
	a.hp = 99
	a.max_hp = 99
	a.assign(gh, "wander")
	a.behavior_left = 999
	for i in 60:
		sim.update()
		if a.tile() == gh:
			break
	if a.tile() != gh:
		_fail("goblin never wandered to the guard")
	var guard_ref = null
	for g in sim.agents:
		if g.kind == "guard":
			guard_ref = g
	if guard_ref == null:
		_fail("no guard present for interrupt test")
		return
	# Park a single guard next to the goblin and freeze both.
	for g in sim.agents:
		if g.kind == "guard" and g != guard_ref:
			g.hp = 0
	sim.update() # reap the extras
	guard_ref.state = "idle"
	guard_ref.purpose = ""
	guard_ref.pos = Vector2(gh) + Vector2(0.5, 0.5)
	guard_ref.path = []
	guard_ref.hp = 99
	guard_ref.max_hp = 99
	a.state = "idle"
	a.purpose = ""
	a.path = []
	a.pos = Vector2(gh) + Vector2(1.5, 0.5) # adjacent, not same tile
	a.fighting = false
	a.behavior_left = 999
	sim.update()
	if not a.fighting:
		_fail("goblin did not switch to fighting under attack")
	var hp_before: int = a.hp
	sim.update()
	sim.update()
	if a.hp >= hp_before:
		_fail("fighting goblin took no damage")
	# Remove the guard: the goblin should disengage.
	for g in sim.agents:
		if g.kind == "guard":
			g.hp = 0
	sim.update()
	sim.update()
	if a.fighting:
		_fail("goblin kept fighting with no guard nearby")

func _test_guard_leash_and_no_siege() -> void:
	# Guards defend the settlement: they chase raiders inside the leash,
	# never storm dens (that is hero work) and never stray into the wilds.
	var sim = _make_sim(149)
	sim.guard_hp = 99
	sim.goblin_hp = 2
	_raid_only(sim)
	var gh: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("guardhouse", gh)
	for i in 60:
		sim.update()
		if sim.buildings.has(gh) and sim.buildings[gh].complete:
			break
	var den_pos: Vector2i = sim.dens.keys()[0]
	_only_den(sim)
	_build_farm(sim, sim.keep_pos + Vector2i(2, 2))
	for i in 1200:
		sim.update()
		for a in sim.agents:
			if a.kind == "guard" \
					and Vector2(a.tile()).distance_to(Vector2(sim.keep_pos)) \
						> sim.GUARD_LEASH + 4.0:
				_fail("guard strayed beyond the leash at %s" % a.tile())
				return
	if sim.dens_cleared > 0:
		_fail("guards stormed the den; that is hero work")
	if not sim.dens.has(den_pos):
		_fail("den vanished without being cleared properly")
	if sim.buildings_razed > 0:
		_fail("guards failed to protect buildings: razed=%d" % sim.buildings_razed)

func _test_guard_respawn() -> void:
	var sim = _make_sim(163)
	var gh: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("guardhouse", gh)
	for i in 60:
		sim.update()
		if sim.buildings.has(gh) and sim.buildings[gh].complete:
			break
	if _count(sim, "guard") != sim.GUARDS_PER_GUARDHOUSE:
		_fail("guardhouse did not staff up")
		return
	sim.guard_retrain_ticks = 20
	var dead = null
	for a in sim.agents:
		if a.kind == "guard":
			dead = a
			break
	dead.hp = 0
	sim.update() # reap
	if _count(sim, "guard") != sim.GUARDS_PER_GUARDHOUSE - 1:
		_fail("guard did not die in respawn test")
		return
	var back := false
	for i in 200:
		sim.update()
		if _count(sim, "guard") == sim.GUARDS_PER_GUARDHOUSE:
			back = true
			break
	if not back:
		_fail("guardhouse never re-trained a fallen guard")

func _test_den_respawn() -> void:
	# A cleared den buys peace, but the wild regrows lairs from time to
	# time — never above the cap, never on civilization's doorstep.
	var sim = _make_sim(167)
	sim.den_respawn_rest = 50
	var before: int = sim.dens.size()
	var pre := {}
	for p in sim.dens:
		pre[p] = true
	var doomed: Vector2i = sim.dens.keys()[0]
	sim._clear_den(doomed)
	if sim.dens.size() != before - 1:
		_fail("den not cleared in respawn test")
		return
	var respawned := false
	var new_pos := Vector2i(-1, -1)
	for i in 3000:
		sim.update()
		if sim.dens_spawned > 0:
			for p in sim.dens:
				if not pre.has(p):
					new_pos = p
					respawned = true
			if respawned:
				break
	if not respawned:
		_fail("cleared den never regrew in 3000 ticks")
		return
	var den: Dictionary = sim.dens[new_pos]
	if int(den.level) != 1 or int(den.hp) <= 0:
		_fail("respawned den not fresh at %s" % new_pos)
	var door: Vector2i = sim.den_doorstep(new_pos, sim.keep_pos)
	if Vector2(door).distance_to(Vector2(sim.keep_pos)) < sim.DEN_WILD_MIN:
		_fail("respawned den too close to the keep at %s" % new_pos)
	for p in sim.buildings:
		if Vector2(p).distance_to(Vector2(door)) < sim.DEN_CIV_CLEARANCE \
				and p != sim.keep_pos:
			_fail("respawned den too close to building at %s" % p)
			break

func _test_long_run() -> void:
	# ~10 game years with default pacing: raids must fire, the den must show
	# a varied life, realm must survive, nothing may wedge. Dens are made
	# effectively un-clearable so the wild half of the ecology persists.
	var sim = _make_sim(151)
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
	for i in 2600:
		sim.update()
	if sim.raids_launched == raids_mid:
		_fail("no raids in long run")
	if not sim.intents_seen.has("raid"):
		_fail("den never picked the raid mood")
	var moods := 0
	for k in sim.intents_seen:
		moods += 1
	if moods < 3:
		_fail("den mood machine too one-dimensional: %s" % sim.intents_seen.keys())
	if sim.pop < 1:
		_fail("total extinction in long run")
	if sim.gold < 0:
		_fail("negative gold in long run")
	if sim.farms < 0 or sim.houses < 0:
		_fail("negative building counts")
	for p in sim.dens:
		if int(sim.dens[p].food) < 0 or int(sim.dens[p].gold) < 0:
			_fail("negative den stores")
	var valid_states := ["idle", "to_target", "acting", "returning", "fleeing"]
	for a in sim.agents:
		if not sim.world.in_bounds(a.tile()):
			_fail("agent out of bounds at %s" % a.tile())
		if not valid_states.has(a.state):
			_fail("bad agent state: %s" % a.state)
		if a.state == "acting" and a.work_left < 0:
			_fail("agent stuck acting")
	for p in sim.buildings:
		if not sim.buildings[p].complete:
			_fail("stuck construction site at %s" % p)
