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
var rng := RandomNumberGenerator.new()

var _eng: KBEngine
var _seat := -1
var _gv := {}                    # valore marginale delle merci (piano attuale)
var _need := {}
var _solv := []                  # valore del k-esimo soldato in più


func decide(eng: KBEngine, seat: int, req: Dictionary):
	_eng = eng
	_seat = seat
	_prepare()
	match str(req.get("type", "")):
		"goods":
			return _choose_goods(int(req["n"]))
		"lose":
			return _choose_lose(int(req["n"]))
		"pick":
			return _pick(req)
		"reroll_statue":
			return _statue()
		"reroll_chapel":
			return _chapel()
		"influence":
			return _influence(req["moves"])
		"build":
			return _build(req["options"], bool(req.get("second", false)))
		"recruit":
			return _recruit(int(req["cost_per"]))
		"ack":
			return true
	return null


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
	for row in range(5):
		for col in range(4):
			var b := row * 4 + col
			if p["bld"][b]:
				continue
			# raggiungibile se mancano al massimo 1 edificio a sinistra
			var missing := 0
			for c in range(col):
				if not p["bld"][row * 4 + c]:
					missing += 1
			if missing > 1:
				break
			var cost := _eng.building_cost(_seat, b)
			var ctot := 0
			for t in D.GOODS:
				ctot += cost.get(t, 0)
			var val := _building_value(b)
			if missing == 1:
				val *= 0.55
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
	var base: float = {"g": 1.05, "w": 0.9, "s": 0.95}[t]
	if level == 0:
		return base
	var deficit: int = _gv[t]["deficit"] - extra
	var v: float = base
	if deficit > 0:
		v += 0.75
	elif extra + _p()["goods"][t] > _need.get(t, 0) + 2:
		v -= 0.25
	if late <= 2:
		v *= 0.75
	return v


func _bundle_value(b: Dictionary) -> float:
	var v := 0.0
	var acc := {"g": 0, "w": 0, "s": 0}
	for t in D.GOODS:
		for k in range(b.get(t, 0)):
			v += _good_value(t, acc[t])
			acc[t] += 1
	if b.get("any", 0) > 0:
		for k in range(b["any"]):
			var bt := _best_good(acc)
			v += _good_value(bt, acc[bt])
			acc[bt] += 1
	v += b.get("vp", 0) * _vp_value()
	if b.get("sol", 0) > 0:
		for k in range(b["sol"]):
			v += _solv[mini(k, _solv.size() - 1)]
	if b.get("p2", 0) > 0:
		v += b["p2"] * (0.95 if _p()["bld"][D.B_MUNICIPIO] else 0.65) * (1.0 if _seasons_left() > 1 else 0.3)
	return v


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
	var W := float(_winters_left())
	var v := float(D.BUILDINGS[b]["vp"])
	var batt := 0.75 * W
	match b:
		D.B_STATUA: v += 0.12 * R
		D.B_CAPPELLA: v += 0.25 * R
		D.B_CHIESA: v += 0.15 * W
		D.B_CATTEDRALE: v += 1.5
		D.B_LOCANDA: v += 0.6 * ceilf(R / 3.0)
		D.B_MERCATO: v += 0.35 * R
		D.B_FATTORIE: v += 0.9 * R - 0.6 * W
		D.B_GILDA_MERC: v += 1.0 * R
		D.B_TORRE, D.B_FUCINA: v += batt
		D.B_CASERMA: v += 0.7 * W
		D.B_GILDA_MAGHI: v += 2.0 * batt
		D.B_PALIZZATA: v += batt * 1.1
		D.B_SCUDERIA: v += 0.3 * R
		D.B_MURA: v += batt * 1.3
		D.B_FORTEZZA: v += batt + 0.5 * W
		D.B_BARRICATA: v += 0.25 * W
		D.B_ARGANO: v += 0.25 * R
		D.B_MUNICIPIO: v += 0.6 * R
		D.B_AMBASCIATA: v += 1.0 * R
	# sblocca l'edificio successivo della riga
	if D.building_col(b) < 3 and R > 1:
		v += 0.25 * D.BUILDINGS[b + 1]["vp"] * minf(1.0, R / 6.0)
	return v


# ------------------------------------------------------------------ battaglia attesa

func _possible_cards() -> Array:
	var y := _eng.year
	if _p()["known"].get(y, false):
		return [_eng.deck[y - 1]]
	var out := []
	for k in range(D.INVADERS.size()):
		if D.INVADERS[k]["year"] == y:
			out.append(k)
	return out


## Valore atteso della battaglia con `sol` soldati (dado del Re incluso).
func _battle_ev(sol: int) -> float:
	var cards := _possible_cards()
	var tot := 0.0
	var cnt := 0
	for ci in cards:
		var card: Dictionary = D.INVADERS[ci]
		var bonus := _eng.battle_bonus(_seat, card["race"])
		var pen_v := _penalty_value(card["pen"])
		var rew_v := _reward_value(card["rew"])
		for die in range(1, 7):
			var t: int = sol + die + bonus
			if t > card["str"] or (t == card["str"] and _p()["bld"][D.B_MURA]):
				tot += rew_v + (1.0 if _p()["bld"][D.B_FORTEZZA] else 0.0) + 0.35
			elif t < card["str"]:
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
			v += D.BUILDINGS[b]["vp"] + 1.2
	v += pen.get("vp", 0)
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


func _choose_lose(n: int) -> Dictionary:
	var g: Dictionary = _p()["goods"].duplicate()
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
	if ctx == "spy":
		var gain := 0.0
		var acc := {"g": 0, "w": 0, "s": 0}
		for k in range(3):
			var t := _best_good(acc)
			gain += _good_value(t, acc[t])
			acc[t] += 1
		return 1 if gain > _vp_value() + 0.6 else 0
	if ctx == "alch":
		var best := 0
		var bv := 0.15
		for i in range(1, opts.size()):
			var give: String = opts[i]["val"]
			var v := -_good_value(give, -1)
			for t in D.GOODS:
				if t != give:
					v += _good_value(t)
			if v > bv:
				bv = v
				best = i
		return best
	if ctx == "townhall":
		var best2 := 0
		var bv2 := 0.0
		for i in range(1, opts.size()):
			var val: String = opts[i]["val"]
			var cost := 0.65 if val == "p2" else _good_value(val, -1)
			if _seasons_left() <= 1:
				cost *= 0.3
			var v2 := _vp_value() - cost
			if v2 > bv2:
				bv2 = v2
				best2 = i
		return best2
	# alternative di merci (Mercante, Capocaccia, Armaiolo)
	var bi := 0
	var bvv := -99.0
	for i in range(opts.size()):
		var o = opts[i]["val"]
		var v3 := _bundle_value(o) if o is Dictionary else 0.0
		if v3 > bvv:
			bvv = v3
			bi = i
	return bi


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
	if r.get("peek", false) and not _p()["known"].get(_eng.year, false) and _eng.phase <= 6:
		v += 0.25
	return v


func _adv_values() -> Dictionary:
	var out := {}
	for a in range(1, 19):
		out[a] = adv_value(a)
	return out


## Miglior valore totale ottenibile dai dadi indicati sui consiglieri liberi (ricerca esaustiva).
func _best_partition_value(vals: Array, whites: Array) -> float:
	var av := _adv_values()
	var p := _p()
	var can_mk: bool = p["bld"][D.B_MERCATO] and not p["used"].get("market", false)
	var r := _search(vals, whites, (1 << vals.size()) - 1, {}, mini(p["p2"], 2), can_mk, av, {})
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
					if a < 1 or a > 18 or used.has(a) or _eng.is_taken(a):
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
		var rest := _search(vals, whites, ((1 << vals.size()) - 1) & ~g, used, mini(p["p2"] - mv["p2"], 2), can_mk and mv["mk"] == 0, av, memo)
		var v: float = gain + rest["v"] - 0.05 * mv["p2"] - (0.1 if mv["mk"] != 0 else 0.0)
		if mv["env"]:
			# l'Agente del Re si usa solo se ne vale davvero la pena
			v -= 1.2
		if level >= 1:
			# prima i consiglieri che gli avversari possono rubare
			v += 0.12 * av[a] * minf(2.0, _threat(a))
		if level >= 2:
			v += 0.08 * _deny_value(a)
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
		var cost := _eng.building_cost(_seat, b)
		var c := 0.0
		var acc := {"g": 0, "w": 0, "s": 0}
		for t in D.GOODS:
			for k in range(cost.get(t, 0)):
				acc[t] -= 1
				c += _good_value(t, acc[t]) * 0.55
		var v := _building_value(b) - c
		if second:
			v -= 0.8
		if level == 0:
			v *= rng.randf_range(0.6, 1.4)
		if v > bv:
			bv = v
			best = b
	return best


func _recruit(cp: int):
	var p := _p()
	var goods: Dictionary = p["goods"].duplicate()
	var best_k := 0
	var best_v := 0.0
	var best_pay := {"g": 0, "w": 0, "s": 0}
	var base := _battle_ev(p["sol"])
	var pay := {"g": 0, "w": 0, "s": 0}
	var cost := 0.0
	var max_k := _eng.n_goods(_seat) / cp
	for k in range(1, max_k + 1):
		for c in range(cp):
			# paga con la merce che vale meno
			var worst := ""
			var wv := 99.0
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
