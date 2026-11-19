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
}

const BUILDING_BLURBS := {
	"castle": "The heart of the realm. Souls shelter within its walls, and the tax collector banks his rounds in its coffers.",
	"farm": "Golden rows of grain. Peasants walk out from the keep to work the soil and haul provisions home. Goblins are said to raid farms first.",
	"house": "A steep-roofed cottage. Each one raises the number of souls the keep can feed, and owes the crown a slow drip of taxes.",
	"guardhouse": "A squat stone watch-tower. It raises a small company of guards who patrol the nearby fields and drive off raiders.",
	"tavern": "A smoky hall of cheap ale and tall tales. Adventurers drift toward it — rogues especially — and rest here between ventures.",
	"market": "Stalls and scales. Heroes spend their plunder here, and the realm profits from every trade.",
	"shrine": "Quiet candles and old blessings. The righteous are drawn to it, and evil lairs draw their wrath.",
}

const LOOT_TITLE := "Dropped Loot"
const LOOT_BLURB := "A purse left where someone fell. Quick hands and greedy hearts both know what to do with it."

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
}

const HERO_TITLES := {
	"rogue": "Rogue",
	"warrior": "Warrior",
	"paladin": "Paladin",
}

const HERO_BLURBS := {
	"rogue": "A knife-for-hire who loves gold more than glory. Chases treasure flags and bounties, and keeps a share for himself.",
	"warrior": "A sellsword who honors the flag. Bold in a fight, fond of ale, loyal to whoever posts a bounty.",
	"paladin": "A holy warrior who smites evil and scorns loot. Fearless before dens; gentle with fresh construction.",
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
}

static func building_title(kind: String) -> String:
	return BUILDING_TITLES.get(kind, "Ruins")

static func building_blurb(kind: String) -> String:
	return BUILDING_BLURBS.get(kind, "")

static func den_title(kind: String = "goblin_den") -> String:
	return DEN_INFO.get(kind, DEN_INFO["goblin_den"]).title

static func den_blurb(kind: String = "goblin_den") -> String:
	return DEN_INFO.get(kind, DEN_INFO["goblin_den"]).blurb

static func loot_title() -> String:
	return LOOT_TITLE

static func loot_blurb() -> String:
	return LOOT_BLURB

static func loot_status(gold: int) -> String:
	return "%d gold lie in the dirt, waiting for quick hands." % gold

static func hero_title(a) -> String:
	return "%s · level %d" % [HERO_TITLES.get(a.hero_class, "Adventurer"), a.level]

static func hero_blurb(a) -> String:
	return HERO_BLURBS.get(a.hero_class, "An adventurer of uncertain stripe.")

static func unit_title(a) -> String:
	if a.kind == "hero":
		return hero_title(a)
	# Wild creatures are named by species, not by their agent kind.
	var role: String = a.species if a.kind == "creature" else a.kind
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
					if sim.tension_between("gnomes", "kobolds") <= -2:
						s = "The gates are barred: the kobold feud has choked off trade."
					elif int(den.get("gold", 0)) > 0:
						s += " Their coffers hold %d gold." % int(den.get("gold", 0))
				return s
			"bandit_camp":
				return "Cookfires and dice. %d gold sits in the strongbox, not all of it honestly come by." \
					% int(den.get("gold", 0))
			"hag_coven":
				return "Bones and drying herbs. The hags mutter over their curses and pay no heed to soldiers."
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
						"rest":
							return "seeking a bed and a hot meal"
						"treasure":
							return "racing to dropped loot"
						"assist":
							return "off to lend a hand"
						"explore":
							return "venturing into the unknown"
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
