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

const DEN_TITLE := "Goblin Den"
const DEN_BLURB := "A ragged cave mouth in the mountainside. Warbands creep out of it to burn and plunder — but it can be stormed and cleared."

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
}

static func building_title(kind: String) -> String:
	return BUILDING_TITLES.get(kind, "Ruins")

static func building_blurb(kind: String) -> String:
	return BUILDING_BLURBS.get(kind, "")

static func den_title() -> String:
	return DEN_TITLE

static func den_blurb() -> String:
	return DEN_BLURB

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
	return UNIT_ROLES.get(a.kind, "Stranger")

static func den_status(den: Dictionary, p: Vector2i = Vector2i(-1, -1), sim = null) -> String:
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
			var s := _farm_status(p, sim)
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

static func agent_activity(a) -> String:
	if a.state == "fleeing":
		match a.kind:
			"goblin":
				return "slinking home to the den"
			"guard":
				return "retreating to dress wounds"
			"hero":
				return "falling back to lick wounds"
			_:
				return "running from danger!"
	match a.kind:
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
							return "storming the goblin den"
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
							return "storming the goblin den"
						_:
							return "walking the watch round"
				"acting":
					match a.purpose:
						"assault":
							return "hammering at the den's mouth"
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
