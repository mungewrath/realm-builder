extends Node2D

const Descriptions = preload("res://scripts/descriptions.gd")
const MinimapC = preload("res://scripts/minimap.gd")
const ManualC = preload("res://scripts/manual.gd")
const ManualButtonC = preload("res://scripts/manual_button.gd")

const SIDE_PANEL_MIN_WIDTH := 900.0

var sim = load("res://scripts/kingdom.gd").new()
var build_mode := ""
var placement_tile := Vector2i(-1, -1)
var placement_panel: PanelContainer
var placement_label: Label
var placement_confirm: Button
var selected_tile := Vector2i(-1, -1)
var selected_unit = null # when set, the inspect panel follows this agent
var inspect_panel: PanelContainer
var inspect_title: Label
var inspect_blurb: Label
var inspect_status: Label
var inspect_units: Label
var inspect_action: Button
var inspect_action2: Button

# Hero roster card: a full list of the realm's heroes and what they are doing.
var hero_roster_panel: PanelContainer
var hero_roster_list: VBoxContainer
var hero_roster_signature := "__unset__"

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

# Player manual card: the book button sits beside the minimap and opens a
# scrollable, searchable reference built from MANUAL.md.
var manual_button: Button
var manual_panel: PanelContainer
var manual_text: RichTextLabel

@onready var map_view := %MapView
@onready var res_label: Label = %ResLabel
@onready var pop_label: Label = %PopLabel
@onready var hero_label: Label = %HeroLabel
@onready var hero_roster_button: Button = %HeroRosterButton
@onready var event_label: Label = %EventLabel
@onready var farm_button: Button = %FarmButton
@onready var house_button: Button = %HouseButton
@onready var guard_button: Button = %GuardButton
@onready var tavern_button: Button = %TavernButton
@onready var market_button: Button = %MarketButton
@onready var shrine_button: Button = %ShrineButton
@onready var blacksmith_button: Button = %BlacksmithButton
@onready var wizard_button: Button = %WizardButton
@onready var ranger_button: Button = %RangerButton
@onready var mead_button: Button = %MeadButton
@onready var herbalist_button: Button = %HerbalistButton
@onready var graveyard_button: Button = %GraveyardButton
@onready var sewers_button: Button = %SewersButton
@onready var dev_button: Button = %DevButton

func _ready() -> void:
	var world = load("res://scripts/world.gd").new()
	world.generate(20261114)
	sim.attach_world(world)
	map_view.setup(world, sim)
	map_view.center_on(sim.keep_pos)
	map_view.tile_clicked.connect(_on_tile_clicked)
	farm_button.pressed.connect(_on_farm_pressed)
	house_button.pressed.connect(_on_house_pressed)
	guard_button.pressed.connect(_on_guard_pressed)
	tavern_button.pressed.connect(_on_tavern_pressed)
	market_button.pressed.connect(_on_market_pressed)
	shrine_button.pressed.connect(_on_shrine_pressed)
	blacksmith_button.pressed.connect(_on_blacksmith_pressed)
	wizard_button.pressed.connect(_on_wizard_pressed)
	ranger_button.pressed.connect(_on_ranger_pressed)
	mead_button.pressed.connect(_on_mead_pressed)
	herbalist_button.pressed.connect(_on_herbalist_pressed)
	graveyard_button.pressed.connect(_on_graveyard_pressed)
	sewers_button.pressed.connect(_on_sewers_pressed)
	_build_minimap()
	_build_inspect_panel()
	_build_event_log()
	_build_hero_roster()
	_build_manual()
	_build_placement_panel()
	_build_speed_panel()
	hero_roster_button.pressed.connect(_toggle_hero_roster)
	get_viewport().size_changed.connect(_layout_inspect_panel)
	get_viewport().size_changed.connect(_layout_event_log)
	get_viewport().size_changed.connect(_layout_hero_roster)
	get_viewport().size_changed.connect(_layout_manual_panel)
	get_viewport().size_changed.connect(_layout_placement_panel)
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

func _on_blacksmith_pressed() -> void:
	_toggle_build("blacksmith")

func _on_wizard_pressed() -> void:
	_toggle_build("wizard_tower")

func _on_ranger_pressed() -> void:
	_toggle_build("ranger_hut")

func _on_mead_pressed() -> void:
	_toggle_build("mead_hall")

func _on_herbalist_pressed() -> void:
	_toggle_build("herbalist_grove")

func _on_graveyard_pressed() -> void:
	_toggle_build("graveyard")

func _on_sewers_pressed() -> void:
	_toggle_build("sewers")

func _toggle_build(kind: String) -> void:
	build_mode = "" if build_mode == kind else kind
	_clear_placement()
	_close_manual()
	if build_mode != "":
		_close_inspect()
		_close_event_log()
		_close_hero_roster()
	_refresh()

func _on_tile_clicked(p: Vector2i) -> void:
	_close_hero_roster()
	_close_manual()
	if build_mode != "":
		# First tap only stages the building. The check button commits, so a
		# mis-tap (or an invalid red preview) never spends gold.
		placement_tile = p
		_refresh_placement()
		return
	_inspect(p)

func _confirm_placement() -> void:
	if build_mode == "" or placement_tile.x < 0:
		return
	if sim.build_at(build_mode, placement_tile):
		build_mode = ""
		_clear_placement()
		map_view.queue_redraw()
		minimap.queue_redraw()
		_refresh()
	else:
		_refresh_placement()
		_refresh()

func _cancel_placement() -> void:
	build_mode = ""
	_clear_placement()
	_refresh()

func _clear_placement() -> void:
	placement_tile = Vector2i(-1, -1)
	if map_view != null:
		map_view.set_placement("", Vector2i(-1, -1), false)
	if placement_panel != null:
		placement_panel.visible = false
	if log_button != null:
		log_button.visible = true

func _refresh_placement() -> void:
	if build_mode == "" or placement_tile.x < 0:
		_clear_placement()
		return
	var reason: String = sim.build_block_reason(placement_tile, build_mode)
	var cost: int = sim.BUILD_COSTS[build_mode]
	if reason == "" and sim.gold < cost:
		reason = "Not enough gold"
	var valid: bool = reason == ""
	map_view.set_placement(build_mode, placement_tile, valid)
	placement_label.text = "Tap ✓ to place %s" % Descriptions.building_title(build_mode) \
		if valid else reason
	placement_confirm.disabled = not valid
	placement_panel.visible = true
	log_button.visible = false

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
	hero_label.text = "Heroes %d / %d" % [sim.hero_count(), sim.hero_cap()]
	event_label.text = sim.last_event if sim.last_event != "" else "Drag to explore, pinch to zoom"
	_refresh_event_log()
	_refresh_hero_roster()
	if placement_tile.x >= 0:
		_refresh_placement()
	farm_button.set_pressed_no_signal(build_mode == "farm")
	house_button.set_pressed_no_signal(build_mode == "house")
	guard_button.set_pressed_no_signal(build_mode == "guardhouse")
	tavern_button.set_pressed_no_signal(build_mode == "tavern")
	market_button.set_pressed_no_signal(build_mode == "market")
	shrine_button.set_pressed_no_signal(build_mode == "shrine")
	blacksmith_button.set_pressed_no_signal(build_mode == "blacksmith")
	wizard_button.set_pressed_no_signal(build_mode == "wizard_tower")
	ranger_button.set_pressed_no_signal(build_mode == "ranger_hut")
	mead_button.set_pressed_no_signal(build_mode == "mead_hall")
	herbalist_button.set_pressed_no_signal(build_mode == "herbalist_grove")
	graveyard_button.set_pressed_no_signal(build_mode == "graveyard")
	sewers_button.set_pressed_no_signal(build_mode == "sewers")
	var kinds := {"farm": farm_button, "house": house_button, "guardhouse": guard_button,
		"tavern": tavern_button, "market": market_button, "shrine": shrine_button,
		"blacksmith": blacksmith_button, "wizard_tower": wizard_button,
		"ranger_hut": ranger_button, "mead_hall": mead_button,
		"herbalist_grove": herbalist_button, "graveyard": graveyard_button,
		"sewers": sewers_button}
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
	inspect_action2 = Button.new()
	inspect_action2.add_theme_font_size_override("font_size", 20)
	inspect_action2.visible = false
	inspect_action2.pressed.connect(_on_inspect_action2)
	vb.add_child(top)
	vb.add_child(inspect_blurb)
	vb.add_child(inspect_status)
	vb.add_child(inspect_action)
	vb.add_child(inspect_action2)
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
		inspect_panel.offset_top = -h - 270.0
		inspect_panel.offset_bottom = -270.0

func _agents_here(p: Vector2i) -> Array:
	# Goblins and wild creatures in ground no one has charted stay hidden
	# even when tapped blind.
	var here := []
	for a in sim.agents:
		if a.tile() != p:
			continue
		if (a.kind == "goblin" or a.kind == "creature" or a.kind == "rat" \
				or (a.kind == "undead" and a.undead_side == "hostile")) \
				and not sim.explored_at(p):
			continue
		here.append(a)
	return here

func _inspect(p: Vector2i) -> void:
	# A click anywhere on a multi-tile structure inspects the whole building.
	var origin: Vector2i = sim.building_origin_at(p)
	if origin.x >= 0:
		p = origin
	var known: bool = sim.explored_at(p)
	var b = sim.buildings.get(p)
	var den = sim.dens.get(p) if known else null
	var pile_gold: int = int(sim.loot_piles.get(p, 0)) if known else 0
	var here := _agents_here(p)
	var workable: bool = sim.can_drain_swamp(p) or sim.can_clear_forest(p) \
		or sim.terrain_works.has(p)
	var explore_here: bool = sim.explore_bounties.has(p) \
		or sim.can_post_explore_bounty(p)
	if b == null and den == null and pile_gold <= 0 and here.is_empty() \
			and not workable and not explore_here:
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
	elif sim.explore_bounties.has(selected_tile) \
			or not sim.explored_at(selected_tile):
		var reward: int = int(sim.explore_bounties.get(
			selected_tile, {}).get("reward", 0))
		inspect_title.text = Descriptions.explore_bounty_title()
		inspect_blurb.text = Descriptions.explore_bounty_blurb()
		inspect_status.text = Descriptions.explore_bounty_status(reward, sim)
	else:
		var t: int = sim.world.get_terrain(selected_tile)
		inspect_title.text = Descriptions.terrain_title(t)
		inspect_blurb.text = Descriptions.terrain_blurb(t)
		inspect_status.text = Descriptions.terrain_status(t, sim, selected_tile)

func _refresh_action(p: Vector2i, den) -> void:
	# One-tap actions live on the inspector card: demolition for friendly
	# buildings (except the Palace), bounty flags on lairs, and terrain work.
	if inspect_action2 != null:
		inspect_action2.visible = false
	var b: Dictionary = sim.buildings.get(p, {})
	if not b.is_empty():
		if b.kind == "castle":
			inspect_action.visible = false
		else:
			inspect_action.text = "Demolish %s" % Descriptions.building_title(b.kind)
			inspect_action.visible = true
			inspect_action.disabled = false
		return
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
		_refresh_tribute_action(p, den)
		return
	if sim.explore_bounties.has(p):
		inspect_action.text = "Add to explore bounty (+%dg)" \
			% (sim.BOUNTY_FEE - sim.BOUNTY_OVERHEAD)
		inspect_action.visible = true
		inspect_action.disabled = sim.gold < sim.BOUNTY_FEE
		return
	if not sim.explored_at(p) and sim.can_post_explore_bounty(p):
		inspect_action.text = "Post explore bounty (%dg)" % sim.BOUNTY_FEE
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

func _refresh_tribute_action(p: Vector2i, den) -> void:
	# Tribute is a second, diplomatic lever on the two camps that can be
	# bought off: bandits who rob the roads and gnomes caught in the feud.
	var kind_key: String = den.get("kind", "")
	if kind_key != "bandit_camp" and kind_key != "gnome_enclave":
		return
	if not dens_reachable(p):
		return
	inspect_action2.visible = true
	if sim.tribute_active(p):
		var left: int = maxi(0, int(den.get("tribute_until", 0)) - sim.tick)
		inspect_action2.text = "Tribute holds (%d ticks)" % left
		inspect_action2.disabled = true
	else:
		inspect_action2.text = "Pay tribute (%dg)" % sim.tribute_cost
		inspect_action2.disabled = sim.gold < sim.tribute_cost

func dens_reachable(p: Vector2i) -> bool:
	# Only dens the realm can actually reach are bounty-able.
	return sim.find_path(sim.den_doorstep(p, sim.keep_pos), sim.keep_pos).size() > 0

func _on_inspect_action() -> void:
	if selected_unit != null:
		if selected_unit.kind == "hero":
			sim.dismiss_hero(selected_unit)
			_refresh_world_views()
		return
	if selected_tile.x < 0:
		return
	if sim.buildings.has(selected_tile):
		sim.demolish_building(selected_tile)
	elif sim.dens.has(selected_tile):
		sim.post_bounty(selected_tile)
	elif sim.explore_bounties.has(selected_tile) \
			or not sim.explored_at(selected_tile):
		sim.post_explore_bounty(selected_tile)
	elif sim.world.get_terrain(selected_tile) == sim.world.SWAMP:
		sim.drain_swamp(selected_tile)
	elif sim.world.get_terrain(selected_tile) == sim.world.FOREST:
		sim.clear_forest(selected_tile)
	_refresh_world_views()

func _on_inspect_action2() -> void:
	if selected_tile.x < 0 or not sim.dens.has(selected_tile):
		return
	sim.pay_tribute(selected_tile)
	_refresh_world_views()

func _refresh_world_views() -> void:
	map_view.queue_redraw()
	minimap.queue_redraw()
	_refresh()
	_refresh_inspect()

func _inspect_agent(a) -> void:
	# Follow mode: the panel tracks the unit wherever it walks.
	if inspect_action2 != null:
		inspect_action2.visible = false
	selected_tile = a.tile()
	map_view.selected = selected_tile
	inspect_title.text = Descriptions.unit_title(a)
	inspect_blurb.text = Descriptions.hero_blurb(a) if a.kind == "hero" else ""
	inspect_status.text = Descriptions.agent_activity(a)
	if a.kind == "hero":
		inspect_status.text += "\nAccuracy %d%% · melee %d" % [
			roundi(sim.hero_accuracy(a) * 100.0), sim.hero_melee_damage(a)]
	var here := _agents_here(selected_tile)
	here.erase(a)
	_show_units(here, false)
	if a.kind == "hero":
		var leaving: bool = a.purpose == "leave" or a.goal == "leave" \
			or sim._removals.has(a)
		inspect_action.text = "Leaving the realm" if leaving else "Dismiss hero"
		inspect_action.visible = true
		inspect_action.disabled = leaving
	else:
		inspect_action.visible = false
		if inspect_action2 != null:
			inspect_action2.visible = false

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
	var explore_here: bool = sim.explore_bounties.has(p) \
		or sim.can_post_explore_bounty(p)
	if b == null and den == null and pile_gold <= 0 and not workable \
			and not explore_here:
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
	if inspect_action2 != null:
		inspect_action2.visible = false
	map_view.queue_redraw()

# --- Two-tap placement (mobile-friendly) ---------------------------------

func _build_placement_panel() -> void:
	placement_panel = PanelContainer.new()
	placement_panel.name = "PlacementPanel"
	placement_panel.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	placement_label = Label.new()
	placement_label.add_theme_font_size_override("font_size", 20)
	placement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	placement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_confirm = Button.new()
	placement_confirm.text = "✓ Place"
	placement_confirm.custom_minimum_size = Vector2(118, 52)
	placement_confirm.add_theme_font_size_override("font_size", 22)
	placement_confirm.pressed.connect(_confirm_placement)
	var cancel := Button.new()
	cancel.text = "✕"
	cancel.custom_minimum_size = Vector2(52, 52)
	cancel.add_theme_font_size_override("font_size", 22)
	cancel.pressed.connect(_cancel_placement)
	row.add_child(placement_label)
	row.add_child(placement_confirm)
	row.add_child(cancel)
	placement_panel.add_child(row)
	get_node("UI/Root").add_child(placement_panel)
	_layout_placement_panel()

func _layout_placement_panel() -> void:
	if placement_panel == null:
		return
	var vp := get_viewport_rect().size
	var w := minf(430.0, vp.x - 32.0)
	placement_panel.anchor_left = 0.5
	placement_panel.anchor_right = 0.5
	placement_panel.anchor_top = 1.0
	placement_panel.anchor_bottom = 1.0
	placement_panel.offset_left = -w / 2.0
	placement_panel.offset_right = w / 2.0
	placement_panel.offset_top = -336.0
	placement_panel.offset_bottom = -270.0

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
	log_button.offset_top = -324.0
	log_button.offset_bottom = -268.0

	log_panel = PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Event Log"
	title.add_theme_font_size_override("font_size", 30)
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
	var h := minf(340.0, maxf(140.0, vp.y - 348.0))
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 16.0
	log_panel.offset_right = 16.0 + w
	log_panel.offset_bottom = -336.0
	log_panel.offset_top = -336.0 - h
	log_text.custom_minimum_size = Vector2(0, h - 64.0)

func _toggle_event_log() -> void:
	if log_panel.visible:
		_close_event_log()
		return
	_close_manual()
	_close_hero_roster()
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

# --- Hero roster -----------------------------------------------------------

func _build_hero_roster() -> void:
	hero_roster_panel = PanelContainer.new()
	hero_roster_panel.name = "HeroRosterPanel"
	hero_roster_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Hero Roster"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(_close_hero_roster)
	top.add_child(title)
	top.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_roster_list = VBoxContainer.new()
	hero_roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_roster_list.add_theme_constant_override("separation", 6)
	scroll.add_child(hero_roster_list)
	vb.add_child(top)
	vb.add_child(scroll)
	hero_roster_panel.add_child(vb)
	get_node("UI/Root").add_child(hero_roster_panel)
	_layout_hero_roster()

func _layout_hero_roster() -> void:
	if hero_roster_panel == null:
		return
	var vp := get_viewport_rect().size
	var w := minf(560.0, vp.x - 32.0)
	var h := minf(430.0, maxf(220.0, vp.y - 160.0))
	hero_roster_panel.anchor_left = 0.5
	hero_roster_panel.anchor_right = 0.5
	hero_roster_panel.anchor_top = 0.5
	hero_roster_panel.anchor_bottom = 0.5
	hero_roster_panel.offset_left = -w / 2.0
	hero_roster_panel.offset_right = w / 2.0
	hero_roster_panel.offset_top = -h / 2.0
	hero_roster_panel.offset_bottom = h / 2.0

func _toggle_hero_roster() -> void:
	if hero_roster_panel.visible:
		_close_hero_roster()
		return
	_close_manual()
	_close_inspect()
	_close_event_log()
	hero_roster_panel.visible = true
	_refresh_hero_roster()

func _close_hero_roster() -> void:
	if hero_roster_panel == null:
		return
	hero_roster_panel.visible = false

func _refresh_hero_roster() -> void:
	if hero_roster_panel == null or not hero_roster_panel.visible:
		return
	var roster: Array = sim.hero_roster()
	var ids := []
	for a in roster:
		ids.append(str(a.get_instance_id()))
	var signature := ",".join(ids)
	if signature != hero_roster_signature:
		hero_roster_signature = signature
		_rebuild_hero_roster(roster)
	if roster.is_empty():
		return
	for i in roster.size():
		var row := hero_roster_list.get_child(i) as Button
		if row != null:
			row.text = _hero_roster_line(roster[i])

func _rebuild_hero_roster(roster: Array) -> void:
	for child in hero_roster_list.get_children():
		hero_roster_list.remove_child(child)
		child.queue_free()
	if roster.is_empty():
		var empty := Label.new()
		empty.text = "No heroes serve the realm yet."
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", Color(0.56, 0.56, 0.56))
		hero_roster_list.add_child(empty)
		return
	for a in roster:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 46)
		row.add_theme_font_size_override("font_size", 20)
		row.text = _hero_roster_line(a)
		row.pressed.connect(_on_roster_hero_pressed.bind(a))
		hero_roster_list.add_child(row)

func _hero_roster_line(a) -> String:
	return "%s — %s" % [Descriptions.unit_title(a), Descriptions.agent_activity(a)]

func _on_roster_hero_pressed(a) -> void:
	if not sim.agents.has(a):
		return
	_close_hero_roster()
	selected_unit = a
	_inspect_agent(a)
	map_view.queue_redraw()

# --- Player manual (bottom-right book) ------------------------------------

func _build_manual() -> void:
	manual_button = ManualButtonC.new()
	manual_button.name = "ManualButton"
	manual_button.pressed.connect(_toggle_manual)
	get_node("UI/Root").add_child(manual_button)
	manual_button.anchor_left = 1.0
	manual_button.anchor_right = 1.0
	manual_button.anchor_top = 1.0
	manual_button.anchor_bottom = 1.0
	manual_button.offset_left = -72.0
	manual_button.offset_right = -12.0
	manual_button.offset_top = -68.0
	manual_button.offset_bottom = -12.0

	manual_panel = PanelContainer.new()
	manual_panel.name = "ManualPanel"
	manual_panel.visible = false
	manual_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Player Manual"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(_close_manual)
	top.add_child(title)
	top.add_child(close)
	manual_text = RichTextLabel.new()
	manual_text.bbcode_enabled = true
	manual_text.scroll_active = true
	manual_text.scroll_following = false
	manual_text.selection_enabled = true
	manual_text.add_theme_font_size_override("normal_font_size", 24)
	manual_text.add_theme_font_size_override("bold_font_size", 24)
	manual_text.add_theme_font_size_override("italics_font_size", 24)
	manual_text.add_theme_font_size_override("bold_italics_font_size", 24)
	manual_text.add_theme_constant_override("line_separation", 5)
	manual_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	manual_text.text = ManualC.to_bbcode(ManualC.load_markdown())
	vb.add_child(top)
	vb.add_child(manual_text)
	manual_panel.add_child(vb)
	get_node("UI/Root").add_child(manual_panel)
	_layout_manual_panel()

func _layout_manual_panel() -> void:
	if manual_panel == null:
		return
	var vp := get_viewport_rect().size
	var w := maxf(240.0, minf(1400.0, vp.x * 0.90))
	var h := maxf(220.0, minf(1000.0, vp.y * 0.90))
	manual_panel.anchor_left = 0.5
	manual_panel.anchor_right = 0.5
	manual_panel.anchor_top = 0.5
	manual_panel.anchor_bottom = 0.5
	manual_panel.offset_left = -w / 2.0
	manual_panel.offset_right = w / 2.0
	manual_panel.offset_top = -h / 2.0
	manual_panel.offset_bottom = h / 2.0

func _toggle_manual() -> void:
	if manual_panel.visible:
		_close_manual()
		return
	_close_event_log()
	_close_hero_roster()
	manual_panel.visible = true
	manual_button.set_pressed_no_signal(true)
	manual_text.scroll_to_line(0)

func _close_manual() -> void:
	if manual_panel == null:
		return
	manual_panel.visible = false
	manual_button.set_pressed_no_signal(false)

# --- Dev tools: sim speed (1-3x), fog of war toggle --------------------------

func _build_minimap() -> void:
	minimap = MinimapC.new()
	minimap.name = "Minimap"
	get_node("UI/Root").add_child(minimap)
	minimap.setup(sim.world, sim, map_view)
	minimap.tile_jump.connect(_on_minimap_jump)
	_layout_minimap()

func _layout_minimap() -> void:
	# Bottom-right, with the manual book tucked into the corner beside it.
	var h: float = minimap.custom_minimum_size.y
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -minimap.custom_minimum_size.x - 84.0
	minimap.offset_right = -84.0
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
