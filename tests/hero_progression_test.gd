extends SceneTree

# M7.2 progression tests: heroes earn XP from meaningful ventures (not only
# kills), core pursuits pay more, and the blacksmith's gear stock becomes
# real equipment that heroes buy and fight with.

var failed := false

func _initialize() -> void:
	_test_activity_xp_table()
	_test_explore_xp()
	_test_activity_integration()
	_test_gear_goal_and_purchase()
	_test_gear_refusals()
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
	h.xp = 0
	h.level = 1
	h.max_hp = int(h.kingdom.HERO_CLASSES[h.hero_class].hp)

func _test_activity_xp_table() -> void:
	var sim = _make_sim(801)
	var cases := [
		["rogue", "treasure", 2], # core
		["druid", "protect", 2], # core
		["dwarf", "assist", 2], # core
		["wizard", "explore", 2], # core
		["ranger", "hunt", 1], # core is explore
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

func _test_explore_xp() -> void:
	var sim = _make_sim(809, true)
	sim.heroes_enabled = false
	var h = _hero(sim, "wizard", sim.keep_pos)
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
	if h.xp - xp0 != 2:
		_fail("exploring wizard gained %d xp, expected core 2" % (h.xp - xp0))

func _test_activity_integration() -> void:
	var AgentC = load("res://scripts/agents.gd")
	# Treasure: looting a pile teaches a rogue.
	var sim = _make_sim(811)
	var h = _hero(sim, "rogue", sim.keep_pos)
	sim.loot_piles[h.tile()] = 5
	h.target = h.tile()
	sim.hero_take_loot(h)
	if h.xp != 2:
		_fail("looting did not grant core xp: %d" % h.xp)
	# Tending the wilds: the druid's core lesson.
	sim = _make_sim(821)
	h = _hero(sim, "druid", sim.keep_pos + Vector2i(2, 2))
	var den: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim._place_wild_den("rabbit_warren", den)
	h.target = den
	sim.hero_protect(h)
	if h.xp != 2:
		_fail("tending wilds did not grant core xp: %d" % h.xp)
	# Hunting: a lesson, but not the ranger's core pursuit.
	sim = _make_sim(823)
	h = _hero(sim, "ranger", sim.keep_pos + Vector2i(2, 2))
	den = sim.keep_pos + Vector2i(3, 2)
	sim._place_wild_den("rabbit_warren", den)
	h.target = den
	sim.hero_hunt(h)
	if h.xp != 1:
		_fail("hunting did not grant activity xp: %d" % h.xp)
	# Gambling: a night at the tables is worth something too.
	sim = _make_sim(827)
	h = _hero(sim, "barbarian", sim.keep_pos + Vector2i(2, 2))
	var tavern: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim.buildings[tavern] = {"kind": "tavern", "complete": true, "tax": 0}
	h.target = tavern
	sim.hero_carouse(h)
	if h.xp != 1:
		_fail("carousing did not grant activity xp: %d" % h.xp)
	# Honest work: the dwarf's core lesson.
	sim = _make_sim(829)
	h = _hero(sim, "dwarf", sim.keep_pos + Vector2i(2, 2))
	var site: Vector2i = sim.keep_pos + Vector2i(3, 2)
	sim.buildings[site] = {"kind": "farm", "complete": false, "tax": 0,
		"progress": 0}
	h.target = site
	sim.hero_assist(h)
	if h.xp != 2:
		_fail("assisting at a worksite did not grant core xp: %d" % h.xp)
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

func _test_gear_combat_bonus() -> void:
	var sim = _make_sim(857)
	var h = _hero(sim, "warrior", sim.keep_pos)
	h.gear = 2
	h.level = 1
	var at: Vector2i = sim.keep_pos + Vector2i(1, 0)
	var g = _spawn_foe(sim, at)
	g.hp = 10
	g.max_hp = 10
	sim._combat_step()
	var expected: int = h.level + 1 + h.gear
	if g.hp != 10 - expected:
		_fail("gear did not add to melee: goblin hp %d, expected %d" \
			% [g.hp, 10 - expected])
