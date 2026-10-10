extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## godot --path . -s res://tests/shot.gd -- <modo>

var main
var n := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


## Risponde a una decisione con l'IA (come farebbe un giocatore).
func auto_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	var ai := KBAI.new()
	var r = ai.decide(g.engine, int(req["seat"]), req)
	g._provide(r)


func _run() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "game"
	await wait(5)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("rules")
		quit()
		return
	var np := 4
	var seats := []
	for i in range(np):
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Giallo", "Blu", "Nero", "Verde"][i], "level": 1})
	main.start_game({"seats": seats, "seed": 42, "ai_delay": 0.0})
	await wait(10)
	var shots_taken := {}
	var guard := 0
	while guard < 4000:
		guard += 1
		await wait(2)
		var g = gv()
		if g.engine.game_over:
			await wait(5)
			await shot("fine")
			break
		var req: Dictionary = g.pending
		if req.is_empty():
			# pausa battaglia?
			if g.modal.get_child_count() > 0 and not shots_taken.has("battle%d" % g.engine.year):
				shots_taken["battle%d" % g.engine.year] = true
				await shot("battaglia_anno%d" % g.engine.year)
				g._clear_modal()
				g.engine.provide_decision(true)
			elif g.modal.get_child_count() > 0:
				g._clear_modal()
				g.engine.provide_decision(true)
			continue
		var key := "%s_%d_%d" % [req["type"], g.engine.year, g.engine.phase]
		if not shots_taken.has(key) and (g.engine.year <= 2 or req["type"] != "influence"):
			shots_taken[key] = true
			await shot(key)
			if req["type"] == "influence":
				# seleziona il primo dado e fotografa le evidenziazioni
				var free = g.engine.free_dice(int(req["seat"]))
				g.sel_dice = [free[0]]
				g._influence_ui()
				g._refresh_adv_highlight()
				await shot(key + "_sel")
		auto_answer()
	quit()
