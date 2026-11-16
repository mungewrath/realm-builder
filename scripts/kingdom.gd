const AgentC = preload("res://scripts/agents.gd")

const FARM_COST := 10
const HOUSE_COST := 15
const START_GOLD := 50
const START_POP := 5

const FARM_WORK_TICKS := 2
const FARM_CARRY := 8
const FARM_WORKERS_PER_FARM := 2
const FARM_CAPACITY_POP := 4
const GROWTH_FOOD := 16
const BUILD_WORK_TICKS := 4
const TAX_RATE_TICKS := 4
const HOUSE_TAX_CAP := 15

const GUARDHOUSE_COST := 30
const GUARDS_PER_GUARDHOUSE := 2
const GUARD_PATROL_RADIUS := 6
const GUARD_PATROL_WAIT := 3
# Guards defend the realm, not the wilds: they never stray farther than
# this from the keep, whatever they are chasing. Clearing dens is hero work.
const GUARD_LEASH := 10
const DEN_HUNGRY_FOOD := 4
# The wild regrows lairs: spawn-window chance, minimum distance from the
# keep, and clearance required from any building.
const DEN_SPAWN_CHANCE := 0.35
const DEN_WILD_MIN := 12
const DEN_CIV_CLEARANCE := 8

const GOBLIN_RAZE_TICKS := 6
const FARM_PLUNDER := 6
const HOUSE_PLUNDER := 8
const DEN_MAX_LEVEL := 3
const DEN_SEED_COUNT := 2

# Goblin behavior tuning (all overridable vars for tests/tuning).
const MIN_WARBAND := 2
const FORAGE_CARRY := 5
const GATHER_TICKS := 4
const DEN_HEAL_TICKS := 6
const MUSTER_FOOD_COST := 2

const BUILD_COSTS := {
	"farm": FARM_COST,
	"house": HOUSE_COST,
	"guardhouse": GUARDHOUSE_COST,
}

var gold: int = START_GOLD
var pop: int = START_POP
var pop_cap: int = START_POP
var farms: int = 0
var houses: int = 0
var tick: int = 0
var last_event: String = ""
var world
var buildings := {}
var keep_pos := Vector2i.ZERO
var agents := []
var collector = null
var food_delivered := 0
var growth_mark := 0
var shortage_mark := 0
var shortage_grace := 20
var deliveries := 0
var tax_collected := 0
var tax_deposited := 0

# M3 — goblins & guards. Dens squat on mountain edges; goblins live there
# and run weighted-random behavior states (lurk/wander/prowl/forage), while
# the den overlays a weighted mood (lurk/prowl/forage/raid) on the idle
# warband. Guards from guardhouses intercept them. All knobs are vars so
# tests (and later tuning) can adjust them without touching constants.
var dens := {} # tile -> {level, hp, food, gold, intent, intent_left, next_muster}
var raids_enabled := true
var den_raid_rest := 80
var den_muster_ticks := 30
var guard_retrain_ticks := 600
var den_intent_weights := {} # optional override; empty = hunger-driven
var dens_max := 3
var den_respawn_rest := 1500
var den_respawn_rest_left := 0
var dens_spawned := 0
var den_hp := 12
var goblin_hp := 4
var guard_hp := 6
var rng := RandomNumberGenerator.new()
var raids_launched := 0
var dens_cleared := 0
var buildings_razed := 0
var guards_fallen := 0
var intents_seen := {}
var _removals := []

# Provisions capacity of the realm: complete farms feed people.
func fed_capacity() -> int:
	return farms * FARM_CAPACITY_POP

func attach_world(w) -> void:
	world = w
	rng.seed = 777
	keep_pos = Vector2i(int(w.SIZE_X / 2.0), int(w.SIZE_Y / 2.0))
	buildings[keep_pos] = {"kind": "castle", "complete": true, "tax": 0}
	for i in START_POP:
		_spawn_peasant()
	_spawn_dens()

func find_path(from: Vector2i, to: Vector2i) -> Array:
	return world.find_path(from, to)

func can_build_at(p: Vector2i) -> bool:
	return world != null and world.is_buildable(p) and not buildings.has(p)

func build_at(kind: String, p: Vector2i) -> bool:
	if not BUILD_COSTS.has(kind):
		last_event = "Unknown building"
		return false
	if not can_build_at(p):
		last_event = "Cannot build there"
		return false
	var cost: int = BUILD_COSTS[kind]
	if gold < cost:
		last_event = "Not enough gold"
		return false
	gold -= cost
	buildings[p] = {"kind": kind, "complete": false, "tax": 0, "progress": 0}
	last_event = "Construction started: " + kind
	return true

func tick_build(p: Vector2i) -> bool:
	# One work tick on a construction site; progress persists across builders.
	var b: Dictionary = buildings[p]
	b.progress = int(b.get("progress", 0)) + 1
	if b.progress >= BUILD_WORK_TICKS:
		complete_building(p)
		return true
	return false

func complete_building(p: Vector2i) -> void:
	var b: Dictionary = buildings[p]
	b.complete = true
	b.progress = BUILD_WORK_TICKS
	match b.kind:
		"farm":
			farms += 1
		"house":
			houses += 1
			pop_cap += 3
		"guardhouse":
			for i in GUARDS_PER_GUARDHOUSE:
				_spawn_guard(p)
	last_event = "Finished building " + b.kind

func take_tax(p: Vector2i) -> int:
	var t: int = buildings[p].tax
	buildings[p].tax = 0
	tax_collected += t
	return t

func update() -> void:
	tick += 1
	if collector == null and houses > 0:
		_spawn_collector()
	_accrue_tax()
	_assign_jobs()
	_route_collector()
	if raids_enabled:
		_dens_tick()
		_assign_guards()
	for a in agents:
		a.update()
	if raids_enabled:
		_combat_step()
	_reap()
	_guard_respawn()
	# Growth from delivered labor, when the larder can support another mouth.
	if pop < pop_cap and pop < fed_capacity() \
			and food_delivered - growth_mark >= GROWTH_FOOD:
		pop += 1
		growth_mark = food_delivered
		_spawn_peasant()
		last_event = "A villager arrived"
	# Shortage is soft: the realm slowly sheds people it cannot feed,
	# but never below one soul and never to game over.
	elif pop > fed_capacity() and pop > 1 \
			and tick - shortage_mark >= shortage_grace:
		pop -= 1
		shortage_mark = tick
		_remove_peasant()
		last_event = "The larder is bare; someone left"

func warn_threat(threat: Vector2i, radius: float) -> int:
	# Called by M3 raiders; peasants nearby run home. Stub for now.
	var fled := 0
	for a in agents:
		if a.kind == "peasant" and a.state != AgentC.FLEEING \
				and Vector2(a.tile()).distance_to(Vector2(threat)) <= radius:
			a.flee_to(keep_pos)
			fled += 1
	if fled > 0:
		last_event = "Peasants flee the danger!"
	return fled

func deliver(a) -> void:
	match a.kind:
		"peasant":
			if a.carrying > 0:
				food_delivered += a.carrying
				deliveries += 1
				a.carrying = 0
		"goblin":
			# Foraged roots and stolen plunder both end up in the den's stores.
			if a.carrying > 0:
				var den: Dictionary = dens.get(a.home, {})
				if not den.is_empty():
					if a.loot_kind == "gold":
						den.gold = int(den.gold) + a.carrying
					else:
						den.food = int(den.food) + a.carrying
				a.carrying = 0
				a.loot_kind = ""
		_:
			if a.pouch > 0:
				var amount: int = a.pouch
				gold += amount
				tax_deposited += amount
				a.pouch = 0
				last_event = "The collector delivered %d gold" % amount

func _spawn_peasant() -> void:
	var a = AgentC.new()
	a.setup(self, "peasant", keep_pos)
	agents.append(a)

func _spawn_collector() -> void:
	collector = AgentC.new()
	collector.setup(self, "collector", keep_pos)
	agents.append(collector)
	last_event = "A tax collector now serves the keep"

func _remove_peasant() -> void:
	# Cull order keeps the economy alive: idlers and walkers first, working
	# builders last, laden carriers only when nothing else remains.
	var victim = _pick_victim(AgentC.IDLE, true)
	if victim == null:
		victim = _pick_victim(AgentC.TO_TARGET, true)
	if victim == null:
		victim = _pick_victim(AgentC.RETURNING, true)
	if victim == null:
		victim = _pick_victim(AgentC.FLEEING, true)
	if victim == null:
		victim = _pick_victim(AgentC.RETURNING, false)
	if victim == null:
		victim = _pick_victim(AgentC.ACTING, false)
	if victim != null:
		agents.erase(victim)

func _pick_victim(state_filter: String, only_unladen: bool):
	for a in agents:
		if a.kind == "peasant" and a.state == state_filter \
				and (not only_unladen or a.carrying == 0):
			return a
	return null

func _accrue_tax() -> void:
	if tick % TAX_RATE_TICKS != 0:
		return
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind == "house" and b.complete:
			b.tax = mini(b.tax + 1, HOUSE_TAX_CAP)

func _assign_jobs() -> void:
	for a in agents:
		if a.kind != "peasant" or a.state != AgentC.IDLE:
			continue
		var site := _nearest_free_site(a.tile())
		if site.x >= 0:
			a.assign(site, AgentC.BUILD)
			continue
		var farm := _nearest_free_farm(a.tile())
		if farm.x >= 0:
			a.assign(farm, AgentC.FARM)

func _route_collector() -> void:
	if collector == null or collector.state != AgentC.IDLE:
		return
	var stops := []
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind == "house" and b.complete and b.tax > 0:
			stops.append(p)
	if stops.is_empty():
		return
	var here: Vector2i = collector.tile()
	stops.sort_custom(func(a, b):
		return Vector2(a).distance_squared_to(Vector2(here)) \
			< Vector2(b).distance_squared_to(Vector2(here)))
	collector.start_round(stops)

func _claimed(target: Vector2i, purpose: String) -> bool:
	for a in agents:
		if a.purpose == purpose and a.target == target and a.state != AgentC.IDLE:
			return true
	return false

func _nearest_free_site(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		if buildings[p].complete or _claimed(p, AgentC.BUILD):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _farm_workers(p: Vector2i) -> int:
	var n := 0
	for a in agents:
		if a.purpose == AgentC.FARM and a.target == p and a.state != AgentC.IDLE:
			n += 1
	return n

func _nearest_free_farm(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "farm" or not b.complete:
			continue
		if _farm_workers(p) >= FARM_WORKERS_PER_FARM:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

# --- M3: goblins & guards --------------------------------------------------

func _spawn_dens() -> void:
	# Dens squat far from the keep, on mountain edges whose doorstep is
	# actually connected to the realm — no sealed pockets.
	var sites: Array = world.mountain_edge_sites()
	var reachable: Array = []
	for s in sites:
		if not find_path(den_doorstep(s, keep_pos), keep_pos).is_empty():
			reachable.append(s)
	reachable.sort_custom(func(a, b):
		return Vector2(a).distance_squared_to(Vector2(keep_pos)) \
			> Vector2(b).distance_squared_to(Vector2(keep_pos)))
	var pool: Array = reachable.slice(0, mini(8, reachable.size()))
	for i in DEN_SEED_COUNT:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		var p: Vector2i = pool.pop_at(idx)
		dens[p] = {
			"level": 1,
			"hp": den_hp,
			"food": 8,
			"gold": 0,
			"intent": "lurk",
			"intent_left": 30 + rng.randi_range(0, 40),
			"next_muster": den_muster_ticks,
		}
	# The wilds do not refill instantly after a clearing.
	den_respawn_rest_left = den_respawn_rest

func _den_respawn_tick() -> void:
	if dens.size() >= dens_max:
		return
	if den_respawn_rest_left > 0:
		den_respawn_rest_left -= 1
		return
	if not _try_spawn_den():
		# No suitable lair right now: look again after a while.
		den_respawn_rest_left = 200 + rng.randi_range(0, 200)

func _try_spawn_den() -> bool:
	# The wild regrows lairs from time to time, but shy of civilization:
	# a site must sit far from the keep and clear of every building, and
	# wilder ground (deep forest nearby) is the likeliest cradle.
	if rng.randf() > DEN_SPAWN_CHANCE:
		return false
	var candidates := []
	for s in world.mountain_edge_sites():
		if dens.has(s):
			continue
		var door := den_doorstep(s, keep_pos)
		if Vector2(door).distance_to(Vector2(keep_pos)) < DEN_WILD_MIN:
			continue
		if find_path(door, keep_pos).is_empty():
			continue
		var near_civ := false
		for p in buildings:
			if Vector2(p).distance_to(Vector2(door)) < DEN_CIV_CLEARANCE:
				near_civ = true
				break
		if near_civ:
			continue
		var forest := 0
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var q: Vector2i = door + Vector2i(dx, dy)
				if world.in_bounds(q) and world.get_terrain(q) == world.FOREST:
					forest += 1
		candidates.append([s, 1 + forest])
	if candidates.is_empty():
		return false
	var total := 0
	for c in candidates:
		total += int(c[1])
	var r := rng.randi_range(1, total)
	var pick: Vector2i = candidates[0][0]
	for c in candidates:
		r -= int(c[1])
		if r <= 0:
			pick = c[0]
			break
	dens[pick] = {
		"level": 1,
		"hp": den_hp,
		"food": 8,
		"gold": 0,
		"intent": "lurk",
		"intent_left": 30 + rng.randi_range(0, 40),
		"next_muster": den_muster_ticks,
	}
	dens_spawned += 1
	den_respawn_rest_left = den_respawn_rest + rng.randi_range(0, 600)
	last_event = "A new goblin den stirs in the wilds!"
	return true

func den_doorstep(den: Vector2i, from: Vector2i) -> Vector2i:
	# Dens sit on (unwalkable) mountain; agents rally on the nearest walkable
	# neighbour instead.
	var best := den
	var best_d := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = den + d
		if world != null and world.in_bounds(n) \
				and world.get_terrain(n) != world.MOUNTAIN \
				and world.get_terrain(n) != world.WATER:
			var dist := Vector2(n).distance_squared_to(Vector2(from))
			if dist < best_d:
				best_d = dist
				best = n
	return best

func _dens_tick() -> void:
	# The den is the warband orchestrator: it musters goblins over time and
	# periodically imposes a weighted-random mood on whoever is home.
	for p in dens:
		var den: Dictionary = dens[p]
		_den_muster(p, den)
		if den.intent == "muster":
			# Gathering a warband: hold the home goblins and watch for quorum.
			if _idle_goblins_at(p).size() >= MIN_WARBAND \
					and _nearest_raid_target(p).x >= 0:
				_launch_raid(p)
			else:
				den.intent_left = int(den.intent_left) - 1
				if int(den.intent_left) <= 0:
					den.intent = "lurk"
					den.intent_left = 20
		elif int(den.intent_left) > 0:
			den.intent_left = int(den.intent_left) - 1
		else:
			_den_pick_mood(p, den)
	_den_respawn_tick()
	_goblin_tick()

func _den_mood_weights(den: Dictionary) -> Dictionary:
	# Hunger drives the mood: a den low on provisions gets restless — it
	# forages hard and raids for what it cannot grow.
	var hungry := int(den.food) <= DEN_HUNGRY_FOOD
	return {
		"lurk": 25,
		"prowl": 20,
		"forage": 25 if hungry else 15,
		"raid": 45 if hungry else 20,
	}

func _den_muster(p: Vector2i, den: Dictionary) -> void:
	den.next_muster = int(den.next_muster) - 1
	if int(den.next_muster) > 0:
		return
	den.next_muster = den_muster_ticks
	var pop := 0
	for a in agents:
		if a.kind == "goblin" and a.home == p:
			pop += 1
	if pop >= 2 + int(den.level):
		return
	if pop == 0:
		# A lone scout always emerges, even from a starving den — the wild
		# never stays empty, and a hunted den can slowly rebuild.
		_spawn_goblin(p)
		return
	if int(den.food) < MUSTER_FOOD_COST:
		return # hungry den: no new goblins
	den.food = int(den.food) - MUSTER_FOOD_COST
	_spawn_goblin(p)

func _den_pick_mood(p: Vector2i, den: Dictionary) -> void:
	var weights: Dictionary = den_intent_weights \
		if not den_intent_weights.is_empty() else _den_mood_weights(den)
	var roll := _weighted_intent(weights)
	intents_seen[roll] = true
	match roll:
		"lurk":
			den.intent = "lurk"
			den.intent_left = 40 + rng.randi_range(0, 40)
		"prowl":
			den.intent = "prowl"
			den.intent_left = 30 + rng.randi_range(0, 30)
			_warband_behave(p, AgentC.PROWL)
		"forage":
			den.intent = "forage"
			den.intent_left = 30 + rng.randi_range(0, 30)
			_warband_behave(p, AgentC.FORAGE)
		"raid":
			var idle := _idle_goblins_at(p)
			if idle.size() < MIN_WARBAND:
				# Too few raiders home: call them in and hold a muster until
				# the warband is ready (or the patience runs out).
				den.intent = "muster"
				den.intent_left = 30 + rng.randi_range(0, 30)
				_warband_behave(p, AgentC.LURK)
			elif _nearest_raid_target(p).x < 0:
				# Nothing worth burning yet: rest a little and re-roll.
				den.intent = "lurk"
				den.intent_left = 20
			else:
				_launch_raid(p)

func _weighted_intent(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += maxi(0, int(weights[k]))
	if total <= 0:
		return "lurk"
	var r := rng.randi_range(1, total)
	for k in weights:
		r -= maxi(0, int(weights[k]))
		if r <= 0:
			return k
	return "lurk"

func _idle_goblins_at(den_pos: Vector2i) -> Array:
	var idle := []
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			idle.append(a)
	return idle

func _warband_behave(den_pos: Vector2i, mood: String) -> void:
	# The den's mood sweeps up every idle goblin — whether that is a raiding
	# party or a lazy afternoon depends on the roll.
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			_goblin_behave(a, mood)

func _launch_raid(den_pos: Vector2i) -> void:
	var den: Dictionary = dens[den_pos]
	var target := _nearest_raid_target(den_pos)
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			a.assign(target, AgentC.RAID)
			a.behavior_left = 0
	den.intent = "rest"
	den.intent_left = den_raid_rest
	raids_launched += 1
	last_event = "A goblin warband marches out of the wild!"
	warn_threat(target, 10.0)

func _goblin_tick() -> void:
	# Personal behavior layer: every idle goblin runs weighted-random states
	# (lurk / wander / prowl / forage) that persist for a state-dependent
	# stretch; combat interrupts them and they hold ground until it passes.
	for a in agents:
		if a.kind != "goblin":
			continue
		if a.fighting:
			continue
		if a.state != AgentC.IDLE:
			continue
		# Wounded goblins convalesce slowly at the den.
		if a.adjacent_to(a.home) and a.hp < a.max_hp:
			a.heal_cd -= 1
			if a.heal_cd <= 0:
				a.heal_cd = DEN_HEAL_TICKS
				a.hp = mini(a.hp + 1, a.max_hp)
		# A den gathering a warband holds its goblins at home.
		var den: Dictionary = dens.get(a.home, {})
		if den.get("intent", "") == "muster":
			continue
		if a.behavior_left > 0:
			a.behavior_left -= 1
			continue
		_roll_goblin_behavior(a)

func _roll_goblin_behavior(g) -> void:
	var weights := {"lurk": 30, "wander": 30, "prowl": 20, "forage": 20}
	var roll := _weighted_intent(weights)
	_goblin_behave(g, roll)

func _goblin_behave(g, roll: String) -> void:
	g.behavior = roll
	match roll:
		"lurk":
			g.behavior_left = 10 + rng.randi_range(0, 20)
		"wander":
			g.assign(_wilds_spot(g.home, 8, g.tile()), AgentC.WANDER)
			g.behavior_left = 15 + rng.randi_range(0, 20)
		"prowl":
			var farm := _nearest_complete("farm", g.tile())
			if farm.x < 0:
				farm = _nearest_complete("house", g.tile())
			if farm.x < 0:
				_goblin_behave(g, "wander")
				return
			var spot := _toward_spot(g.tile(), farm)
			g.assign(spot, AgentC.PROWL)
			g.behavior_left = 20 + rng.randi_range(0, 20)
		"forage":
			var spot := _forage_spot(g.home)
			g.assign(spot, AgentC.FORAGE)
			g.behavior_left = 40

func _wilds_spot(center: Vector2i, radius: int, from: Vector2i) -> Vector2i:
	for i in 10:
		var p := center + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if _open_ground(p):
			return p
	return center

func _toward_spot(from: Vector2i, farm: Vector2i) -> Vector2i:
	# A step that is vaguely on the way to the farm — scouts circle, they do
	# not beeline.
	for i in 10:
		var p := from + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
		if _open_ground(p) \
				and Vector2(p).distance_squared_to(Vector2(farm)) \
					< Vector2(from).distance_squared_to(Vector2(farm)):
			return p
	return from

func _forage_spot(den_pos: Vector2i) -> Vector2i:
	# Berries and grubs: prefer forest near the den, settle for any open
	# ground near it.
	var best := Vector2i(-1, -1)
	var pool := []
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var p: Vector2i = den_pos + Vector2i(dx, dy)
			if world.in_bounds(p) and world.get_terrain(p) == world.FOREST \
					and not buildings.has(p):
				pool.append(p)
	if not pool.is_empty():
		return pool[rng.randi_range(0, pool.size() - 1)]
	return _wilds_spot(den_pos, 8, den_pos)

func _open_ground(p: Vector2i) -> bool:
	if world == null or not world.in_bounds(p):
		return false
	var t: int = world.get_terrain(p)
	return (t == world.GRASS or t == world.FOREST) and not buildings.has(p)

func _nearest_complete(kind: String, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != kind or not b.complete:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func adjacent_guards(t: Vector2i) -> int:
	var n := 0
	for a in agents:
		if a.kind == "guard" and a.adjacent_to(t):
			n += 1
	return n

func _nearest_raid_target(from: Vector2i) -> Vector2i:
	for kind in ["farm", "house"]:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p in buildings:
			var b: Dictionary = buildings[p]
			if b.kind != kind or not b.complete:
				continue
			var d := Vector2(p).distance_squared_to(Vector2(from))
			if d < best_d:
				best_d = d
				best = p
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func raid_strike(p: Vector2i, goblin) -> void:
	# The warband puts a building to the torch and pockets what it can carry.
	# Sites still under construction are left alone — nothing to loot there.
	var loot := 0
	if buildings.has(p) and buildings[p].complete:
		var b: Dictionary = buildings[p]
		match b.kind:
			"farm":
				loot = FARM_PLUNDER
				goblin.loot_kind = "food"
			"house", "guardhouse":
				loot = mini(gold, HOUSE_PLUNDER)
				gold -= loot
				goblin.loot_kind = "gold"
		_raze_building(p)
	goblin.carrying = loot

func _raze_building(p: Vector2i) -> void:
	var b: Dictionary = buildings[p]
	match b.kind:
		"farm":
			farms -= 1
		"house":
			houses -= 1
			pop_cap = maxi(1, pop_cap - 3)
		"guardhouse":
			_remove_guards_of(p)
	buildings.erase(p)
	buildings_razed += 1
	last_event = "Goblins razed the %s!" % b.kind

func _remove_guards_of(p: Vector2i) -> void:
	for a in agents:
		if a.kind == "guard" and a.home == p and not _removals.has(a):
			_removals.append(a)

func raid_returned(goblin) -> void:
	# Warband survivors regroup at the den; a raid that lands loot makes the
	# den grow bolder (bigger musters, bolder moods next time).
	var loot: int = goblin.carrying
	goblin.state = AgentC.IDLE
	goblin.purpose = ""
	deliver(goblin)
	if loot > 0 and dens.has(goblin.home):
		var den: Dictionary = dens[goblin.home]
		if int(den.level) < DEN_MAX_LEVEL:
			den.level = int(den.level) + 1
			last_event = "The goblin den grows bolder"

func _assign_guards() -> void:
	var gobs := []
	var guards := []
	for a in agents:
		if a.kind == "goblin":
			gobs.append(a)
		elif a.kind == "guard":
			guards.append(a)
	# Spread out: a goblin already engaged attracts fewer new guards.
	var engaged := {}
	for g in guards:
		if g.purpose == AgentC.INTERCEPT and g.target_agent != null \
				and agents.has(g.target_agent):
			engaged[g.target_agent] = int(engaged.get(g.target_agent, 0)) + 1
	for g in guards:
		if g.state == AgentC.FLEEING:
			continue
		if g.purpose == AgentC.INTERCEPT:
			var quarry = g.target_agent
			var quarry_valid: bool = quarry != null and agents.has(quarry) \
				and quarry.kind == "goblin" and quarry.state != AgentC.FLEEING \
				and _within_leash(quarry.tile())
			if not quarry_valid:
				# The quarry fell, broke and ran, or left the watch's leash:
				# guards defend the realm, not the wilds.
				g.target_agent = null
				g.purpose = ""
				g.state = AgentC.IDLE
			elif not g.adjacent_to(quarry.tile()):
				var t: Vector2i = quarry.tile()
				if t != g.target:
					g.target = t
					g.path = find_path(g.tile(), t)
			continue
		if g.state != AgentC.IDLE:
			continue
		var gob = _pick_goblin(gobs, g.tile(), engaged)
		if gob != null:
			engaged[gob] = int(engaged.get(gob, 0)) + 1
			g.chase(gob)
			continue
		if g.behavior_left > 0:
			g.behavior_left -= 1
			continue
		_roll_guard_behavior(g)

func _roll_guard_behavior(g) -> void:
	# The watch has its own weighted moods: walk a round, or stand easy.
	var roll := _weighted_intent({"patrol": 55, "lurk": 45})
	g.behavior = roll
	match roll:
		"lurk":
			g.behavior_left = 20 + rng.randi_range(0, 30)
		_:
			g.assign(_patrol_spot(g.home), AgentC.PATROL)
			g.behavior_left = 20 + rng.randi_range(0, 30)

func _within_leash(t: Vector2i) -> bool:
	return Vector2(t).distance_to(Vector2(keep_pos)) <= GUARD_LEASH

func _guard_respawn() -> void:
	# A guardhouse slowly re-trains its watch after losses. The countdown
	# only runs while short-handed, so a change of training pace takes
	# effect at the next loss.
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "guardhouse" or not b.complete:
			continue
		var alive := 0
		for a in agents:
			if a.kind == "guard" and a.home == p:
				alive += 1
		if alive >= GUARDS_PER_GUARDHOUSE:
			if b.has("retrain"):
				b.erase("retrain")
			continue
		if not b.has("retrain"):
			b.retrain = guard_retrain_ticks
		b.retrain = int(b.retrain) - 1
		if int(b.retrain) <= 0:
			_spawn_guard(p)
			b.retrain = guard_retrain_ticks
			last_event = "The guardhouse trains a new watchman"

func _pick_goblin(gobs: Array, from: Vector2i, engaged: Dictionary):
	# Nearest goblin still pressing the raid, preferring one no guard is
	# already on. Fleeing stragglers are written off — chasing them drags
	# the watch away from the realm — and so are goblins beyond the leash:
	# the watch never chases into the wilds.
	var best = null
	var best_d := INF
	var best_free = null
	var best_free_d := INF
	for a in gobs:
		if a.state == AgentC.FLEEING or not _within_leash(a.tile()):
			continue
		var d := Vector2(a.tile()).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = a
		if int(engaged.get(a, 0)) == 0 and d < best_free_d:
			best_free_d = d
			best_free = a
	return best_free if best_free != null else best

func _patrol_spot(home: Vector2i) -> Vector2i:
	for i in 8:
		var p := home + Vector2i(rng.randi_range(-GUARD_PATROL_RADIUS, GUARD_PATROL_RADIUS),
			rng.randi_range(-GUARD_PATROL_RADIUS, GUARD_PATROL_RADIUS))
		if world != null and world.in_bounds(p) and world.get_terrain(p) != world.MOUNTAIN \
				and world.get_terrain(p) != world.WATER and not buildings.has(p):
			return p
	return home

func _combat_step() -> void:
	# Simple attrition: foes on neighbouring tiles trade blows. A fighter who
	# drops to the flee threshold breaks for home; anyone at 0 hp is reaped.
	var gobs := []
	var guards := []
	for a in agents:
		if a.kind == "goblin":
			gobs.append(a)
		elif a.kind == "guard":
			guards.append(a)
	for gob in gobs:
		var attackers := 0
		for g in guards:
			if g.adjacent_to(gob.tile()):
				attackers += 1
		if attackers > 0:
			# Combat interrupts behavior: the goblin turns to defend itself.
			gob.fighting = true
			gob.behavior_left = 0
			gob.hurt(attackers)
	for g in guards:
		var enemies := 0
		for gob in gobs:
			if gob.adjacent_to(g.tile()):
				enemies += 1
		if enemies > 0:
			g.hurt(enemies)
	for p in dens.duplicate():
		var den: Dictionary = dens[p]
		var besiegers := 0
		for g in guards:
			if g.adjacent_to(p):
				besiegers += 1
		if besiegers > 0:
			den.hp -= besiegers
			if den.hp <= 0:
				_clear_den(p)

func _clear_den(p: Vector2i) -> void:
	dens.erase(p)
	dens_cleared += 1
	for a in agents:
		if a.kind == "goblin" and a.home == p and not _removals.has(a):
			_removals.append(a)
	# A cleared lair buys peace — but the wild always creeps back.
	den_respawn_rest_left = den_respawn_rest + rng.randi_range(0, 600)
	last_event = "The goblin den was cleared!"

func _reap() -> void:
	var guard_fell := false
	for a in agents:
		if (a.kind == "guard" or a.kind == "goblin") and a.hp <= 0 \
				and not _removals.has(a):
			_removals.append(a)
			if a.kind == "guard":
				guards_fallen += 1
				guard_fell = true
	if guard_fell:
		last_event = "A guard fell in battle!"
	for x in _removals:
		agents.erase(x)
	_removals.clear()

func _spawn_guard(guardhouse: Vector2i) -> void:
	var a = AgentC.new()
	a.setup(self, "guard", guardhouse)
	a.home = guardhouse
	agents.append(a)

func _spawn_goblin(den_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.setup(self, "goblin", den_doorstep(den_pos, keep_pos))
	a.home = den_pos
	agents.append(a)
