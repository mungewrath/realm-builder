extends Node2D

const Descriptions = preload("res://scripts/descriptions.gd")

const SIDE_PANEL_MIN_WIDTH := 900.0

var sim = load("res://scripts/kingdom.gd").new()
var build_mode := ""
var selected_tile := Vector2i(-1, -1)
var inspect_panel: PanelContainer
var inspect_title: Label
var inspect_blurb: Label
var inspect_status: Label
var inspect_units: Label

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
	map_view.setup(world, sim)
	map_view.tile_clicked.connect(_on_tile_clicked)
	farm_button.pressed.connect(_on_farm_pressed)
	house_button.pressed.connect(_on_house_pressed)
	_build_inspect_panel()
	get_viewport().size_changed.connect(_layout_inspect_panel)
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
	if build_mode != "":
		if sim.build_at(build_mode, p):
			map_view.queue_redraw()
			build_mode = ""
		_refresh()
		return
	_inspect(p)

func _on_tick() -> void:
	sim.update()
	map_view.queue_redraw()
	_refresh()
	_refresh_inspect()

func _refresh() -> void:
	res_label.text = "Gold %d  |  Fed %d/%d  |  Farms %d" % [
		sim.gold, mini(sim.fed_capacity(), sim.pop), sim.pop, sim.farms]
	pop_label.text = "People %d / %d  |  Houses %d" % [sim.pop, sim.pop_cap, sim.houses]
	event_label.text = sim.last_event if sim.last_event != "" else "Drag to explore, pinch to zoom"
	farm_button.set_pressed_no_signal(build_mode == "farm")
	house_button.set_pressed_no_signal(build_mode == "house")
	farm_button.disabled = sim.gold < sim.BUILD_COSTS.farm
	house_button.disabled = sim.gold < sim.BUILD_COSTS.house

# --- Tap-to-inspect -------------------------------------------------------

func _build_inspect_panel() -> void:
	inspect_panel = PanelContainer.new()
	inspect_panel.name = "InspectPanel"
	inspect_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	inspect_title = Label.new()
	inspect_title.add_theme_font_size_override("font_size", 26)
	inspect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(_close_inspect)
	top.add_child(inspect_title)
	top.add_child(close)
	inspect_blurb = _make_body_label()
	inspect_status = _make_body_label()
	inspect_units = _make_body_label()
	vb.add_child(top)
	vb.add_child(inspect_blurb)
	vb.add_child(inspect_status)
	vb.add_child(inspect_units)
	inspect_panel.add_child(vb)
	get_node("UI/Root").add_child(inspect_panel)
	_layout_inspect_panel()

func _make_body_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 20)
	return l

func _layout_inspect_panel() -> void:
	if inspect_panel == null:
		return
	var vp := get_viewport_rect().size
	if vp.x >= SIDE_PANEL_MIN_WIDTH:
		inspect_panel.anchor_left = 1.0
		inspect_panel.anchor_right = 1.0
		inspect_panel.anchor_top = 0.0
		inspect_panel.anchor_bottom = 1.0
		inspect_panel.offset_left = -340.0
		inspect_panel.offset_right = -16.0
		inspect_panel.offset_top = 16.0
		inspect_panel.offset_bottom = -16.0
	else:
		inspect_panel.anchor_left = 0.0
		inspect_panel.anchor_right = 1.0
		inspect_panel.anchor_top = 1.0
		inspect_panel.anchor_bottom = 1.0
		var h := minf(240.0, vp.y / 3.0)
		inspect_panel.offset_left = 12.0
		inspect_panel.offset_right = -12.0
		inspect_panel.offset_top = -h - 116.0
		inspect_panel.offset_bottom = -116.0

func _inspect(p: Vector2i) -> void:
	var b = sim.buildings.get(p)
	var here := []
	for a in sim.agents:
		if a.tile() == p:
			here.append(a)
	if b == null and here.is_empty():
		_close_inspect()
		return
	selected_tile = p
	map_view.selected = p
	if b != null:
		inspect_title.text = Descriptions.building_title(b.kind)
		inspect_blurb.text = Descriptions.building_blurb(b.kind)
		inspect_status.text = Descriptions.building_status(b.kind, p, b, sim)
	else:
		inspect_title.text = Descriptions.UNIT_ROLES.get(here[0].kind, "Stranger")
		inspect_blurb.text = ""
		inspect_status.text = Descriptions.agent_activity(here[0])
	var lines := []
	var first := 0 if b != null else 1
	for i in range(first, mini(here.size(), 4)):
		lines.append(Descriptions.agent_line(here[i]))
	inspect_units.text = "\n".join(lines)
	inspect_units.visible = inspect_units.text != ""
	inspect_blurb.visible = inspect_blurb.text != ""
	inspect_status.visible = inspect_status.text != ""
	inspect_panel.visible = true

func _refresh_inspect() -> void:
	if inspect_panel == null or not inspect_panel.visible or selected_tile.x < 0:
		return
	_inspect(selected_tile)

func _close_inspect() -> void:
	inspect_panel.visible = false
	selected_tile = Vector2i(-1, -1)
	map_view.selected = Vector2i(-1, -1)
	map_view.queue_redraw()
