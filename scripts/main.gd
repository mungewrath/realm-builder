extends Node2D

var sim := KingdomSim.new()

@onready var res_label: Label = %ResLabel
@onready var pop_label: Label = %PopLabel
@onready var event_label: Label = %EventLabel
@onready var farm_button: Button = %FarmButton
@onready var house_button: Button = %HouseButton

func _ready() -> void:
	farm_button.pressed.connect(func(): sim.build_farm(); _refresh())
	house_button.pressed.connect(func(): sim.build_house(); _refresh())
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()
	_refresh()

func _on_tick() -> void:
	sim.update()
	_refresh()

func _refresh() -> void:
	res_label.text = "Gold %d  |  Food %d  |  Farms %d" % [sim.gold, sim.food, sim.farms]
	pop_label.text = "People %d / %d  |  Houses %d" % [sim.pop, sim.pop_cap, sim.houses]
	event_label.text = sim.last_event
	farm_button.disabled = sim.gold < KingdomSim.FARM_COST
	house_button.disabled = sim.gold < KingdomSim.HOUSE_COST
