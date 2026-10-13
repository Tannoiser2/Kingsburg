class_name KBEngine
extends Node
## Motore delle regole di Kingsburg (seconda edizione) con i moduli di To Forge a Realm.
## Nessuna dipendenza dalla UI. Ogni scelta passa da `decide()`: l'IA risponde subito, per i giocatori
## umani viene emesso `decision_requested` e si attende `provide_decision()`. Online le scelte passano
## dal registro di mosse (OnlineSession): con lo stesso seme ogni dispositivo ottiene la stessa partita.
##
## Moduli (config["mods"]):
##   lines        1 · linee di edifici aggiuntive (retro del tabellone Provincia, righe A..G)
##   alt          2 · linee di edifici alternative      (alt_draft: scelta a turno invece che a caso)
##   gov          3 · Governatori                       (gov_auction: asta in PV)
##   fate         4 · carte Fato
##   troops       5 · Rinforzi invernali determinabili
##   capricci     6 · Capricci a Corte                   (restaurazione: variante Restaurazione)

signal changed
signal log_added(text: String)
signal phase_changed(year: int, phase: int)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/kb_data.gd")
const POL5 := 105                 # caselle della carta del Politico
const POL10 := 110

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var mods := {}

var players: Array = []
var n := 0
var order: Array = []            # posti nell'ordine di gioco
var year := 1
var phase := 0
var season := -1                  # 0 primavera, 1 estate, 2 autunno, -1 nessuna
var step := ""                    # sotto-fase: setup, roll, influence, rewards, build, end
var adv := {}                     # consigliere -> {"seat", "dice":[valori], "white":[bool], "p2", "mk"}
var adv_extra := {}               # consigliere -> posto che ha usato l'Agente del Re lì
var blocked := {}                 # (2 giocatori) consigliere -> {"dice":[valori], "color"}
var deck: Array = []              # indice carta Invasori per anno (0..4)
var deck2: Array = []             # seconda carta (Manovra a Tenaglia), -1 se assente
var revealed := -1                # carta Invasori scoperta in inverno
var revealed2 := -1
var envoy := -1                   # posto che ha il segnalino Agente del Re
var king_die := 0
var battle: Array = []            # risultati dell'ultima battaglia
var battle_str := 0
var game_over := false
var results: Array = []
var log_lines: Array = []
var current := -1                 # posto che sta decidendo
var abort := false
var pause_enabled := false
var online = null
var dummy_colors: Array = []
var setup_done := false

# carte Fato
var fate_deck: Array = []
var fate_card := -1               # carta scoperta quest'anno
var fate_key := ""                # effetto in vigore (Situazione Perdurante copia quello precedente)
var fate_prev_key := ""
var fate_extra := -1              # carta pescata in più per Situazione Perdurante al primo anno
var king_sick := 0
var last_year := 5
# Capricci
var cap_pile: Array = []
var cap_tiles := {}               # consigliere -> true
var cap4 := {"g": 0, "w": 0, "s": 0}
var cap5 := ""
var cap_last := -1                # ultima tessera estratta (per la UI)
# Accordi Segreti / Stelle in Ascesa
var marks := {}                   # consigliere -> [posti]
var stars := {}                   # consigliere -> "g"|"w"|"s"|"p2"
# Governatori in asta (UI)
var gov_pool: Array = []


# ------------------------------------------------------------------ setup

## config: {"seats":[{"color":int,"ai":bool,"name":String,"level":int}], "seed":int, "ai_level":int, "mods":{}}
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	mods = config.get("mods", {}).duplicate()
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
			"bld": _empty_bld(), "lines": _base_lines(), "dice": [], "passed": false, "aid_white": false,
			"known": {}, "used": {}, "sum": 0, "gov": -1, "gov_opts": [], "alt_opts": [],
			"troops": D.TROOP_TOKENS.duplicate(), "troop": -1, "heir": {}, "paladin": false,
			"built": false, "infl": 0, "winter": {}, "ach_bonus": 0,
		})
	# mazzo Invasori: una carta a caso per ogni anno
	deck.clear()
	deck2.clear()
	for y in range(1, 6):
		var pool := _year_cards(y)
		deck.append(pool[rng.randi_range(0, pool.size() - 1)])
		deck2.append(-1)
	order = range(n)
	_shuffle(order)
	dummy_colors.clear()
	for c in D.COLORS:
		var used := false
		for p in players:
			if p["color"] == c["id"]:
				used = true
		if not used:
			dummy_colors.append(c["key"])
	# carte Fato
	fate_deck.clear()
	if mods.get("fate", false):
		fate_deck = range(D.FATE.size())
		_shuffle(fate_deck)
	# Capricci
	cap_pile.clear()
	cap_tiles.clear()
	if mods.get("capricci", false):
		cap_pile = range(1, 17)
		_shuffle(cap_pile)
		if mods.get("restaurazione", false):
			for k in cap_pile:
				_place_capriccio(k)
			cap_pile.clear()
	# Governatori: carte distribuite (la scelta avviene all'inizio della partita)
	if mods.get("gov", false):
		var gp: Array = range(D.GOVERNORS.size())
		if n == 2:
			gp.erase(_gov_index("duca"))
		_shuffle(gp)
		if mods.get("gov_auction", false):
			gov_pool = gp.slice(0, n + 1)
		else:
			for p in players:
				p["gov_opts"] = gp.slice(0, 3)
				gp = gp.slice(3)
	# linee alternative: pescate a caso (o scelte a turno all'inizio della partita)
	if mods.get("alt", false) and not mods.get("alt_draft", false):
		var pool2 := _alt_pool()
		_shuffle(pool2)
		for p in players:
			var a1: String = pool2.pop_back()
			var j := pool2.size() - 1
			while j >= 0 and pool2[j] == a1:
				j -= 1
			var a2: String = a1
			if j >= 0:
				a2 = pool2[j]
				pool2.remove_at(j)
			p["alt_opts"] = [a1, a2] if a2 != a1 else [a1]
	year = 1
	phase = 0
	envoy = -1
	last_year = 5
	log_lines.clear()
	game_over = false
	results.clear()


func _year_cards(y: int) -> Array:
	var pool := []
	for k in range(D.INVADERS.size()):
		if D.INVADERS[k]["year"] == y:
			pool.append(k)
	return pool


func _alt_pool() -> Array:
	var out := []
	for L in ["A", "B", "C", "D", "E", "F", "G"]:
		if (L == "A" or L == "G") and not mods.get("lines", false):
			continue
		out.append(L)
		out.append(L)
	return out


func _base_lines() -> Array:
	var out := []
	var rows := ["A", "B", "C", "D", "E", "F", "G"] if mods.get("lines", false) else ["B", "C", "D", "E", "F"]
	for L in rows:
		out.append(D.LINES[L].duplicate())
	return out


func _empty_bld() -> Array:
	var a := []
	for i in range(D.N_BUILDINGS):
		a.append(false)
	return a


func _gov_index(key: String) -> int:
	for i in range(D.GOVERNORS.size()):
		if D.GOVERNORS[i]["key"] == key:
			return i
	return -1


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
	if log_lines.size() > 500:
		log_lines.pop_front()
	log_added.emit(t)


func has_b(seat: int, b: int) -> bool:
	return players[seat]["bld"][b]


func gov(seat: int) -> String:
	var g: int = players[seat]["gov"]
	return D.GOVERNORS[g]["key"] if g >= 0 else ""


func n_bld(seat: int) -> int:
	var c := 0
	for x in players[seat]["bld"]:
		if x:
			c += 1
	return c


func n_goods(seat: int) -> int:
	var g: Dictionary = players[seat]["goods"]
	return g["g"] + g["w"] + g["s"]


func fate(key: String) -> bool:
	return fate_key == key


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


## Posto alla sinistra (successivo) e alla destra (precedente) nell'ordine dei posti.
func left_of(s: int) -> int:
	return (s + 1) % n


func right_of(s: int) -> int:
	return (s - 1 + n) % n


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


## Scelta fra opzioni: restituisce l'indice (0 se la risposta non è valida).
func pick(seat: int, ctx: String, title: String, options: Array, extra := {}) -> int:
	var req := {"type": "pick", "ctx": ctx, "title": title, "options": options}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	return clampi(int(c) if (c is int or c is float) else 0, 0, options.size() - 1)


func yesno(seat: int, ctx: String, title: String, yes_val := {}, no_label := "No", yes_label := "Sì") -> bool:
	var i := await pick(seat, ctx, title, [{"label": no_label, "val": {}}, {"label": yes_label, "val": yes_val}])
	return i == 1


func choose_goods(seat: int, nn: int, title: String, ctx := "", extra := {}) -> Dictionary:
	var req := {"type": "goods", "n": nn, "title": title, "ctx": ctx}
	for k in extra:
		req[k] = extra[k]
	var r = await decide(seat, req)
	return _sanitize_goods(r, nn)


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
	await _game_setup()
	if abort: return
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
		await _end_of_year()
		if abort: return
		if y >= last_year:
			break
	await _final_scoring()


func _set_phase(ph: int) -> void:
	phase = ph
	season = -1
	step = ""
	phase_changed.emit(year, ph)
	log_msg("[b]Anno %s · %s[/b]" % [D.ROMAN[year], D.PHASE_NAMES[ph]])
	changed.emit()


## Scelte iniziali dei moduli: Governatori e linee di edifici alternative.
func _game_setup() -> void:
	step = "setup"
	if mods.get("gov", false):
		if mods.get("gov_auction", false):
			await _gov_auction()
		else:
			# scelte segrete: si rivelano tutte insieme
			var picks := {}
			for s in order:
				var opts: Array = players[s]["gov_opts"]
				var r = await decide(s, {"type": "gov", "options": opts, "title": "Scegli il tuo Governatore", "secret": true})
				picks[s] = int(r) if (r is int or r is float) and int(r) in opts else opts[0]
			for s in picks:
				players[s]["gov"] = picks[s]
			for s in order:
				log_msg("%s è governato dal %s." % [pname(s), D.GOVERNORS[players[s]["gov"]]["name"]])
		for s in range(n):
			await _gov_start(s)
	if mods.get("alt", false):
		if mods.get("alt_draft", false):
			await _alt_draft()
		for s in order:
			var opts2: Array = players[s]["alt_opts"]
			var r2 = await decide(s, {"type": "lines", "options": opts2, "title": "Linee di edifici alternative: quali usi?"})
			var use: Array = []
			if r2 is Array:
				for L in r2:
					if str(L) in opts2 and not str(L) in use:
						use.append(str(L))
			for L in use:
				_use_alt_line(s, L)
			if use.is_empty():
				log_msg("%s non usa linee alternative." % pname(s))
			else:
				log_msg("%s usa le linee alternative %s." % [pname(s), ", ".join(use)])
	setup_done = true
	changed.emit()


func _use_alt_line(s: int, L: String) -> void:
	var lines: Array = players[s]["lines"]
	for i in range(lines.size()):
		if lines[i] == D.LINES[L]:
			lines[i] = D.ALT_LINES[L].duplicate()
			return


func _alt_draft() -> void:
	var avail := _alt_pool()
	var seq := order.duplicate()
	var rev := order.duplicate()
	rev.reverse()
	for round_i in range(2):
		for s in (seq if round_i == 0 else rev):
			var opts := []
			for L in avail:
				if not L in opts and not L in players[s]["alt_opts"]:
					opts.append(L)
			if opts.is_empty():
				continue
			var r = await decide(s, {"type": "draft_line", "options": opts, "title": "Scegli una linea di edifici alternativa (%d di 2)" % (round_i + 1)})
			var L2: String = str(r) if str(r) in opts else opts[0]
			players[s]["alt_opts"].append(L2)
			avail.erase(L2)
			log_msg("%s prende la linea alternativa %s." % [pname(s), L2])
			changed.emit()


## Asta dei Governatori: si offre in PV, a turno.
func _gov_auction() -> void:
	var have := {}
	var opener_i := 0
	while have.size() < n:
		var bidders := []
		for k in range(n):
			var s: int = order[(opener_i + k) % n]
			if not have.has(s):
				bidders.append(s)
		var opener: int = bidders[0]
		if bidders.size() == 1:
			var r0 = await decide(opener, {"type": "gov", "options": gov_pool.duplicate(), "title": "Scegli il tuo Governatore (resti solo tu)"})
			var g0: int = int(r0) if (r0 is int or r0 is float) and int(r0) in gov_pool else gov_pool[0]
			_gov_take(opener, g0, 0)
			have[opener] = true
			break
		var r = await decide(opener, {"type": "gov", "options": gov_pool.duplicate(), "title": "Asta: scegli il Governatore da mettere all'asta", "auction": true})
		var g: int = int(r) if (r is int or r is float) and int(r) in gov_pool else gov_pool[0]
		var bid := await _ask_bid(opener, g, -1, true)
		var leader := opener
		var active := bidders.duplicate()
		var i := 1
		while active.size() > 1:
			var s2: int = active[i % active.size()]
			if s2 == leader:
				i += 1
				continue
			var b2 := await _ask_bid(s2, g, bid, false)
			if b2 > bid:
				bid = b2
				leader = s2
				log_msg("%s offre %d PV per il %s." % [pname(s2), bid, D.GOVERNORS[g]["name"]])
				i += 1
			else:
				active.erase(s2)
				log_msg("%s passa." % pname(s2))
			changed.emit()
		_gov_take(leader, g, bid)
		have[leader] = true
		opener_i += 1
	gov_pool.clear()


func _ask_bid(s: int, g: int, cur: int, opening: bool) -> int:
	var opts := []
	if not opening:
		opts.append({"label": "Passo", "val": {}, "bid": -1})
	for v in range(cur + 1, cur + 7):
		opts.append({"label": "Offro %d PV" % v, "val": {"vp": -v}, "bid": v})
	var title := "Asta per il %s: %s" % [D.GOVERNORS[g]["name"], ("offerta iniziale" if opening else "offerta attuale %d PV" % cur)]
	var i := await pick(s, "auction", title, opts, {"gov": g, "cur": cur})
	return int(opts[i]["bid"])


func _gov_take(s: int, g: int, bid: int) -> void:
	players[s]["gov"] = g
	gov_pool.erase(g)
	if bid > 0:
		_add_vp(s, -bid)
	log_msg("%s prende il %s%s." % [pname(s), D.GOVERNORS[g]["name"], (" pagando %d PV" % bid) if bid > 0 else ""])
	changed.emit()


func _gov_start(s: int) -> void:
	var p: Dictionary = players[s]
	match gov(s):
		"nobile":
			_add_vp(s, 6)
		"ladro":
			p["goods"]["g"] += 4
			_add_vp(s, -3)
		"principessa":
			envoy = s
			p["goods"]["g"] += 1
			_add_vp(s, 1)
		"ereditiera":
			p["heir"] = {"g": 2, "w": 1, "s": 1, "p2": 2}
		"paladino":
			p["paladin"] = true


# ------------------------------------------------------------------ fasi 1, 3, 5

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
	await _start_of_year()
	for p in players:
		p["aid_white"] = false
	var princess := -1
	for s in range(n):
		if gov(s) == "principessa":
			princess = s
	if year == 1 and princess >= 0:
		players[princess]["aid_white"] = true
		log_msg("Aiuto del Re: solo %s (Principessa) lancerà un dado bianco in più in Primavera." % pname(princess))
		changed.emit()
		return
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
				_gain_bundle(s, await choose_goods(s, 1, "Aiuto del Re: scegli una merce", "aid"), "Aiuto del Re")
	changed.emit()


## Inizio dell'anno: carta Fato, Damigella, Torre di Vedetta, Stregone, Accordi Segreti, Stelle.
func _start_of_year() -> void:
	marks.clear()
	stars.clear()
	if mods.get("fate", false) and not fate_deck.is_empty():
		fate_card = fate_deck.pop_back()
		fate_extra = -1
		var key: String = D.FATE[fate_card]["key"]
		if key == "perdurante":
			if fate_prev_key != "":
				key = fate_prev_key
				log_msg("Carta Fato: Situazione Perdurante, resta in vigore «%s»." % _fate_name(key))
			elif not fate_deck.is_empty():
				fate_extra = fate_deck.pop_back()
				key = D.FATE[fate_extra]["key"]
				log_msg("Carta Fato: Situazione Perdurante al primo anno, si pesca «%s»." % D.FATE[fate_extra]["name"])
		else:
			log_msg("Carta Fato: «%s»." % D.FATE[fate_card]["name"])
		fate_key = key
		fate_prev_key = key
		fx.emit("fate", {"card": fate_card})
		if key == "malato":
			king_sick += 1
			if king_sick >= 2:
				last_year = year
				log_msg("Il Re si è ammalato di nuovo: alla fine di quest'anno morirà e la partita terminerà.")
		if key == "tenaglia":
			var pool := _year_cards(year)
			pool.erase(deck[year - 1])
			deck2[year - 1] = pool[rng.randi_range(0, pool.size() - 1)]
		if key == "stelle":
			stars = {1: "g", 10: "g", 4: "w", 15: "w", 5: "s", 16: "s", 6: "p2", 13: "p2"}
		changed.emit()
		await pause_point({"type": "ack", "ctx": "fate", "card": fate_card})
	else:
		fate_key = ""
	for s in range(n):
		if gov(s) == "damigella":
			players[s]["p2"] += 1
			log_msg("%s: Damigella, +1 gettone +2." % pname(s))
		if has_b(s, D.B_VEDETTA) and year >= 4:
			await _peek(s, "Torre di Vedetta")
		if gov(s) == "stregone" and year == 3:
			await _stregone(s)
	if fate("accordi"):
		for s in order:
			var opts: Array = range(1, 19)
			var r = await decide(s, {"type": "mark", "options": opts, "title": "Accordi Segreti: metti il tuo segnalino su un Consigliere"})
			var a: int = int(r) if (r is int or r is float) and int(r) in opts else 18
			if not marks.has(a):
				marks[a] = []
			marks[a].append(s)
			log_msg("%s mette il suo segnalino su %s (%d)." % [pname(s), D.ADVISORS[a]["name"], a])
			changed.emit()


func _fate_name(key: String) -> String:
	for f in D.FATE:
		if f["key"] == key:
			return f["name"]
	return key


func _stregone(s: int) -> void:
	for k in range(3):
		var opts := []
		for line in players[s]["lines"]:
			if not has_b(s, line[0]):
				opts.append(line[0])
		if opts.is_empty():
			return
		var labels := [{"label": "Basta così", "val": {}}]
		for b in opts:
			labels.append({"label": "%s (gratis, senza PV)" % D.BUILDINGS[b]["name"], "val": {"bld": b}, "b": b})
		var i := await pick(s, "stregone", "Stregone: costruisci gratis un edificio della prima colonna (%d di 3)" % (k + 1), labels)
		if i == 0:
			return
		var b2: int = labels[i]["b"]
		players[s]["bld"][b2] = true
		log_msg("%s (Stregone) costruisce gratis: %s." % [pname(s), D.BUILDINGS[b2]["name"]])
		fx.emit("build", {"seat": s, "b": b2})
		changed.emit()


func phase_3() -> void:
	_set_phase(3)
	if fate("cattivoumore"):
		log_msg("Premio del Re annullato: il Re è di cattivo umore.")
		return
	var bonus := 2 if fate("buonumore") else 1
	var mx := 0
	for p in players:
		mx = maxi(mx, n_bld(p["seat"]))
	if mx == 0:
		log_msg("Premio del Re: nessuno ha ancora costruito.")
		return
	for p in players:
		if n_bld(p["seat"]) == mx:
			_add_vp(p["seat"], bonus)
			log_msg("Premio del Re: %s (+%d PV, %d edifici)." % [pname(p["seat"]), bonus, mx])
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
		p["built"] = false
		p["infl"] = 0
	step = "roll"
	# Capricci: una nuova tessera a ogni stagione
	if mods.get("capricci", false) and not mods.get("restaurazione", false) and not cap_pile.is_empty():
		var k: int = cap_pile.pop_back()
		_place_capriccio(k)
		log_msg("Capriccio a corte: %s (%d) ora dà «%s»" % [D.ADVISORS[k]["name"], k, D.CAPRICCI[k]])
		fx.emit("capriccio", {"adv": k})
	# carte Fato: nuove risorse scoperte
	for f in [["foresta", "w", "Legno"], ["miniera", "g", "Oro"], ["cava", "s", "Pietra"]]:
		if fate(f[0]):
			var d := _d6()
			if d >= 4:
				for p in players:
					p["goods"][f[1]] += 1
				log_msg("%s: il dado fa %d, tutti ricevono 1 %s." % [_fate_name(f[0]), d, f[2]])
			else:
				log_msg("%s: il dado fa %d, niente questa volta." % [_fate_name(f[0]), d])
	# Sacerdote: benedizione divina
	var blessing := false
	for s in order:
		if gov(s) == "sacerdote":
			blessing = await yesno(s, "blessing", "Sacerdote: invochi la benedizione divina? (chi non tirerebbe dadi bianchi ne tira uno, gli altri ricevono 1 PV)")
			if blessing:
				log_msg("%s invoca la benedizione divina." % pname(s))
	# a) dadi
	for s in range(n):
		if has_b(s, D.B_GILDA_MERC):
			players[s]["goods"]["g"] += 1
			log_msg("%s: Gilda dei Mercanti, +1 Oro." % pname(s))
	for s in order:
		if has_b(s, D.B_PORTO):
			_gain_bundle(s, await choose_goods(s, 1, "Porto: scegli una merce", "porto"), "Porto")
	var prosper_gain := []
	for s in range(n):
		var p: Dictionary = players[s]
		var whites := 0
		if has_b(s, D.B_FATTORIE):
			whites += 1
		if si == 0 and p["aid_white"]:
			whites += 1
		if si == 2 and has_b(s, D.B_VIGNE):
			whites += 1
		if si == 1 and gov(s) == "fata":
			whites += 1
		var base_whites := whites
		if fate("prospero"):
			if base_whites == 0:
				whites += 1
			else:
				prosper_gain.append(s)
		if blessing:
			if base_whites == 0:
				whites += 1
			else:
				_add_vp(s, 1)
				log_msg("%s: benedizione divina, +1 PV." % pname(s))
		var colored := 2 if (si == 2 and fate("carestia")) else 3
		for k in range(colored):
			p["dice"].append({"v": _roll(s, false), "white": false, "used": false})
		for k in range(whites):
			p["dice"].append({"v": _roll(s, true), "white": true, "used": false})
	for s in order:
		if s in prosper_gain:
			_gain_bundle(s, await choose_goods(s, 1, "Anno Prospero: scegli una merce", "prospero"), "Anno Prospero")
	fx.emit("roll", {})
	changed.emit()
	# rilanci e trasformazioni dei dadi, nell'ordine di gioco attuale
	for s in order:
		await _dice_abilities(s)
	# effetti che dipendono dai dadi definitivi
	for s in order:
		await _after_dice(s)
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
	while guard < 300:
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
	# Duca: dadi spostati sulla Nobildonna
	for s in order:
		if gov(s) == "duca" and not is_taken(12):
			var mine := []
			for a in adv:
				if adv[a]["seat"] == s and a > 12 and a <= 18:
					mine.append(a)
			if not mine.is_empty():
				mine.sort()
				var from: int = mine[mine.size() - 1]
				if await yesno(s, "duca", "Duca: sposti i tuoi dadi da %s (%d) alla Nobildonna (12)?" % [D.ADVISORS[from]["name"], from]):
					adv[12] = adv[from]
					adv.erase(from)
					log_msg("%s (Duca) sposta i suoi dadi da %s alla Nobildonna." % [pname(s), D.ADVISORS[from]["name"]])
					changed.emit()
	# c) aiuto dei Consiglieri
	step = "rewards"
	changed.emit()
	for a in range(1, 19):
		if adv.has(a):
			await _reward(adv[a]["seat"], a)
		if adv_extra.has(a):
			await _reward(adv_extra[a], a)
		if a == 5 or a == 10:
			var slot := POL5 if a == 5 else POL10
			if adv.has(slot):
				await _politico_reward(adv[slot]["seat"], slot)
	# d) costruzione
	step = "build"
	for s in order:
		await _build_turn(s)
	# fine stagione
	step = "end"
	for s in order:
		await _end_of_season(s, si)
	await _fate_end_of_season(si)
	if mods.get("restaurazione", false) and not cap_tiles.is_empty():
		_restaurazione_remove()
	adv.clear()
	adv_extra.clear()
	blocked.clear()
	for p in players:
		p["dice"] = []
	season = -1
	changed.emit()


func _d6() -> int:
	return rng.randi_range(1, 6)


## Tiro di un dado di un giocatore (Consiglieri Snob, Sacerdote).
func _roll(s: int, white: bool) -> int:
	var v := _d6()
	if white and gov(s) == "sacerdote" and v <= 2:
		_add_vp(s, 1)
		log_msg("%s (Sacerdote): dado bianco %d, +1 PV." % [pname(s), v])
	if fate("snob"):
		if v == 6:
			v = 4
		elif v == 5:
			v = 3
	return v


func dice_sum(seat: int) -> int:
	var t := 0
	for d in players[seat]["dice"]:
		t += int(d["v"])
	return t


func _reroll_all(s: int) -> void:
	for d in players[s]["dice"]:
		d["v"] = _roll(s, d["white"])


## Statua, Cappella, Altare, Filosofo, Principe: ognuno una volta a stagione, nell'ordine che si vuole.
func _dice_abilities(s: int) -> void:
	var p: Dictionary = players[s]
	var phil_before := -1
	var last := ""
	for attempt in range(8):
		var opts := [{"label": "Nessun altro effetto", "val": {}, "k": ""}]
		if has_b(s, D.B_STATUA) and not p["used"].get("statue", false) and _all_same(s):
			opts.append({"label": "Statua: rilancia un dado (tutti uguali)", "val": {}, "k": "statue"})
		if has_b(s, D.B_CAPPELLA) and not p["used"].get("chapel", false) and dice_sum(s) <= 7:
			opts.append({"label": "Cappella: rilancia tutti i dadi (somma %d)" % dice_sum(s), "val": {}, "k": "chapel"})
		if has_b(s, D.B_ALTARE) and not p["used"].get("altar", false) and dice_sum(s) <= 9:
			opts.append({"label": "Altare: rilancia tutti i dadi (somma %d)" % dice_sum(s), "val": {}, "k": "altar"})
		if gov(s) == "filosofo" and not p["used"].get("phil", false) and dice_sum(s) <= 10:
			opts.append({"label": "Filosofo: rilancia tutti i dadi (somma %d)" % dice_sum(s), "val": {}, "k": "phil"})
		if gov(s) == "principe" and not p["used"].get("prince", false) and dice_sum(s) <= 8:
			opts.append({"label": "Principe: i dadi colorati diventano 3, 4 e 6 (somma %d)" % dice_sum(s), "val": {}, "k": "prince"})
		if opts.size() == 1:
			break
		var k := ""
		if opts.size() == 2 and opts[1]["k"] == "statue":
			var r = await decide(s, {"type": "reroll_statue", "title": "Statua: tutti i dadi uguali. Vuoi rilanciarne uno?"})
			var idx := int(r) if (r is int or r is float) else -1
			p["used"]["statue"] = true
			if idx >= 0 and idx < p["dice"].size():
				var old: int = p["dice"][idx]["v"]
				p["dice"][idx]["v"] = _roll(s, p["dice"][idx]["white"])
				log_msg("%s rilancia un dado con la Statua: %d → %d." % [pname(s), old, p["dice"][idx]["v"]])
				fx.emit("roll", {"seat": s})
				last = "statue"
				changed.emit()
				continue
			break
		var i := await pick(s, "dice", "Dadi: %s · somma %d. Vuoi usare un effetto?" % [_dice_text(s), dice_sum(s)], opts, {"dice": true})
		k = opts[i]["k"]
		if k == "":
			break
		match k:
			"statue":
				p["used"]["statue"] = true
				var r2 = await decide(s, {"type": "reroll_statue", "title": "Statua: scegli il dado da rilanciare"})
				var idx2 := int(r2) if (r2 is int or r2 is float) else 0
				idx2 = clampi(idx2, 0, p["dice"].size() - 1)
				var old2: int = p["dice"][idx2]["v"]
				p["dice"][idx2]["v"] = _roll(s, p["dice"][idx2]["white"])
				log_msg("%s rilancia un dado con la Statua: %d → %d." % [pname(s), old2, p["dice"][idx2]["v"]])
			"chapel":
				p["used"]["chapel"] = true
				_reroll_all(s)
				log_msg("%s rilancia tutti i dadi con la Cappella: somma %d." % [pname(s), dice_sum(s)])
			"altar":
				p["used"]["altar"] = true
				_reroll_all(s)
				log_msg("%s rilancia tutti i dadi con l'Altare: somma %d." % [pname(s), dice_sum(s)])
			"phil":
				p["used"]["phil"] = true
				phil_before = dice_sum(s)
				_reroll_all(s)
				log_msg("%s (Filosofo) rilancia tutti i dadi: somma %d." % [pname(s), dice_sum(s)])
			"prince":
				p["used"]["prince"] = true
				var vals := [3, 4, 6]
				var col := []
				for d in p["dice"]:
					if not d["white"]:
						col.append(d)
				if col.size() == 2:
					vals = [4, 6]
				for j in range(mini(col.size(), vals.size())):
					col[j]["v"] = vals[j]
				log_msg("%s (Principe) trasforma i dadi colorati: somma %d." % [pname(s), dice_sum(s)])
		last = k
		fx.emit("roll", {"seat": s})
		changed.emit()
	if last == "phil" and phil_before >= 0 and dice_sum(s) < phil_before:
		_add_vp(s, 1)
		log_msg("%s (Filosofo): il nuovo totale è più basso, +1 PV." % pname(s))


func _dice_text(s: int) -> String:
	return "-".join(players[s]["dice"].map(func(d): return str(d["v"]) + ("b" if d["white"] else "")))


func _after_dice(s: int) -> void:
	var p: Dictionary = players[s]
	var sm := dice_sum(s)
	if has_b(s, D.B_GRIFONI) and sm <= 9:
		p["sol"] += 1
		log_msg("%s: Allevamento Grifoni, +1 soldato." % pname(s))
	if has_b(s, D.B_UNIVERSITA) and sm <= 9:
		_add_vp(s, 2)
		log_msg("%s: Università, +2 PV." % pname(s))
	if gov(s) == "ereditiera":
		var one := false
		for d in p["dice"]:
			if not d["white"] and d["v"] == 1:
				one = true
		if one:
			var h: Dictionary = p["heir"]
			var opts := [{"label": "Niente", "val": {}, "k": ""}]
			var any_left := false
			for t in ["g", "w", "s", "p2"]:
				if h.get(t, 0) > 0:
					any_left = true
					opts.append({"label": "Prendi 1 %s" % ("gettone +2" if t == "p2" else D.GOOD_NAMES[t]), "val": {t: 1}, "k": t})
			if not any_left:
				_add_vp(s, 1)
				log_msg("%s (Ereditiera): la carta è vuota, +1 PV." % pname(s))
			else:
				var i := await pick(s, "heir", "Ereditiera: hai un 1 su un dado colorato. Prendi qualcosa dalla carta?", opts)
				var t2: String = opts[i]["k"]
				if t2 != "":
					h[t2] -= 1
					_gain_bundle(s, {t2: 1}, "Ereditiera")
	changed.emit()


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


## Il giocatore può influenzare questo Consigliere (Re malato, Accordi Segreti)?
func adv_allowed(seat: int, a: int) -> bool:
	if a > 100:
		return gov(seat) == "politico" and not adv.has(a)
	if a == 18 and fate("malato"):
		return false
	if marks.has(a) and not seat in marks[a]:
		return false
	return true


## Tutte le mosse legali: {"adv", "dice":[indici], "p2":0|1, "pv":valore del gettone, "mk":-1|0|1, "env":bool, "it":bool}
func legal_moves(seat: int) -> Array:
	var p: Dictionary = players[seat]
	var free := free_dice(seat)
	var out := []
	if free.is_empty():
		return out
	var multi_p2 := gov(seat) == "damigella"
	var can_p2: bool = p["p2"] > 0 and (multi_p2 or not p["used"].get("p2", false))
	var p2vals := [2]
	if gov(seat) == "truffatore":
		p2vals = [1, 2, 3]
	var can_mk: bool = has_b(seat, D.B_MERCATO) and not p["used"].get("market", false)
	var can_it: bool = has_b(seat, D.B_MERC_ITIN) and not p["used"].get("itin", false)
	var can_env: bool = envoy == seat
	var seen := {}
	var m := free.size()
	var targets := range(1, 19)
	if gov(seat) == "politico":
		targets.append(POL5)
		targets.append(POL10)
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
		var combos := [[0, 0]]
		if can_p2:
			for pv in p2vals:
				combos.append([1, pv])
		for cb in combos:
			for mk in ([0, -1, 1] if can_mk else [0]):
				var a: int = tot + cb[1] + mk
				if a == 5 or a == 10:
					if gov(seat) == "politico" and adv_allowed(seat, POL5 if a == 5 else POL10):
						_add_move(out, seen, {"adv": POL5 if a == 5 else POL10, "dice": idx, "p2": cb[0], "pv": cb[1], "mk": mk, "env": false, "it": false})
				if a < 1 or a > 18 or not adv_allowed(seat, a):
					continue
				var env := false
				if is_taken(a):
					if not can_env or adv_extra.has(a):
						continue
					env = true
				_add_move(out, seen, {"adv": a, "dice": idx, "p2": cb[0], "pv": cb[1], "mk": mk, "env": env, "it": false})
		# Mercato Itinerante: un solo dado colorato su un Consigliere da 1 a 6
		if can_it and idx.size() == 1 and colored:
			for a2 in range(1, 7):
				if a2 == tot or not adv_allowed(seat, a2):
					continue
				var env2 := false
				if is_taken(a2):
					if not can_env or adv_extra.has(a2):
						continue
					env2 = true
				_add_move(out, seen, {"adv": a2, "dice": idx, "p2": 0, "pv": 0, "mk": 0, "env": env2, "it": true})
	return out


func _add_move(out: Array, seen: Dictionary, mv: Dictionary) -> void:
	var key := "%d|%s|%d|%d|%d|%s|%s" % [mv["adv"], str(mv["dice"]), mv["p2"], mv["pv"], mv["mk"], mv["env"], mv["it"]]
	if seen.has(key):
		return
	seen[key] = true
	out.append(mv)


func _match_move(r, moves: Array) -> Dictionary:
	if not (r is Dictionary) or r.get("pass", false):
		return {}
	for mv in moves:
		if int(mv["adv"]) == int(r.get("adv", -1)) and int(mv["p2"]) == int(r.get("p2", 0)) and int(mv["pv"]) == int(r.get("pv", mv["pv"])) \
				and int(mv["mk"]) == int(r.get("mk", 0)) and bool(mv["env"]) == bool(r.get("env", false)) and bool(mv["it"]) == bool(r.get("it", false)):
			var a: Array = mv["dice"].duplicate()
			var b: Array = []
			for x in r.get("dice", []):
				b.append(int(x))
			a.sort()
			b.sort()
			if a == b:
				return mv
	return {}


func adv_name(a: int) -> String:
	if a == POL5:
		return "Politico (5)"
	if a == POL10:
		return "Politico (10)"
	return "%s (%d)" % [D.ADVISORS[a]["name"], a]


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
	if mv["it"]:
		p["used"]["itin"] = true
	var a: int = mv["adv"]
	var extra := ""
	if mv["p2"] > 0:
		extra += " %+d (gettone)" % mv["pv"]
	if mv["mk"] != 0:
		extra += " (Mercato %+d)" % mv["mk"]
	if mv["it"]:
		extra += " (Mercato Itinerante)"
	var dt := "+".join(vals.map(func(x): return str(x)))
	if mv["env"]:
		adv_extra[a] = seat
		envoy = -1
		log_msg("%s usa l'Agente del Re e influenza anche lui %s con %s%s." % [pname(seat), adv_name(a), dt, extra])
	else:
		adv[a] = {"seat": seat, "dice": vals, "white": whites, "p2": mv["p2"], "mk": mv["mk"], "pv": mv["pv"], "it": mv["it"]}
		log_msg("%s influenza %s con %s%s." % [pname(seat), adv_name(a), dt, extra])
	if a <= 18:
		p["infl"] += 1
	if stars.has(a):
		var t: String = stars[a]
		stars.erase(a)
		_gain_bundle(seat, {t: 1}, "Stelle in Ascesa")
	fx.emit("place", {"seat": seat, "adv": a})


# ------------------------------------------------------------------ ricompense

func _reward(s: int, a: int) -> void:
	if cap_tiles.has(a):
		await _capriccio_reward(s, a)
		return
	var r: Dictionary = D.ADVISORS[a]["r"]
	var nm: String = D.ADVISORS[a]["name"]
	var p: Dictionary = players[s]
	var got := {}
	for t in D.GOODS:
		if r.get(t, 0) > 0:
			got[t] = r[t]
	if r.has("or"):
		var opts: Array = r["or"]
		var ci := await pick(s, "adv%d" % a, "%s: scegli" % nm, opts.map(func(o): return {"label": D.bundle_text(o), "val": o}), {"adv": a})
		for t in opts[ci]:
			got[t] = got.get(t, 0) + opts[ci][t]
	if r.get("any", 0) > 0:
		var gs := await choose_goods(s, r["any"], "%s: scegli %d merc%s" % [nm, r["any"], "e" if r["any"] == 1 else "i"], "adv%d" % a, {"adv": a})
		for t in gs:
			got[t] = got.get(t, 0) + gs[t]
	if r.has("alch"):
		var have := []
		for t in D.GOODS:
			if p["goods"][t] > 0:
				have.append(t)
		if not have.is_empty():
			var opts2 := [{"label": "Non scambiare", "val": {}, "k": ""}]
			for t in have:
				var others := D.GOODS.filter(func(x): return x != t)
				var v := {t: -1, others[0]: 1, others[1]: 1}
				opts2.append({"label": "Cedi 1 %s → 1 %s e 1 %s" % [D.GOOD_NAMES[t], D.GOOD_NAMES[others[0]], D.GOOD_NAMES[others[1]]], "val": v, "k": t})
			var ci3 := await pick(s, "alch", "Alchimista: vuoi scambiare una merce?", opts2, {"adv": a})
			var give: String = opts2[ci3]["k"]
			if give != "" and p["goods"][give] > 0:
				p["goods"][give] -= 1
				for t in D.GOODS:
					if t != give:
						got[t] = got.get(t, 0) + 1
				log_msg("%s: l'Alchimista trasforma 1 %s." % [pname(s), D.GOOD_NAMES[give]])
	if r.has("spy"):
		if await yesno(s, "spy", "Spia: paghi 1 PV per 3 merci a scelta?", {"vp": -1, "any": 3}, "No", "Sì, pago 1 PV"):
			_add_vp(s, -1)
			var gs5 := await choose_goods(s, 3, "Spia: scegli 3 merci", "spy", {"adv": a})
			for t in gs5:
				got[t] = got.get(t, 0) + gs5[t]
	if r.get("vp", 0) > 0:
		got["vp"] = r["vp"]
	if r.get("sol", 0) > 0:
		got["sol"] = r["sol"]
	if r.get("p2", 0) > 0:
		got["p2"] = r["p2"]
	_soldier_bonus(s, a, got)
	_gain_bundle(s, got, nm)
	if r.get("peek", false):
		await _peek(s, nm)
	changed.emit()


## Scuderia e Chiamata alle Armi.
func _soldier_bonus(s: int, a: int, got: Dictionary) -> void:
	var stable := has_b(s, D.B_SCUDERIA)
	if got.get("sol", 0) > 0 and stable:
		got["sol"] += 1
	if fate("chiamata"):
		if not stable and got.get("sol", 0) > 0:
			got["sol"] += 1
		elif stable and a >= 11 and a <= 18:
			got["sol"] = got.get("sol", 0) + 1


func _politico_reward(s: int, slot: int) -> void:
	if slot == POL5:
		var opts := [{"label": "1 merce a scelta", "val": {"any": 1}}, {"label": "2 gettoni +2", "val": {"p2": 2}}]
		var i := await pick(s, "pol5", "Politico (5): scegli", opts)
		if i == 0:
			_gain_bundle(s, await choose_goods(s, 1, "Politico: scegli una merce", "pol5"), "Politico")
		else:
			_gain_bundle(s, {"p2": 2}, "Politico")
	else:
		var gs := await choose_goods(s, 1, "Politico (10): scegli una merce", "pol10")
		gs["p2"] = 1
		gs["vp"] = 1
		_gain_bundle(s, gs, "Politico")
	changed.emit()


## Guardare la carta Invasori dell'anno (Generale, Regina, Torre di Vedetta, Capriccio 13).
func _peek(s: int, why: String) -> void:
	if fate("nebbia"):
		_gain_bundle(s, {"p2": 1}, "%s (Nebbia di Guerra, al posto di guardare gli Invasori)" % why)
		return
	var card: int = deck[year - 1]
	if deck2[year - 1] >= 0:
		var c2: int = deck2[year - 1]
		var i := await pick(s, "peek2", "Manovra a Tenaglia: quale carta Invasori guardi?", [{"label": "Quella sul tabellone", "val": {}}, {"label": "Quella aggiunta sotto", "val": {}}])
		card = c2 if i == 1 else card
	var known: Array = players[s]["known"].get(year, [])
	if not card in known:
		known.append(card)
	players[s]["known"][year] = known
	log_msg("%s guarda una carta Invasori (%s)." % [pname(s), why])
	fx.emit("peek", {"seat": s, "card": card})


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
		p["goods"][t] = maxi(0, p["goods"][t] + b.get(t, 0))
	if b.get("vp", 0) != 0:
		_add_vp(s, b["vp"])
	if b.get("sol", 0) != 0:
		p["sol"] = maxi(0, p["sol"] + b["sol"])
	if b.get("p2", 0) != 0:
		p["p2"] = maxi(0, p["p2"] + b["p2"])
	var txt := D.bundle_text(b)
	if txt != "":
		log_msg("%s: %s → %s." % [pname(s), why, txt])
	fx.emit("gain", {"seat": s, "b": b})


func _add_vp(s: int, v: int) -> void:
	players[s]["vp"] += v


# ------------------------------------------------------------------ Capricci

func _place_capriccio(k: int) -> void:
	cap_tiles[k] = true
	cap_last = k
	if k == 4:
		cap4 = {"g": 1, "w": 1, "s": 1}
	if k == 5:
		cap5 = D.GOODS[rng.randi_range(0, 2)]


func _restaurazione_remove() -> void:
	var influenced := []
	for k in cap_tiles:
		if adv.has(k) or adv_extra.has(k) or blocked.has(k):
			influenced.append(k)
	var rem := -1
	if not influenced.is_empty():
		influenced.sort()
		rem = influenced[influenced.size() - 1]
	else:
		var ks := cap_tiles.keys()
		ks.sort()
		rem = ks[0]
	cap_tiles.erase(rem)
	log_msg("Restaurazione: torna la ricompensa originale di %s (%d)." % [D.ADVISORS[rem]["name"], rem])


func _others(s: int) -> Array:
	var out := []
	for k in range(n):
		if k != s:
			out.append(k)
	return out


func _capriccio_reward(s: int, a: int) -> void:
	var p: Dictionary = players[s]
	var why := "Capriccio %d" % a
	var got := {}
	match a:
		1:
			var target := -1
			for k in range(2, 19):
				if not is_taken(k) and not adv_extra.has(k):
					target = k
					break
			if target < 0:
				log_msg("%s: tutti i Consiglieri sono stati influenzati, nessuna ricompensa." % why)
				return
			log_msg("%s: %s riceve la ricompensa di %s (%d)." % [why, pname(s), D.ADVISORS[target]["name"], target])
			await _reward(s, target)
			return
		2:
			var opts := [{"label": "2 gettoni +2", "val": {"p2": 2}}]
			if p["p2"] > 0:
				opts.append({"label": "Paga 1 gettone +2 per 1 Oro e 1 soldato", "val": {"p2": -1, "g": 1, "sol": 1}})
			got = opts[await pick(s, "cap2", "%s: scegli" % why, opts)]["val"].duplicate()
		3:
			var t := await _hostile_good(left_of(s), s, "%s: scegli la merce che %s riceverà" % [why, pname(s)])
			got = {t: 1}
		4:
			var opts4 := []
			for t in D.GOODS:
				if cap4[t] > 0:
					opts4.append({"label": "1 %s" % D.GOOD_NAMES[t], "val": {t: 1}, "k": t})
			var t4: String = opts4[await pick(s, "cap4", "%s: prendi una merce dalla tessera" % why, opts4)]["k"]
			cap4[t4] -= 1
			got = {t4: 1}
			if cap4["g"] + cap4["w"] + cap4["s"] == 0:
				cap4 = {"g": 1, "w": 1, "s": 1}
		5:
			got = {cap5: 1}
			cap5 = D.GOODS[rng.randi_range(0, 2)]
		6:
			var opts6 := [{"label": "Niente", "val": {}}]
			if n_goods(s) > 0:
				opts6.append({"label": "Paga 1 merce: 1 soldato e 1 PV", "val": {"any": -1, "sol": 1, "vp": 1}, "k": "goods"})
			opts6.append({"label": "Paga 1 PV: 1 soldato e 1 merce", "val": {"vp": -1, "sol": 1, "any": 1}, "k": "vp"})
			if p["sol"] > 0:
				opts6.append({"label": "Paga 1 soldato: 1 PV e 1 merce", "val": {"sol": -1, "vp": 1, "any": 1}, "k": "sol"})
			var i6 := await pick(s, "cap6", "%s: puoi fare uno scambio" % why, opts6)
			match str(opts6[i6].get("k", "")):
				"goods":
					var lose := await _choose_lose(s, 1, "%s: scegli la merce da pagare" % why)
					for t in D.GOODS:
						p["goods"][t] -= lose[t]
					got = {"sol": 1, "vp": 1}
				"vp":
					got = await choose_goods(s, 1, "%s: scegli la merce" % why, "cap6")
					got["vp"] = -1
					got["sol"] = 1
				"sol":
					got = await choose_goods(s, 1, "%s: scegli la merce" % why, "cap6")
					got["sol"] = -1
					got["vp"] = 1
		7:
			var other := await _choose_player(s, "%s: scegli un giocatore (riceve una merce a sua scelta, tu due uguali)" % why, "cap7")
			var g7 := await choose_goods(other, 1, "%s: %s ti fa scegliere una merce (lui ne riceverà due uguali)" % [why, pname(s)], "cap7o")
			_gain_bundle(other, g7, why)
			for t in D.GOODS:
				if g7[t] > 0:
					got[t] = 2
		8:
			var t8a := await _hostile_good(left_of(s), s, "%s: scegli una merce per %s" % [why, pname(s)])
			var t8b := await _hostile_good(right_of(s), s, "%s: scegli un'altra merce per %s" % [why, pname(s)])
			got = {t8a: 1}
			got[t8b] = got.get(t8b, 0) + 1
		9:
			var items := [["g", "1 Oro"], ["w", "1 Legno"], ["s", "1 Pietra"], ["sol", "1 soldato"], ["p2", "1 gettone +2"]]
			for k2 in range(2):
				var opts9 := []
				for it in items:
					if not got.has(it[0]):
						opts9.append({"label": it[1], "val": {it[0]: 1}, "k": it[0]})
				var i9 := await pick(s, "cap9", "%s: scegli (%d di 2)" % [why, k2 + 1], opts9)
				got[opts9[i9]["k"]] = 1
		10:
			var opts10 := [{"label": "2 Oro", "val": {"g": 2}}, {"label": "2 Legni", "val": {"w": 2}}, {"label": "2 Pietre", "val": {"s": 2}}]
			got = opts10[await pick(s, "cap10", "%s: scegli" % why, opts10)]["val"].duplicate()
		11:
			got = {"s": 1, "sol": 1, "vp": 1}
			var opts11 := [{"label": "Prendi 1 Pietra, 1 soldato e 1 PV", "val": got.duplicate()}]
			if _is_least(s, "goods"):
				opts11.append({"label": "Rinuncia al soldato per una Pietra in più", "val": {"s": 2, "vp": 1}})
				opts11.append({"label": "Rinuncia al PV per una Pietra in più", "val": {"s": 2, "sol": 1}})
			if _is_least(s, "sol"):
				opts11.append({"label": "Rinuncia alla Pietra per un soldato in più", "val": {"sol": 2, "vp": 1}})
				opts11.append({"label": "Rinuncia al PV per un soldato in più", "val": {"sol": 2, "s": 1}})
			if _is_least(s, "vp"):
				opts11.append({"label": "Rinuncia al soldato per un PV in più", "val": {"vp": 2, "s": 1}})
				opts11.append({"label": "Rinuncia alla Pietra per un PV in più", "val": {"vp": 2, "sol": 1}})
			got = opts11[await pick(s, "cap11", "%s: scegli" % why, opts11)]["val"].duplicate()
		12:
			var opts12 := [{"label": "3 Oro a te, 1 PV a ogni altro", "val": {"g": 3}}, {"label": "3 PV a te, 1 Oro a ogni altro", "val": {"vp": 3}}]
			var i12 := await pick(s, "cap12", "%s: scegli" % why, opts12)
			got = opts12[i12]["val"].duplicate()
			for o in _others(s):
				_gain_bundle(o, {"vp": 1} if i12 == 0 else {"g": 1}, why)
		13:
			got = await choose_goods(s, 1, "%s: scegli una merce" % why, "cap13")
			got["p2"] = 1
			got["vp"] = 1
			got["sol"] = 1
		14:
			var other14 := await _choose_player(s, "%s: scegli un giocatore (prende una cosa, tu le altre quattro)" % why, "cap14")
			var items14 := [["g", "1 Oro"], ["w", "1 Legno"], ["s", "1 Pietra"], ["p2", "1 gettone +2"], ["sol", "1 soldato"]]
			var opts14 := items14.map(func(it): return {"label": it[1], "val": {it[0]: 1}, "k": it[0]})
			var i14 := await pick(other14, "cap14o", "%s: %s ti fa scegliere una cosa per te (lui prende le altre)" % [why, pname(s)], opts14)
			var taken: String = opts14[i14]["k"]
			_gain_bundle(other14, {taken: 1}, why)
			for it in items14:
				if it[0] != taken:
					got[it[0]] = 1
		15:
			var pool := {"g": 2, "w": 2, "s": 2}
			var give := await _choose_lose_from(s, pool, 2, "%s: scegli le 2 merci da dare agli altri (tieni le altre 4)" % why)
			for t in D.GOODS:
				got[t] = pool[t] - give[t]
			var others := _others(s)
			for t in D.GOODS:
				for k3 in range(give[t]):
					var to: int = others[0]
					if others.size() > 1:
						to = await _choose_player(s, "%s: a chi dai 1 %s?" % [why, D.GOOD_NAMES[t]], "cap15")
					_gain_bundle(to, {t: 1}, "%s di %s" % [why, pname(s)])
		16:
			got = {"vp": 5}
	_soldier_bonus(s, a, got)
	_gain_bundle(s, got, why)
	if a == 13:
		await _peek(s, why)
	changed.emit()


func _is_least(s: int, what: String) -> bool:
	var mine := 0
	for k in range(n):
		var v := 0
		match what:
			"goods": v = n_goods(k)
			"sol": v = players[k]["sol"]
			"vp": v = players[k]["vp"]
		if k == s:
			mine = v
	for k in range(n):
		var v2 := 0
		match what:
			"goods": v2 = n_goods(k)
			"sol": v2 = players[k]["sol"]
			"vp": v2 = players[k]["vp"]
		if v2 < mine:
			return false
	return true


## Un avversario sceglie la merce che un altro giocatore riceverà.
func _hostile_good(chooser: int, target: int, title: String) -> String:
	if chooser == target:
		chooser = right_of(target)
	var opts := D.GOODS.map(func(t): return {"label": "1 %s" % D.GOOD_NAMES[t], "val": {t: 1}, "k": t})
	var i := await pick(chooser, "hostile", title, opts, {"target": target})
	return opts[i]["k"]


func _choose_player(s: int, title: String, ctx: String) -> int:
	var others := _others(s)
	if others.size() == 1:
		return others[0]
	var opts := others.map(func(o): return {"label": pname(o), "val": {}, "who": o})
	var i := await pick(s, ctx, title, opts)
	return opts[i]["who"]


func _choose_lose(s: int, k: int, title: String) -> Dictionary:
	return await _choose_lose_from(s, players[s]["goods"], k, title)


func _choose_lose_from(s: int, have: Dictionary, k: int, title: String) -> Dictionary:
	var r = await decide(s, {"type": "lose", "n": k, "title": title, "have": have.duplicate()})
	var lose := _sanitize_goods(r, k)
	for t in D.GOODS:
		if lose[t] > have[t]:
			return _auto_lose_from(have, k)
	return lose


# ------------------------------------------------------------------ costruzione

## Costo di un edificio per il giocatore: {"g","w","s"} dopo Argano, Falegnameria e carte Fato.
func building_cost(s: int, b: int) -> Dictionary:
	var c: Dictionary = D.BUILDINGS[b]["cost"].duplicate()
	for t in D.GOODS:
		c[t] = c.get(t, 0)
	var col := D.building_col(b)
	if has_b(s, D.B_ARGANO) and col >= 2 and c["g"] > 0:
		c["g"] -= 1
	if has_b(s, D.B_FALEGNAMERIA) and col >= 2 and c["w"] > 0:
		c["w"] -= 1
	if fate("riottosi"):
		c["g"] += 1
	if fate("urbanistica"):
		var tools := has_b(s, D.B_ARGANO) or has_b(s, D.B_FALEGNAMERIA)
		if not tools and col >= 2:
			c["g"] += 1
		elif tools and col <= 1:
			# una merce a scelta in meno: quella che manca di più
			var best := ""
			var short := -99
			for t in ["g", "w", "s"]:
				if c[t] > 0:
					var sh: int = c[t] - players[s]["goods"][t]
					if sh > short:
						short = sh
						best = t
			if best != "":
				c[best] -= 1
	return c


## Pagamento effettivo (Carpentiere e Scultore usano Legno o Pietra come Oro). {} se non può pagare.
func payment(s: int, cost: Dictionary) -> Dictionary:
	var g: Dictionary = players[s]["goods"]
	var pay := {"g": 0, "w": 0, "s": 0}
	for t in ["w", "s"]:
		if g[t] < cost.get(t, 0):
			return {}
		pay[t] = cost.get(t, 0)
	var need: int = cost.get("g", 0)
	var use_g := mini(need, g["g"])
	pay["g"] = use_g
	need -= use_g
	var subs := []
	if gov(s) == "carpentiere":
		subs.append("w")
	if gov(s) == "scultore":
		subs.append("s")
	for t in subs:
		var spare: int = g[t] - pay[t]
		var k := mini(need, spare)
		pay[t] += k
		need -= k
	if need > 0:
		return {}
	return pay


func can_afford(s: int, cost: Dictionary) -> bool:
	return not payment(s, cost).is_empty()


func line_of(s: int, b: int) -> Array:
	for line in players[s]["lines"]:
		if b in line:
			return line
	return []


func can_build(s: int, b: int) -> bool:
	if has_b(s, b):
		return false
	var line := line_of(s, b)
	if line.is_empty():
		return false
	for c in range(line.find(b)):
		if not has_b(s, line[c]):
			return false
	return can_afford(s, building_cost(s, b))


func buildable(s: int) -> Array:
	var out := []
	for line in players[s]["lines"]:
		for b in line:
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
	# Architetto: un edificio extra se un avversario ne ha di più
	if gov(s) == "architetto":
		var more := false
		for o in _others(s):
			if n_bld(o) > n_bld(s):
				more = true
		var opts3 := buildable(s)
		if more and not opts3.is_empty():
			var r3 = await decide(s, {"type": "build", "options": opts3, "second": true, "why": "Architetto"})
			var b3 := int(r3) if (r3 is int or r3 is float) else -1
			if b3 in opts3:
				log_msg("%s (Architetto) costruisce un edificio extra." % pname(s))
				_do_build(s, b3)
	# Agente del Re: un secondo edificio nella stessa stagione
	if envoy == s:
		var opts2 := buildable(s)
		if not opts2.is_empty():
			var r2 = await decide(s, {"type": "build", "options": opts2, "second": true, "why": "Agente del Re"})
			var b2 := int(r2) if (r2 is int or r2 is float) else -1
			if b2 in opts2:
				envoy = -1
				log_msg("%s usa l'Agente del Re per costruire un secondo edificio." % pname(s))
				_do_build(s, b2)
	# Esattore: merci per gli edifici della IV colonna costruiti dagli avversari
	for k in range(n):
		var pend: int = players[k].get("tax", 0)
		while pend > 0:
			pend -= 1
			_gain_bundle(k, await choose_goods(k, 1, "Esattore: un avversario ha costruito nella IV colonna, scegli una merce", "esattore"), "Esattore")
		players[k]["tax"] = 0


func _do_build(s: int, b: int) -> void:
	var c := building_cost(s, b)
	var pay := payment(s, c)
	for t in D.GOODS:
		players[s]["goods"][t] -= pay.get(t, 0)
	var arch := has_b(s, D.B_GILDA_ARCH)
	players[s]["bld"][b] = true
	players[s]["built"] = true
	var vp: int = D.BUILDINGS[b]["vp"]
	var extra := 0
	if arch and b != D.B_GILDA_ARCH:
		extra += 1
	if b == D.B_FONTANA and year <= 3:
		extra += 4 - year
	_add_vp(s, vp + extra)
	log_msg("%s costruisce: %s (%s)%s." % [pname(s), D.BUILDINGS[b]["name"], D.cost_text(pay), (", +%d PV" % (vp + extra)) if vp + extra > 0 else ""])
	if D.building_col(b) == 3:
		for k in _others(s):
			if gov(k) == "esattore":
				players[k]["tax"] = players[k].get("tax", 0) + 1
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
	if si == 1:
		for b in [D.B_GIOSTRA, D.B_CIRCO]:
			if has_b(s, b):
				_add_vp(s, 1)
				log_msg("%s: %s, +1 PV." % [pname(s), D.BUILDINGS[b]["name"]])
		if has_b(s, D.B_MONASTERO) and n_goods(s) == 0:
			_add_vp(s, 1)
			log_msg("%s: Monastero, +1 PV." % pname(s))
		if has_b(s, D.B_BIRRERIA) and p["sol"] > 0:
			p["sol"] -= 1
			_add_vp(s, 1)
			p["p2"] += 1
			log_msg("%s: Birreria, un soldato in meno, +1 PV e un gettone +2." % pname(s))
	if has_b(s, D.B_ARENA):
		var top := true
		for o in _others(s):
			if players[o]["sol"] > p["sol"]:
				top = false
		if top:
			_add_vp(s, 1)
			log_msg("%s: Arena, +1 PV." % pname(s))
	if has_b(s, D.B_PARCO) and p["infl"] >= 3:
		_add_vp(s, 1)
		log_msg("%s: Parco, +1 PV." % pname(s))
	# Segheria, Tagliapietre, Oreficeria (in Estate; con la Zecca anche in Primavera e Autunno)
	if si == 1 or has_b(s, D.B_ZECCA):
		if has_b(s, D.B_SEGHERIA) and p["goods"]["w"] > 0:
			if await yesno(s, "segheria", "Segheria: trasformi 1 Legno in 2 Oro?", {"w": -1, "g": 2}):
				_gain_bundle(s, {"w": -1, "g": 2}, "Segheria")
		if has_b(s, D.B_TAGLIAPIETRE) and p["goods"]["s"] > 0:
			if await yesno(s, "tagliapietre", "Tagliapietre: trasformi 1 Pietra in 3 Oro?", {"s": -1, "g": 3}):
				_gain_bundle(s, {"s": -1, "g": 3}, "Tagliapietre")
		if has_b(s, D.B_OREFICERIA) and p["goods"]["g"] > 0:
			if await yesno(s, "oreficeria", "Oreficeria: paghi 1 Oro per 1 PV e 1 soldato?", {"g": -1, "vp": 1, "sol": 1}):
				_gain_bundle(s, {"g": -1, "vp": 1, "sol": 1}, "Oreficeria")
	var diplo := fate("diplomatici")
	if has_b(s, D.B_MUNICIPIO):
		await _pay_for_vp(s, "Municipio", true, 1 + (1 if diplo else 0))
	if si == 2 and has_b(s, D.B_UFF_CAMBIO):
		await _pay_for_vp(s, "Ufficio del Cambio", false, 2 + (1 if diplo else 0))
	if diplo and not has_b(s, D.B_MUNICIPIO) and not has_b(s, D.B_UFF_CAMBIO):
		await _pay_for_vp(s, "Movimenti Diplomatici", true, 1)
	if si == 2 and has_b(s, D.B_CAMPO_ADD) and p["sol"] < 2:
		p["sol"] += 1
		log_msg("%s: Campo Addestramento, +1 soldato." % pname(s))
	if gov(s) == "predicatore":
		var someone := false
		for k in range(n):
			if not players[k]["built"]:
				someone = true
		if someone:
			_add_vp(s, 1)
			log_msg("%s (Predicatore): qualcuno non ha costruito, +1 PV." % pname(s))
	if gov(s) == "intrigante":
		var high := false
		for a in adv:
			if a >= 14 and a <= 18 and adv[a]["seat"] != s:
				high = true
		for a in adv_extra:
			if a >= 14 and adv_extra[a] != s:
				high = true
		if high:
			_add_vp(s, 1)
			log_msg("%s (Intrigante): un avversario ha influenzato un Consigliere da 14 in su, +1 PV." % pname(s))
	changed.emit()


## Paga un gettone +2 (se ammesso) o una merce per ricevere PV.
func _pay_for_vp(s: int, why: String, allow_p2: bool, vp: int) -> void:
	var p: Dictionary = players[s]
	var opts := [{"label": "Niente", "val": {}, "k": ""}]
	if allow_p2 and p["p2"] > 0:
		opts.append({"label": "Paga un gettone +2", "val": {"p2": -1, "vp": vp}, "k": "p2"})
	for t in D.GOODS:
		if p["goods"][t] > 0:
			opts.append({"label": "Paga 1 %s" % D.GOOD_NAMES[t], "val": {t: -1, "vp": vp}, "k": t})
	if opts.size() == 1:
		return
	var i := await pick(s, "payvp", "%s: paghi per %d PV?" % [why, vp], opts)
	var k: String = opts[i]["k"]
	if k == "":
		return
	if k == "p2":
		p["p2"] -= 1
	else:
		p["goods"][k] -= 1
	_add_vp(s, vp)
	log_msg("%s: %s, paga %s per %d PV." % [pname(s), why, ("un gettone +2" if k == "p2" else "1 " + D.GOOD_NAMES[k]), vp])


## Effetti delle carte Fato a fine stagione.
func _fate_end_of_season(si: int) -> void:
	if fate("commercio"):
		for s in order:
			var p: Dictionary = players[s]
			if n_goods(s) == 0:
				continue
			var opts := [{"label": "Nessuno scambio", "val": {}, "k": ""}]
			for a in D.GOODS:
				if p["goods"][a] > 0:
					for b in D.GOODS:
						if a != b:
							opts.append({"label": "1 %s → 1 %s" % [D.GOOD_NAMES[a], D.GOOD_NAMES[b]], "val": {a: -1, b: 1}, "k": a + b})
			var i := await pick(s, "commercio", "Commercio con i Regni Vicini: scambi una merce?", opts)
			var k: String = opts[i]["k"]
			if k != "":
				_gain_bundle(s, {k[0]: -1, k[1]: 1}, "Commercio")
	if si != 2:
		return
	if fate("tasse"):
		for s in order:
			var paid := mini(2, players[s]["goods"]["g"])
			players[s]["goods"]["g"] -= paid
			var lost := (2 - paid) * 2
			_add_vp(s, -lost)
			log_msg("%s paga %d Oro di tasse%s." % [pname(s), paid, (" e perde %d PV" % lost) if lost > 0 else ""])
	if fate("flotta"):
		for s in order:
			var w: int = mini(2, players[s]["goods"]["w"])
			if w == 0:
				continue
			var opts2 := [{"label": "Niente", "val": {}}]
			for k2 in range(1, w + 1):
				opts2.append({"label": "Paga %d Legn%s per %d PV" % [k2, "o" if k2 == 1 else "i", 2 * k2], "val": {"w": -k2, "vp": 2 * k2}})
			var i2 := await pick(s, "flotta", "Flotta Reale: quanto Legno paghi?", opts2)
			if i2 > 0:
				_gain_bundle(s, opts2[i2]["val"], "Flotta Reale")
	if fate("parata"):
		var mx := 0
		for p in players:
			mx = maxi(mx, p["sol"])
		if mx > 0:
			for p in players:
				if p["sol"] == mx:
					_add_vp(p["seat"], 1)
					log_msg("%s: Parata Militare, +1 PV." % pname(p["seat"]))
	if fate("inondazione"):
		for s in order:
			var st := mini(2, players[s]["goods"]["s"])
			players[s]["goods"]["s"] -= st
			if st == 1:
				_add_vp(s, -2)
				log_msg("%s paga solo 1 Pietra per l'Inondazione e perde 2 PV." % pname(s))
			elif st == 0:
				var b := _building_to_destroy(s)
				if b >= 0:
					_destroy(s, b)
					log_msg("%s non paga per l'Inondazione: %s distrutto." % [pname(s), D.BUILDINGS[b]["name"]])
			else:
				log_msg("%s paga 2 Pietre per l'Inondazione." % pname(s))
	changed.emit()


# ------------------------------------------------------------------ mercenari e battaglia

func recruit_cost(s: int) -> int:
	if fate("fondi") and not has_b(s, D.B_CASERMA):
		return 1
	return 1 if has_b(s, D.B_CASERMA) else 2


## Merci (e gettoni +2 col Centro Reclutamento) utilizzabili per reclutare.
func recruit_funds(s: int) -> int:
	return n_goods(s) + (players[s]["p2"] if has_b(s, D.B_CENTRO_RECL) else 0)


func phase_7() -> void:
	_set_phase(7)
	if fate("fondi"):
		for s in range(n):
			if has_b(s, D.B_CASERMA):
				_gain_bundle(s, {"g": 1}, "Fondi Militari")
	for s in order:
		var cp := recruit_cost(s)
		if recruit_funds(s) < cp:
			continue
		var r = await decide(s, {"type": "recruit", "cost_per": cp, "p2ok": has_b(s, D.B_CENTRO_RECL),
			"title": "Mercenari: recluta soldati (%d merc%s ciascuno)" % [cp, "e" if cp == 1 else "i"]})
		if not (r is Dictionary):
			continue
		var k := maxi(0, int(r.get("n", 0)))
		var pay_in: Dictionary = r.get("pay", {})
		var pay := {"g": maxi(0, int(pay_in.get("g", 0))), "w": maxi(0, int(pay_in.get("w", 0))), "s": maxi(0, int(pay_in.get("s", 0))),
			"p2": maxi(0, int(pay_in.get("p2", 0))) if has_b(s, D.B_CENTRO_RECL) else 0}
		var ok: bool = pay["g"] + pay["w"] + pay["s"] + pay["p2"] == k * cp
		for t in D.GOODS:
			if pay[t] > players[s]["goods"][t]:
				ok = false
		if pay["p2"] > players[s]["p2"]:
			ok = false
		if k == 0 or not ok:
			continue
		for t in D.GOODS:
			players[s]["goods"][t] -= pay[t]
		players[s]["p2"] -= pay["p2"]
		players[s]["sol"] += k
		var ptxt := D.cost_text(pay)
		if pay["p2"] > 0:
			ptxt += (", " if ptxt != "gratis" else "") + "%d gettoni +2" % pay["p2"]
		log_msg("%s recluta %d soldat%s pagando %s." % [pname(s), k, "o" if k == 1 else "i", ptxt])
		fx.emit("recruit", {"seat": s, "n": k})
		changed.emit()
	for s in range(n):
		if has_b(s, D.B_SCUOLA) and players[s]["sol"] >= 3:
			_add_vp(s, 2)
			log_msg("%s: Scuola, +2 PV." % pname(s))


## Bonus degli edifici (e del Governatore) in battaglia. str_printed: forza stampata degli invasori.
func battle_bonus(s: int, race: String, str_printed := 0) -> int:
	var b := 0
	var w: Dictionary = players[s]["winter"]
	if has_b(s, D.B_TORRE): b += 1
	if has_b(s, D.B_FUCINA): b += 1
	if has_b(s, D.B_GILDA_MAGHI): b += 2
	if has_b(s, D.B_PALIZZATA): b += 2 if race == "zombi" else 1
	if has_b(s, D.B_MURA): b += 1
	if has_b(s, D.B_FORTEZZA): b += 1
	if has_b(s, D.B_CHIESA) and race == "demoni": b += 1
	if has_b(s, D.B_BARRICATA) and race == "goblin": b += 1
	if has_b(s, D.B_FATTORIE): b -= 1
	if has_b(s, D.B_FORT_SOMM) and str_printed > 0 and str_printed <= 5: b += 1
	if has_b(s, D.B_GLADIATORI): b += 1
	if has_b(s, D.B_VEDETTA): b += 1
	if has_b(s, D.B_ARMERIA): b += 0 if race in ["zombi", "demoni"] else 2
	if has_b(s, D.B_ALCHIMISTI): b += 3 if w.get("alch", false) else 1
	if has_b(s, D.B_PICC_PALIZZ) and w.get("small_pal", players[s]["sol"] >= 1): b += 1
	if has_b(s, D.B_BASTIONI) and w.get("bast", false): b += 1
	if gov(s) == "generale": b += 1
	if gov(s) == "mercenario": b += 2
	return b


func wins_ties(s: int) -> bool:
	return has_b(s, D.B_MURA) or has_b(s, D.B_BASTIONI)


func phase_8() -> void:
	_set_phase(8)
	# decisioni prima di svelare i nemici
	for s in order:
		var w := {}
		w["small_pal"] = players[s]["sol"] >= 1
		if has_b(s, D.B_ALCHIMISTI) and players[s]["goods"]["g"] > 0:
			if await yesno(s, "alch_w", "Gilda degli Alchimisti: paghi 1 Oro per avere +3 invece di +1 in battaglia?", {"g": -1}):
				players[s]["goods"]["g"] -= 1
				w["alch"] = true
				log_msg("%s paga 1 Oro alla Gilda degli Alchimisti (+3 in battaglia)." % pname(s))
		if has_b(s, D.B_BASTIONI) and players[s]["goods"]["s"] > 0:
			if await yesno(s, "bast_w", "Mura con Bastioni: paghi 1 Pietra per +1 in battaglia?", {"s": -1}):
				players[s]["goods"]["s"] -= 1
				w["bast"] = true
				log_msg("%s paga 1 Pietra per le Mura con Bastioni (+1 in battaglia)." % pname(s))
		players[s]["winter"] = w
	var snow := fate("nevicata")
	if mods.get("troops", false):
		for s in order:
			var toks: Array = players[s]["troops"]
			var opts := []
			for v in toks:
				if snow and v == 0 and toks.size() > 1:
					continue
				if not v in opts:
					opts.append(v)
			var r = await decide(s, {"type": "troops", "options": opts, "title": "Richiesta di Truppe: quale gettone giochi?", "secret": true})
			players[s]["troop"] = int(r) if (r is int or r is float) and int(r) in opts else opts[0]
		# i gettoni si rivelano tutti insieme
		for s in order:
			players[s]["troops"].erase(players[s]["troop"])
	# carta (o carte) Invasori
	var ci: int = deck[year - 1]
	var card: Dictionary = D.INVADERS[ci]
	revealed = ci
	revealed2 = deck2[year - 1]
	if revealed2 >= 0:
		var c2: Dictionary = D.INVADERS[revealed2]
		log_msg("Manovra a Tenaglia: arrivano anche i %s (forza %d)." % [D.RACE_NAMES[c2["race"]], c2["str"]])
		if c2["str"] > card["str"]:
			ci = revealed2
			card = c2
	var strength: int = card["str"]
	if fate("feroci"):
		strength += 1
	if fate("numerosi") and card["race"] in ["goblin", "orchi"]:
		strength += 1
	battle_str = strength
	# rinforzi del Re
	king_die = 2 if snow else _d6()
	var reinf := {}
	for s in range(n):
		var base := king_die
		if mods.get("troops", false):
			base = players[s]["troop"] - (1 if snow else 0)
		base = maxi(0, base)
		if has_b(s, D.B_ACCADEMIA):
			var d := _d6()
			var dv := d
			if mods.get("troops", false):
				dv = (d + 1) / 2
			if dv > base:
				log_msg("%s: Accademia Militare, il dado fa %d e vale %d rinforzi." % [pname(s), d, dv])
				base = dv
		reinf[s] = base
		players[s]["sol"] += base
	var rtxt := ""
	if mods.get("troops", false):
		rtxt = "Rinforzi: " + ", ".join(range(n).map(func(k): return "%s %d" % [pname(k), reinf[k]]))
	elif snow:
		rtxt = "Nevicata intensa: il Re invia 2 soldati a ciascuno."
	else:
		rtxt = "Il dado del Re dà %d soldat%s a tutti." % [king_die, "o" if king_die == 1 else "i"]
	log_msg("Invasori: %s, forza %d. %s" % [D.RACE_NAMES[card["race"]], strength, rtxt])
	fx.emit("invaders", {"card": ci, "die": king_die})
	changed.emit()
	battle.clear()
	for s in range(n):
		var bonus := battle_bonus(s, card["race"], card["str"])
		var tot: int = players[s]["sol"] + bonus
		var res := "tie"
		if tot > strength or (tot == strength and wins_ties(s)):
			res = "win"
		elif tot < strength:
			res = "lose"
		battle.append({"seat": s, "total": tot, "res": res, "sol": players[s]["sol"], "bonus": bonus, "notes": [], "reinf": reinf[s]})
	var mx := -999
	for e in battle:
		mx = maxi(mx, e["total"])
	var best_bonus := 2 if fate("giurati") else 1
	for s in order:
		var e: Dictionary = battle[s]
		if e["res"] == "win":
			var rew := {}
			if gov(s) != "mercenario":
				rew = card["rew"].duplicate()
				if has_b(s, D.B_MANIERO):
					for k in rew:
						rew[k] *= 2
					e["notes"].append("Maniero: premi doppi")
			else:
				e["notes"].append("Mercenario: niente premi")
			if rew.get("any", 0) > 0:
				var gs := await choose_goods(s, rew["any"], "Vittoria! Scegli %d merc%s" % [rew["any"], "e" if rew["any"] == 1 else "i"], "battle")
				rew.erase("any")
				for t in gs:
					rew[t] = rew.get(t, 0) + gs[t]
			if has_b(s, D.B_FORTEZZA):
				rew["vp"] = rew.get("vp", 0) + 1
				e["notes"].append("Fortezza +1 PV")
			if e["total"] == mx:
				rew["vp"] = rew.get("vp", 0) + best_bonus
				e["notes"].append("miglior difesa +%d PV" % best_bonus)
				e["best"] = true
			_gain_bundle(s, rew, "vittoria contro gli Invasori")
			e["got"] = D.bundle_text(rew) if not rew.is_empty() else "niente"
		elif e["res"] == "lose":
			if players[s]["paladin"] and await yesno(s, "paladin", "Paladino: scarti la carta invece di subire la sconfitta? (perdi i 3 PV di fine partita)", {"vp": 2}):
				players[s]["paladin"] = false
				e["lost"] = "niente (il Paladino si sacrifica)"
				log_msg("%s scarta il Paladino e non subisce la sconfitta." % pname(s))
			else:
				e["lost"] = await _apply_penalty(s, card["pen"])
		else:
			log_msg("%s respinge a fatica gli Invasori (pareggio)." % pname(s))
	changed.emit()
	await pause_point({"type": "ack", "ctx": "battle", "card": ci})
	for p in players:
		var keep := 0
		if has_b(p["seat"], D.B_QUARTIERI) and battle[p["seat"]].get("best", false) and p["sol"] > 0:
			keep = 1
			log_msg("%s: Quartieri delle Truppe, trattiene un soldato." % pname(p["seat"]))
		p["sol"] = keep
		p["winter"] = {}
	revealed = -1
	revealed2 = -1
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
			lose = await _choose_lose(s, k2, "Sconfitta: scegli %d merci da perdere" % k2)
		for t in D.GOODS:
			p["goods"][t] -= lose[t]
		var tx := D.cost_text(lose)
		if tx != "gratis":
			parts.append(tx)
	for i in range(pen.get("bld", 0)):
		var b := _building_to_destroy(s)
		if b >= 0:
			_destroy(s, b)
			parts.append("%s distrutto" % D.BUILDINGS[b]["name"])
	if pen.get("vp", 0) > 0:
		if has_b(s, D.B_RIFUGIO):
			parts.append("nessun PV (Rifugio Nascosto)")
		else:
			_add_vp(s, -pen["vp"])
			parts.append("%d PV" % pen["vp"])
	var txt := ", ".join(parts) if not parts.is_empty() else "nulla da perdere"
	log_msg("%s è sconfitto: perde %s." % [pname(s), txt])
	return txt


func _destroy(s: int, b: int) -> void:
	players[s]["bld"][b] = false
	_add_vp(s, -D.BUILDINGS[b]["vp"])
	fx.emit("destroy", {"seat": s, "b": b})


func _auto_lose_from(have: Dictionary, k: int) -> Dictionary:
	var g: Dictionary = have.duplicate()
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


## L'edificio distrutto: colonna più a destra con edifici, riga più in alto (il Duomo è ignorato).
func _building_to_destroy(s: int) -> int:
	var lines: Array = players[s]["lines"]
	for col in range(3, -1, -1):
		for line in lines:
			var b: int = line[col]
			if has_b(s, b) and b != D.B_DUOMO:
				return b
	return -1


# ------------------------------------------------------------------ fine anno e fine partita

func _end_of_year() -> void:
	var final_year := year >= last_year
	for s in order:
		match gov(s):
			"carpentiere":
				_gain_bundle(s, {"w": 1}, "Carpentiere")
			"minatore":
				_gain_bundle(s, {"g": 2 if year == 4 else 1}, "Minatore")
			"scultore":
				_gain_bundle(s, {"s": 1}, "Scultore")
	marks.clear()
	stars.clear()
	if not final_year:
		_minstrel()
	changed.emit()


func _minstrel() -> void:
	for s in range(n):
		if gov(s) != "menestrello":
			continue
		var more := false
		var less := false
		for o in _others(s):
			if players[o]["vp"] > players[s]["vp"]:
				more = true
			if players[o]["vp"] < players[s]["vp"]:
				less = true
		var v := (1 if more else 0) + (0 if less else 1)
		if v > 0:
			_add_vp(s, v)
			log_msg("%s (Menestrello): +%d PV." % [pname(s), v])


func _final_scoring() -> void:
	phase = 9
	season = -1
	if year < 5:
		log_msg("[b]Il Re è morto: la partita termina alla fine dell'anno %s.[/b]" % D.ROMAN[year])
	for p in players:
		var s: int = p["seat"]
		if mods.get("troops", false) and not p["troops"].is_empty():
			var left: int = p["troops"].max()
			if left > 0:
				_add_vp(s, left)
				log_msg("%s: gettone Richiesta di Truppe avanzato, +%d PV." % [pname(s), left])
		if p["paladin"]:
			_add_vp(s, 3)
			log_msg("%s: ha ancora il Paladino, +3 PV." % pname(s))
		if gov(s) == "architetto" and n_bld(s) >= 15:
			_add_vp(s, 5)
			log_msg("%s (Architetto): almeno 15 edifici, +5 PV." % pname(s))
		if has_b(s, D.B_GILDA_ARCH):
			var top := true
			for o in _others(s):
				if n_bld(o) > n_bld(s):
					top = false
			if top:
				_add_vp(s, 3)
				log_msg("%s: Gilda degli Architetti, +3 PV." % pname(s))
		if p["bld"][D.B_CATTEDRALE]:
			var extra := n_goods(s) / 2
			if extra > 0:
				_add_vp(s, extra)
				log_msg("%s: Cattedrale, +%d PV per le merci." % [pname(s), extra])
	_minstrel()
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
		parts.append("%d:%d:%d:%d:%d:%d:%d:%s" % [p["vp"], p["goods"]["g"], p["goods"]["w"], p["goods"]["s"], p["p2"], p["sol"], p["gov"], str(p["bld"].map(func(x): return 1 if x else 0))])
	return "|".join(parts)
