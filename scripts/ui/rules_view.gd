extends Control
## Regole in breve, Consiglieri ed edifici. Si apre dal menu o durante la partita.

const D = preload("res://scripts/data/kb_data.gd")

var main
var embedded := false
var on_close: Callable


func _ready() -> void:
	size = Vector2(1920, 1080)
	if not embedded:
		var bg := TextureRect.new()
		bg.texture = UI.tex("res://assets/menu_bg.jpg")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.modulate = Color(0.25, 0.25, 0.3)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#14110cf6"), UI.GOLD, 2, 10))
	box.position = Vector2(120, 40)
	box.custom_minimum_size = Vector2(1680, 1000)
	box.size = Vector2(1680, 1000)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("REGOLE DI KINGSBURG", 38)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var close := UI.button("CHIUDI" if embedded else "INDIETRO", 180, 52, 24)
	close.pressed.connect(func():
		if embedded:
			on_close.call()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(820, 900)
	left.text = _rules_text()
	cols.add_child(left)
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.custom_minimum_size = Vector2(800, 900)
	right.text = _tables_text()
	cols.add_child(right)


func _rules_text() -> String:
	var g := "[color=#e8c25a]"
	var e := "[/color]"
	return """[font_size=24]%sScopo%s[/font_size]
Siete governatori di provincia di Re Tritus. In 5 anni costruite edifici, influenzate i Consiglieri del Re e respingete gli Invasori: vince chi ha più Punti Vittoria (a parità, più merci, poi più edifici).

[font_size=24]%sOgni anno: 8 fasi%s[/font_size]
[b]1. Aiuto del Re[/b] – chi ha meno edifici (a parità meno merci) tira un dado bianco in più in Primavera. Se più giocatori sono ultimi alla pari, ognuno riceve invece 1 merce a scelta.
[b]2. Primavera[/b], [b]4. Estate[/b], [b]6. Autunno[/b] – stagioni produttive:
  • Tutti tirano i 3 dadi (più eventuali bianchi). Chi ha la somma più bassa gioca per primo (a parità resta avanti chi lo era già).
  • A turno ognuno [b]influenza un Consigliere[/b] usando uno o più dadi la cui somma sia esattamente il suo numero, oppure passa. Ogni Consigliere si influenza una volta sola per stagione. Serve almeno un dado colorato: i bianchi si usano solo insieme ai colorati. Un gettone +2 aggiunge 2 a un gruppo di dadi.
  • In ordine di numero (1→18) i Consiglieri danno il loro aiuto.
  • A turno ognuno può [b]costruire un edificio[/b] pagandone il costo: in ogni riga serve aver costruito tutti quelli a sinistra. Si guadagnano subito i suoi PV.
[b]3. Premio del Re[/b] – chi ha più edifici guadagna 1 PV (tutti, in caso di parità).
[b]5. Agente del Re[/b] – chi ha meno edifici (a parità meno merci) riceve l'Agente del Re: in una delle prossime stagioni produttive potrà influenzare un Consigliere già occupato (che darà l'aiuto due volte) oppure costruire un secondo edificio. Va restituito alla fase 5 successiva.
[b]7. Mercenari[/b] – a turno si possono reclutare soldati: 2 merci a scelta ciascuno (1 con la Caserma).
[b]8. Inverno[/b] – si scopre la carta Invasori dell'anno. Il dado del Re aggiunge da 1 a 6 soldati a tutti. Forza = soldati + bonus degli edifici. Maggiore della forza degli Invasori: vittoria e ricompensa (chi ha la forza più alta fra i vincitori, +1 PV). Uguale: nulla. Minore: si subiscono le penalità (merci, un edificio della colonna più a destra – riga più in alto – e PV). Poi i soldati tornano a zero.

[font_size=24]%sCon 2 giocatori%s[/font_size]
A ogni stagione produttiva 3 dadi neutrali occupano il Consigliere pari alla loro somma, e 2 dadi neutrali quello pari alla loro (o, se coincide, i Consiglieri dei singoli valori).

[font_size=24]%sComandi%s[/font_size]
• Clic sui dadi per sceglierli, poi clic su un Consigliere evidenziato in verde. Senza dadi scelti, i riquadri gialli mostrano dove puoi arrivare: se c'è un solo modo, basta il clic sul Consigliere.
• Clic su un giocatore per vederne la provincia; passa il mouse su edifici e Consiglieri per i dettagli.
• Chi ha guardato la carta Invasori (Generale, Regina) può rivederla con un clic sul dorso accanto all'Inverno.
• F11: schermo intero.""" % [g, e, g, e, g, e, g, e]


func _tables_text() -> String:
	var g := "[color=#e8c25a]"
	var e := "[/color]"
	var s := "[font_size=24]%sI Consiglieri del Re%s[/font_size]\n" % [g, e]
	for a in range(1, 19):
		s += "[b]%d %s[/b] – %s\n" % [a, D.ADVISORS[a]["name"], D.ADVISORS[a]["text"]]
	s += "\n[font_size=24]%sGli edifici (riga per riga)%s[/font_size]\n" % [g, e]
	for b in range(20):
		var bd: Dictionary = D.BUILDINGS[b]
		s += "[b]%s[/b] (%s · %d PV): %s\n" % [bd["name"], D.cost_text(bd["cost"]), bd["vp"], bd["text"]]
		if b % 4 == 3:
			s += "\n"
	s += "[font_size=24]%sInvasori per anno%s[/font_size]\nI: 2-4 · II: 3-5 · III: 4-6 · IV: 5-7 · V: 7-9\n" % [g, e]
	return s
