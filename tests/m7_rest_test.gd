extends SceneTree

# M7.3 tests: the graveyard's corpse economy and necromancer servants, the
# sewer's rat/plague tradeoff, and tribute diplomacy with bandits and gnomes.

var failed := false

func _initialize() -> void:
	_test_content_rows()
	_test_graveyard_risk()
	_test_necromancer_raises()
	_test_shrine_ward()
	_test_sewer_rats()
	_test_plague_control()
	_test_bandit_tribute()
	_test_gnome_tribute()
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)

func _make_sim(seed_value: int):
	var WorldC = load("res://scripts/world.gd").new()
	WorldC.generate(seed_value)
	var sim = load("res://scripts/kingdom.gd").new()
	sim.wild_ecology = false
	sim.raids_enabled = false
	sim.heroes_enabled = false
	sim.keep_trickle = 0
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # compact fixtures; footprints live in sim_test
	sim.set_fog_enabled(false)
	sim.wild_spawn_chance = 0.0
	sim.wild_respawn_rest_left = 999999
	return sim

func _spot(sim, kind: String, taken: Array = []) -> Vector2i:
	for r in range(1, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var p: Vector2i = sim.keep_pos + Vector2i(dx, dy)
				if taken.has(p):
					continue
				if sim.can_build_at(p, kind):
					return p
	return Vector2i(-1, -1)

func _complete(sim, kind: String, p: Vector2i) -> bool:
	sim.gold = maxi(sim.gold, 200)
	if not sim.build_at(kind, p):
		_fail("build %s at %s refused" % [kind, p])
		return false
	sim.complete_building(p)
	return true

func _count(sim, kind: String, side := "") -> int:
	var n := 0
	for a in sim.agents:
		if sim._removals.has(a):
			continue
		if a.kind != kind:
			continue
		if side != "" and a.undead_side != side:
			continue
		n += 1
	return n

func _clear_agents(sim, kind: String) -> void:
	var kept := []
	for a in sim.agents:
		if a.kind != kind:
			kept.append(a)
	sim.agents = kept
	sim._removals.clear()

func _test_content_rows() -> void:
	var KingdomC = load("res://scripts/kingdom.gd")
	if KingdomC.BUILD_COSTS.get("graveyard", -1) != 50:
		_fail("graveyard cost wrong")
	if KingdomC.BUILD_COSTS.get("sewers", -1) != 40:
		_fail("sewers cost wrong")
	if KingdomC.BUILDING_SIZES.get("graveyard", Vector2i.ZERO) != Vector2i(2, 2):
		_fail("graveyard footprint wrong")
	if KingdomC.BUILDING_SIZES.get("sewers", Vector2i.ZERO) != Vector2i(1, 1):
		_fail("sewers footprint wrong")
	if not KingdomC.HERO_CLASSES.has("necromancer"):
		_fail("necromancer content row missing")
	elif KingdomC.HERO_CLASSES["necromancer"].attracted_by != "graveyard":
		_fail("necromancer is not drawn to the graveyard")
	var D = load("res://scripts/descriptions.gd")
	for kind in ["graveyard", "sewers"]:
		if D.building_title(kind) == "" or D.building_blurb(kind) == "":
			_fail("missing inspector text for " + kind)
	if String(D.HERO_BLURBS.get("necromancer", "")).findn("grave") == -1:
		_fail("necromancer blurb does not mention the grave")

func _test_graveyard_risk() -> void:
	var sim = _make_sim(801)
	var grave: Vector2i = _spot(sim, "graveyard")
	if not _complete(sim, "graveyard", grave):
		return
	var b: Dictionary = sim.buildings[grave]
	b.corpses = 2
	b.risk = sim.graveyard_risk_ticks - 1
	sim.graveyard_risk_chance = 1.0
	sim._graveyard_tick(grave, b)
	if sim.undead_risen != 1 or _count(sim, "undead", "hostile") != 1:
		_fail("graveyard did not raise hostile dead: risen=%d" % sim.undead_risen)
	if int(b.corpses) != 1:
		_fail("graveyard risk did not consume a corpse: %d" % int(b.corpses))
	# Deaths near a graveyard become stored corpses.
	sim.food_delivered = 0
	sim._record_corpse(grave + Vector2i(2, 0))
	if int(b.corpses) != 2 or sim.corpses_buried != 1:
		_fail("nearby death was not stored in the graveyard")

func _test_necromancer_raises() -> void:
	var sim = _make_sim(803)
	var grave: Vector2i = _spot(sim, "graveyard")
	if not _complete(sim, "graveyard", grave):
		return
	var b: Dictionary = sim.buildings[grave]
	b.corpses = 2
	sim._spawn_hero("necromancer")
	if not sim._has_necromancer():
		_fail("necromancer hero did not register")
		return
	b.risk = sim.graveyard_risk_ticks - 1
	sim._graveyard_tick(grave, b)
	if sim.undead_raised != 1 or _count(sim, "undead", "ally") != 1:
		_fail("necromancer did not raise an ally: raised=%d" % sim.undead_raised)
	var u = null
	for a in sim.agents:
		if a.kind == "undead" and a.undead_side == "ally":
			u = a
	if u == null:
		return
	u.decay_left = 1
	sim._undead_tick()
	if _count(sim, "undead", "ally") != 0 or sim.undead_lost != 1:
		_fail("raised servant's loyalty did not decay")
	sim._reap()
	if _count(sim, "undead", "ally") != 0:
		_fail("expired servant remained in the agent list")

func _test_shrine_ward() -> void:
	var sim = _make_sim(809)
	var grave: Vector2i = _spot(sim, "graveyard")
	if not _complete(sim, "graveyard", grave):
		return
	var shrine: Vector2i = _spot(sim, "shrine", [grave])
	if not _complete(sim, "shrine", shrine):
		return
	sim.shrine_ward_radius = 20
	var b: Dictionary = sim.buildings[grave]
	b.corpses = 2
	b.risk = sim.graveyard_risk_ticks - 1
	sim.graveyard_risk_chance = 1.0
	sim._graveyard_tick(grave, b)
	if _count(sim, "undead", "hostile") != 0 or sim.undead_warded != 1:
		_fail("shrine ward did not keep the dead down")
	if int(b.corpses) != 2:
		_fail("warded graveyard consumed a corpse")

func _test_sewer_rats() -> void:
	var sim = _make_sim(811)
	var sewer: Vector2i = _spot(sim, "sewers")
	if not _complete(sim, "sewers", sewer):
		return
	sim.sewer_rat_ticks = 1
	sim.buildings[sewer].rat_left = 1
	sim._sewer_tick(sewer, sim.buildings[sewer])
	if sim.rats_spawned != 1 or _count(sim, "rat") != 1:
		_fail("sewer did not attract a rat: spawned=%d" % sim.rats_spawned)
	var farm: Vector2i = _spot(sim, "farm", [sewer])
	if not _complete(sim, "farm", farm):
		return
	sim.food_delivered = 20
	var rat = null
	for a in sim.agents:
		if a.kind == "rat":
			rat = a
	if rat == null:
		return
	rat.target = farm
	sim.rat_raid(rat)
	if int(sim.food_spoiled) != sim.rat_spoil \
			or sim.food_delivered != 20 - sim.rat_spoil:
		_fail("rats did not spoil provisions: spoiled=%d delivered=%d"
			% [sim.food_spoiled, sim.food_delivered])

func _test_plague_control() -> void:
	var dirty = _make_sim(813)
	if not is_equal_approx(dirty._plague_chance_for(6), 0.0) \
			or not is_equal_approx(dirty._plague_chance_for(7), 0.30) \
			or not is_equal_approx(dirty._plague_chance_for(8), 0.35) \
			or not is_equal_approx(dirty._plague_chance_for(12), 0.55):
		_fail("plague chance did not start at 25% and scale 5% per extra person")
	dirty.pop = 10
	dirty._plague_left = 1
	dirty.plague_check_ticks = 1
	dirty.plague_chance = 1.0
	dirty._plague_tick()
	if dirty.plague_outbreaks != 1 or dirty.pop != 9:
		_fail("crowded houses without sewers did not breed fever: %d/%d"
			% [dirty.plague_outbreaks, dirty.pop])

	var clean = _make_sim(817)
	clean.pop = 10
	var sewer: Vector2i = _spot(clean, "sewers")
	if not _complete(clean, "sewers", sewer):
		return
	clean._plague_left = 1
	clean.plague_check_ticks = 1
	clean.plague_chance = 1.0
	clean._plague_tick()
	if clean.plague_outbreaks != 0 or clean.pop != 10:
		_fail("sewers did not protect a settlement at their safe capacity")
	clean.plague_chance = 0.25
	clean.pop = 15
	if not is_equal_approx(clean._plague_chance_for(clean.pop), 0.50):
		_fail("sewer safe capacity did not offset overcrowding chance")

	var burial = _make_sim(823)
	var grave: Vector2i = _spot(burial, "graveyard")
	if not _complete(burial, "graveyard", grave):
		return
	if not is_equal_approx(burial._plague_chance_for(8), 0.0) \
			or not is_equal_approx(burial._plague_chance_for(9), 0.30):
		_fail("unwarded graveyard did not add plague relief")
	var shrine_pos := Vector2i(-1, -1)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var q: Vector2i = grave + Vector2i(dx, dy)
			if burial.can_build_at(q, "shrine"):
				shrine_pos = q
				break
		if shrine_pos.x >= 0:
			break
	if shrine_pos.x < 0 or not _complete(burial, "shrine", shrine_pos):
		_fail("could not place a shrine beside the graveyard")
		return
	if not is_equal_approx(burial._plague_chance_for(8), 0.0) \
			or not is_equal_approx(burial._plague_chance_for(9), 0.30):
		_fail("shrine ward changed the graveyard's plague relief")

func _bandit_den(sim, p: Vector2i) -> void:
	sim.dens[p] = {"kind": "bandit_camp", "level": 1, "hp": 12, "food": 3,
		"gold": 4, "intent": "lurk", "intent_left": 10, "next_muster": 1}

func _test_bandit_tribute() -> void:
	var sim = _make_sim(819)
	sim.dens.clear()
	var camp: Vector2i = sim.keep_pos + Vector2i(4, 4)
	_bandit_den(sim, camp)
	sim.gold = 100
	sim.bandit_muster_ticks = 1
	if not sim.can_pay_tribute(camp):
		_fail("bandit camp refused tribute eligibility")
		return
	if not sim.pay_tribute(camp):
		_fail("bandit tribute payment failed")
		return
	if sim.gold != 100 - sim.tribute_cost or sim.tribute_paid != 1:
		_fail("bandit tribute accounting wrong: gold=%d paid=%d"
			% [sim.gold, sim.tribute_paid])
	if not sim.tribute_active(camp):
		_fail("bandit tribute did not start its clock")
	var spawned_before: int = sim.bandits_spawned
	for i in 3:
		sim._bandit_tick()
	if sim.bandits_spawned != spawned_before:
		_fail("tribute-paid bandits mustered anyway")
	if sim.pay_tribute(camp):
		_fail("tribute could be paid twice while active")
	sim.dens[camp].tribute_until = 0
	sim._bandit_tick()
	if sim.bandits_spawned <= spawned_before:
		_fail("bandits did not muster after tribute lapsed")

func _test_gnome_tribute() -> void:
	var sim = _make_sim(821)
	sim.dens.clear()
	var gnome: Vector2i = sim.keep_pos + Vector2i(4, 4)
	var kobold: Vector2i = sim.keep_pos + Vector2i(5, 4)
	sim.dens[gnome] = {"kind": "gnome_enclave", "level": 1, "hp": 12,
		"food": 3, "gold": 5, "trade_left": 1}
	sim.dens[kobold] = {"kind": "kobold_den", "level": 1, "hp": 12,
		"food": 3, "gold": 0, "theft_left": 999}
	sim.gold = 100
	sim.tension_decay_ticks = 100000
	sim.tension[sim._pair_key("kobolds", "gnomes")] = -3
	if not sim.pay_tribute(gnome):
		_fail("gnome tribute payment failed")
		return
	if sim.tension_between("kobolds", "gnomes") < 0:
		_fail("gnome tribute did not cool the feud")
	# Claims remain quiet while the tribute holds, even if tension is forced.
	sim.tension[sim._pair_key("kobolds", "gnomes")] = -3
	sim.claim_friction_ticks = 1
	sim._claim_left = 1
	sim._claim_friction_tick()
	if sim.tension_between("kobolds", "gnomes") != -3:
		_fail("claim friction soured the ledger during paid tribute")
	sim.feud_ticks = 1
	sim._feud_left = 1
	var feuds_before: int = sim.feuds_triggered
	sim._feud_tick()
	if sim.feuds_triggered != feuds_before:
		_fail("gnome warbands struck during paid tribute")
	# Tinkers trade even while the old ledger reads like a feud.
	sim.tension[sim._pair_key("kobolds", "gnomes")] = -3
	sim.gnome_trade_ticks = 1
	sim.dens[gnome].trade_left = 1
	var trades_before: int = sim.gnome_trades
	sim._gnome_tick()
	if sim.gnome_trades <= trades_before:
		_fail("gnomes stayed behind their walls during paid tribute")
