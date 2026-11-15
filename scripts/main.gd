extends Node2D

var sim = load("res://scripts/kingdom.gd").new()
var build_mode := ""

@onready var map_view := %MapView
@onready var res_label: Label = %ResLabel
@onready var pop_label: Label = %PopLabel
@onready var event_label: Label = %EventLabel
@onready var farm_button: Button = %FarmButton
@onready var house_button: Button = %HouseButton

func _ready() -> void:
	var world = load("res://scripts/world.gd").new()
	world.generate(20261114)
	sim.attach_world(world)
	map_view.setup(world, sim.buildings)
	map_view.tile_clicked.connect(_on_tile_clicked)
	farm_button.pressed.connect(_on_farm_pressed)
	house_button.pressed.connect(_on_house_pressed)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()
	_refresh()

func _on_farm_pressed() -> void:
	build_mode = "" if build_mode == "farm" else "farm"
	_refresh()

func _on_house_pressed() -> void:
	build_mode = "" if build_mode == "house" else "house"
	_refresh()

func _on_tile_clicked(p: Vector2i) -> void:
	if build_mode == "":
		return
	if sim.build_at(build_mode, p):
		map_view.queue_redraw()
		build_mode = ""
	_refresh()

func _on_tick() -> void:
	sim.update()
	_refresh()

func _refresh() -> void:
	res_label.text = "Gold %d  |  Food %d  |  Farms %d" % [sim.gold, sim.food, sim.farms]
	pop_label.text = "People %d / %d  |  Houses %d" % [sim.pop, sim.pop_cap, sim.houses]
	event_label.text = sim.last_event if sim.last_event != "" else "Drag to explore, pinch to zoom"
	farm_button.set_pressed_no_signal(build_mode == "farm")
	house_button.set_pressed_no_signal(build_mode == "house")
	farm_button.disabled = sim.gold < sim.BUILD_COSTS.farm
	house_button.disabled = sim.gold < sim.BUILD_COSTS.house
