extends SceneTree
## Prova del gioco online: due istanze di Kingsburg (chi crea la stanza e un amico) giocano una
## partita intera sul finto Firebase (tests/firebase_mock.py), con un terzo colore IA. Le persone
## sono simulate dall'IA. KB_ROLE=host|guest, KB_CODEFILE=file per il codice della stanza,
## KB_PHASE=drop: l'ospite esce a metà (per provare il rientro con KB_PHASE=back).
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0
var hooked := false
var ai := KBAI.new()

func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("KB_ROLE")
	var cf := OS.get_environment("KB_CODEFILE")
	var phase := OS.get_environment("KB_PHASE")
	var menu = main.current
	menu.seat_mode = [0, 0, 1, 2, 2]
	if OS.get_environment("KB_MODS") != "":
		for k in OS.get_environment("KB_MODS").split(","):
			menu.mods[k] = true
	menu.speed = 3
	menu._online_panel()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await menu._online_create()
		var code: String = main.lobby.get("code", "")
		print("KBTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._online_join()
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 900000:
			print("KBTEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("engine" in view) or view.engine == null:
			continue
		var e: KBEngine = view.engine
		if not hooked:
			hooked = true
			e.pause_requested.connect(func(_t): (func(): e.provide_decision(true)).call_deferred())
		var req: Dictionary = view.pending
		if not req.is_empty() and view.online._mine_pending:
			view._provide(ai.decide(e, req["seat"], req))
		if phase == "drop" and e.year >= 2 and e.phase >= 4:
			print("KBTEST esco a metà partita, mossa ", view.online.n)
			quit(0)
			return
		if e.game_over:
			await _wait(0.5)
			print("KBTEST impronta ", view.online.n, " | ", e.fingerprint())
			quit(0)
			return
