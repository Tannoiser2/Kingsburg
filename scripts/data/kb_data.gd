class_name KBData
extends RefCounted
## Dati di Kingsburg (seconda edizione, gioco base): Consiglieri, edifici, Invasori, colori dei
## giocatori e coordinate sul tabellone principale (in frazioni 0..1 dell'immagine).

const GOODS := ["g", "w", "s"]
const GOOD_NAMES := {"g": "Oro", "w": "Legno", "s": "Pietra"}
const GOOD_NAMES_PL := {"g": "Oro", "w": "Legno", "s": "Pietra"}

const COLORS := [
	{"id": 0, "key": "red", "name": "Rosso", "house": "Leone", "col": Color("#c8302a"), "light": Color("#f07a6e")},
	{"id": 1, "key": "yellow", "name": "Giallo", "house": "Cervo", "col": Color("#d9a21a"), "light": Color("#ffd25a")},
	{"id": 2, "key": "blue", "name": "Blu", "house": "Ariete", "col": Color("#2850a8"), "light": Color("#7aa0ff")},
	{"id": 3, "key": "black", "name": "Nero", "house": "Aquila", "col": Color("#2a2a2a"), "light": Color("#bdbdbd")},
	{"id": 4, "key": "green", "name": "Verde", "house": "Drago", "col": Color("#2a8a4a"), "light": Color("#6fe39a")},
]

## Consiglieri 1..18. r = ricompensa:
##  vp, g, w, s, sol (soldati), p2 (gettoni +2), any (merci a scelta), or (alternative), alch, spy, peek
const ADVISORS := {
	1: {"name": "Giullare", "text": "1 Punto Vittoria", "r": {"vp": 1}},
	2: {"name": "Signorotto", "text": "1 Oro", "r": {"g": 1}},
	3: {"name": "Architetto", "text": "1 Legno", "r": {"w": 1}},
	4: {"name": "Mercante", "text": "1 Oro oppure 1 Legno", "r": {"or": [{"g": 1}, {"w": 1}]}},
	5: {"name": "Sergente", "text": "1 soldato", "r": {"sol": 1}},
	6: {"name": "Alchimista", "text": "Cedi 1 merce per ricevere una unità di ciascuna delle altre due", "r": {"alch": true}},
	7: {"name": "Astronomo", "text": "1 merce a scelta e un gettone +2", "r": {"any": 1, "p2": 1}},
	8: {"name": "Tesoriere", "text": "2 Ori", "r": {"g": 2}},
	9: {"name": "Capocaccia", "text": "1 Oro e 1 Legno oppure 1 Pietra e 1 Legno", "r": {"or": [{"g": 1, "w": 1}, {"s": 1, "w": 1}]}},
	10: {"name": "Generale", "text": "2 soldati e guardi la carta Invasori", "r": {"sol": 2, "peek": true}},
	11: {"name": "Armaiolo", "text": "1 Oro e 1 Pietra oppure 1 Pietra e 1 Legno", "r": {"or": [{"g": 1, "s": 1}, {"s": 1, "w": 1}]}},
	12: {"name": "Nobildonna", "text": "2 merci a scelta e un gettone +2", "r": {"any": 2, "p2": 1}},
	13: {"name": "Campione", "text": "3 Pietre", "r": {"s": 3}},
	14: {"name": "Spia", "text": "Puoi pagare 1 PV per ricevere 3 merci a scelta", "r": {"spy": true}},
	15: {"name": "Inventore", "text": "1 Pietra, 1 Oro e 1 Legno", "r": {"g": 1, "w": 1, "s": 1}},
	16: {"name": "Mago", "text": "4 Ori", "r": {"g": 4}},
	17: {"name": "Regina", "text": "2 merci a scelta, 3 PV e guardi la carta Invasori", "r": {"any": 2, "vp": 3, "peek": true}},
	18: {"name": "Re", "text": "1 Oro, 1 Pietra, 1 Legno e 1 soldato", "r": {"g": 1, "w": 1, "s": 1, "sol": 1}},
}

## Edifici: id = riga * 4 + colonna (righe B..F del tabellone Provincia, colonne I..IV).
const BUILDINGS := [
	{"name": "Statua", "cost": {"g": 2}, "vp": 3, "text": "All'inizio di ogni stagione, se hai lo stesso numero su tutti i tuoi dadi produttivi, puoi rilanciarne uno."},
	{"name": "Cappella", "cost": {"g": 3, "s": 1}, "vp": 5, "text": "All'inizio di ogni stagione, se la somma dei tuoi dadi produttivi è 7 o meno, puoi rilanciarli tutti."},
	{"name": "Chiesa", "cost": {"g": 3, "w": 1, "s": 2}, "vp": 7, "text": "+0 in battaglia (diventa +1 contro i Demoni)."},
	{"name": "Cattedrale", "cost": {"g": 5, "s": 3}, "vp": 9, "text": "A fine partita ricevi 1 PV extra per ogni 2 merci che possiedi."},
	{"name": "Locanda", "cost": {"g": 1, "w": 1}, "vp": 0, "text": "Alla fine di ogni Estate ricevi un gettone +2."},
	{"name": "Mercato", "cost": {"g": 2, "w": 2}, "vp": 1, "text": "Una volta a stagione puoi influenzare un Consigliere il cui valore è di un punto inferiore o superiore alla somma dei dadi che usi."},
	{"name": "Fattorie", "cost": {"g": 2, "w": 3, "s": 1}, "vp": 2, "text": "In ogni stagione produttiva lanci un dado bianco extra. Malus di -1 in battaglia."},
	{"name": "Gilda dei Mercanti", "cost": {"g": 3, "w": 1, "s": 2}, "vp": 4, "text": "All'inizio di ogni stagione produttiva, prima di tirare i dadi, ricevi 1 Oro."},
	{"name": "Torre di Guardia", "cost": {"g": 1, "s": 1}, "vp": 1, "text": "+1 in battaglia."},
	{"name": "Fucina", "cost": {"g": 1, "w": 2}, "vp": 2, "text": "+1 in battaglia."},
	{"name": "Caserma", "cost": {"g": 2, "w": 2, "s": 1}, "vp": 4, "text": "Paghi solo una merce per reclutare ciascun soldato nella fase 7."},
	{"name": "Gilda dei Maghi", "cost": {"g": 3, "w": 2, "s": 2}, "vp": 6, "text": "+2 in battaglia."},
	{"name": "Palizzata", "cost": {"w": 2}, "vp": 0, "text": "+1 in battaglia (diventa +2 contro gli Zombi)."},
	{"name": "Scuderia", "cost": {"g": 1, "w": 1, "s": 1}, "vp": 2, "text": "+1 soldato quando influenzi un Consigliere che dia almeno 1 soldato."},
	{"name": "Mura", "cost": {"g": 2, "s": 2}, "vp": 2, "text": "+1 in battaglia. Inoltre, in battaglia vinci i pareggi."},
	{"name": "Fortezza", "cost": {"g": 3, "s": 2}, "vp": 4, "text": "+1 in battaglia. Inoltre, quando vinci una battaglia, ricevi 1 PV oltre alle normali ricompense."},
	{"name": "Barricata", "cost": {"w": 1}, "vp": 0, "text": "+0 in battaglia (diventa +1 contro i Goblin)."},
	{"name": "Argano", "cost": {"w": 1, "s": 1}, "vp": 1, "text": "Tutti gli edifici delle colonne III e IV ti costano 1 Oro in meno."},
	{"name": "Municipio", "cost": {"g": 2, "w": 1, "s": 1}, "vp": 2, "text": "Alla fine di ogni stagione produttiva puoi pagare un gettone +2 o una merce per ricevere 1 PV (al massimo una volta a stagione)."},
	{"name": "Ambasciata", "cost": {"g": 2, "w": 2, "s": 2}, "vp": 4, "text": "Alla fine di ogni stagione produttiva ricevi 1 PV."},
]

const B_STATUA := 0
const B_CAPPELLA := 1
const B_CHIESA := 2
const B_CATTEDRALE := 3
const B_LOCANDA := 4
const B_MERCATO := 5
const B_FATTORIE := 6
const B_GILDA_MERC := 7
const B_TORRE := 8
const B_FUCINA := 9
const B_CASERMA := 10
const B_GILDA_MAGHI := 11
const B_PALIZZATA := 12
const B_SCUDERIA := 13
const B_MURA := 14
const B_FORTEZZA := 15
const B_BARRICATA := 16
const B_ARGANO := 17
const B_MUNICIPIO := 18
const B_AMBASCIATA := 19

const RACE_NAMES := {"goblin": "Goblin", "orchi": "Orchi", "zombi": "Zombi", "barbari": "Barbari", "demoni": "Demoni", "draghi": "Draghi"}

## Carte Invasori (indice = posizione nel foglio delle immagini). pen = penalità in caso di sconfitta
## (nell'ordine: oro, legno, pietra, merci a scelta, edifici, PV); rew = ricompense in caso di vittoria.
const INVADERS := [
	{"year": 1, "str": 2, "race": "goblin", "pen": {"w": 1, "s": 1, "vp": 1, "bld": 1}, "rew": {"w": 1}},
	{"year": 1, "str": 3, "race": "goblin", "pen": {"g": 1, "bld": 1}, "rew": {"s": 1}},
	{"year": 1, "str": 3, "race": "orchi", "pen": {"any": 2, "vp": 1}, "rew": {"g": 1}},
	{"year": 1, "str": 4, "race": "zombi", "pen": {"vp": 2}, "rew": {"vp": 1}},
	{"year": 1, "str": 2, "race": "barbari", "pen": {"any": 1, "bld": 1}, "rew": {"g": 1}},
	{"year": 4, "str": 7, "race": "orchi", "pen": {"any": 2, "bld": 1}, "rew": {"any": 1}},
	{"year": 4, "str": 6, "race": "demoni", "pen": {"any": 4, "vp": 1}, "rew": {"g": 1, "vp": 1}},
	{"year": 4, "str": 5, "race": "goblin", "pen": {"w": 4, "s": 4, "vp": 1, "bld": 1}, "rew": {"w": 1}},
	{"year": 4, "str": 6, "race": "goblin", "pen": {"g": 4, "bld": 1}, "rew": {"s": 1}},
	{"year": 4, "str": 7, "race": "zombi", "pen": {"vp": 2}, "rew": {"vp": 1}},
	{"year": 5, "str": 8, "race": "demoni", "pen": {"bld": 1, "vp": 2}, "rew": {"vp": 2}},
	{"year": 5, "str": 9, "race": "draghi", "pen": {"vp": 5}, "rew": {"vp": 3}},
	{"year": 5, "str": 7, "race": "barbari", "pen": {"vp": 8}, "rew": {"vp": 1}},
	{"year": 5, "str": 9, "race": "demoni", "pen": {"bld": 1}, "rew": {"vp": 2}},
	{"year": 5, "str": 8, "race": "barbari", "pen": {"bld": 1}, "rew": {"vp": 1}},
	{"year": 2, "str": 5, "race": "barbari", "pen": {"any": 2, "vp": 1}, "rew": {"g": 1}},
	{"year": 2, "str": 5, "race": "zombi", "pen": {"vp": 2}, "rew": {"vp": 1}},
	{"year": 2, "str": 4, "race": "orchi", "pen": {"any": 2, "bld": 1}, "rew": {"g": 1}},
	{"year": 2, "str": 3, "race": "goblin", "pen": {"w": 2, "s": 2, "vp": 1, "bld": 1}, "rew": {"w": 1}},
	{"year": 2, "str": 4, "race": "goblin", "pen": {"g": 2, "bld": 1}, "rew": {"s": 1}},
	{"year": 3, "str": 6, "race": "demoni", "pen": {"g": 2, "w": 1, "s": 1, "vp": 1}, "rew": {"vp": 1}},
	{"year": 3, "str": 5, "race": "goblin", "pen": {"g": 3, "bld": 1}, "rew": {"s": 1}},
	{"year": 3, "str": 4, "race": "goblin", "pen": {"w": 3, "s": 3, "vp": 1, "bld": 1}, "rew": {"w": 1}},
	{"year": 3, "str": 6, "race": "zombi", "pen": {"vp": 2}, "rew": {"vp": 1}},
	{"year": 3, "str": 5, "race": "orchi", "pen": {"any": 2, "bld": 1}, "rew": {"g": 1}},
]

const YEAR_RANGE := {1: "2-4", 2: "3-5", 3: "4-6", 4: "5-7", 5: "7-9"}

const PHASE_NAMES := ["", "Aiuto del Re", "Primavera", "Premio del Re", "Estate", "Agente del Re", "Autunno", "Mercenari", "Inverno"]
const SEASON_NAMES := ["Primavera", "Estate", "Autunno"]
const ROMAN := ["", "I", "II", "III", "IV", "V"]

# ------------------------------------------------------------------ coordinate tabellone
# Frazioni dell'immagine del tabellone (quadrata).

## Centro del ritratto di ogni Consigliere (dove si appoggiano i dadi).
const ADV_POS := {
	17: Vector2(615, 380), 18: Vector2(790, 380),
	13: Vector2(440, 590), 14: Vector2(615, 590), 15: Vector2(790, 590), 16: Vector2(965, 590),
	7: Vector2(265, 810), 8: Vector2(440, 810), 9: Vector2(615, 810), 10: Vector2(790, 810), 11: Vector2(965, 810), 12: Vector2(1140, 810),
	1: Vector2(225, 1035), 2: Vector2(415, 1035), 3: Vector2(605, 1035), 4: Vector2(795, 1035), 5: Vector2(985, 1035), 6: Vector2(1175, 1035),
}
## Rettangolo cliccabile di ogni Consigliere (metà larghezza, metà altezza), in unità 1400.
const ADV_HALF := Vector2(80, 108)


static func adv_rect(a: int) -> Rect2:
	var c: Vector2 = ADV_POS[a]
	var cy := c.y + 10
	return Rect2((c.x - ADV_HALF.x) / 1400.0, (cy - ADV_HALF.y) / 1400.0, ADV_HALF.x * 2 / 1400.0, ADV_HALF.y * 2 / 1400.0)


static func adv_center(a: int) -> Vector2:
	return ADV_POS[a] / 1400.0


## Casella del segnapunti (0..59).
static func vp_pos(v: int) -> Vector2:
	v = posmod(v, 60)
	var lo := 40.0
	var hi := 1360.0
	var step := 87.5
	var p := Vector2.ZERO
	if v == 0:
		p = Vector2(lo, hi)
	elif v < 15:
		p = Vector2(lo, 1265 - (v - 1) * step)
	elif v == 15:
		p = Vector2(lo, lo)
	elif v < 30:
		p = Vector2(127 + (v - 16) * step, lo)
	elif v == 30:
		p = Vector2(hi, lo)
	elif v < 45:
		p = Vector2(hi, 127 + (v - 31) * step)
	elif v == 45:
		p = Vector2(hi, hi)
	else:
		p = Vector2(1265 - (v - 46) * step, hi)
	return p / 1400.0


## Casella della Tabella dei Soldati (0..20).
static func sol_pos(s: int) -> Vector2:
	s = clampi(s, 0, 20)
	return Vector2(137 + 56.2 * s, 130 if s % 2 == 0 else 176) / 1400.0


static func order_pos(i: int) -> Vector2:
	return Vector2(220, 352 + 60 * i) / 1400.0


static func year_pos(y: int) -> Vector2:
	var p: Vector2 = [Vector2(403, 300), Vector2(472, 300), Vector2(403, 370), Vector2(472, 370), Vector2(437, 440)][clampi(y - 1, 0, 4)]
	return p / 1400.0


static func season_pos(ph: int) -> Vector2:
	var p: Vector2 = [Vector2(140, 1222), Vector2(272, 1262), Vector2(410, 1180), Vector2(545, 1262), Vector2(680, 1180), Vector2(815, 1262), Vector2(950, 1180), Vector2(1258, 1222)][clampi(ph - 1, 0, 7)]
	return p / 1400.0


static func building_col(b: int) -> int:
	return b % 4


static func building_row(b: int) -> int:
	return b / 4


static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for t in GOODS:
		if cost.get(t, 0) > 0:
			parts.append("%d %s" % [cost[t], GOOD_NAMES[t]])
	return ", ".join(parts) if not parts.is_empty() else "gratis"


static func bundle_text(b: Dictionary) -> String:
	var parts := []
	for t in GOODS:
		if b.get(t, 0) > 0:
			parts.append("%d %s" % [b[t], GOOD_NAMES[t]])
	if b.get("any", 0) > 0:
		parts.append("%d merc%s a scelta" % [b["any"], "e" if b["any"] == 1 else "i"])
	if b.get("vp", 0) > 0:
		parts.append("%d PV" % b["vp"])
	if b.get("sol", 0) > 0:
		parts.append("%d soldat%s" % [b["sol"], "o" if b["sol"] == 1 else "i"])
	if b.get("p2", 0) > 0:
		parts.append("%d gettone +2" % b["p2"])
	if b.get("bld", 0) > 0:
		parts.append("%d edificio" % b["bld"])
	return ", ".join(parts)
