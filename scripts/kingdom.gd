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

const BUILD_COSTS := {
	"farm": FARM_COST,
	"house": HOUSE_COST,
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

# Provisions capacity of the realm: complete farms feed people.
func fed_capacity() -> int:
	return farms * FARM_CAPACITY_POP

func attach_world(w) -> void:
	world = w
	keep_pos = Vector2i(int(w.SIZE_X / 2.0), int(w.SIZE_Y / 2.0))
	buildings[keep_pos] = {"kind": "castle", "complete": true, "tax": 0}
	for i in START_POP:
		_spawn_peasant()

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
	for a in agents:
		a.update()
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
	if a.kind == "peasant":
		if a.carrying > 0:
			food_delivered += a.carrying
			deliveries += 1
			a.carrying = 0
	else:
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
