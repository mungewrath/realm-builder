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
	_test_hero_aggro()
	_test_bounty_flow()
	_test_explore_bounty_flow()
	_test_death_drops_loot()
	_test_loot_pickup()
	_test_leisure_goals()
	_test_fast_first_arrival()
	_test_hero_cap_scaling()
	_test_over_cap_warnings_and_departure()
	_test_dismiss_hero()
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
	sim.wild_ecology = false # hero accounting; ecology has its own suite
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # existing fixtures stay 1x1; footprint checks live in sim_test
	sim.set_fog_enabled(false) # hero accounting without fog gates
	sim.keep_trickle = 0 # exact gold accounting; trickle has its own check
	return sim

func _count(sim, kind: String) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == kind:
			n += 1
	return n

func _decide_until(sim, h, purpose: String, tries: int) -> bool:
	# Live decisions are a weighted draw, so one roll can miss the
	# favorite; give a favored pursuit a fair sample before declaring.
	for i in tries:
		sim._hero_decide(h)
		if h.purpose == purpose:
			return true
	return false

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
	if int(mix.get("rogue", 0)) != 1 or int(mix.get("paladin", 0)) != 1 \
			or mix.has("druid"):
		_fail("tavern+shrine mix wrong: %s" % mix)
	# M7.1: the druid follows the herbalist grove, not the shrine.
	if not _build(sim, "herbalist_grove", sim.keep_pos + Vector2i(3, 2)):
		return
	mix = sim._attraction_mix()
	if int(mix.get("druid", 0)) != 1:
		_fail("herbalist grove did not draw a druid: %s" % mix)
	# Incomplete buildings must not attract anyone yet.
	sim.gold = 200
	sim.build_at("market", sim.keep_pos + Vector2i(4, 3))
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
	var expect := {"bounty": 8, "treasure": 20, "smite": 2, "patrol": 1}
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
	expect = {"bounty": 7, "smite": 10, "assist": 4, "patrol": 1}
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
	expect = {"bounty": 12, "treasure": 10, "smite": 4, "assist": 3, "patrol": 1}
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
	g.hp = 8
	g.max_hp = 8
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

func _spawn_foe(sim, at: Vector2i):
	var AgentC = load("res://scripts/agents.gd")
	var g = AgentC.new()
	g.setup(sim, "goblin", at)
	g.home = sim.dens.keys()[0]
	g.pos = Vector2(at) + Vector2(0.5, 0.5)
	g.path = []
	g.state = "idle"
	g.purpose = ""
	sim.agents.append(g)
	return g

func _reachable_spot(sim, origin: Vector2i, dist: int) -> Vector2i:
	# A walkable tile at (about) the given Chebyshev distance, reachable
	# from the origin by the same pathing the sim uses.
	for d in [Vector2i(dist, 0), Vector2i(-dist, 0), Vector2i(0, dist),
			Vector2i(0, -dist), Vector2i(dist, dist), Vector2i(-dist, dist),
			Vector2i(dist, -dist), Vector2i(-dist, -dist)]:
		var p: Vector2i = origin + d
		if not sim.world.in_bounds(p) or not sim.world._walkable(p):
			continue
		if not sim.find_path(origin, p).is_empty():
			return p
	return Vector2i(-9999, -9999)

func _test_hero_aggro() -> void:
	var sim = _make_sim(241)
	sim.raids_enabled = false
	_only_den(sim)
	var h = _spawn_at(sim, "warrior", sim.keep_pos)
	if h == null:
		return
	var AgentC = load("res://scripts/agents.gd")
	# A visible enemy in the vicinity is a fight the hero starts.
	var near: Vector2i = _reachable_spot(sim, h.tile(), 4)
	if near.x < 0:
		_fail("no reachable spot for the aggro test")
		return
	var g = _spawn_foe(sim, near)
	sim.update()
	if h.target_agent != g or h.purpose != AgentC.INTERCEPT:
		_fail("hero ignored an enemy in the vicinity")
		return
	var gobs := 0
	for i in 120:
		sim.update()
		gobs = 0
		for a in sim.agents:
			if a.kind == "goblin":
				gobs += 1
		if gobs == 0:
			break
	if gobs != 0:
		_fail("aggroed hero never reached the enemy")
		return

	# Beyond both radii an enemy is none of the hero's business.
	var far: Vector2i = _reachable_spot(sim, h.tile(), int(sim.hero_alarm_radius) + 2)
	if far.x >= 0:
		var f = _spawn_foe(sim, far)
		h.state = "idle"
		h.purpose = ""
		h.target_agent = null
		h.fighting = false
		h.path = []
		sim.update()
		if h.target_agent == f:
			_fail("hero chased an enemy beyond aggro range")
		sim.agents.erase(f)

	# A raider (or any foe at a building's door) raises the alarm farther out.
	var alarm: Vector2i = _reachable_spot(sim, h.tile(), int(sim.hero_aggro_radius) + 2)
	if alarm.x >= 0:
		var r = _spawn_foe(sim, alarm)
		r.purpose = AgentC.RAID
		h.state = "idle"
		h.purpose = ""
		h.target_agent = null
		h.fighting = false
		h.path = []
		sim.update()
		if h.target_agent != r:
			_fail("hero ignored a raider beyond the quiet radius")
		sim.agents.erase(r)

	# Overriding needs: a hero resting indoors or fleeing does not bite.
	var g2 = _spawn_foe(sim, _reachable_spot(sim, h.tile(), 3))
	h.state = AgentC.ACTING
	h.purpose = AgentC.REST
	h.work_left = 50
	h.target_agent = null
	sim.update()
	if h.target_agent != null:
		_fail("resting hero left the tavern to fight")
	h.state = AgentC.FLEEING
	h.purpose = ""
	sim.update()
	if h.target_agent != null:
		_fail("fleeing hero turned to fight")
	sim.agents.erase(g2)

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

func _test_explore_bounty_flow() -> void:
	var sim = _make_sim(241)
	sim.set_fog_enabled(true)
	sim.heroes_enabled = false
	sim.raids_enabled = false
	sim.dens.clear()
	sim.gold = 100
	var target: Vector2i = sim._explore_target(sim.keep_pos)
	if target.x < 0:
		_fail("no uncharted target to flag")
		return
	if not sim.can_post_explore_bounty(target):
		_fail("reachable uncharted ground refused an explore bounty")
		return
	if not sim.post_explore_bounty(target):
		_fail("explore bounty post failed")
		return
	var net: int = sim.BOUNTY_FEE - sim.BOUNTY_OVERHEAD
	if sim.gold != 100 - sim.BOUNTY_FEE \
			or int(sim.explore_bounties[target].reward) != net:
		_fail("explore bounty fee/reward wrong: gold %d reward %s" \
			% [sim.gold, sim.explore_bounties[target]])
	if sim.post_explore_bounty(sim.keep_pos):
		_fail("explore bounty posted on charted ground")
	if not sim.post_explore_bounty(target):
		_fail("explore bounty could not be topped up")
	if int(sim.explore_bounties[target].reward) != net * 2:
		_fail("explore bounty did not stack: %s" % sim.explore_bounties[target])
	var h = _spawn_at(sim, "wizard", sim.keep_pos)
	if h == null:
		return
	if not sim.hero_goal_scores(h).has("explore"):
		_fail("explore bounty did not enter the hero's goal table")
	if sim._explore_target(h.tile()) != target:
		_fail("hero did not prefer the explore bounty target")
	h.assign(target, "explore")
	for i in 2000:
		sim.update()
		if not sim.explore_bounties.has(target):
			break
	if sim.explore_bounties.has(target):
		_fail("hero never reached the explore bounty")
		return
	if h.pouch != net * 2 or sim.explore_bounties_paid != net * 2:
		_fail("explore bounty payout wrong: purse %d paid %d" \
			% [h.pouch, sim.explore_bounties_paid])
	if not sim.explored_at(target):
		_fail("explore bounty target was not charted")
	if sim.can_post_explore_bounty(target):
		_fail("charted ground still accepted an explore bounty")

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

func _test_leisure_goals() -> void:
	# Idle hours: prayer, an evening at the tavern, and a spot of hunting.
	# Each only exists when the realm offers it; ventures always outrank it.
	var sim = _make_sim(263)
	sim.raids_enabled = false
	# Pray: a weary paladin and a shrine.
	if not _build(sim, "shrine", sim.keep_pos + Vector2i(1, 1)):
		return
	var pal = _spawn_at(sim, "paladin", sim.keep_pos + Vector2i(-1, -1))
	if pal == null:
		return
	pal.fatigue = 3
	pal.hp = pal.max_hp - 2
	var s: Dictionary = sim.hero_goal_scores(pal)
	if not s.has("pray"):
		_fail("weary paladin never considers prayer: %s" % s)
		return
	if s.has("hunt") or s.has("carouse"):
		_fail("paladin weighted into the wrong leisure: %s" % s)
	# Prayer is the weary paladin's favored pursuit, and it comes up in
	# the draw.
	if sim._best_hero_goal(sim.hero_goal_scores(pal)) != "pray":
		_fail("weary paladin's favored pursuit is not prayer")
	if not _decide_until(sim, pal, "pray", 30):
		_fail("paladin never set out to pray in 30 draws")
	var prayed := false
	for i in 300:
		sim.update()
		if pal.fatigue < 3:
			prayed = true
			break
	if not prayed:
		_fail("paladin never prayed (at %s, %s)" % [pal.tile(), pal.state])
	if int(pal.hp) != int(pal.max_hp) - 1:
		_fail("prayer did not mend: hp %d/%d" % [pal.hp, pal.max_hp])

	# Hunt: a charted warren gives rogues game to chase.
	sim = _make_sim(269)
	sim.raids_enabled = false
	var site: Vector2i = sim._wild_den_site("rabbit_warren")
	if site.x < 0:
		_fail("no warren site for the hunt test")
		return
	sim._place_wild_den("rabbit_warren", site)
	sim.dens[site].food = 6
	var rog = _spawn_at(sim, "rogue", sim.keep_pos + Vector2i(-1, -1))
	if rog == null:
		return
	s = sim.hero_goal_scores(rog)
	if not s.has("hunt"):
		_fail("rogue never considers hunting: %s" % s)
		return
	if s.has("pray") or s.has("carouse"):
		_fail("rogue weighted into the wrong leisure: %s" % s)
	# Hunting yields to ventures: a live bounty outranks the chase.
	sim.bounties[sim._nearest_den(rog.tile())] = {"reward": 18}
	var bounty_score: int = int(sim.hero_goal_scores(rog).bounty)
	var hunt_score: int = int(sim.hero_goal_scores(rog).hunt)
	sim.bounties.clear()
	if hunt_score >= bounty_score:
		_fail("hunt (%d) should not outrank a bounty (%d)" % [hunt_score, bounty_score])
	# The chase is for fresh legs: a weary hero leaves the warrens be.
	rog.fatigue = 3
	if sim.hero_goal_scores(rog).has("hunt"):
		_fail("weary rogue still hooked on hunting")
	rog.fatigue = 0
	var xp_before: int = rog.xp
	# The chase is the fresh rogue's favored pursuit, and it comes up.
	if sim._best_hero_goal(sim.hero_goal_scores(rog)) != "hunt":
		_fail("fresh rogue's favored pursuit is not hunting")
	if not _decide_until(sim, rog, "hunt", 30):
		_fail("rogue never set out after game in 30 draws")
	var hunted := false
	for i in 400:
		sim.update()
		if int(sim.dens[site].food) < 6:
			hunted = true
			break
	if not hunted:
		_fail("rogue never took game (warren food %d)" % int(sim.dens[site].food))
	if rog.xp <= xp_before:
		_fail("hunt gave no experience")
	# The warren keeps its kind: hunting never razed the lair.
	if not sim.dens.has(site):
		_fail("hunting destroyed the warren")
	# Idle hours rotate by odds, not gates: a round of leisure dulls the
	# appetite (half score, quarter weight in the draw) and wears off.
	rog.fatigue = 0
	if rog.leisure_left <= 0:
		_fail("hunting did not start a leisure cooldown")
	var dull: int = int(sim.hero_goal_scores(rog).hunt)
	rog.leisure_left = 0
	var keen: int = int(sim.hero_goal_scores(rog).hunt)
	if dull >= keen:
		_fail("cooldown did not dull the chase: %d vs %d" % [dull, keen])

	# Carouse: a bored rogue at the tavern drinks a coin into the till.
	sim = _make_sim(271)
	sim.raids_enabled = false
	if not _build(sim, "tavern", sim.keep_pos + Vector2i(1, 1)):
		return
	rog = _spawn_at(sim, "rogue", sim.keep_pos + Vector2i(-1, -1))
	if rog == null:
		return
	rog.fatigue = 2
	s = sim.hero_goal_scores(rog)
	if not s.has("carouse"):
		_fail("bored rogue never considers the tavern: %s" % s)
		return
	# The tavern is the bored rogue's favored pastime, and it comes up.
	if sim._best_hero_goal(sim.hero_goal_scores(rog)) != "carouse":
		_fail("bored rogue's favored pursuit is not carousing")
	if not _decide_until(sim, rog, "carouse", 30):
		_fail("rogue never set out for the tavern in 30 draws")
	var caroused := false
	var lingered := 0
	for i in 300:
		sim.update()
		if rog.state == "acting" and rog.purpose == "carouse":
			lingered = maxi(lingered, rog.work_left)
		if rog.fatigue < 2:
			caroused = true
			break
	# A tavern evening is a while, not a single tick.
	if lingered <= 1:
		_fail("rogue caroused on the doorstep (work_left %d)" % lingered)
	if not caroused:
		_fail("rogue never caroused (at %s, %s)" % [rog.tile(), rog.state])
	var till: int = int(sim.buildings[sim.keep_pos + Vector2i(1, 1)].tax)
	if till < 1:
		_fail("carousing left the tavern till empty")
	# Dice nights rotate too: one evening dulls the appetite, never
	# locks the tavern door.
	if rog.leisure_left <= 0:
		_fail("carousing did not start a leisure cooldown")
	var dull_c: int = int(sim.hero_goal_scores(rog).carouse)
	rog.leisure_left = 0
	var keen_c: int = int(sim.hero_goal_scores(rog).carouse)
	if dull_c >= keen_c:
		_fail("cooldown did not dull the tavern: %d vs %d" % [dull_c, keen_c])

func _test_fast_first_arrival() -> void:
	# Finishing a hall pulls the attraction roll forward to ~10 ticks: the
	# first hero steps out within seconds, not after a stale 2-minute cycle.
	# Chance forced to 1 so the timing itself is what is under test.
	var sim = _make_sim(273)
	sim.raids_enabled = false
	sim.hero_arrival_chance = 1.0
	if not _build(sim, "tavern", sim.keep_pos + Vector2i(1, 1)):
		return
	var arrived := false
	for i in 12:
		sim.update()
		if _count(sim, "hero") > 0:
			arrived = true
			break
	if not arrived:
		_fail("no hero within 12 ticks of the tavern's finish")

func _test_hero_cap_scaling() -> void:
	# One hero per five living peasants, never fewer than one.
	var sim = _make_sim(277)
	var cases := [[0, 1], [4, 1], [5, 1], [9, 1], [10, 2], [14, 2],
		[15, 3], [24, 4], [25, 5]]
	for row in cases:
		sim.pop = int(row[0])
		if sim.hero_cap() != int(row[1]):
			_fail("pop %d gives hero cap %d, expected %d"
				% [sim.pop, sim.hero_cap(), row[1]])

func _test_over_cap_warnings_and_departure() -> void:
	var sim = _make_sim(279)
	sim.raids_enabled = false
	sim.pop = 5 # cap 1
	var h = _spawn_at(sim, "rogue", sim.keep_pos)
	_spawn_at(sim, "warrior", sim.keep_pos)
	if sim._count_kind("hero") != 2 or sim.hero_cap() != 1:
		_fail("staging failed for over-cap test")
		return
	var warn_mark: int = sim.event_seq
	sim._hero_cap_tick()
	if sim._hero_over_cap_warnings_left != sim.hero_over_cap_warnings - 1:
		_fail("first over-cap warning did not fire")
	for i in 200:
		sim._hero_cap_tick()
	if sim._hero_over_cap_warnings_left != 0:
		_fail("over-cap warnings never exhausted")
	var warns := 0
	for e in sim.event_log:
		if int(e.id) > warn_mark and (String(e.text).contains("peasants can support")
				or String(e.text).contains("Heroes grow restless")):
			warns += 1
	if warns != 2:
		_fail("expected exactly 2 over-cap warnings, saw %d" % warns)
	var seq_after: int = sim.event_seq
	for i in 50:
		sim._hero_cap_tick()
	if sim.event_seq != seq_after:
		_fail("over-cap warnings kept repeating after the second")
	# Leaving is now on the hero's action table.
	var exit: Vector2i = sim._leave_target(h.tile())
	if exit.x < 0:
		_fail("no reachable map edge for a departing hero")
		return
	var scores: Dictionary = sim.hero_goal_scores(h)
	if not scores.has("leave"):
		_fail("over-cap hero has no leave option: %s" % scores)
		return
	var AgentC = load("res://scripts/agents.gd")
	h.state = "idle"
	h.purpose = ""
	h.path = []
	h.decision_left = 0
	var chose := false
	for i in 300:
		sim._hero_decide(h)
		if h.purpose == AgentC.LEAVE:
			chose = true
			break
	if not chose:
		_fail("over-cap hero never chose to leave")
		return
	# Let the departing hero walk off the map; the realm drops the agent.
	sim.heroes_enabled = false
	for i in 500:
		sim.update()
		if sim.heroes_departed > 0:
			break
	if sim.heroes_departed != 1:
		_fail("departing hero was not counted (departed %d)" % sim.heroes_departed)
	if sim._count_kind("hero") != 1 or sim.agents.has(h):
		_fail("departing hero never left the map")

func _test_dismiss_hero() -> void:
	var sim = _make_sim(281)
	var h = _spawn_at(sim, "rogue", sim.keep_pos)
	if h == null:
		return
	if sim.hero_count() != 1 or sim.hero_roster().size() != 1:
		_fail("hero count/roster missed the spawned hero")
	if not sim.dismiss_hero(h):
		_fail("selected hero refused dismissal")
		return
	if h.purpose != "leave" or h.goal != "leave":
		_fail("dismissed hero is not leaving: %s/%s" % [h.purpose, h.goal])
	sim.heroes_enabled = false # let the exit walk finish without new plans
	for i in 500:
		sim.update()
		if sim.heroes_departed > 0:
			break
	if sim.heroes_departed != 1 or sim.agents.has(h):
		_fail("dismissed hero never left the realm")
	if sim.hero_count() != 0:
		_fail("hero count did not drop after departure")

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
	if sim.heroes_spawned != sim.heroes_fallen + sim.heroes_departed \
			+ _count(sim, "hero"):
		_fail("hero accounting off: spawned %d fallen %d departed %d alive %d"
			% [sim.heroes_spawned, sim.heroes_fallen, sim.heroes_departed,
				_count(sim, "hero")])
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
