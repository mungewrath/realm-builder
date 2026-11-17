extends RefCounted

# Pure sim agent (peasant / tax collector / goblin raider / guard). Runs
# headless; the view only reads pos/state/carrying/hp for drawing.

const SPEED := 3.0 # tiles per tick
const FLEE_AT := 1 # hp threshold at which a fighter breaks and runs home

const IDLE := "idle"
const TO_TARGET := "to_target"
const ACTING := "acting"
const RETURNING := "returning"
const FLEEING := "fleeing"

const FARM := "farm"
const BUILD := "build"
const COLLECT := "collect"
const RAID := "raid"
const INTERCEPT := "intercept"
const PATROL := "patrol"
const ASSAULT := "assault"

# Hero quest purposes (M4). ASSAULT is shared with the guard stub; the rest
# are hero-only legs of the fight/rest/shop loop.
const RECRUIT := "recruit"
const SHOP := "shop"
const REST := "rest"
const TREASURE := "treasure"
const ASSIST := "assist"

# Goblin behavior states (personal, weighted-random; the den overlays its
# own mood on the idle warband). LURK is never a movement purpose.
const LURK := "lurk"
const WANDER := "wander"
const PROWL := "prowl"
const FORAGE := "forage"

var kind := "peasant"
var pos := Vector2.ZERO
var state := IDLE
var purpose := ""
var target := Vector2i.ZERO
var work_left := 0
var carrying := 0
var pouch := 0
var round_list := []
var path := []
var kingdom: Object
var hp := 0
var max_hp := 0
var home := Vector2i.ZERO
var target_agent = null
var speed := SPEED
# Behavior layer (goblins): current personal state and how long it persists.
var behavior := LURK
var behavior_left := 0
var fighting := false
var heal_cd := 0
var loot_kind := ""
# Hero layer (M4): class row id, scored goal, and the usual leveling kit.
var hero_class := ""
var goal := ""
var quest_den := Vector2i.ZERO
var level := 1
var xp := 0
var fatigue := 0
var decision_left := 0

func setup(k, kind_value: String, spawn: Vector2i) -> void:
	kingdom = k
	kind = kind_value
	pos = Vector2(spawn) + Vector2(0.5, 0.5)
	match kind:
		"goblin":
			hp = kingdom.goblin_hp
			max_hp = hp
			# Warbands march with a stagger so they don't arrive as one blob,
			# but never faster than a guard.
			speed = SPEED * (0.7 + 0.3 * kingdom.rng.randf())
		"guard":
			hp = kingdom.guard_hp
			max_hp = hp

func tile() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

func adjacent_to(t: Vector2i) -> bool:
	return Vector2(tile()).distance_to(Vector2(t)) <= 1.5

func assign(dest: Vector2i, new_purpose: String) -> void:
	purpose = new_purpose
	target = dest
	state = TO_TARGET
	path = kingdom.find_path(tile(), dest)

func chase(other) -> void:
	purpose = INTERCEPT
	target_agent = other
	target = other.tile()
	state = TO_TARGET
	path = kingdom.find_path(tile(), target)

func start_round(stops: Array) -> void:
	round_list = stops.duplicate()
	purpose = COLLECT
	target = round_list.pop_front()
	state = TO_TARGET
	path = kingdom.find_path(tile(), target)

func flee_to(dest: Vector2i) -> void:
	# Fighters break for home; mountain dens are reached via their doorstep.
	if kind == "goblin":
		dest = kingdom.den_doorstep(home, tile())
	state = FLEEING
	path = kingdom.find_path(tile(), dest)

func hurt(n: int) -> void:
	hp -= n
	if hp > 0 and hp <= FLEE_AT and state != FLEEING:
		# Fighters break for home. Heroes fall back to the tavern (or the
		# keep when there is none) and come back once rested and healed.
		if kind == "hero":
			fatigue = maxi(fatigue, kingdom.HERO_FATIGUE_MAX)
			flee_to(kingdom.hero_rest_spot(self))
		else:
			flee_to(home)

func update() -> void:
	# Combat interrupts behavior: while engaged, hold ground and defend; once
	# the threat passes, resume whatever was underway. A fighter already
	# breaking for home (FLEEING) keeps running — breaking off is the point.
	if state != FLEEING and fighting:
		if kingdom.adjacent_foes(self) == 0:
			fighting = false
		else:
			return
	match state:
		TO_TARGET, RETURNING, FLEEING:
			_walk()
		ACTING:
			work_left -= 1
			if work_left <= 0:
				_finish_work()

func _walk() -> void:
	var budget: float = speed
	while budget > 0.0 and not path.is_empty():
		var next: Vector2 = Vector2(path[0]) + Vector2(0.5, 0.5)
		var step := next - pos
		var d := step.length()
		if d <= budget:
			pos = next
			path.remove_at(0)
			budget -= d
		else:
			pos += step * (budget / d)
			budget = 0.0
	if path.is_empty():
		_arrived()

func _arrived() -> void:
	match state:
		TO_TARGET:
			match purpose:
				FARM:
					state = ACTING
					work_left = kingdom.FARM_WORK_TICKS
				BUILD, COLLECT:
					state = ACTING
					work_left = 1
				RAID:
					state = ACTING
					work_left = kingdom.GOBLIN_RAZE_TICKS
				INTERCEPT, ASSAULT:
					state = ACTING
					work_left = 1
				PATROL:
					state = ACTING
					work_left = kingdom.GUARD_PATROL_WAIT
				FORAGE:
					state = ACTING
					work_left = kingdom.GATHER_TICKS
				RECRUIT, WANDER, PROWL:
					# Settle in / loiter where the behavior put us until it
					# expires.
					state = IDLE
					purpose = ""
				SHOP, TREASURE, ASSIST:
					state = ACTING
					work_left = 1
				REST:
					state = ACTING
					work_left = kingdom.HERO_REST_TICKS
		RETURNING:
			if purpose == RAID:
				kingdom.raid_returned(self)
			else:
				kingdom.deliver(self)
				state = IDLE
				purpose = ""
		FLEEING:
			match kind:
				"goblin":
					# Regroup at the den; wounds heal slowly there.
					state = IDLE
					purpose = ""
				"guard":
					hp = max_hp
					state = IDLE
					purpose = ""
				"hero":
					# Lick wounds at the tavern; the next decision will be
					# rest, which heals.
					fighting = false
					state = IDLE
					purpose = ""
				_:
					kingdom.deliver(self)
					state = IDLE
					purpose = ""

func _finish_work() -> void:
	match purpose:
		FARM:
			carrying = kingdom.FARM_CARRY
			state = RETURNING
			path = kingdom.find_path(tile(), kingdom.keep_pos)
		BUILD:
			# Site progress persists across builders; the site may also have
			# been razed mid-walk, in which case the builder simply gives up.
			if not kingdom.buildings.has(target):
				state = IDLE
				purpose = ""
			elif kingdom.tick_build(target):
				state = IDLE
				purpose = ""
			else:
				work_left = 1
		COLLECT:
			if kingdom.buildings.has(target):
				pouch += kingdom.take_tax(target)
			_advance_round()
		RAID:
			kingdom.raid_strike(target, self)
			state = RETURNING
			path = kingdom.find_path(tile(), kingdom.den_doorstep(home, tile()))
		FORAGE:
			carrying = kingdom.FORAGE_CARRY
			loot_kind = "food"
			state = RETURNING
			path = kingdom.find_path(tile(), kingdom.den_doorstep(home, tile()))
		SHOP:
			kingdom.hero_shop(self)
			state = IDLE
			purpose = ""
		REST:
			kingdom.hero_rest(self)
			state = IDLE
			purpose = ""
		TREASURE:
			kingdom.hero_take_loot(self)
			state = IDLE
			purpose = ""
		ASSIST:
			kingdom.hero_assist(self)
			state = IDLE
			purpose = ""
		ASSAULT:
			# Hero work: the kingdom decides whether the quest continues
			# (keeps ACTING) or the den fell (sets IDLE).
			kingdom.hero_assault_tick(self)
		INTERCEPT, PATROL:
			state = IDLE
			purpose = ""

func _advance_round() -> void:
	if round_list.is_empty():
		state = RETURNING
		path = kingdom.find_path(tile(), kingdom.keep_pos)
	else:
		target = round_list.pop_front()
		state = TO_TARGET
		path = kingdom.find_path(tile(), target)
