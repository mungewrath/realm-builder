extends SceneTree

# M6.2 faction tests: the tension ledger (seed, drift, claim friction), the
# kobold–gnome feud (theft, trade choke, feud strikes), bandit musters and
# muggings, hag curses (blocked farms, expiry) and a long-run soak with the
# whole ecology on.

var failed := false

func _initialize() -> void:
	_test_tension_seed()
	_test_tension_drift()
	_test_claim_friction()
	_test_kobold_theft()
	_test_gnome_trade()
	_test_feud()
	_test_feud_thaw()
	_test_rival_respawn_spacing()
	_test_bandit_mug()
	_test_hag_curse()
	_test_cursed_farm_carry()
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
	sim.wild_ecology = true
	sim.attach_world(WorldC)
	sim.building_padding = false
	sim.building_footprints = false # existing fixtures stay 1x1; footprint checks live in sim_test
	sim.set_fog_enabled(false)
	sim.keep_trickle = 0
	sim.heroes_enabled = false
	sim.wild_spawn_chance = 0.0
	sim.wild_respawn_rest_left = 999999
	return sim

func _dens_of_kind(sim, kind_key: String) -> Array:
	var out := []
	for p in sim.dens:
		if sim.dens[p].get("kind", "") == kind_key:
			out.append(p)
	return out

func _count(sim, kind: String) -> int:
	var n := 0
	for a in sim.agents:
		if a.kind == kind:
			n += 1
	return n

func _set_tension(sim, a: String, b: String, v: int) -> void:
	sim.tension[sim._pair_key(a, b)] = v

func _bandit_at(sim, home: Vector2i):
	for a in sim.agents:
		if a.kind == "bandit" and a.home == home:
			return a
	return null

func _test_tension_seed() -> void:
	var sim = _make_sim(401)
	if sim.tension.is_empty():
		_fail("tension ledger never seeded")
		return
	if sim.tension_between("kobolds", "gnomes") != -3:
		_fail("kobold–gnome feud not seeded at -3")
	if sim.tension_between("gnomes", "kobolds") != -3:
		_fail("tension lookup not symmetric")
	if sim.tension_between("gnomes", "hags") != -1:
		_fail("gnome–hag base tension wrong")
	if sim.tension_between("kobolds", "kobolds") != 0:
		_fail("a faction should be indifferent to itself")

func _test_tension_drift() -> void:
	var sim = _make_sim(403)
	sim.tension_decay_ticks = 1
	_set_tension(sim, "kobolds", "gnomes", -3)
	_set_tension(sim, "gnomes", "unquiet", 2)
	sim.update()
	if sim.tension_between("kobolds", "gnomes") != -2:
		_fail("negative tension did not drift toward zero")
	if sim.tension_between("gnomes", "unquiet") != 1:
		_fail("positive tension did not drift toward zero")
	for k in sim.tension:
		if absi(int(sim.tension[k])) > 3:
			_fail("tension left the -3..3 band at %s" % k)

func _closest_edge_pair(sim) -> Array:
	var edges: Array = sim._mountain_edge_pool()
	var best := INF
	var pair := [Vector2i(-1, -1), Vector2i(-1, -1)]
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			var d := Vector2(edges[i]).distance_squared_to(Vector2(edges[j]))
			if d < best:
				best = d
				pair = [edges[i], edges[j]]
	return pair

func _test_claim_friction() -> void:
	# Claims overlapping with another faction's sour the ledger over time.
	var sim = _make_sim(405)
	# Re-seat the feuding pair on the closest two hill shoulders.
	for p in _dens_of_kind(sim, "kobold_den") + _dens_of_kind(sim, "gnome_enclave"):
		sim.dens.erase(p)
	var pair := _closest_edge_pair(sim)
	if pair[0].x < 0:
		_fail("no hill shoulders to stage a claim dispute")
		return
	if Vector2(pair[0]).distance_to(Vector2(pair[1])) > sim.den_claim_radius:
		return # this map's shoulders are too spread out to overlap claims
	var row := {"level": 1, "hp": sim.den_hp, "food": 3, "gold": 0,
		"unmet": 0, "regrow": 0}
	var kb: Dictionary = row.duplicate()
	kb.kind = "kobold_den"
	var gn: Dictionary = row.duplicate()
	gn.kind = "gnome_enclave"
	sim.dens[pair[0]] = kb
	sim.dens[pair[1]] = gn
	sim.claim_friction_ticks = 1
	sim._claim_left = 1
	sim.tension_decay_ticks = 100000
	_set_tension(sim, "kobolds", "gnomes", 0)
	var before: int = sim.tension_between("kobolds", "gnomes")
	for i in 3:
		sim.update()
	if sim.claims_felt <= 0:
		_fail("overlapping claims never soured the ledger")
	if sim.tension_between("kobolds", "gnomes") >= before:
		_fail("claim friction did not lower tension")

func _test_kobold_theft() -> void:
	# Kobolds filch from the nearest gnome enclave (no farms on the map yet).
	var sim = _make_sim(407)
	var kbs := _dens_of_kind(sim, "kobold_den")
	var gns := _dens_of_kind(sim, "gnome_enclave")
	if kbs.is_empty() or gns.is_empty():
		_fail("seed did not place the feuding hillfolk")
		return
	var kb: Vector2i = kbs[0]
	var gn: Vector2i = gns[0]
	sim.dens[kb].food = 0
	sim.dens[gn].gold = 5
	sim.kobold_theft_ticks = 1
	sim.tension_decay_ticks = 100000
	_set_tension(sim, "kobolds", "gnomes", 0)
	for i in 3:
		sim.update()
	if int(sim.dens[kb].food) <= 0:
		_fail("kobolds never stole anything")
	if int(sim.dens[gn].gold) >= 5:
		_fail("gnome coffers untouched by kobold theft")
	if sim.kobold_thefts <= 0:
		_fail("theft counter never moved")
	if sim.tension_between("kobolds", "gnomes") >= 0:
		_fail("theft did not deepen the feud")

func _test_gnome_trade() -> void:
	# Peaceful hills mean trade: gnome coin trickles into the realm's ledger.
	var sim = _make_sim(409)
	var gns := _dens_of_kind(sim, "gnome_enclave")
	if gns.is_empty():
		_fail("no enclave to trade with")
		return
	_set_tension(sim, "kobolds", "gnomes", 0) # the feud has cooled
	sim.tension_decay_ticks = 100000
	sim.gnome_trade_ticks = 1
	var gold_before: int = sim.gold
	for i in 3:
		sim.update()
	if sim.gnome_trades <= 0:
		_fail("gnomes never traded in peacetime")
	if sim.gold <= gold_before:
		_fail("gnome trade added no gold to the realm")
	# Feud rages again: the tinkers bar their gates.
	_set_tension(sim, "kobolds", "gnomes", -3)
	var trades_before: int = sim.gnome_trades
	for i in 3:
		sim.update()
	if sim.gnome_trades != trades_before:
		_fail("gnomes traded while feuding with the kobolds")

func _test_feud() -> void:
	# Once the ledger passes the threshold, kobold warbands fall on the
	# enclave and carry off its coin.
	var sim = _make_sim(411)
	var gns := _dens_of_kind(sim, "gnome_enclave")
	if gns.is_empty():
		_fail("no enclave to feud with")
		return
	var gn: Vector2i = gns[0]
	sim.dens[gn].gold = 6
	_set_tension(sim, "kobolds", "gnomes", -2)
	sim.tension_decay_ticks = 100000
	sim.feud_ticks = 1
	sim._feud_left = 1
	sim.update()
	if sim.feuds_triggered <= 0:
		_fail("feud threshold never triggered a strike")
		return
	if int(sim.dens[gn].gold) >= 6:
		_fail("feud strike did not carry off gnome coin")

func _test_feud_thaw() -> void:
	# Clearing one side of the feud resolves it: the ledger clears and the
	# tinkers come out to trade.
	var sim = _make_sim(419)
	sim.tension_decay_ticks = 100000
	var kbs := _dens_of_kind(sim, "kobold_den")
	var gns := _dens_of_kind(sim, "gnome_enclave")
	if kbs.is_empty() or gns.is_empty():
		_fail("feud pairs missing for the thaw test")
		return
	_set_tension(sim, "kobolds", "gnomes", -3)
	sim._clear_den(kbs[0])
	if sim.tension_between("kobolds", "gnomes") != 0:
		_fail("feud did not thaw after the kobolds were wiped out")
	sim.gnome_trade_ticks = 1
	var trades_before: int = sim.gnome_trades
	for i in 3:
		sim.update()
	if sim.gnome_trades <= trades_before:
		_fail("gnomes stayed locked after the feud thawed")

func _test_rival_respawn_spacing() -> void:
	# New burrows do not resettle on a gnome enclave's claim and re-ignite
	# the feud the player just resolved.
	var sim = _make_sim(421)
	sim.wild_spawn_chance = 1.0
	sim.wild_spawn_weights = {"kobold_den": 1}
	var gns := _dens_of_kind(sim, "gnome_enclave")
	if gns.is_empty():
		_fail("no enclave for the spacing test")
		return
	for p in _dens_of_kind(sim, "kobold_den"):
		sim.dens.erase(p)
	for i in 30:
		sim._try_spawn_wild_den()
	for p in _dens_of_kind(sim, "kobold_den"):
		if Vector2(p).distance_to(Vector2(gns[0])) \
				<= float(sim.den_claim_radius):
			_fail("respawned kobolds squat on the gnome claim")
			return

func _test_bandit_mug() -> void:
	# A camp musters a bandit; the bandit shadows a laden collector home
	# and lifts at most `bandit_take` from the purse.
	var sim = _make_sim(413)
	var site: Vector2i = sim._wild_den_site("bandit_camp")
	if site.x < 0:
		_fail("no grass for a bandit camp")
		return
	sim._place_wild_den("bandit_camp", site)
	sim.bandit_muster_ticks = 100000 # keep the camp at one rider
	var AgentC = load("res://scripts/agents.gd")
	var victim = AgentC.new()
	var spot: Vector2i = sim._wilds_spot(site, 4, site)
	victim.setup(sim, "collector", spot)
	victim.pouch = 20
	sim.agents.append(victim)
	var mugged := false
	for i in 80:
		sim.update()
		if sim.bandit_mugs > 0:
			mugged = true
			break
	if not mugged:
		_fail("bandit never mugged the collector")
		return
	if victim.pouch != 20 - sim.bandit_take:
		_fail("purse lift wrong: %d left of 20" % victim.pouch)
	if _bandit_at(sim, site) == null:
		_fail("mugging bandit vanished")

func _test_hag_curse() -> void:
	# The covens do not raid: they wither the nearest farm within reach.
	var sim = _make_sim(415)
	var site: Vector2i = sim._wild_den_site("hag_coven")
	if site.x < 0:
		_fail("no forest for a hag coven")
		return
	sim._place_wild_den("hag_coven", site)
	# Stage a farm close enough for the hags to reach.
	var farm := Vector2i(-1, -1)
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var q: Vector2i = site + Vector2i(dx, dy)
			if not sim.world.in_bounds(q) or sim.buildings.has(q) or sim.dens.has(q):
				continue
			if sim.world.get_terrain(q) == sim.world.GRASS:
				farm = q
				break
		if farm.x >= 0:
			break
	if farm.x < 0:
		_fail("no grass near the coven for a farm")
		return
	if Vector2(farm).distance_to(Vector2(site)) > sim.hag_reach:
		_fail("staged farm out of hag reach")
		return
	sim.buildings[farm] = {"kind": "farm", "complete": true, "tax": 0, "progress": 0}
	sim.hag_curse_ticks = 1
	sim.hag_curse_duration = 4
	sim.update()
	if sim.curses_cast <= 0:
		_fail("hag never cursed the farm")
		return
	if not sim.is_cursed(farm):
		_fail("curse never landed on the farm")
	if sim._nearest_free_farm(sim.keep_pos) == farm:
		_fail("farmers still flock to a cursed field")
	# Stop recasting so the curse can be watched wearing off.
	for p in _dens_of_kind(sim, "hag_coven"):
		sim.dens[p].curse_left = 100000
	for i in 6:
		sim.update()
	if sim.is_cursed(farm):
		_fail("hag curse never wore off")

func _test_cursed_farm_carry() -> void:
	var sim = _make_sim(417)
	var farm := Vector2i(-1, -1)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var q: Vector2i = sim.keep_pos + Vector2i(dx, dy)
			if dx == 0 and dy == 0:
				continue
			if not sim.world.in_bounds(q) or sim.buildings.has(q):
				continue
			if sim.world.get_terrain(q) == sim.world.GRASS:
				farm = q
				break
		if farm.x >= 0:
			break
	if farm.x < 0:
		_fail("no grass near the keep for a farm")
		return
	sim.buildings[farm] = {"kind": "farm", "complete": true, "tax": 0, "progress": 0}
	var AgentC = load("res://scripts/agents.gd")
	var p = AgentC.new()
	p.setup(sim, "peasant", farm)
	p.target = farm
	p.purpose = "farm"
	sim.buildings[farm].cursed_until = sim.tick + 100
	p._finish_work()
	if p.carrying != 0:
		_fail("a cursed field still yielded a harvest")
	sim.buildings[farm].cursed_until = 0
	p.state = "acting"
	p._finish_work()
	if p.carrying != sim.FARM_CARRY:
		_fail("an un-cursed field yielded no harvest")

func _test_long_run() -> void:
	# ~three game years with the whole wild ecology running: nothing wedges,
	# nothing goes negative, and the ledger stays in its band.
	var sim = _make_sim(419)
	sim.heroes_enabled = false
	for p in sim.dens:
		sim.dens[p].hp = 999
	sim.gold = 100
	sim.build_at("farm", sim.keep_pos + Vector2i(1, 1))
	sim.build_at("house", sim.keep_pos + Vector2i(-1, 1))
	sim.build_at("guardhouse", sim.keep_pos + Vector2i(1, -1))
	for i in 1200:
		sim.update()
	if sim.pop < 1:
		_fail("total extinction in the factions soak")
	for k in sim.tension:
		if absi(int(sim.tension[k])) > 3:
			_fail("tension left the band in soak at %s" % k)
	for p in sim.dens:
		if int(sim.dens[p].food) < 0 or int(sim.dens[p].gold) < 0:
			_fail("negative den stores at %s" % p)
		if not sim.DEN_KINDS.has(sim.dens[p].get("kind", "")):
			_fail("unknown den kind at %s" % p)
	var valid_states := ["idle", "to_target", "acting", "returning", "fleeing"]
	for a in sim.agents:
		if not sim.world.in_bounds(a.tile()):
			_fail("agent out of bounds at %s" % a.tile())
		if not valid_states.has(a.state):
			_fail("bad agent state: %s" % a.state)
		if a.kind == "bandit" and not sim.dens.has(a.home):
			_fail("bandit homed to a vanished camp")
	if _count(sim, "bandit") > 40:
		_fail("bandit population ran away: %d" % _count(sim, "bandit"))
