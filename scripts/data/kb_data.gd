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
	# --- espansione: linee A e G del retro del tabellone Provincia (modulo 1) ---
	{"name": "Segheria", "cost": {"w": 2, "s": 1}, "vp": 1, "text": "Alla fine di ogni Estate puoi trasformare 1 Legno in 2 Oro."},
	{"name": "Tagliapietre", "cost": {"g": 1, "w": 1, "s": 2}, "vp": 2, "text": "Alla fine di ogni Estate puoi trasformare 1 Pietra in 3 Oro."},
	{"name": "Oreficeria", "cost": {"g": 2, "w": 2, "s": 2}, "vp": 3, "text": "Alla fine di ogni Estate puoi pagare 1 Oro per ricevere 1 PV e 1 soldato."},
	{"name": "Zecca", "cost": {"g": 6, "w": 1, "s": 1}, "vp": 5, "text": "Puoi usare Segheria, Tagliapietre e Oreficeria anche alla fine di ogni Primavera e di ogni Autunno."},
	{"name": "Fortificazioni Sommarie", "cost": {"s": 1}, "vp": 0, "text": "+1 in battaglia, ma solo contro invasori di forza 5 o meno."},
	{"name": "Centro Reclutamento", "cost": {"g": 1, "w": 1}, "vp": 1, "text": "Nella fase 7 puoi usare i gettoni +2 come fossero merci."},
	{"name": "Campo Addestramento", "cost": {"g": 1, "w": 2}, "vp": 2, "text": "Alla fine dell'Autunno, se hai meno di 2 soldati, ricevi 1 soldato."},
	{"name": "Accademia Militare", "cost": {"g": 2, "w": 1, "s": 1}, "vp": 3, "text": "In Inverno tiri un dado: se è superiore al dado del Re, tu (solo) puoi usarlo invece di quello del Re per stabilire quanti rinforzi ricevi."},
	# --- linee alternative (modulo 2) ---
	{"name": "Giostra", "cost": {"g": 1, "w": 2}, "vp": 0, "text": "Alla fine di ogni Estate ricevi 1 PV."},
	{"name": "Circo", "cost": {"g": 1, "w": 3}, "vp": 2, "text": "Alla fine di ogni Estate ricevi 1 PV."},
	{"name": "Scuola dei Gladiatori", "cost": {"g": 2, "w": 1, "s": 2}, "vp": 4, "text": "+1 in battaglia."},
	{"name": "Arena", "cost": {"g": 2, "s": 4}, "vp": 6, "text": "Alla fine di ogni stagione produttiva, se nessun avversario ha più soldati di te, ricevi 1 PV."},
	{"name": "Ponte", "cost": {"s": 2}, "vp": 4, "text": "Nessun effetto."},
	{"name": "Altare", "cost": {"g": 2, "s": 2}, "vp": 4, "text": "All'inizio di ogni stagione produttiva, se la somma dei tuoi dadi è 9 o meno, puoi rilanciarli tutti (una volta a stagione)."},
	{"name": "Monastero", "cost": {"g": 1, "w": 2, "s": 2}, "vp": 5, "text": "Alla fine dell'Estate, se non hai merci, ricevi 1 PV."},
	{"name": "Duomo", "cost": {"g": 4, "w": 1, "s": 2}, "vp": 8, "text": "Non può essere distrutto (gli invasori lo ignorano quando determinano l'edificio da distruggere)."},
	{"name": "Birreria", "cost": {"g": 1, "w": 1}, "vp": 0, "text": "Alla fine di ogni Estate perdi un soldato e guadagni 1 PV e un gettone +2 (se non hai soldati, non ricevi nulla)."},
	{"name": "Mercato Itinerante", "cost": {"g": 1, "w": 2, "s": 1}, "vp": 1, "text": "Una volta a stagione puoi influenzare un Consigliere di valore 6 o meno usando un singolo dado colorato, indipendentemente dal suo valore."},
	{"name": "Vigne", "cost": {"g": 2, "w": 3}, "vp": 1, "text": "In Autunno tiri un dado bianco extra."},
	{"name": "Porto", "cost": {"g": 1, "w": 2, "s": 2}, "vp": 2, "text": "All'inizio di ogni stagione produttiva ricevi una merce a tua scelta."},
	{"name": "Torre di Vedetta", "cost": {"g": 1, "s": 1}, "vp": 0, "text": "+1 in battaglia. Inoltre, all'inizio del IV e del V anno guardi la carta Invasori."},
	{"name": "Armeria", "cost": {"w": 2, "s": 1}, "vp": 1, "text": "+2 in battaglia (diventa +0 contro Zombi e Demoni)."},
	{"name": "Quartieri delle Truppe", "cost": {"g": 1, "w": 3}, "vp": 3, "text": "Alla fine dell'Inverno, se hai vinto col miglior punteggio, puoi trattenere un soldato invece di congedarli tutti."},
	{"name": "Gilda degli Alchimisti", "cost": {"g": 2, "w": 2, "s": 2}, "vp": 5, "text": "+1 in battaglia (diventa +3 se paghi 1 Oro; decidi in Inverno, prima che siano svelati i nemici)."},
	{"name": "Piccola Palizzata", "cost": {"w": 1}, "vp": 0, "text": "+1 in battaglia, ma solo se hai almeno un soldato (all'inizio dell'Inverno)."},
	{"name": "Allevamento Grifoni", "cost": {"g": 1, "s": 2}, "vp": 2, "text": "All'inizio di ogni stagione produttiva, se la somma dei tuoi dadi è 9 o meno, ricevi 1 soldato."},
	{"name": "Mura con Bastioni", "cost": {"g": 2, "s": 1}, "vp": 2, "text": "+1 in battaglia se paghi 1 Pietra (decidi in Inverno, prima che siano svelati i nemici). Inoltre, in battaglia vinci i pareggi."},
	{"name": "Maniero", "cost": {"g": 3, "w": 1, "s": 1}, "vp": 5, "text": "Quando vinci una battaglia, ricevi due volte i premi (escluso l'eventuale PV per la miglior vittoria)."},
	{"name": "Rifugio Nascosto", "cost": {"w": 1}, "vp": 0, "text": "Se perdi una battaglia non perdi PV (ma subisci ancora gli altri effetti della sconfitta)."},
	{"name": "Falegnameria", "cost": {"w": 1, "s": 1}, "vp": 1, "text": "Tutti gli edifici delle colonne III e IV ti costano 1 Legno in meno."},
	{"name": "Ufficio del Cambio", "cost": {"g": 2, "w": 1, "s": 1}, "vp": 2, "text": "Alla fine di ogni Autunno puoi pagare una merce per ricevere 2 PV (una sola volta in ogni Autunno)."},
	{"name": "Gilda degli Architetti", "cost": {"g": 1, "w": 2, "s": 2}, "vp": 3, "text": "Ogni edificio che costruisci dopo vale per te 1 PV extra. Inoltre, se a fine partita nessun avversario ha più edifici di te, ricevi 3 PV."},
	{"name": "Fontana", "cost": {"s": 1}, "vp": 0, "text": "Se costruita nel I anno ricevi 3 PV, nel II anno 2 PV, nel III anno 1 PV."},
	{"name": "Parco", "cost": {"w": 2}, "vp": 1, "text": "In ogni stagione produttiva, se hai influenzato 3 Consiglieri, ricevi 1 PV."},
	{"name": "Scuola", "cost": {"g": 1, "w": 2}, "vp": 2, "text": "Alla fine della fase 7, se hai almeno 3 soldati, ricevi 2 PV."},
	{"name": "Università", "cost": {"g": 2, "w": 1, "s": 1}, "vp": 2, "text": "All'inizio di ogni stagione produttiva, se la somma dei tuoi dadi è 9 o meno, ricevi 2 PV."},
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

const B_SEGHERIA := 20
const B_TAGLIAPIETRE := 21
const B_OREFICERIA := 22
const B_ZECCA := 23
const B_FORT_SOMM := 24
const B_CENTRO_RECL := 25
const B_CAMPO_ADD := 26
const B_ACCADEMIA := 27
const B_GIOSTRA := 28
const B_CIRCO := 29
const B_GLADIATORI := 30
const B_ARENA := 31
const B_PONTE := 32
const B_ALTARE := 33
const B_MONASTERO := 34
const B_DUOMO := 35
const B_BIRRERIA := 36
const B_MERC_ITIN := 37
const B_VIGNE := 38
const B_PORTO := 39
const B_VEDETTA := 40
const B_ARMERIA := 41
const B_QUARTIERI := 42
const B_ALCHIMISTI := 43
const B_PICC_PALIZZ := 44
const B_GRIFONI := 45
const B_BASTIONI := 46
const B_MANIERO := 47
const B_RIFUGIO := 48
const B_FALEGNAMERIA := 49
const B_UFF_CAMBIO := 50
const B_GILDA_ARCH := 51
const B_FONTANA := 52
const B_PARCO := 53
const B_SCUOLA := 54
const B_UNIVERSITA := 55

## Linee di edifici. Fronte del tabellone Provincia: B..F; retro (modulo 1): A..G.
const LINES := {"A": [20, 21, 22, 23], "B": [0, 1, 2, 3], "C": [4, 5, 6, 7], "D": [8, 9, 10, 11],
	"E": [12, 13, 14, 15], "F": [16, 17, 18, 19], "G": [24, 25, 26, 27]}
## Linee alternative (modulo 2), che si sovrappongono a quella con la stessa lettera.
const ALT_LINES := {"A": [28, 29, 30, 31], "B": [32, 33, 34, 35], "C": [36, 37, 38, 39], "D": [40, 41, 42, 43],
	"E": [44, 45, 46, 47], "F": [48, 49, 50, 51], "G": [52, 53, 54, 55]}
const N_BUILDINGS := 56

## Governatori (modulo 3), nell'ordine delle immagini.
const GOVERNORS := [
	{"key": "stregone", "name": "Stregone", "text": "All'inizio del III anno costruisci fino a 3 edifici della prima colonna che ancora non possiedi, senza pagarne il costo e senza riceverne i PV."},
	{"key": "politico", "name": "Politico", "text": "In ogni stagione produttiva puoi schierare i tuoi dadi anche su questa carta: con 5 ricevi 1 merce a scelta oppure 2 gettoni +2; con 10 ricevi 1 merce a scelta, 1 gettone +2 e 1 PV."},
	{"key": "paladino", "name": "Paladino", "text": "Se perdi una battaglia, puoi scartare questa carta invece di subire i danni della sconfitta. Se a fine partita hai ancora questa carta, ricevi 3 PV."},
	{"key": "predicatore", "name": "Predicatore", "text": "Alla fine di ogni stagione produttiva, se uno o più giocatori non hanno costruito edifici, ricevi 1 PV."},
	{"key": "nobile", "name": "Nobile", "text": "Inizi il gioco con 6 PV."},
	{"key": "principe", "name": "Principe", "text": "In ogni stagione produttiva, se la somma dei tuoi dadi è 8 o meno, puoi trasformare i tre dadi colorati in 3, 4 e 6 (gli eventuali dadi bianchi non cambiano)."},
	{"key": "sacerdote", "name": "Sacerdote", "text": "Quando tiri un dado bianco, se esce 1 o 2 ricevi 1 PV. All'inizio di ogni stagione produttiva, prima di tirare, puoi invocare la benedizione divina: ogni giocatore che non dovrebbe tirare dadi bianchi ne tira uno, mentre ogni altro giocatore riceve 1 PV."},
	{"key": "truffatore", "name": "Truffatore", "text": "Puoi usare i gettoni +2 anche come +1 o come +3."},
	{"key": "principessa", "name": "Principessa", "text": "Inizi il gioco con l'Agente del Re, 1 Oro e 1 PV. Inoltre, nella fase 1 del primo anno solo tu ricevi l'Aiuto del Re."},
	{"key": "filosofo", "name": "Filosofo", "text": "In ogni stagione produttiva, se la somma dei tuoi dadi è 10 o meno, puoi ritirarli tutti. Se il nuovo totale è inferiore al vecchio e non lo modifichi più, ricevi 1 PV. Una volta a stagione."},
	{"key": "carpentiere", "name": "Carpentiere", "text": "Alla fine di ogni anno ricevi 1 Legno. Quando costruisci, puoi usare il Legno come fosse Oro."},
	{"key": "architetto", "name": "Architetto", "text": "In ciascuna stagione produttiva, se almeno un avversario ha più edifici di te, puoi costruire un edificio extra (pagandone il costo). A fine partita ricevi 5 PV se hai almeno 15 edifici."},
	{"key": "fata", "name": "Fata", "text": "Ogni Estate tiri un dado bianco extra."},
	{"key": "esattore", "name": "Esattore", "text": "Ogni volta che un avversario costruisce un edificio della IV colonna, ricevi una merce a tua scelta."},
	{"key": "ereditiera", "name": "Ereditiera", "text": "All'inizio del gioco metti su questa carta 2 Oro, 1 Legno, 1 Pietra e 2 gettoni +2. All'inizio di ogni stagione, se almeno uno dei tuoi dadi colorati è 1, puoi prendere una merce o un gettone dalla carta; se non ce ne sono più, ricevi 1 PV."},
	{"key": "duca", "name": "Duca", "text": "In ogni stagione produttiva, dopo che tutti hanno schierato i dadi, se nessuno ha influenzato la Nobildonna (12), puoi spostarvi i tuoi dadi dal Consigliere di valore maggiore che hai influenzato (indipendentemente dal loro valore). Con 2 giocatori non si usa."},
	{"key": "damigella", "name": "Damigella", "text": "All'inizio di ogni anno ricevi un gettone +2. Puoi usare più gettoni +2 nella stessa stagione, ma solo uno su ciascun Consigliere."},
	{"key": "generale", "name": "Generale", "text": "+1 in battaglia."},
	{"key": "ladro", "name": "Ladro", "text": "Inizi il gioco con 4 Oro ma con 3 PV in meno."},
	{"key": "intrigante", "name": "Intrigante", "text": "In ogni stagione produttiva, se almeno un avversario ha influenzato un Consigliere di valore 14 o più, ricevi 1 PV."},
	{"key": "minatore", "name": "Minatore", "text": "Alla fine di ogni anno ricevi 1 Oro. Alla fine del IV anno ricevi 1 Oro extra."},
	{"key": "mercenario", "name": "Mercenario", "text": "+2 in battaglia. Se vinci la battaglia non ricevi i premi, ma partecipi all'assegnazione del PV per chi ha vinto con il miglior totale."},
	{"key": "scultore", "name": "Scultore", "text": "Alla fine di ogni anno ricevi 1 Pietra. Quando costruisci, puoi usare la Pietra come fosse Oro."},
	{"key": "menestrello", "name": "Menestrello", "text": "Alla fine di ogni anno ricevi 1 PV se almeno un avversario ha più PV di te, e un altro se nessun avversario ha meno PV di te."},
]

## Carte Fato (modulo 4), nell'ordine delle immagini (29 carte, "Il Re è malato" due volte).
const FATE := [
	{"key": "prospero", "name": "Anno Prospero", "text": "In ogni stagione produttiva ogni giocatore che non dovrebbe tirare dadi bianchi ne tira uno, mentre ogni altro giocatore riceve una merce a sua scelta."},
	{"key": "fondi", "name": "Fondi Militari", "text": "Nella fase 7 chi non possiede la Caserma paga solo una merce per reclutare i soldati; chi la possiede ottiene 1 Oro."},
	{"key": "chiamata", "name": "Chiamata alle Armi", "text": "Chi non possiede le Scuderie ottiene +1 soldato quando influenza un Consigliere che dia almeno 1 soldato; chi le possiede ottiene 1 soldato quando influenza un Consigliere di valore 11 o più."},
	{"key": "diplomatici", "name": "Movimenti Diplomatici", "text": "Alla fine di ogni stagione produttiva chi non ha il Municipio o l'Ufficio del Cambio può pagare un gettone +2 o una merce per ricevere 1 PV (una volta a stagione). Chi li possiede, se li usa, riceve 1 PV extra."},
	{"key": "perdurante", "name": "Situazione Perdurante", "text": "Si applica lo stesso evento dell'anno precedente (se è il primo anno si pesca subito un'altra carta)."},
	{"key": "malato", "name": "Il Re è Malato!", "text": "Nessuno può influenzare il Re (18). Se il Re si era già ammalato, alla fine di quest'anno il Re muore e la partita termina."},
	{"key": "urbanistica", "name": "Espansione Urbanistica", "text": "Chi non possiede l'Argano o la Falegnameria paga 1 Oro in più per gli edifici delle colonne III e IV. Chi li possiede paga una merce (a scelta) in meno per gli edifici delle colonne I e II."},
	{"key": "nebbia", "name": "Nebbia di Guerra", "text": "Quando un giocatore dovrebbe guardare la carta Invasori riceve invece un gettone +2."},
	{"key": "tenaglia", "name": "Manovra a Tenaglia", "text": "Una seconda carta Invasori di quest'anno si aggiunge alla prima. Chi guarda gli Invasori sceglie quale delle due vedere. In Inverno si considera solo quella di Forza maggiore (a parità, quella sul tabellone)."},
	{"key": "foresta", "name": "Scoperta una Nuova Foresta", "text": "All'inizio di ogni stagione produttiva si tira un dado bianco: con 4 o più ogni giocatore riceve 1 Legno."},
	{"key": "tasse", "name": "Aumento delle Tasse", "text": "Alla fine dell'Autunno tutti devono pagare 2 Oro. Per ogni Oro che non pagano perdono 2 PV."},
	{"key": "nevicata", "name": "Nevicata Intensa", "text": "Quest'Inverno il Re invia 2 soldati a ciascuno invece di tirare il dado. Con i Rinforzi determinabili: un soldato in meno del gettone, e il gettone 0 non si può usare."},
	{"key": "flotta", "name": "Flotta Reale", "text": "Alla fine dell'Autunno tutti possono pagare fino a 2 Legno: per ogni Legno pagato ricevono 2 PV."},
	{"key": "parata", "name": "Parata Militare", "text": "Alla fine dell'Autunno chi ha più soldati riceve 1 PV (a parità tutti)."},
	{"key": "giurati", "name": "Nemici Giurati", "text": "In Inverno il premio per chi vince col punteggio più alto è di 2 PV (invece di uno)."},
	{"key": "inondazione", "name": "Inondazione", "text": "Alla fine dell'Autunno tutti devono pagare 2 Pietre. Chi ne paga solo una perde 2 PV; chi non paga nulla perde un edificio."},
	{"key": "feroci", "name": "Nemici Feroci", "text": "Gli invasori hanno +1 Forza in Inverno."},
	{"key": "numerosi", "name": "Nemici Numerosi", "text": "Goblin e Orchi hanno +1 Forza in Inverno."},
	{"key": "snob", "name": "Consiglieri Snob", "text": "In ogni stagione produttiva ogni dado che fa 6 diventa un 4 e ogni 5 diventa un 3 (anche nei rilanci)."},
	{"key": "riottosi", "name": "Lavoranti Riottosi", "text": "Quest'anno tutti gli edifici costano 1 Oro in più."},
	{"key": "carestia", "name": "Carestia", "text": "In Autunno ogni giocatore lancia un dado colorato in meno."},
	{"key": "buonumore", "name": "Il Re è di Buon Umore", "text": "Il premio della fase 3 è raddoppiato."},
	{"key": "miniera", "name": "Scoperta una Nuova Miniera", "text": "All'inizio di ogni stagione produttiva si tira un dado bianco: con 4 o più ogni giocatore riceve 1 Oro."},
	{"key": "cava", "name": "Scoperta una Nuova Cava", "text": "All'inizio di ogni stagione produttiva si tira un dado bianco: con 4 o più ogni giocatore riceve 1 Pietra."},
	{"key": "commercio", "name": "Commercio con i Regni Vicini", "text": "Alla fine di ogni stagione produttiva (dopo aver costruito) ogni giocatore può scambiare una sua merce con un'altra."},
	{"key": "stelle", "name": "Stelle in Ascesa", "text": "1 Oro su 1 e 10, 1 Legno su 4 e 15, 1 Pietra su 5 e 16, un gettone +2 su 6 e 13. Chi schiera i dadi su uno di questi Consiglieri prende subito ciò che c'è (non viene rimpiazzato). A fine anno si scarta ciò che resta."},
	{"key": "accordi", "name": "Accordi Segreti", "text": "Ogni giocatore (in ordine di gioco) mette un segnalino su un Consigliere a scelta. Ognuno può influenzare solo i Consiglieri senza segnalini e quello su cui c'è il proprio. A fine anno i segnalini si riprendono."},
	{"key": "malato", "name": "Il Re è Malato!", "text": "Nessuno può influenzare il Re (18). Se il Re si era già ammalato, alla fine di quest'anno il Re muore e la partita termina."},
	{"key": "cattivoumore", "name": "Il Re è di Cattivo Umore", "text": "Il premio della fase 3 è annullato."},
]

## Capricci a Corte (modulo 6): tessere che sostituiscono la ricompensa del Consigliere con lo stesso numero.
const CAPRICCI := {
	1: "Ottieni la ricompensa del Consigliere con il numero più basso non influenzato in questa stagione.",
	2: "Ottieni 2 gettoni +2, oppure paga un gettone +2 per 1 Oro e 1 soldato.",
	3: "Il giocatore alla tua sinistra nomina una merce: la prendi dalla riserva.",
	4: "Prendi una merce dalla tessera (che contiene 1 Oro, 1 Legno e 1 Pietra e si riempie quando resta vuota).",
	5: "Prendi la merce presente sulla tessera (estratta a caso; dopo se ne estrae un'altra).",
	6: "Puoi pagare 1 merce per 1 soldato e 1 PV, oppure 1 PV per 1 soldato e 1 merce, oppure 1 soldato per 1 PV e 1 merce.",
	7: "Scegli un altro giocatore: ottiene una merce a sua scelta e tu ricevi due unità di quella stessa merce.",
	8: "Il giocatore alla tua sinistra sceglie una merce per te, poi quello alla tua destra un'altra (in 2 giocatori l'avversario sceglie due volte).",
	9: "Scegli due cose diverse fra 1 Oro, 1 Legno, 1 Pietra, 1 soldato e 1 gettone +2.",
	10: "Ottieni 2 Oro oppure 2 Legni oppure 2 Pietre.",
	11: "1 Pietra, 1 soldato e 1 PV. Chi ha meno merci, soldati o PV può fare una conversione (vedi regole).",
	12: "Ottieni 3 Oro e ogni altro giocatore 1 PV, oppure 3 PV e ogni altro giocatore 1 Oro.",
	13: "Ottieni 1 merce a scelta, 1 gettone +2, 1 PV, 1 soldato e guardi la carta Invasori.",
	14: "Scegli un altro giocatore: prende per sé una cosa fra Oro, Legno, Pietra, gettone +2 e soldato; tu ottieni le altre quattro.",
	15: "Ottieni 2 Oro, 2 Legni e 2 Pietre: ne tieni 4 a scelta e dai le altre 2 agli altri giocatori.",
	16: "Ottieni 5 PV.",
}

## Valori dei gettoni Richiesta di Truppe (modulo 5).
const TROOP_TOKENS := [0, 1, 1, 2, 3, 4]

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
