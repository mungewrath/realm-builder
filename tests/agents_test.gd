extends SceneTree

# M2 agent tests: construction completion accounting, tax rounds,
# delivery sums, long-run deadlock check, flee stub.

var failed := false

func _initialize() -> void:
	_test_construction()
	_test_tax_round()
	_test_delivery_accounting()
	_test_pop_growth()
	_test_shortage_churn()
	_test_long_run()
	_test_flee()
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
	# These tests assert exact economy accounting; goblin raids (M3) would
	# raze buildings mid-test. Raid dynamics get their own suite.
	sim.raids_enabled = false
	return sim

func _test_construction() -> void:
	var sim = _make_sim(7)
	var p: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("house", p)
	if sim.buildings[p].complete:
		_fail("construction site complete on placement")
	var gold_after_build: int = sim.gold
	for i in 100:
		sim.update()
		if sim.buildings[p].complete:
			break
	if not sim.buildings[p].complete:
		_fail("house never completed")
		return
	if sim.houses != 1 or sim.pop_cap != 8:
		_fail("completion accounting: houses=%d cap=%d" % [sim.houses, sim.pop_cap])
	if sim.gold != gold_after_build:
		_fail("completion changed gold")
	if sim.buildings[p].tax != 0:
		_fail("brand-new house already taxed")

func _test_tax_round() -> void:
	var sim = _make_sim(11)
	var h1: Vector2i = sim.keep_pos + Vector2i(1, 1)
	var h2: Vector2i = sim.keep_pos + Vector2i(-1, 1)
	sim.build_at("house", h1)
	sim.build_at("house", h2)
	for i in 100:
		sim.update()
		if sim.buildings[h1].complete and sim.buildings[h2].complete:
			break
	if not (sim.buildings[h1].complete and sim.buildings[h2].complete):
		_fail("houses never completed")
		return
	sim.update()
	sim.update()
	if sim.collector == null:
		_fail("no collector after houses built")
		return
	# Pin the collector home and idle so the next round is fully observable.
	var c = sim.collector
	c.state = "idle"
	c.pouch = 0
	c.round_list = []
	c.pos = Vector2(sim.keep_pos) + Vector2(0.5, 0.5)
	c.path = []
	sim.buildings[h1].tax = 7
	sim.buildings[h2].tax = 7
	var gold_before: int = sim.gold
	# One full round: out to the houses, back, deposit.
	for i in 100:
		sim.update()
		if c.state == "idle" and c.tile() == sim.keep_pos and c.pouch == 0:
			break
	if c.pouch != 0 or c.state != "idle" or c.tile() != sim.keep_pos:
		_fail("collector never finished the round (state=%s pouch=%d)" % [c.state, c.pouch])
	if sim.tax_deposited != sim.tax_collected:
		_fail("collected vs deposited mismatch: %d vs %d" % [sim.tax_collected, sim.tax_deposited])
	if sim.tax_collected < 14:
		_fail("collector collected too little: %d" % sim.tax_collected)
	if sim.gold != gold_before + sim.tax_deposited:
		_fail("gold accounting mismatch")
	# Rounds keep running on natural accrual; gold invariant must hold at any instant.
	var deposited_then: int = sim.tax_deposited
	for i in 100:
		sim.update()
	if sim.tax_deposited <= deposited_then:
		_fail("tax rounds stalled")
	for h in [h1, h2]:
		var t: int = sim.buildings[h].tax
		if t < 0 or t > sim.HOUSE_TAX_CAP:
			_fail("tax outside cap bounds: %d" % t)
	if sim.gold != gold_before + sim.tax_deposited:
		_fail("gold accounting mismatch after accrual")

func _test_delivery_accounting() -> void:
	var sim = _make_sim(13)
	var f1: Vector2i = sim.keep_pos + Vector2i(1, 1)
	var f2: Vector2i = sim.keep_pos + Vector2i(-1, 1)
	sim.build_at("farm", f1)
	sim.build_at("farm", f2)
	for i in 60:
		sim.update()
		if sim.buildings[f1].complete and sim.buildings[f2].complete:
			break
	for i in 300:
		sim.update()
	if sim.deliveries < 5:
		_fail("too few deliveries: %d" % sim.deliveries)
	if sim.food_delivered != sim.deliveries * sim.FARM_CARRY:
		_fail("delivery sum mismatch: %d vs %d" % [sim.food_delivered, sim.deliveries * sim.FARM_CARRY])
	if sim.farms != 2:
		_fail("farm count wrong")
	if sim.pop < 1:
		_fail("pop extinct in delivery test")

func _test_pop_growth() -> void:
	# Growth = delivered rations + provisions headroom; declines need shortage.
	var sim = _make_sim(31)
	var f1: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("farm", f1)
	for i in 60:
		sim.update()
		if sim.buildings[f1].complete:
			break
	if not sim.buildings[f1].complete:
		_fail("farm never completed in growth test")
		return
	# Make room: capacity is 4, pop is 5 — drop one villager.
	sim.agents.pop_back()
	sim.pop -= 1
	for i in 400:
		sim.update()
	if sim.pop != 4:
		_fail("pop should regrow to capacity: %d" % sim.pop)
	# Overcrowding beyond capacity sheds people slowly, never below 1.
	sim.agents.pop_back()
	sim.pop -= 1
	sim.shortage_grace = 5
	for i in 400:
		sim.update()
	if sim.pop < 1 or sim.pop > 4:
		_fail("pop outside capacity bounds under shortage: %d" % sim.pop)

func _test_shortage_churn() -> void:
	# Regression: sites used to reset progress every time a builder was culled
	# (formerly by starvation, now by shortage), so farms never finished.
	# Progress must persist and builders must be culled last.
	var sim = _make_sim(29)
	var sites := [
		sim.keep_pos + Vector2i(1, 1),
		sim.keep_pos + Vector2i(-1, 1),
		sim.keep_pos + Vector2i(1, -1),
	]
	for p in sites:
		sim.build_at("farm", p)
	sim.shortage_grace = 2
	for i in 200:
		sim.update()
	for p in sites:
		if not sim.buildings[p].complete:
			_fail("site at %s never finished despite churn (progress=%d)" % [p, sim.buildings[p].progress])
	if sim.food_delivered <= 0:
		_fail("no deliveries after churn recovery")
	if sim.pop < 1:
		_fail("pop extinct in churn test")
	for p in sim.buildings:
		if not sim.buildings[p].complete:
			_fail("stuck construction site at %s" % p)

func _test_long_run() -> void:
	var sim = _make_sim(17)
	var spots := [
		sim.keep_pos + Vector2i(1, 1),
		sim.keep_pos + Vector2i(-1, 1),
		sim.keep_pos + Vector2i(1, -1),
		sim.keep_pos + Vector2i(-1, -1),
	]
	sim.build_at("farm", spots[0])
	sim.build_at("farm", spots[1])
	sim.build_at("house", spots[2])
	sim.build_at("house", spots[3])
	if sim.gold != 0:
		_fail("build costs wrong in long-run setup")
	for i in 100:
		sim.update()
	for p in spots:
		if not sim.buildings[p].complete:
			_fail("building never completed in long-run setup")
	var delivered_mid: int = sim.food_delivered
	var deposited_mid: int = sim.tax_deposited
	for i in 1450:
		sim.update()
	if sim.food_delivered <= delivered_mid:
		_fail("economy stalled: no deliveries in second half")
	if sim.tax_deposited <= deposited_mid:
		_fail("tax rounds stalled in second half")
	if sim.collector == null:
		_fail("collector missing in long run")
	if sim.pop < 1:
		_fail("total extinction in long run")
	if sim.gold < 0:
		_fail("negative resources in long run")
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

func _test_flee() -> void:
	var sim = _make_sim(23)
	var farm: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("farm", farm)
	for i in 60:
		sim.update()
		if sim.buildings[farm].complete:
			break
	if not sim.buildings[farm].complete:
		_fail("farm never completed in flee test")
		return
	for i in 20:
		sim.update()
		if sim.deliveries > 0:
			break
	var fled: int = sim.warn_threat(farm, 12.0)
	if fled < 1:
		_fail("no peasants fled")
	var fled_agents := []
	for a in sim.agents:
		if a.kind == "peasant" and a.state == "fleeing":
			fled_agents.append(a)
	if fled_agents.is_empty():
		_fail("no agent in fleeing state")
	for i in 100:
		sim.update()
		var all_home := true
		for a in fled_agents:
			if a.state != "idle" or a.tile() != sim.keep_pos:
				all_home = false
		if all_home:
			break
	for a in fled_agents:
		if a.state != "idle" or a.tile() != sim.keep_pos:
			_fail("fleeing peasant never made it home")
	var before: int = sim.food_delivered
	for i in 60:
		sim.update()
	if sim.food_delivered <= before:
		_fail("economy did not resume after flee")
