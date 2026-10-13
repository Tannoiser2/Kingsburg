extends SceneTree
## Partite IA contro IA senza grafica:
## godot --headless -s res://tests/sim.gd -- <partite> <giocatori> <livello> <livello posto 0> <moduli>
## moduli: elenco separato da virgole fra lines,alt,alt_draft,gov,gov_auction,fate,troops,capricci,restaurazione (o "all")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 20
	var np := int(args[1]) if args.size() > 1 else 4
	var lvl := int(args[2]) if args.size() > 2 else 1
	var lvl0 := int(args[3]) if args.size() > 3 else lvl
	var mods := {}
	if args.size() > 4:
		var m := args[4]
		if m == "all":
			m = "lines,alt,gov,fate,troops,capricci"
		for k in m.split(","):
			if k != "":
				mods[k] = true
	var wins := {}
	var vps := []
	var t0 := Time.get_ticks_msec()
	for g in range(games):
		var eng := KBEngine.new()
		eng.headless = true
		root.add_child(eng)
		var seats := []
		for i in range(np):
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": lvl0 if i == 0 else lvl})
		eng.setup({"seats": seats, "seed": 1000 + g, "mods": mods})
		await eng.run()
		var r: Array = eng.results
		wins[r[0]["seat"]] = wins.get(r[0]["seat"], 0) + 1
		var line := []
		for e in r:
			var gv: String = eng.gov(e["seat"])
			line.append("%s%s %d" % [eng.pname(e["seat"]), ("(" + gv + ")") if gv != "" else "", e["vp"]])
			vps.append(e["vp"])
		print("partita %d (anni %d): %s" % [g, eng.year, ", ".join(line)])
		eng.queue_free()
	var avg := 0.0
	for v in vps:
		avg += v
	print("vittorie per posto: ", wins, "  PV medi: %.1f  tempo %d ms" % [avg / vps.size(), Time.get_ticks_msec() - t0])
	quit()
