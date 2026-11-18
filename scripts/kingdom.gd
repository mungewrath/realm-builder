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

# Buildings that owe the crown taxes: rate per accrual round, purse cap.
# Shrines and guardhouses are crown service — they earn nothing. Farms pay
# a tithe on top of feeding the realm; markets earn best.
const BUILD_TAX := {
	"farm": {"rate": 1, "cap": 6},
	"house": {"rate": 1, "cap": HOUSE_TAX_CAP},
	"tavern": {"rate": 2, "cap": 20},
	"market": {"rate": 3, "cap": 30},
}

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

const TAVERN_COST := 25
const MARKET_COST := 30
const SHRINE_COST := 35

const BUILD_COSTS := {
	"farm": FARM_COST,
	"house": HOUSE_COST,
	"guardhouse": GUARDHOUSE_COST,
	"tavern": TAVERN_COST,
	"market": MARKET_COST,
	"shrine": SHRINE_COST,
}

# M4 — heroes & attraction (the indirect-control core). Heroes arrive on
# their own, score the world against their personality table, and act on
# their own judgment. The player nudges with buildings, gold, and bounty
# flags — never commands. Adding a class is a content row, not code.
# Base stats are tuned so a fresh hero can handle a small goblin mob
# (2-3 raiders): goblins hit for 1 each per round, a level-1 hero swings
# for 2 and breaks off to heal before dying.
const HERO_CLASSES := {
	"rogue": {
		"title": "Rogue",
		"attracted_by": "tavern",
		"hp": 10,
		"weights": {"bounty": 4, "treasure": 9, "smite_evil": 1, "assist": 0,
			"hunt": 5, "pray": 0, "carouse": 3},
	},
	"warrior": {
		"title": "Warrior",
		"attracted_by": "guardhouse",
		"hp": 14,
		"weights": {"bounty": 8, "treasure": 4, "smite_evil": 3, "assist": 3,
			"hunt": 3, "pray": 1, "carouse": 2},
	},
	"paladin": {
		"title": "Paladin",
		"attracted_by": "shrine",
		"hp": 18,
		"weights": {"bounty": 3, "treasure": 0, "smite_evil": 9, "assist": 4,
			"hunt": 0, "pray": 6, "carouse": 0},
	},
}
# Ventures outrank leisure, leisure outranks idle strolling; ties break
# toward the earlier entry.
const HERO_GOAL_PRIORITY := ["rest", "shop", "smite", "bounty", "treasure",
	"hunt", "pray", "carouse", "explore", "assist", "patrol"]

const HERO_PURSE_TARGET := 10
const HERO_FATIGUE_MAX := 5
const HERO_REST_TICKS := 10
const HERO_XP_PER_LEVEL := 4
const BOUNTY_FEE := 20
const BOUNTY_OVERHEAD := 2 # the posting office's cut; the rest lands on the flag

# M5 — exploration & fog of war. The map starts dark; the keep charts its
# surroundings at the start, and heroes (keen eyes, long roam) and the
# realm's workers chart more as they move. Charted ground stays revealed
# permanently — no re-dimming. Goblins reveal nothing; the wild keeps its
# secrets. Fog is presentation plus a build gate: the wilds are simulated
# the same as ever, only unseen. Radii are vars so tests can tweak them.
const KEEP_REVEAL := 7.0
const HERO_REVEAL := 4.0
const WORKER_REVEAL := 2.0

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

# The keep's household scrapes together a slow trickle of coin (per minute
# of normal time), so a realm that spends its last gold on the wrong
# building can still dig itself out. Vars so tests/tuning can adjust.
var keep_trickle := 5
var keep_trickle_ticks := 60

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

# M6.1 — ecology. Dens are content rows: where they can squat, what units
# they raise, and what they eat. Goblins are one row among many; prey dens
# regrow their larder from the land, predator dens hunt other dens' stores
# (den-stock predation — no wild unit combat in this chunk). Every wild den
# tracks unmet needs: a long-empty larder migrates the den or starves it.
# All knobs are vars so tests and tuning can adjust them.
const DEN_KINDS := {
	"goblin_den": {
		"title": "Goblin Den",
		"faction": "goblinkin",
		"hostile": true,
		"site": "mountain_edge",
		"spies_as": "A goblin den is spied in the wilds!",
	},
	"rabbit_warren": {
		"title": "Rabbit Warren",
		"faction": "wilders",
		"hostile": false,
		"site": "grass",
		"role": "prey",
		"unit": "rabbit",
		"spies_as": "A warren of rabbits is spied in the meadows!",
	},
	"wolf_den": {
		"title": "Wolf Den",
		"faction": "wilders",
		"hostile": false,
		"site": "forest",
		"role": "predator",
		"unit": "wolf",
		"diet": ["rabbit_warren"],
		"fallback": "farm", # warrens gone: packs raid farm stores
		"spies_as": "A wolf den is spied in the deep woods!",
	},
	"spider_den": {
		"title": "Giant Spider Nest",
		"faction": "wilders",
		"hostile": false,
		"site": "forest",
		"role": "predator",
		"unit": "spider",
		"diet": ["goblin_den"],
		"spies_as": "A giant spider nest is spied in the woods!",
	},
}

# Per-species agent stats: pace and constitution (creatures are not
# combatants in this chunk, but the agent layer wants both).
const CREATURE_STATS := {
	"rabbit": {"speed": 2.2, "hp": 1, "carry": 2},
	"wolf": {"speed": 3.0, "hp": 3, "carry": 3},
	"spider": {"speed": 2.4, "hp": 3, "carry": 2},
}

const WILD_DEN_FOOD_START := 5
const PREY_FOOD_CAP := 8

# Wild ecology: toggle, caps, and pacing. Existing exact-accounting suites
# run with `wild_ecology` off, same pattern as fog and the gold trickle.
var wild_ecology := true
var wild_dens_max := 3
var wild_spawn_chance := 0.2
var wild_spawn_weights := {"rabbit_warren": 40, "wolf_den": 35, "spider_den": 25}
var den_migrate_ticks := 300
var prey_regrow_ticks := 30
var wild_den_rest := 400
var dens_migrated := 0
var dens_starved := 0
var wild_dens_spawned := 0
var wild_respawn_rest_left := 0
var hunts_made := 0

# M4 — heroes. Attraction pace and hero count are vars so tests and tuning
# can adjust them. Bounties are the player's one-tap flags on dens; loot
# piles are what fallen heroes (and cleared dens) leave behind.
var heroes_enabled := true
var hero_attraction_ticks := 45 # a roll every ~45s of normal time
var _hero_attraction_left := 45
var hero_arrival_chance := 0.75
# Finishing a hall of any kind pulls the next attraction roll forward to
# this — the first hero steps out within seconds of the door opening.
var hero_first_arrival_ticks := 10
var hero_cap := 4
# After a hunt or a tavern evening, leisure is off the books for this
# long — heroes rotate between pastimes and the wilds instead of
# grinding one warren (or one dice table) until it runs dry.
var hero_leisure_cooldown := 60
var heroes_spawned := 0
var heroes_fallen := 0
var dens_cleared_by_heroes := 0
var market_sales := 0
var taverns := 0
var markets := 0
var shrines := 0
var bounties := {} # den tile -> {reward}
var bounties_posted := 0
var bounties_paid := 0
var loot_piles := {} # tile -> gold

# M5 — fog state: one layer. `explored` is the map you have charted, and
# charted ground stays lit for good. Open-ground accounting lets the
# exploration flood skip the "there is no frontier anywhere" case in O(1)
# instead of flooding the whole charted map per hero decision.
var fog_enabled := true
var explored := PackedByteArray() # 0 unseen, 1 revealed (permanent)
var open_tiles := PackedByteArray() # 1 for grass/forest tiles
var open_tile_total := 0
var open_tiles_explored := 0
var uncharted_open := {} # open tiles no one has charted yet
var sealed_frontiers := {} # frontier tiles proven unreachable by pathing
var tiles_explored := 0
var landmarks_spotted := 0

# Provisions capacity of the realm: complete farms feed people.
func fed_capacity() -> int:
	return farms * FARM_CAPACITY_POP

func attach_world(w) -> void:
	world = w
	rng.seed = 777
	keep_pos = Vector2i(int(w.SIZE_X / 2.0), int(w.SIZE_Y / 2.0))
	buildings[keep_pos] = {"kind": "castle", "complete": true, "tax": 0}
	explored.resize(w.SIZE_X * w.SIZE_Y)
	open_tiles.resize(w.SIZE_X * w.SIZE_Y)
	for i in w.SIZE_X * w.SIZE_Y:
		var t: int = w.tiles[i]
		if t == w.GRASS or t == w.FOREST:
			open_tiles[i] = 1
			open_tile_total += 1
			uncharted_open[Vector2i(i % w.SIZE_X, i / w.SIZE_X)] = true
	if fog_enabled:
		_stamp_explored(keep_pos, KEEP_REVEAL)
	else:
		_reveal_everything()
	for i in START_POP:
		_spawn_peasant()
	_spawn_dens()
	if wild_ecology:
		_seed_wild_dens()

func set_fog_enabled(on: bool) -> void:
	# Dev/tuning toggle. Turning fog back on re-charts from where the realm
	# actually stands now: the keep's ground and every friendly agent.
	if fog_enabled == on:
		return
	fog_enabled = on
	for a in agents:
		a.fog_tile = Vector2i(-1, -1)
	if on:
		explored.fill(0)
		tiles_explored = 0
		open_tiles_explored = 0
		uncharted_open.clear()
		sealed_frontiers.clear()
		for i in open_tiles.size():
			if open_tiles[i] == 1:
				uncharted_open[Vector2i(i % world.SIZE_X, i / world.SIZE_X)] = true
		landmarks_spotted = 0
		_fog_tick()
	else:
		_reveal_everything()

func _reveal_everything() -> void:
	explored.fill(1)
	tiles_explored = explored.size()
	open_tiles_explored = open_tile_total
	uncharted_open.clear()
	sealed_frontiers.clear()

func _reveal_radius(a) -> float:
	return HERO_REVEAL if a.kind == "hero" else WORKER_REVEAL

func _stamp_explored(p: Vector2i, radius: float) -> void:
	# Chart a disc of tiles around `p`; newly charted dens are landmarks.
	var r := int(ceili(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > radius:
				continue
			var q := p + Vector2i(dx, dy)
			if not world.in_bounds(q):
				continue
			var i: int = q.y * world.SIZE_X + q.x
			if explored[i] == 1:
				continue
			explored[i] = 1
			tiles_explored += 1
			if open_tiles[i] == 1:
				open_tiles_explored += 1
				uncharted_open.erase(q)
			if dens.has(q):
				landmarks_spotted += 1
				var kind_key: String = dens[q].get("kind", "goblin_den")
				last_event = DEN_KINDS[kind_key].spies_as

func _fog_tick() -> void:
	if not fog_enabled:
		return
	for a in agents:
		# Only the realm's folk chart the map. Goblins and wild creatures
		# reveal nothing — the wild keeps its secrets.
		if a.kind == "goblin" or a.kind == "creature":
			continue
		var t: Vector2i = a.tile()
		if t != a.fog_tile:
			a.fog_tile = t
			_stamp_explored(t, _reveal_radius(a))

func explored_at(p: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return world.in_bounds(p) and explored[p.y * world.SIZE_X + p.x] == 1

func find_path(from: Vector2i, to: Vector2i) -> Array:
	return world.find_path(from, to)

func can_build_at(p: Vector2i) -> bool:
	if world == null or not world.is_buildable(p) or buildings.has(p):
		return false
	# Wild dens are occupied ground: no raising walls over a warren.
	if dens.has(p):
		return false
	# You cannot raise walls on land no one has charted.
	return explored_at(p)

func build_at(kind: String, p: Vector2i) -> bool:
	if not BUILD_COSTS.has(kind):
		last_event = "Unknown building"
		return false
	if not can_build_at(p):
		last_event = "That land is unexplored" \
			if (world != null and world.in_bounds(p) and not explored_at(p)) \
			else "Wild beasts den there" if dens.has(p) else "Cannot build there"
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
		"tavern":
			taverns += 1
		"market":
			markets += 1
		"shrine":
			shrines += 1
	# A newly finished hero hall pulls the next attraction roll forward:
	# heroes show up within seconds of the door opening, not after a stale
	# cycle has ground its way around.
	if _is_hero_hall(b.kind) and _count_kind("hero") < hero_cap:
		_hero_attraction_left = mini(_hero_attraction_left, hero_first_arrival_ticks)
	last_event = "Finished building " + b.kind

func _is_hero_hall(kind: String) -> bool:
	for cls in HERO_CLASSES:
		if HERO_CLASSES[cls].attracted_by == kind:
			return true
	return false

func take_tax(p: Vector2i) -> int:
	var t: int = buildings[p].tax
	buildings[p].tax = 0
	tax_collected += t
	return t

func update() -> void:
	tick += 1
	_keep_trickle_tick()
	if collector == null and houses > 0:
		_spawn_collector()
	_accrue_tax()
	_assign_jobs()
	_route_collector()
	if raids_enabled:
		_dens_tick()
		_assign_guards()
	if wild_ecology:
		_wild_dens_tick()
		_wild_creatures_tick()
	if heroes_enabled:
		_attraction_tick()
		_assign_heroes()
	for a in agents:
		a.update()
	_fog_tick()
	# Combat is adjacency-driven; with no foes around it is a cheap no-op,
	# so it runs regardless of the raid toggle (hero tests rely on it).
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

func _keep_trickle_tick() -> void:
	# A soft floor under the economy: even a broke realm earns pocket coin.
	if tick % int(keep_trickle_ticks) == 0:
		gold += keep_trickle

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
		"goblin", "creature":
			# Foraged roots, grazed browse and hunted prey all end up in the
			# home den's stores.
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
		if not b.complete:
			continue
		var row: Dictionary = BUILD_TAX.get(b.kind, {})
		if row.is_empty():
			continue
		b.tax = mini(int(b.tax) + int(row.rate), int(row.cap))

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
		if b.complete and int(b.tax) > 0:
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
			"kind": "goblin_den",
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
	# Goblin lairs refill on their own clock; wild dens (ecology) do not
	# crowd them out of the cap.
	if _count_hostile_dens() >= dens_max:
		return
	if den_respawn_rest_left > 0:
		den_respawn_rest_left -= 1
		return
	if not _try_spawn_den():
		# No suitable lair right now: look again after a while.
		den_respawn_rest_left = 200 + rng.randi_range(0, 200)

func _count_hostile_dens() -> int:
	var n := 0
	for p in dens:
		if is_hostile_den(p):
			n += 1
	return n

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
		"kind": "goblin_den",
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
	# periodically imposes a weighted-random mood on whoever is home. Wild
	# dens (ecology) run their own simpler machine in `_wild_dens_tick`.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "goblin_den") != "goblin_den":
			continue
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
		"tavern":
			taverns -= 1
		"market":
			markets -= 1
		"shrine":
			shrines -= 1
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

# --- M6.1: ecology — wild dens, creatures, food chains ----------------------

func is_hostile_den(p: Vector2i) -> bool:
	return dens.has(p) and DEN_KINDS[dens[p].get("kind", "goblin_den")].hostile

func _wild_den_site(kind_key: String, near := Vector2i(-99, -99), near_r := 0,
		clearance := DEN_CIV_CLEARANCE, min_keep := DEN_WILD_MIN) -> Vector2i:
	# A suitable squat for a wild den: right terrain, clear of every other
	# den and building, and (unless migrating toward prey) far from the keep.
	var terrain_want: int = world.GRASS if DEN_KINDS[kind_key].site == "grass" \
		else world.FOREST
	var best := Vector2i(-1, -1)
	var pool := []
	for y in world.SIZE_Y:
		for x in world.SIZE_X:
			var p := Vector2i(x, y)
			if world.get_terrain(p) != terrain_want or dens.has(p) or buildings.has(p):
				continue
			if near_r <= 0:
				if Vector2(p).distance_to(Vector2(keep_pos)) < min_keep:
					continue
			elif Vector2(p).distance_to(Vector2(near)) > near_r:
				continue
			var near_civ := false
			for b in buildings:
				if Vector2(b).distance_to(Vector2(p)) < clearance:
					near_civ = true
					break
			if near_civ:
				continue
			pool.append(p)
	if pool.is_empty():
		return best
	return pool[rng.randi_range(0, pool.size() - 1)]

func _seed_wild_dens() -> void:
	# The starting wilds hold prey and a predator: a warren to graze and a
	# wolf pack to stalk it. Spiders arrive only with the regrowth. Some
	# worlds have no deep forest; the seed falls back to shallower ground
	# rather than leaving the wilds empty.
	var warren := _wild_den_site("rabbit_warren")
	if warren.x < 0:
		warren = _wild_den_site("rabbit_warren", Vector2i(-99, -99), 0, 4, 8)
	if warren.x >= 0:
		_place_wild_den("rabbit_warren", warren)
	var woods := _wild_den_site("wolf_den")
	if woods.x < 0:
		woods = _wild_den_site("wolf_den", Vector2i(-99, -99), 0, 4, 8)
	if woods.x >= 0:
		_place_wild_den("wolf_den", woods)
	wild_respawn_rest_left = wild_den_rest + rng.randi_range(0, 300)

func _place_wild_den(kind_key: String, p: Vector2i, food := WILD_DEN_FOOD_START) -> void:
	dens[p] = {
		"kind": kind_key,
		"level": 1,
		"hp": den_hp,
		"food": food,
		"gold": 0,
		"unmet": 0,
		"regrow": 0,
	}
	var unit: String = DEN_KINDS[kind_key].unit
	for i in (2 if unit != "spider" else 1):
		_spawn_creature(unit, p)
	if not fog_enabled or not explored[p.y * world.SIZE_X + p.x]:
		return
	# Charted ground at placement time: count it as spotted land only.
	if DEN_KINDS[kind_key].spies_as != "":
		last_event = DEN_KINDS[kind_key].spies_as

func _wild_respawn_tick() -> void:
	if _count_wild_dens() >= wild_dens_max:
		return
	if wild_respawn_rest_left > 0:
		wild_respawn_rest_left -= 1
		return
	if not _try_spawn_wild_den():
		wild_respawn_rest_left = 200 + rng.randi_range(0, 200)

func _count_wild_dens() -> int:
	var n := 0
	for p in dens:
		if dens[p].get("kind", "goblin_den") != "goblin_den":
			n += 1
	return n

func _try_spawn_wild_den() -> bool:
	if rng.randf() > wild_spawn_chance:
		return false
	var kind_key := _weighted_intent(wild_spawn_weights)
	var p := _wild_den_site(kind_key)
	if p.x < 0:
		return false
	_place_wild_den(kind_key, p)
	wild_dens_spawned += 1
	wild_respawn_rest_left = wild_den_rest + rng.randi_range(0, 300)
	return true

func _wild_dens_tick() -> void:
	# Wild den upkeep: prey larders regrow from the land; every den counts
	# unmet needs while empty and, past the threshold, moves on or dies off.
	for p in dens.keys():
		var den: Dictionary = dens[p]
		var kind_key: String = den.get("kind", "goblin_den")
		if kind_key == "goblin_den":
			continue # goblins raid instead of migrating; hunger drives them
		if DEN_KINDS[kind_key].role == "prey":
			den.regrow = int(den.regrow) + 1
			if int(den.regrow) >= prey_regrow_ticks:
				den.regrow = 0
				den.food = mini(int(den.food) + 1, PREY_FOOD_CAP)
		if int(den.food) > 0:
			den.unmet = 0
			continue
		den.unmet = int(den.unmet) + 1
		if int(den.unmet) >= den_migrate_ticks:
			var dest := _migration_site(p, den)
			if dest.x < 0:
				_starve_den(p, den)
			else:
				_migrate_den(p, den, dest)
	_wild_respawn_tick()

func _migration_site(p: Vector2i, den: Dictionary) -> Vector2i:
	# Where a starving den moves: predators follow their prey (a warren of
	# rabbits, say); wolves with no warrens left stalk toward the farm
	# stores, or else roam the far wilds and raid from there; prey dens
	# seek fresh meadows. Spiders with no goblin dens to snare have
	# nowhere to go — they starve.
	var kind_key: String = den.get("kind", "goblin_den")
	var row: Dictionary = DEN_KINDS[kind_key]
	if row.role == "predator":
		var prey := _nearest_prey_den(p, row.diet)
		if prey.x >= 0:
			return _wild_den_site(kind_key, prey, 6)
		if row.has("fallback"):
			var farm := _nearest_complete(row.fallback, p)
			if farm.x >= 0:
				var near_farm := _wild_den_site(kind_key, farm, 7, 2)
				if near_farm.x >= 0:
					return near_farm
			return _wild_den_site(kind_key)
		return Vector2i(-1, -1)
	return _wild_den_site(kind_key)

func _migrate_den(p: Vector2i, den: Dictionary, dest: Vector2i) -> void:
	dens.erase(p)
	dens[dest] = den
	den.unmet = 0
	for a in agents:
		if a.kind == "creature" and a.home == p:
			a.home = dest
	dens_migrated += 1
	last_event = "The %s moved on to richer grounds" % DEN_KINDS[den.kind].title

func _starve_den(p: Vector2i, den: Dictionary) -> void:
	dens.erase(p)
	dens_starved += 1
	for a in agents:
		if a.kind == "creature" and a.home == p and not _removals.has(a):
			_removals.append(a)
	last_event = "The %s has starved out of the wilds" % DEN_KINDS[den.kind].title

func _nearest_prey_den(from: Vector2i, diet: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in dens:
		if not diet.has(dens[p].get("kind", "")):
			continue
		if int(dens[p].food) <= 0:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _hunter_out(den_pos: Vector2i) -> bool:
	for a in agents:
		if a.kind == "creature" and a.home == den_pos \
				and a.purpose == AgentC.HUNT:
			return true
	return false

func _hunt_target(a) -> Vector2i:
	var den: Dictionary = dens.get(a.home, {})
	var row: Dictionary = DEN_KINDS[den.get("kind", "goblin_den")]
	var prey := _nearest_prey_den(a.home, row.diet)
	if prey.x >= 0:
		return prey
	if row.has("fallback"):
		var farm := _nearest_complete(row.fallback, a.tile())
		if farm.x >= 0:
			return farm
	return Vector2i(-1, -1)

func hunt_strike(p: Vector2i, hunter) -> void:
	# The predator takes what it can from its prey's larder — or, when the
	# wild prey is gone, strips a farm's stores (no torch, no raze: the
	# wolves want meat, not ashes).
	var taken := 0
	if dens.has(p):
		taken = mini(CREATURE_STATS[hunter.species].carry, int(dens[p].food))
		dens[p].food = int(dens[p].food) - taken
	elif buildings.has(p) and buildings[p].complete:
		taken = FARM_PLUNDER
		last_event = "Wolves strip a farm's stores in the night!"
	hunts_made += 1
	hunter.carrying = taken
	hunter.loot_kind = "food"

func _wild_creatures_tick() -> void:
	for a in agents:
		if a.kind != "creature":
			continue
		if a.state != AgentC.IDLE:
			continue
		if a.behavior_left > 0:
			a.behavior_left -= 1
			continue
		_roll_creature_behavior(a)

func _roll_creature_behavior(a) -> void:
	var den: Dictionary = dens.get(a.home, {})
	if a.species == "rabbit":
		var roll := _weighted_intent({"graze": 60, "wander": 25, "lurk": 15})
		match roll:
			"graze":
				a.assign(_graze_spot(a.home), AgentC.FORAGE)
				a.behavior_left = 40
			"wander":
				a.assign(_wilds_spot(a.home, 5, a.tile()), AgentC.WANDER)
				a.behavior_left = 15 + rng.randi_range(0, 15)
			_:
				a.behavior = "lurk"
				a.behavior_left = 10 + rng.randi_range(0, 20)
		return
	# Predators: hunt when the larder runs low and no packmate is already
	# out; otherwise prowl lazily around the den. No grazing — meat does
	# not grow on bushes; a predator's larder only grows by hunting.
	if int(den.get("food", 0)) <= DEN_HUNGRY_FOOD and not _hunter_out(a.home):
		var prey := _hunt_target(a)
		if prey.x >= 0:
			a.assign(prey, AgentC.HUNT)
			a.behavior_left = 80
			return
	var roll := _weighted_intent({"lurk": 60, "wander": 40})
	if roll == "lurk":
		a.behavior = "lurk"
		a.behavior_left = 20 + rng.randi_range(0, 30)
	else:
		a.assign(_wilds_spot(a.home, 6, a.tile()), AgentC.WANDER)
		a.behavior_left = 20 + rng.randi_range(0, 20)

func _graze_spot(den_pos: Vector2i) -> Vector2i:
	# Meadow browse: prefer open grass near the den, settle for any open
	# ground around it.
	var pool := []
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var p: Vector2i = den_pos + Vector2i(dx, dy)
			if _open_ground(p) and world.get_terrain(p) == world.GRASS:
				pool.append(p)
	if not pool.is_empty():
		return pool[rng.randi_range(0, pool.size() - 1)]
	return _wilds_spot(den_pos, 6, den_pos)

func _spawn_creature(species_name: String, den_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.species = species_name
	a.setup(self, "creature", den_pos)
	a.home = den_pos
	agents.append(a)

# --- M4: heroes & attraction ------------------------------------------------

func post_bounty(den_pos: Vector2i) -> bool:
	# The player's one-tap nudge: a flag with gold on it. Heroes weigh it
	# against everything else and decide for themselves. Only hostile dens
	# are bounty-able — wild beasts are not a den of evil.
	if not is_hostile_den(den_pos):
		last_event = "That lair is no den of evil"
		return false
	if gold < BOUNTY_FEE:
		last_event = "Not enough gold for the bounty"
		return false
	gold -= BOUNTY_FEE
	# The fee funds the flag; only the net amount is ever claimable.
	var net: int = BOUNTY_FEE - BOUNTY_OVERHEAD
	if bounties.has(den_pos):
		bounties[den_pos].reward += net
	else:
		bounties[den_pos] = {"reward": net}
		bounties_posted += 1
	last_event = "A bounty flag flies over the den!"
	return true

func _attraction_tick() -> void:
	# The realm's reputation does the recruiting: a periodic roll whose
	# weights come straight from the building mix.
	_hero_attraction_left -= 1
	if _hero_attraction_left > 0:
		return
	_hero_attraction_left = hero_attraction_ticks
	if _count_kind("hero") >= hero_cap:
		return
	var mix := _attraction_mix()
	if mix.is_empty():
		return
	if rng.randf() > hero_arrival_chance:
		return
	_spawn_hero(_weighted_intent(mix))

func _attraction_mix() -> Dictionary:
	var mix := {}
	for p in buildings:
		var b: Dictionary = buildings[p]
		if not b.complete:
			continue
		for cls in HERO_CLASSES:
			if HERO_CLASSES[cls].attracted_by == b.kind:
				mix[cls] = int(mix.get(cls, 0)) + 1
	return mix

func _spawn_hero(cls: String) -> void:
	# Heroes arrive where their kind belongs: a rogue steps out of the
	# tavern, a warrior signs on at the guardhouse, a paladin at the
	# shrine. The attraction roll guarantees the hall exists by now.
	var hall := _pick_hall(cls)
	var a = AgentC.new()
	a.setup(self, "hero", hall)
	a.hero_class = cls
	a.max_hp = int(HERO_CLASSES[cls].hp)
	a.hp = a.max_hp
	a.home = hall
	a.assign(a.home, AgentC.RECRUIT)
	agents.append(a)
	heroes_spawned += 1
	last_event = "A %s strides out of the %s" \
		% [HERO_CLASSES[cls].title, HERO_CLASSES[cls].attracted_by]

func _pick_hall(cls: String) -> Vector2i:
	# A random complete hall of the class's attracting kind; the keep is
	# the fallback of last resort.
	var kind: String = HERO_CLASSES[cls].attracted_by
	var pool := []
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind == kind and b.complete:
			pool.append(p)
	if pool.is_empty():
		return keep_pos
	return pool[rng.randi_range(0, pool.size() - 1)]

func _count_kind(kind: String) -> int:
	var n := 0
	for a in agents:
		if a.kind == kind:
			n += 1
	return n

func _count_complete(kind: String) -> int:
	var n := 0
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind == kind and b.complete:
			n += 1
	return n

func _nearest_den(from: Vector2i) -> Vector2i:
	# Smite targets are dens of evil, not rabbit burrows.
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in dens:
		if not is_hostile_den(p):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_pile(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in loot_piles:
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _best_bounty(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_reward := -1
	var best_d := INF
	for p in bounties:
		var reward: int = int(bounties[p].reward)
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if reward > best_reward or (reward == best_reward and d < best_d):
			best_reward = reward
			best_d = d
			best = p
	return best

func hero_rest_spot(h) -> Vector2i:
	var t := _nearest_complete("tavern", h.tile())
	return t if t.x >= 0 else keep_pos

func hero_goal_scores(h) -> Dictionary:
	# The heart of indirect control: pure, table-driven incentive scoring.
	# Personality weights from the content row decide what this hero cares
	# about; the world decides what is actually available — and the fog
	# decides what the hero has heard of. Dens and loot in uncharted land
	# simply do not exist as options yet.
	var w: Dictionary = HERO_CLASSES[h.hero_class].weights
	var scores := {}
	if h.pouch >= HERO_PURSE_TARGET and _count_complete("market") > 0:
		scores["shop"] = 10 + int(w.treasure)
	if h.fatigue >= HERO_FATIGUE_MAX:
		scores["rest"] = 12 + h.fatigue
	if not bounties.is_empty() and int(w.bounty) > 0:
		# Bounties fly only over dens the player could see, so they are
		# charted by construction.
		var best_reward := 0
		for p in bounties:
			best_reward = maxi(best_reward, int(bounties[p].reward))
		# The flag's size does the pulling — a pittance tempts, a fortune
		# drags even the reluctant out the door — while personality only
		# tints how tempting flags are at all.
		scores["bounty"] = int(w.bounty) + int(best_reward / 4.0)
	var known_dens := _dens_known_to_realm()
	if int(w.smite_evil) > 0 and not known_dens.is_empty():
		var top := 1
		for p in known_dens:
			top = maxi(top, int(dens[p].level))
		scores["smite"] = int(w.smite_evil) + top
	var known_piles := _piles_known_to_realm()
	if int(w.treasure) > 0 and not known_piles.is_empty():
		var best_gold := 0
		for p in known_piles:
			best_gold = maxi(best_gold, int(loot_piles[p]))
		# A pile is certain gold; a bounty means a fight first. Risk-adjusted,
		# free coin on the ground scores a good deal higher.
		scores["treasure"] = int(w.treasure) * 2 + int(best_gold / 4.0)
	# Leisure: hunting warrens, prayer, tavern evenings — the idle hours
	# that keep heroes from marching like clockwork. Each only exists when
	# the realm actually offers it, ventures always outrank them, and the
	# chase itself is for fresh legs: a hero grows tired of hunting long
	# before the warren runs dry, leaving the game to the wolves. A recent
	# round of leisure dulls the appetite (halved score, so quarter weight
	# in the draw) but never locks the door — rotation comes from the
	# odds, not from gates.
	var known_warrens := _warrens_known_to_realm()
	var leisure_damp := 2 if h.leisure_left > 0 else 1
	if int(w.get("hunt", 0)) > 0 and not known_warrens.is_empty() \
			and h.fatigue <= 2:
		var best_game := 0
		for p in known_warrens:
			best_game = maxi(best_game, int(dens[p].food))
		scores["hunt"] = (int(w.hunt) + int(best_game / 4.0)) / leisure_damp
	if int(w.get("pray", 0)) > 0 and _count_complete("shrine") > 0 \
			and h.fatigue >= 2:
		# Prayer is for the weary: a fresh paladin has evil to smite.
		scores["pray"] = int(w.pray) * 2
	if int(w.get("carouse", 0)) > 0 and taverns > 0 \
			and h.fatigue < HERO_FATIGUE_MAX:
		# Ale and dice scale with the purse: a hero with plunder to burn
		# leans hard toward the tavern; a broke one mostly stays home.
		# (The market still outranks it while the purse is worth banking.)
		scores["carouse"] = (int(w.carouse) + rng.randi_range(0, 1)
			+ mini(int(h.pouch), 40) / 4) / leisure_damp
	if int(w.assist) > 0 and _nearest_free_site(h.tile()).x >= 0:
		scores["assist"] = int(w.assist)
	# Unknown land beats idle strolling: with no venture on the books, a
	# hero heads for the frontier about half the time (a coin-flip against
	# patrolling, broken toward exploring on the tie).
	if _explore_target(h.tile()).x >= 0:
		scores["explore"] = 1 + rng.randi_range(0, 1)
	scores["patrol"] = 1
	return scores

func _dens_known_to_realm() -> Array:
	# Hostile dens the realm has actually charted — everything else is
	# rumor, and wild beasts are no smiting matter anyway.
	var known := []
	for p in dens:
		if is_hostile_den(p) and explored_at(p):
			known.append(p)
	return known

func _warrens_known_to_realm() -> Array:
	# Hunt grounds: charted warrens that still hold game.
	var known := []
	for p in dens:
		if dens[p].get("kind", "") == "rabbit_warren" \
				and int(dens[p].food) > 0 and explored_at(p):
			known.append(p)
	return known

func _nearest_known_warren(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in _warrens_known_to_realm():
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _piles_known_to_realm() -> Array:
	var known := []
	for p in loot_piles:
		if explored_at(p):
			known.append(p)
	return known

func _explore_target(from: Vector2i) -> Vector2i:
	# Nearest uncharted walkable tile the hero can actually reach. The
	# candidate set is the live list of uncharted open tiles, so probing is
	# a path search with early exit — and a sealed pocket (uncharted land
	# nothing can walk into) is memoized once instead of being re-flooded
	# by every hero decision.
	if not fog_enabled:
		return Vector2i(-1, -1)
	if uncharted_open.is_empty():
		return Vector2i(-1, -1)
	while true:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for c in uncharted_open:
			if sealed_frontiers.has(c):
				continue
			var d := Vector2(c).distance_squared_to(Vector2(from))
			if d < best_d:
				best_d = d
				best = c
		if best.x < 0:
			return Vector2i(-1, -1)
		if not find_path(from, best).is_empty():
			return best
		# Unreachable ground: sealed off by mountains or water. Every hero
		# would reach the same verdict, so remember it.
		sealed_frontiers[best] = true
	var prev := {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in world.DIRS_ALL:
			var n: Vector2i = cur + d
			if not world.in_bounds(n) or prev.has(n):
				continue
			if not _open_ground(n):
				continue
			# Diagonal moves must not squeeze between two blocked tiles.
			if d.x != 0 and d.y != 0:
				if not _open_ground(cur + Vector2i(d.x, 0)) \
						or not _open_ground(cur + Vector2i(0, d.y)):
					continue
			prev[n] = cur
			if explored[n.y * world.SIZE_X + n.x] == 0:
				return n
			queue.append(n)
	return Vector2i(-1, -1)

func _best_hero_goal(scores: Dictionary) -> String:
	# Deterministic pick: highest score wins, ties break toward the fixed
	# priority order. Used by tests (and any UI that wants to show a
	# hero's favored pursuit); live decisions draw by weight instead.
	var best := "patrol"
	var best_v := -1
	for g in HERO_GOAL_PRIORITY:
		if scores.has(g) and int(scores[g]) > best_v:
			best_v = int(scores[g])
			best = g
	return best

func _pick_hero_goal(h, scores: Dictionary) -> String:
	# Overriding priorities come first: safety. An exhausted hero turns
	# in, whatever the dice say. Self-defense needs no goal at all —
	# heroes reflexively fight anything hostile in reach, outside this
	# choice. Everything else is a weighted draw over what the realm
	# offers: favored pursuits are usually taken, but every action on
	# the table keeps a chance — heroes have moods, not gears. Scores
	# square into weights so a fat bounty or a full purse really pulls,
	# while idle options still surface now and then.
	if scores.has("rest") and h.fatigue >= HERO_FATIGUE_MAX:
		return "rest"
	var total := 0
	for g in scores:
		total += int(scores[g]) * int(scores[g])
	if total <= 0:
		return "patrol"
	var roll := rng.randi_range(1, total)
	for g in scores:
		roll -= int(scores[g]) * int(scores[g])
		if roll <= 0:
			return g
	return "patrol"

func _assign_heroes() -> void:
	for a in agents:
		if a.kind != "hero":
			continue
		_hero_level_check(a)
		if a.leisure_left > 0:
			a.leisure_left -= 1
		if a.state != AgentC.IDLE or a.fighting:
			continue
		if a.decision_left > 0:
			a.decision_left -= 1
			continue
		_hero_decide(a)

func _hero_decide(h) -> void:
	var goal := _pick_hero_goal(h, hero_goal_scores(h))
	h.goal = goal
	h.decision_left = 2 + rng.randi_range(0, 4)
	match goal:
		"shop":
			h.assign(_nearest_complete("market", h.tile()), AgentC.SHOP)
		"rest":
			h.assign(hero_rest_spot(h), AgentC.REST)
		"smite":
			var den := _nearest_den(h.tile())
			h.quest_den = den
			h.assign(den_doorstep(den, h.tile()), AgentC.ASSAULT)
		"bounty":
			var den := _best_bounty(h.tile())
			h.quest_den = den
			h.assign(den_doorstep(den, h.tile()), AgentC.ASSAULT)
		"treasure":
			h.assign(_nearest_pile(h.tile()), AgentC.TREASURE)
		"hunt":
			h.assign(_nearest_known_warren(h.tile()), AgentC.HUNT)
		"pray":
			h.assign(_nearest_complete("shrine", h.tile()), AgentC.PRAY)
		"carouse":
			h.assign(_nearest_complete("tavern", h.tile()), AgentC.CAROUSE)
		"explore":
			h.assign(_explore_target(h.tile()), AgentC.EXPLORE)
		"assist":
			h.assign(_nearest_free_site(h.tile()), AgentC.ASSIST)
		_:
			h.assign(_wilds_spot(keep_pos, 5, h.tile()), AgentC.WANDER)

func _hero_level_check(h) -> void:
	while h.xp >= HERO_XP_PER_LEVEL * h.level:
		h.xp -= HERO_XP_PER_LEVEL * h.level
		h.level += 1
		h.max_hp += 2
		h.hp = h.max_hp
		last_event = "%s rises to level %d" % [HERO_CLASSES[h.hero_class].title, h.level]

func _hero_gain_xp(h, n: int) -> void:
	h.xp += n
	_hero_level_check(h)

func hero_shop(h) -> void:
	# Heroes bank their plunder at the market; the realm profits from
	# the trade. Loot in the pockets is what makes heroes come at all.
	if h.pouch > 0:
		gold += h.pouch
		market_sales += h.pouch
		h.pouch = 0
		last_event = "The %s spends loot at the market" % HERO_CLASSES[h.hero_class].title
	h.fatigue += 1

func hero_rest(h) -> void:
	h.fatigue = 0
	h.hp = h.max_hp

func hero_pray(h) -> void:
	# Candlelight and quiet: prayer eases a weary hero, and mends a
	# little of what the wilds took.
	h.fatigue = maxi(0, h.fatigue - 2)
	h.hp = mini(h.hp + 1, h.max_hp)

func hero_carouse(h) -> void:
	# An evening of ale and dice: cheaper than rest, dearer than pride.
	# The coin spent ends up in the tavern's till for the collector.
	h.fatigue = maxi(0, h.fatigue - 1)
	h.hp = mini(h.hp + 1, h.max_hp)
	h.leisure_left = hero_leisure_cooldown
	var b: Dictionary = buildings.get(h.target, {})
	if b.get("kind", "") == "tavern":
		var row: Dictionary = BUILD_TAX["tavern"]
		b.tax = mini(int(b.tax) + 1, int(row.cap))

func hero_hunt(h) -> void:
	# A spot of hunting: the warren's larder loses a hare or two, and the
	# hunter comes back a touch more seasoned. Thin the warrens too hard
	# and the wolves start eyeing the farms — the ecology keeps score.
	var den: Dictionary = dens.get(h.target, {})
	if not den.is_empty() and DEN_KINDS[den.get("kind", "")].role == "prey":
		den.food = maxi(0, int(den.food) - 2)
		_hero_gain_xp(h, 1)
	h.fatigue += 1
	h.leisure_left = hero_leisure_cooldown

func hero_take_loot(h) -> void:
	if loot_piles.has(h.target):
		h.pouch += int(loot_piles[h.target])
		loot_piles.erase(h.target)
		last_event = "The %s pockets the dropped loot" % HERO_CLASSES[h.hero_class].title
	h.fatigue += 1

func hero_assist(h) -> void:
	# Occasional flavor: a fresh hero with nothing better to score lends a
	# hand at a construction site. Never required — assist is the lowest
	# personality weight.
	if buildings.has(h.target) and not buildings[h.target].complete:
		tick_build(h.target)
	h.fatigue += 1

func hero_assault_tick(h) -> void:
	# Den damage flows from the combat step's siege accounting; here the
	# hero only notices the victory and moves on.
	if not dens.has(h.quest_den):
		h.state = AgentC.IDLE
		h.purpose = ""
		h.fatigue += 1
		last_event = "The %s's work at the den is done" % HERO_CLASSES[h.hero_class].title
		return
	h.work_left = 1

func adjacent_foes(a) -> int:
	# Foes that make a fighter hold ground: guards and heroes hem goblins
	# in; goblins hem heroes in.
	var n := 0
	for other in agents:
		if other == a:
			continue
		if a.kind == "goblin":
			if (other.kind == "guard" or other.kind == "hero") \
					and other.adjacent_to(a.tile()):
				n += 1
		elif a.kind == "hero":
			if other.kind == "goblin" and other.adjacent_to(a.tile()):
				n += 1
	return n

func _combat_step() -> void:
	# Simple attrition: foes on neighbouring tiles trade blows. A fighter who
	# drops to the flee threshold breaks for home; anyone at 0 hp is reaped.
	# Heroes join with melee weight = level, so veteran heroes hit harder.
	var gobs := []
	var guards := []
	var heroes := []
	for a in agents:
		if a.kind == "goblin":
			gobs.append(a)
		elif a.kind == "guard":
			guards.append(a)
		elif a.kind == "hero":
			heroes.append(a)
	for gob in gobs:
		var attackers := 0
		for g in guards:
			if g.adjacent_to(gob.tile()):
				attackers += 1
		for h in heroes:
			# A hero swings harder than rank alone: level + 1, so a fresh
			# hero can actually carve through a small warband.
			if h.adjacent_to(gob.tile()):
				attackers += h.level + 1
		if attackers > 0:
			# Combat interrupts behavior: the goblin turns to defend itself.
			gob.fighting = true
			gob.behavior_left = 0
			var wounded: bool = gob.hp > 0
			gob.hurt(attackers)
			if wounded and gob.hp <= 0:
				# The kill is credited to the heroes who landed it.
				for h in heroes:
					if h.adjacent_to(gob.tile()):
						_hero_gain_xp(h, 1)
	for g in guards:
		var enemies := 0
		for gob in gobs:
			if gob.adjacent_to(g.tile()):
				enemies += 1
		if enemies > 0:
			g.hurt(enemies)
	for h in heroes:
		var enemies := 0
		for gob in gobs:
			if gob.adjacent_to(h.tile()):
				enemies += 1
		if enemies > 0:
			h.fighting = true
			h.hurt(enemies)
	for p in dens.duplicate():
		var den: Dictionary = dens[p]
		if not is_hostile_den(p):
			continue # wild lairs are nobody's siege target
		var besiegers := 0
		for g in guards:
			if g.adjacent_to(p):
				besiegers += 1
		for h in heroes:
			if h.adjacent_to(p):
				besiegers += h.level
		if besiegers > 0:
			den.hp -= besiegers
			if den.hp <= 0:
				_clear_den(p)

func _clear_den(p: Vector2i) -> void:
	var den: Dictionary = dens[p]
	var spoils: int = int(den.gold)
	dens.erase(p)
	dens_cleared += 1
	for a in agents:
		if a.kind == "goblin" and a.home == p and not _removals.has(a):
			_removals.append(a)
	# The lair's plunder spills out where anyone quick can grab it.
	if spoils > 0:
		var door: Vector2i = den_doorstep(p, keep_pos)
		loot_piles[door] = int(loot_piles.get(door, 0)) + spoils
	var reward := 0
	if bounties.has(p):
		reward = int(bounties[p].reward)
		bounties.erase(p)
	var claimant = null
	for a in agents:
		if a.kind == "hero" and a.adjacent_to(p):
			claimant = a
			break
	if claimant != null:
		_hero_gain_xp(claimant, 5)
		dens_cleared_by_heroes += 1
		if reward > 0:
			claimant.pouch += reward
			bounties_paid += reward
			last_event = "The %s clears the den and claims the bounty!" \
				% HERO_CLASSES[claimant.hero_class].title
		else:
			last_event = "A %s storms the goblin den and prevails!" \
				% HERO_CLASSES[claimant.hero_class].title
	elif reward > 0:
		last_event = "The den fell to the watch; the bounty goes unclaimed"
	else:
		last_event = "The goblin den was cleared!"

func _reap() -> void:
	var guard_fell := false
	var fallen_hero_class := ""
	for a in agents:
		if a.hp <= 0 and (a.kind == "guard" or a.kind == "goblin" \
				or a.kind == "hero") and not _removals.has(a):
			_removals.append(a)
			match a.kind:
				"guard":
					guards_fallen += 1
					guard_fell = true
				"hero":
					# A fallen hero drops their purse where anyone quick
					# — a rogue, say — can race to it.
					heroes_fallen += 1
					fallen_hero_class = a.hero_class
					if a.pouch > 0:
						loot_piles[a.tile()] = int(loot_piles.get(a.tile(), 0)) + a.pouch
	if guard_fell:
		last_event = "A guard fell in battle!"
	elif fallen_hero_class != "":
		last_event = "A %s has fallen in battle!" % HERO_CLASSES[fallen_hero_class].title
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
