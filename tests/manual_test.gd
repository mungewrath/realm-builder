extends SceneTree

# The manual is the player-facing reference, so keep the Markdown present,
# complete enough to cover the major systems, and renderable in-game.

var failed := false

func _initialize() -> void:
	var ManualC = load("res://scripts/manual.gd")
	var md: String = ManualC.load_markdown()
	if md.length() < 2000:
		_fail("manual is suspiciously short")
	for section in [
		"Core Loop", "Gold, Food, and People", "Land, Fog, and Terrain",
		"Heroes and Indirect Control", "Hero Levels and Gear",
		"Hero Cap, Warnings, and Leaving", "Bounties", "Kobolds and Gnomes",
		"Graveyards and the Necromancer", "Sewers, Rats, and Plague",
		"Tribute", "Failure and Recovery",
	]:
		if not md.contains(section):
			_fail("manual missing section: " + section)
	var bb: String = ManualC.to_bbcode(md)
	if bb.length() < md.length() / 2:
		_fail("manual renderer dropped too much text")
	if not bb.contains("[b]"):
		_fail("manual renderer did not apply bold styling")
	if bb.contains("## ") or bb.contains("**"):
		_fail("manual renderer left Markdown syntax in the panel")
	print("RESULT: %s" % ["PASS" if not failed else "FAIL"])
	quit(1 if failed else 0)

func _fail(msg: String) -> void:
	failed = true
	print("FAIL: " + msg)
