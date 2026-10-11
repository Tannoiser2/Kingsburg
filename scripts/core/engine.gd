class_name KBEngine
extends Node
## Motore delle regole di Kingsburg (seconda edizione, gioco base). Nessuna dipendenza dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito, per i giocatori umani viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte passano dal registro
## di mosse (OnlineSession): con lo stesso seme ogni dispositivo ottiene la stessa partita.

signal changed
signal log_added(text: String)
signal phase_changed(year: int, phase: int)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/kb_data.gd")

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}

var players: Array = []
var n := 0
var order: Array = []            # posti nell'ordine di gioco
var year := 1
var phase := 0
var season := -1                  # 0 primavera, 1 estate, 2 autunno, -1 nessuna
var step := ""                    # sotto-fase: roll, influence, rewards, build, ...
var adv := {}                     # consigliere -> {"seat", "dice":[valori], "white":[bool], "p2", "mk"}
var adv_extra := {}               # consigliere -> posto che ha usato l'Agente del Re lì
var blocked := {}                 # (2 giocatori) consigliere -> {"dice":[valori], "color"}
var deck: Array = []              # indice carta Invasori per anno (0..4)
var revealed := -1                # carta Invasori scoperta in inverno
var envoy := -1                   # posto che ha il segnalino Agente del Re
var king_die := 0
var battle: Array = []            # risultati dell'ultima battaglia
var game_over := false
var results: Array = []
var log_lines: Array = []
var current := -1                 # posto che sta decidendo
var abort := false
var pause_enabled := false
var online = null
var dummy_colors: Array = []


# ------------------------------------------------------------------ setup

## config: {"seats":[{"color":int,"ai":bool,"name":String,"level":int}], "seed":int, "ai_level":int}
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	players.clear()
	ais.clear()
	var seats: Array = config["seats"]
	n = seats.size()
	for i in range(n):
		var s: Dictionary = seats[i]
		var a := KBAI.new()
		a.level = int(s.get("level", config.get("ai_level", 1)))
		a.rng.seed = int(config.get("seed", 1)) * 7 + i * 131 + 17
		ais[i] = a
		var c: Dictionary = D.COLORS[int(s["color"])]
		players.append({
			"seat": i, "color": int(s["color"]), "name": str(s.get("name", c["name"])), "ai": bool(s.get("ai", true)),
			"goods": {"g": 0, "w": 0, "s": 0}, "p2": 0, "vp": 0, "sol": 0,
			"bld": _empty_bld(), "dice": [], "passed": false, "aid_white": false,
			"known": {}, "used": {}, "sum": 0,
		})
	# mazzo Invasori: una carta a caso per ogni anno
	deck.clear()
	for y in range(1, 6):
		var pool := []
		for k in range(D.INVADERS.size()):
			if D.INVADERS[k]["year"] == y:
				pool.append(k)
		deck.append(pool[rng.randi_range(0, pool.size() - 1)])
	# ordine iniziale sorteggiato
	order = range(n)
	_shuffle(order)
	# colori dei dadi neutrali (2 giocatori)
	dummy_colors.clear()
	for c in D.COLORS:
		var used := false
		for p in players:
			if p["color"] == c["id"]:
				used = true
		if not used:
			dummy_colors.append(c["key"])
	year = 1
	phase = 0
	envoy = -1
	log_lines.clear()
	game_over = false
	results.clear()


func _empty_bld() -> Array:
	var a := []
	for i in range(20):
		a.append(false)
	return a


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func pname(seat: int) -> String:
	return players[seat]["name"]


func log_msg(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 400:
		log_lines.pop_front()
	log_added.emit(t)


func has_b(seat: int, b: int) -> bool:
	return players[seat]["bld"][b]


func n_bld(seat: int) -> int:
	var c := 0
	for x in players[seat]["bld"]:
		if x:
			c += 1
	return c


func n_goods(seat: int) -> int:
	var g: Dictionary = players[seat]["goods"]
	return g["g"] + g["w"] + g["s"]


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


# ------------------------------------------------------------------ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


## Pausa per far leggere qualcosa (battaglia, fine anno): solo se c'è qualcuno davanti allo schermo.
func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled:
		return
	if online != null and online.catchup:
		return
	if not any_local_human():
		return
	pause_requested.emit(req)
	await decision_provided


# ------------------------------------------------------------------ partita

func run() -> void:
	for y in range(1, 6):
		year = y
		await phase_1()
		if abort: return
		await productive(0)
		if abort: return
		await phase_3()
		await productive(1)
		if abort: return
		await phase_5()
		await productive(2)
		if abort: return
		await phase_7()
		if abort: return
		await phase_8()
		if abort: return
	_final_scoring()


func _set_phase(ph: int) -> void:
	phase = ph
	season = -1
	step = ""
	phase_changed.emit(year, ph)
	log_msg("[b]Anno %s · %s[/b]" % [D.ROMAN[year], D.PHASE_NAMES[ph]])
	changed.emit()


## Chi è "più in difficoltà": meno edifici, a parità meno merci. Restituisce i posti ultimi alla pari.
func _weakest() -> Array:
	var best := []
	var key := Vector2i(999, 999)
	for p in players:
		var k := Vector2i(n_bld(p["seat"]), n_goods(p["seat"]))
		if k.x < key.x or (k.x == key.x and k.y < key.y):
			key = k
			best = [p["seat"]]
		elif k == key:
			best.append(p["seat"])
	return best


func phase_1() -> void:
	_set_phase(1)
	for p in players:
		p["aid_white"] = false
	var w := _weakest()
	if w.size() == 1:
		players[w[0]]["aid_white"] = true
		log_msg("Aiuto del Re: %s lancerà un dado bianco in più in Primavera." % pname(w[0]))
		fx.emit("aid", {"seat": w[0]})
	else:
		var names := []
		for s in w:
			names.append(pname(s))
		log_msg("Aiuto del Re: %s ricevono una merce a scelta." % ", ".join(names))
		for s in order:
			if s in w:
				var r = await decide(s, {"type": "goods", "n": 1, "title": "Aiuto del Re: scegli una merce", "ctx": "aid"})
				_gain_bundle(s, _sanitize_goods(r, 1), "Aiuto del Re")
	changed.emit()


func phase_3() -> void:
	_set_phase(3)
	var mx := 0
	for p in players:
		mx = maxi(mx, n_bld(p["seat"]))
	if mx == 0:
		log_msg("Premio del Re: nessuno ha ancora costruito.")
		return
	for p in players:
		if n_bld(p["seat"]) == mx:
			_add_vp(p["seat"], 1)
			log_msg("Premio del Re: %s (+1 PV, %d edifici)." % [pname(p["seat"]), mx])
	changed.emit()


func phase_5() -> void:
	_set_phase(5)
	if envoy >= 0:
		log_msg("%s restituisce l'Agente del Re senza averlo usato." % pname(envoy))
		envoy = -1
	var w := _weakest()
	if w.size() == 1:
		envoy = w[0]
		log_msg("Agente del Re: va a %s." % pname(envoy))
		fx.emit("envoy", {"seat": envoy})
	else:
		log_msg("Agente del Re: più giocatori sono ultimi alla pari, nessuno lo riceve.")
	changed.emit()


# ------------------------------------------------------------------ stagione produttiva

func productive(si: int) -> void:
	_set_phase([2, 4, 6][si])
	season = si
	adv.clear()
	adv_extra.clear()
	blocked.clear()
	for p in players:
		p["used"] = {}
		p["passed"] = false
		p["dice"] = []
	# a) dadi
	step = "roll"
	for s in range(n):
		var p: Dictionary = players[s]
		if has_b(s, D.B_GILDA_MERC):
			p["goods"]["g"] += 1
			log_msg("%s: Gilda dei Mercanti, +1 Oro." % pname(s))
		var whites := 0
		if has_b(s, D.B_FATTORIE):
			whites += 1
		if si == 0 and p["aid_white"]:
			whites += 1
		for k in range(3):
			p["dice"].append({"v": _d6(), "white": false, "used": false})
		for k in range(whites):
			p["dice"].append({"v": _d6(), "white": true, "used": false})
	fx.emit("roll", {})
	changed.emit()
	# rilanci (Statua e Cappella), nell'ordine di gioco attuale
	for s in order:
		await _rerolls(s)
	# nuovo ordine di gioco
	var prev := order.duplicate()
	for p in players:
		p["sum"] = dice_sum(p["seat"])
	order.sort_custom(func(a, b):
		var sa: int = players[a]["sum"]
		var sb: int = players[b]["sum"]
		if sa != sb:
			return sa < sb
		return prev.find(a) < prev.find(b))
	var parts := []
	for s in order:
		parts.append("%s (%d)" % [pname(s), players[s]["sum"]])
	log_msg("Ordine di gioco: " + ", ".join(parts))
	if n == 2:
		_block_two_players()
	changed.emit()
	# b) influenzare i Consiglieri
	step = "influence"
	var guard := 0
	while guard < 200:
		guard += 1
		var any_active := false
		for s in order:
			var p: Dictionary = players[s]
			if p["passed"]:
				continue
			var moves := legal_moves(s)
			if moves.is_empty():
				p["passed"] = true
				changed.emit()
				continue
			any_active = true
			var r = await decide(s, {"type": "influence", "moves": moves})
			if abort:
				return
			var mv := _match_move(r, moves)
			if mv.is_empty():
				p["passed"] = true
				log_msg("%s passa." % pname(s))
			else:
				_apply_move(s, mv)
			changed.emit()
		if not any_active:
			break
	# c) aiuto dei Consiglieri
	step = "rewards"
	changed.emit()
	for a in range(1, 19):
		if adv.has(a):
			await _reward(adv[a]["seat"], a)
		if adv_extra.has(a):
			await _reward(adv_extra[a], a)
	# d) costruzione
	step = "build"
	for s in order:
		await _build_turn(s)
	# fine stagione
	step = "end"
	for s in order:
		await _end_of_season(s, si)
	adv.clear()
	adv_extra.clear()
	blocked.clear()
	for p in players:
		p["dice"] = []
	season = -1
	changed.emit()


func _d6() -> int:
	return rng.randi_range(1, 6)


func dice_sum(seat: int) -> int:
	var t := 0
	for d in players[seat]["dice"]:
		t += int(d["v"])
	return t


func _rerolls(s: int) -> void:
	var p: Dictionary = players[s]
	for attempt in range(2):
		var did := false
		if has_b(s, D.B_STATUA) and not p["used"].get("statue", false) and _all_same(s):
			var r = await decide(s, {"type": "reroll_statue", "title": "Statua: tutti i dadi uguali. Vuoi rilanciarne uno?"})
			p["used"]["statue"] = true
			var idx := int(r) if (r is int or r is float) else -1
			if idx >= 0 and idx < p["dice"].size():
				var old: int = p["dice"][idx]["v"]
				p["dice"][idx]["v"] = _d6()
				log_msg("%s rilancia un dado con la Statua: %d → %d." % [pname(s), old, p["dice"][idx]["v"]])
				fx.emit("roll", {"seat": s})
				did = true
			changed.emit()
		if has_b(s, D.B_CAPPELLA) and not p["used"].get("chapel", false) and dice_sum(s) <= 7:
			var r2 = await decide(s, {"type": "reroll_chapel", "title": "Cappella: la somma dei dadi è %d. Vuoi rilanciarli tutti?" % dice_sum(s)})
			p["used"]["chapel"] = true
			if r2 == true:
				for d in p["dice"]:
					d["v"] = _d6()
				log_msg("%s rilancia tutti i dadi con la Cappella: somma %d." % [pname(s), dice_sum(s)])
				fx.emit("roll", {"seat": s})
				did = true
			changed.emit()
		if not did:
			break


func _all_same(s: int) -> bool:
	var dice: Array = players[s]["dice"]
	if dice.size() < 2:
		return false
	for d in dice:
		if d["v"] != dice[0]["v"]:
			return false
	return true


## Con due giocatori, i dadi di due colori non usati occupano alcuni Consiglieri.
func _block_two_players() -> void:
	var c1: String = dummy_colors[0] if dummy_colors.size() > 0 else "white"
	var c2: String = dummy_colors[1] if dummy_colors.size() > 1 else "white"
	var a := [_d6(), _d6(), _d6()]
	var s3: int = a[0] + a[1] + a[2]
	blocked[s3] = {"dice": a, "color": c1}
	var b := [_d6(), _d6()]
	var s2: int = b[0] + b[1]
	if s2 != s3:
		blocked[s2] = {"dice": b, "color": c2}
	else:
		blocked[b[0]] = {"dice": [b[0]], "color": c2}
		if b[1] != b[0]:
			blocked[b[1]] = {"dice": [b[1]], "color": c2}
	var ks := blocked.keys()
	ks.sort()
	log_msg("Consiglieri occupati dai dadi neutrali: %s." % ", ".join(ks.map(func(x): return str(x))))


# ------------------------------------------------------------------ mosse di influenza

func free_dice(seat: int) -> Array:
	var out := []
	var dice: Array = players[seat]["dice"]
	for i in range(dice.size()):
		if not dice[i]["used"]:
			out.append(i)
	return out


func is_taken(a: int) -> bool:
	return adv.has(a) or blocked.has(a)


## Tutte le mosse legali: {"adv", "dice":[indici], "p2":0|1, "mk":-1|0|1, "env":bool}
func legal_moves(seat: int) -> Array:
	var p: Dictionary = players[seat]
	var free := free_dice(seat)
	var out := []
	if free.is_empty():
		return out
	var can_p2: bool = p["p2"] > 0 and not p["used"].get("p2", false)   # un solo gettone +2 per stagione
	var can_mk: bool = has_b(seat, D.B_MERCATO) and not p["used"].get("market", false)
	var can_env: bool = envoy == seat
	var seen := {}
	var m := free.size()
	for mask in range(1, 1 << m):
		var idx := []
		var tot := 0
		var colored := false
		for k in range(m):
			if mask & (1 << k):
				var di: int = free[k]
				idx.append(di)
				tot += int(p["dice"][di]["v"])
				if not p["dice"][di]["white"]:
					colored = true
		if not colored:
			continue
		for p2 in ([0, 1] if can_p2 else [0]):
			for mk in ([0, -1, 1] if can_mk else [0]):
				var a: int = tot + 2 * p2 + mk
				if a < 1 or a > 18:
					continue
				var taken := is_taken(a)
				var env := false
				if taken:
					if not can_env or adv_extra.has(a):
						continue
					env = true
				var key := "%d|%s|%d|%d" % [a, str(idx), p2, mk]
				if seen.has(key):
					continue
				seen[key] = true
				out.append({"adv": a, "dice": idx, "p2": p2, "mk": mk, "env": env})
	return out


func _match_move(r, moves: Array) -> Dictionary:
	if not (r is Dictionary) or r.get("pass", false):
		return {}
	for mv in moves:
		if int(mv["adv"]) == int(r.get("adv", -1)) and int(mv["p2"]) == int(r.get("p2", 0)) and int(mv["mk"]) == int(r.get("mk", 0)) and bool(mv["env"]) == bool(r.get("env", false)):
			var a: Array = mv["dice"].duplicate()
			var b: Array = []
			for x in r.get("dice", []):
				b.append(int(x))
			a.sort()
			b.sort()
			if a == b:
				return mv
	return {}


func _apply_move(seat: int, mv: Dictionary) -> void:
	var p: Dictionary = players[seat]
	var vals := []
	var whites := []
	for di in mv["dice"]:
		p["dice"][di]["used"] = true
		vals.append(p["dice"][di]["v"])
		whites.append(p["dice"][di]["white"])
	if mv["p2"] > 0:
		p["p2"] -= 1
		p["used"]["p2"] = true
	if mv["mk"] != 0:
		p["used"]["market"] = true
	var a: int = mv["adv"]
	var extra := ""
	if mv["p2"] > 0:
		extra += " +2"
	if mv["mk"] != 0:
		extra += " (Mercato %+d)" % mv["mk"]
	if mv["env"]:
		adv_extra[a] = seat
		envoy = -1
		log_msg("%s usa l'Agente del Re e influenza anche lui %s (%d) con %s%s." % [pname(seat), D.ADVISORS[a]["name"], a, "+".join(vals.map(func(x): return str(x))), extra])
	else:
		adv[a] = {"seat": seat, "dice": vals, "white": whites, "p2": mv["p2"], "mk": mv["mk"]}
		log_msg("%s influenza %s (%d) con %s%s." % [pname(seat), D.ADVISORS[a]["name"], a, "+".join(vals.map(func(x): return str(x))), extra])
	fx.emit("place", {"seat": seat, "adv": a})


# ------------------------------------------------------------------ ricompense

func _reward(s: int, a: int) -> void:
	var r: Dictionary = D.ADVISORS[a]["r"]
	var nm: String = D.ADVISORS[a]["name"]
	var p: Dictionary = players[s]
	var got := {}
	for t in D.GOODS:
		if r.get(t, 0) > 0:
			got[t] = r[t]
	if r.has("or"):
		var opts: Array = r["or"]
		var c = await decide(s, {"type": "pick", "ctx": "adv%d" % a, "adv": a, "title": "%s: scegli" % nm,
			"options": opts.map(func(o): return {"label": D.bundle_text(o), "val": o})})
		var ci := clampi(int(c) if (c is int or c is float) else 0, 0, opts.size() - 1)
		for t in opts[ci]:
			got[t] = got.get(t, 0) + opts[ci][t]
	if r.get("any", 0) > 0:
		var c2 = await decide(s, {"type": "goods", "n": r["any"], "ctx": "adv%d" % a, "adv": a, "title": "%s: scegli %d merc%s" % [nm, r["any"], "e" if r["any"] == 1 else "i"]})
		var gs := _sanitize_goods(c2, r["any"])
		for t in gs:
			got[t] = got.get(t, 0) + gs[t]
	if r.has("alch"):
		var have := []
		for t in D.GOODS:
			if p["goods"][t] > 0:
				have.append(t)
		if not have.is_empty():
			var opts2 := [{"label": "Non scambiare", "val": ""}]
			for t in have:
				var others := D.GOODS.filter(func(x): return x != t)
				opts2.append({"label": "Cedi 1 %s → 1 %s e 1 %s" % [D.GOOD_NAMES[t], D.GOOD_NAMES[others[0]], D.GOOD_NAMES[others[1]]], "val": t})
			var c3 = await decide(s, {"type": "pick", "ctx": "alch", "adv": a, "title": "Alchimista: vuoi scambiare una merce?", "options": opts2})
			var ci3 := clampi(int(c3) if (c3 is int or c3 is float) else 0, 0, opts2.size() - 1)
			var give: String = opts2[ci3]["val"]
			if give != "" and p["goods"][give] > 0:
				p["goods"][give] -= 1
				for t in D.GOODS:
					if t != give:
						got[t] = got.get(t, 0) + 1
				log_msg("%s: l'Alchimista trasforma 1 %s." % [pname(s), D.GOOD_NAMES[give]])
	if r.has("spy"):
		var c4 = await decide(s, {"type": "pick", "ctx": "spy", "adv": a, "title": "Spia: paghi 1 PV per 3 merci a scelta?",
			"options": [{"label": "No", "val": false}, {"label": "Sì, pago 1 PV", "val": true}]})
		if int(c4) == 1:
			_add_vp(s, -1)
			var c5 = await decide(s, {"type": "goods", "n": 3, "ctx": "spy", "adv": a, "title": "Spia: scegli 3 merci"})
			var gs5 := _sanitize_goods(c5, 3)
			for t in gs5:
				got[t] = got.get(t, 0) + gs5[t]
	if r.get("vp", 0) > 0:
		got["vp"] = r["vp"]
	if r.get("sol", 0) > 0:
		got["sol"] = r["sol"] + (1 if has_b(s, D.B_SCUDERIA) else 0)
	if r.get("p2", 0) > 0:
		got["p2"] = r["p2"]
	_gain_bundle(s, got, nm)
	if r.get("peek", false):
		p["known"][year] = true
		log_msg("%s guarda la carta Invasori." % pname(s))
		fx.emit("peek", {"seat": s, "card": deck[year - 1]})
	changed.emit()


func _sanitize_goods(r, nn: int) -> Dictionary:
	var out := {"g": 0, "w": 0, "s": 0}
	if r is Dictionary:
		var tot := 0
		for t in D.GOODS:
			var v := maxi(0, int(r.get(t, 0)))
			v = mini(v, nn - tot)
			out[t] = v
			tot += v
		if tot < nn:
			out["g"] += nn - tot
	else:
		out["g"] = nn
	return out


func _gain_bundle(s: int, b: Dictionary, why: String) -> void:
	var p: Dictionary = players[s]
	for t in D.GOODS:
		p["goods"][t] += b.get(t, 0)
	if b.get("vp", 0) != 0:
		_add_vp(s, b["vp"])
	if b.get("sol", 0) > 0:
		p["sol"] += b["sol"]
	if b.get("p2", 0) > 0:
		p["p2"] += b["p2"]
	var txt := D.bundle_text(b)
	if txt != "":
		log_msg("%s: %s → %s." % [pname(s), why, txt])
	fx.emit("gain", {"seat": s, "b": b})


func _add_vp(s: int, v: int) -> void:
	players[s]["vp"] += v


# ------------------------------------------------------------------ costruzione

func building_cost(s: int, b: int) -> Dictionary:
	var c: Dictionary = D.BUILDINGS[b]["cost"].duplicate()
	if has_b(s, D.B_ARGANO) and D.building_col(b) >= 2 and c.get("g", 0) > 0:
		c["g"] -= 1
	return c


func can_afford(s: int, cost: Dictionary) -> bool:
	for t in D.GOODS:
		if players[s]["goods"][t] < cost.get(t, 0):
			return false
	return true


func can_build(s: int, b: int) -> bool:
	if has_b(s, b):
		return false
	var col := D.building_col(b)
	for c in range(col):
		if not has_b(s, D.building_row(b) * 4 + c):
			return false
	return can_afford(s, building_cost(s, b))


func buildable(s: int) -> Array:
	var out := []
	for b in range(20):
		if can_build(s, b):
			out.append(b)
	return out


func _build_turn(s: int) -> void:
	var opts := buildable(s)
	if not opts.is_empty():
		var r = await decide(s, {"type": "build", "options": opts, "second": false})
		var b := int(r) if (r is int or r is float) else -1
		if b in opts:
			_do_build(s, b)
	# Agente del Re: un secondo edificio nella stessa stagione
	if envoy == s:
		var opts2 := buildable(s)
		if not opts2.is_empty():
			var r2 = await decide(s, {"type": "build", "options": opts2, "second": true})
			var b2 := int(r2) if (r2 is int or r2 is float) else -1
			if b2 in opts2:
				envoy = -1
				log_msg("%s usa l'Agente del Re per costruire un secondo edificio." % pname(s))
				_do_build(s, b2)


func _do_build(s: int, b: int) -> void:
	var c := building_cost(s, b)
	for t in D.GOODS:
		players[s]["goods"][t] -= c.get(t, 0)
	players[s]["bld"][b] = true
	var vp: int = D.BUILDINGS[b]["vp"]
	_add_vp(s, vp)
	log_msg("%s costruisce: %s (%s)%s." % [pname(s), D.BUILDINGS[b]["name"], D.cost_text(c), (", +%d PV" % vp) if vp > 0 else ""])
	fx.emit("build", {"seat": s, "b": b})
	changed.emit()


func _end_of_season(s: int, si: int) -> void:
	var p: Dictionary = players[s]
	if si == 1 and has_b(s, D.B_LOCANDA):
		p["p2"] += 1
		log_msg("%s: Locanda, +1 gettone +2." % pname(s))
	if has_b(s, D.B_AMBASCIATA):
		_add_vp(s, 1)
		log_msg("%s: Ambasciata, +1 PV." % pname(s))
	if has_b(s, D.B_MUNICIPIO):
		var opts := [{"label": "Niente", "val": ""}]
		if p["p2"] > 0:
			opts.append({"label": "Paga un gettone +2", "val": "p2"})
		for t in D.GOODS:
			if p["goods"][t] > 0:
				opts.append({"label": "Paga 1 %s" % D.GOOD_NAMES[t], "val": t})
		if opts.size() > 1:
			var r = await decide(s, {"type": "pick", "ctx": "townhall", "title": "Municipio: paghi per 1 PV?", "options": opts})
			var ci := clampi(int(r) if (r is int or r is float) else 0, 0, opts.size() - 1)
			var v: String = opts[ci]["val"]
			if v == "p2" and p["p2"] > 0:
				p["p2"] -= 1
				_add_vp(s, 1)
				log_msg("%s: Municipio, paga un gettone +2 per 1 PV." % pname(s))
			elif v in D.GOODS and p["goods"][v] > 0:
				p["goods"][v] -= 1
				_add_vp(s, 1)
				log_msg("%s: Municipio, paga 1 %s per 1 PV." % [pname(s), D.GOOD_NAMES[v]])
	changed.emit()


# ------------------------------------------------------------------ mercenari e battaglia

func recruit_cost(s: int) -> int:
	return 1 if has_b(s, D.B_CASERMA) else 2


func phase_7() -> void:
	_set_phase(7)
	for s in order:
		var cp := recruit_cost(s)
		if n_goods(s) < cp:
			continue
		var r = await decide(s, {"type": "recruit", "cost_per": cp, "title": "Mercenari: recluta soldati (%d merc%s ciascuno)" % [cp, "e" if cp == 1 else "i"]})
		if not (r is Dictionary):
			continue
		var k := maxi(0, int(r.get("n", 0)))
		var pay := _sanitize_goods(r.get("pay", {}), k * cp)
		var ok := true
		for t in D.GOODS:
			if pay[t] > players[s]["goods"][t]:
				ok = false
		if k == 0 or not ok:
			continue
		for t in D.GOODS:
			players[s]["goods"][t] -= pay[t]
		players[s]["sol"] += k
		log_msg("%s recluta %d soldat%s pagando %s." % [pname(s), k, "o" if k == 1 else "i", D.cost_text(pay)])
		fx.emit("recruit", {"seat": s, "n": k})
		changed.emit()


func battle_bonus(s: int, race: String) -> int:
	var b := 0
	if has_b(s, D.B_TORRE): b += 1
	if has_b(s, D.B_FUCINA): b += 1
	if has_b(s, D.B_GILDA_MAGHI): b += 2
	if has_b(s, D.B_PALIZZATA): b += 2 if race == "zombi" else 1
	if has_b(s, D.B_MURA): b += 1
	if has_b(s, D.B_FORTEZZA): b += 1
	if has_b(s, D.B_CHIESA) and race == "demoni": b += 1
	if has_b(s, D.B_BARRICATA) and race == "goblin": b += 1
	if has_b(s, D.B_FATTORIE): b -= 1
	return b


func phase_8() -> void:
	_set_phase(8)
	var ci: int = deck[year - 1]
	var card: Dictionary = D.INVADERS[ci]
	revealed = ci
	king_die = _d6()
	log_msg("Invasori: %s, forza %d. Il dado del Re dà %d soldat%s a tutti." % [D.RACE_NAMES[card["race"]], card["str"], king_die, "o" if king_die == 1 else "i"])
	fx.emit("invaders", {"card": ci, "die": king_die})
	for p in players:
		p["sol"] += king_die
	changed.emit()
	battle.clear()
	var totals := {}
	for s in range(n):
		var tot: int = players[s]["sol"] + battle_bonus(s, card["race"])
		totals[s] = tot
		var res := "tie"
		if tot > card["str"] or (tot == card["str"] and has_b(s, D.B_MURA)):
			res = "win"
		elif tot < card["str"]:
			res = "lose"
		battle.append({"seat": s, "total": tot, "res": res, "sol": players[s]["sol"], "bonus": battle_bonus(s, card["race"]), "notes": []})
	var best := -999
	for e in battle:
		if e["res"] == "win":
			best = maxi(best, e["total"])
	var mx := -999
	for e in battle:
		mx = maxi(mx, e["total"])
	for s in order:
		var e: Dictionary = battle[s]
		if e["res"] == "win":
			var rew: Dictionary = card["rew"].duplicate()
			if rew.get("any", 0) > 0:
				var r = await decide(s, {"type": "goods", "n": rew["any"], "ctx": "battle", "title": "Vittoria! Scegli %d merc%s" % [rew["any"], "e" if rew["any"] == 1 else "i"]})
				var gs := _sanitize_goods(r, rew["any"])
				rew.erase("any")
				for t in gs:
					rew[t] = rew.get(t, 0) + gs[t]
			if has_b(s, D.B_FORTEZZA):
				rew["vp"] = rew.get("vp", 0) + 1
				e["notes"].append("Fortezza +1 PV")
			if e["total"] == mx:
				rew["vp"] = rew.get("vp", 0) + 1
				e["notes"].append("miglior difesa +1 PV")
			_gain_bundle(s, rew, "vittoria contro gli Invasori")
			e["got"] = D.bundle_text(rew)
		elif e["res"] == "lose":
			e["lost"] = await _apply_penalty(s, card["pen"])
		else:
			log_msg("%s respinge a fatica gli Invasori (pareggio)." % pname(s))
	changed.emit()
	await pause_point({"type": "ack", "ctx": "battle", "card": ci})
	for p in players:
		p["sol"] = 0
	revealed = -1
	changed.emit()


func _apply_penalty(s: int, pen: Dictionary) -> String:
	var p: Dictionary = players[s]
	var parts := []
	for t in D.GOODS:
		if pen.get(t, 0) > 0:
			var k := mini(pen[t], p["goods"][t])
			p["goods"][t] -= k
			if k > 0:
				parts.append("%d %s" % [k, D.GOOD_NAMES[t]])
	if pen.get("any", 0) > 0:
		var k2: int = pen["any"]
		var lose := {"g": 0, "w": 0, "s": 0}
		if n_goods(s) <= k2:
			lose = p["goods"].duplicate()
		else:
			var r = await decide(s, {"type": "lose", "n": k2, "title": "Sconfitta: scegli %d merci da perdere" % k2})
			lose = _sanitize_goods(r, k2)
			for t in D.GOODS:
				if lose[t] > p["goods"][t]:
					lose = _auto_lose(s, k2)
					break
		for t in D.GOODS:
			p["goods"][t] -= lose[t]
		var tx := D.cost_text(lose)
		if n_goods(s) >= 0 and tx != "gratis":
			parts.append(tx)
	for i in range(pen.get("bld", 0)):
		var b := _building_to_destroy(s)
		if b >= 0:
			p["bld"][b] = false
			_add_vp(s, -D.BUILDINGS[b]["vp"])
			parts.append("%s distrutto" % D.BUILDINGS[b]["name"])
			fx.emit("destroy", {"seat": s, "b": b})
	if pen.get("vp", 0) > 0:
		_add_vp(s, -pen["vp"])
		parts.append("%d PV" % pen["vp"])
	var txt := ", ".join(parts) if not parts.is_empty() else "nulla da perdere"
	log_msg("%s è sconfitto: perde %s." % [pname(s), txt])
	return txt


func _auto_lose(s: int, k: int) -> Dictionary:
	var g: Dictionary = players[s]["goods"].duplicate()
	var out := {"g": 0, "w": 0, "s": 0}
	for i in range(k):
		var best := ""
		for t in ["w", "s", "g"]:
			if g[t] > 0 and (best == "" or g[t] > g[best]):
				best = t
		if best == "":
			break
		g[best] -= 1
		out[best] += 1
	return out


## L'edificio distrutto: colonna più a destra con edifici, riga più in alto.
func _building_to_destroy(s: int) -> int:
	for col in range(3, -1, -1):
		for row in range(5):
			var b := row * 4 + col
			if has_b(s, b):
				return b
	return -1


# ------------------------------------------------------------------ fine partita

func _final_scoring() -> void:
	phase = 9
	season = -1
	for p in players:
		if p["bld"][D.B_CATTEDRALE]:
			var extra := n_goods(p["seat"]) / 2
			if extra > 0:
				_add_vp(p["seat"], extra)
				log_msg("%s: Cattedrale, +%d PV per le merci." % [pname(p["seat"]), extra])
	var ranking := range(n)
	ranking.sort_custom(func(a, b):
		var pa: Dictionary = players[a]
		var pb: Dictionary = players[b]
		if pa["vp"] != pb["vp"]:
			return pa["vp"] > pb["vp"]
		if n_goods(a) != n_goods(b):
			return n_goods(a) > n_goods(b)
		if n_bld(a) != n_bld(b):
			return n_bld(a) > n_bld(b)
		return a < b)
	results.clear()
	var place := 0
	for i in range(ranking.size()):
		var s: int = ranking[i]
		if i == 0:
			place = 1
		else:
			var prv: int = ranking[i - 1]
			if not (players[s]["vp"] == players[prv]["vp"] and n_goods(s) == n_goods(prv) and n_bld(s) == n_bld(prv)):
				place = i + 1
		results.append({"seat": s, "place": place, "vp": players[s]["vp"], "goods": n_goods(s), "bld": n_bld(s)})
	game_over = true
	log_msg("[b]Fine partita: vince %s con %d PV.[/b]" % [pname(ranking[0]), players[ranking[0]]["vp"]])
	changed.emit()
	game_ended.emit(results)


## Impronta della partita (per verificare che due dispositivi siano allineati).
func fingerprint() -> String:
	var parts := []
	for p in players:
		parts.append("%d:%d:%d:%d:%d:%d:%s" % [p["vp"], p["goods"]["g"], p["goods"]["w"], p["goods"]["s"], p["p2"], p["sol"], str(p["bld"].map(func(x): return 1 if x else 0))])
	return "|".join(parts)
