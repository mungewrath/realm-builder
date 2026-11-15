extends SceneTree

func _initialize() -> void:
	var sim = load("res://scripts/kingdom.gd").new()
	var failed := false

	if sim.gold != 50 or sim.pop != 5:
		failed = true
		print("FAIL: bad starting state")

	sim.build_farm()
	sim.build_house()
	if sim.farms != 1 or sim.houses != 1 or sim.pop_cap != 8:
		failed = true
		print("FAIL: buildings not applied")

	sim.gold = 0
	sim.build_farm()
	if sim.farms != 1:
		failed = true
		print("FAIL: bought without gold")
	sim.gold = 50

	for i in 10:
		sim.update()
	if sim.tick != 10:
		failed = true
		print("FAIL: ticks wrong")
	if sim.pop < 1 or sim.food < 0 or sim.gold <= 0:
		failed = true
		print("FAIL: economy out of range: food=%d pop=%d gold=%d" % [sim.food, sim.pop, sim.gold])

	print("RESULT: %s (gold=%d food=%d pop=%d/%d farms=%d houses=%d)" % ["PASS" if not failed else "FAIL", sim.gold, sim.food, sim.pop, sim.pop_cap, sim.farms, sim.houses])
	quit(1 if failed else 0)
