const FARM_COST := 10
const HOUSE_COST := 15
const START_GOLD := 50
const START_FOOD := 20
const START_POP := 5

const BUILD_COSTS := {
	"farm": FARM_COST,
	"house": HOUSE_COST,
}

var gold: int = START_GOLD
var food: int = START_FOOD
var pop: int = START_POP
var pop_cap: int = START_POP
var farms: int = 0
var houses: int = 0
var tick: int = 0
var last_event: String = ""
var world
var buildings := {}
var keep_pos := Vector2i.ZERO

func attach_world(w) -> void:
	world = w
	keep_pos = Vector2i(int(w.SIZE_X / 2.0), int(w.SIZE_Y / 2.0))
	buildings[keep_pos] = "castle"

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
	buildings[p] = kind
	match kind:
		"farm":
			farms += 1
		"house":
			houses += 1
			pop_cap += 3
	last_event = "Built " + kind
	return true

func update() -> void:
	tick += 1
	var food_eaten := pop
	var food_grown := farms * 2
	food = maxi(0, food + food_grown - food_eaten)
	gold += pop
	if food > pop and pop < pop_cap:
		pop += 1
		last_event = "A villager arrived"
	elif food == 0 and pop > 1:
		pop -= 1
		last_event = "Starvation! Someone left"
