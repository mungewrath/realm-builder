extends Node2D

const Descriptions = preload("res://scripts/descriptions.gd")
const MinimapC = preload("res://scripts/minimap.gd")

const SIDE_PANEL_MIN_WIDTH := 900.0

var sim = load("res://scripts/kingdom.gd").new()
var build_mode := ""
var selected_tile := Vector2i(-1, -1)
var selected_unit = null # when set, the inspect panel follows this agent
var inspect_panel: PanelContainer
var inspect_title: Label
var inspect_blurb: Label
var inspect_status: Label
var inspect_units: Label
var inspect_action: Button

# Sim speed (dev tool): 1-3x. The tick timer runs at 1/speed seconds.
const SPEEDS := [1.0, 1.5, 2.0, 3.0]
var sim_speed := 1.0
var tick_timer: Timer
var speed_panel: PanelContainer
var speed_buttons := {}
var speed_label: Label
var fog_check: CheckButton
var minimap: Control

# Event log scrollback (bottom-left): a compact panel fed by sim.event_log.
var log_button: Button
var log_panel: PanelContainer
var log_text: RichTextLabel
var log_last_id := 0

@onready var map_view := %MapView
@onready var res_label: Label = %ResLabel
@onready var pop_label: Label = %PopLabel
@onready var event_label: Label = %EventLabel
@onready var farm_button: Button = %FarmButton
@onready var house_button: Button = %HouseButton
@onready var guard_button: Button = %GuardButton
@onready var tavern_button: Button = %TavernButton
@onready var market_button: Button = %MarketButton
@onready var shrine_button: Button = %ShrineButton
@onready var dev_button: Button = %DevButton

func _ready() -> void:
	var world = load("res://scripts/world.gd").new()
	world.generate(20261114)
	sim.attach_world(world)
	map_view.setup(world, sim)
	map_view.tile_clicked.connect(_on_tile_clicked)
	farm_button.pressed.connect(_on_farm_pressed)
	house_button.pressed.connect(_on_house_pressed)
	guard_button.pressed.connect(_on_guard_pressed)
	tavern_button.pressed.connect(_on_tavern_pressed)
	market_button.pressed.connect(_on_market_pressed)
	shrine_button.pressed.connect(_on_shrine_pressed)
	_build_minimap()
	_build_inspect_panel()
	_build_event_log()
	_build_speed_panel()
	get_viewport().size_changed.connect(_layout_inspect_panel)
	get_viewport().size_changed.connect(_layout_event_log)
	tick_timer = Timer.new()
	tick_timer.wait_time = 1.0 / sim_speed
	tick_timer.timeout.connect(_on_tick)
	add_child(tick_timer)
	tick_timer.start()
	_refresh()

func _on_farm_pressed() -> void:
	_toggle_build("farm")

func _on_house_pressed() -> void:
	_toggle_build("house")

func _on_guard_pressed() -> void:
	_toggle_build("guardhouse")

func _on_tavern_pressed() -> void:
	_toggle_build("tavern")

func _on_market_pressed() -> void:
	_toggle_build("market")

func _on_shrine_pressed() -> void:
	_toggle_build("shrine")

func _toggle_build(kind: String) -> void:
	build_mode = "" if build_mode == kind else kind
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
	minimap.queue_redraw()
	_refresh()
	_refresh_inspect()

func _refresh() -> void:
	res_label.text = "Gold %d  |  Fed %d/%d  |  Farms %d" % [
		sim.gold, mini(sim.fed_capacity(), sim.pop), sim.pop, sim.farms]
	pop_label.text = "People %d / %d  |  Houses %d" % [sim.pop, sim.pop_cap, sim.houses]
	event_label.text = sim.last_event if sim.last_event != "" else "Drag to explore, pinch to zoom"
	_refresh_event_log()
	farm_button.set_pressed_no_signal(build_mode == "farm")
	house_button.set_pressed_no_signal(build_mode == "house")
	guard_button.set_pressed_no_signal(build_mode == "guardhouse")
	tavern_button.set_pressed_no_signal(build_mode == "tavern")
	market_button.set_pressed_no_signal(build_mode == "market")
	shrine_button.set_pressed_no_signal(build_mode == "shrine")
	var kinds := {"farm": farm_button, "house": house_button, "guardhouse": guard_button,
		"tavern": tavern_button, "market": market_button, "shrine": shrine_button}
	for kind in kinds:
		var btn: Button = kinds[kind]
		btn.disabled = sim.gold < sim.BUILD_COSTS[kind]

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
	inspect_action = Button.new()
	inspect_action.add_theme_font_size_override("font_size", 20)
	inspect_action.visible = false
	inspect_action.pressed.connect(_on_inspect_action)
	vb.add_child(top)
	vb.add_child(inspect_blurb)
	vb.add_child(inspect_status)
	vb.add_child(inspect_action)
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
		inspect_panel.offset_top = -h - 210.0
		inspect_panel.offset_bottom = -210.0

func _agents_here(p: Vector2i) -> Array:
	# Goblins and wild creatures in ground no one has charted stay hidden
	# even when tapped blind.
	var here := []
	for a in sim.agents:
		if a.tile() != p:
			continue
		if (a.kind == "goblin" or a.kind == "creature") \
				and not sim.explored_at(p):
			continue
		here.append(a)
	return here

func _inspect(p: Vector2i) -> void:
	var known: bool = sim.explored_at(p)
	var b = sim.buildings.get(p)
	var den = sim.dens.get(p) if known else null
	var pile_gold: int = int(sim.loot_piles.get(p, 0)) if known else 0
	var here := _agents_here(p)
	var workable: bool = sim.can_drain_swamp(p) or sim.can_clear_forest(p) \
		or sim.terrain_works.has(p)
	if b == null and den == null and pile_gold <= 0 and here.is_empty() \
			and not workable:
		_close_inspect()
		return
	# A click on a building, den, or loot pile pins the tile; a unit standing
	# on it is listed underneath, never followed. Only a bare unit click
	# follows.
	selected_unit = null if (b != null or den != null or pile_gold > 0 \
		or here.is_empty()) else here[0]
	if selected_unit != null:
		_inspect_agent(selected_unit)
		return
	selected_tile = p
	map_view.selected = p
	_fill_tile_inspect(b, den, pile_gold)
	_show_units(here, true)
	_refresh_action(p, den)

func _fill_tile_inspect(b, den, pile_gold: int) -> void:
	if b != null:
		inspect_title.text = Descriptions.building_title(b.kind)
		inspect_blurb.text = Descriptions.building_blurb(b.kind)
		inspect_status.text = Descriptions.building_status(b.kind, selected_tile, b, sim)
	elif den != null:
		var kind_key: String = den.get("kind", "goblin_den")
		inspect_title.text = Descriptions.den_title(kind_key)
		inspect_blurb.text = Descriptions.den_blurb(kind_key)
		inspect_status.text = Descriptions.den_status(den, selected_tile, sim)
	elif pile_gold > 0:
		inspect_title.text = Descriptions.loot_title()
		inspect_blurb.text = Descriptions.loot_blurb()
		inspect_status.text = Descriptions.loot_status(pile_gold)
	else:
		var t: int = sim.world.get_terrain(selected_tile)
		inspect_title.text = Descriptions.terrain_title(t)
		inspect_blurb.text = Descriptions.terrain_blurb(t)
		inspect_status.text = Descriptions.terrain_status(t, sim, selected_tile)

func _refresh_action(p: Vector2i, den) -> void:
	# One-tap actions live on the inspector card: bounty flags on any lair
	# the realm can reach, and terrain work on charted marsh or woods.
	if den != null:
		if not dens_reachable(p):
			inspect_action.visible = false
			return
		if sim.bounties.has(p):
			inspect_action.text = "Add to bounty (+%dg)" % (sim.BOUNTY_FEE - sim.BOUNTY_OVERHEAD)
		else:
			inspect_action.text = "Post bounty (%dg)" % sim.BOUNTY_FEE
		inspect_action.visible = true
		inspect_action.disabled = sim.gold < sim.BOUNTY_FEE
		return
	var work: Dictionary = sim.terrain_works.get(p, {})
	if not work.is_empty():
		var verb: String = "Draining marsh" if work.kind == "drain" \
			else "Clearing woods"
		inspect_action.text = "%s (%d/%d)" % [
			verb, int(work.progress), sim.TERRAIN_WORK_TICKS]
		inspect_action.visible = true
		inspect_action.disabled = true
	elif sim.can_drain_swamp(p):
		inspect_action.text = "Begin draining (%dg)" % sim.drain_cost
		inspect_action.visible = true
		inspect_action.disabled = sim.gold < sim.drain_cost
	elif sim.can_clear_forest(p):
		inspect_action.text = "Begin clearing (%dg)" % sim.clear_cost
		inspect_action.visible = true
		inspect_action.disabled = sim.gold < sim.clear_cost
	else:
		inspect_action.visible = false

func dens_reachable(p: Vector2i) -> bool:
	# Only dens the realm can actually reach are bounty-able.
	return sim.find_path(sim.den_doorstep(p, sim.keep_pos), sim.keep_pos).size() > 0

func _on_inspect_action() -> void:
	if selected_tile.x < 0:
		return
	if sim.dens.has(selected_tile):
		sim.post_bounty(selected_tile)
	elif sim.world.get_terrain(selected_tile) == sim.world.SWAMP:
		sim.drain_swamp(selected_tile)
	elif sim.world.get_terrain(selected_tile) == sim.world.FOREST:
		sim.clear_forest(selected_tile)
	map_view.queue_redraw()
	minimap.queue_redraw()
	_refresh()
	_refresh_inspect()

func _inspect_agent(a) -> void:
	# Follow mode: the panel tracks the unit wherever it walks.
	selected_tile = a.tile()
	map_view.selected = selected_tile
	inspect_title.text = Descriptions.unit_title(a)
	inspect_blurb.text = Descriptions.hero_blurb(a) if a.kind == "hero" else ""
	inspect_status.text = Descriptions.agent_activity(a)
	var here := _agents_here(selected_tile)
	here.erase(a)
	_show_units(here, false)
	inspect_action.visible = false

func _show_units(here: Array, include_first: bool) -> void:
	var lines := []
	var first := 0 if include_first else 1
	for i in range(first, mini(here.size(), 4)):
		lines.append(Descriptions.agent_line(here[i]))
	inspect_units.text = "\n".join(lines)
	inspect_units.visible = inspect_units.text != ""
	inspect_blurb.visible = inspect_blurb.text != ""
	inspect_status.visible = inspect_status.text != ""
	inspect_panel.visible = true

func _refresh_inspect() -> void:
	if inspect_panel == null or not inspect_panel.visible:
		return
	if selected_unit != null:
		# A unit that leaves the sim (reaped, den cleared) closes the panel.
		if not sim.agents.has(selected_unit):
			_close_inspect()
			return
		_inspect_agent(selected_unit)
		return
	if selected_tile.x < 0:
		return
	_inspect_tile(selected_tile)

func _inspect_tile(p: Vector2i) -> void:
	var known: bool = sim.explored_at(p)
	var b = sim.buildings.get(p)
	var den = sim.dens.get(p) if known else null
	var pile_gold: int = int(sim.loot_piles.get(p, 0)) if known else 0
	var here := _agents_here(p)
	var workable: bool = sim.can_drain_swamp(p) or sim.can_clear_forest(p) \
		or sim.terrain_works.has(p)
	if b == null and den == null and pile_gold <= 0 and not workable:
		# A razed, claimed, or vanished pin: close rather than stale text.
		_close_inspect()
		return
	_fill_tile_inspect(b, den, pile_gold)
	_show_units(here, true)
	_refresh_action(p, den)

func _close_inspect() -> void:
	inspect_panel.visible = false
	selected_tile = Vector2i(-1, -1)
	selected_unit = null
	map_view.selected = Vector2i(-1, -1)
	inspect_action.visible = false
	map_view.queue_redraw()

# --- Event log (bottom-left) ---------------------------------------------

func _build_event_log() -> void:
	# The toggle sits above the build bar; the panel is a compact card, not
	# a full-screen takeover — the map stays visible behind it.
	log_button = Button.new()
	log_button.name = "LogButton"
	log_button.text = "Log"
	log_button.toggle_mode = true
	log_button.custom_minimum_size = Vector2(110, 56)
	log_button.add_theme_font_size_override("font_size", 22)
	log_button.pressed.connect(_toggle_event_log)
	get_node("UI/Root").add_child(log_button)
	log_button.anchor_left = 0.0
	log_button.anchor_right = 0.0
	log_button.anchor_top = 1.0
	log_button.anchor_bottom = 1.0
	log_button.offset_left = 16.0
	log_button.offset_right = 126.0
	log_button.offset_top = -272.0
	log_button.offset_bottom = -216.0

	log_panel = PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Event Log"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(_close_event_log)
	top.add_child(title)
	top.add_child(close)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_active = true
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.add_theme_font_size_override("normal_font_size", 18)
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(top)
	vb.add_child(log_text)
	log_panel.add_child(vb)
	get_node("UI/Root").add_child(log_panel)
	_layout_event_log()

func _layout_event_log() -> void:
	if log_panel == null:
		return
	var vp := get_viewport_rect().size
	var w := minf(460.0, vp.x - 32.0)
	var h := minf(340.0, maxf(140.0, vp.y - 296.0))
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 16.0
	log_panel.offset_right = 16.0 + w
	log_panel.offset_bottom = -284.0
	log_panel.offset_top = -284.0 - h
	log_text.custom_minimum_size = Vector2(0, h - 64.0)

func _toggle_event_log() -> void:
	if log_panel.visible:
		_close_event_log()
		return
	log_panel.visible = true
	log_button.set_pressed_no_signal(true)
	_rebuild_event_log()

func _close_event_log() -> void:
	if log_panel == null:
		return
	log_panel.visible = false
	log_button.set_pressed_no_signal(false)

func _rebuild_event_log() -> void:
	# Open fresh from the sim's scrollback (old entries may already have
	# rotated out of the ring while the panel was shut).
	log_text.clear()
	log_last_id = 0
	if sim.event_log.is_empty():
		log_text.append_text("[color=#8f8f8f]Nothing has happened yet.[/color]")
	else:
		_refresh_event_log()

func _refresh_event_log() -> void:
	if log_panel == null or not log_panel.visible:
		return
	# First real entry after an empty open replaces the placeholder line.
	if log_last_id == 0 and not sim.event_log.is_empty():
		log_text.clear()
	# Entries carry monotonic ids, so appending is cheap and stays correct
	# when the ring buffer drops old messages.
	for e in sim.event_log:
		if int(e.id) <= log_last_id:
			continue
		log_text.append_text("[color=#8f8f8f]%d[/color]  %s\n" % [int(e.tick), e.text])
		log_last_id = int(e.id)

# --- Dev tools: sim speed (1-3x), fog of war toggle --------------------------

func _build_minimap() -> void:
	minimap = MinimapC.new()
	minimap.name = "Minimap"
	get_node("UI/Root").add_child(minimap)
	minimap.setup(sim.world, sim, map_view)
	minimap.tile_jump.connect(_on_minimap_jump)
	_layout_minimap()

func _layout_minimap() -> void:
	# Bottom-right corner, above the build bar; the inspector card overlaps
	# it while open, which is fine — dismiss to see the map.
	var h: float = minimap.custom_minimum_size.y
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -minimap.custom_minimum_size.x - 12.0
	minimap.offset_right = -12.0
	minimap.offset_top = -h - 12.0
	minimap.offset_bottom = -12.0

func _on_minimap_jump(p: Vector2i) -> void:
	map_view.center_on(p)
	map_view.queue_redraw()
	minimap.queue_redraw()

func _build_speed_panel() -> void:
	speed_panel = PanelContainer.new()
	speed_panel.name = "SpeedPanel"
	speed_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 18)
	speed_label.text = "Sim speed"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for s in SPEEDS:
		var b := Button.new()
		b.text = "%sx" % str(s)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_set_speed.bind(s))
		row.add_child(b)
		speed_buttons[s] = b
	# Fog of war can be switched off here to troubleshoot the map view.
	fog_check = CheckButton.new()
	fog_check.text = "Fog of war"
	fog_check.button_pressed = sim.fog_enabled
	fog_check.add_theme_font_size_override("font_size", 18)
	fog_check.toggled.connect(_set_fog)
	vb.add_child(speed_label)
	vb.add_child(row)
	vb.add_child(fog_check)
	speed_panel.add_child(vb)
	get_node("UI/Root").add_child(speed_panel)
	speed_panel.anchor_left = 1.0
	speed_panel.anchor_right = 1.0
	speed_panel.offset_left = -260.0
	speed_panel.offset_right = -16.0
	speed_panel.offset_top = 76.0
	speed_panel.offset_bottom = 190.0
	_mark_speed_buttons()
	dev_button.pressed.connect(_on_dev_pressed)

func _set_fog(on: bool) -> void:
	sim.set_fog_enabled(on)
	map_view.queue_redraw()
	minimap.queue_redraw()

func _on_dev_pressed() -> void:
	speed_panel.visible = not speed_panel.visible
	fog_check.set_pressed_no_signal(sim.fog_enabled)
	_mark_speed_buttons()

func _set_speed(s: float) -> void:
	sim_speed = s
	tick_timer.wait_time = 1.0 / s
	tick_timer.start()
	speed_label.text = "Sim speed  ·  now %sx" % str(s)
	_mark_speed_buttons()

func _mark_speed_buttons() -> void:
	for s in speed_buttons:
		speed_buttons[s].set_pressed_no_signal(is_equal_approx(s, sim_speed))
