extends RefCounted

# Flavor text for the tap-to-inspect panel. Mirrored from content-design.md
# rows; hints at mechanics, never states exact formulas.

const BUILDING_TITLES := {
	"castle": "The Keep",
	"farm": "Farm",
	"house": "House",
	"guardhouse": "Guardhouse",
	"tavern": "Tavern",
	"market": "Market",
	"shrine": "Shrine",
	"blacksmith": "Blacksmith",
	"wizard_tower": "Wizard Tower",
	"ranger_hut": "Ranger Hut",
	"mead_hall": "Mead Hall",
	"herbalist_grove": "Herbalist Grove",
	"graveyard": "Graveyard",
	"sewers": "Sewers",
}

const BUILDING_BLURBS := {
	"castle": "The heart of the realm. Souls shelter within its walls, and the tax collector banks his rounds in its coffers.",
	"farm": "Golden rows of grain. Peasants walk out from the keep to work the soil and haul provisions home. Goblins are said to raid farms first.",
	"house": "A steep-roofed cottage. Each one raises the number of souls the keep can feed, and owes the crown a slow drip of taxes.",
	"guardhouse": "A squat stone watch-tower. It raises a small company of guards who patrol the nearby fields and drive off raiders.",
	"tavern": "A smoky hall of cheap ale and tall tales. Adventurers drift toward it — rogues especially — and rest here between ventures.",
	"market": "Stalls and scales. Heroes spend their plunder here, and the realm profits from every trade.",
	"shrine": "Quiet candles and old blessings. The righteous are drawn to it, and evil lairs draw their wrath.",
	"blacksmith": "Hammer and anvil, sparks and steam. The forge turns out gear for the realm's fighters, and dwarves and warriors both answer its ring.",
	"wizard_tower": "A crooked spire humming with old power. Mana gathers at its peak, and a wizard's far sight slowly charts the wilds.",
	"ranger_hut": "A low cabin at the treeline. Rangers range out from it, charting the wilds and keeping hungry beasts away from the settled fields.",
	"mead_hall": "A longhouse thick with the smell of ale and roasted meat. Barbarians gather here, and strong drink makes bold hands reach for bounty flags.",
	"herbalist_grove": "Neat rows of herbs and a quiet green hut. Druids and healers tend the grove; its herbs ease wounds and can lift a hag's curse.",
	"graveyard": "Crooked stones under a cold sky. The dead are laid here — and a necromancer is drawn to the stored corpses. The burial ground eases plague pressure; a shrine's ward keeps the unquiet down.",
	"sewers": "A grated stone mouth breathing damp air. The drains keep fever out of the crowded houses, but rats follow the filth up into the larder. Rogues find the tunnels a convenient den.",
}

const LOOT_TITLE := "Dropped Loot"
const LOOT_BLURB := "A purse left where someone fell. Quick hands and greedy hearts both know what to do with it."

const EXPLORE_BOUNTY_TITLE := "Uncharted Ground"
const EXPLORE_BOUNTY_BLURB := "Blank country beyond the realm's maps. A posted bounty turns a patch of that darkness into a destination for a bold hero."

# M6.1: dens are content rows now — one title/blurb per kind. Goblin dens
# stay the realm's enemy; wild lairs are the land's own folk.
const DEN_INFO := {
	"goblin_den": {
		"title": "Goblin Den",
		"blurb": "A ragged cave mouth in the mountainside. Warbands creep out of it to burn and plunder — but it can be stormed and cleared.",
	},
	"rabbit_warren": {
		"title": "Rabbit Warren",
		"blurb": "A sandy mound of burrows. The rabbits graze the meadows and multiply — and everything hungry in the wilds knows it.",
	},
	"wolf_den": {
		"title": "Wolf Den",
		"blurb": "A dark hollow under the roots. The pack hunts where the rabbits are — and if the warrens ever run dry, the farms will do.",
	},
	"spider_den": {
		"title": "Giant Spider Nest",
		"blurb": "A cave mouth veiled in web. The great spider snares goblins for supper; some folk quietly cheer for it.",
	},
	"kobold_den": {
		"title": "Kobold Burrow",
		"blurb": "A yapping burrow in the hills. Kobolds filch chickens and trinkets — and they have hated the gnomes for longer than anyone remembers.",
	},
	"gnome_enclave": {
		"title": "Gnome Enclave",
		"blurb": "A warren of workshops under a hill shoulder. Gnome tinkers trade clever little things for coin — when the hills are peaceful enough to trade at all.",
	},
	"bandit_camp": {
		"title": "Bandit Camp",
		"blurb": "A ring of tents and a cookfire by the road. Rough men muster here and rob fat purses; storm it and the road grows quieter.",
	},
	"hag_coven": {
		"title": "Hag Coven",
		"blurb": "A crooked hut in the deep woods, hung with bones and drying herbs. The hags do not raid — they curse the fields and laugh.",
	},
	"frog_den": {
		"title": "Frog Pond",
		"blurb": "A ringing, reedy pond in the marsh. The great frogs are the bottom of the food chain — and the first thing to vanish when the water is drained.",
	},
	"owlbear_den": {
		"title": "Owlbear Den",
		"blurb": "A trampled hollow under the trees. The owlbear hunts the frogs of the marsh; when the frogs are gone, its hungry eyes turn toward the farms.",
	},
}

# M6.3: terrain the player can work.
const TERRAIN_TITLES := {
	0: "Open Ground",
	1: "Deep Woods",
	2: "Water",
	3: "Mountain",
	4: "Marshland",
}

const TERRAIN_BLURBS := {
	0: "Grass and bare earth, fit for building.",
	1: "Old woods, thick with game and shade. Cleared, the timber makes way for farmland.",
	2: "Still water. Nothing is built on it, and few things walk through it.",
	3: "Broken stone and sheer slopes. Warbands creep down from these heights.",
	4: "Reed and black water. Frogs breed here and wild things shelter; drained, it makes rich soil.",
}

const HERO_TITLES := {
	"rogue": "Rogue",
	"warrior": "Warrior",
	"paladin": "Paladin",
	"druid": "Druid",
	"dwarf": "Dwarf Craftsman",
	"wizard": "Wizard",
	"ranger": "Ranger",
	"barbarian": "Barbarian",
	"necromancer": "Necromancer",
}

const HERO_BLURBS := {
	"rogue": "A knife-for-hire who loves gold more than glory. Chases treasure flags and bounties, and keeps a share for himself.",
	"warrior": "A sellsword who honors the flag. Bold in a fight, fond of ale, loyal to whoever posts a bounty.",
	"paladin": "A holy warrior who smites evil and scorns loot. Fearless before dens; gentle with fresh construction.",
	"druid": "A keeper of the wild places. Tends the lairs of the land's own creatures — and takes a dim view of drained marshes and felled woods.",
	"dwarf": "A stubborn smith with a good hammer and a better head for stone. Lends a hand at building and forges gear for those who fight.",
	"wizard": "A scholar of fire and sigils. The tower's mana draws them, and they smite evil in ways that leave the grass smoking.",
	"ranger": "A silent woodsman. Charts the wilds for the realm, hunts game, and keeps the beasts from the farms.",
	"barbarian": "A roaring fighter from the far hills. Mead and a posted bounty are all the orders a barbarian needs.",
	"necromancer": "A grave-robed scholar of the boundary between life and death. The graveyard draws them, and stored corpses rise as temporary servants whose loyalty slowly rots away.",
}

const UNIT_ROLES := {
	"peasant": "Peasant",
	"collector": "Tax Collector",
	"guard": "Guard",
	"goblin": "Goblin",
	"rabbit": "Rabbit",
	"wolf": "Grey Wolf",
	"spider": "Giant Spider",
	"bandit": "Bandit",
	"frog": "Giant Frog",
	"owlbear": "Owlbear",
	"rat": "Giant Rat",
	"undead": "Restless Dead",
	"skeleton": "Skeleton",
	"ghoul": "Ghoul",
}

static func building_title(kind: String) -> String:
	return BUILDING_TITLES.get(kind, "Ruins")

static func building_blurb(kind: String) -> String:
	return BUILDING_BLURBS.get(kind, "")

static func den_title(kind: String = "goblin_den") -> String:
	return DEN_INFO.get(kind, DEN_INFO["goblin_den"]).title

static func den_blurb(kind: String = "goblin_den") -> String:
	return DEN_INFO.get(kind, DEN_INFO["goblin_den"]).blurb

static func terrain_title(t: int) -> String:
	return TERRAIN_TITLES.get(t, "Ground")

static func terrain_blurb(t: int) -> String:
	return TERRAIN_BLURBS.get(t, "")

static func terrain_status(t: int, sim, p := Vector2i(-1, -1)) -> String:
	# Only the workable terrains reach the inspector; say what a tap does,
	# or how far the ordered work has got.
	if sim != null and p.x >= 0 and sim.terrain_works.has(p):
		var w: Dictionary = sim.terrain_works[p]
		var verb: String = "draining the marsh" if w.kind == "drain" \
			else "clearing the woods"
		return "Peasants are %s (%d/%d work)." % [
			verb, int(w.progress), sim.TERRAIN_WORK_TICKS]
	if t == 4 and sim != null:
		return "Marsh water lies over rich soil. Draining it opens farmland at the cost of the wilds (%dg); the work takes peasant labour." % sim.drain_cost
	if t == 1 and sim != null:
		return "Old-growth timber. Clearing the woods opens the ground for building (%dg); the work takes peasant labour — and the druids will notice." % sim.clear_cost
	return ""

static func loot_title() -> String:
	return LOOT_TITLE

static func loot_blurb() -> String:
	return LOOT_BLURB

static func loot_status(gold: int) -> String:
	return "%d gold lie in the dirt, waiting for quick hands." % gold

static func explore_bounty_title() -> String:
	return EXPLORE_BOUNTY_TITLE

static func explore_bounty_blurb() -> String:
	return EXPLORE_BOUNTY_BLURB

static func explore_bounty_status(reward: int, sim) -> String:
	if reward > 0:
		return "%d gold waits for the hero who reaches this spot and charts it." \
			% reward
	if sim == null:
		return "Post a bounty to call a hero here."
	return "No one has charted this ground. Post a bounty (%dg) to send a hero into it." \
		% sim.BOUNTY_FEE

static func hero_title(a) -> String:
	var s := "%s · level %d" % [HERO_TITLES.get(a.hero_class, "Adventurer"), a.level]
	if int(a.gear) > 0:
		s += " · gear %d" % int(a.gear)
	return s

static func hero_blurb(a) -> String:
	return HERO_BLURBS.get(a.hero_class, "An adventurer of uncertain stripe.")

static func unit_title(a) -> String:
	if a.kind == "hero":
		return hero_title(a)
	# Wild creatures and raised dead are named by species when set.
	var role: String = a.species if (a.kind == "creature" or a.kind == "undead") \
		else a.kind
	return UNIT_ROLES.get(role, "Stranger")

static func den_status(den: Dictionary, p: Vector2i = Vector2i(-1, -1), sim = null) -> String:
	# Wild lairs speak of their larder; goblin dens of their next move.
	var kind: String = den.get("kind", "goblin_den")
	if kind != "goblin_den":
		match kind:
			"kobold_den":
				var s := "A yapping, cluttered burrow; the kobolds hoard whatever they can lift."
				if sim != null and sim.tension_between("kobolds", "gnomes") <= -2:
					s += " The feud with the gnomes is at a boil."
				return s
			"gnome_enclave":
				var s := "Little workshops steam and clank; tinker goods wait on the trade."
				if sim != null:
					if sim.tribute_active(p):
						s += " The tribute has bought a truce with the kobolds."
					elif sim.tension_between("gnomes", "kobolds") <= -2:
						s = "The gates are barred: the kobold feud has choked off trade."
					elif int(den.get("gold", 0)) > 0:
						s += " Their coffers hold %d gold." % int(den.get("gold", 0))
				return s
			"bandit_camp":
				var s := "Cookfires and dice. %d gold sits in the strongbox, not all of it honestly come by." \
					% int(den.get("gold", 0))
				if sim != null and sim.tribute_active(p):
					s += " Tribute has bought their silence for now."
				return s
			"hag_coven":
				return "Bones and drying herbs. The hags mutter over their curses and pay no heed to soldiers."
			"frog_den":
				if sim != null and p.x >= 0 \
						and not sim._habitat_ok(p, sim.DEN_KINDS["frog_den"].habitat):
					return "The marsh has been drained; the pond shrinks and the frogs are dying off."
				return "Reeds, lilies, and a chorus of frogs. The bottom of the marsh's food chain is thriving."
			"owlbear_den":
				if sim != null and p.x >= 0 \
						and not sim._habitat_ok(p, sim.DEN_KINDS["owlbear_den"].habitat):
					return "The woods are gone. With no frogs left to hunt, the owlbear's hunger turns toward the farms."
				return "Bones and feathers litter the hollow. The owlbear is abroad, and the marsh's frogs keep it fed."
		var status := ""
		if int(den.get("food", 0)) <= 0:
			status = "The larder is empty; the den grows desperate."
		elif int(den.get("food", 0)) < 3:
			status = "Lean pickings of late; hungry eyes scan the horizon."
		else:
			status = "The den is well fed and the wilds are quiet."
		return status
	# The den's current mood colors what a visitor would see.
	var s := ""
	match den.get("intent", ""):
		"muster":
			s = "Calling its warband home; trouble is brewing."
		"prowl":
			s = "Scouts prowl the fields, looking for fat targets."
		"forage":
			s = "Foragers range the wilds, hauling provisions home."
		"rest":
			s = "Licking wounds and counting loot after a raid."
		_:
			match clampi(int(den.get("level", 1)), 1, 3):
				1:
					s = "Scarcely more than a camp — but its warbands are hungry."
				2:
					s = "A busy warren; the raids grow frequent and bold."
				_:
					s = "A thriving warren of loot and fire. Cleared, it would be a boon."
	if sim != null and p.x >= 0 and sim.bounties.has(p):
		s += " A bounty of %d gold flies over it." % int(sim.bounties[p].reward)
	return s

static func building_status(kind: String, p: Vector2i, b: Dictionary, sim) -> String:
	if not b.complete:
		return _site_status(b, sim)
	match kind:
		"house":
			return _purse(int(b.tax))
		"farm":
			var s := ""
			if sim != null and sim.is_cursed(p):
				s = "A hag's curse lies on these fields: the crops wither and no farmer will work them. "
			s += _farm_status(p, sim)
			if int(b.tax) > 0:
				s += " The tithe purse holds a few coins, waiting on the collector."
			return s
		"guardhouse":
			return _guardhouse_status(p, sim)
		"tavern":
			var s := "The fire is warm and the ale is cheap; adventurers trade rumors of gold and glory."
			if int(b.tax) > 0:
				s += " The till is growing heavy."
			return s
		"market":
			var s := "Traders report brisk business; heroes pawn their plunder here."
			if int(b.tax) > 0:
				s += " The toll box is filling."
			return s
		"shrine":
			return "Candles burn for the realm's protectors."
		"blacksmith":
			var stock := int(b.get("gear", 0))
			if stock <= 0:
				return "The forge is hot and the anvil rings; fresh gear is on the way."
			if stock < sim.GEAR_STOCK_CAP:
				return "Weapons and mail crowd the racks; %d gear points wait for a buyer." % stock
			return "The racks are full to groaning with finished gear."
		"wizard_tower":
			var mana := int(b.get("mana", 0))
			if mana <= 0:
				return "The spire hums softly as mana gathers at its peak."
			return "The tower's stones pulse with gathered mana and old watchfulness."
		"ranger_hut":
			return "Rangers come and go by hidden trails, charting the wilds and watching the treeline."
		"mead_hall":
			var morale := int(b.get("morale", 0))
			if morale <= 0:
				return "The longhouse waits for its first cask to settle."
			if morale < sim.MEAD_STOCK_CAP:
				return "Ale flows and boasts grow louder; the hall's spirit is high."
			return "The mead hall roars with song and good cheer."
		"herbalist_grove":
			var herbs := int(b.get("herbs", 0))
			if herbs <= 0:
				return "Green shoots rise in the herb beds, not yet ready for the harvest."
			return "Bundles of healing herbs hang drying beneath the eaves."
		"graveyard":
			var stored := int(b.get("corpses", 0))
			var s := ""
			if sim != null:
				s = "Burial relief: +%d safe population. " \
					% int(sim.plague_graveyard_capacity)
			if stored <= 0:
				s += "The graves are quiet, for now."
			else:
				s += "Stored corpses: %d. " % stored
				if sim != null and sim._shrine_ward_at(p):
					s += "A shrine's ward keeps the unquiet in their graves."
				elif sim != null and sim._has_necromancer():
					s += "A necromancer stalks the rows, waking servants from the dead."
				else:
					s += "No one is watching the graves, and the unquiet are stirring."
			return s
		"sewers":
			var s := "The drains carry the filth away; crowded houses breathe easier for it."
			if sim != null:
				var rats: int = int(sim._count_agents_home(p, "rat"))
				if rats > 0:
					s += " Rats have found their way up from below."
				if int(b.get("rat_left", 0)) <= sim.sewer_rat_ticks / 3:
					s += " Something is moving in the dark."
			return s
		"castle":
			return "The realm numbers %d souls, and the ledger grows with every collector's round." % sim.pop
	return ""

static func _site_status(b: Dictionary, sim) -> String:
	var progress: int = int(b.get("progress", 0))
	var half: int = maxi(1, sim.BUILD_WORK_TICKS / 2)
	if progress < half:
		return "Scaffolding and a hopeful flag — the frame is just begun."
	return "Half-raised; hammers ring out across the fields."

static func _purse(tax: int) -> String:
	if tax <= 0:
		return "The hearth holds an empty purse."
	if tax <= 5:
		return "The hearth holds a few coins."
	if tax <= 10:
		return "The hearth holds a modest purse, waiting on the collector."
	return "The purse is brimming, begging for the collector's visit."

static func _farm_status(p: Vector2i, sim) -> String:
	var workers := 0
	var hauling := false
	for a in sim.agents:
		if a.purpose == "farm" and a.target == p and a.state != "idle":
			workers += 1
			if a.carrying > 0:
				hauling = true
	var s := ""
	match workers:
		0:
			s = "The rows stand ready, awaiting hands."
		1:
			s = "A pair of hands works the rows."
		_:
			s = "Many hands work the rows."
	if hauling:
		s += " Grain is bound for the keep."
	return s

static func _guardhouse_status(p: Vector2i, sim) -> String:
	var on_watch := 0
	var out := 0
	for a in sim.agents:
		if a.kind == "guard" and a.home == p:
			if a.state == "idle" or a.state == "fleeing":
				on_watch += 1
			else:
				out += 1
	if out > 0 and on_watch > 0:
		return "Part of the watch is out beating the bounds."
	if out > 0:
		return "The watch is out driving off raiders."
	return "Guards drill in the yard, spears ready."

static func _creature_activity(a) -> String:
	# The wilds' folk: what a beast of this species is up to.
	if a.carrying > 0:
		match a.species:
			"rabbit":
				return "hauling browse back to the warren"
			"wolf":
				return "hauling the kill back to the den"
			"owlbear":
				return "dragging a heavy kill to its hollow"
			"frog":
				return "carrying a mouthful back to the pond"
			_:
				return "dragging supper back to the nest"
	match a.state:
		"idle":
			if a.adjacent_to(a.home):
				match a.species:
					"rabbit":
						return "dozing at the warren"
					"wolf":
						return "curled up at the den"
					"owlbear":
						return "dozing in its trampled hollow"
					"frog":
						return "sitting half-submerged at the pond"
					_:
						return "coiled in the nest"
			match a.behavior:
				"wander":
					return "rambling through the wilds"
				_:
					return "loitering in the wilds"
		"to_target":
			match a.purpose:
				"forage":
					match a.species:
						"rabbit":
							return "hopping out to graze"
						"frog":
							return "croaking out toward the reeds"
						_:
							return "rooting about for food"
				"hunt":
					return "stalking its prey"
				_:
					return "rambling through the wilds"
		"acting":
			match a.purpose:
				"forage":
					return "grazing"
				"hunt":
					return "at the prey's doorstep"
				_:
					return "about its business"
		"returning":
			return "padding back to the den"
	return "about its business"

static func agent_line(a) -> String:
	var role: String = unit_title(a)
	return "%s — %s" % [role, agent_activity(a)]

static func _hero_home_name(a) -> String:
	# The hero's recruiting hall, if the sim told us; otherwise the keep.
	var kind := ""
	if "kingdom" in a and a.kingdom != null and a.kingdom.buildings.has(a.home):
		kind = a.kingdom.buildings[a.home].kind
	match kind:
		"tavern":
			return "tavern"
		"guardhouse":
			return "guardhouse"
		"shrine":
			return "shrine"
		"blacksmith":
			return "forge"
		"wizard_tower":
			return "wizard tower"
		"ranger_hut":
			return "ranger hut"
		"mead_hall":
			return "mead hall"
		"herbalist_grove":
			return "herbalist grove"
		"graveyard":
			return "graveyard"
		"sewers":
			return "sewers"
		_:
			return "keep"

static func _den_label(a) -> String:
	# Name the lair the agent is actually assaulting (wild lairs included),
	# falling back to the doorstep/target tile when the den has moved on.
	var k = a.kingdom
	if k == null:
		return "den"
	var p: Vector2i = a.quest_den
	var found: bool = p != Vector2i.ZERO and k.dens.has(p)
	if not found and k.dens.has(a.target):
		p = a.target
		found = true
	if not found:
		for d in k.dens:
			if a.adjacent_to(d):
				p = d
				found = true
				break
	if not found:
		return "den"
	var kind: String = k.dens[p].get("kind", "goblin_den")
	if not k.DEN_KINDS.has(kind):
		return "den"
	return String(k.DEN_KINDS[kind].title).to_lower()

static func agent_activity(a) -> String:
	if a.state == "fleeing":
		match a.kind:
			"goblin":
				return "slinking home to the den"
			"bandit":
				return "running back to camp!"
			"guard":
				return "retreating to dress wounds"
			"hero":
				return "falling back to lick wounds"
			_:
				return "running from danger!"
	match a.kind:
		"creature":
			return _creature_activity(a)
		"hero":
			if a.fighting:
				return "fighting for their life!"
			match a.state:
				"idle":
					if a.adjacent_to(a.home):
						return "mulling plans at the %s" % _hero_home_name(a)
					return "weighing their next venture"
				"to_target":
					match a.purpose:
						"assault":
							if a.goal == "bounty":
								return "riding out on the bounty"
							return "riding out to smite evil"
						"shop":
							return "walking to market with heavy pockets"
						"gear":
							return "off to the forge with a heavy purse"
						"leave":
							return "bound for the edge of the realm"
						"rest":
							return "seeking a bed and a hot meal"
						"treasure":
							return "racing to dropped loot"
						"assist":
							return "off to lend a hand"
						"explore":
							return "venturing into the unknown"
						"protect":
							return "walking out to tend the wilds"
						"hunt":
							return "off after game in the wilds"
						"pray":
							return "walking to the shrine"
						"carouse":
							return "heading for the tavern"
						_:
							return "strolling the realm"
				"acting":
					match a.purpose:
						"rest":
							return "resting and recovering"
						"shop":
							return "spending loot at the market"
						"gear":
							return "haggling over a new blade"
						"treasure":
							return "gathering dropped coins"
						"assist":
							return "hammering alongside the builders"
						"assault":
							return "storming the %s" % _den_label(a)
						"pray":
							return "kneeling in quiet prayer"
						"carouse":
							return "drinking and dicing the night away"
						"protect":
							return "tending the land and its creatures"
						"hunt":
							return "hunting game in the brush"
						_:
							return "about their business"
		"collector":
			match a.state:
				"idle":
					return "waiting at the keep for his round"
				"to_target":
					return "walking his collection round"
				"acting":
					return "counting coins at a door"
				"returning":
					return "hauling the day's taxes home"
		"goblin":
			if a.fighting:
				return "defending itself!"
			if a.carrying > 0:
				if a.loot_kind == "food":
					return "hauling provisions back to the den"
				return "hauling plunder back to the den"
			match a.state:
				"idle":
					if a.adjacent_to(a.home):
						return "loitering at the den"
					match a.behavior:
						"wander":
							return "lingering on a ramble"
						"prowl":
							return "eyeing the settlement from afar"
						_:
							return "loitering in the wilds"
				"to_target":
					match a.purpose:
						"wander":
							return "rambling through the wilds"
						"prowl":
							return "skulking toward the settlement"
						"forage":
							return "out foraging for the den"
						_:
							return "marching off to raid!"
				"acting":
					if a.purpose == "forage":
						return "rooting for grubs"
					return "putting a building to the torch"
				"returning":
					return "slinking home to the den"
		"undead":
			if a.fighting:
				return "fighting with the living!"
			if a.undead_side == "ally":
				match a.state:
					"idle":
						return "waiting for its master's will"
					"to_target":
						if a.purpose == "assault":
							return "marching on the %s" % _den_label(a)
						return "stalking the realm's enemies"
					"acting":
						if a.purpose == "assault":
							return "hammering at the %s's door" % _den_label(a)
						return "clawing at the living"
					"returning":
						return "drifting back to its grave"
				return "serving its master"
			match a.state:
				"idle":
					return "stirring in the grave dirt"
				"to_target":
					return "drawn toward the living"
				"acting":
					if a.purpose == "raid":
						return "clawing at the settlement"
					return "reaching for the living"
				"returning":
					return "sinking back toward the graves"
			return "restless and hungry"
		"rat":
			if a.fighting:
				return "squealing and biting!"
			match a.state:
				"idle":
					return "scurrying through the drains"
				"to_target":
					return "slipping toward the larder"
				"acting":
					return "gnawing at the stores"
				"returning":
					return "darting back into the sewers"
		"bandit":
			if a.fighting:
				return "brawling with the watch!"
			if a.carrying > 0:
				return "making off with a lifted purse"
			match a.state:
				"idle":
					if a.adjacent_to(a.home):
						return "dicing by the campfire"
					match a.behavior:
						"wander":
							return "loitering by the road"
						_:
							return "skulking near camp"
				"to_target":
					if a.purpose == "mug":
						return "shadowing a fat purse"
					return "prowling the road"
				"acting":
					if a.purpose == "mug":
						return "lifting a purse!"
					return "watching the road"
				"returning":
					return "slipping back to camp with the take"
		"guard":
			match a.state:
				"idle":
					if a.adjacent_to(a.home):
						return "waiting at the guardhouse"
					match a.behavior:
						"patrol":
							return "pausing on the watch round"
						_:
							return "standing easy"
				"to_target":
					match a.purpose:
						"intercept":
							return "rushing to drive off raiders"
						"assault":
							return "storming the %s" % _den_label(a)
						_:
							return "walking the watch round"
				"acting":
					match a.purpose:
						"assault":
							return "hammering at the %s's door" % _den_label(a)
						_:
							return "scanning the horizon"
				"returning":
					return "walking the watch round"
		"peasant":
			if a.carrying > 0:
				return "hauling grain home"
			match a.state:
				"idle":
					return "loitering by the keep"
				"to_target":
					match a.purpose:
						"farm":
							return "walking to the fields"
						"build":
							return "off to raise a building"
				"acting":
					match a.purpose:
						"farm":
							return "working the rows"
						"build":
							return "hammering at the site"
				"returning":
					return "walking home"
	return "about their business"
