extends SceneTree

# M4 hero tests: attraction mix vs. building mix, hero arrival at the hall
# that drew them, the incentive scoring table snapshot (the indirect-control
# core), the fight/rest/shop hero loop, bounty posting and claims, death
# dropping loot that rogues race to, and a long run without deadlock.

var failed := false

func _initialize() -> void:
	_test_attraction_mix()
	_test_hero_arrival()
	_test_incentive_snapshot()
	_test_shop_and_rest_loop()
	_test_hero_combat_and_levels()
	_test_bounty_flow()
	_test_death_drops_loot()
	_test_loot_pickup()
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
	sim.set_fog_enabled(false) # hero accounting without fog gates
	sim.keep_trickle = 0 # exact gold accounting; trickle has its own check
	return sim

func _count(sim, kind: String) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == kind:
			n += 1
	return n

func _heroes(sim) -> Array:
	var out := []
	for a in sim.agents:
		if a.kind == "hero":
			out.append(a)
	return out

func _build(sim, kind: String, spot: Vector2i) -> bool:
	sim.gold = maxi(sim.gold, 200)
	if not sim.build_at(kind, spot):
		_fail("build %s at %s refused" % [kind, spot])
		return false
	for i in 60:
		sim.update()
		if sim.buildings.has(spot) and sim.buildings[spot].complete:
			return true
	_fail("%s never completed at %s" % [kind, spot])
	return false

func _force_arrival(sim, cls: String):
	# Speed the attraction roll up and make it certain.
	sim.hero_arrival_chance = 1.0
	sim._hero_attraction_left = 1
	for i in 30:
		sim.update()
		if _count(sim, "hero") > 0:
			break
	for h in _heroes(sim):
		if h.hero_class == cls:
			return h
	_fail("%s never arrived via attraction" % cls)
	return null

func _spawn_at(sim, cls: String, pos: Vector2i):
	# Direct spawn for controlled scenarios; teleport past the border walk.
	sim._spawn_hero(cls)
	var hs := _heroes(sim)
	if hs.is_empty():
		_fail("hero spawn failed for %s" % cls)
		return null
	var h = hs[hs.size() - 1]
	h.pos = Vector2(pos) + Vector2(0.5, 0.5)
	h.state = "idle"
	h.purpose = ""
	h.path = []
	h.decision_left = 0
	return h

func _only_den(sim) -> void:
	var keep: Vector2i = sim.dens.keys()[0]
	for p in sim.dens.keys():
		if p != keep:
			sim.dens.erase(p)

func _test_attraction_mix() -> void:
	var sim = _make_sim(201)
	sim.raids_enabled = false
	if not _build(sim, "tavern", sim.keep_pos + Vector2i(1, 1)):
		return
	var mix: Dictionary = sim._attraction_mix()
	if mix.size() != 1 or int(mix.get("rogue", 0)) != 1:
		_fail("tavern-only mix wrong: %s" % mix)
	if not _build(sim, "shrine", sim.keep_pos + Vector2i(2, 2)):
		return
	mix = sim._attraction_mix()
	if int(mix.get("rogue", 0)) != 1 or int(mix.get("paladin", 0)) != 1:
		_fail("tavern+shrine mix wrong: %s" % mix)
	# Incomplete buildings must not attract anyone yet.
	sim.gold = 200
	sim.build_at("market", sim.keep_pos + Vector2i(3, 3))
	if sim._attraction_mix().has("warrior"):
		_fail("unfinished building attracted a class")

func _test_hero_arrival() -> void:
	var sim = _make_sim(211)
	sim.raids_enabled = false
	if not _build(sim, "tavern", sim.keep_pos + Vector2i(1, 1)):
		return
	var h = _force_arrival(sim, "rogue")
	if h == null:
		return
	if h.home != sim.keep_pos + Vector2i(1, 1):
		_fail("rogue did not adopt the tavern as home: %s" % h.home)
	var arrived := false
	for i in 300:
		sim.update()
		if h.state != "acting" and h.adjacent_to(h.home):
			arrived = true
			break
	if not arrived:
		_fail("rogue never reached the tavern (at %s, %s)" % [h.tile(), h.state])

func _test_incentive_snapshot() -> void:
	# The scoring table is the heart of indirect control: pin the whole
	# environment and assert exact scores per class.
	var sim = _make_sim(223)
	sim.raids_enabled = false
	_only_den(sim)
	var den: Vector2i = sim.dens.keys()[0]
	sim.bounties[den] = {"reward": sim.BOUNTY_FEE - sim.BOUNTY_OVERHEAD}
	sim.loot_piles[sim.keep_pos + Vector2i(3, 3)] = 10
	sim.gold = 200
	sim.build_at("farm", sim.keep_pos + Vector2i(1, 1)) # incomplete site

	var rogue = _spawn_at(sim, "rogue", sim.keep_pos + Vector2i(-1, -1))
	if rogue == null:
		return
	var s: Dictionary = sim.hero_goal_scores(rogue)
	# A loot pile is risk-free coin and scores a good deal higher than a
	# bounty of similar size: the rogue goes for the pile, not the flag.
	var expect := {"bounty": 12, "treasure": 20, "smite": 2, "patrol": 1}
	if s.size() != expect.size():
		_fail("rogue score keys wrong: %s" % s)
	for k in expect:
		if int(s.get(k, -1)) != int(expect[k]):
			_fail("rogue score %s = %d, expected %d" % [k, int(s.get(k, -1)), expect[k]])
	if sim._best_hero_goal(s) != "treasure":
		_fail("rogue should prefer the risk-free pile, got %s" % sim._best_hero_goal(s))

	# Paladin: no treasure (never loots), smite wins the tie on priority.
	var paladin = _spawn_at(sim, "paladin", sim.keep_pos + Vector2i(-2, -1))
	if paladin == null:
		return
	s = sim.hero_goal_scores(paladin)
	expect = {"bounty": 10, "smite": 10, "assist": 4, "patrol": 1}
	if s.size() != expect.size():
		_fail("paladin score keys wrong: %s" % s)
	for k in expect:
		if int(s.get(k, -1)) != int(expect[k]):
			_fail("paladin score %s = %d, expected %d" % [k, int(s.get(k, -1)), expect[k]])
	if sim._best_hero_goal(s) != "smite":
		_fail("paladin should smite, got %s" % sim._best_hero_goal(s))

	# Warrior: the bounty flag dominates.
	var warrior = _spawn_at(sim, "warrior", sim.keep_pos + Vector2i(-1, -2))
	if warrior == null:
		return
	s = sim.hero_goal_scores(warrior)
	expect = {"bounty": 20, "treasure": 10, "smite": 4, "assist": 3, "patrol": 1}
	if s.size() != expect.size():
		_fail("warrior score keys wrong: %s" % s)
	for k in expect:
		if int(s.get(k, -1)) != int(expect[k]):
			_fail("warrior score %s = %d, expected %d" % [k, int(s.get(k, -1)), expect[k]])
	if sim._best_hero_goal(s) != "bounty":
		_fail("warrior should chase the bounty, got %s" % sim._best_hero_goal(s))

func _test_shop_and_rest_loop() -> void:
	var sim = _make_sim(227)
	sim.raids_enabled = false
	if not _build(sim, "tavern", sim.keep_pos + Vector2i(1, 1)):
		return
	if not _build(sim, "market", sim.keep_pos + Vector2i(2, 2)):
		return
	var h = _force_arrival(sim, "rogue")
	if h == null:
		return
	for i in 300:
		sim.update()
		if h.state == "idle":
			break
	# Loaded purse beats weariness: shop first, then rest and heal.
	h.pouch = 20
	h.fatigue = 5
	h.hp = h.max_hp - 3
	var gold_before: int = sim.gold
	var shopped := false
	var rested := false
	for i in 500:
		sim.update()
		if not shopped and h.pouch == 0:
			shopped = true
			if sim.gold != gold_before + 20:
				_fail("shop deposit wrong: gold %d -> %d" % [gold_before, sim.gold])
			if sim.market_sales < 20:
				_fail("market sales not accounted: %d" % sim.market_sales)
		if shopped and h.fatigue == 0:
			rested = true
			if h.hp != h.max_hp:
				_fail("rest did not heal: hp %d/%d" % [h.hp, h.max_hp])
			break
	if not shopped:
		_fail("hero never shopped (pouch %d)" % h.pouch)
	if not rested:
		_fail("hero never rested (fatigue %d)" % h.fatigue)

func _test_hero_combat_and_levels() -> void:
	var sim = _make_sim(233)
	sim.raids_enabled = false
	_only_den(sim)
	var den: Vector2i = sim.dens.keys()[0]
	var door: Vector2i = sim.den_doorstep(den, sim.keep_pos)
	var h = _spawn_at(sim, "warrior", door)
	if h == null:
		return
	# One goblin squares up against the warrior on his own tile.
	var GoblinC = load("res://scripts/agents.gd")
	var g = GoblinC.new()
	g.setup(sim, "goblin", door)
	g.home = den
	g.pos = Vector2(door) + Vector2(0.5, 0.5)
	g.path = []
	sim.agents.append(g)
	var gobs := 0
	for i in 300:
		sim.update()
		gobs = 0
		for a in sim.agents:
			if a.kind == "goblin":
				gobs += 1
		if gobs == 0:
			break
	if gobs != 0:
		_fail("warrior never cleared the adjacent goblins")
		return
	if h.xp < 1:
		_fail("goblin kill gave no xp: %d" % h.xp)
	if h.hp >= h.max_hp:
		_fail("warrior took no damage in the melee")
	# With the goblin down, the warrior presses on to the den itself.
	var den_gone := false
	for i in 400:
		sim.update()
		if sim.dens.is_empty():
			den_gone = true
			break
	if not den_gone:
		_fail("warrior never cleared the den")
		return
	if sim.dens_cleared_by_heroes != 1:
		_fail("hero den clear not accounted: %d" % sim.dens_cleared_by_heroes)
	# 1 kill-xp + 5 clear-xp crosses the first threshold.
	if h.level < 2:
		_fail("hero did not level up: level %d xp %d" % [h.level, h.xp])
	if h.max_hp < 12:
		_fail("level up did not grow max_hp: %d" % h.max_hp)

func _test_bounty_flow() -> void:
	var sim = _make_sim(239)
	sim.raids_enabled = false
	_only_den(sim)
	var den: Vector2i = sim.dens.keys()[0]
	sim.dens[den].hp = 3 # a thin warren falls fast
	sim.gold = 100
	if not sim.post_bounty(den):
		_fail("bounty post refused")
		return
	if sim.gold != 100 - sim.BOUNTY_FEE:
		_fail("bounty fee not charged: gold %d" % sim.gold)
	var net: int = sim.BOUNTY_FEE - sim.BOUNTY_OVERHEAD
	if int(sim.bounties[den].reward) != net:
		_fail("bounty reward wrong: %s (fee must fund the flag)" % sim.bounties[den])
	if sim.post_bounty(sim.keep_pos):
		_fail("bounty posted where no den stands")
	var door: Vector2i = sim.den_doorstep(den, sim.keep_pos)
	var h = _spawn_at(sim, "paladin", door)
	if h == null:
		return
	var claimed := false
	for i in 400:
		sim.update()
		if sim.dens.is_empty():
			break
	if sim.dens.has(den):
		_fail("bounty den never fell")
		return
	if sim.bounties.has(den):
		_fail("bounty flag survived the den")
	if sim.bounties_paid != net:
		_fail("bounty not paid: %d" % sim.bounties_paid)
	if h.pouch != net:
		_fail("claimant did not bank the bounty: %d" % h.pouch)
	if sim.dens_cleared_by_heroes != 1:
		_fail("hero clear not accounted")
	claimed = true
	if not claimed:
		_fail("unreachable")

func _test_death_drops_loot() -> void:
	var sim = _make_sim(241)
	sim.raids_enabled = false
	var h = _spawn_at(sim, "rogue", sim.keep_pos + Vector2i(2, -2))
	if h == null:
		return
	var spot: Vector2i = h.tile()
	h.pouch = 25
	h.hp = 1
	h.hurt(2) # drops straight to 0 — no chance to flee
	sim.update()
	if _count(sim, "hero") != 0:
		_fail("dead hero not reaped")
	if sim.heroes_fallen != 1:
		_fail("hero fall not accounted")
	# The hero may take one last step on its death tick, so only assert the
	# pile exists with the right gold, near where it fell.
	if sim.loot_piles.size() != 1 or int(sim.loot_piles.values()[0]) != 25:
		_fail("loot pile wrong: %s" % sim.loot_piles)
	elif Vector2(sim.loot_piles.keys()[0]).distance_to(Vector2(spot)) > 4.0:
		_fail("loot pile dropped far from the fall: %s vs %s" % [sim.loot_piles.keys()[0], spot])

func _test_loot_pickup() -> void:
	var sim = _make_sim(251)
	sim.raids_enabled = false
	var pile: Vector2i = sim.keep_pos + Vector2i(2, 1) # inside the cleared keep site: always grass
	sim.loot_piles[pile] = 25
	var h = _spawn_at(sim, "rogue", pile)
	if h == null:
		return
	var got_it := false
	for i in 200:
		sim.update()
		if h.pouch >= 25:
			got_it = true
			break
	if not got_it:
		_fail("rogue never picked up the dropped loot")
	if sim.loot_piles.has(pile):
		_fail("loot pile not removed after pickup")

func _test_long_run() -> void:
	# ~10 game years with everything on: raids, heroes, bounties posted by
	# the sim itself once gold allows. Nothing may wedge.
	var sim = _make_sim(257)
	var spots := [
		sim.keep_pos + Vector2i(1, 1),
		sim.keep_pos + Vector2i(-1, 1),
		sim.keep_pos + Vector2i(2, 2),
		sim.keep_pos + Vector2i(-1, -1),
	]
	sim.gold = 400
	sim.build_at("tavern", spots[0])
	sim.build_at("market", spots[1])
	sim.build_at("shrine", spots[2])
	sim.build_at("guardhouse", spots[3])
	var bountied := false
	for i in 3650:
		sim.update()
		if not bountied and not sim.dens.is_empty() and sim.gold > 100:
			bountied = true
			sim.post_bounty(sim.dens.keys()[0])
	if sim.pop < 1:
		_fail("total extinction in long run")
	if sim.gold < 0:
		_fail("negative gold in long run")
	if sim.heroes_spawned < 1:
		_fail("no hero ever arrived in 10 years of taverns and shrines")
	if sim.heroes_spawned != sim.heroes_fallen + _count(sim, "hero"):
		_fail("hero accounting off: spawned %d fallen %d alive %d"
			% [sim.heroes_spawned, sim.heroes_fallen, _count(sim, "hero")])
	for h in _heroes(sim):
		if h.level < 1 or h.max_hp <= 0:
			_fail("hero in bad shape: level %d hp %d/%d" % [h.level, h.hp, h.max_hp])
	var valid_states := ["idle", "to_target", "acting", "returning", "fleeing"]
	for a in sim.agents:
		if not sim.world.in_bounds(a.tile()):
			_fail("agent out of bounds at %s" % a.tile())
		if not valid_states.has(a.state):
			_fail("bad agent state: %s" % a.state)
		if a.state == "acting" and a.work_left < 0:
			_fail("agent stuck acting")
	for p in sim.dens:
		if int(sim.dens[p].food) < 0 or int(sim.dens[p].gold) < 0:
			_fail("negative den stores")
	for p in sim.loot_piles:
		if int(sim.loot_piles[p]) < 0:
			_fail("negative loot pile")
	for p in sim.bounties:
		if int(sim.bounties[p].reward) < 0:
			_fail("negative bounty")
