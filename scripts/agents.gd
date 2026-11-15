extends RefCounted

# Pure sim agent (peasant / tax collector). Runs headless; the view only
# reads pos/state/carrying for drawing.

const SPEED := 3.0 # tiles per tick

const IDLE := "idle"
const TO_TARGET := "to_target"
const ACTING := "acting"
const RETURNING := "returning"
const FLEEING := "fleeing"

const FARM := "farm"
const BUILD := "build"
const COLLECT := "collect"

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

func setup(k, kind_value: String, spawn: Vector2i) -> void:
	kingdom = k
	kind = kind_value
	pos = Vector2(spawn) + Vector2(0.5, 0.5)

func tile() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

func assign(dest: Vector2i, new_purpose: String) -> void:
	purpose = new_purpose
	target = dest
	state = TO_TARGET
	path = kingdom.find_path(tile(), dest)

func start_round(stops: Array) -> void:
	round_list = stops.duplicate()
	purpose = COLLECT
	target = round_list.pop_front()
	state = TO_TARGET
	path = kingdom.find_path(tile(), target)

func flee_to(dest: Vector2i) -> void:
	# Behavior stub reused in M3 (raiders). Drops nothing; resumes work after.
	state = FLEEING
	path = kingdom.find_path(tile(), dest)

func update() -> void:
	match state:
		TO_TARGET, RETURNING, FLEEING:
			_walk()
		ACTING:
			work_left -= 1
			if work_left <= 0:
				_finish_work()

func _walk() -> void:
	var budget: float = SPEED
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
				BUILD:
					state = ACTING
					work_left = 1
				COLLECT:
					state = ACTING
					work_left = 1
		RETURNING, FLEEING:
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
			# Site progress persists across builders; keep hammering until done.
			if kingdom.tick_build(target):
				state = IDLE
				purpose = ""
			else:
				work_left = 1
		COLLECT:
			pouch += kingdom.take_tax(target)
			if round_list.is_empty():
				state = RETURNING
				path = kingdom.find_path(tile(), kingdom.keep_pos)
			else:
				target = round_list.pop_front()
				state = TO_TARGET
				path = kingdom.find_path(tile(), target)
