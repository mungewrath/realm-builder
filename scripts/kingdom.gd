class_name KingdomSim

const FARM_COST := 10
const HOUSE_COST := 15
const START_GOLD := 50
const START_FOOD := 20
const START_POP := 5

var gold: int = START_GOLD
var food: int = START_FOOD
var pop: int = START_POP
var pop_cap: int = START_POP
var farms: int = 0
var houses: int = 0
var tick: int = 0
var last_event: String = ""

func build_farm() -> void:
	if gold < FARM_COST:
		last_event = "Not enough gold for a farm"
		return
	gold -= FARM_COST
	farms += 1
	last_event = "Farm built"

func build_house() -> void:
	if gold < HOUSE_COST:
		last_event = "Not enough gold for a house"
		return
	gold -= HOUSE_COST
	houses += 1
	pop_cap += 3
	last_event = "House built"

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
