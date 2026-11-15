extends RefCounted

# Flavor text for the tap-to-inspect panel. Mirrored from content-design.md
# rows; hints at mechanics, never states exact formulas.

const BUILDING_TITLES := {
	"castle": "The Keep",
	"farm": "Farm",
	"house": "House",
}

const BUILDING_BLURBS := {
	"castle": "The heart of the realm. Souls shelter within its walls, and the tax collector banks his rounds in its coffers.",
	"farm": "Golden rows of grain. Peasants walk out from the keep to work the soil and haul provisions home. Goblins are said to raid farms first.",
	"house": "A steep-roofed cottage. Each one raises the number of souls the keep can feed, and owes the crown a slow drip of taxes.",
}

const UNIT_ROLES := {
	"peasant": "Peasant",
	"collector": "Tax Collector",
}

static func building_title(kind: String) -> String:
	return BUILDING_TITLES.get(kind, "Ruins")

static func building_blurb(kind: String) -> String:
	return BUILDING_BLURBS.get(kind, "")

static func building_status(kind: String, p: Vector2i, b: Dictionary, sim) -> String:
	if not b.complete:
		return _site_status(b, sim)
	match kind:
		"house":
			return _purse(int(b.tax))
		"farm":
			return _farm_status(p, sim)
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

static func agent_line(a) -> String:
	return "%s — %s" % [UNIT_ROLES.get(a.kind, "Stranger"), agent_activity(a)]

static func agent_activity(a) -> String:
	if a.state == "fleeing":
		return "running from danger!"
	match a.kind:
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
