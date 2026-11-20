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

# M6.1 leisure legs: hunting game at a warren, prayer at a shrine, an
# evening at the tavern.
const PRAY := "pray"
const CAROUSE := "carouse"

# M7.2: buy forged gear from the blacksmith's stock.
const GEAR := "gear"

# Over the realm's hero cap, a restless hero may simply walk out.
const LEAVE := "leave"

# Goblin behavior states (personal, weighted-random; the den overlays its
# own mood on the idle warband). LURK is never a movement purpose.
const LURK := "lurk"
const WANDER := "wander"
const PROWL := "prowl"
const FORAGE := "forage"

# M6.1 wild creatures: a predator's leg to a prey den (or a farm, when the
# wild prey is gone). FORAGE doubles as the rabbit's graze leg.
const HUNT := "hunt"

# M6.2 bandits: shadow a laden purse and lift it on the road.
const MUG := "mug"

# M5: hero exploration leg — chart the unknown when nothing is known.
const EXPLORE := "explore"

# M6.3: the druid's leg — tend a wild lair and its larder.
const PROTECT := "protect"
# M6.3: labour on a terrain worksite (drain marsh / clear woods).
const TERRAIN := "terrain"

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
# M7.2: forged gear points bought at the blacksmith; each adds to melee.
var gear := 0
# M5 fog bookkeeping: last tile this agent already revealed from.
var fog_tile := Vector2i(-1, -1)
# M6.1 wild ecology: species row id for creature agents.
var species := ""
# Leisure cooldown (M6.1): ticks during which hunt/carouse are off the
# books after a round of them, so idle hours rotate instead of repeating.
var leisure_left := 0

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
		"bandit":
			hp = kingdom.bandit_hp
			max_hp = hp
		"creature":
			# Species must be set before setup(); stats come from the row.
			var stats: Dictionary = kingdom.CREATURE_STATS[species]
			speed = stats.speed
			hp = stats.hp
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
	# Fighters break for home before dying: rank-and-file at the last
	# breath, heroes once they are clearly losing (a third of their health)
	# — they limp to the tavern, heal, and come back.
	var break_at := FLEE_AT
	if kind == "hero":
		break_at = maxi(1, int(ceil(max_hp / 3.0)))
	if hp > 0 and hp <= break_at and state != FLEEING:
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
				BUILD, COLLECT, TERRAIN:
					state = ACTING
					work_left = 1
				RAID:
					state = ACTING
					work_left = kingdom.GOBLIN_RAZE_TICKS
				INTERCEPT, ASSAULT:
					state = ACTING
					work_left = 1
				MUG:
					# The lift itself is quick; the shadowing is the work.
					state = ACTING
					work_left = 1
				HUNT:
					# A hero's spot of hunting takes a little while; a
					# predator's pounce is over in one bound.
					state = ACTING
					work_left = kingdom.HERO_HUNT_TICKS if kind == "hero" else 1
				PROTECT:
					# A druid settles in to tend the wilds.
					state = ACTING
					work_left = kingdom.HERO_PROTECT_TICKS
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
				EXPLORE:
					# A new horizon is a lesson in itself.
					kingdom.hero_explore(self)
					state = IDLE
					purpose = ""
				LEAVE:
					kingdom.hero_leave(self)
					state = IDLE
					purpose = ""
				SHOP, GEAR, TREASURE, ASSIST:
					state = ACTING
					work_left = 1
				PRAY:
					state = ACTING
					work_left = kingdom.HERO_PRAY_TICKS
				CAROUSE:
					state = ACTING
					work_left = kingdom.HERO_CAROUSE_TICKS
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
				"bandit":
					# Lie low at camp until the watch loses interest.
					target_agent = null
					fighting = false
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
			# A cursed field yields nothing: the harvest withers in the rows.
			carrying = 0 if kingdom.is_cursed(target) else kingdom.FARM_CARRY
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
		TERRAIN:
			# Land work persists at the tile until the last labour tick.
			if not kingdom.terrain_works.has(target):
				state = IDLE
				purpose = ""
			elif kingdom.tick_terrain(target):
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
			# Goblins haul grubs by the armful; wild creatures graze light.
			carrying = kingdom.FORAGE_CARRY if kind != "creature" \
				else kingdom.CREATURE_STATS[species].carry
			loot_kind = "food"
			state = RETURNING
			var dest: Vector2i = kingdom.den_doorstep(home, tile()) \
				if kind == "goblin" else home
			path = kingdom.find_path(tile(), dest)
		PROTECT:
			kingdom.hero_protect(self)
			state = IDLE
			purpose = ""
		HUNT:
			if kind == "hero":
				# The hero's spot of hunting: thin the warren's game.
				kingdom.hero_hunt(self)
				state = IDLE
				purpose = ""
			else:
				# The predator's kill lands in the home den's larder.
				kingdom.hunt_strike(target, self)
				state = RETURNING
				path = kingdom.find_path(tile(), home)
		MUG:
			# The purse is lifted; the bandit slips back to camp with it.
			kingdom.bandit_mug(self)
		SHOP:
			kingdom.hero_shop(self)
			state = IDLE
			purpose = ""
		GEAR:
			kingdom.hero_buy_gear(self)
			state = IDLE
			purpose = ""
		REST:
			kingdom.hero_rest(self)
			state = IDLE
			purpose = ""
		PRAY:
			kingdom.hero_pray(self)
			state = IDLE
			purpose = ""
		CAROUSE:
			kingdom.hero_carouse(self)
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
