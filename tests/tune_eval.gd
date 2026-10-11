extends SceneTree
## Valuta un insieme di pesi per l'IA (posto 0) contro l'IA Normale: stampa vittorie e scarto medio di PV.
## KB_W='{"deficit":0.9,...}' godot --headless -s res://tests/tune_eval.gd -- <partite> <seme iniziale>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 60
	var s0 := int(args[1]) if args.size() > 1 else 5000
	var over = JSON.parse_string(OS.get_environment("KB_W")) if OS.get_environment("KB_W") != "" else {}
	var wins := 0.0
	var diff := 0.0
	for g in range(games):
		var np := 3 + g % 3   # 3, 4, 5 giocatori
		if g % 6 == 5:
			np = 2
		var eng := KBEngine.new()
		eng.headless = true
		root.add_child(eng)
		var seats := []
		for i in range(np):
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": 1})
		var seat0 := g % np
		eng.setup({"seats": seats, "seed": s0 + g})
		eng.ais[seat0].set_weights(over)
		await eng.run()
		var best := 0
		var others := 0.0
		for p in eng.players:
			if p["seat"] != seat0:
				others += p["vp"]
		for r in eng.results:
			if r["seat"] == seat0 and r["place"] == 1:
				wins += 1.0
		diff += eng.players[seat0]["vp"] - others / (np - 1)
		eng.queue_free()
	print("RESULT %.4f %.4f" % [diff / games, wins / games])
	quit()
