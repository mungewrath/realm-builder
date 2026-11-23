extends SceneTree

# M7.2 progression tests: heroes earn XP from meaningful ventures (not only
# kills), core pursuits pay more, and the blacksmith's gear stock becomes
# real equipment that heroes buy and fight with.

var failed := false

func _initialize() -> void:
	_test_activity_xp_table()
	_test_level_curve()
	_test_explore_xp()
	_test_activity_integration()
	_test_gear_goal_and_purchase()
	_test_gear_refusals()
	_test_combat_tuning()
	_test_gear_combat_bonus()
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

func _hero(sim, cls: String, at := Vector2i(-9999, -9999)):
	sim._spawn_hero(cls)
	var h = sim.agents[sim.agents.size() - 1]
	if at.x != -9999:
		h.pos = Vector2(at) + Vector2(0.5, 0.5)
	h.state = "idle"
	h.purpose = ""
	h.path = []
	h.decision_left = 0
	return h

func _fresh_xp(h) -> void:
	# Park the hero past the early thresholds so a single award can be
	# observed without immediately leveling them up.
	h.xp = 0
	h.level = 5
	h.max_hp = int(h.kingdom.HERO_CLASSES[h.hero_class].hp)

func _test_activity_xp_table() -> void:
	var sim = _make_sim(801)
	var cases := [
		["rogue", "carouse", 4], # primary
		["rogue", "treasure", 1], # off primary
		["rogue", "explore", 1], # off primary
		["druid", "protect", 4], # primary
		["dwarf", "assist", 4], # primary
		["wizard", "explore", 4], # primary
		["ranger", "explore", 4], # primary
		["ranger", "hunt", 1], # off primary
		["barbarian", "carouse", 1], # core is bounty
	]
	for row in cases:
		var h = _hero(sim, row[0])
		_fresh_xp(h)
		var gained: int = sim.hero_activity_xp(h, row[1])
		if gained != int(row[2]):
			_fail("%s %s gained %d xp, expected %d" \
				% [row[0], row[1], gained, row[2]])
		if h.xp != gained:
			_fail("%s %s xp not applied: %d" % [row[0], row[1], h.xp])
	if sim.hero_activity_xp(_hero(sim, "rogue"), "rest") != 0:
		_fail("rest awarded activity xp")

func _test_level_curve() -> void:
	var sim = _make_sim(802)
	var prev := 0
	for lvl in range(1, 11):
		var need: int = sim._hero_xp_to_next(lvl)
		if need <= prev:
			_fail("level curve not rising at level %d: %d <= %d" \
				% [lvl, need, prev])
		prev = need
	if sim._hero_xp_to_next(1) != sim.HERO_XP_PER_LEVEL:
		_fail("first level asks %d, expected %d" \
			% [sim._hero_xp_to_next(1), sim.HERO_XP_PER_LEVEL])
	# A pure linear curve would ask exactly PER_LEVEL * level; the exponential
	# component must push later levels above that line.
	if sim._hero_xp_to_next(10) <= sim.HERO_XP_PER_LEVEL * 10:
		_fail("level curve has no exponential component: %d" \
			% sim._hero_xp_to_next(10))

func _test_explore_xp() -> void:
	var sim = _make_sim(809, true)
	sim.heroes_enabled = false
	var h = _hero(sim, "wizard", sim.keep_pos)
	_fresh_xp(h)
	h.pos = Vector2(sim.keep_pos) + Vector2(0.5, 0.5)
	var target: Vector2i = sim._explore_target(h.tile())
	if target.x < 0:
		_fail("no frontier to explore for the xp test")
		return
	var xp0: int = h.xp
	var AgentC = load("res://scripts/agents.gd")
	h.assign(target, AgentC.EXPLORE)
	for i in 400:
		sim.update()
		if h.state == "idle" and h.purpose == "":
			break
	if h.purpose == AgentC.EXPLORE:
		_fail("wizard never finished exploring")
	if h.state != "idle":
		_fail("wizard did not settle after exploring")
	if h.xp - xp0 != 4:
		_fail("exploring wizard gained %d xp, expected primary 4" % (h.xp - xp0))

func _test_activity_integration() -> void:
	var AgentC = load("res://scripts/agents.gd")
	# Treasure: looting a pile is outside the rogue's primary pursuit now.
	var sim = _make_sim(811)
	var h = _hero(sim, "rogue", sim.keep_pos)
	_fresh_xp(h)
	sim.loot_piles[h.tile()] = 5
	h.target = h.tile()
	sim.hero_take_loot(h)
	if h.xp != 1:
		_fail("looting did not grant partial xp: %d" % h.xp)
	# Tending the wilds: the druid's primary lesson.
	sim = _make_sim(821)
	h = _hero(sim, "druid", sim.keep_pos + Vector2i(2, 2))
	_fresh_xp(h)
	var den: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim._place_wild_den("rabbit_warren", den)
	h.target = den
	sim.hero_protect(h)
	if h.xp != 4:
		_fail("tending wilds did not grant primary xp: %d" % h.xp)
	# Hunting: a lesson, but not the ranger's primary pursuit.
	sim = _make_sim(823)
	h = _hero(sim, "ranger", sim.keep_pos + Vector2i(2, 2))
	_fresh_xp(h)
	den = sim.keep_pos + Vector2i(3, 2)
	sim._place_wild_den("rabbit_warren", den)
	h.target = den
	sim.hero_hunt(h)
	if h.xp != 1:
		_fail("hunting did not grant partial activity xp: %d" % h.xp)
	# Gambling: the rogue's primary lesson.
	sim = _make_sim(827)
	h = _hero(sim, "rogue", sim.keep_pos + Vector2i(2, 2))
	_fresh_xp(h)
	var tavern: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim.buildings[tavern] = {"kind": "tavern", "complete": true, "tax": 0}
	h.target = tavern
	sim.hero_carouse(h)
	if h.xp != 4:
		_fail("rogue gambling did not grant primary xp: %d" % h.xp)
	# Carousing outside the class's pursuit still teaches a little.
	sim = _make_sim(828)
	h = _hero(sim, "barbarian", sim.keep_pos + Vector2i(2, 2))
	_fresh_xp(h)
	tavern = sim.keep_pos + Vector2i(3, 2)
	sim.buildings[tavern] = {"kind": "tavern", "complete": true, "tax": 0}
	h.target = tavern
	sim.hero_carouse(h)
	if h.xp != 1:
		_fail("barbarian carousing did not grant partial xp: %d" % h.xp)
	# Honest work: the dwarf's primary lesson.
	sim = _make_sim(829)
	h = _hero(sim, "dwarf", sim.keep_pos + Vector2i(2, 2))
	_fresh_xp(h)
	var site: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim.buildings[site] = {"kind": "farm", "complete": false, "tax": 0,
		"progress": 0}
	h.target = site
	sim.hero_assist(h)
	if h.xp != 4:
		_fail("assisting at a worksite did not grant primary xp: %d" % h.xp)
	# Shopping banks coin but is not a lesson.
	sim = _make_sim(839)
	h = _hero(sim, "rogue", sim.keep_pos)
	h.pouch = 20
	sim.hero_shop(h)
	if h.xp != 0:
		_fail("market shopping awarded xp")

func _test_gear_goal_and_purchase() -> void:
	var sim = _make_sim(841)
	var forge: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.gold = 500
	if not sim.build_at("blacksmith", forge):
		_fail("blacksmith build refused")
		return
	sim.complete_building(forge)
	var b: Dictionary = sim.buildings[forge]
	b.gear = 2
	var h = _hero(sim, "warrior", forge)
	h.pouch = 20
	var scores: Dictionary = sim.hero_goal_scores(h)
	if not scores.has("gear"):
		_fail("armed hero with coin ignored the forge: %s" % scores)
		return
	if int(scores["gear"]) != 12 + int(sim.HERO_CLASSES.warrior.weights.smite_evil):
		_fail("gear score wrong: %s" % scores)
	if sim._best_hero_goal(scores) != "gear":
		_fail("forge gear was not the favored pursuit: %s" % scores)
	# Walk the shop leg to completion without letting the hero re-decide.
	sim.heroes_enabled = false
	var gold0: int = sim.gold
	var AgentC = load("res://scripts/agents.gd")
	h.assign(forge, AgentC.GEAR)
	for i in 40:
		sim.update()
		if h.gear > 0:
			break
	if int(b.gear) != 1:
		_fail("forge stock not consumed: %d" % int(b.gear))
	if h.gear != 1:
		_fail("hero did not gain gear: %d" % h.gear)
	if h.pouch != 20 - sim.GEAR_COST:
		_fail("gear price not taken from purse: %d" % h.pouch)
	if sim.gold != gold0 + sim.GEAR_COST or sim.gear_sales != sim.GEAR_COST:
		_fail("gear sale not credited to the realm")

func _test_gear_refusals() -> void:
	var sim = _make_sim(853)
	var forge: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.buildings[forge] = {"kind": "blacksmith", "complete": true, "tax": 0,
		"gear": 1}
	var wiz = _hero(sim, "wizard", forge)
	wiz.pouch = 20
	if sim.hero_goal_scores(wiz).has("gear"):
		_fail("wizard wanted forged gear despite the sages")
	sim.buildings[forge].gear = 0
	var h = _hero(sim, "warrior", forge)
	h.pouch = 20
	if sim.hero_goal_scores(h).has("gear"):
		_fail("empty forge still drew a shopper")
	sim.hero_buy_gear(h)
	if h.gear != 0:
		_fail("hero bought gear from an empty forge")
	sim.buildings[forge].gear = 1
	h.pouch = sim.GEAR_COST - 1
	if sim.hero_goal_scores(h).has("gear"):
		_fail("penniless hero still wanted gear")
	sim.hero_buy_gear(h)
	if h.gear != 0:
		_fail("hero bought gear without enough coin")
	h.pouch = 20
	h.gear = sim.HERO_GEAR_MAX
	if sim.hero_goal_scores(h).has("gear"):
		_fail("fully equipped hero still wanted gear")
	sim.hero_buy_gear(h)
	if int(sim.buildings[forge].gear) != 1:
		_fail("max-equipped hero still consumed stock")

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

func _test_combat_tuning() -> void:
	var sim = _make_sim(855)
	var h = _hero(sim, "warrior", sim.keep_pos)
	if sim.hero_accuracy(h) != sim.HERO_BASE_ACCURACY:
		_fail("level-1 accuracy is %.2f, expected %.2f" \
			% [sim.hero_accuracy(h), sim.HERO_BASE_ACCURACY])
	h.level = 2
	if not is_equal_approx(sim.hero_accuracy(h), 0.45):
		_fail("level-2 accuracy wrong: %.2f" % sim.hero_accuracy(h))
	h.level = 10
	if not is_equal_approx(sim.hero_accuracy(h), 0.85):
		_fail("level-10 accuracy wrong: %.2f" % sim.hero_accuracy(h))
	h.level = 20
	if not is_equal_approx(sim.hero_accuracy(h), sim.HERO_ACCURACY_MAX):
		_fail("accuracy did not cap: %.2f" % sim.hero_accuracy(h))
	h.level = 1
	h.gear = 2
	if sim.hero_melee_damage(h) != 6:
		_fail("level-1 geared damage wrong: %d" % sim.hero_melee_damage(h))
	h.level = 4
	if sim.hero_melee_damage(h) != 7:
		_fail("level-4 damage wrong: %d" % sim.hero_melee_damage(h))
	h.level = 7
	if sim.hero_melee_damage(h) != 8:
		_fail("level-7 damage wrong: %d" % sim.hero_melee_damage(h))
	if int(sim.HERO_CLASSES["warrior"].hp) != 11 \
			or int(sim.HERO_CLASSES["wizard"].hp) != 8:
		_fail("base hero HP was not cut by 20%")

func _test_gear_combat_bonus() -> void:
	var sim = _make_sim(857)
	var h = _hero(sim, "warrior", sim.keep_pos)
	h.gear = 2
	h.level = 1
	h.hp = 999
	h.max_hp = 999
	var at: Vector2i = sim.keep_pos + Vector2i(1, 0)
	var g = _spawn_foe(sim, at)
	var expected: int = sim.hero_melee_damage(h)
	var dealt := 0
	for i in 100:
		g.hp = 10
		g.max_hp = 10
		sim._combat_step()
		if g.hp < 10:
			dealt = 10 - g.hp
			break
	if dealt != expected:
		_fail("gear hit dealt %d, expected %d (accuracy %.2f)" \
			% [dealt, expected, sim.hero_accuracy(h)])
