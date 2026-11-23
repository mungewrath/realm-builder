const AgentC = preload("res://scripts/agents.gd")

const FARM_COST := 10
const HOUSE_COST := 15
const START_GOLD := 50
const START_POP := 5
# The population is abstract; only a handful of bodies need to walk the map.
const PEASANT_AGENT_CAP := 4
const EVENT_LOG_MAX := 300

const FARM_WORK_TICKS := 2
const FARM_CARRY := 8
const FARM_WORKERS_PER_FARM := 2
const FARM_CAPACITY_POP := 4
const GROWTH_FOOD := 16
const BUILD_WORK_TICKS := 4
const TAX_RATE_TICKS := 4
const HOUSE_TAX_CAP := 15

# Buildings that owe the crown taxes: rate per accrual round, purse cap.
# Shrines and guardhouses are crown service — they earn nothing. Farms pay
# a tithe on top of feeding the realm; markets earn best.
const BUILD_TAX := {
	"farm": {"rate": 1, "cap": 6},
	"house": {"rate": 1, "cap": HOUSE_TAX_CAP},
	"tavern": {"rate": 2, "cap": 20},
	"market": {"rate": 3, "cap": 30},
}

const GUARDHOUSE_COST := 30
const GUARDS_PER_GUARDHOUSE := 2
const GUARD_PATROL_RADIUS := 6
const GUARD_PATROL_WAIT := 3
# Guards defend the realm, not the wilds: they never stray farther than
# this from the keep, whatever they are chasing. Clearing dens is hero work.
const GUARD_LEASH := 10
const DEN_HUNGRY_FOOD := 4
# The wild regrows lairs: spawn-window chance, minimum distance from the
# keep, and clearance required from any building.
const DEN_SPAWN_CHANCE := 0.65
const DEN_WILD_MIN := 12
const DEN_CIV_CLEARANCE := 8

const GOBLIN_RAZE_TICKS := 6
const FARM_PLUNDER := 6
const HOUSE_PLUNDER := 8
const DEN_MAX_LEVEL := 3
const DEN_SEED_COUNT := 3

# Goblin behavior tuning (all overridable vars for tests/tuning).
const MIN_WARBAND := 2
const FORAGE_CARRY := 5
const GATHER_TICKS := 4
const DEN_HEAL_TICKS := 6
const MUSTER_FOOD_COST := 2

const TAVERN_COST := 25
const MARKET_COST := 30
const SHRINE_COST := 35

# M7.1 — the remaining halls of the realm. Their produce is mostly indirect
# (gear, mana, morale, herbs, charted land), so it lives in the hall rows
# below rather than in the tax table.
const BLACKSMITH_COST := 40
const WIZARD_TOWER_COST := 60
const RANGER_HUT_COST := 30
const MEAD_HALL_COST := 45
const HERBALIST_GROVE_COST := 35

# M7.3 — the double-edged halls and diplomacy. The graveyard is corpse
# storage that draws a necromancer but risks unquiet dead; sewers keep fever
# down but draw rats from the filth. Tribute buys temporary peace.
const GRAVEYARD_COST := 50
const SEWERS_COST := 40
const TRIBUTE_COST := 25
const TRIBUTE_TICKS := 200

const BUILDING_SIZES := {
	"farm": Vector2i(1, 1),
	"house": Vector2i(1, 1),
	"guardhouse": Vector2i(2, 1),
	"tavern": Vector2i(2, 1),
	"market": Vector2i(2, 1),
	"shrine": Vector2i(2, 1),
	"blacksmith": Vector2i(2, 1),
	"wizard_tower": Vector2i(1, 2),
	"ranger_hut": Vector2i(2, 1),
	"mead_hall": Vector2i(2, 1),
	"herbalist_grove": Vector2i(2, 2),
	"graveyard": Vector2i(2, 2),
	"sewers": Vector2i(1, 1),
	"castle": Vector2i(3, 3),
}

const BUILD_COSTS := {
	"farm": FARM_COST,
	"house": HOUSE_COST,
	"guardhouse": GUARDHOUSE_COST,
	"tavern": TAVERN_COST,
	"market": MARKET_COST,
	"shrine": SHRINE_COST,
	"blacksmith": BLACKSMITH_COST,
	"wizard_tower": WIZARD_TOWER_COST,
	"ranger_hut": RANGER_HUT_COST,
	"mead_hall": MEAD_HALL_COST,
	"herbalist_grove": HERBALIST_GROVE_COST,
	"graveyard": GRAVEYARD_COST,
	"sewers": SEWERS_COST,
}

# M6.3 — terrain actions. Drained marsh becomes farmland; cleared woods
# become open ground. Both leave a mark on the wilds (pollution), which is
# what druids read as a desecration.
const DRAIN_COST := 25
const CLEAR_COST := 15
# Ordering the work only buys the attempt; peasants (or a helpful hero) must
# invest labour ticks before the land actually changes.
const TERRAIN_WORK_TICKS := 4

# M4 — heroes & attraction (the indirect-control core). Heroes arrive on
# their own, score the world against their personality table, and act on
# their own judgment. The player nudges with buildings, gold, and bounty
# flags — never commands. Adding a class is a content row, not code.
# Base stats are tuned so a fresh hero can handle a small goblin mob
# (2-3 raiders): goblins hit for 1 each per round, while a level-1 hero
# lands a heavier swing only about 40% of the time and breaks off to heal
# before dying.
const HERO_CLASSES := {
	"rogue": {
		"title": "Rogue",
		"attracted_by": ["tavern", "sewers"],
		"hp": 8,
		"weights": {"bounty": 4, "treasure": 9, "smite_evil": 1, "assist": 0,
			"hunt": 4, "pray": 0, "carouse": 3},
	},
	"warrior": {
		"title": "Warrior",
		"attracted_by": ["guardhouse", "blacksmith"],
		"hp": 11,
		"weights": {"bounty": 8, "treasure": 4, "smite_evil": 3, "assist": 3,
			"hunt": 3, "pray": 1, "carouse": 2},
	},
	"paladin": {
		"title": "Paladin",
		"attracted_by": "shrine",
		"hp": 14,
		"weights": {"bounty": 3, "treasure": 0, "smite_evil": 9, "assist": 4,
			"hunt": 0, "pray": 6, "carouse": 0},
	},
	# M7.1: the druid finally has a hall of its own; the herbalist grove
	# draws them instead of the shrine. Their heart is in the wilds.
	"druid": {
		"title": "Druid",
		"attracted_by": "herbalist_grove",
		"hp": 10,
		"weights": {"bounty": 0, "treasure": 0, "smite_evil": 2, "assist": 1,
			"hunt": 0, "pray": 3, "carouse": 0, "protect": 9},
	},
	# M7.1 — the rest of the halls' folk. Their quirks are content weights
	# on the existing goal table; unique mechanics (dwarven repair, wizard
	# scrolls) can layer on later without new rows.
	"dwarf": {
		"title": "Dwarf Craftsman",
		"attracted_by": "blacksmith",
		"hp": 12,
		"weights": {"bounty": 2, "treasure": 3, "smite_evil": 3, "assist": 8,
			"hunt": 0, "pray": 0, "carouse": 2},
	},
	"wizard": {
		"title": "Wizard",
		"attracted_by": "wizard_tower",
		"hp": 8,
		"weights": {"bounty": 2, "treasure": 4, "smite_evil": 8, "assist": 1,
			"hunt": 0, "pray": 2, "carouse": 0, "explore": 4},
	},
	"ranger": {
		"title": "Ranger",
		"attracted_by": "ranger_hut",
		"hp": 10,
		"weights": {"bounty": 2, "treasure": 2, "smite_evil": 3, "assist": 2,
			"hunt": 6, "pray": 0, "carouse": 1, "protect": 5, "explore": 6},
	},
	"barbarian": {
		"title": "Barbarian",
		"attracted_by": "mead_hall",
		"hp": 13,
		"weights": {"bounty": 9, "treasure": 4, "smite_evil": 4, "assist": 1,
			"hunt": 2, "pray": 0, "carouse": 4},
	},
	# M7.3: the shady late game. The necromancer is drawn by grave ground,
	# smites evil in its own fashion, and turns stored corpses into temporary
	# servants while the realm has a graveyard.
	"necromancer": {
		"title": "Necromancer",
		"attracted_by": "graveyard",
		"hp": 10,
		"weights": {"bounty": 2, "treasure": 4, "smite_evil": 9, "assist": 0,
			"hunt": 1, "pray": 0, "carouse": 0, "explore": 5},
	},
}
# Ventures outrank leisure, leisure outranks idle strolling; ties break
# toward the earlier entry.
const HERO_GOAL_PRIORITY := ["rest", "leave", "gear", "shop", "smite",
	"bounty", "treasure", "protect", "hunt", "pray", "carouse", "explore",
	"assist", "patrol"]

# M7.1 — hall production pacing. Stocks are per-building; the globals only
# total what the realm has produced for the inspector and tests.
const GEAR_FORGE_TICKS := 45
const GEAR_STOCK_CAP := 6
const MANA_TRICKLE_TICKS := 30
const MANA_STOCK_CAP := 9
const TOWER_SCRY_TICKS := 60
const TOWER_REVEAL := 6.0
const RANGER_WATCH_TICKS := 45
const RANGER_REVEAL := 5.0
const MEAD_BREW_TICKS := 40
const MEAD_STOCK_CAP := 9
const HERB_GROW_TICKS := 40
const HERB_STOCK_CAP := 9
const HERB_CURE_TICKS := 60

const HERO_PURSE_TARGET := 10
const HERO_FATIGUE_MAX := 5
const HERO_REST_TICKS := 10
# Errands are quick, but an evening in the tavern, a quiet hour at the
# shrine, and a spot of hunting all take a little time — heroes settle
# in rather than snapping an action off in a single tick.
const HERO_CAROUSE_TICKS := 8
const HERO_PRAY_TICKS := 6
const HERO_HUNT_TICKS := 4
const HERO_PROTECT_TICKS := 5
const HERO_XP_PER_LEVEL := 4
# A fresh hero is not a guaranteed hit. Accuracy climbs with level; damage
# rises much more slowly than it used to, so veteran power is not raw DPS.
const HERO_BASE_ACCURACY := 0.40
const HERO_ACCURACY_PER_LEVEL := 0.05
const HERO_ACCURACY_MAX := 0.90
const HERO_BASE_DAMAGE := 4
const HERO_DAMAGE_LEVEL_STEP := 3
# Guards and hostile raiders (monsters) are not guaranteed hits either:
# they roll accuracy like heroes, so a lone guard or raider can miss.
const GUARD_BASE_ACCURACY := 0.40
const GUARD_ACCURACY_PER_LEVEL := 0.00
const GUARD_ACCURACY_MAX := 0.90
const GUARD_BASE_DAMAGE := 1
const GUARD_DAMAGE_LEVEL_STEP := 1
const MONSTER_BASE_ACCURACY := 0.40
const MONSTER_ACCURACY_PER_LEVEL := 0.00
const MONSTER_ACCURACY_MAX := 0.90
const MONSTER_BASE_DAMAGE := 1
const MONSTER_DAMAGE_LEVEL_STEP := 1
# Common aliases for the same knobs.
const GUARD_ACCURACY := 0.40
const GUARD_ACC := 0.40
const MONSTER_ACCURACY := 0.40
const MONSTER_ACC := 0.40
const GOBLIN_ACCURACY := 0.40
const GOBLIN_BASE_ACCURACY := 0.40
const BANDIT_ACCURACY := 0.40
const RAT_ACCURACY := 0.40
const HOSTILE_ACCURACY := 0.40
const MOB_ACCURACY := 0.40
const ENEMY_ACCURACY := 0.40
# M7.2 — heroes learn by doing. Each meaningful venture teaches a little;
# the class's core pursuit teaches more, so a rogue grows by treasure and
# a druid by tending the wilds, not only by killing things. Combat XP is
# still paid separately on kills and den clears.
const HERO_ACTIVITY_XP := {
	"explore": 1, "protect": 1, "hunt": 1, "treasure": 1,
	"assist": 1, "carouse": 1,
}
const HERO_CORE_ACTIVITY := {
	"rogue": "treasure",
	"warrior": "bounty", # fighting is their core; combat XP already pays
	"paladin": "smite",
	"druid": "protect",
	"dwarf": "assist",
	"wizard": "explore",
	"ranger": "explore",
	"barbarian": "bounty",
	"necromancer": "smite",
}
# Gear is bought from the blacksmith's forged stock, one point at a time.
const GEAR_COST := 8
const HERO_GEAR_MAX := 4
const BOUNTY_FEE := 20
const BOUNTY_OVERHEAD := 2 # the posting office's cut; the rest lands on the flag

# M5 — exploration & fog of war. The map starts dark; the keep charts its
# surroundings at the start, and heroes (keen eyes, long roam) and the
# realm's workers chart more as they move. Charted ground stays revealed
# permanently — no re-dimming. Goblins reveal nothing; the wild keeps its
# secrets. Fog is presentation plus a build gate: the wilds are simulated
# the same as ever, only unseen. Radii are vars so tests can tweak them.
const KEEP_REVEAL := 7.0
const HERO_REVEAL := 4.0
const WORKER_REVEAL := 2.0

var gold: int = START_GOLD
var pop: int = START_POP
var pop_cap: int = START_POP
var farms: int = 0
var houses: int = 0
var tick: int = 0
# Scrollback for the UI event log: every announcement lands here (the setter
# on `last_event` below appends it), capped so a long game cannot grow it
# without bound. `id` is monotonic so views can append incrementally even
# when old entries rotate out.
var event_log: Array = []
var event_seq: int = 0
var last_event: String = "":
	set(value):
		last_event = value
		if value != "":
			event_seq += 1
			event_log.append({"id": event_seq, "tick": tick, "text": value})
			if event_log.size() > EVENT_LOG_MAX:
				event_log.pop_front()
var world
var buildings := {}
var building_padding := true
var building_footprints := true
# Tile -> origin index. Building dictionaries are still the source of truth;
# the cache rebuilds whenever the count or footprint mode changes, so direct
# test fixtures and normal construction both stay correct.
var _building_tile_index := {}
var _building_index_count := -1
var _building_index_footprints := true
var keep_pos := Vector2i.ZERO
var agents := []
var collector = null
var food_delivered := 0
var growth_mark := 0
var shortage_mark := 0
var shortage_grace := 20
var deliveries := 0
var tax_collected := 0
var tax_deposited := 0

# The keep's household scrapes together a slow trickle of coin (per minute
# of normal time), so a realm that spends its last gold on the wrong
# building can still dig itself out. Vars so tests/tuning can adjust.
var keep_trickle := 5
var keep_trickle_ticks := 60

# M3 — goblins & guards. Dens squat on mountain edges; goblins live there
# and run weighted-random behavior states (lurk/wander/prowl/forage), while
# the den overlays a weighted mood (lurk/prowl/forage/raid) on the idle
# warband. Guards from guardhouses intercept them. All knobs are vars so
# tests (and later tuning) can adjust them without touching constants.
var dens := {} # tile -> {level, hp, food, gold, intent, intent_left, next_muster}
var raids_enabled := true
var den_raid_rest := 80
var den_muster_ticks := 30
var guard_retrain_ticks := 600
var den_intent_weights := {} # optional override; empty = hunger-driven
var dens_max := 5
var den_respawn_rest := 220
var den_respawn_rest_left := 0
var dens_spawned := 0
var den_hp := 12
var goblin_hp := 4
var guard_hp := 6
var rng := RandomNumberGenerator.new()
var raids_launched := 0
var dens_cleared := 0
var buildings_razed := 0
var buildings_demolished := 0
var guards_fallen := 0
var intents_seen := {}
var _removals := []

# M6.1 — ecology. Dens are content rows: where they can squat, what units
# they raise, and what they eat. Goblins are one row among many; prey dens
# regrow their larder from the land, predator dens hunt other dens' stores
# (den-stock predation — no wild unit combat in this chunk). Every wild den
# tracks unmet needs: a long-empty larder migrates the den or starves it.
# All knobs are vars so tests and tuning can adjust them.
const DEN_KINDS := {
	"goblin_den": {
		"title": "Goblin Den",
		"faction": "goblinkin",
		"hostile": true,
		"site": "mountain_edge",
		"spies_as": "A goblin den is spied in the wilds!",
	},
	"rabbit_warren": {
		"title": "Rabbit Warren",
		"faction": "wilders",
		"hostile": false,
		"site": "grass",
		"role": "prey",
		"unit": "rabbit",
		"spies_as": "A warren of rabbits is spied in the meadows!",
	},
	"wolf_den": {
		"title": "Wolf Den",
		"faction": "wilders",
		"hostile": false,
		"site": "forest",
		"role": "predator",
		"unit": "wolf",
		"diet": ["rabbit_warren"],
		"habitat": {"terrain": "forest", "min": 3, "radius": 6},
		"fallback": "farm", # warrens gone: packs raid farm stores
		"spies_as": "A wolf den is spied in the deep woods!",
	},
	"spider_den": {
		"title": "Giant Spider Nest",
		"faction": "wilders",
		"hostile": false,
		"site": "forest",
		"role": "predator",
		"unit": "spider",
		"diet": ["goblin_den"],
		"habitat": {"terrain": "forest", "min": 3, "radius": 6},
		"spies_as": "A giant spider nest is spied in the woods!",
	},
	# M6.3: the marsh chain — frogs breed in the bogs, owlbears stalk the
	# frogs, and draining the wet ground collapses both in turn.
	"frog_den": {
		"title": "Frog Pond",
		"faction": "swampfolk",
		"hostile": false,
		"site": "swamp",
		"role": "prey",
		"unit": "frog",
		"habitat": {"terrain": "swamp", "min": 3, "radius": 6},
		"spies_as": "A chorus of frogs is heard in the marsh!",
	},
	"owlbear_den": {
		"title": "Owlbear Den",
		"faction": "wilders",
		"hostile": false,
		"site": "forest",
		"role": "predator",
		"unit": "owlbear",
		"diet": ["frog_den"],
		"fallback": "farm", # frogs gone: owlbears range toward the farms
		"habitat": {"terrain": "forest", "min": 3, "radius": 6},
		"spies_as": "An owlbear's screech echoes from the deep woods!",
	},
	# M6.2 factions: the hills hold old enemies — kobold burrows and gnome
	# enclaves squabble over the same ridges — while bandit camps squat by
	# the roads and hag covens haunt the deep woods.
	"kobold_den": {
		"title": "Kobold Burrow",
		"faction": "kobolds",
		"hostile": false,
		"site": "mountain_edge",
		"role": "thief",
		"spies_as": "A kobold burrow is spied in the hills!",
	},
	"gnome_enclave": {
		"title": "Gnome Enclave",
		"faction": "gnomes",
		"hostile": false,
		"site": "mountain_edge",
		"role": "trader",
		"spies_as": "A gnome enclave is spied in the hills!",
	},
	"bandit_camp": {
		"title": "Bandit Camp",
		"faction": "bandits",
		"hostile": true,
		"site": "grass",
		"role": "raider",
		"spies_as": "A bandit camp is spied by the road!",
	},
	"hag_coven": {
		"title": "Hag Coven",
		"faction": "hags",
		"hostile": true,
		"site": "forest",
		"role": "curser",
		"habitat": {"terrain": "forest", "min": 3, "radius": 6},
		"spies_as": "A hag coven is spied in the deep woods!",
	},
}

# M6.2 — faction tension. A symmetric -3..+3 ledger per pair (positive =
# alliance-lean), seeded from content-design and shifted by events, drifting
# back toward indifference. Keys sort the two faction ids so the pair is
# order-independent.
const FACTION_BASE_TENSION := {
	"goblinkin|kobolds": 1,
	"goblinkin|gnomes": -3,
	"goblinkin|bandits": 1,
	"goblinkin|hags": 0,
	"goblinkin|wilders": -1,
	"goblinkin|unquiet": 1,
	"kobolds|gnomes": -3,
	"kobolds|bandits": 0,
	"kobolds|hags": 0,
	"kobolds|wilders": 0,
	"kobolds|unquiet": -1,
	"gnomes|bandits": -1,
	"gnomes|hags": -1,
	"gnomes|wilders": 1,
	"gnomes|unquiet": -2,
	"bandits|hags": 1,
	"bandits|wilders": 0,
	"bandits|unquiet": 0,
	"hags|wilders": 1,
	"hags|unquiet": 1,
	"wilders|unquiet": -2,
}

# Per-species agent stats: pace and constitution (creatures are not
# combatants in this chunk, but the agent layer wants both).
const CREATURE_STATS := {
	"rabbit": {"speed": 2.2, "hp": 1, "carry": 2},
	"wolf": {"speed": 3.0, "hp": 3, "carry": 3},
	"spider": {"speed": 2.4, "hp": 3, "carry": 2},
	"frog": {"speed": 2.0, "hp": 1, "carry": 2},
	"owlbear": {"speed": 2.8, "hp": 6, "carry": 4},
}

const WILD_DEN_FOOD_START := 5
const PREY_FOOD_CAP := 8
# A pack hunts once its larder reaches this mark, and a starving pack sends
# a second hunter out rather than waiting for the first to come home.
const PREDATOR_HUNGRY_FOOD := 6
const PREDATOR_STARVING_FOOD := 2

# Wild ecology: toggle, caps, and pacing. Existing exact-accounting suites
# run with `wild_ecology` off, same pattern as fog and the gold trickle.
var wild_ecology := true
var wild_dens_max := 16
var wild_spawn_chance := 0.55
var wild_spawn_weights := {
	"rabbit_warren": 22, "wolf_den": 17, "spider_den": 14,
	"frog_den": 15, "owlbear_den": 9,
	"kobold_den": 11, "gnome_enclave": 9, "bandit_camp": 11, "hag_coven": 9,
}
var den_migrate_ticks := 300
var prey_regrow_ticks := 30
# Hunger pressure: packs burn their larder faster and go hunting sooner, so
# a full map of wildlife keeps moving, eating, and pushing at the farms.
var predator_upkeep_ticks := 90
var wild_den_rest := 110
var dens_migrated := 0
var dens_starved := 0
var wild_dens_spawned := 0
var wild_respawn_rest_left := 0
var hunts_made := 0

# M6.2 — factions & tension. All knobs are vars so tests can compress time.
var tension := {} # "a|b" -> -3..3, drifting toward 0
var tension_decay_ticks := 500
var claim_friction_ticks := 120
var _claim_left := 120
var den_claim_radius := 6
var claims_felt := 0
var feud_ticks := 200
var _feud_left := 200
var feuds_triggered := 0
var kobold_theft_ticks := 150
var kobold_thefts := 0
var gnome_trade_ticks := 200
var gnome_trade_gold := 1
var gnome_trades := 0
var bandit_muster_ticks := 300
var bandit_hp := 5
var bandit_take := 10 # the most one mug lifts from a purse
var bandit_reach := 24 # how far from camp bandits look for purses
var bandit_mugs := 0
var bandits_spawned := 0
var hag_curse_ticks := 300
var hag_curse_duration := 300
var hag_reach := 20
var curses_cast := 0

# M6.3 — terrain actions & the druid's reaction.
var drain_cost := DRAIN_COST
var clear_cost := CLEAR_COST
# tile -> {"kind": "drain"|"clear", "progress": int}; cleared on completion.
var terrain_works := {}
var tiles_drained := 0
var tiles_cleared := 0
var pollution := 0 # wilds despoiled: forests felled and marshes drained
var druid_pollution_limit := 8
var wilderness_tended := 0
var druids_departed := 0

# M4 — heroes. Attraction pace and hero count are vars so tests and tuning
# can adjust them. Bounties are the player's one-tap flags on dens; loot
# piles are what fallen heroes (and cleared dens) leave behind.
var heroes_enabled := true
var hero_attraction_ticks := 45 # a roll every ~45s of normal time
var _hero_attraction_left := 45
var hero_arrival_chance := 0.75
# Finishing a hall of any kind pulls the next attraction roll forward to
# this — the first hero steps out within seconds of the door opening.
var hero_first_arrival_ticks := 10
# The realm's hero ceiling follows its living peasant population: one hero
# per five souls, always at least one. Lose people (or grow too fast) and
# the hall can find itself over its means.
var hero_cap_per_peasant := 5
var hero_cap_min := 1
var hero_over_cap_warnings := 2
var hero_over_cap_warning_gap := 30
# After a hunt or a tavern evening, leisure is off the books for this
# long — heroes rotate between pastimes and the wilds instead of
# grinding one warren (or one dice table) until it runs dry.
var hero_leisure_cooldown := 60
# Aggro: an enemy in this radius pulls a hero off whatever they were doing
# and into a fight. Foes caught tearing at a building raise the alarm much
# farther out. Only overriding needs (fleeing, exhaustion, being indoors)
# keep a hero from answering.
var hero_aggro_radius := 6
var hero_alarm_radius := 12
# Speculative hero searches stop at this depth; real travel routes are not
# capped, but picking a fight or a frontier never needs a whole-map flood.
var hero_search_radius := 10
var heroes_spawned := 0
var heroes_fallen := 0
var heroes_departed := 0
var _hero_over_cap_warnings_left := 2
var _hero_over_cap_warn_in := 0
var dens_cleared_by_heroes := 0
var market_sales := 0
var taverns := 0
var markets := 0
var shrines := 0
# M7.1 — hall production totals (per-building stocks live on the building
# dict so each hall can be inspected on its own).
var gear_forged := 0
var gear_sales := 0
var mana_channeled := 0
var mead_brewed := 0
var herbs_grown := 0
var curses_cured := 0
var ranger_calm_radius := 8
# M7.3 — graveyard, sewer and tribute tuning. Vars so tests can compress
# risk cycles and pin down exact costs without waiting a whole session.
var graveyards := 0
var sewers := 0
var graveyard_reach := 18
var graveyard_risk_ticks := 45
var graveyard_risk_chance := 0.65
var grave_corpse_cap := 9
var undead_loyalty_ticks := 160
var undead_army_cap := 3
var shrine_ward_radius := 8
var corpses_buried := 0
var undead_risen := 0
var undead_raised := 0
var undead_lost := 0
var undead_destroyed := 0
var undead_warded := 0

var sewer_rat_ticks := 120
var sewer_rats_per_building := 2
var rat_spoil := 2
var rats_spawned := 0
var rats_destroyed := 0
var food_spoiled := 0
var plague_check_ticks := 60
var plague_chance := 0.25
var plague_overcrowd_chance := 0.05
var plague_safe_base := 6
var plague_sewer_capacity := 4
var plague_graveyard_capacity := 2
var _plague_left := 60
var plague_outbreaks := 0

var tribute_cost := TRIBUTE_COST
var tribute_ticks := TRIBUTE_TICKS
var tribute_paid := 0

var bounties := {} # den tile -> {reward}
var bounties_posted := 0
var bounties_paid := 0
var explore_bounties := {} # uncharted tile -> {reward}
var explore_bounties_posted := 0
var explore_bounties_paid := 0
var loot_piles := {} # tile -> gold

# M5 — fog state: one layer. `explored` is the map you have charted, and
# charted ground stays lit for good. Open-ground accounting lets the
# exploration flood skip the "there is no frontier anywhere" case in O(1)
# instead of flooding the whole charted map per hero decision.
var fog_enabled := true
var explored := PackedByteArray() # 0 unseen, 1 revealed (permanent)
var open_tiles := PackedByteArray() # 1 for grass/forest tiles
var open_tile_total := 0
var open_tiles_explored := 0
var uncharted_open := {} # open tiles no one has charted yet
var tiles_explored := 0
var landmarks_spotted := 0
# Bumped whenever the explored layer changes, so the view can refresh its fog
# texture in O(1) instead of rescanning every tile each frame.
var fog_version := 0

# Provisions capacity of the realm: complete farms feed people.
func fed_capacity() -> int:
	return farms * FARM_CAPACITY_POP

func hero_cap() -> int:
	# A realm of five peasants can keep one hero; larger populations support
	# proportionally more, but never fewer than one.
	var ratio := maxi(1, hero_cap_per_peasant)
	return maxi(hero_cap_min, floori(float(pop) / float(ratio)))

func attach_world(w) -> void:
	world = w
	rng.seed = 777
	keep_pos = Vector2i(int(w.SIZE_X / 2.0), int(w.SIZE_Y / 2.0))
	buildings[keep_pos] = {"kind": "castle", "complete": true, "tax": 0}
	explored.resize(w.SIZE_X * w.SIZE_Y)
	open_tiles.resize(w.SIZE_X * w.SIZE_Y)
	for i in w.SIZE_X * w.SIZE_Y:
		var t: int = w.tiles[i]
		if t == w.GRASS or t == w.FOREST:
			open_tiles[i] = 1
			open_tile_total += 1
			uncharted_open[Vector2i(i % w.SIZE_X, i / w.SIZE_X)] = true
	if fog_enabled:
		_stamp_explored(keep_pos, KEEP_REVEAL)
	else:
		_reveal_everything()
	_seed_starting_buildings()
	_sync_peasants()
	_hero_over_cap_warnings_left = hero_over_cap_warnings
	_hero_over_cap_warn_in = 0
	_init_tension()
	_spawn_dens()
	if wild_ecology:
		_seed_wild_dens()

func set_fog_enabled(on: bool) -> void:
	# Dev/tuning toggle. Turning fog back on re-charts from where the realm
	# actually stands now: the keep's ground and every friendly agent.
	if fog_enabled == on:
		return
	fog_enabled = on
	fog_version += 1
	for a in agents:
		a.fog_tile = Vector2i(-1, -1)
	if on:
		explored.fill(0)
		tiles_explored = 0
		open_tiles_explored = 0
		uncharted_open.clear()
		for i in open_tiles.size():
			if open_tiles[i] == 1:
				uncharted_open[Vector2i(i % world.SIZE_X, i / world.SIZE_X)] = true
		landmarks_spotted = 0
		_fog_tick()
	else:
		_reveal_everything()

func _reveal_everything() -> void:
	explored.fill(1)
	tiles_explored = explored.size()
	open_tiles_explored = open_tile_total
	uncharted_open.clear()
	fog_version += 1

func _reveal_radius(a) -> float:
	return HERO_REVEAL if a.kind == "hero" else WORKER_REVEAL

func _stamp_explored(p: Vector2i, radius: float) -> void:
	# Chart a disc of tiles around `p`; newly charted dens are landmarks.
	var r := int(ceili(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > radius:
				continue
			var q := p + Vector2i(dx, dy)
			if not world.in_bounds(q):
				continue
			var i: int = q.y * world.SIZE_X + q.x
			if explored[i] == 1:
				continue
			explored[i] = 1
			fog_version += 1
			tiles_explored += 1
			if open_tiles[i] == 1:
				open_tiles_explored += 1
				uncharted_open.erase(q)
			if dens.has(q):
				landmarks_spotted += 1
				var kind_key: String = dens[q].get("kind", "goblin_den")
				last_event = DEN_KINDS[kind_key].spies_as

func _fog_tick() -> void:
	if not fog_enabled:
		return
	for a in agents:
		# Only the realm's folk chart the map. Goblins, bandits and wild
		# creatures reveal nothing — the wild keeps its secrets.
		if a.kind == "goblin" or a.kind == "creature" or a.kind == "bandit" \
				or a.kind == "rat" or a.kind == "undead":
			continue
		var t: Vector2i = a.tile()
		if t != a.fog_tile:
			a.fog_tile = t
			_stamp_explored(t, _reveal_radius(a))

func explored_at(p: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return world.in_bounds(p) and explored[p.y * world.SIZE_X + p.x] == 1

func find_path(from: Vector2i, to: Vector2i, max_depth := -1) -> Array:
	return world.find_path(from, to, max_depth)

func building_size(kind: String) -> Vector2i:
	if not building_footprints:
		return Vector2i.ONE
	return BUILDING_SIZES.get(kind, Vector2i.ONE)

func building_rect(origin: Vector2i, kind: String) -> Rect2i:
	# The keep is anchored by its centre (keep_pos); constructed buildings use
	# the tapped tile as their top-left corner.
	var offset := -Vector2i.ONE if building_footprints and kind == "castle" \
		else Vector2i.ZERO
	return Rect2i(origin + offset, building_size(kind))

func building_tiles(origin: Vector2i, kind: String) -> Array:
	var rect := building_rect(origin, kind)
	var out := []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			out.append(Vector2i(x, y))
	return out

func _ensure_building_index() -> void:
	if _building_index_count == buildings.size() \
			and _building_index_footprints == building_footprints:
		return
	_building_index_count = buildings.size()
	_building_index_footprints = building_footprints
	_building_tile_index.clear()
	for origin in buildings:
		var kind: String = buildings[origin].get("kind", "")
		for t in building_tiles(origin, kind):
			_building_tile_index[t] = origin

func building_origin_at(p: Vector2i) -> Vector2i:
	_ensure_building_index()
	return _building_tile_index.get(p, Vector2i(-1, -1))

func _terrain_allows(kind: String, t: int) -> bool:
	if t == world.GRASS:
		return true
	# The grove and ranger hut are tended wild land: they can root in marsh
	# or woods as readily as on open grass.
	if kind == "herbalist_grove" or kind == "ranger_hut":
		return t == world.FOREST or t == world.SWAMP
	return false

func _building_padding_blocked(origin: Vector2i, kind: String) -> bool:
	if not building_padding:
		return false
	var rect := building_rect(origin, kind)
	for y in range(rect.position.y - 1, rect.position.y + rect.size.y + 1):
		for x in range(rect.position.x - 1, rect.position.x + rect.size.x + 1):
			var q := Vector2i(x, y)
			if rect.has_point(q):
				continue
			if building_origin_at(q).x >= 0:
				return true
	return false

func build_block_reason(p: Vector2i, kind := "") -> String:
	if world == null:
		return "Cannot build there"
	var rect := building_rect(p, kind)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var q := Vector2i(x, y)
			if not world.in_bounds(q):
				return "Cannot build there"
			# You cannot raise walls on land no one has charted.
			if not explored_at(q):
				return "That land is unexplored"
			# Wild dens are occupied ground: no raising walls over a warren.
			if dens.has(q):
				return "Wild beasts den there"
			if building_origin_at(q).x >= 0:
				return "Something already stands there"
			if terrain_works.has(q):
				return "Work is already underway there"
			if not _terrain_allows(kind, world.get_terrain(q)):
				return "Cannot build there"
	# Keep a full ring of open ground between buildings, so settlements
	# breathe and every structure keeps its own patch of land.
	if _building_padding_blocked(p, kind):
		return "Leave a one-tile gap between buildings"
	return ""

func can_build_at(p: Vector2i, kind := "") -> bool:
	return build_block_reason(p, kind) == ""

func build_at(kind: String, p: Vector2i) -> bool:
	if not BUILD_COSTS.has(kind):
		last_event = "Unknown building"
		return false
	var reason := build_block_reason(p, kind)
	if reason != "":
		last_event = reason
		return false
	var cost: int = BUILD_COSTS[kind]
	if gold < cost:
		last_event = "Not enough gold"
		return false
	gold -= cost
	buildings[p] = {"kind": kind, "complete": false, "tax": 0, "progress": 0}
	last_event = "Construction started: " + kind
	return true

func can_drain_swamp(p: Vector2i) -> bool:
	return world != null and world.in_bounds(p) and explored_at(p) \
		and world.get_terrain(p) == world.SWAMP \
		and not dens.has(p) and building_origin_at(p).x < 0 \
		and not terrain_works.has(p)

func drain_swamp(p: Vector2i) -> bool:
	# Orders the work: the fee is paid now, the land changes once labour is
	# invested (see tick_terrain). Keeps terrain shaping a real commitment,
	# like raising a building.
	if not can_drain_swamp(p):
		last_event = "Only charted, open marsh can be drained"
		return false
	if gold < drain_cost:
		last_event = "Not enough gold to drain the marsh"
		return false
	gold -= drain_cost
	terrain_works[p] = {"kind": "drain", "progress": 0}
	last_event = "Peasants begin draining the marsh"
	return true

func can_clear_forest(p: Vector2i) -> bool:
	return world != null and world.in_bounds(p) and explored_at(p) \
		and world.get_terrain(p) == world.FOREST \
		and not dens.has(p) and building_origin_at(p).x < 0 \
		and not terrain_works.has(p)

func clear_forest(p: Vector2i) -> bool:
	# Orders the work, as with draining: fee first, labour later.
	if not can_clear_forest(p):
		last_event = "Only charted, open woods can be cleared"
		return false
	if gold < clear_cost:
		last_event = "Not enough gold to clear the woods"
		return false
	gold -= clear_cost
	terrain_works[p] = {"kind": "clear", "progress": 0}
	last_event = "Peasants begin clearing the woods"
	return true

func tick_terrain(p: Vector2i) -> bool:
	# One labour tick on a terrain worksite. Returns true on the tick the
	# land changes; progress persists across workers like a build site.
	if not terrain_works.has(p):
		return false
	var w: Dictionary = terrain_works[p]
	w.progress = int(w.progress) + 1
	if int(w.progress) < TERRAIN_WORK_TICKS:
		return false
	terrain_works.erase(p)
	if w.kind == "drain":
		world.set_terrain(p, world.GRASS)
		_note_terrain_opened(p)
		tiles_drained += 1
		pollution += 2
		last_event = "The marsh is drained for farmland"
	else:
		world.set_terrain(p, world.GRASS)
		tiles_cleared += 1
		pollution += 1
		last_event = "The woods are cleared for timber"
	return true

func _note_terrain_opened(p: Vector2i) -> void:
	# Draining marsh creates new open ground. Track it the same way the
	# fog layer does at world attach, so exploration and build gating stay
	# consistent.
	if open_tiles.size() != world.SIZE_X * world.SIZE_Y:
		return
	var i: int = p.y * world.SIZE_X + p.x
	if open_tiles[i] == 1:
		return
	open_tiles[i] = 1
	open_tile_total += 1
	if explored.size() == open_tiles.size():
		if explored[i] == 1:
			open_tiles_explored += 1
		else:
			uncharted_open[p] = true

func tick_build(p: Vector2i) -> bool:
	# One work tick on a construction site; progress persists across builders.
	var b: Dictionary = buildings[p]
	b.progress = int(b.get("progress", 0)) + 1
	if b.progress >= BUILD_WORK_TICKS:
		complete_building(p)
		return true
	return false

func complete_building(p: Vector2i) -> void:
	var b: Dictionary = buildings[p]
	b.complete = true
	b.progress = BUILD_WORK_TICKS
	match b.kind:
		"farm":
			farms += 1
		"house":
			houses += 1
			pop_cap += 3
		"guardhouse":
			for i in GUARDS_PER_GUARDHOUSE:
				_spawn_guard(p)
		"tavern":
			taverns += 1
		"market":
			markets += 1
		"shrine":
			shrines += 1
		"graveyard":
			graveyards += 1
			# The first burial is already in the ground; the grave earth
			# starts with one corpse to draw on.
			b.corpses = 1
			b.risk = 0
		"sewers":
			sewers += 1
			b.rat_left = sewer_rat_ticks
	# A newly finished hero hall pulls the next attraction roll forward:
	# heroes show up within seconds of the door opening, not after a stale
	# cycle has ground its way around.
	if _is_hero_hall(b.kind) and _count_kind("hero") < hero_cap():
		_hero_attraction_left = mini(_hero_attraction_left, hero_first_arrival_ticks)
	last_event = "Finished building " + b.kind

func _is_hero_hall(kind: String) -> bool:
	for cls in HERO_CLASSES:
		if _class_attracted_to(cls, kind):
			return true
	return false

func _class_attracted_to(cls: String, kind: String) -> bool:
	# M7.1: a hall can draw more than one class (the blacksmith signs
	# warriors as well as dwarves), so a row may list its halls.
	var want = HERO_CLASSES[cls].attracted_by
	if want is Array:
		return want.has(kind)
	return want == kind

func take_tax(p: Vector2i) -> int:
	var t: int = buildings[p].tax
	buildings[p].tax = 0
	tax_collected += t
	return t

func update() -> void:
	tick += 1
	_keep_trickle_tick()
	if collector == null and houses > 0:
		_spawn_collector()
	_accrue_tax()
	_halls_tick()
	_risk_buildings_tick()
	_plague_tick()
	_assign_jobs()
	_route_collector()
	if raids_enabled:
		_dens_tick()
		_assign_guards()
	if wild_ecology:
		_wild_dens_tick()
		_wild_creatures_tick()
		_factions_tick()
	if heroes_enabled:
		_attraction_tick()
		_hero_cap_tick()
		_hero_aggro_tick()
		_assign_heroes()
	for a in agents:
		a.update()
	_fog_tick()
	# Combat is adjacency-driven; with no foes around it is a cheap no-op,
	# so it runs regardless of the raid toggle (hero tests rely on it).
	_combat_step()
	_reap()
	_guard_respawn()
	# Growth from delivered labor, when the larder can support another mouth.
	if pop < pop_cap and pop < fed_capacity() \
			and food_delivered - growth_mark >= GROWTH_FOOD:
		pop += 1
		growth_mark = food_delivered
		last_event = "A villager arrived"
	# Shortage is soft: the realm slowly sheds people it cannot feed,
	# but never below one soul and never to game over.
	elif pop > fed_capacity() and pop > 1 \
			and tick - shortage_mark >= shortage_grace:
		pop -= 1
		shortage_mark = tick
		last_event = "The larder is bare; someone left"
	_sync_peasants()

func _keep_trickle_tick() -> void:
	# A soft floor under the economy: even a broke realm earns pocket coin.
	if tick % int(keep_trickle_ticks) == 0:
		gold += keep_trickle

func warn_threat(threat: Vector2i, radius: float) -> int:
	# Called by M3 raiders; peasants nearby run home. Stub for now.
	var fled := 0
	for a in agents:
		if a.kind == "peasant" and a.state != AgentC.FLEEING \
				and Vector2(a.tile()).distance_to(Vector2(threat)) <= radius:
			a.flee_to(keep_pos)
			fled += 1
	if fled > 0:
		last_event = "Peasants flee the danger!"
	return fled

func deliver(a) -> void:
	match a.kind:
		"peasant":
			if a.carrying > 0:
				food_delivered += a.carrying
				deliveries += 1
				a.carrying = 0
		"goblin", "creature", "bandit":
			# Foraged roots, grazed browse, hunted prey and lifted purses all
			# end up in the home den's stores.
			if a.carrying > 0:
				var den: Dictionary = dens.get(a.home, {})
				if not den.is_empty():
					if a.loot_kind == "gold":
						den.gold = int(den.gold) + a.carrying
					else:
						den.food = int(den.food) + a.carrying
				a.carrying = 0
				a.loot_kind = ""
		_:
			if a.pouch > 0:
				var amount: int = a.pouch
				gold += amount
				tax_deposited += amount
				a.pouch = 0
				last_event = "The collector delivered %d gold" % amount

func _spawn_peasant() -> void:
	var a = AgentC.new()
	a.setup(self, "peasant", keep_pos)
	agents.append(a)

func _peasant_count() -> int:
	var n := 0
	for a in agents:
		if a.kind == "peasant":
			n += 1
	return n

func _seed_starting_buildings() -> void:
	# Give the realm a small head start: one farm and one house, placed
	# on open ground within a short walk of the keep.
	for kind in ["farm", "house"]:
		var placed := false
		for r in range(1, 8):
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					if abs(x) + abs(y) != r:
						continue
					var p: Vector2i = keep_pos + Vector2i(x, y)
					if not can_build_at(p, kind):
						continue
					buildings[p] = {"kind": kind, "complete": true, "tax": 0, "progress": BUILD_WORK_TICKS}
					if kind == "farm":
						farms += 1
					else:
						houses += 1
						pop_cap += 3
					placed = true
					break
				if placed:
					break
			if placed:
				break

func _sync_peasants() -> void:
	# Population keeps growing as an abstract number; only a small visible
	# workforce ever walks the map. This keeps houses cheap to add without
	# turning the simulation into a crowd of pathfinding villagers.
	var want: int = mini(pop, PEASANT_AGENT_CAP)
	var have := _peasant_count()
	while have < want:
		_spawn_peasant()
		have += 1
	while have > want:
		_remove_peasant()
		have -= 1

func _spawn_collector() -> void:
	collector = AgentC.new()
	collector.setup(self, "collector", keep_pos)
	agents.append(collector)
	last_event = "A tax collector now serves the keep"

func _remove_peasant() -> void:
	# Cull order keeps the economy alive: idlers and walkers first, working
	# builders last, laden carriers only when nothing else remains.
	var victim = _pick_victim(AgentC.IDLE, true)
	if victim == null:
		victim = _pick_victim(AgentC.TO_TARGET, true)
	if victim == null:
		victim = _pick_victim(AgentC.RETURNING, true)
	if victim == null:
		victim = _pick_victim(AgentC.FLEEING, true)
	if victim == null:
		victim = _pick_victim(AgentC.RETURNING, false)
	if victim == null:
		victim = _pick_victim(AgentC.ACTING, false)
	if victim != null:
		agents.erase(victim)

func _pick_victim(state_filter: String, only_unladen: bool):
	for a in agents:
		if a.kind == "peasant" and a.state == state_filter \
				and (not only_unladen or a.carrying == 0):
			return a
	return null

func _halls_tick() -> void:
	# M7.1 — the halls' own produce. Each building carries its own timer so
	# a late hall starts its cycle when it opens, not on a global beat.
	for p in buildings.keys():
		var b: Dictionary = buildings[p]
		if not b.complete:
			continue
		match b.kind:
			"blacksmith":
				_blacksmith_tick(b)
			"wizard_tower":
				_wizard_tower_tick(p, b)
			"ranger_hut":
				_ranger_hut_tick(p, b)
			"mead_hall":
				_mead_hall_tick(b)
			"herbalist_grove":
				_herbalist_grove_tick(p, b)

func _blacksmith_tick(b: Dictionary) -> void:
	b.forge = int(b.get("forge", 0)) + 1
	if int(b.forge) < GEAR_FORGE_TICKS:
		return
	b.forge = 0
	if int(b.get("gear", 0)) >= GEAR_STOCK_CAP:
		return
	b.gear = int(b.get("gear", 0)) + 1
	gear_forged += 1

func _wizard_tower_tick(p: Vector2i, b: Dictionary) -> void:
	b.channel = int(b.get("channel", 0)) + 1
	if int(b.channel) >= MANA_TRICKLE_TICKS:
		b.channel = 0
		if int(b.get("mana", 0)) < MANA_STOCK_CAP:
			b.mana = int(b.get("mana", 0)) + 1
			mana_channeled += 1
	b.scry = int(b.get("scry", 0)) + 1
	if int(b.scry) >= TOWER_SCRY_TICKS:
		b.scry = 0
		_stamp_explored(p, TOWER_REVEAL)

func _ranger_hut_tick(p: Vector2i, b: Dictionary) -> void:
	b.watch = int(b.get("watch", 0)) + 1
	if int(b.watch) < RANGER_WATCH_TICKS:
		return
	b.watch = 0
	# The ranger's watch lights the wilder ground around the hut; the trails
	# they walk are what makes the map's edges known to the realm.
	_stamp_explored(p, RANGER_REVEAL)

func _mead_hall_tick(b: Dictionary) -> void:
	b.brew = int(b.get("brew", 0)) + 1
	if int(b.brew) < MEAD_BREW_TICKS:
		return
	b.brew = 0
	if int(b.get("morale", 0)) < MEAD_STOCK_CAP:
		b.morale = int(b.get("morale", 0)) + 1
		mead_brewed += 1

func _herbalist_grove_tick(p: Vector2i, b: Dictionary) -> void:
	b.grow = int(b.get("grow", 0)) + 1
	if int(b.grow) >= HERB_GROW_TICKS:
		b.grow = 0
		if int(b.get("herbs", 0)) < HERB_STOCK_CAP:
			b.herbs = int(b.get("herbs", 0)) + 1
			herbs_grown += 1
	b.tend = int(b.get("tend", 0)) + 1
	if int(b.tend) < HERB_CURE_TICKS:
		return
	b.tend = 0
	if int(b.get("herbs", 0)) <= 0:
		return
	var farm := _nearest_cursed_farm(p)
	if farm.x < 0:
		return
	buildings[farm].cursed_until = 0
	b.herbs = int(b.herbs) - 1
	curses_cured += 1
	last_event = "Herbalists lift a hag's curse from the fields"

# --- M7.3: graveyard/shadow economy, sewers, and tribute ------------------

func _risk_buildings_tick() -> void:
	# The realm's double-edged halls keep their own clocks. Graveyards
	# collect the fallen and either raise servants for a necromancer or
	# let the unquiet claw free; sewers draw rats out of the filth.
	for p in buildings.keys():
		var b: Dictionary = buildings[p]
		if not b.complete:
			continue
		match b.kind:
			"graveyard":
				_graveyard_tick(p, b)
			"sewers":
				_sewer_tick(p, b)
	_undead_tick()
	_rat_tick()

func _graveyard_tick(p: Vector2i, b: Dictionary) -> void:
	b.risk = int(b.get("risk", 0)) + 1
	if int(b.risk) < graveyard_risk_ticks:
		return
	b.risk = 0
	if int(b.get("corpses", 0)) <= 0:
		return
	# A necromancer turns the grave's hoard of corpses into loyal servants;
	# without one, the same stock is a hazard.
	if _has_necromancer():
		if _count_undead("ally") >= undead_army_cap:
			return
		b.corpses = int(b.corpses) - 1
		_spawn_undead(p, false)
		undead_raised += 1
		last_event = "A necromancer raises a grave servant"
		return
	if _shrine_ward_at(p):
		undead_warded += 1
		if undead_warded == 1:
			last_event = "A shrine's ward keeps the graveyard quiet"
		return
	if rng.randf() > graveyard_risk_chance:
		return
	if _count_undead("hostile") >= undead_army_cap:
		return
	b.corpses = int(b.corpses) - 1
	_spawn_undead(p, true)
	undead_risen += 1
	last_event = "Unquiet dead claw free of the graveyard!"

func _has_necromancer() -> bool:
	for a in agents:
		if a.kind == "hero" and a.hero_class == "necromancer" \
				and not _removals.has(a):
			return true
	return false

func _count_undead(side: String) -> int:
	var n := 0
	for a in agents:
		if a.kind == "undead" and a.undead_side == side \
				and not _removals.has(a):
			n += 1
	return n

func _count_agents_home(home_pos: Vector2i, kind: String) -> int:
	var n := 0
	for a in agents:
		if a.home == home_pos and a.kind == kind and not _removals.has(a):
			n += 1
	return n

func _shrine_ward_at(p: Vector2i) -> bool:
	var r2: int = shrine_ward_radius * shrine_ward_radius
	for q in buildings:
		var b: Dictionary = buildings[q]
		if b.complete and b.kind == "shrine" \
				and Vector2(q).distance_squared_to(Vector2(p)) <= r2:
			return true
	return false

func _spawn_undead(grave: Vector2i, hostile: bool) -> void:
	var a = AgentC.new()
	a.species = "ghoul" if hostile else "skeleton"
	a.setup(self, "undead", grave)
	a.home = grave
	a.undead_side = "hostile" if hostile else "ally"
	a.speed = 2.2 if hostile else 2.0
	a.max_hp = 6 if hostile else 5
	a.hp = a.max_hp
	a.decay_left = 0 if hostile else undead_loyalty_ticks
	a.state = AgentC.IDLE
	a.purpose = ""
	agents.append(a)

func _undead_tick() -> void:
	# Hostile dead seek the living; a necromancer's servants march on the
	# realm's enemies until their loyalty runs out.
	for a in agents:
		if a.kind != "undead" or _removals.has(a):
			continue
		if a.undead_side == "ally":
			a.decay_left = int(a.decay_left) - 1
			if int(a.decay_left) <= 0:
				_removals.append(a)
				undead_lost += 1
				last_event = "The raised dead crumble back to dust"
				continue
		if a.fighting or a.state != AgentC.IDLE:
			continue
		if a.undead_side == "ally":
			var den := _nearest_den(a.tile())
			if den.x >= 0:
				a.quest_den = den
				a.assign(den_doorstep(den, a.tile()), AgentC.ASSAULT)
				continue
			var foe = _nearest_foe_near(a, a.home, 18)
			if foe != null:
				a.chase(foe)
				continue
			a.assign(_wilds_spot(a.home, 4, a.tile()), AgentC.WANDER)
			a.behavior_left = 20
			continue
		var victim = _nearest_living_near(a, a.home, 18)
		if victim != null:
			a.chase(victim)
			continue
		var farm := _nearest_complete("farm", a.tile())
		if farm.x < 0:
			farm = _nearest_complete("house", a.tile())
		if farm.x >= 0:
			a.assign(farm, AgentC.RAID)
			continue
		a.assign(_wilds_spot(a.home, 4, a.tile()), AgentC.WANDER)
		a.behavior_left = 20

func _nearest_foe_near(from_agent, center: Vector2i, radius: int):
	var best = null
	var best_d := INF
	var r2 := radius * radius
	for e in agents:
		if e == from_agent or e.hp <= 0 or _removals.has(e):
			continue
		if not _is_hostile_agent(e):
			continue
		var d := Vector2(e.tile()).distance_squared_to(Vector2(center))
		if d > r2 or d >= best_d:
			continue
		best_d = d
		best = e
	return best

func _nearest_living_near(from_agent, center: Vector2i, radius: int):
	var best = null
	var best_d := INF
	var r2 := radius * radius
	for e in agents:
		if e == from_agent or e.hp <= 0 or _removals.has(e):
			continue
		if e.kind != "hero" and e.kind != "guard" and e.kind != "peasant":
			continue
		var d := Vector2(e.tile()).distance_squared_to(Vector2(center))
		if d > r2 or d >= best_d:
			continue
		best_d = d
		best = e
	return best

func undead_raid(u) -> void:
	# The unquiet dead do not loot; they spoil what the living need. A farm
	# loses provisions, a house loses coin to broken stores and panic.
	if buildings.has(u.target) and buildings[u.target].complete:
		var b: Dictionary = buildings[u.target]
		match b.kind:
			"farm":
				var spoiled: int = mini(rat_spoil, food_delivered)
				food_delivered -= spoiled
				food_spoiled += spoiled
				last_event = "Unquiet dead spoil provisions in the fields!"
			"house":
				var lost: int = mini(2, gold)
				gold -= lost
				last_event = "Unquiet dead claw at a house in the night!"

func undead_assault_tick(u) -> void:
	# The den's damage comes from the combat step's siege accounting; the
	# servant lingers while its target stands, then fades when the lair is
	# cleared or its loyalty expires.
	if not dens.has(u.quest_den):
		u.state = AgentC.IDLE
		u.purpose = ""
		return
	u.work_left = 1

func _sewer_tick(p: Vector2i, b: Dictionary) -> void:
	b.rat_left = int(b.get("rat_left", sewer_rat_ticks)) - 1
	if int(b.rat_left) > 0:
		return
	b.rat_left = sewer_rat_ticks
	if _count_agents_home(p, "rat") >= sewer_rats_per_building:
		return
	_spawn_rat(p)

func _spawn_rat(sewer_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.species = "rat"
	a.setup(self, "rat", sewer_pos)
	a.home = sewer_pos
	a.speed = 3.2
	a.max_hp = 2
	a.hp = a.max_hp
	agents.append(a)
	rats_spawned += 1

func _rat_tick() -> void:
	for a in agents:
		if a.kind != "rat" or _removals.has(a) or a.fighting:
			continue
		if a.state != AgentC.IDLE:
			continue
		if a.behavior_left > 0:
			a.behavior_left -= 1
			continue
		var farm := _nearest_complete("farm", a.tile())
		if farm.x >= 0:
			a.assign(farm, AgentC.RAID)
			a.behavior_left = 45
		else:
			a.assign(_wilds_spot(a.home, 4, a.tile()), AgentC.WANDER)
			a.behavior_left = 30

func rat_raid(a) -> void:
	# Rats do not raze; they get into the stores and spoil what they cannot
	# eat. Guards and heroes can cut them down before the damage is done.
	if buildings.has(a.target) and buildings[a.target].complete:
		var spoiled: int = mini(rat_spoil, food_delivered)
		food_delivered -= spoiled
		food_spoiled += spoiled
		last_event = "Sewer rats spoil provisions in the larder!"

func _plague_tick() -> void:
	# Crowded houses breed fever; drains and sewers keep it at bay. The
	# risk only starts once a settlement outgrows its sanitation.
	_plague_left -= 1
	if _plague_left > 0:
		return
	_plague_left = plague_check_ticks
	var chance := _plague_chance_for(pop)
	if chance <= 0.0 or rng.randf() > chance:
		return
	pop = maxi(1, pop - 1)
	shortage_mark = tick
	plague_outbreaks += 1
	last_event = "Fever spreads through the crowded houses!"

func _plague_chance_for(population: int) -> float:
	# A base outbreak chance, rising sharply for every person the realm
	# cannot safely house. Sewers and burial ground raise that safe capacity.
	var safe: int = plague_safe_base + sewers * plague_sewer_capacity \
		+ _graveyard_plague_relief()
	var over := population - safe
	if over <= 0:
		return 0.0
	return minf(1.0, plague_chance + plague_overcrowd_chance * float(over))

func _graveyard_plague_relief() -> int:
	var relief := 0
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.complete and b.kind == "graveyard":
			relief += plague_graveyard_capacity
	return relief

# --- tribute diplomacy ----------------------------------------------------

func tribute_active(p: Vector2i) -> bool:
	return dens.has(p) and int(dens[p].get("tribute_until", 0)) > tick

func can_pay_tribute(p: Vector2i) -> bool:
	if not dens.has(p):
		return false
	var kind: String = dens[p].get("kind", "")
	if kind != "bandit_camp" and kind != "gnome_enclave":
		return false
	return not tribute_active(p)

func pay_tribute(p: Vector2i) -> bool:
	if not can_pay_tribute(p):
		last_event = "There is no tribute to pay here"
		return false
	if gold < tribute_cost:
		last_event = "Not enough gold for tribute"
		return false
	gold -= tribute_cost
	var den: Dictionary = dens[p]
	den.tribute_until = tick + tribute_ticks
	tribute_paid += 1
	if den.get("kind", "") == "bandit_camp":
		den.next_muster = bandit_muster_ticks
		last_event = "Bandits take the tribute and stay their hands"
	else:
		# Gnome coin buys a truce in the hills; the kobold feud cools while
		# the tinkers' tribute keeps the claim dispute off the ledger.
		shift_tension("kobolds", "gnomes", 3)
		last_event = "Gnome tribute buys a truce in the hills"
	return true

func _gnome_tribute_active() -> bool:
	for p in dens:
		if dens[p].get("kind", "") == "gnome_enclave" and tribute_active(p):
			return true
	return false

func _gnome_warded_pair(a: String, b: String) -> bool:
	if not _gnome_tribute_active():
		return false
	return (a == "kobolds" and b == "gnomes") \
		or (a == "gnomes" and b == "kobolds")

func _nearest_cursed_farm(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "farm" or not b.complete or not is_cursed(p):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _mead_morale_bonus() -> int:
	# Strong drink and louder boasts: mead heartens the realm's fighters,
	# which shows up as a pull toward bounty flags.
	var total := 0
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.complete and b.kind == "mead_hall":
			total += int(b.get("morale", 0))
	return mini(total / 3, 2)

func _ranger_calm_at(p: Vector2i) -> bool:
	# A ranger's watch keeps the wild things from ranging into the settled
	# fields nearby.
	for b in buildings:
		var row: Dictionary = buildings[b]
		if row.complete and row.kind == "ranger_hut" \
				and Vector2(b).distance_to(Vector2(p)) <= ranger_calm_radius:
			return true
	return false

func _accrue_tax() -> void:
	if tick % TAX_RATE_TICKS != 0:
		return
	for p in buildings:
		var b: Dictionary = buildings[p]
		if not b.complete:
			continue
		var row: Dictionary = BUILD_TAX.get(b.kind, {})
		if row.is_empty():
			continue
		b.tax = mini(int(b.tax) + int(row.rate), int(row.cap))

func _assign_jobs() -> void:
	for a in agents:
		if a.kind != "peasant" or a.state != AgentC.IDLE:
			continue
		var site := _nearest_free_site(a.tile())
		if site.x >= 0:
			a.assign(site, AgentC.BUILD)
			continue
		var work := _nearest_free_terrain(a.tile())
		if work.x >= 0:
			a.assign(work, AgentC.TERRAIN)
			continue
		var farm := _nearest_free_farm(a.tile())
		if farm.x >= 0:
			a.assign(farm, AgentC.FARM)

func _route_collector() -> void:
	if collector == null or collector.state != AgentC.IDLE:
		return
	var stops := []
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.complete and int(b.tax) > 0:
			stops.append(p)
	if stops.is_empty():
		return
	var here: Vector2i = collector.tile()
	stops.sort_custom(func(a, b):
		return Vector2(a).distance_squared_to(Vector2(here)) \
			< Vector2(b).distance_squared_to(Vector2(here)))
	collector.start_round(stops)

func _claimed(target: Vector2i, purpose: String) -> bool:
	for a in agents:
		if a.purpose == purpose and a.target == target and a.state != AgentC.IDLE:
			return true
	return false

func _nearest_free_terrain(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in terrain_works:
		if _claimed(p, AgentC.TERRAIN):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_free_site(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		if buildings[p].complete or _claimed(p, AgentC.BUILD):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _farm_workers(p: Vector2i) -> int:
	var n := 0
	for a in agents:
		if a.purpose == AgentC.FARM and a.target == p and a.state != AgentC.IDLE:
			n += 1
	return n

func _nearest_free_farm(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "farm" or not b.complete:
			continue
		if is_cursed(p):
			continue # a cursed field yields nothing; farmers stay away
		if _farm_workers(p) >= FARM_WORKERS_PER_FARM:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

# --- M3: goblins & guards --------------------------------------------------

func _spawn_dens() -> void:
	# Dens squat far from the keep, on mountain edges whose doorstep is
	# actually connected to the realm — no sealed pockets.
	var sites: Array = world.mountain_edge_sites()
	var reachable: Array = []
	for s in sites:
		if not find_path(den_doorstep(s, keep_pos), keep_pos).is_empty():
			reachable.append(s)
	reachable.sort_custom(func(a, b):
		return Vector2(a).distance_squared_to(Vector2(keep_pos)) \
			> Vector2(b).distance_squared_to(Vector2(keep_pos)))
	var pool: Array = reachable.slice(0, mini(8, reachable.size()))
	for i in DEN_SEED_COUNT:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		var p: Vector2i = pool.pop_at(idx)
		dens[p] = {
			"kind": "goblin_den",
			"level": 1,
			"hp": den_hp,
			"food": 8,
			"gold": 0,
			"intent": "lurk",
			"intent_left": 30 + rng.randi_range(0, 40),
			"next_muster": den_muster_ticks,
		}
	# The wilds do not refill instantly after a clearing.
	den_respawn_rest_left = den_respawn_rest

func _den_respawn_tick() -> void:
	# Goblin lairs refill on their own clock; other dens (wild ecology) do
	# not crowd them out of the cap.
	if _count_goblin_dens() >= dens_max:
		return
	if den_respawn_rest_left > 0:
		den_respawn_rest_left -= 1
		return
	if not _try_spawn_den():
		# No suitable lair right now: look again soon, without spinning.
		den_respawn_rest_left = 30 + rng.randi_range(0, 60)

func _count_goblin_dens() -> int:
	var n := 0
	for p in dens:
		if dens[p].get("kind", "goblin_den") == "goblin_den":
			n += 1
	return n

func _count_hostile_dens() -> int:
	var n := 0
	for p in dens:
		if is_hostile_den(p):
			n += 1
	return n

func _try_spawn_den() -> bool:
	# The wild regrows lairs from time to time, but shy of civilization:
	# a site must sit far from the keep and clear of every building, and
	# wilder ground (deep forest nearby) is the likeliest cradle.
	if rng.randf() > DEN_SPAWN_CHANCE:
		return false
	var candidates := []
	for s in world.mountain_edge_sites():
		if dens.has(s):
			continue
		var door := den_doorstep(s, keep_pos)
		if Vector2(door).distance_to(Vector2(keep_pos)) < DEN_WILD_MIN:
			continue
		if find_path(door, keep_pos).is_empty():
			continue
		var near_civ := false
		for p in buildings:
			if Vector2(p).distance_to(Vector2(door)) < DEN_CIV_CLEARANCE:
				near_civ = true
				break
		if near_civ:
			continue
		var forest := 0
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var q: Vector2i = door + Vector2i(dx, dy)
				if world.in_bounds(q) and world.get_terrain(q) == world.FOREST:
					forest += 1
		candidates.append([s, 1 + forest])
	if candidates.is_empty():
		return false
	var total := 0
	for c in candidates:
		total += int(c[1])
	var r := rng.randi_range(1, total)
	var pick: Vector2i = candidates[0][0]
	for c in candidates:
		r -= int(c[1])
		if r <= 0:
			pick = c[0]
			break
	dens[pick] = {
		"kind": "goblin_den",
		"level": 1,
		"hp": den_hp,
		"food": 8,
		"gold": 0,
		"intent": "lurk",
		"intent_left": 30 + rng.randi_range(0, 40),
		"next_muster": den_muster_ticks,
	}
	dens_spawned += 1
	den_respawn_rest_left = den_respawn_rest + rng.randi_range(0, 180)
	last_event = "A new goblin den stirs in the wilds!"
	return true

func den_doorstep(den: Vector2i, from: Vector2i) -> Vector2i:
	# Dens sit on (unwalkable) mountain; agents rally on the nearest walkable
	# neighbour instead.
	var best := den
	var best_d := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = den + d
		if world != null and world.in_bounds(n) \
				and world.get_terrain(n) != world.MOUNTAIN \
				and world.get_terrain(n) != world.WATER:
			var dist := Vector2(n).distance_squared_to(Vector2(from))
			if dist < best_d:
				best_d = dist
				best = n
	return best

func _dens_tick() -> void:
	# The den is the warband orchestrator: it musters goblins over time and
	# periodically imposes a weighted-random mood on whoever is home. Wild
	# dens (ecology) run their own simpler machine in `_wild_dens_tick`.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "goblin_den") != "goblin_den":
			continue
		_den_muster(p, den)
		if den.intent == "muster":
			# Gathering a warband: hold the home goblins and watch for quorum.
			if _idle_goblins_at(p).size() >= MIN_WARBAND \
					and _nearest_raid_target(p).x >= 0:
				_launch_raid(p)
			else:
				den.intent_left = int(den.intent_left) - 1
				if int(den.intent_left) <= 0:
					den.intent = "lurk"
					den.intent_left = 20
		elif int(den.intent_left) > 0:
			den.intent_left = int(den.intent_left) - 1
		else:
			_den_pick_mood(p, den)
	_den_respawn_tick()
	_goblin_tick()

func _den_mood_weights(den: Dictionary) -> Dictionary:
	# Hunger drives the mood: a den low on provisions gets restless — it
	# forages hard and raids for what it cannot grow.
	var hungry := int(den.food) <= DEN_HUNGRY_FOOD
	return {
		"lurk": 25,
		"prowl": 20,
		"forage": 25 if hungry else 15,
		"raid": 45 if hungry else 20,
	}

func _den_muster(p: Vector2i, den: Dictionary) -> void:
	den.next_muster = int(den.next_muster) - 1
	if int(den.next_muster) > 0:
		return
	den.next_muster = den_muster_ticks
	var pop := 0
	for a in agents:
		if a.kind == "goblin" and a.home == p:
			pop += 1
	if pop >= 2 + int(den.level):
		return
	if pop == 0:
		# A lone scout always emerges, even from a starving den — the wild
		# never stays empty, and a hunted den can slowly rebuild.
		_spawn_goblin(p)
		return
	if int(den.food) < MUSTER_FOOD_COST:
		return # hungry den: no new goblins
	den.food = int(den.food) - MUSTER_FOOD_COST
	_spawn_goblin(p)

func _den_pick_mood(p: Vector2i, den: Dictionary) -> void:
	var weights: Dictionary = den_intent_weights \
		if not den_intent_weights.is_empty() else _den_mood_weights(den)
	var roll := _weighted_intent(weights)
	intents_seen[roll] = true
	match roll:
		"lurk":
			den.intent = "lurk"
			den.intent_left = 40 + rng.randi_range(0, 40)
		"prowl":
			den.intent = "prowl"
			den.intent_left = 30 + rng.randi_range(0, 30)
			_warband_behave(p, AgentC.PROWL)
		"forage":
			den.intent = "forage"
			den.intent_left = 30 + rng.randi_range(0, 30)
			_warband_behave(p, AgentC.FORAGE)
		"raid":
			var idle := _idle_goblins_at(p)
			if idle.size() < MIN_WARBAND:
				# Too few raiders home: call them in and hold a muster until
				# the warband is ready (or the patience runs out).
				den.intent = "muster"
				den.intent_left = 30 + rng.randi_range(0, 30)
				_warband_behave(p, AgentC.LURK)
			elif _nearest_raid_target(p).x < 0:
				# Nothing worth burning yet: rest a little and re-roll.
				den.intent = "lurk"
				den.intent_left = 20
			else:
				_launch_raid(p)

func _weighted_intent(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += maxi(0, int(weights[k]))
	if total <= 0:
		return "lurk"
	var r := rng.randi_range(1, total)
	for k in weights:
		r -= maxi(0, int(weights[k]))
		if r <= 0:
			return k
	return "lurk"

func _idle_goblins_at(den_pos: Vector2i) -> Array:
	var idle := []
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			idle.append(a)
	return idle

func _warband_behave(den_pos: Vector2i, mood: String) -> void:
	# The den's mood sweeps up every idle goblin — whether that is a raiding
	# party or a lazy afternoon depends on the roll.
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			_goblin_behave(a, mood)

func _launch_raid(den_pos: Vector2i) -> void:
	var den: Dictionary = dens[den_pos]
	var target := _nearest_raid_target(den_pos)
	for a in agents:
		if a.kind == "goblin" and a.home == den_pos and a.state == AgentC.IDLE \
				and not a.fighting:
			a.assign(target, AgentC.RAID)
			a.behavior_left = 0
	den.intent = "rest"
	den.intent_left = den_raid_rest
	raids_launched += 1
	last_event = "A goblin warband marches out of the wild!"
	warn_threat(target, 10.0)

func _goblin_tick() -> void:
	# Personal behavior layer: every idle goblin runs weighted-random states
	# (lurk / wander / prowl / forage) that persist for a state-dependent
	# stretch; combat interrupts them and they hold ground until it passes.
	for a in agents:
		if a.kind != "goblin":
			continue
		if a.fighting:
			continue
		if a.state != AgentC.IDLE:
			continue
		# Wounded goblins convalesce slowly at the den.
		if a.adjacent_to(a.home) and a.hp < a.max_hp:
			a.heal_cd -= 1
			if a.heal_cd <= 0:
				a.heal_cd = DEN_HEAL_TICKS
				a.hp = mini(a.hp + 1, a.max_hp)
		# A den gathering a warband holds its goblins at home.
		var den: Dictionary = dens.get(a.home, {})
		if den.get("intent", "") == "muster":
			continue
		if a.behavior_left > 0:
			a.behavior_left -= 1
			continue
		_roll_goblin_behavior(a)

func _roll_goblin_behavior(g) -> void:
	var weights := {"lurk": 30, "wander": 30, "prowl": 20, "forage": 20}
	var roll := _weighted_intent(weights)
	_goblin_behave(g, roll)

func _goblin_behave(g, roll: String) -> void:
	g.behavior = roll
	match roll:
		"lurk":
			g.behavior_left = 10 + rng.randi_range(0, 20)
		"wander":
			g.assign(_wilds_spot(g.home, 8, g.tile()), AgentC.WANDER)
			g.behavior_left = 15 + rng.randi_range(0, 20)
		"prowl":
			var farm := _nearest_complete("farm", g.tile())
			if farm.x < 0:
				farm = _nearest_complete("house", g.tile())
			if farm.x < 0:
				_goblin_behave(g, "wander")
				return
			var spot := _toward_spot(g.tile(), farm)
			g.assign(spot, AgentC.PROWL)
			g.behavior_left = 20 + rng.randi_range(0, 20)
		"forage":
			var spot := _forage_spot(g.home)
			g.assign(spot, AgentC.FORAGE)
			g.behavior_left = 40

func _wilds_spot(center: Vector2i, radius: int, from: Vector2i) -> Vector2i:
	for i in 10:
		var p := center + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if _open_ground(p):
			return p
	return center

func _toward_spot(from: Vector2i, farm: Vector2i) -> Vector2i:
	# A step that is vaguely on the way to the farm — scouts circle, they do
	# not beeline.
	for i in 10:
		var p := from + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
		if _open_ground(p) \
				and Vector2(p).distance_squared_to(Vector2(farm)) \
					< Vector2(from).distance_squared_to(Vector2(farm)):
			return p
	return from

func _forage_spot(den_pos: Vector2i) -> Vector2i:
	# Berries and grubs: prefer forest near the den, settle for any open
	# ground near it.
	var best := Vector2i(-1, -1)
	var pool := []
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var p: Vector2i = den_pos + Vector2i(dx, dy)
			if world.in_bounds(p) and world.get_terrain(p) == world.FOREST \
					and building_origin_at(p).x < 0:
				pool.append(p)
	if not pool.is_empty():
		return pool[rng.randi_range(0, pool.size() - 1)]
	return _wilds_spot(den_pos, 8, den_pos)

func _open_ground(p: Vector2i) -> bool:
	if world == null or not world.in_bounds(p):
		return false
	var t: int = world.get_terrain(p)
	return (t == world.GRASS or t == world.FOREST) and building_origin_at(p).x < 0

func _nearest_complete(kind: String, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != kind or not b.complete:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_raid_target(from: Vector2i) -> Vector2i:
	for kind in ["farm", "house"]:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p in buildings:
			var b: Dictionary = buildings[p]
			if b.kind != kind or not b.complete:
				continue
			var d := Vector2(p).distance_squared_to(Vector2(from))
			if d < best_d:
				best_d = d
				best = p
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func raid_strike(p: Vector2i, goblin) -> void:
	# The warband puts a building to the torch and pockets what it can carry.
	# Sites still under construction are left alone — nothing to loot there.
	var loot := 0
	if buildings.has(p) and buildings[p].complete:
		var b: Dictionary = buildings[p]
		match b.kind:
			"farm":
				loot = FARM_PLUNDER
				goblin.loot_kind = "food"
			"house", "guardhouse":
				loot = mini(gold, HOUSE_PLUNDER)
				gold -= loot
				goblin.loot_kind = "gold"
		_raze_building(p)
	goblin.carrying = loot

func _remove_building(p: Vector2i) -> Dictionary:
	if not buildings.has(p):
		return {}
	var b: Dictionary = buildings[p]
	if b.complete:
		match b.kind:
			"farm":
				farms -= 1
			"house":
				houses -= 1
				pop_cap = maxi(1, pop_cap - 3)
			"guardhouse":
				_remove_guards_of(p)
			"tavern":
				taverns -= 1
			"market":
				markets -= 1
			"shrine":
				shrines -= 1
			"graveyard":
				graveyards = maxi(0, graveyards - 1)
				_remove_home_agents(p, ["undead"])
			"sewers":
				sewers = maxi(0, sewers - 1)
				_remove_home_agents(p, ["rat"])
	buildings.erase(p)
	return b

func _remove_home_agents(home_pos: Vector2i, kinds: Array) -> void:
	for a in agents:
		if a.home == home_pos and kinds.has(a.kind) and not _removals.has(a):
			_removals.append(a)

func _raze_building(p: Vector2i) -> void:
	var b := _remove_building(p)
	buildings_razed += 1
	last_event = "Goblins razed the %s!" % b.kind

func demolish_building(p: Vector2i) -> bool:
	# The player may clear any friendly structure except the Palace. There is
	# no refund: demolition is a way to correct a layout, not a bank.
	var b: Dictionary = buildings.get(p, {})
	if b.is_empty():
		last_event = "There is no building to demolish"
		return false
	if b.kind == "castle":
		last_event = "The Palace cannot be demolished"
		return false
	_remove_building(p)
	buildings_demolished += 1
	last_event = "The %s is demolished" % String(b.kind).replace("_", " ")
	return true

func _remove_guards_of(p: Vector2i) -> void:
	for a in agents:
		if a.kind == "guard" and a.home == p and not _removals.has(a):
			_removals.append(a)

func raid_returned(goblin) -> void:
	# Warband survivors regroup at the den; a raid that lands loot makes the
	# den grow bolder (bigger musters, bolder moods next time).
	var loot: int = goblin.carrying
	goblin.state = AgentC.IDLE
	goblin.purpose = ""
	deliver(goblin)
	if loot > 0 and dens.has(goblin.home):
		var den: Dictionary = dens[goblin.home]
		if int(den.level) < DEN_MAX_LEVEL:
			den.level = int(den.level) + 1
			last_event = "The goblin den grows bolder"

func _assign_guards() -> void:
	var gobs := []
	var guards := []
	for a in agents:
		if a.kind == "goblin":
			gobs.append(a)
		elif a.kind == "guard":
			guards.append(a)
	# Spread out: a goblin already engaged attracts fewer new guards.
	var engaged := {}
	for g in guards:
		if g.purpose == AgentC.INTERCEPT and g.target_agent != null \
				and agents.has(g.target_agent):
			engaged[g.target_agent] = int(engaged.get(g.target_agent, 0)) + 1
	for g in guards:
		if g.state == AgentC.FLEEING:
			continue
		if g.purpose == AgentC.INTERCEPT:
			var quarry = g.target_agent
			var quarry_valid: bool = quarry != null and agents.has(quarry) \
				and quarry.kind == "goblin" and quarry.state != AgentC.FLEEING \
				and _within_leash(quarry.tile())
			if not quarry_valid:
				# The quarry fell, broke and ran, or left the watch's leash:
				# guards defend the realm, not the wilds.
				g.target_agent = null
				g.purpose = ""
				g.state = AgentC.IDLE
			elif not g.adjacent_to(quarry.tile()):
				var t: Vector2i = quarry.tile()
				if t != g.target:
					g.target = t
					g.path = find_path(g.tile(), t)
			continue
		if g.state != AgentC.IDLE:
			continue
		var gob = _pick_goblin(gobs, g.tile(), engaged)
		if gob != null:
			engaged[gob] = int(engaged.get(gob, 0)) + 1
			g.chase(gob)
			continue
		if g.behavior_left > 0:
			g.behavior_left -= 1
			continue
		_roll_guard_behavior(g)

func _roll_guard_behavior(g) -> void:
	# The watch has its own weighted moods: walk a round, or stand easy.
	var roll := _weighted_intent({"patrol": 55, "lurk": 45})
	g.behavior = roll
	match roll:
		"lurk":
			g.behavior_left = 20 + rng.randi_range(0, 30)
		_:
			g.assign(_patrol_spot(g.home), AgentC.PATROL)
			g.behavior_left = 20 + rng.randi_range(0, 30)

func _within_leash(t: Vector2i) -> bool:
	return Vector2(t).distance_to(Vector2(keep_pos)) <= GUARD_LEASH

func _guard_respawn() -> void:
	# A guardhouse slowly re-trains its watch after losses. The countdown
	# only runs while short-handed, so a change of training pace takes
	# effect at the next loss.
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "guardhouse" or not b.complete:
			continue
		var alive := 0
		for a in agents:
			if a.kind == "guard" and a.home == p:
				alive += 1
		if alive >= GUARDS_PER_GUARDHOUSE:
			if b.has("retrain"):
				b.erase("retrain")
			continue
		if not b.has("retrain"):
			b.retrain = guard_retrain_ticks
		b.retrain = int(b.retrain) - 1
		if int(b.retrain) <= 0:
			_spawn_guard(p)
			b.retrain = guard_retrain_ticks
			last_event = "The guardhouse trains a new watchman"

func _pick_goblin(gobs: Array, from: Vector2i, engaged: Dictionary):
	# Nearest goblin still pressing the raid, preferring one no guard is
	# already on. Fleeing stragglers are written off — chasing them drags
	# the watch away from the realm — and so are goblins beyond the leash:
	# the watch never chases into the wilds.
	var best = null
	var best_d := INF
	var best_free = null
	var best_free_d := INF
	for a in gobs:
		if a.state == AgentC.FLEEING or not _within_leash(a.tile()):
			continue
		var d := Vector2(a.tile()).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = a
		if int(engaged.get(a, 0)) == 0 and d < best_free_d:
			best_free_d = d
			best_free = a
	return best_free if best_free != null else best

func _patrol_spot(home: Vector2i) -> Vector2i:
	for i in 8:
		var p := home + Vector2i(rng.randi_range(-GUARD_PATROL_RADIUS, GUARD_PATROL_RADIUS),
			rng.randi_range(-GUARD_PATROL_RADIUS, GUARD_PATROL_RADIUS))
		if world != null and world.in_bounds(p) and world.get_terrain(p) != world.MOUNTAIN \
				and world.get_terrain(p) != world.WATER and building_origin_at(p).x < 0:
			return p
	return home

# --- M6.1: ecology — wild dens, creatures, food chains ----------------------

func is_hostile_den(p: Vector2i) -> bool:
	return dens.has(p) and DEN_KINDS[dens[p].get("kind", "goblin_den")].hostile

func _wild_den_site(kind_key: String, near := Vector2i(-99, -99), near_r := 0,
		clearance := DEN_CIV_CLEARANCE, min_keep := DEN_WILD_MIN) -> Vector2i:
	# A suitable squat for a den: right terrain, clear of every other den
	# and building, and (unless migrating toward prey) far from the keep.
	if DEN_KINDS[kind_key].site == "mountain_edge":
		return _mountain_edge_site(near, near_r, clearance, min_keep)
	var site: String = DEN_KINDS[kind_key].site
	var terrain_want: int = world.GRASS
	if site == "forest":
		terrain_want = world.FOREST
	elif site == "swamp":
		terrain_want = world.SWAMP
	var best := Vector2i(-1, -1)
	var pool := []
	for y in world.SIZE_Y:
		for x in world.SIZE_X:
			var p := Vector2i(x, y)
			if world.get_terrain(p) != terrain_want or dens.has(p) \
					or building_origin_at(p).x >= 0 or terrain_works.has(p):
				continue
			if near_r <= 0:
				if Vector2(p).distance_to(Vector2(keep_pos)) < min_keep:
					continue
			elif Vector2(p).distance_to(Vector2(near)) > near_r:
				continue
			var near_civ := false
			for b in buildings:
				if Vector2(b).distance_to(Vector2(p)) < clearance:
					near_civ = true
					break
			if near_civ:
				continue
			pool.append(p)
	if pool.is_empty():
		return best
	return pool[rng.randi_range(0, pool.size() - 1)]

func _mountain_edge_pool(clearance := DEN_CIV_CLEARANCE,
		min_keep := DEN_WILD_MIN) -> Array:
	# Reachable mountain shoulders the realm could actually march on — the
	# ground kobolds, gnomes and other hillfolk squat.
	var pool := []
	for s in world.mountain_edge_sites():
		if dens.has(s) or building_origin_at(s).x >= 0:
			continue
		var door := den_doorstep(s, keep_pos)
		if Vector2(door).distance_to(Vector2(keep_pos)) < min_keep:
			continue
		if find_path(door, keep_pos).is_empty():
			continue
		var near_civ := false
		for b in buildings:
			if Vector2(b).distance_to(Vector2(door)) < clearance:
				near_civ = true
				break
		if near_civ:
			continue
		pool.append(s)
	return pool

func _mountain_edge_site(near := Vector2i(-99, -99), near_r := 0,
		clearance := DEN_CIV_CLEARANCE, min_keep := DEN_WILD_MIN) -> Vector2i:
	var pool := _mountain_edge_pool(clearance, min_keep)
	if near_r > 0:
		var near_pool := []
		for p in pool:
			if Vector2(p).distance_to(Vector2(near)) <= near_r:
				near_pool.append(p)
		pool = near_pool
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[rng.randi_range(0, pool.size() - 1)]

func _seed_wild_dens() -> void:
	# The starting wilds hold prey and a predator: a warren to graze and a
	# wolf pack to stalk it. Spiders arrive only with the regrowth. Some
	# worlds have no deep forest; the seed falls back to shallower ground
	# rather than leaving the wilds empty.
	var warren := _wild_den_site("rabbit_warren")
	if warren.x < 0:
		warren = _wild_den_site("rabbit_warren", Vector2i(-99, -99), 0, 4, 8)
	if warren.x >= 0:
		_place_wild_den("rabbit_warren", warren)
	var woods := _wild_den_site("wolf_den")
	if woods.x < 0:
		woods = _wild_den_site("wolf_den", Vector2i(-99, -99), 0, 4, 8)
	if woods.x >= 0:
		_place_wild_den("wolf_den", woods)
	# Marshes: a frog pond and the owlbear that stalks it. Draining the bog
	# unwinds the chain — frogs lose their ground, the owlbear loses its
	# frogs and ranges toward the farms.
	var pond := _wild_den_site("frog_den")
	if pond.x < 0:
		pond = _wild_den_site("frog_den", Vector2i(-99, -99), 0, 4, 8)
	if pond.x >= 0:
		_place_wild_den("frog_den", pond)
		var screech := _wild_den_site("owlbear_den", pond, 8)
		if screech.x < 0:
			screech = _wild_den_site("owlbear_den")
		if screech.x >= 0:
			_place_wild_den("owlbear_den", screech)
	# The old feud: a kobold burrow and a gnome enclave squat the closest
	# pair of hill shoulders — claims nearly overlapping from the start, so
	# the tension ledger has something to grind on. If the hills offer only
	# one shoulder, the feud waits for a spawn.
	var edges := _mountain_edge_pool()
	var kb := Vector2i(-1, -1)
	var gn := Vector2i(-1, -1)
	var best_d := INF
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			var d := Vector2(edges[i]).distance_squared_to(Vector2(edges[j]))
			if d < best_d:
				best_d = d
				kb = edges[i]
				gn = edges[j]
	if kb.x >= 0:
		_place_wild_den("kobold_den", kb)
		_place_wild_den("gnome_enclave", gn)
	# Roads are dangerous: a bandit camp squats the nearer wilds, and a coven
	# haunts the woods closest to the settled fields — both within striking
	# distance of the realm's traffic from the first day.
	var camp := _wild_den_site("bandit_camp", keep_pos, 24, DEN_CIV_CLEARANCE, 10)
	if camp.x < 0:
		camp = _wild_den_site("bandit_camp")
	if camp.x >= 0:
		_place_wild_den("bandit_camp", camp)
	var coven := _wild_den_site("hag_coven", keep_pos, 40)
	if coven.x < 0:
		coven = _wild_den_site("hag_coven")
	if coven.x >= 0:
		_place_wild_den("hag_coven", coven)
	wild_respawn_rest_left = wild_den_rest + rng.randi_range(0, 120)

func _place_wild_den(kind_key: String, p: Vector2i, food := WILD_DEN_FOOD_START) -> void:
	dens[p] = {
		"kind": kind_key,
		"level": 1,
		"hp": den_hp,
		"food": food,
		"gold": 0,
		"unmet": 0,
		"regrow": 0,
	}
	var role: String = DEN_KINDS[kind_key].get("role", "")
	if role == "prey" or role == "predator":
		var unit: String = DEN_KINDS[kind_key].unit
		for i in (2 if unit != "spider" else 1):
			_spawn_creature(unit, p)
	elif role == "raider":
		_spawn_bandit(p)
	if not fog_enabled or not explored[p.y * world.SIZE_X + p.x]:
		return
	# Charted ground at placement time: count it as spotted land only.
	if DEN_KINDS[kind_key].spies_as != "":
		last_event = DEN_KINDS[kind_key].spies_as

func _wild_respawn_tick() -> void:
	if _count_wild_dens() >= wild_dens_max:
		return
	if wild_respawn_rest_left > 0:
		wild_respawn_rest_left -= 1
		return
	if not _try_spawn_wild_den():
		wild_respawn_rest_left = 30 + rng.randi_range(0, 60)

func _count_wild_dens() -> int:
	var n := 0
	for p in dens:
		if dens[p].get("kind", "goblin_den") != "goblin_den":
			n += 1
	return n

func _try_spawn_wild_den() -> bool:
	if rng.randf() > wild_spawn_chance:
		return false
	var kind_key := _weighted_intent(wild_spawn_weights)
	var p := _wild_den_site(kind_key)
	if p.x < 0:
		return false
	# Hill folk do not resettle on a rival's doorstep: the seeded feud is a
	# story beat, but endless respawn judder would keep the tinkers locked
	# behind their walls forever. Keep new dens clear of enemy claims.
	if kind_key == "kobold_den" or kind_key == "gnome_enclave":
		var rival_kind := "gnome_enclave" if kind_key == "kobold_den" \
				else "kobold_den"
		var rival := _nearest_den_of_kind(rival_kind, p)
		if rival.x >= 0 and Vector2(p).distance_to(Vector2(rival)) \
				<= float(den_claim_radius + 1):
			return false
	_place_wild_den(kind_key, p)
	wild_dens_spawned += 1
	wild_respawn_rest_left = wild_den_rest + rng.randi_range(0, 120)
	return true

func _wild_dens_tick() -> void:
	# Wild den upkeep: prey larders regrow from the land; every den counts
	# unmet needs while empty and, past the threshold, moves on or dies off.
	for p in dens.keys():
		var den: Dictionary = dens[p]
		var kind_key: String = den.get("kind", "goblin_den")
		if kind_key == "goblin_den":
			continue # goblins raid instead of migrating; hunger drives them
		var row: Dictionary = DEN_KINDS[kind_key]
		if row.role == "prey":
			den.regrow = int(den.regrow) + 1
			if int(den.regrow) >= prey_regrow_ticks:
				den.regrow = 0
				den.food = mini(int(den.food) + 1, PREY_FOOD_CAP)
		elif row.role == "predator" and int(den.food) > 0:
			# A pack eats: the larder drains between kills, so hunger (and
			# therefore hunting) comes round on its own.
			den.upkeep = int(den.get("upkeep", predator_upkeep_ticks)) - 1
			if int(den.upkeep) <= 0:
				den.upkeep = predator_upkeep_ticks
				den.food = int(den.food) - 1
		# Larder-keepers and land-bound lairs migrate or starve; traders
		# and raiders live off their wits (and other people's purses).
		if not ["prey", "predator", "thief", "curser"].has(row.role):
			continue
		var fed: bool = int(den.food) > 0
		# Some lairs also need the land itself: a drained marsh drowns the
		# frogs as surely as an empty larder.
		if row.has("habitat") and not _habitat_ok(p, row.habitat):
			fed = false
		if fed:
			den.unmet = 0
			continue
		den.unmet = int(den.unmet) + 1
		if int(den.unmet) >= den_migrate_ticks:
			var dest := _migration_site(p, den)
			if dest.x < 0:
				_starve_den(p, den)
			else:
				_migrate_den(p, den, dest)
	_wild_respawn_tick()

func _habitat_ok(p: Vector2i, habitat: Dictionary) -> bool:
	# A den's land need: count suitable terrain within its claim. Draining
	# the bog under a frog pond is how the marsh chain starts collapsing.
	var want: int = world.SWAMP
	if habitat.get("terrain", "swamp") == "forest":
		want = world.FOREST
	elif habitat.get("terrain", "swamp") == "grass":
		want = world.GRASS
	var r: int = int(habitat.get("radius", den_claim_radius))
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var q := p + Vector2i(dx, dy)
			if world != null and world.get_terrain(q) == want:
				n += 1
	return n >= int(habitat.get("min", 1))

func _migration_site(p: Vector2i, den: Dictionary) -> Vector2i:
	# Where a starving den moves: predators follow their prey (a warren of
	# rabbits, say); wolves with no warrens left stalk toward the farm
	# stores, or else roam the far wilds and raid from there; prey dens
	# seek fresh meadows. Spiders with no goblin dens to snare have
	# nowhere to go — they starve.
	var kind_key: String = den.get("kind", "goblin_den")
	var row: Dictionary = DEN_KINDS[kind_key]
	if row.role == "thief":
		# A hungry burrow follows the chickens: squat the hills above the
		# nearest farm, or find fresh hills to skulk in.
		var farm := _nearest_complete("farm", p)
		if farm.x >= 0:
			var near_farm := _mountain_edge_site(farm, 12, 3, 8)
			if near_farm.x >= 0:
				return near_farm
		return _mountain_edge_site()
	if row.role == "predator":
		var prey := _nearest_prey_den(p, row.diet)
		if prey.x >= 0:
			return _wild_den_site(kind_key, prey, 6)
		if row.has("fallback"):
			var farm := _nearest_complete(row.fallback, p)
			if farm.x >= 0:
				var near_farm := _wild_den_site(kind_key, farm, 7, 2)
				if near_farm.x >= 0:
					return near_farm
			return _wild_den_site(kind_key)
		return Vector2i(-1, -1)
	return _wild_den_site(kind_key)

func _migrate_den(p: Vector2i, den: Dictionary, dest: Vector2i) -> void:
	dens.erase(p)
	dens[dest] = den
	# A posted bounty follows the lair it was put on.
	if bounties.has(p):
		bounties[dest] = bounties[p]
		bounties.erase(p)
	den.unmet = 0
	for a in agents:
		if a.kind == "creature" and a.home == p:
			a.home = dest
	dens_migrated += 1
	last_event = "The %s moved on to richer grounds" % DEN_KINDS[den.kind].title

func _starve_den(p: Vector2i, den: Dictionary) -> void:
	dens.erase(p)
	# A lair that dies off on its own takes its posted flag with it.
	bounties.erase(p)
	_thaw_separated_feud()
	dens_starved += 1
	for a in agents:
		if a.kind == "creature" and a.home == p and not _removals.has(a):
			_removals.append(a)
	last_event = "The %s has starved out of the wilds" % DEN_KINDS[den.kind].title

func _nearest_prey_den(from: Vector2i, diet: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in dens:
		if not diet.has(dens[p].get("kind", "")):
			continue
		if int(dens[p].food) <= 0:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _hunters_out(den_pos: Vector2i) -> int:
	var n := 0
	for a in agents:
		if a.kind == "creature" and a.home == den_pos \
				and a.purpose == AgentC.HUNT:
			n += 1
	return n

func _hunt_target(a) -> Vector2i:
	var den: Dictionary = dens.get(a.home, {})
	var row: Dictionary = DEN_KINDS.get(den.get("kind", ""), {})
	if not row.has("diet"):
		return Vector2i(-1, -1)
	var prey := _nearest_prey_den(a.home, row.diet)
	if prey.x >= 0:
		return prey
	if row.has("fallback"):
		var farm := _nearest_complete(row.fallback, a.tile())
		if farm.x >= 0 and not _ranger_calm_at(farm):
			return farm
	return Vector2i(-1, -1)

func hunt_strike(p: Vector2i, hunter) -> void:
	# The predator takes what it can from its prey's larder — or, when the
	# wild prey is gone, strips a farm's stores (no torch, no raze: the
	# wolves want meat, not ashes).
	var taken := 0
	if dens.has(p):
		taken = mini(CREATURE_STATS[hunter.species].carry, int(dens[p].food))
		dens[p].food = int(dens[p].food) - taken
	elif buildings.has(p) and buildings[p].complete:
		taken = FARM_PLUNDER
		last_event = "Wolves strip a farm's stores in the night!"
	hunts_made += 1
	hunter.carrying = taken
	hunter.loot_kind = "food"

func _wild_creatures_tick() -> void:
	for a in agents:
		if a.kind != "creature":
			continue
		if a.state != AgentC.IDLE:
			continue
		if a.behavior_left > 0:
			a.behavior_left -= 1
			continue
		_roll_creature_behavior(a)

func _roll_creature_behavior(a) -> void:
	var den: Dictionary = dens.get(a.home, {})
	var row: Dictionary = DEN_KINDS.get(den.get("kind", ""), {})
	var role: String = row.get("role", "")
	if role == "":
		# A lair cleared out from under its beasts: rabbits and frogs still
		# graze, everything else falls back to hunting.
		role = "prey" if (a.species == "rabbit" or a.species == "frog") \
			else "predator"
	if role == "prey":
		var roll := _weighted_intent({"graze": 60, "wander": 25, "lurk": 15})
		match roll:
			"graze":
				a.assign(_graze_spot(a.home), AgentC.FORAGE)
				a.behavior_left = 40
			"wander":
				a.assign(_wilds_spot(a.home, 5, a.tile()), AgentC.WANDER)
				a.behavior_left = 15 + rng.randi_range(0, 15)
			_:
				a.behavior = "lurk"
				a.behavior_left = 10 + rng.randi_range(0, 20)
		return
	# Predators: hunt when the larder runs low; a starving pack sends both
	# its hunters out at once. Otherwise prowl lazily around the den. No
	# grazing — meat does not grow on bushes; a predator's larder only grows
	# by hunting.
	var food := int(den.get("food", 0))
	if food <= PREDATOR_HUNGRY_FOOD:
		var max_hunters := 2 if food <= PREDATOR_STARVING_FOOD else 1
		if _hunters_out(a.home) < max_hunters:
			var prey := _hunt_target(a)
			if prey.x >= 0:
				a.assign(prey, AgentC.HUNT)
				a.behavior_left = 80
				return
	var roll := _weighted_intent({"lurk": 60, "wander": 40})
	if roll == "lurk":
		a.behavior = "lurk"
		a.behavior_left = 20 + rng.randi_range(0, 30)
	else:
		a.assign(_wilds_spot(a.home, 6, a.tile()), AgentC.WANDER)
		a.behavior_left = 20 + rng.randi_range(0, 20)

func _graze_spot(den_pos: Vector2i) -> Vector2i:
	# Meadow browse: prefer open grass near the den, settle for any open
	# ground around it.
	var pool := []
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var p: Vector2i = den_pos + Vector2i(dx, dy)
			if _open_ground(p) and world.get_terrain(p) == world.GRASS:
				pool.append(p)
	if not pool.is_empty():
		return pool[rng.randi_range(0, pool.size() - 1)]
	return _wilds_spot(den_pos, 6, den_pos)

func _spawn_creature(species_name: String, den_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.species = species_name
	a.setup(self, "creature", den_pos)
	a.home = den_pos
	agents.append(a)

# --- M6.2: factions — tension, the kobold–gnome feud, bandits, hags ---------

func _init_tension() -> void:
	# Normalize the hand-written content keys so every pair lands under the
	# same sorted key no matter which side the content sheet listed first.
	tension = {}
	for k in FACTION_BASE_TENSION:
		var parts: PackedStringArray = k.split("|")
		if parts.size() != 2:
			continue
		tension[_pair_key(parts[0], parts[1])] = int(FACTION_BASE_TENSION[k])

func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

func tension_between(a: String, b: String) -> int:
	return int(tension.get(_pair_key(a, b), 0))

func shift_tension(a: String, b: String, delta: int) -> void:
	# Events nudge the ledger; it never leaves the -3..+3 band.
	if a == b or delta == 0:
		return
	var k := _pair_key(a, b)
	tension[k] = clampi(int(tension.get(k, 0)) + delta, -3, 3)

func _factions_tick() -> void:
	# Grudges and friendships both fade toward indifference over time.
	if tick % tension_decay_ticks == 0:
		for k in tension:
			var v := int(tension[k])
			if v > 0:
				tension[k] = v - 1
			elif v < 0:
				tension[k] = v + 1
	_claim_friction_tick()
	_kobold_tick()
	_gnome_tick()
	_bandit_tick()
	_hag_tick()
	_feud_tick()

func _claim_friction_tick() -> void:
	# Territory is the root of most quarrels: dens of different factions
	# whose claims overlap sour their ledger, tick by tick.
	_claim_left -= 1
	if _claim_left > 0:
		return
	_claim_left = claim_friction_ticks
	var tiles: Array = dens.keys()
	for i in tiles.size():
		var p: Vector2i = tiles[i]
		var f1: String = DEN_KINDS[dens[p].get("kind", "goblin_den")].faction
		if f1 == "wilders":
			continue # beasts do not do politics
		for j in range(i + 1, tiles.size()):
			var q: Vector2i = tiles[j]
			var f2: String = DEN_KINDS[dens[q].get("kind", "goblin_den")].faction
			if f1 == f2 or f2 == "wilders":
				continue
			if _gnome_warded_pair(f1, f2):
				continue # tribute keeps the hill feud off the ledger
			if Vector2(p).distance_squared_to(Vector2(q)) \
					> den_claim_radius * den_claim_radius:
				continue
			shift_tension(f1, f2, -1)
			claims_felt += 1

func _kobold_tick() -> void:
	# Kobolds filch chickens and shiny things: a burrow's larder grows at a
	# farm's expense — or at a gnome enclave's, which is how the feud keeps
	# its kindling.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "") != "kobold_den":
			continue
		den.theft_left = int(den.get("theft_left", kobold_theft_ticks)) - 1
		if int(den.theft_left) > 0:
			continue
		den.theft_left = kobold_theft_ticks
		var farm := _nearest_complete("farm", p)
		var enclave := _nearest_den_of_kind("gnome_enclave", p)
		# Only a burrow whose claim reaches the enclave can rob it: distant
		# kobolds have no quarrel with the hills' far side.
		var enclave_hot: bool = enclave.x >= 0 \
			and not _gnome_tribute_active() \
			and Vector2(enclave).distance_squared_to(Vector2(p)) \
				<= den_claim_radius * den_claim_radius
		var steal_farm := farm.x >= 0 and not is_cursed(farm)
		if enclave_hot and (not steal_farm or Vector2(enclave).distance_squared_to(Vector2(p))
				< Vector2(farm).distance_squared_to(Vector2(p))):
			# Tinker gold is shinier than chickens.
			var gnomes: Dictionary = dens[enclave]
			var purloined := mini(int(gnomes.gold), 2)
			gnomes.gold = int(gnomes.gold) - purloined
			den.food = int(den.food) + 1 + purloined
			shift_tension("kobolds", "gnomes", -1)
			kobold_thefts += 1
			last_event = "Kobolds pilfer the gnome enclave's workshops!"
		elif steal_farm:
			den.food = int(den.food) + 1
			kobold_thefts += 1
			last_event = "Kobolds raid a farm for chickens and shiny things!"

func _gnome_tick() -> void:
	# Gnome tinkers trade gadgets for coin — until the feud with the kobolds
	# makes the hills too dangerous to trade from.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "") != "gnome_enclave":
			continue
		den.trade_left = int(den.get("trade_left", gnome_trade_ticks)) - 1
		if int(den.trade_left) > 0:
			continue
		den.trade_left = gnome_trade_ticks
		if tension_between("gnomes", "kobolds") <= -2 \
				and not _gnome_tribute_active():
			continue # the feud keeps the tinkers behind their walls
		gold += gnome_trade_gold
		den.gold = int(den.gold) + 0 # traded away, not hoarded
		gnome_trades += 1
		last_event = "Gnome tinkers trade their gadgets for coin"

func _feud_tick() -> void:
	# The designed pressure point: once the kobold–gnome ledger sours past
	# the threshold, warbands fall on the enclave. Peace comes from
	# separation (claims stop overlapping, tension drifts back) — or from
	# the hero's sword.
	_feud_left -= 1
	if _feud_left > 0:
		return
	_feud_left = feud_ticks
	if tension_between("kobolds", "gnomes") > -2:
		return
	if _gnome_tribute_active():
		return # paid coin keeps the warbands home
	for p in dens:
		if dens[p].get("kind", "") != "kobold_den":
			continue
		var enclave := _nearest_den_of_kind("gnome_enclave", p)
		if enclave.x < 0:
			continue
		# Warbands march only across contested hills, not the whole map.
		if Vector2(enclave).distance_squared_to(Vector2(p)) \
				> den_claim_radius * den_claim_radius:
			continue
		# Warbands take coin if there is any, otherwise they strip the
		# enclave's larder. With nothing left worth taking, they stay home.
		var gn: Dictionary = dens[enclave]
		if int(gn.gold) > 0:
			var spoils := mini(int(gn.gold), 4)
			gn.gold = int(gn.gold) - spoils
			dens[p].gold = int(dens[p].gold) + spoils
		elif int(gn.food) > 0:
			gn.food = int(gn.food) - 1
			dens[p].food = int(dens[p].food) + 1
		else:
			continue
		feuds_triggered += 1
		last_event = "Kobold warbands fall on the gnome enclave!"
		return

func _feud_anchored() -> bool:
	# The quarrel lives on overlapping claims: at least one burrow and
	# enclave share the same hills.
	for p in dens:
		if dens[p].get("kind", "") != "kobold_den":
			continue
		var enclave := _nearest_den_of_kind("gnome_enclave", p)
		if enclave.x >= 0 and Vector2(enclave).distance_squared_to(Vector2(p)) \
				<= den_claim_radius * den_claim_radius:
			return true
	return false

func _thaw_separated_feud() -> void:
	# Once no burrow and enclave share territory (one side wiped out, or
	# they drifted apart) the old grudge has nothing left to stoke it: the
	# ledger clears, trade reopens and the warbands stop coming. A new
	# burrow moving in later can sour it again.
	if _feud_anchored():
		return
	var k := _pair_key("kobolds", "gnomes")
	if int(tension.get(k, 0)) < 0:
		tension[k] = 0

func _nearest_den_of_kind(kind_key: String, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in dens:
		if dens[p].get("kind", "") != kind_key:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _bandit_tick() -> void:
	# Camps muster rough men; idle bandits look for fat purses near camp and
	# shadow the collector (or a loaded hero) until they can lift the purse.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "") != "bandit_camp":
			continue
		if tribute_active(p):
			continue # bought-off camps do not muster
		den.next_muster = int(den.get("next_muster", bandit_muster_ticks)) - 1
		if int(den.next_muster) > 0:
			continue
		den.next_muster = bandit_muster_ticks
		var pop := 0
		for a in agents:
			if a.kind == "bandit" and a.home == p:
				pop += 1
		if pop < 2 + int(den.level):
			_spawn_bandit(p)
	for a in agents:
		if a.kind != "bandit" or a.fighting:
			continue
		if tribute_active(a.home):
			# Paid tribute: the camp stands down and releases any quarry.
			if a.purpose == AgentC.MUG:
				a.target_agent = null
				a.purpose = ""
				a.state = AgentC.IDLE
				a.path = []
			continue
		if a.purpose == AgentC.MUG:
			var quarry = a.target_agent
			if quarry == null or not agents.has(quarry) \
					or int(quarry.pouch) <= 0:
				a.target_agent = null
				a.purpose = ""
				a.state = AgentC.IDLE
				a.path = []
			elif not a.adjacent_to(quarry.tile()):
				if quarry.tile() != a.target:
					a.target = quarry.tile()
					a.path = find_path(a.tile(), a.target)
			continue
		if a.state != AgentC.IDLE:
			continue
		# Wounded bandits lie low at camp and mend.
		if a.adjacent_to(a.home) and a.hp < a.max_hp:
			a.heal_cd -= 1
			if a.heal_cd <= 0:
				a.heal_cd = DEN_HEAL_TICKS
				a.hp = mini(a.hp + 1, a.max_hp)
		var victim = _pick_mug_victim(a)
		if victim != null:
			a.chase(victim)
			a.purpose = AgentC.MUG
			continue
		a.assign(_wilds_spot(a.home, 5, a.tile()), AgentC.WANDER)
		a.behavior_left = 30

func _pick_mug_victim(bandit):
	# Tax collectors first: soft targets with full purses. A hero on the
	# road is a fallback — and one who may well turn the ambush around.
	var best = null
	var best_d := INF
	var reach_sq: int = bandit_reach * bandit_reach
	for a in agents:
		if a.kind != "collector" or int(a.pouch) <= 0:
			continue
		var d := Vector2(a.tile()).distance_squared_to(Vector2(bandit.home))
		if d > reach_sq or d >= best_d:
			continue
		best_d = d
		best = a
	if best != null:
		return best
	for a in agents:
		if a.kind != "hero" or int(a.pouch) <= 0:
			continue
		var d := Vector2(a.tile()).distance_squared_to(Vector2(bandit.home))
		if d > reach_sq or d >= best_d:
			continue
		best_d = d
		best = a
	return best

func bandit_mug(b) -> void:
	# The lift: a purse lightened on the road, carried home to the camp.
	var victim = b.target_agent
	var take := 0
	if victim != null and agents.has(victim) and int(victim.pouch) > 0:
		take = mini(int(victim.pouch), bandit_take)
		victim.pouch -= take
	b.target_agent = null
	b.carrying = take
	b.loot_kind = "gold"
	if take > 0:
		bandit_mugs += 1
		last_event = "Bandits rob a purse on the road!"
	b.state = AgentC.RETURNING
	b.path = find_path(b.tile(), b.home)

func _spawn_bandit(den_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.setup(self, "bandit", den_pos)
	a.home = den_pos
	agents.append(a)
	bandits_spawned += 1

func _hag_tick() -> void:
	# Hags do not raid; they wither the fields. A coven curses the nearest
	# farm within reach on a slow clock — the curse halts its harvest until
	# it wears off.
	for p in dens:
		var den: Dictionary = dens[p]
		if den.get("kind", "") != "hag_coven":
			continue
		den.curse_left = int(den.get("curse_left", hag_curse_ticks)) - 1
		if int(den.curse_left) > 0:
			continue
		den.curse_left = hag_curse_ticks
		var farm := _nearest_complete("farm", p)
		if farm.x < 0 or Vector2(farm).distance_to(Vector2(p)) > hag_reach:
			continue
		if is_cursed(farm):
			continue
		buildings[farm].cursed_until = tick + hag_curse_duration
		curses_cast += 1
		last_event = "A hag's curse withers the fields!"

func is_cursed(p: Vector2i) -> bool:
	var b: Dictionary = buildings.get(p, {})
	return not b.is_empty() and int(b.get("cursed_until", 0)) > tick

# --- M4: heroes & attraction ------------------------------------------------

func can_post_explore_bounty(p: Vector2i) -> bool:
	# The flag has to sit on land a hero can actually reach, and only land
	# the realm has not charted yet. Existing flags may be topped up later.
	if not fog_enabled or world == null or not world.in_bounds(p):
		return false
	if explored_at(p):
		return false
	return not find_path(keep_pos, p).is_empty()

func post_explore_bounty(p: Vector2i) -> bool:
	# A bounty on a blank patch of map: heroes are invited to go chart it.
	if not explore_bounties.has(p) and not can_post_explore_bounty(p):
		last_event = "Only reachable uncharted ground can take an explore bounty"
		return false
	if gold < BOUNTY_FEE:
		last_event = "Not enough gold for the explore bounty"
		return false
	gold -= BOUNTY_FEE
	var net: int = BOUNTY_FEE - BOUNTY_OVERHEAD
	if explore_bounties.has(p):
		explore_bounties[p].reward += net
	else:
		explore_bounties[p] = {"reward": net}
		explore_bounties_posted += 1
	last_event = "A bounty flag marks uncharted ground!"
	return true

func post_bounty(den_pos: Vector2i) -> bool:
	# The player's one-tap nudge: a flag with gold on it. Heroes weigh it
	# against everything else and decide for themselves. Any lair the realm
	# is not the owner of can be flagged — goblin dens, wild warrens, bandit
	# camps — but never the realm's own buildings.
	if not dens.has(den_pos):
		last_event = "There is no lair to post a bounty on"
		return false
	if gold < BOUNTY_FEE:
		last_event = "Not enough gold for the bounty"
		return false
	gold -= BOUNTY_FEE
	# The fee funds the flag; only the net amount is ever claimable.
	var net: int = BOUNTY_FEE - BOUNTY_OVERHEAD
	if bounties.has(den_pos):
		bounties[den_pos].reward += net
	else:
		bounties[den_pos] = {"reward": net}
		bounties_posted += 1
	last_event = "A bounty flag flies over the lair!"
	return true

func _hero_cap_tick() -> void:
	# The population funds the hero ceiling. When the realm is over its
	# means, warn twice (spaced out so the log is readable), then let the
	# heroes' own action table carry the restless off the map.
	var cap := hero_cap()
	var over: int = _count_kind("hero") - cap
	if over <= 0:
		if _hero_over_cap_warnings_left < hero_over_cap_warnings:
			_hero_over_cap_warnings_left = hero_over_cap_warnings
			_hero_over_cap_warn_in = 0
		return
	if _hero_over_cap_warnings_left <= 0:
		return
	if _hero_over_cap_warn_in > 0:
		_hero_over_cap_warn_in -= 1
		return
	_hero_over_cap_warnings_left -= 1
	if _hero_over_cap_warnings_left > 0:
		var label := "hero" if cap == 1 else "heroes"
		last_event = "The realm's %d peasants can support only %d %s; %d too many." \
			% [pop, cap, label, over]
	else:
		last_event = "Heroes grow restless: the realm supports only %d. Some may leave." \
			% cap
	_hero_over_cap_warn_in = hero_over_cap_warning_gap

func _attraction_tick() -> void:
	# The realm's reputation does the recruiting: a periodic roll whose
	# weights come straight from the building mix.
	_hero_attraction_left -= 1
	if _hero_attraction_left > 0:
		return
	_hero_attraction_left = hero_attraction_ticks
	if _count_kind("hero") >= hero_cap():
		return
	var mix := _attraction_mix()
	if mix.is_empty():
		return
	if rng.randf() > hero_arrival_chance:
		return
	_spawn_hero(_weighted_intent(mix))

func _attraction_mix() -> Dictionary:
	var mix := {}
	for p in buildings:
		var b: Dictionary = buildings[p]
		if not b.complete:
			continue
		for cls in HERO_CLASSES:
			if not _class_attracted_to(cls, b.kind):
				continue
			# A druid smells a defiled realm from the road and turns back:
			# no point attracting one just to watch it depart next tick.
			if cls == "druid" and pollution >= druid_pollution_limit:
				continue
			mix[cls] = int(mix.get(cls, 0)) + 1
	return mix

func _spawn_hero(cls: String) -> void:
	# Heroes arrive where their kind belongs: a rogue steps out of the
	# tavern, a warrior signs on at the guardhouse, a paladin at the
	# shrine. The attraction roll guarantees the hall exists by now.
	var hall := _pick_hall(cls)
	var a = AgentC.new()
	a.setup(self, "hero", hall)
	a.hero_class = cls
	a.max_hp = int(HERO_CLASSES[cls].hp)
	a.hp = a.max_hp
	a.home = hall
	a.assign(a.home, AgentC.RECRUIT)
	agents.append(a)
	heroes_spawned += 1
	var origin := "keep"
	if buildings.has(hall):
		origin = String(buildings[hall].kind).replace("_", " ")
	last_event = "A %s strides out of the %s" \
		% [HERO_CLASSES[cls].title, origin]

func _pick_hall(cls: String) -> Vector2i:
	# A random complete hall that attracts the class; the keep is the
	# fallback of last resort.
	var pool := []
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.complete and _class_attracted_to(cls, b.kind):
			pool.append(p)
	if pool.is_empty():
		return keep_pos
	return pool[rng.randi_range(0, pool.size() - 1)]

func _count_kind(kind: String) -> int:
	var n := 0
	for a in agents:
		if a.kind == kind:
			n += 1
	return n

func _count_complete(kind: String) -> int:
	var n := 0
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind == kind and b.complete:
			n += 1
	return n

func _nearest_forge_with_gear(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.kind != "blacksmith" or not b.complete or int(b.get("gear", 0)) <= 0:
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_den(from: Vector2i) -> Vector2i:
	# Smite targets are dens of evil, not rabbit burrows.
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in dens:
		if not is_hostile_den(p):
			continue
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_pile(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in loot_piles:
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _best_explore_bounty(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_reward := -1
	var best_d := INF
	for p in explore_bounties:
		var reward: int = int(explore_bounties[p].reward)
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if reward > best_reward or (reward == best_reward and d < best_d):
			best_reward = reward
			best_d = d
			best = p
	return best

func _best_bounty(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_reward := -1
	var best_d := INF
	for p in bounties:
		var reward: int = int(bounties[p].reward)
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if reward > best_reward or (reward == best_reward and d < best_d):
			best_reward = reward
			best_d = d
			best = p
	return best

func hero_rest_spot(h) -> Vector2i:
	# A hero turns in at the nearest warm hearth: the tavern, or the
	# herbalist grove when its herbs promise a quieter recovery.
	var here: Vector2i = h.tile()
	var tavern := _nearest_complete("tavern", here)
	var grove := _nearest_complete("herbalist_grove", here)
	if tavern.x < 0:
		return grove if grove.x >= 0 else keep_pos
	if grove.x < 0:
		return tavern
	if Vector2(grove).distance_squared_to(Vector2(here)) \
			< Vector2(tavern).distance_squared_to(Vector2(here)):
		return grove
	return tavern

func hero_goal_scores(h) -> Dictionary:
	# The heart of indirect control: pure, table-driven incentive scoring.
	# Personality weights from the content row decide what this hero cares
	# about; the world decides what is actually available — and the fog
	# decides what the hero has heard of. Dens and loot in uncharted land
	# simply do not exist as options yet.
	var w: Dictionary = HERO_CLASSES[h.hero_class].weights
	var scores := {}
	if h.pouch >= HERO_PURSE_TARGET and _count_complete("market") > 0:
		scores["shop"] = 10 + int(w.treasure)
	# Forged gear beats a heavier purse for anyone who expects a fight.
	# Wizards hoard scrolls and pay sages instead; the forge is not for them.
	if h.hero_class != "wizard" and h.pouch >= GEAR_COST \
			and h.gear < HERO_GEAR_MAX \
			and _nearest_forge_with_gear(h.tile()).x >= 0:
		scores["gear"] = 12 + int(w.get("smite_evil", 0))
	if h.fatigue >= HERO_FATIGUE_MAX:
		scores["rest"] = 12 + h.fatigue
	if not bounties.is_empty() and int(w.bounty) > 0:
		# Bounties fly only over dens the player could see, so they are
		# charted by construction.
		var best_reward := 0
		for p in bounties:
			best_reward = maxi(best_reward, int(bounties[p].reward))
		# The flag's size does the pulling — a pittance tempts, a fortune
		# drags even the reluctant out the door — while personality only
		# tints how tempting flags are at all.
		scores["bounty"] = int(w.bounty) + int(best_reward / 4.0) \
			+ _mead_morale_bonus()
	var explore_spot := _best_explore_bounty(h.tile())
	if explore_spot.x >= 0:
		var explore_reward := int(explore_bounties[explore_spot].reward)
		scores["explore"] = 8 + int(w.get("explore", 0)) \
			+ int(explore_reward / 4.0)
	var known_dens := _dens_known_to_realm()
	if int(w.smite_evil) > 0 and not known_dens.is_empty():
		var top := 1
		for p in known_dens:
			top = maxi(top, int(dens[p].level))
		scores["smite"] = int(w.smite_evil) + top
	# protect_wilderness: druids care about the land, and the more of it
	# the realm has stripped, the harder the pull.
	if int(w.get("protect", 0)) > 0:
		var wilds := _wilds_known_to_realm()
		if not wilds.is_empty():
			scores["protect"] = int(w.protect) + mini(pollution, 10)
	var known_piles := _piles_known_to_realm()
	if int(w.treasure) > 0 and not known_piles.is_empty():
		var best_gold := 0
		for p in known_piles:
			best_gold = maxi(best_gold, int(loot_piles[p]))
		# A pile is certain gold; a bounty means a fight first. Risk-adjusted,
		# free coin on the ground scores a good deal higher.
		scores["treasure"] = int(w.treasure) * 2 + int(best_gold / 4.0)
	# Leisure: hunting warrens, prayer, tavern evenings — the idle hours
	# that keep heroes from marching like clockwork. Each only exists when
	# the realm actually offers it, ventures always outrank them, and the
	# chase itself is for fresh legs: a hero grows tired of hunting long
	# before the warren runs dry, leaving the game to the wolves. A recent
	# round of leisure dulls the appetite (halved score, so quarter weight
	# in the draw) but never locks the door — rotation comes from the
	# odds, not from gates.
	var known_warrens := _warrens_known_to_realm()
	var leisure_damp := 2 if h.leisure_left > 0 else 1
	if int(w.get("hunt", 0)) > 0 and not known_warrens.is_empty() \
			and h.fatigue <= 2:
		var best_game := 0
		for p in known_warrens:
			best_game = maxi(best_game, int(dens[p].food))
		scores["hunt"] = (int(w.hunt) + int(best_game / 4.0)) / leisure_damp
	if int(w.get("pray", 0)) > 0 and _count_complete("shrine") > 0 \
			and h.fatigue >= 2:
		# Prayer is for the weary: a fresh paladin has evil to smite.
		scores["pray"] = int(w.pray) * 2
	if int(w.get("carouse", 0)) > 0 and taverns > 0 \
			and h.fatigue < HERO_FATIGUE_MAX:
		# Ale and dice scale with the purse: a hero with plunder to burn
		# leans hard toward the tavern; a broke one mostly stays home.
		# (The market still outranks it while the purse is worth banking.)
		scores["carouse"] = (int(w.carouse) + rng.randi_range(0, 1)
			+ mini(int(h.pouch), 40) / 4) / leisure_damp
	if int(w.assist) > 0 and (_nearest_free_site(h.tile()).x >= 0 \
			or _nearest_free_terrain(h.tile()).x >= 0):
		scores["assist"] = int(w.assist)
	# Unknown land beats idle strolling: with no venture on the books, a
	# hero heads for the frontier about half the time (a coin-flip against
	# patrolling, broken toward exploring on the tie).
	if not scores.has("explore") and _explore_target(h.tile()).x >= 0:
		scores["explore"] = 1 + rng.randi_range(0, 1) \
			+ int(w.get("explore", 0))
	# Over the realm's means, and already warned: leaving is now one of the
	# hero's own options. The pull grows with the overage, but the weighted
	# draw still leaves room for one last venture.
	if _hero_over_cap_warnings_left <= 0:
		var over: int = _count_kind("hero") - hero_cap()
		if over > 0 and _leave_target(h.tile()).x >= 0:
			scores["leave"] = 4 + mini(over, 4) * 2 + rng.randi_range(0, 2)
	scores["patrol"] = 1
	return scores

func _leave_target(from: Vector2i) -> Vector2i:
	# A departing hero heads for the nearest reachable rim of the map, where
	# the road runs on to whatever realm will have them.
	var rims := []
	for y in world.SIZE_Y:
		for x in world.SIZE_X:
			if x > 3 and x < world.SIZE_X - 4 \
					and y > 3 and y < world.SIZE_Y - 4:
				continue
			var p := Vector2i(x, y)
			if _open_ground(p):
				rims.append(p)
	rims.sort_custom(func(a, b):
		return Vector2(a).distance_squared_to(Vector2(from)) \
			< Vector2(b).distance_squared_to(Vector2(from)))
	for p in rims:
		if p == from or not find_path(from, p).is_empty():
			return p
	return Vector2i(-1, -1)

func _dens_known_to_realm() -> Array:
	# Hostile dens the realm has actually charted — everything else is
	# rumor, and wild beasts are no smiting matter anyway.
	var known := []
	for p in dens:
		if is_hostile_den(p) and explored_at(p):
			known.append(p)
	return known

func _warrens_known_to_realm() -> Array:
	# Hunt grounds: charted warrens that still hold game.
	var known := []
	for p in dens:
		if dens[p].get("kind", "") == "rabbit_warren" \
				and int(dens[p].food) > 0 and explored_at(p):
			known.append(p)
	return known

func _nearest_known_warren(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in _warrens_known_to_realm():
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _wilds_known_to_realm() -> Array:
	# The wilds a druid would tend: charted lairs of the wilders and the
	# marshfolk, whatever their kind.
	var known := []
	for p in dens:
		if is_hostile_den(p):
			continue
		var faction: String = DEN_KINDS[dens[p].get("kind", "goblin_den")].faction
		if faction != "wilders" and faction != "swampfolk":
			continue
		if explored_at(p):
			known.append(p)
	return known

func _nearest_known_wild(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in _wilds_known_to_realm():
		var d := Vector2(p).distance_squared_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = p
	return best

func _piles_known_to_realm() -> Array:
	var known := []
	for p in loot_piles:
		if explored_at(p):
			known.append(p)
	return known

func _explore_target(from: Vector2i) -> Vector2i:
	# A posted flag outranks the nearest frontier: that is the whole point
	# of the bounty. With no flag, find the nearest uncharted walkable tile
	# within a short walk. A local flood is enough: heroes need a frontier
	# to wander toward, not a proof that some far corner is reachable. The
	# depth cap also stops a hero in a fully charted pocket from flooding
	# the realm every decision.
	var bounty_spot := _best_explore_bounty(from)
	if bounty_spot.x >= 0:
		return bounty_spot
	if not fog_enabled:
		return Vector2i(-1, -1)
	if uncharted_open.is_empty():
		return Vector2i(-1, -1)
	var max_depth := maxi(1, int(hero_search_radius))
	var prev := {from: from}
	var depth := {from: 0}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var next_depth: int = int(depth[cur]) + 1
		if next_depth > max_depth:
			continue
		for d in world.DIRS_ALL:
			var n: Vector2i = cur + d
			if not world.in_bounds(n) or prev.has(n):
				continue
			if not _open_ground(n):
				continue
			# Diagonal moves must not squeeze between two blocked tiles.
			if d.x != 0 and d.y != 0:
				if not _open_ground(cur + Vector2i(d.x, 0)) \
						or not _open_ground(cur + Vector2i(0, d.y)):
					continue
			prev[n] = cur
			depth[n] = next_depth
			if explored[n.y * world.SIZE_X + n.x] == 0:
				return n
			queue.append(n)
	return Vector2i(-1, -1)

func _best_hero_goal(scores: Dictionary) -> String:
	# Deterministic pick: highest score wins, ties break toward the fixed
	# priority order. Used by tests (and any UI that wants to show a
	# hero's favored pursuit); live decisions draw by weight instead.
	var best := "patrol"
	var best_v := -1
	for g in HERO_GOAL_PRIORITY:
		if scores.has(g) and int(scores[g]) > best_v:
			best_v = int(scores[g])
			best = g
	return best

func _pick_hero_goal(h, scores: Dictionary) -> String:
	# Overriding priorities come first: safety. An exhausted hero turns
	# in, whatever the dice say. Self-defense needs no goal at all —
	# heroes reflexively fight anything hostile in reach, outside this
	# choice. Everything else is a weighted draw over what the realm
	# offers: favored pursuits are usually taken, but every action on
	# the table keeps a chance — heroes have moods, not gears. Scores
	# square into weights so a fat bounty or a full purse really pulls,
	# while idle options still surface now and then.
	if scores.has("rest") and h.fatigue >= HERO_FATIGUE_MAX:
		return "rest"
	var total := 0
	for g in scores:
		total += int(scores[g]) * int(scores[g])
	if total <= 0:
		return "patrol"
	var roll := rng.randi_range(1, total)
	for g in scores:
		roll -= int(scores[g]) * int(scores[g])
		if roll <= 0:
			return g
	return "patrol"

func _hero_aggro_tick() -> void:
	# Heroes pick fights on their own initiative: any enemy they can see in
	# the vicinity yanks them off patrols, leisure and errands. Only
	# overriding needs hold them back — a fleeing hero is too hurt, an
	# exhausted one must rest, and one inside a building (tavern, market)
	# misses the alarm. Reflexive adjacency combat runs in _combat_step
	# regardless, and a siege stays committed rather than chasing strays.
	for a in agents:
		if a.kind != "hero":
			continue
		if a.state == AgentC.FLEEING or a.fighting:
			continue
		if a.fatigue >= HERO_FATIGUE_MAX:
			continue
		if a.purpose == AgentC.REST or a.purpose == AgentC.SHOP:
			continue
		if a.purpose == AgentC.INTERCEPT or a.purpose == AgentC.ASSAULT:
			continue
		if a.hp <= maxi(1, int(ceil(a.max_hp / 3.0))):
			continue
		var foe = _nearest_visible_foe(a)
		if foe == null:
			continue
		a.chase(foe)
		a.goal = "fight"
		a.decision_left = 0

func _nearest_visible_foe(h):
	var best = null
	var best_d := INF
	for e in agents:
		if not _is_hostile_agent(e):
			continue
		if e.hp <= 0 or _removals.has(e):
			continue
		if not explored_at(e.tile()):
			continue # no line of sight through the fog
		var d: float = Vector2(h.tile()).distance_to(Vector2(e.tile()))
		if d >= best_d or d > hero_alarm_radius:
			continue
		if d > hero_aggro_radius:
			# Only an alarm — a foe at work on a building — carries this far.
			if not _foe_raiding(e):
				continue
		best = e
		best_d = d
	# One local path query for the chosen foe: a chase we cannot walk is no
	# chase, and a speculative chase beyond alarm range is not worth a flood.
	if best == null \
			or find_path(h.tile(), best.tile(), int(ceil(hero_alarm_radius))).is_empty():
		return null
	return best

func _foe_raiding(e) -> bool:
	# A raider at work, or any foe standing on a building's doorstep, is
	# an alarm the whole neighborhood hears. Only the eight neighbouring
	# tiles matter, so this stays cheap no matter how many houses exist.
	if e.purpose == AgentC.RAID:
		return true
	var here: Vector2i = e.tile()
	for d in world.DIRS_ALL:
		if building_origin_at(here + d).x >= 0:
			return true
	return false

func _assign_heroes() -> void:
	for a in agents:
		if a.kind != "hero":
			continue
		_hero_level_check(a)
		if a.hero_class == "druid" and pollution >= druid_pollution_limit:
			# The realm has despoiled too much of the land; the druid
			# abandons it rather than serve the defilers.
			_druid_depart(a)
			continue
		if a.leisure_left > 0:
			a.leisure_left -= 1
		if a.state != AgentC.IDLE or a.fighting:
			continue
		if a.decision_left > 0:
			a.decision_left -= 1
			continue
		_hero_decide(a)

func _hero_decide(h) -> void:
	var goal := _pick_hero_goal(h, hero_goal_scores(h))
	h.goal = goal
	h.decision_left = 2 + rng.randi_range(0, 4)
	match goal:
		"leave":
			h.assign(_leave_target(h.tile()), AgentC.LEAVE)
		"gear":
			h.assign(_nearest_forge_with_gear(h.tile()), AgentC.GEAR)
		"shop":
			h.assign(_nearest_complete("market", h.tile()), AgentC.SHOP)
		"rest":
			h.assign(hero_rest_spot(h), AgentC.REST)
		"smite":
			var den := _nearest_den(h.tile())
			h.quest_den = den
			h.assign(den_doorstep(den, h.tile()), AgentC.ASSAULT)
		"bounty":
			var den := _best_bounty(h.tile())
			h.quest_den = den
			h.assign(den_doorstep(den, h.tile()), AgentC.ASSAULT)
		"treasure":
			h.assign(_nearest_pile(h.tile()), AgentC.TREASURE)
		"protect":
			h.assign(_nearest_known_wild(h.tile()), AgentC.PROTECT)
		"hunt":
			h.assign(_nearest_known_warren(h.tile()), AgentC.HUNT)
		"pray":
			h.assign(_nearest_complete("shrine", h.tile()), AgentC.PRAY)
		"carouse":
			h.assign(_nearest_complete("tavern", h.tile()), AgentC.CAROUSE)
		"explore":
			h.assign(_explore_target(h.tile()), AgentC.EXPLORE)
		"assist":
			var site := _nearest_free_site(h.tile())
			h.assign(site if site.x >= 0 else _nearest_free_terrain(h.tile()),
				AgentC.ASSIST)
		_:
			h.assign(_wilds_spot(keep_pos, 5, h.tile()), AgentC.WANDER)

func hero_count() -> int:
	var n := 0
	for a in agents:
		if a.kind == "hero" and not _removals.has(a):
			n += 1
	return n

func hero_roster() -> Array:
	var roster := []
	for a in agents:
		if a.kind == "hero":
			roster.append(a)
	return roster

func dismiss_hero(h) -> bool:
	# Player-directed departure, using the same road out as an over-cap hero.
	if h == null or not agents.has(h) or h.kind != "hero" or _removals.has(h):
		return false
	var target := _leave_target(h.tile())
	h.fighting = false
	h.target_agent = null
	h.decision_left = 0
	if target.x < 0:
		hero_leave(h)
		return true
	h.goal = "leave"
	h.purpose = AgentC.LEAVE
	h.target = target
	h.state = AgentC.TO_TARGET
	h.path = find_path(h.tile(), target)
	if h.path.is_empty():
		hero_leave(h)
	else:
		last_event = "The %s is dismissed from the realm" \
			% HERO_CLASSES[h.hero_class].title
	return true

func hero_leave(h) -> void:
	# A hero who has had enough simply walks out; the realm keeps no leash.
	if _removals.has(h):
		return
	_removals.append(h)
	heroes_departed += 1
	last_event = "The %s leaves the realm" % HERO_CLASSES[h.hero_class].title

func _druid_depart(h) -> void:
	if _removals.has(h):
		return
	_removals.append(h)
	druids_departed += 1
	heroes_departed += 1
	last_event = "A druid turns away from the defiled realm"

func _hero_level_check(h) -> void:
	while h.xp >= HERO_XP_PER_LEVEL * h.level:
		h.xp -= HERO_XP_PER_LEVEL * h.level
		h.level += 1
		h.max_hp += 2
		h.hp = h.max_hp
		last_event = "%s rises to level %d" % [HERO_CLASSES[h.hero_class].title, h.level]

func _hero_gain_xp(h, n: int) -> void:
	h.xp += n
	_hero_level_check(h)

func hero_activity_xp(h, activity: String) -> int:
	# M7.2: a venture well done is its own lesson. The base award keeps
	# exploration, husbandry, hunting, gambling and honest work worth doing;
	# a class's core pursuit pays double, so heroes grow along the path their
	# personality already favors.
	var gained: int = int(HERO_ACTIVITY_XP.get(activity, 0))
	if gained <= 0:
		return 0
	if String(HERO_CORE_ACTIVITY.get(h.hero_class, "")) == activity:
		gained += 1
	_hero_gain_xp(h, gained)
	return gained

func hero_explore(h) -> void:
	# Arriving at an explore flag pays the hero who made the journey.
	if h.tile() == h.target and explore_bounties.has(h.target):
		var reward: int = int(explore_bounties[h.target].reward)
		explore_bounties.erase(h.target)
		h.pouch += reward
		explore_bounties_paid += reward
		last_event = "The %s charts the bounty ground and claims the purse!" \
			% HERO_CLASSES[h.hero_class].title
	hero_activity_xp(h, "explore")

func hero_buy_gear(h) -> void:
	# The forge's stock is real: a hero with coin and a free hand takes one
	# point of gear off the rack. The sale returns coin to the realm, and
	# every gear point makes the hero hit harder in melee.
	var p: Vector2i = h.target
	var b: Dictionary = buildings.get(p, {})
	if b.is_empty() or b.kind != "blacksmith" or not b.complete:
		return
	if int(b.get("gear", 0)) <= 0 or h.gear >= HERO_GEAR_MAX \
			or h.pouch < GEAR_COST:
		return
	b.gear = int(b.gear) - 1
	h.gear += 1
	h.pouch -= GEAR_COST
	gold += GEAR_COST
	gear_sales += GEAR_COST
	h.fatigue += 1
	last_event = "The %s buys forged gear" % HERO_CLASSES[h.hero_class].title

func hero_shop(h) -> void:
	# Heroes bank their plunder at the market; the realm profits from
	# the trade. Loot in the pockets is what makes heroes come at all.
	if h.pouch > 0:
		gold += h.pouch
		market_sales += h.pouch
		h.pouch = 0
		last_event = "The %s spends loot at the market" % HERO_CLASSES[h.hero_class].title
	h.fatigue += 1

func hero_rest(h) -> void:
	h.fatigue = 0
	h.hp = h.max_hp

func hero_pray(h) -> void:
	# Candlelight and quiet: prayer eases a weary hero, and mends a
	# little of what the wilds took.
	h.fatigue = maxi(0, h.fatigue - 2)
	h.hp = mini(h.hp + 1, h.max_hp)

func hero_carouse(h) -> void:
	# An evening of ale and dice: cheaper than rest, dearer than pride.
	# The coin spent ends up in the tavern's till for the collector. A
	# night at the tables is also a lesson in reading people — and luck.
	h.fatigue = maxi(0, h.fatigue - 1)
	h.hp = mini(h.hp + 1, h.max_hp)
	h.leisure_left = hero_leisure_cooldown
	var b: Dictionary = buildings.get(h.target, {})
	if b.get("kind", "") == "tavern" and b.get("complete", false):
		var row: Dictionary = BUILD_TAX["tavern"]
		b.tax = mini(int(b.tax) + 1, int(row.cap))
		hero_activity_xp(h, "carouse")

func hero_protect(h) -> void:
	# The druid walks to a wild lair and tends it: a little food in its
	# larder, a little breathing room for the land.
	var den: Dictionary = dens.get(h.target, {})
	if not den.is_empty() and not is_hostile_den(h.target):
		den.food = mini(int(den.food) + 1, PREY_FOOD_CAP)
		wilderness_tended += 1
		if rng.randi_range(0, 2) == 0:
			last_event = "A druid tends the wilds"
		hero_activity_xp(h, "protect")
	h.fatigue += 1
	h.leisure_left = hero_leisure_cooldown

func hero_hunt(h) -> void:
	# A spot of hunting: the warren's larder loses a hare or two, and the
	# hunter comes back a touch more seasoned. Thin the warrens too hard
	# and the wolves start eyeing the farms — the ecology keeps score.
	var den: Dictionary = dens.get(h.target, {})
	if not den.is_empty() and DEN_KINDS[den.get("kind", "")].role == "prey":
		den.food = maxi(0, int(den.food) - 2)
		hero_activity_xp(h, "hunt")
	h.fatigue += 1
	h.leisure_left = hero_leisure_cooldown

func hero_take_loot(h) -> void:
	if loot_piles.has(h.target):
		h.pouch += int(loot_piles[h.target])
		loot_piles.erase(h.target)
		hero_activity_xp(h, "treasure")
		last_event = "The %s pockets the dropped loot" % HERO_CLASSES[h.hero_class].title
	h.fatigue += 1

func hero_assist(h) -> void:
	# Occasional flavor: a fresh hero with nothing better to score lends a
	# hand at a construction site or a terrain worksite. Never required —
	# assist is the lowest personality weight. Honest work still teaches a
	# careful pair of hands something.
	var worked := false
	if buildings.has(h.target) and not buildings[h.target].complete:
		worked = tick_build(h.target)
	elif terrain_works.has(h.target):
		worked = tick_terrain(h.target)
	if worked or buildings.has(h.target) or terrain_works.has(h.target):
		hero_activity_xp(h, "assist")
	h.fatigue += 1

func hero_assault_tick(h) -> void:
	# Den damage flows from the combat step's siege accounting; here the
	# hero only notices the victory and moves on.
	if not dens.has(h.quest_den):
		h.state = AgentC.IDLE
		h.purpose = ""
		h.fatigue += 1
		last_event = "The %s's work at the den is done" % HERO_CLASSES[h.hero_class].title
		return
	h.work_left = 1

func _is_hostile_agent(a) -> bool:
	if a.kind == "goblin" or a.kind == "bandit" or a.kind == "rat":
		return true
	return a.kind == "undead" and a.undead_side == "hostile"

func _is_defender_agent(a) -> bool:
	if a.kind == "guard" or a.kind == "hero":
		return true
	return a.kind == "undead" and a.undead_side == "ally"

func adjacent_foes(a) -> int:
	# Foes that make a fighter hold ground: the realm's defenders hem the
	# wild's raiders in, and every hostile thing hems the defenders in.
	var n := 0
	var a_hostile := _is_hostile_agent(a)
	var a_defender := _is_defender_agent(a)
	if not a_hostile and not a_defender:
		return 0
	for other in agents:
		if other == a:
			continue
		if a_hostile and _is_defender_agent(other) \
				and other.adjacent_to(a.tile()):
			n += 1
		elif a_defender and _is_hostile_agent(other) \
				and other.adjacent_to(a.tile()):
			n += 1
	return n

func hero_accuracy(h) -> float:
	return minf(HERO_ACCURACY_MAX, HERO_BASE_ACCURACY \
		+ HERO_ACCURACY_PER_LEVEL * float(h.level - 1))

func hero_melee_damage(h) -> int:
	return HERO_BASE_DAMAGE + floori(float(h.level - 1) \
		/ float(HERO_DAMAGE_LEVEL_STEP)) + int(h.gear)

func guard_accuracy(g) -> float:
	return minf(GUARD_ACCURACY_MAX, GUARD_BASE_ACCURACY \
		+ GUARD_ACCURACY_PER_LEVEL * float(g.level - 1))

func guard_melee_damage(g) -> int:
	return GUARD_BASE_DAMAGE

func monster_accuracy(m) -> float:
	return minf(MONSTER_ACCURACY_MAX, MONSTER_BASE_ACCURACY \
		+ MONSTER_ACCURACY_PER_LEVEL * float(m.level - 1))

func monster_melee_damage(m) -> int:
	return MONSTER_BASE_DAMAGE

# Aliases for other fighter names.
func goblin_accuracy(m): return monster_accuracy(m)
func goblin_melee_damage(m): return monster_melee_damage(m)
func bandit_accuracy(m): return monster_accuracy(m)
func bandit_melee_damage(m): return monster_melee_damage(m)
func rat_accuracy(m): return monster_accuracy(m)
func rat_melee_damage(m): return monster_melee_damage(m)
func hostile_accuracy(m): return monster_accuracy(m)
func hostile_melee_damage(m): return monster_melee_damage(m)
func enemy_accuracy(m): return monster_accuracy(m)
func enemy_melee_damage(m): return monster_melee_damage(m)
func mob_accuracy(m): return monster_accuracy(m)
func mob_melee_damage(m): return monster_melee_damage(m)
func guard_acc(g): return guard_accuracy(g)
func monster_acc(m): return monster_accuracy(m)
func _combat_step() -> void:
	# Simple attrition: foes on neighbouring tiles trade blows. A fighter who
	# drops to the flee threshold breaks for home; anyone at 0 hp is reaped.
	# Heroes roll accuracy and hit for a flat, slowly level-scaled amount.
	var gobs := []
	var guards := []
	var heroes := []
	var bands := []
	var rats := []
	var allies := []
	var hostile_dead := []
	for a in agents:
		if a.kind == "goblin":
			gobs.append(a)
		elif a.kind == "bandit":
			bands.append(a)
		elif a.kind == "rat":
			rats.append(a)
		elif a.kind == "guard":
			guards.append(a)
		elif a.kind == "hero":
			heroes.append(a)
		elif a.kind == "undead":
			if a.undead_side == "ally":
				allies.append(a)
			else:
				hostile_dead.append(a)
	var hostiles: Array = gobs + bands + rats + hostile_dead
	var defenders: Array = guards + heroes + allies
	for foe in hostiles:
		var damage := 0
		var hitters := []
		var engaged := false
		for g in guards:
			if not g.adjacent_to(foe.tile()):
				continue
			engaged = true
			if rng.randf() < guard_accuracy(g):
				damage += guard_melee_damage(g)
		for h in heroes:
			if not h.adjacent_to(foe.tile()):
				continue
			engaged = true
			# Heroes can miss. Accuracy rises with level, while damage per
			# hit rises only every few levels; gear still adds a point.
			if rng.randf() < hero_accuracy(h):
				damage += hero_melee_damage(h)
				hitters.append(h)
		for u in allies:
			if u.adjacent_to(foe.tile()):
				engaged = true
				damage += 2
		if engaged and foe.state != AgentC.FLEEING:
			foe.fighting = true
			foe.behavior_left = 0
		if damage > 0:
			var wounded: bool = foe.hp > 0
			foe.hurt(damage)
			if wounded and foe.hp <= 0:
				# The kill is credited to the heroes who landed a blow.
				for h in hitters:
					_hero_gain_xp(h, 1)
	for d in defenders:
		var enemies := 0
		var adjacent := 0
		for foe in hostiles:
			if not foe.adjacent_to(d.tile()):
				continue
			adjacent += 1
			if rng.randf() < monster_accuracy(foe):
				enemies += 1
		if adjacent > 0 and (d.kind == "hero" or d.kind == "guard" \
				or d.kind == "undead"):
			d.fighting = true
		if enemies > 0:
			d.hurt(enemies)
	for p in dens.duplicate():
		var den: Dictionary = dens[p]
		# Hostile lairs are always siege targets; a bounty makes any other
		# lair fair game for the realm's armed folk.
		if not is_hostile_den(p) and not bounties.has(p):
			continue
		var besiegers := 0
		for g in guards:
			if g.adjacent_to(p) and rng.randf() < guard_accuracy(g):
				besiegers += guard_melee_damage(g)
		for h in heroes:
			if h.adjacent_to(p) and rng.randf() < hero_accuracy(h):
				besiegers += hero_melee_damage(h)
		for u in allies:
			if u.adjacent_to(p):
				besiegers += 2
		if besiegers > 0:
			den.hp -= besiegers
			if den.hp <= 0:
				_clear_den(p)

func _clear_den(p: Vector2i) -> void:
	var den: Dictionary = dens[p]
	var title: String = DEN_KINDS[den.get("kind", "goblin_den")].title
	var spoils: int = int(den.gold)
	dens.erase(p)
	dens_cleared += 1
	for a in agents:
		if (a.kind == "goblin" or a.kind == "bandit" or a.kind == "creature") \
				and a.home == p and not _removals.has(a):
			_removals.append(a)
	# The lair's plunder spills out where anyone quick can grab it.
	if spoils > 0:
		var door: Vector2i = den_doorstep(p, keep_pos)
		loot_piles[door] = int(loot_piles.get(door, 0)) + spoils
	var reward := 0
	if bounties.has(p):
		reward = int(bounties[p].reward)
		bounties.erase(p)
	_thaw_separated_feud()
	var claimant = null
	for a in agents:
		if a.kind == "hero" and a.adjacent_to(p):
			claimant = a
			break
	if claimant != null:
		_hero_gain_xp(claimant, 5)
		dens_cleared_by_heroes += 1
		if reward > 0:
			claimant.pouch += reward
			bounties_paid += reward
			last_event = "The %s clears the %s and claims the bounty!" \
				% [HERO_CLASSES[claimant.hero_class].title, title.to_lower()]
		else:
			last_event = "A %s storms the %s and prevails!" \
				% [HERO_CLASSES[claimant.hero_class].title, title.to_lower()]
	elif reward > 0:
		last_event = "The den fell to the watch; the bounty goes unclaimed"
	else:
		last_event = "The %s was cleared!" % title.to_lower()

func _reap() -> void:
	var guard_fell := false
	var fallen_hero_class := ""
	for a in agents:
		if a.hp <= 0 and (a.kind == "guard" or a.kind == "goblin" \
				or a.kind == "bandit" or a.kind == "hero" \
				or a.kind == "undead" or a.kind == "rat") \
				and not _removals.has(a):
			_removals.append(a)
			match a.kind:
				"guard":
					guards_fallen += 1
					guard_fell = true
					_record_corpse(a.tile())
				"goblin":
					_record_corpse(a.tile())
				"bandit":
					_record_corpse(a.tile())
					# A cut-down bandit spills what he lifted onto the road.
					if int(a.carrying) > 0:
						loot_piles[a.tile()] = int(loot_piles.get(a.tile(), 0)) \
							+ int(a.carrying)
						a.carrying = 0
				"hero":
					# A fallen hero drops their purse where anyone quick
					# — a rogue, say — can race to it.
					heroes_fallen += 1
					fallen_hero_class = a.hero_class
					_record_corpse(a.tile())
					if a.pouch > 0:
						loot_piles[a.tile()] = int(loot_piles.get(a.tile(), 0)) + a.pouch
				"undead":
					if a.undead_side == "ally":
						undead_lost += 1
					else:
						undead_destroyed += 1
				"rat":
					rats_destroyed += 1
	if guard_fell:
		last_event = "A guard fell in battle!"
	elif fallen_hero_class != "":
		last_event = "A %s has fallen in battle!" % HERO_CLASSES[fallen_hero_class].title
	for x in _removals:
		agents.erase(x)
	_removals.clear()

func _record_corpse(p: Vector2i) -> void:
	# The nearest graveyard within its reach takes the body. Corpses feed
	# either the necromancer's servants or the graveyard's unquiet risk.
	var best := Vector2i(-1, -1)
	var best_d := INF
	var reach_sq: int = graveyard_reach * graveyard_reach
	for q in buildings:
		var b: Dictionary = buildings[q]
		if not b.complete or b.kind != "graveyard":
			continue
		var d := Vector2(q).distance_squared_to(Vector2(p))
		if d > reach_sq or d >= best_d:
			continue
		best_d = d
		best = q
	if best.x < 0:
		return
	var grave: Dictionary = buildings[best]
	if int(grave.get("corpses", 0)) >= grave_corpse_cap:
		return
	grave.corpses = int(grave.get("corpses", 0)) + 1
	corpses_buried += 1

func _spawn_guard(guardhouse: Vector2i) -> void:
	var a = AgentC.new()
	a.setup(self, "guard", guardhouse)
	a.home = guardhouse
	agents.append(a)

func _spawn_goblin(den_pos: Vector2i) -> void:
	var a = AgentC.new()
	a.setup(self, "goblin", den_doorstep(den_pos, keep_pos))
	a.home = den_pos
	agents.append(a)
