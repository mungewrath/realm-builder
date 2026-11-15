extends SceneTree

# M2.5 inspector content tests: blurbs exist for every building, status
# wording is tiered (vague, not formulaic), agent activity covers all states.

var failed := false

func _initialize() -> void:
	_test_building_text()
	_test_purse_tiers()
	_test_site_status()
	_test_farm_status()
	_test_agent_lines()
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

func _test_building_text() -> void:
	var D = load("res://scripts/descriptions.gd")
	for kind in ["castle", "farm", "house"]:
		if D.building_title(kind) == "":
			_fail("missing title for " + kind)
		if D.building_blurb(kind) == "":
			_fail("missing blurb for " + kind)
	if D.building_blurb("nope") != "":
		_fail("unknown building should have empty blurb")

func _test_purse_tiers() -> void:
	var D = load("res://scripts/descriptions.gd")
	var sim = _make_sim(3)
	var p := Vector2i(0, 0)
	var tiers := {}
	for tax in [0, 3, 8, 13]:
		var b := {"kind": "house", "complete": true, "tax": tax}
		var s: String = D.building_status("house", p, b, sim)
		if s == "":
			_fail("empty purse status at tax=%d" % tax)
		if tiers.has(s):
			_fail("purse tiers not distinct at tax=%d" % tax)
		tiers[s] = tax
	if D.building_status("house", p, {"kind": "house", "complete": true, "tax": 0}, sim) \
			.findn("empty") == -1:
		_fail("empty purse should read as empty")

func _test_site_status() -> void:
	var D = load("res://scripts/descriptions.gd")
	var sim = _make_sim(5)
	var early: String = D.building_status("farm", Vector2i.ZERO,
		{"kind": "farm", "complete": false, "progress": 0}, sim)
	var late: String = D.building_status("farm", Vector2i.ZERO,
		{"kind": "farm", "complete": false, "progress": sim.BUILD_WORK_TICKS - 1}, sim)
	if early == "" or late == "":
		_fail("empty construction status")
	if early == late:
		_fail("construction progress tiers not distinct")

func _test_farm_status() -> void:
	var D = load("res://scripts/descriptions.gd")
	var sim = _make_sim(7)
	var farm: Vector2i = sim.keep_pos + Vector2i(1, 1)
	sim.build_at("farm", farm)
	sim.buildings[farm].complete = true
	var empty: String = D.building_status("farm", farm, sim.buildings[farm], sim)
	if empty.findn("awaiting hands") == -1:
		_fail("unworked farm should await hands: " + empty)
	var a = load("res://scripts/agents.gd").new()
	a.setup(sim, "peasant", farm)
	sim.agents.append(a)
	a.assign(farm, "farm")
	a.pos = Vector2(farm) + Vector2(0.5, 0.5)
	a.state = "acting"
	var worked: String = D.building_status("farm", farm, sim.buildings[farm], sim)
	if worked == empty:
		_fail("worked farm status should differ")
	if worked.findn("hands") == -1:
		_fail("worked farm should mention hands: " + worked)

func _test_agent_lines() -> void:
	var D = load("res://scripts/descriptions.gd")
	var sim = _make_sim(11)
	var seen := {}
	var cases := [
		["idle", "farm", 0],
		["to_target", "farm", 0],
		["acting", "farm", 0],
		["to_target", "build", 0],
		["acting", "build", 0],
		["returning", "farm", 8],
		["fleeing", "farm", 0],
	]
	var a = load("res://scripts/agents.gd").new()
	a.setup(sim, "peasant", sim.keep_pos)
	sim.agents.append(a)
	for c in cases:
		a.state = c[0]
		a.purpose = c[1]
		a.carrying = c[2]
		var s: String = D.agent_line(a)
		if s == "":
			_fail("empty agent line for %s/%s" % [c[0], c[1]])
		if seen.has(s):
			_fail("duplicate agent line for %s/%s" % [c[0], c[1]])
		seen[s] = true
	a.state = "idle"
	a.purpose = ""
	a.carrying = 0
	var peasant_line: String = D.agent_line(a)
	if peasant_line.findn("Peasant") == -1:
		_fail("peasant role missing from line: " + peasant_line)
	a.kind = "collector"
	a.pouch = 5
	var collector_line: String = D.agent_line(a)
	if collector_line.findn("Tax Collector") == -1:
		_fail("collector role missing from line: " + collector_line)
	if collector_line == peasant_line.replace("Peasant", "Tax Collector") \
			and collector_line.findn("waiting") == -1:
		_fail("collector idle line should differ from peasant idle")
