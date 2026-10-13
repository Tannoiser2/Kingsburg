class_name KBAI
extends RefCounted
## IA di Kingsburg. Valuta tutto in "punti vittoria attesi":
## - le merci valgono di più quando servono per gli edifici che ha in mente (piano di costruzione);
## - i soldati valgono quanto migliorano l'esito atteso della battaglia d'inverno;
## - per i Consiglieri cerca la migliore ripartizione di tutti i dadi (ricerca esaustiva) e gioca
##   per primo il gruppo più prezioso, tenendo conto di quali Consiglieri gli avversari possono rubargli.
## Usa un generatore casuale proprio: non tocca mai quello del motore (online deve restare allineato).

const D = preload("res://scripts/data/kb_data.gd")

var level := 1                   # 0 facile, 1 normale, 2 difficile
## Pesi della valutazione. "Normale" usa BASE; "Difficile" usa TUNED (trovati con partite IA contro IA).
const BASE := {"miss": 0.55, "g_g": 1.05, "g_w": 0.9, "g_s": 0.95, "deficit": 0.75, "surplus": 0.25, "late": 0.75,
	"p2": 0.65, "p2_th": 0.95, "unlock": 0.25, "winb": 0.35, "lostb": 1.2, "spy": 0.6, "envoy": 1.2,
	"threat": 0.12, "deny": 0.0, "bcost": 0.55, "second": 0.8,
	"batt": 0.75, "statua": 0.12, "cappella": 0.25, "locanda": 0.6, "mercato": 0.35, "fattorie": 0.9, "gmerc": 1.0,
	"caserma": 0.7, "scuderia": 0.3, "argano": 0.25, "municipio": 0.6, "ambasciata": 1.0}
const TUNED := {"g_s": 1.52, "late": 0.975, "p2": 0.488, "p2_th": 0.712, "unlock": 0.325, "envoy": 0.72,
	"deny": 0.05, "bcost": 0.715, "caserma": 0.91}
var W := {}
var W2 := {}
var rng := RandomNumberGenerator.new()

var _eng: KBEngine
var _seat := -1
var _gv := {}                    # valore marginale delle merci (piano attuale)
var _need := {}
var _solv := []                  # valore del k-esimo soldato in più


func decide(eng: KBEngine, seat: int, req: Dictionary):
	_eng = eng
	_seat = seat
	if W.is_empty():
		set_weights({})
	_prepare()
	match str(req.get("type", "")):
		"goods":
			if str(req.get("ctx", "")) == "cap7o":
				return _choose_goods(int(req["n"]))
			return _choose_goods(int(req["n"]))
		"lose":
			return _choose_lose(int(req["n"]), req.get("have", {}))
		"pick":
			return _pick(req)
		"reroll_statue":
			return _statue()
		"reroll_chapel":
			return _chapel()
		"gov":
			return _gov(req)
		"lines":
			return _lines(req["options"])
		"draft_line":
			return _draft_line(req["options"])
		"mark":
			return _mark(req["options"])
		"troops":
			return _troops(req["options"])
		"influence":
			return _influence(req["moves"])
		"build":
			return _build(req["options"], bool(req.get("second", false)))
		"recruit":
			return _recruit(int(req["cost_per"]), bool(req.get("p2ok", false)))
		"ack":
			return true
	return null


func set_weights(over: Dictionary) -> void:
	W = BASE.duplicate()
	if level >= 2:
		for k in TUNED:
			W[k] = TUNED[k]
	for k in over:
		W[k] = float(over[k])
	W2 = W


# ------------------------------------------------------------------ modello di valore

func _p() -> Dictionary:
	return _eng.players[_seat]


## Stagioni produttive che restano (compresa quella in corso se non è ancora finita la costruzione).
func _seasons_left() -> int:
	var y := _eng.year
	var ph := _eng.phase
	var done := 0
	if ph >= 2: done += 1
	if ph >= 4: done += 1
	if ph >= 6: done += 1
	if ph in [2, 4, 6] and _eng.step in ["roll", "influence", "rewards"]:
		done -= 1
	return maxi(0, (5 - y) * 3 + (3 - done))


func _winters_left() -> int:
	return 5 - _eng.year + (1 if _eng.phase <= 8 else 0)


func _prepare() -> void:
	var p := _p()
	var late := _seasons_left()
	# piano: i due edifici migliori raggiungibili
	var cands := []
	for line in p["lines"]:
		for col in range(4):
			var b: int = line[col]
			if p["bld"][b]:
				continue
			# raggiungibile se mancano al massimo 1 edificio a sinistra
			var missing := 0
			for c in range(col):
				if not p["bld"][line[c]]:
					missing += 1
			if missing > 1:
				break
			var cost := _eng.building_cost(_seat, b)
			var ctot := 0
			for t in D.GOODS:
				ctot += cost.get(t, 0)
			var val := _building_value(b)
			if missing == 1:
				val *= W["miss"]
			cands.append({"b": b, "score": val / maxf(1.0, ctot + 0.5), "cost": cost})
			if missing == 1:
				break
	cands.sort_custom(func(a, b): return a["score"] > b["score"])
	_need = {"g": 0, "w": 0, "s": 0}
	for i in range(mini(2, cands.size())):
		for t in D.GOODS:
			_need[t] += cands[i]["cost"].get(t, 0)
	_gv = {}
	var cath: bool = p["bld"][D.B_CATTEDRALE]
	for t in D.GOODS:
		var deficit: int = maxi(0, _need[t] - p["goods"][t])
		_gv[t] = {"deficit": deficit}
	_gv["late"] = late
	_gv["cath"] = cath
	_solv = _soldier_values(p["sol"])


## Valore marginale di una merce di tipo t, dato quante ne arrivano già (extra).
func _good_value(t: String, extra := 0) -> float:
	var late: int = _gv["late"]
	if late <= 0:
		return 0.55 if _gv["cath"] else 0.05
	var base: float = W["g_" + t]
	if level == 0:
		return base
	var deficit: int = _gv[t]["deficit"] - extra
	var v: float = base
	if deficit > 0:
		v += W["deficit"]
	elif extra + _p()["goods"][t] > _need.get(t, 0) + 2:
		v -= W["surplus"]
	if late <= 2:
		v *= W["late"]
	return v


func _bundle_value(b: Dictionary) -> float:
	var v := 0.0
	var acc := {"g": 0, "w": 0, "s": 0}
	var g: Dictionary = _p()["goods"]
	for t in D.GOODS:
		var k0: int = int(b.get(t, 0))
		if k0 >= 0:
			for k in range(k0):
				v += _good_value(t, acc[t])
				acc[t] += 1
		else:
			for k in range(-k0):
				if g[t] + acc[t] <= 0:
					return -99.0
				acc[t] -= 1
				v -= _good_value(t, acc[t])
	var an: int = int(b.get("any", 0))
	if an > 0:
		for k in range(an):
			var bt := _best_good(acc)
			v += _good_value(bt, acc[bt])
			acc[bt] += 1
	elif an < 0:
		for k in range(-an):
			var wt := _worst_good(acc)
			if wt == "":
				return -99.0
			acc[wt] -= 1
			v -= _good_value(wt, acc[wt])
	v += b.get("vp", 0) * _vp_value()
	var sl: int = int(b.get("sol", 0))
	if sl > 0:
		for k in range(sl):
			v += _solv[mini(k, _solv.size() - 1)]
	elif sl < 0:
		if _p()["sol"] + sl < 0:
			return -99.0
		v += sl * _solv[0]
	var pt: int = int(b.get("p2", 0))
	if pt < 0 and _p()["p2"] + pt < 0:
		return -99.0
	if pt != 0:
		v += pt * (W["p2_th"] if _p()["bld"][D.B_MUNICIPIO] else W["p2"]) * (1.0 if _seasons_left() > 1 else 0.3)
	return v


func _worst_good(acc: Dictionary) -> String:
	var g: Dictionary = _p()["goods"]
	var worst := ""
	var wv := 99.0
	for t in D.GOODS:
		if g[t] + acc.get(t, 0) > 0:
			var v := _good_value(t, acc.get(t, 0) - 1)
			if v < wv:
				wv = v
				worst = t
	return worst


func _vp_value() -> float:
	return 1.0


func _best_good(acc: Dictionary) -> String:
	var best := "g"
	var bv := -99.0
	for t in D.GOODS:
		var v := _good_value(t, acc.get(t, 0))
		if v > bv:
			bv = v
			best = t
	return best


## Valore di un edificio: PV + effetto per il resto della partita.
func _building_value(b: int) -> float:
	var R := float(_seasons_left())
	var WN := float(_winters_left())
	var v := float(D.BUILDINGS[b]["vp"])
	var batt: float = W2["batt"] * WN
	match b:
		D.B_STATUA: v += W2["statua"] * R
		D.B_CAPPELLA: v += W2["cappella"] * R
		D.B_CHIESA: v += 0.15 * WN
		D.B_CATTEDRALE: v += 1.5
		D.B_LOCANDA: v += W2["locanda"] * ceilf(R / 3.0)
		D.B_MERCATO: v += W2["mercato"] * R
		D.B_FATTORIE: v += W2["fattorie"] * R - 0.6 * WN
		D.B_GILDA_MERC: v += W2["gmerc"] * R
		D.B_TORRE, D.B_FUCINA: v += batt
		D.B_CASERMA: v += W2["caserma"] * WN
		D.B_GILDA_MAGHI: v += 2.0 * batt
		D.B_PALIZZATA: v += batt * 1.1
		D.B_SCUDERIA: v += W2["scuderia"] * R
		D.B_MURA: v += batt * 1.3
		D.B_FORTEZZA: v += batt + 0.5 * WN
		D.B_BARRICATA: v += 0.25 * WN
		D.B_ARGANO: v += W2["argano"] * R
		D.B_MUNICIPIO: v += W2["municipio"] * R
		D.B_AMBASCIATA: v += W2["ambasciata"] * R
		D.B_SEGHERIA, D.B_TAGLIAPIETRE: v += 0.5 * ceilf(R / 3.0) * (3.0 if _p()["bld"][D.B_ZECCA] else 1.0)
		D.B_OREFICERIA: v += 0.6 * ceilf(R / 3.0) * (3.0 if _p()["bld"][D.B_ZECCA] else 1.0)
		D.B_ZECCA: v += 0.5 * R * 2.0 / 3.0
		D.B_FORT_SOMM: v += 0.5 * minf(WN, 3.0)
		D.B_CENTRO_RECL: v += 0.25 * WN
		D.B_CAMPO_ADD: v += 0.5 * WN
		D.B_ACCADEMIA: v += 0.6 * WN
		D.B_GIOSTRA, D.B_CIRCO: v += ceilf(R / 3.0)
		D.B_GLADIATORI: v += batt
		D.B_ARENA: v += 0.4 * R
		D.B_ALTARE: v += 0.3 * R
		D.B_MONASTERO: v += 0.2 * ceilf(R / 3.0)
		D.B_DUOMO: v += 1.0
		D.B_BIRRERIA: v += 0.8 * ceilf(R / 3.0)
		D.B_MERC_ITIN: v += 0.3 * R
		D.B_VIGNE: v += 0.8 * ceilf(R / 3.0)
		D.B_PORTO: v += 0.9 * R
		D.B_VEDETTA: v += batt + 0.2
		D.B_ARMERIA: v += batt * 1.6
		D.B_QUARTIERI: v += 0.3 * WN
		D.B_ALCHIMISTI: v += batt * 1.6
		D.B_PICC_PALIZZ: v += batt * 0.8
		D.B_GRIFONI: v += 0.25 * R
		D.B_BASTIONI: v += batt * 1.0
		D.B_MANIERO: v += 0.6 * WN
		D.B_RIFUGIO: v += 0.6 * WN
		D.B_FALEGNAMERIA: v += 0.25 * R
		D.B_UFF_CAMBIO: v += 0.9 * ceilf(R / 3.0)
		D.B_GILDA_ARCH: v += 0.35 * R + 1.5
		D.B_FONTANA: v += maxf(0.0, 4.0 - _eng.year)
		D.B_PARCO: v += 0.35 * R
		D.B_SCUOLA: v += 0.8 * WN
		D.B_UNIVERSITA: v += 0.5 * R
	# sblocca l'edificio successivo della riga
	var line := _eng.line_of(_seat, b)
	var col := line.find(b)
	if col >= 0 and col < 3 and R > 1:
		v += W["unlock"] * D.BUILDINGS[line[col + 1]]["vp"] * minf(1.0, R / 6.0)
	if _p()["bld"][D.B_GILDA_ARCH]:
		v += 1.0
	return v


# ------------------------------------------------------------------ battaglia attesa

func _possible_cards() -> Array:
	var y := _eng.year
	var known: Array = _p()["known"].get(y, [])
	if not known.is_empty():
		return known
	var out := []
	for k in range(D.INVADERS.size()):
		if D.INVADERS[k]["year"] == y:
			out.append(k)
	return out


## Rinforzi possibili in inverno (dado del Re, Nevicata, gettoni Richiesta di Truppe, Accademia).
func _reinforcements(token := -1) -> Array:
	var out := []
	var snow := _eng.fate("nevicata")
	var base := []
	if token >= 0:
		base = [token - (1 if snow else 0)]
	elif _eng.mods.get("troops", false):
		var toks: Array = _p()["troops"]
		if toks.is_empty():
			base = [0]
		else:
			base = [toks[toks.size() / 2] - (1 if snow else 0)]
	elif snow:
		base = [2]
	else:
		base = [1, 2, 3, 4, 5, 6]
	for b0 in base:
		var b1: int = maxi(0, b0)
		if _p()["bld"][D.B_ACCADEMIA]:
			for d in range(1, 7):
				var dv := d if not _eng.mods.get("troops", false) else (d + 1) / 2
				out.append(maxi(b1, dv))
		else:
			out.append(b1)
	return out


## Valore atteso della battaglia con `sol` soldati (rinforzi inclusi).
func _battle_ev(sol: int, extra_bonus := 0, token := -1) -> float:
	var cards := _possible_cards()
	var tot := 0.0
	var cnt := 0
	var reinf := _reinforcements(token)
	var merc := _eng.gov(_seat) == "mercenario"
	for ci in cards:
		var card: Dictionary = D.INVADERS[ci]
		var strength: int = card["str"]
		if _eng.fate("feroci"):
			strength += 1
		if _eng.fate("numerosi") and card["race"] in ["goblin", "orchi"]:
			strength += 1
		var bonus := _eng.battle_bonus(_seat, card["race"], card["str"]) + extra_bonus
		var pen_v := _penalty_value(card["pen"])
		var rew_v := 0.0 if merc else _reward_value(card["rew"]) * (2.0 if _p()["bld"][D.B_MANIERO] else 1.0)
		for r in reinf:
			var t: int = sol + r + bonus
			if t > strength or (t == strength and _eng.wins_ties(_seat)):
				tot += rew_v + (1.0 if _p()["bld"][D.B_FORTEZZA] else 0.0) + W["winb"] * (2.0 if _eng.fate("giurati") else 1.0)
			elif t < strength:
				tot -= pen_v
			cnt += 1
	return tot / maxf(1, cnt)


func _penalty_value(pen: Dictionary) -> float:
	var p := _p()
	var v := 0.0
	for t in D.GOODS:
		v += mini(pen.get(t, 0), p["goods"][t]) * 1.0
	v += mini(pen.get("any", 0), _eng.n_goods(_seat)) * 0.9
	if pen.get("bld", 0) > 0:
		var b := _eng._building_to_destroy(_seat)
		if b >= 0:
			v += D.BUILDINGS[b]["vp"] + W["lostb"]
	if not p["bld"][D.B_RIFUGIO]:
		v += pen.get("vp", 0)
	if p["paladin"]:
		v = minf(v, 3.0)
	return v


func _reward_value(rew: Dictionary) -> float:
	var v := 0.0
	for t in D.GOODS:
		v += rew.get(t, 0) * 1.0
	v += rew.get("any", 0) * 1.1
	v += rew.get("vp", 0)
	return v


func _soldier_values(cur: int) -> Array:
	var out := []
	if _eng.phase > 8 or _eng.phase == 0:
		return [0.3, 0.2, 0.1, 0.05]
	var prev := _battle_ev(cur)
	for k in range(1, 5):
		var e := _battle_ev(cur + k)
		out.append(maxf(0.05, e - prev))
		prev = e
	return out


# ------------------------------------------------------------------ scelte semplici

func _choose_goods(n: int) -> Dictionary:
	var acc := {"g": 0, "w": 0, "s": 0}
	for i in range(n):
		var t := _best_good(acc)
		if level == 0 and rng.randf() < 0.3:
			t = D.GOODS[rng.randi_range(0, 2)]
		acc[t] += 1
	return acc


func _choose_lose(n: int, have := {}) -> Dictionary:
	var g: Dictionary = have.duplicate() if not have.is_empty() else _p()["goods"].duplicate()
	var out := {"g": 0, "w": 0, "s": 0}
	for i in range(n):
		var worst := ""
		var wv := 99.0
		for t in D.GOODS:
			if g[t] - out[t] > 0:
				var v := _good_value(t, -out[t] - 1)
				if v < wv:
					wv = v
					worst = t
		if worst == "":
			break
		out[worst] += 1
	return out


func _pick(req: Dictionary):
	var opts: Array = req["options"]
	var ctx: String = str(req.get("ctx", ""))
	var p := _p()
	match ctx:
		"dice":
			return _dice_pick(opts)
		"auction":
			return _auction(req)
		"hostile":
			# la merce che serve meno a chi la riceve: quella che ha già in abbondanza
			var tg: Dictionary = _eng.players[int(req.get("target", 0))]["goods"]
			var bi0 := 0
			for i0 in range(opts.size()):
				if tg[opts[i0]["k"]] > tg[opts[bi0]["k"]]:
					bi0 = i0
			return bi0
		"cap7", "cap14", "cap15":
			# il giocatore meno pericoloso: quello con meno PV
			var bw := 0
			for i1 in range(opts.size()):
				if _eng.players[opts[i1]["who"]]["vp"] < _eng.players[opts[bw]["who"]]["vp"]:
					bw = i1
			return bw
		"paladin":
			var ci: int = _eng.revealed if _eng.revealed >= 0 else _eng.deck[_eng.year - 1]
			return 1 if _penalty_value(D.INVADERS[ci]["pen"]) > 3.2 else 0
		"alch_w":
			var gain := _battle_ev(p["sol"], 2) - _battle_ev(p["sol"])
			return 1 if gain > _good_value("g", -1) * 0.8 else 0
		"bast_w":
			var gain2 := _battle_ev(p["sol"], 1) - _battle_ev(p["sol"])
			return 1 if gain2 > _good_value("s", -1) * 0.8 else 0
		"blessing":
			var with_white := 0
			for q in _eng.players:
				if q["seat"] != _seat and (q["bld"][D.B_FATTORIE] or q["aid_white"]):
					with_white += 1
			return 1 if with_white <= 1 else 0
		"stregone":
			var bb := 0
			var bv0 := 0.0
			for i2 in range(1, opts.size()):
				var v0 := _building_value(int(opts[i2]["b"])) + 0.5
				if v0 > bv0:
					bv0 = v0
					bb = i2
			return bb
		"duca":
			var mine := []
			for a in _eng.adv:
				if _eng.adv[a]["seat"] == _seat and a > 12 and a <= 18:
					mine.append(a)
			if mine.is_empty():
				return 0
			mine.sort()
			return 1 if adv_value(12) > adv_value(mine[mine.size() - 1]) + 0.2 else 0
		"peek2":
			return 0
	# scelta generica: l'opzione che vale di più (val = guadagni e costi)
	var bi := 0
	var bvv := -999.0
	for i in range(opts.size()):
		var o = opts[i].get("val", {})
		var v3 := _bundle_value(o) if o is Dictionary else 0.0
		if ctx == "spy" and i == 1:
			v3 -= W["spy"]
		if ctx in ["payvp"] and _seasons_left() <= 1 and i > 0:
			v3 += 0.4
		if v3 > bvv + 0.0001:
			bvv = v3
			bi = i
	return bi


## Effetti sui dadi (Statua, Cappella, Altare, Filosofo, Principe): il migliore se migliora l'attesa.
func _dice_pick(opts: Array) -> int:
	var p := _p()
	var dice: Array = p["dice"]
	var cur := _best_partition_value(_vals(dice), _whites(dice))
	var best := 0
	var best_v := cur + 0.15
	for i in range(1, opts.size()):
		var k: String = opts[i]["k"]
		var ev := cur
		match k:
			"chapel", "altar", "phil":
				ev = 0.0
				for t in range(16):
					var vals := []
					for d in dice:
						vals.append(rng.randi_range(1, 6))
					ev += _best_partition_value(vals, _whites(dice))
				ev /= 16.0
				if k == "phil":
					ev += 0.3
			"statue":
				ev = 0.0
				for v in range(1, 7):
					var vals2 := _vals(dice)
					vals2[0] = v
					ev += _best_partition_value(vals2, _whites(dice))
				ev /= 6.0
			"prince":
				var vals3 := _vals(dice)
				var tgt := [3, 4, 6]
				var j := 0
				for q in range(dice.size()):
					if not dice[q]["white"] and j < 3:
						vals3[q] = tgt[j]
						j += 1
				ev = _best_partition_value(vals3, _whites(dice))
		if ev > best_v:
			best_v = ev
			best = i
	return best


# ------------------------------------------------------------------ moduli di espansione

const GOV_RATING := {"stregone": 6.0, "politico": 6.0, "paladino": 4.0, "predicatore": 5.0, "nobile": 6.0,
	"principe": 5.0, "sacerdote": 4.0, "truffatore": 4.0, "principessa": 4.5, "filosofo": 4.0, "carpentiere": 5.0,
	"architetto": 5.0, "fata": 4.0, "esattore": 4.0, "ereditiera": 5.0, "duca": 3.0, "damigella": 5.0,
	"generale": 5.0, "ladro": 3.0, "intrigante": 4.0, "minatore": 6.0, "mercenario": 4.0, "scultore": 5.0, "menestrello": 5.0}


func _gov_rating(g: int) -> float:
	return GOV_RATING.get(D.GOVERNORS[g]["key"], 4.0)


func _gov(req: Dictionary):
	var opts: Array = req["options"]
	var best: int = opts[0]
	for g in opts:
		var v := _gov_rating(g) + (rng.randf_range(-1.0, 1.0) if level == 0 else 0.0)
		if v > _gov_rating(best):
			best = g
	return best


func _auction(req: Dictionary) -> int:
	var opts: Array = req["options"]
	var g: int = int(req.get("gov", 0))
	var others := []
	for o in _eng.gov_pool:
		if o != g:
			others.append(_gov_rating(o))
	var alt := 0.0
	if not others.is_empty():
		others.sort()
		alt = others[others.size() - 1]
	var max_bid := _gov_rating(g) - alt + 1.0
	for i in range(opts.size()):
		var b: int = int(opts[i].get("bid", -1))
		if b >= 0 and b <= max_bid:
			return i
	return 0


## Valore di una linea di edifici per il resto della partita (le colonne più a destra contano meno).
func _line_value(line: Array) -> float:
	var w := [1.0, 0.85, 0.65, 0.45]
	var v := 0.0
	for c in range(4):
		var b: int = line[c]
		var cost := 0
		for t in D.GOODS:
			cost += D.BUILDINGS[b]["cost"].get(t, 0)
		v += w[c] * (_building_value(b) - 0.6 * cost)
	return v


func _lines(options: Array) -> Array:
	var use := []
	for L in options:
		if _line_value(D.ALT_LINES[L]) > _line_value(D.LINES[L]) + 0.5:
			use.append(L)
	return use


func _draft_line(options: Array) -> String:
	var best: String = options[0]
	var bv := -999.0
	for L in options:
		var v := _line_value(D.ALT_LINES[L]) - _line_value(D.LINES[L])
		if v > bv:
			bv = v
			best = L
	return best


func _mark(options: Array) -> int:
	var best: int = options[0]
	var bv := -999.0
	for a in options:
		var v := adv_value(a) * (0.7 if a >= 16 else 1.0)
		if v > bv:
			bv = v
			best = a
	return best


func _troops(options: Array) -> int:
	var p := _p()
	var toks: Array = p["troops"]
	var final := _eng.year >= _eng.last_year
	var best: int = options[0]
	var bv := -999.0
	for t in options:
		var v := _battle_ev(p["sol"], 0, t)
		var rest := toks.duplicate()
		rest.erase(t)
		if final:
			v += float(rest.max()) if not rest.is_empty() else 0.0
		else:
			v -= 0.45 * t
		if v > bv:
			bv = v
			best = t
	return best


func _statue():
	# tutti i dadi uguali: rilanciarne uno conviene se migliora la ripartizione attesa
	var p := _p()
	var dice: Array = p["dice"]
	var cur := _best_partition_value(_vals(dice), _whites(dice))
	var ev := 0.0
	for v in range(1, 7):
		var vals := _vals(dice)
		vals[0] = v
		ev += _best_partition_value(vals, _whites(dice))
	ev /= 6.0
	return 0 if ev > cur + 0.1 else -1


func _chapel():
	var p := _p()
	var dice: Array = p["dice"]
	var cur := _best_partition_value(_vals(dice), _whites(dice))
	var ev := 0.0
	var samples := 24
	for k in range(samples):
		var vals := []
		for d in dice:
			vals.append(rng.randi_range(1, 6))
		ev += _best_partition_value(vals, _whites(dice))
	ev /= samples
	return ev > cur + 0.2


func _vals(dice: Array) -> Array:
	return dice.map(func(d): return int(d["v"]))


func _whites(dice: Array) -> Array:
	return dice.map(func(d): return bool(d["white"]))


# ------------------------------------------------------------------ consiglieri

## Valore della ricompensa del consigliere a per questo giocatore.
func adv_value(a: int) -> float:
	if a == _eng.POL5:
		return maxf(_bundle_value({"any": 1}), _bundle_value({"p2": 2}))
	if a == _eng.POL10:
		return _bundle_value({"any": 1, "p2": 1, "vp": 1})
	var extra := 0.0
	if _eng.stars.has(a):
		extra += _bundle_value({_eng.stars[a]: 1})
	if _eng.fate("chiamata"):
		var stable: bool = _p()["bld"][D.B_SCUDERIA]
		if (not stable and a in [5, 10, 18]) or (stable and a >= 11):
			extra += _solv[0]
	if _eng.cap_tiles.has(a):
		return _capriccio_value(a) + extra
	return _base_adv_value(a) + extra


func _capriccio_value(a: int) -> float:
	match a:
		1:
			for k in range(2, 19):
				if not _eng.is_taken(k):
					return _base_adv_value(k) * 0.8
			return 0.0
		2: return _bundle_value({"p2": 2})
		3: return _bundle_value({"any": 1}) * 0.7
		4: return _bundle_value({"any": 1})
		5: return _bundle_value({_eng.cap5: 1}) if _eng.cap5 != "" else 0.8
		6: return 0.7
		7: return _bundle_value({"any": 2}) * 0.8
		8: return _bundle_value({"any": 2}) * 0.75
		9: return _bundle_value({"any": 2})
		10: return maxf(_bundle_value({"g": 2}), maxf(_bundle_value({"w": 2}), _bundle_value({"s": 2})))
		11: return _bundle_value({"s": 1, "sol": 1, "vp": 1})
		12: return maxf(_bundle_value({"g": 3}), _bundle_value({"vp": 3})) - 0.3 * (_eng.n - 1)
		13: return _bundle_value({"any": 1, "p2": 1, "vp": 1, "sol": 1}) + 0.25
		14: return _bundle_value({"g": 1, "w": 1, "s": 1, "p2": 1}) * 0.9
		15: return _bundle_value({"any": 4})
		16: return 5.0
	return 0.0


func _base_adv_value(a: int) -> float:
	var r: Dictionary = D.ADVISORS[a]["r"]
	var v := 0.0
	var base := {}
	for t in D.GOODS:
		if r.get(t, 0) > 0:
			base[t] = r[t]
	if r.get("vp", 0) > 0:
		base["vp"] = r["vp"]
	if r.get("sol", 0) > 0:
		base["sol"] = r["sol"] + (1 if _p()["bld"][D.B_SCUDERIA] else 0)
	if r.get("p2", 0) > 0:
		base["p2"] = r["p2"]
	if r.get("any", 0) > 0:
		base["any"] = r["any"]
	v = _bundle_value(base)
	if r.has("or"):
		var bo := 0.0
		for o in r["or"]:
			bo = maxf(bo, _bundle_value(o))
		v += bo
	if r.has("alch"):
		var best := 0.0
		for t in D.GOODS:
			if _p()["goods"][t] > 0:
				var g := -_good_value(t, -1)
				for t2 in D.GOODS:
					if t2 != t:
						g += _good_value(t2)
				best = maxf(best, g)
		v += maxf(0.0, best)
	if r.has("spy"):
		var gain := 0.0
		var acc := {"g": 0, "w": 0, "s": 0}
		for k in range(3):
			var t := _best_good(acc)
			gain += _good_value(t, acc[t])
			acc[t] += 1
		v += maxf(0.0, gain - _vp_value())
	if r.get("peek", false) and _p()["known"].get(_eng.year, []).is_empty() and _eng.phase <= 6:
		v += 0.25
	return v


func _adv_values() -> Dictionary:
	var out := {}
	for a in range(1, 19):
		out[a] = adv_value(a) if _eng.adv_allowed(_seat, a) else -50.0
	out[_eng.POL5] = adv_value(_eng.POL5)
	out[_eng.POL10] = adv_value(_eng.POL10)
	return out


## Miglior valore totale ottenibile dai dadi indicati sui consiglieri liberi (ricerca esaustiva).
func _best_partition_value(vals: Array, whites: Array) -> float:
	var av := _adv_values()
	var p := _p()
	var can_mk: bool = p["bld"][D.B_MERCATO] and not p["used"].get("market", false)
	var r := _search(vals, whites, (1 << vals.size()) - 1, {}, (0 if p["used"].get("p2", false) else mini(p["p2"], 1)), can_mk, av, {})
	return r["v"]


## Ricerca: assegna gruppi di dadi ai consiglieri liberi. Restituisce {"v": valore, "first": mossa}.
func _search(vals: Array, whites: Array, mask: int, used: Dictionary, p2: int, mk: bool, av: Dictionary, memo: Dictionary) -> Dictionary:
	if mask == 0:
		return {"v": 0.0}
	var key := "%d|%s|%d|%s" % [mask, str(used.keys()), p2, mk]
	if memo.has(key):
		return memo[key]
	# il dado più basso del gruppo rimanente: o resta inutilizzato o fa parte di un gruppo
	var low := 0
	while not (mask & (1 << low)):
		low += 1
	var best := _search(vals, whites, mask & ~(1 << low), used, p2, mk, av, memo).duplicate()
	var rest := mask & ~(1 << low)
	# enumera i sottoinsiemi di rest da aggiungere al dado low
	var sub := rest
	while true:
		var g := sub | (1 << low)
		var tot := 0
		var colored := false
		for k in range(vals.size()):
			if g & (1 << k):
				tot += int(vals[k])
				if not whites[k]:
					colored = true
		if colored:
			for pp in ([0, 1] if p2 > 0 else [0]):
				for m in ([0, -1, 1] if mk else [0]):
					var a: int = tot + 2 * pp + m
					if a < 1 or a > 18 or used.has(a) or _eng.is_taken(a) or av[a] < -10.0:
						continue
					var used2 := used.duplicate()
					used2[a] = true
					var r := _search(vals, whites, mask & ~g, used2, p2 - pp, mk and m == 0, av, memo)
					var v: float = av[a] + r["v"] - 0.05 * pp - (0.1 if m != 0 else 0.0)
					if v > best["v"]:
						best = {"v": v, "a": a, "g": g, "pp": pp, "m": m}
		if sub == 0:
			break
		sub = (sub - 1) & rest
	memo[key] = best
	return best


## Quanto un avversario può arrivare a un consigliere libero in questa stagione (per l'urgenza).
func _threat(a: int) -> float:
	var t := 0.0
	for q in _eng.players:
		if q["seat"] == _seat or q["passed"]:
			continue
		var free := _eng.free_dice(q["seat"])
		var m := free.size()
		var reach := false
		for mask in range(1, 1 << m):
			var tot := 0
			var colored := false
			for k in range(m):
				if mask & (1 << k):
					var d: Dictionary = q["dice"][free[k]]
					tot += int(d["v"])
					if not d["white"]:
						colored = true
			if colored and (tot == a or (q["p2"] > 0 and tot + 2 == a)):
				reach = true
				break
		if reach:
			t += 1.0
	return t


func _influence(moves: Array):
	var p := _p()
	var free := _eng.free_dice(_seat)
	var vals := []
	var whites := []
	for i in free:
		vals.append(int(p["dice"][i]["v"]))
		whites.append(bool(p["dice"][i]["white"]))
	var av := _adv_values()
	var can_mk: bool = p["bld"][D.B_MERCATO] and not p["used"].get("market", false)
	# valutazione di ogni mossa: valore del consigliere + miglior uso dei dadi rimanenti
	var best_mv: Dictionary = {}
	var best_v := 0.0
	var memo := {}
	for mv in moves:
		var g := 0
		for di in mv["dice"]:
			g |= 1 << free.find(di)
		var a: int = mv["adv"]
		var gain: float = av[a]
		if mv["env"]:
			gain *= 1.0
		var used := {a: true}
		var rest := _search(vals, whites, ((1 << vals.size()) - 1) & ~g, used, (0 if (p["used"].get("p2", false) or mv["p2"] > 0) else mini(p["p2"], 1)), can_mk and mv["mk"] == 0, av, memo)
		var v: float = gain + rest["v"] - 0.05 * mv["p2"] - (0.1 if mv["mk"] != 0 else 0.0) - (0.15 if mv["it"] else 0.0)
		if mv["env"]:
			# l'Agente del Re si usa solo se ne vale davvero la pena
			v -= W["envoy"]
		if level >= 1 and a <= 18:
			# prima i consiglieri che gli avversari possono rubare
			v += W["threat"] * av[a] * minf(2.0, _threat(a))
		if a <= 18:
			v += W["deny"] * _deny_value(a)
		if level == 0:
			v *= rng.randf_range(0.7, 1.3)
		if v > best_v:
			best_v = v
			best_mv = mv
	if best_mv.is_empty():
		return {"pass": true}
	return best_mv


## Quanto il consigliere a interessa agli avversari che possono raggiungerlo.
func _deny_value(a: int) -> float:
	var r: Dictionary = D.ADVISORS[a]["r"]
	var v := 0.0
	v += r.get("vp", 0) * 1.0 + r.get("any", 0) * 0.8 + r.get("g", 0) * 0.5 + r.get("sol", 0) * 0.4
	return v * minf(1.0, _threat(a))


# ------------------------------------------------------------------ costruzione

func _build(options: Array, second: bool):
	var best := -1
	var bv := 0.0
	var p := _p()
	for b in options:
		var cost := _eng.payment(_seat, _eng.building_cost(_seat, b))
		var c := 0.0
		var acc := {"g": 0, "w": 0, "s": 0}
		for t in D.GOODS:
			for k in range(cost.get(t, 0)):
				acc[t] -= 1
				c += _good_value(t, acc[t]) * W["bcost"]
		var v := _building_value(b) - c
		if second:
			v -= W["second"]
		if level == 0:
			v *= rng.randf_range(0.6, 1.4)
		if v > bv:
			bv = v
			best = b
	return best


func _recruit(cp: int, p2ok := false):
	var p := _p()
	var goods: Dictionary = p["goods"].duplicate()
	var p2 := int(p["p2"]) if p2ok else 0
	var best_k := 0
	var best_v := 0.0
	var best_pay := {"g": 0, "w": 0, "s": 0, "p2": 0}
	var base := _battle_ev(p["sol"])
	var pay := {"g": 0, "w": 0, "s": 0, "p2": 0}
	var cost := 0.0
	var max_k := (_eng.n_goods(_seat) + p2) / cp
	for k in range(1, max_k + 1):
		for c in range(cp):
			# paga con ciò che vale meno
			var worst := ""
			var wv := 99.0
			if pay["p2"] < p2:
				worst = "p2"
				wv = W["p2"]
			for t in D.GOODS:
				if goods[t] - pay[t] > 0:
					var v := _good_value(t, -pay[t] - 1)
					if v < wv:
						wv = v
						worst = t
			if worst == "":
				break
			pay[worst] += 1
			cost += wv
		var gain := _battle_ev(p["sol"] + k) - base
		var net := gain - cost
		if net > best_v + 0.05:
			best_v = net
			best_k = k
			best_pay = pay.duplicate()
	return {"n": best_k, "pay": best_pay}
