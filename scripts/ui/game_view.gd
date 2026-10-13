extends Control
## Vista di gioco: tabellone principale a sinistra, giocatori, provincia e azioni a destra.

const D = preload("res://scripts/data/kb_data.gd")
const BOARD_POS := Vector2(16, 16)
const BOARD_SIZE := 1048.0
const RX := 1080.0             # inizio colonna destra
const RW := 824.0
const CARD := Vector2(178, 98)
const INV_POS := Vector2(1185.0 / 1400.0, 1222.0 / 1400.0)
const INV_SIZE := Vector2(64, 98)

var main
var config: Dictionary
var engine: KBEngine
var online = null
var humans: Array = []
var viewer := -1                # provincia mostrata
var pending: Dictionary = {}

# selezione per l'influenza
var sel_dice: Array = []
var use_p2 := false
var p2v := 2
var itin := false
var mk := 0

# nodi
var board: TextureRect
var board_layer: Control
var markers: Control
var adv_panels := {}
var header_lbl: Label
var sub_lbl: Label
var rows_box: VBoxContainer
var prov_title: Label
var prov_info: Label
var prov_grid: Control
var action_box: Control
var action_msg: Label
var action_row: HBoxContainer
var modal: Control
var toast: Control
var log_panel: PanelContainer
var log_text: RichTextLabel
var online_lbl: Label
var last_line := ""
var chron: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	online = config.get("online", null)
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/menu_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = Vector2(1920, 1080)
	bg.modulate = Color(0.16, 0.16, 0.2)
	add_child(bg)

	engine = KBEngine.new()
	add_child(engine)
	engine.setup(config)
	engine.ai_delay = config.get("ai_delay", 0.5)
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for p in engine.players:
			if not p["ai"]:
				humans.append(p["seat"])
	viewer = humans[0] if humans.size() > 0 else 0
	engine.pause_enabled = humans.size() > 0

	_build_board()
	_build_side()
	_build_log()
	modal = Control.new()
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	toast = Control.new()
	toast.size = Vector2(1920, 1080)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	_build_online_label()

	engine.changed.connect(refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.pause_requested.connect(_on_pause)
	engine.phase_changed.connect(func(_y, _p): refresh())
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


# =================================================================== costruzione

func _build_board() -> void:
	var frame := Panel.new()
	frame.position = BOARD_POS - Vector2(6, 6)
	frame.size = Vector2(BOARD_SIZE + 12, BOARD_SIZE + 12)
	frame.add_theme_stylebox_override("panel", UI.panel_style(Color("#000000"), Color("#5a4a2a"), 2, 6))
	add_child(frame)
	board = TextureRect.new()
	board.texture = UI.tex("res://assets/board.jpg")
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.stretch_mode = TextureRect.STRETCH_SCALE
	board.position = BOARD_POS
	board.size = Vector2(BOARD_SIZE, BOARD_SIZE)
	add_child(board)
	board_layer = Control.new()
	board_layer.position = BOARD_POS
	board_layer.size = board.size
	board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_layer)
	for a in range(1, 19):
		var r := D.adv_rect(a)
		var p := Panel.new()
		p.position = r.position * BOARD_SIZE
		p.size = r.size * BOARD_SIZE
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.tooltip_text = "%d · %s\n%s" % [a, D.ADVISORS[a]["name"], D.ADVISORS[a]["text"]]
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		p.gui_input.connect(_on_adv_input.bind(a))
		p.mouse_entered.connect(func(): _hover_adv(a, true))
		p.mouse_exited.connect(func(): _hover_adv(a, false))
		board_layer.add_child(p)
		adv_panels[a] = p
	var cr := PanelContainer.new()
	cr.position = Vector2(662, 146)
	cr.size = Vector2(312, 196) if not engine.mods.get("fate", false) else Vector2(312, 118)
	cr.custom_minimum_size = cr.size
	var crs := UI.panel_style(Color("#0e0b07d0"), Color("#6a5a3a"), 1, 8)
	crs.set_content_margin_all(6)
	cr.add_theme_stylebox_override("panel", crs)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_layer.add_child(cr)
	chron = RichTextLabel.new()
	chron.bbcode_enabled = true
	chron.scroll_following = true
	chron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chron.add_theme_font_size_override("normal_font_size", 15)
	chron.add_theme_font_size_override("bold_font_size", 16)
	chron.add_theme_constant_override("line_separation", -2)
	cr.add_child(chron)
	markers = Control.new()
	markers.size = board.size
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_layer.add_child(markers)


func _build_side() -> void:
	var head := PanelContainer.new()
	head.position = Vector2(RX, 10)
	head.custom_minimum_size = Vector2(RW, 66)
	head.size = Vector2(RW, 66)
	head.add_theme_stylebox_override("panel", UI.panel_style(Color("#120f0bee"), Color("#5a4a2a"), 1, 6))
	add_child(head)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	head.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	header_lbl = UI.title("", 26)
	vb.add_child(header_lbl)
	sub_lbl = UI.label("", 19, Color("#cfc5b0"))
	vb.add_child(sub_lbl)
	for t in [["DIARIO", _toggle_log], ["REGOLE", _show_rules_popup], ["MENU", _ask_quit]]:
		var b := UI.button(t[0], 104, 44, 19)
		b.pressed.connect(t[1])
		hb.add_child(b)

	rows_box = VBoxContainer.new()
	rows_box.position = Vector2(RX, 84)
	rows_box.size = Vector2(RW, 290)
	rows_box.add_theme_constant_override("separation", 4)
	add_child(rows_box)

	prov_title = UI.title("", 22)
	prov_title.position = Vector2(RX + 4, 372)
	add_child(prov_title)
	prov_info = UI.label("", 19, Color("#cfc5b0"))
	prov_info.position = Vector2(RX + 420, 378)
	prov_info.size = Vector2(400, 26)
	prov_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(prov_info)
	var pf := Panel.new()
	pf.position = Vector2(RX, 406)
	pf.size = Vector2(RW, 5 * (CARD.y + 4) + 12)
	pf.add_theme_stylebox_override("panel", UI.panel_style(Color("#16243dee"), Color("#2c3c5c"), 1, 6))
	add_child(pf)
	prov_grid = Control.new()
	prov_grid.position = Vector2(RX + (RW - 4 * (CARD.x + 6)) / 2.0 + 3, 412)
	add_child(prov_grid)

	action_box = PanelContainer.new()
	action_box.position = Vector2(RX, 930)
	action_box.custom_minimum_size = Vector2(RW, 140)
	action_box.size = Vector2(RW, 140)
	action_box.add_theme_stylebox_override("panel", UI.panel_style(Color("#120f0bf2"), UI.GOLD, 2, 6))
	add_child(action_box)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	action_box.add_child(av)
	action_msg = UI.label("", 22, Color.WHITE, UI.font_bold)
	action_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_msg.custom_minimum_size = Vector2(RW - 24, 0)
	av.add_child(action_msg)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	av.add_child(action_row)


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.position = Vector2(60, 300)
	log_panel.size = Vector2(960, 700)
	log_panel.custom_minimum_size = Vector2(960, 700)
	log_panel.add_theme_stylebox_override("panel", UI.panel_style(Color("#0d0b08f4"), UI.GOLD, 2, 8))
	log_panel.visible = false
	add_child(log_panel)
	var vb := VBoxContainer.new()
	log_panel.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("DIARIO DELLA PARTITA", 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var c := UI.button("CHIUDI", 120, 44, 19)
	c.pressed.connect(_toggle_log)
	hb.add_child(c)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.custom_minimum_size = Vector2(930, 620)
	vb.add_child(log_text)


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible
	if log_panel.visible:
		log_panel.move_to_front()


func _on_log(t: String) -> void:
	log_text.append_text(t + "\n")
	if t.begins_with("[b]"):
		chron.append_text("[color=#e8c25a]" + t + "[/color]\n")
	else:
		chron.append_text(t + "\n")
	if chron.get_paragraph_count() > 60:
		chron.remove_paragraph(0)
	if not t.begins_with("[b]"):
		last_line = t
	if pending.is_empty():
		_idle_message()


# =================================================================== aggiornamento

func refresh() -> void:
	if engine == null or engine.players.is_empty():
		return
	_refresh_header()
	_refresh_markers()
	_refresh_rows()
	_refresh_province()
	_refresh_adv_highlight()
	if pending.is_empty():
		_idle_message()


func _refresh_header() -> void:
	var ph := engine.phase
	if ph == 9 or engine.game_over:
		header_lbl.text = "Fine della partita"
		sub_lbl.text = ""
		return
	if ph == 0:
		header_lbl.text = "Kingsburg"
		sub_lbl.text = ""
		return
	header_lbl.text = "Anno %s · %s" % [D.ROMAN[engine.year], D.PHASE_NAMES[ph]]
	var st := ""
	match engine.step:
		"roll": st = "Lancio dei dadi"
		"influence": st = "Influenzare i Consiglieri"
		"rewards": st = "Aiuto dei Consiglieri"
		"build": st = "Costruire edifici"
		"end": st = "Fine della stagione"
	var inv := "Invasori dell'anno: forza %s" % D.YEAR_RANGE[engine.year]
	sub_lbl.text = (st + " · " if st != "" else "") + inv


func _bp(frac: Vector2) -> Vector2:
	return frac * BOARD_SIZE


func _coat_marker(color_id: int, center: Vector2, sz: float) -> TextureRect:
	var t := UI.icon_rect(UI.coat(color_id), Vector2(sz, sz))
	t.position = center - Vector2(sz, sz) / 2.0
	markers.add_child(t)
	return t


func _disc(center: Vector2, sz: float, col: Color, txt := "") -> Panel:
	var p := Panel.new()
	p.size = Vector2(sz, sz)
	p.position = center - p.size / 2.0
	var sb := UI.panel_style(col, Color("#1a0f2a"), 2, int(sz / 2))
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if txt != "":
		var l := UI.label(txt, int(sz * 0.42), Color.WHITE, UI.font_bold)
		l.size = p.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	markers.add_child(p)
	return p


func _refresh_markers() -> void:
	for c in markers.get_children():
		c.queue_free()
	var purple := Color("#6b3fa0")
	# anno e stagione
	_disc(_bp(D.year_pos(engine.year)), 40, purple)
	if engine.phase >= 1 and engine.phase <= 8:
		_disc(_bp(D.season_pos(engine.phase)), 44, purple)
	# Agente del Re sul calendario (se nessuno lo ha)
	if engine.envoy < 0:
		var ep := _bp(D.season_pos(5)) + Vector2(30, -34)
		_disc(ep, 34, Color("#8a4fd0"), "A").tooltip_text = "Agente del Re"
	# carta Invasori (dorso dell'anno) accanto all'inverno
	if engine.year >= 1 and engine.year <= 5 and engine.phase < 9:
		var back := UI.icon_rect(UI.tex("res://assets/invaders/back%d.jpg" % engine.year), INV_SIZE)
		back.position = _bp(INV_POS) - INV_SIZE / 2.0
		back.mouse_filter = Control.MOUSE_FILTER_STOP
		back.tooltip_text = "Invasori dell'anno %s: forza %s" % [D.ROMAN[engine.year], D.YEAR_RANGE[engine.year]]
		markers.add_child(back)
	# ordine di gioco
	for i in range(engine.order.size()):
		var s: int = engine.order[i]
		_coat_marker(engine.players[s]["color"], _bp(D.order_pos(i)) + Vector2(70, 0), 44)
	# segnapunti e soldati (pile sulla stessa casella)
	var by_vp := {}
	var by_sol := {}
	for p in engine.players:
		var v := posmod(int(p["vp"]), 60)
		by_vp[v] = by_vp.get(v, []) + [p]
		var sv: int = clampi(p["sol"], 0, 20)
		by_sol[sv] = by_sol.get(sv, []) + [p]
	for v in by_vp:
		var lst: Array = by_vp[v]
		for k in range(lst.size()):
			var off := Vector2((k - (lst.size() - 1) / 2.0) * 9, (k - (lst.size() - 1) / 2.0) * -9)
			var m := _coat_marker(lst[k]["color"], _bp(D.vp_pos(v)) + off, 34)
			m.tooltip_text = "%s: %d PV" % [lst[k]["name"], lst[k]["vp"]]
			m.mouse_filter = Control.MOUSE_FILTER_PASS
	for v in by_sol:
		var lst2: Array = by_sol[v]
		for k in range(lst2.size()):
			var off2 := Vector2(0, -k * 7)
			_coat_marker(lst2[k]["color"], _bp(D.sol_pos(v)) + off2, 32)
	# Capricci a Corte: le tessere coprono la ricompensa del Consigliere
	for k in engine.cap_tiles:
		var r := D.adv_rect(k)
		var tw := r.size.x * BOARD_SIZE * 1.02
		var cap := UI.icon_rect(UI.cap_tex(k), Vector2(tw, tw * 215.0 / 440.0))
		cap.position = Vector2(r.position.x * BOARD_SIZE - tw * 0.01, (r.position.y + r.size.y) * BOARD_SIZE - tw * 215.0 / 440.0 + 2)
		cap.mouse_filter = Control.MOUSE_FILTER_PASS
		cap.tooltip_text = "Capriccio %d: %s" % [k, D.CAPRICCI[k]]
		markers.add_child(cap)
		if k == 4 or k == 5:
			var hb := HBoxContainer.new()
			hb.position = cap.position + Vector2(tw * 0.55, -22)
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var goods := []
			if k == 4:
				for t in D.GOODS:
					for j in range(engine.cap4[t]):
						goods.append(t)
			elif engine.cap5 != "":
				goods.append(engine.cap5)
			for t in goods:
				hb.add_child(UI.icon_rect(UI.good_icon(t), Vector2(24, 24)))
			markers.add_child(hb)
	# Accordi Segreti e Stelle in Ascesa
	for a in engine.marks:
		var lst3: Array = engine.marks[a]
		for j in range(lst3.size()):
			var mc := _coat_marker(engine.players[lst3[j]]["color"], _bp(D.adv_center(a)) + Vector2(-48 + j * 16, -62), 30)
			mc.tooltip_text = "Accordi Segreti: segnalino di %s" % engine.pname(lst3[j])
			mc.mouse_filter = Control.MOUSE_FILTER_PASS
	for a in engine.stars:
		var it: String = engine.stars[a]
		var st := UI.icon_rect(UI.tex("res://assets/tokens/plus2.png") if it == "p2" else UI.good_icon(it), Vector2(30, 30))
		st.position = _bp(D.adv_center(a)) + Vector2(32, -76)
		markers.add_child(st)
	# carta Fato dell'anno (e la sostitutiva di Situazione Perdurante)
	if engine.fate_card >= 0 and engine.phase >= 1 and engine.phase <= 8:
		var cards := [engine.fate_card]
		if engine.fate_extra >= 0:
			cards.append(engine.fate_extra)
		for j2 in range(cards.size()):
			var fc := UI.icon_rect(UI.fate_tex(cards[j2]), Vector2(250, 164))
			fc.position = Vector2(700 + j2 * 20, 272 + j2 * 18)
			fc.mouse_filter = Control.MOUSE_FILTER_STOP
			fc.tooltip_text = "%s\n%s" % [D.FATE[cards[j2]]["name"], D.FATE[cards[j2]]["text"]]
			var fci: int = cards[j2]
			fc.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_card_popup(UI.fate_tex(fci), Vector2(600, 394)))
			markers.add_child(fc)
	if engine.year >= 1 and engine.year <= 5 and engine.deck2[engine.year - 1] >= 0 and engine.phase < 9:
		var back2 := UI.icon_rect(UI.tex("res://assets/invaders/back%d.jpg" % engine.year), INV_SIZE * 0.8)
		back2.position = _bp(INV_POS) - INV_SIZE / 2.0 + Vector2(-INV_SIZE.x * 0.6, 14)
		back2.tooltip_text = "Manovra a Tenaglia: una seconda carta Invasori"
		back2.mouse_filter = Control.MOUSE_FILTER_PASS
		markers.add_child(back2)
	# dadi sui Consiglieri
	for a in engine.adv:
		if a > 18:
			continue
		var e: Dictionary = engine.adv[a]
		var key: String = D.COLORS[engine.players[e["seat"]]["color"]]["key"]
		_place_dice(a, e["dice"], e["white"], key, e.get("p2", 0), e.get("mk", 0))
	for a in engine.blocked:
		var bl: Dictionary = engine.blocked[a]
		_place_dice(a, bl["dice"], [], bl["color"], 0, 0, true)
	for a in engine.adv_extra:
		var c := _bp(D.adv_center(a)) + Vector2(52, -70)
		var dd := _disc(c, 40, Color("#8a4fd0"), "A")
		dd.add_theme_stylebox_override("panel", UI.panel_style(Color("#8a4fd0"), D.COLORS[engine.players[engine.adv_extra[a]]["color"]]["light"], 3, 20))


func _place_dice(a: int, vals: Array, whites: Array, key: String, p2: int, mkv: int, neutral := false) -> void:
	var c := _bp(D.adv_center(a))
	var sz := 40.0 if vals.size() <= 3 else 32.0
	var w := vals.size() * (sz + 2) + (sz * 0.9 if p2 > 0 else 0.0)
	var x := c.x - w / 2.0
	var y := c.y - sz / 2.0 - 6
	for i in range(vals.size()):
		var k := "white" if (i < whites.size() and whites[i]) else key
		var t := UI.icon_rect(UI.die_tex(k, vals[i]), Vector2(sz, sz))
		t.position = Vector2(x, y)
		if neutral:
			t.modulate = Color(1, 1, 1, 0.85)
		markers.add_child(t)
		x += sz + 2
	if p2 > 0:
		var t2 := UI.icon_rect(UI.tex("res://assets/tokens/plus2.png"), Vector2(sz * 0.85, sz * 0.85))
		t2.position = Vector2(x, y + sz * 0.08)
		markers.add_child(t2)
	if mkv != 0:
		var l := UI.label("%+d" % mkv, 20, Color.WHITE, UI.font_bold)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.position = Vector2(c.x + w / 2.0 + 2, y + 4)
		markers.add_child(l)


func _refresh_rows() -> void:
	for c in rows_box.get_children():
		c.queue_free()
	for s in range(engine.n):
		rows_box.add_child(_player_row(s))


func _player_row(s: int) -> Control:
	var p: Dictionary = engine.players[s]
	var col: Dictionary = D.COLORS[p["color"]]
	var acting: bool = engine.current == s and not engine.game_over and (engine.step in ["influence", "build"] or engine.phase in [1, 7] or not pending.is_empty())
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(RW, 54)
	var bgc := Color("#1a1610ee")
	if s == viewer:
		bgc = Color("#2a2418ee")
	pc.add_theme_stylebox_override("panel", UI.panel_style(bgc, col["light"] if acting else Color("#3a3226"), 3 if acting else 1, 6))
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			viewer = s
			refresh())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	pc.add_child(hb)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ordn := engine.order.find(s) + 1
	var ol := UI.label("%d°" % ordn, 20, Color("#bdb39a"), UI.font_bold)
	ol.custom_minimum_size = Vector2(28, 0)
	hb.add_child(ol)
	hb.add_child(UI.icon_rect(UI.coat(p["color"]), Vector2(38, 38)))
	var nm := UI.label(p["name"] + (" (IA)" if p["ai"] else ""), 21, col["light"], UI.font_bold)
	nm.custom_minimum_size = Vector2(112 if engine.mods.get("gov", false) or engine.mods.get("troops", false) else 132, 0)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(nm)
	# dadi liberi
	var dbox := HBoxContainer.new()
	dbox.custom_minimum_size = Vector2(128, 0)
	dbox.add_theme_constant_override("separation", 2)
	for d in p["dice"]:
		if d["used"]:
			continue
		var t := UI.icon_rect(UI.die_tex("white" if d["white"] else col["key"], d["v"]), Vector2(24, 24))
		dbox.add_child(t)
	if p["passed"] and engine.step == "influence":
		dbox.add_child(UI.label("passa", 18, Color("#9a9080")))
	hb.add_child(dbox)
	_stat(hb, UI.icon("vp"), str(p["vp"]), "Punti Vittoria")
	_stat(hb, UI.icon("soldier"), str(p["sol"]), "Soldati")
	_stat(hb, UI.icon("gold"), str(p["goods"]["g"]), "Oro")
	_stat(hb, UI.icon("wood"), str(p["goods"]["w"]), "Legno")
	_stat(hb, UI.icon("stone"), str(p["goods"]["s"]), "Pietra")
	_stat(hb, UI.tex("res://assets/tokens/plus2.png"), str(p["p2"]), "Gettoni +2")
	_stat(hb, UI.icon("build"), str(engine.n_bld(s)), "Edifici")
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 2)
	if engine.envoy == s:
		var e := Panel.new()
		e.custom_minimum_size = Vector2(26, 26)
		e.add_theme_stylebox_override("panel", UI.panel_style(Color("#8a4fd0"), Color.WHITE, 1, 13))
		e.tooltip_text = "Ha l'Agente del Re"
		var el := UI.label("A", 16, Color.WHITE, UI.font_bold)
		el.size = Vector2(26, 26)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.add_child(el)
		extra.add_child(e)
	if p["aid_white"] and engine.phase <= 2:
		var w := UI.icon_rect(UI.die_tex("white", 6), Vector2(22, 22))
		w.tooltip_text = "Aiuto del Re: un dado bianco in più in Primavera"
		w.mouse_filter = Control.MOUSE_FILTER_PASS
		extra.add_child(w)
	if p["gov"] >= 0:
		var gt := TextureRect.new()
		gt.texture = UI.gov_tex(p["gov"])
		gt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		gt.custom_minimum_size = Vector2(30, 38)
		gt.tooltip_text = "%s\n%s%s" % [D.GOVERNORS[p["gov"]]["name"], D.GOVERNORS[p["gov"]]["text"], "\n(Paladino ancora in mano)" if p["paladin"] else ""]
		var gi: int = p["gov"]
		gt.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_card_popup(UI.gov_tex(gi), Vector2(760, 496)))
		extra.add_child(gt)
	if engine.mods.get("troops", false):
		var tl := UI.label(" ".join(p["troops"].map(func(x): return str(x))), 16, Color("#cfe0a0"))
		tl.tooltip_text = "Gettoni Richiesta di Truppe ancora disponibili"
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		extra.add_child(tl)
	if not p["known"].get(engine.year, []).is_empty() and _can_see(s):
		var k := UI.icon_rect(UI.icon("peek"), Vector2(26, 26))
		k.tooltip_text = "Conosce la carta Invasori di quest'anno: clic sulla carta nel tabellone per rivederla"
		k.mouse_filter = Control.MOUSE_FILTER_PASS
		extra.add_child(k)
	hb.add_child(extra)
	return pc


func _stat(hb: HBoxContainer, t: Texture2D, v: String, tip: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.custom_minimum_size = Vector2(47, 0)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := UI.icon_rect(t, Vector2(26, 26))
	box.add_child(ic)
	box.add_child(UI.label(v, 21, Color.WHITE, UI.font_bold))
	hb.add_child(box)


## Il giocatore davanti allo schermo può vedere le informazioni private di s?
func _can_see(s: int) -> bool:
	if online != null:
		return s == online.seat
	return s in humans or humans.is_empty()


func _refresh_province() -> void:
	for c in prov_grid.get_children():
		c.queue_free()
	var s := viewer
	var p: Dictionary = engine.players[s]
	var col: Dictionary = D.COLORS[p["color"]]
	prov_title.text = "Provincia · %s" % p["name"]
	prov_title.add_theme_color_override("font_color", col["light"])
	var bonus := engine.battle_bonus(s, "")
	prov_info.text = "%d edifici · difesa edifici %+d · reclutare: %d merc%s/soldato" % [engine.n_bld(s), bonus, engine.recruit_cost(s), "e" if engine.recruit_cost(s) == 1 else "i"]
	var opts: Array = []
	if pending.get("type", "") == "build" and int(pending.get("seat", -1)) == s:
		opts = pending["options"]
	var lines: Array = p["lines"]
	var rows := lines.size()
	var ch := minf(CARD.y, floorf(507.0 / rows) - 4.0)
	var card := Vector2(roundf(ch * CARD.x / CARD.y), ch)
	prov_grid.position = Vector2(RX + (RW - 4 * (card.x + 6)) / 2.0 + 3, 412)
	for r in range(rows):
		for c in range(4):
			var b: int = lines[r][c]
			var root := Control.new()
			root.position = Vector2(c * (card.x + 6), r * (card.y + 4))
			root.size = card
			prov_grid.add_child(root)
			var t := TextureRect.new()
			t.texture = UI.building_tex(b)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_SCALE
			t.size = card
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(t)
			var built: bool = p["bld"][b]
			var can: bool = b in opts
			if not built and not can:
				t.modulate = Color(0.45, 0.45, 0.5)
			if built:
				var ts := card.y * 0.35
				var tok := UI.icon_rect(UI.coat(p["color"]), Vector2(ts, ts))
				tok.position = Vector2(card.x * 0.503 - ts / 2.0, card.y * 0.152 - ts / 2.0)
				root.add_child(tok)
			if can:
				var hl := Panel.new()
				hl.size = card
				hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var sb := UI.panel_style(Color(0, 0, 0, 0), UI.GREEN, 3, 4)
				hl.add_theme_stylebox_override("panel", sb)
				root.add_child(hl)
			var cost := engine.building_cost(s, b)
			var tip := "%s · %d PV\nCosto per te: %s\n%s" % [D.BUILDINGS[b]["name"], D.BUILDINGS[b]["vp"], D.cost_text(cost), D.BUILDINGS[b]["text"]]
			if built:
				tip += "\n(costruito)"
			elif can:
				tip += "\nClic per costruire"
			root.tooltip_text = tip
			root.mouse_filter = Control.MOUSE_FILTER_STOP
			root.gui_input.connect(_on_building_input.bind(b))
			if card.y < CARD.y:
				root.mouse_entered.connect(func(): _building_preview(b, root))
				root.mouse_exited.connect(func(): _building_preview(-1, root))


## Anteprima grande dell'edificio sotto il mouse (quando le carte sono piccole).
var _preview: TextureRect

func _building_preview(b: int, root: Control) -> void:
	if _preview == null:
		_preview = TextureRect.new()
		_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_preview.stretch_mode = TextureRect.STRETCH_SCALE
		_preview.size = Vector2(480, 268)
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_preview)
	if b < 0:
		_preview.visible = false
		return
	_preview.texture = UI.building_tex(b)
	_preview.move_to_front()
	_preview.position = Vector2(RX - 490, clampf(root.global_position.y - 100, 10, 800))
	_preview.visible = true


## Carta ingrandita al centro (Governatori, Fato, Invasori). Clic per chiudere.
func _card_popup(tex: Texture2D, sz: Vector2) -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = layer.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	var t := UI.icon_rect(tex, sz)
	t.position = Vector2(960, 540) - sz / 2.0
	layer.add_child(t)
	layer.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			layer.queue_free())


# =================================================================== consiglieri

func _sel_sum() -> int:
	var p: Dictionary = engine.players[int(pending.get("seat", 0))]
	var t := 0
	for i in sel_dice:
		t += int(p["dice"][i]["v"])
	return t


## Mosse compatibili con la selezione attuale.
func _moves_for_selection() -> Array:
	if pending.get("type", "") != "influence":
		return []
	var out := []
	var sd: Array = sel_dice.duplicate()
	sd.sort()
	for mv in pending["moves"]:
		var md: Array = mv["dice"].duplicate()
		md.sort()
		if md == sd and int(mv["p2"]) == (1 if use_p2 else 0) and int(mv["mk"]) == mk and bool(mv["it"]) == itin \
				and (not use_p2 or int(mv["pv"]) == p2v):
			out.append(mv)
	return out


func _refresh_adv_highlight() -> void:
	var valid := {}
	if pending.get("type", "") == "mark":
		for a0 in pending["options"]:
			valid[int(a0)] = "yes"
	if pending.get("type", "") == "influence":
		if sel_dice.is_empty():
			for mv in pending["moves"]:
				if int(mv["p2"]) == 0 and int(mv["mk"]) == 0 and not mv["it"]:
					valid[int(mv["adv"])] = "maybe"
		else:
			for mv in _moves_for_selection():
				valid[int(mv["adv"])] = "yes"
	for a in adv_panels:
		var p: Panel = adv_panels[a]
		if valid.has(a):
			var col := UI.GREEN if valid[a] == "yes" else Color("#e8c25a88")
			var sb := UI.panel_style(Color(col.r, col.g, col.b, 0.12), col, 4 if valid[a] == "yes" else 2, 10)
			p.add_theme_stylebox_override("panel", sb)
		else:
			p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _hover_adv(a: int, on: bool) -> void:
	pass


func _on_adv_input(ev: InputEvent, a: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if pending.get("type", "") == "mark":
		if a in pending["options"]:
			_provide(a)
		return
	if pending.get("type", "") != "influence":
		return
	var cand := _moves_for_selection().filter(func(m): return int(m["adv"]) == a)
	if cand.is_empty() and sel_dice.is_empty():
		# nessun dado scelto: se c'è un solo modo (per valori dei dadi) di arrivarci, lo usa
		var by_vals := {}
		var p: Dictionary = engine.players[int(pending["seat"])]
		for mv in pending["moves"]:
			if int(mv["adv"]) != a or int(mv["p2"]) != 0 or int(mv["mk"]) != 0 or mv["it"]:
				continue
			var vals: Array = mv["dice"].map(func(i): return int(p["dice"][i]["v"]) * 10 + (1 if p["dice"][i]["white"] else 0))
			vals.sort()
			by_vals[str(vals)] = mv
		if by_vals.size() == 1:
			cand = [by_vals.values()[0]]
		elif by_vals.size() > 1:
			action_msg.text = "Ci sono più modi per arrivare a %s (%d): scegli prima i dadi." % [D.ADVISORS[a]["name"], a]
			return
	if cand.is_empty():
		return
	_provide(cand[0])


func _on_building_input(ev: InputEvent, b: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if pending.get("type", "") != "build" or int(pending["seat"]) != viewer:
		return
	if b in pending["options"]:
		_provide(b)


# =================================================================== decisioni

func _on_decision(req: Dictionary) -> void:
	# scelte segrete (Governatore, gettoni Truppe) con più persone allo stesso schermo: prima la tenda
	if req.get("secret", false) and humans.size() > 1 and online == null and not req.get("_shown", false):
		req["_shown"] = true
		_curtain(int(req["seat"]), func(): _on_decision(req))
		return
	pending = req
	var s: int = req["seat"]
	viewer = s
	sel_dice = []
	use_p2 = false
	p2v = 2
	itin = false
	mk = 0
	_clear_modal()
	refresh()
	var who := "%s, tocca a te" % engine.pname(s) if humans.size() > 1 else "Tocca a te"
	match str(req["type"]):
		"influence":
			_influence_ui()
		"build":
			_clear_actions()
			if req.get("second", false):
				action_msg.text = "%s: %s, puoi costruire un altro edificio (clic su una carta evidenziata)." % [who, req.get("why", "Agente del Re")]
			else:
				action_msg.text = "%s: costruisci un edificio (clic su una carta evidenziata) oppure nessuno." % who
			var b := UI.button("NON COSTRUIRE", 240, 52, 22)
			b.pressed.connect(func(): _provide(-1))
			action_row.add_child(b)
		"goods":
			_goods_modal(req, false)
		"lose":
			_goods_modal(req, true)
		"pick":
			_pick_modal(req)
		"reroll_statue":
			_statue_modal(req)
		"reroll_chapel":
			_yesno_modal(req["title"], func(v): _provide(v))
		"recruit":
			_recruit_modal(req)
		"gov":
			_gov_modal(req)
		"lines":
			_lines_modal(req)
		"draft_line":
			_draft_modal(req)
		"troops":
			_troops_modal(req)
		"mark":
			_clear_actions()
			action_msg.text = "%s: %s (clic su un Consigliere evidenziato)." % [who, req["title"]]
		_:
			_provide(null)


func _provide(r) -> void:
	pending = {}
	sel_dice = []
	use_p2 = false
	p2v = 2
	itin = false
	mk = 0
	_clear_modal()
	_clear_actions()
	refresh()
	engine.provide_decision(r)


func _clear_actions() -> void:
	for c in action_row.get_children():
		c.queue_free()


func _idle_message() -> void:
	if not pending.is_empty() or engine == null:
		return
	_clear_actions()
	if engine.game_over:
		action_msg.text = "Partita finita."
		return
	var s := engine.current
	var txt := last_line
	if s >= 0 and s < engine.n and engine.players[s]["ai"] and engine.step in ["influence", "build"]:
		txt = "%s sta pensando…\n%s" % [engine.pname(s), last_line]
	action_msg.text = txt


func _influence_ui() -> void:
	_clear_actions()
	var s: int = pending["seat"]
	var p: Dictionary = engine.players[s]
	var who := "%s: " % engine.pname(s) if humans.size() > 1 else ""
	action_msg.text = who + "scegli i dadi, poi clic su un Consigliere evidenziato (oppure PASSA)."
	var col_key: String = D.COLORS[p["color"]]["key"]
	var nfree := engine.free_dice(s).size()
	var dsz := 64.0 if nfree <= 4 else 50.0
	for i in range(p["dice"].size()):
		var d: Dictionary = p["dice"][i]
		if d["used"]:
			continue
		var b := TextureButton.new()
		b.texture_normal = UI.die_tex("white" if d["white"] else col_key, d["v"])
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(dsz, dsz)
		var on: bool = i in sel_dice
		if on:
			b.modulate = Color(1.15, 1.15, 0.8)
		else:
			b.modulate = Color(0.75, 0.75, 0.75) if not sel_dice.is_empty() else Color.WHITE
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", UI.panel_style(Color(0, 0, 0, 0), UI.GOLD if on else Color(0, 0, 0, 0), 3, 8))
		wrap.add_child(b)
		b.pressed.connect(func():
			if i in sel_dice:
				sel_dice.erase(i)
			else:
				sel_dice.append(i)
			_influence_ui()
			_refresh_adv_highlight())
		action_row.add_child(wrap)
	var sl := UI.label("", 26, UI.GOLD, UI.font_bold)
	sl.custom_minimum_size = Vector2(70, 0)
	var tot := _sel_sum() + (p2v if use_p2 else 0) + mk
	sl.text = "= %d" % tot if not sel_dice.is_empty() and not itin else ("1 dado" if itin else "")
	action_row.add_child(sl)
	var multi := engine.gov(s) == "damigella"
	if p["p2"] > 0 and (multi or not p["used"].get("p2", false)):
		var trick := engine.gov(s) == "truffatore"
		var b2 := UI.button("%+d (%d)" % [p2v, p["p2"]] if use_p2 else "+2 (%d)" % p["p2"], 96, 52, 22)
		if use_p2:
			UI.primary(b2)
		b2.tooltip_text = "Aggiungi un gettone +2 ai dadi scelti" + (" (Truffatore: clic di nuovo per usarlo come +3 o +1)" if trick else "")
		b2.pressed.connect(func():
			if not use_p2:
				use_p2 = true
				p2v = 2
			elif trick and p2v == 2:
				p2v = 3
			elif trick and p2v == 3:
				p2v = 1
			else:
				use_p2 = false
				p2v = 2
			_influence_ui()
			_refresh_adv_highlight())
		action_row.add_child(b2)
	if engine.has_b(s, D.B_MERCATO) and not p["used"].get("market", false):
		var bm := UI.button("Mercato %s" % ("±1" if mk == 0 else "%+d" % mk), 130, 52, 22)
		if mk != 0:
			UI.primary(bm)
		bm.tooltip_text = "Mercato: influenza un Consigliere di valore 1 più alto o più basso (clic per cambiare)"
		bm.pressed.connect(func():
			mk = {0: -1, -1: 1, 1: 0}[mk]
			_influence_ui()
			_refresh_adv_highlight())
		action_row.add_child(bm)
	if engine.has_b(s, D.B_MERC_ITIN) and not p["used"].get("itin", false):
		var bi := UI.button("Itinerante", 120, 52, 20)
		if itin:
			UI.primary(bi)
		bi.tooltip_text = "Mercato Itinerante: con un solo dado colorato influenzi un Consigliere da 1 a 6, qualunque sia il valore"
		bi.pressed.connect(func():
			itin = not itin
			_influence_ui()
			_refresh_adv_highlight())
		action_row.add_child(bi)
	# Politico: caselle 5 e 10 sulla carta
	for mv in _moves_for_selection():
		if int(mv["adv"]) > 18:
			var pb := UI.button("Politico %d" % (5 if int(mv["adv"]) == engine.POL5 else 10), 120, 52, 20)
			UI.primary(pb)
			pb.tooltip_text = "Schiera i dadi sulla carta del Politico"
			var mvc: Dictionary = mv
			pb.pressed.connect(func(): _provide(mvc))
			action_row.add_child(pb)
	if engine.envoy == s:
		var ei := UI.label("Agente: puoi usare\nun Consigliere occupato", 16, Color("#d0b0ff"))
		action_row.add_child(ei)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(sp)
	var bp := UI.button("PASSA", 110, 52, 24)
	bp.pressed.connect(func(): _provide({"pass": true}))
	action_row.add_child(bp)


# ------------------------------------------------------------------ finestre

func _clear_modal() -> void:
	for c in modal.get_children():
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Finestra centrata sul tabellone. Restituisce il contenitore verticale.
func _open_modal(title_text: String, w := 640.0, dim := true) -> VBoxContainer:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.position = BOARD_POS
		shade.size = Vector2(BOARD_SIZE, BOARD_SIZE)
		modal.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#16120cf6"), UI.GOLD, 2, 10))
	box.custom_minimum_size = Vector2(w, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var t := UI.title(title_text, 28)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 30, 0)
	vb.add_child(t)
	_center_box.call_deferred(box)
	return vb


func _center_box(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = BOARD_POS + Vector2(BOARD_SIZE, BOARD_SIZE) / 2.0 - box.size / 2.0


func _who_prefix(s: int) -> String:
	return "%s · " % engine.pname(s) if humans.size() > 1 else ""


func _goods_modal(req: Dictionary, losing: bool) -> void:
	var s: int = req["seat"]
	var nn: int = req["n"]
	var vb := _open_modal(_who_prefix(s) + str(req.get("title", "")), 620)
	if req.has("adv"):
		var hb0 := HBoxContainer.new()
		hb0.add_child(UI.icon_rect(UI.advisor_tex(int(req["adv"])), Vector2(110, 150)))
		var l0 := UI.label(D.ADVISORS[int(req["adv"])]["text"], 22, Color("#ddd"))
		l0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l0.custom_minimum_size = Vector2(440, 0)
		hb0.add_child(l0)
		vb.add_child(hb0)
	var have: Dictionary = req.get("have", engine.players[s]["goods"])
	var cnt := {"g": 0, "w": 0, "s": 0}
	var ok := UI.primary(UI.button("CONFERMA", 220, 56, 24))
	var lbls := {}
	var upd := func():
		var tot: int = cnt["g"] + cnt["w"] + cnt["s"]
		for t in D.GOODS:
			lbls[t].text = str(cnt[t])
		ok.disabled = tot != nn
		ok.text = "CONFERMA" if tot == nn else "ANCORA %d" % (nn - tot)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	for t in D.GOODS:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(UI.icon_rect(UI.good_icon(t), Vector2(72, 72)))
		var nml := UI.label("%s (hai %d)" % [D.GOOD_NAMES[t], have[t]], 19, Color("#cfc5b0"))
		nml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nml)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var minus := UI.button("−", 48, 48, 26)
		var l := UI.label("0", 30, Color.WHITE, UI.font_bold)
		l.custom_minimum_size = Vector2(40, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbls[t] = l
		var plus := UI.button("+", 48, 48, 26)
		minus.pressed.connect(func():
			if cnt[t] > 0:
				cnt[t] -= 1
				upd.call())
		plus.pressed.connect(func():
			var tot: int = cnt["g"] + cnt["w"] + cnt["s"]
			if tot < nn and (not losing or cnt[t] < have[t]):
				cnt[t] += 1
				upd.call())
		row.add_child(minus)
		row.add_child(l)
		row.add_child(plus)
		col.add_child(row)
		hb.add_child(col)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_child(ok)
	vb.add_child(br)
	ok.pressed.connect(func(): _provide(cnt.duplicate()))
	upd.call()


func _pick_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var vb := _open_modal(_who_prefix(s) + str(req.get("title", "")), 620)
	if req.has("adv"):
		var hb0 := HBoxContainer.new()
		hb0.add_theme_constant_override("separation", 12)
		hb0.add_child(UI.icon_rect(UI.advisor_tex(int(req["adv"])), Vector2(110, 150)))
		var l0 := UI.label(D.ADVISORS[int(req["adv"])]["text"], 22, Color("#ddd"))
		l0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l0.custom_minimum_size = Vector2(440, 0)
		hb0.add_child(l0)
		vb.add_child(hb0)
	if req.has("gov"):
		var gt := UI.icon_rect(UI.gov_tex(int(req["gov"])), Vector2(570, 372))
		vb.add_child(gt)
	var ctx: String = str(req.get("ctx", ""))
	if ctx.begins_with("cap") and ctx.substr(3).trim_suffix("o").is_valid_int():
		var k := int(ctx.substr(3).trim_suffix("o"))
		var ct := UI.icon_rect(UI.cap_tex(k), Vector2(330, 161))
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 12)
		crow.add_child(ct)
		var cl := UI.label(D.CAPRICCI[k], 20, Color("#ddd"))
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.custom_minimum_size = Vector2(240, 0)
		crow.add_child(cl)
		vb.add_child(crow)
	if req.get("dice", false):
		var dr := HBoxContainer.new()
		dr.alignment = BoxContainer.ALIGNMENT_CENTER
		var key: String = D.COLORS[engine.players[s]["color"]]["key"]
		for d in engine.players[s]["dice"]:
			dr.add_child(UI.icon_rect(UI.die_tex("white" if d["white"] else key, d["v"]), Vector2(60, 60)))
		vb.add_child(dr)
	var opts: Array = req["options"]
	var h := 56.0 if opts.size() <= 7 else 44.0
	for i in range(opts.size()):
		var b := UI.button(str(opts[i]["label"]), 560, h, 23 if h > 50 else 20)
		b.pressed.connect(func(): _provide(i))
		vb.add_child(b)


## Scelta del Governatore: le carte affiancate, clic per scegliere.
func _gov_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var opts: Array = req["options"]
	var w := 380.0 if opts.size() <= 3 else 300.0
	var vb := _open_modal(_who_prefix(s) + str(req.get("title", "")), minf(1800.0, opts.size() * (w + 12) + 30), true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	for g in opts:
		var b := TextureButton.new()
		b.texture_normal = UI.gov_tex(g)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
		b.custom_minimum_size = Vector2(w, w * 496.0 / 760.0)
		b.tooltip_text = "%s\n%s" % [D.GOVERNORS[g]["name"], D.GOVERNORS[g]["text"]]
		var gg: int = g
		b.pressed.connect(func(): _provide(gg))
		hb.add_child(b)
	var note := UI.label("Clic sulla carta che scegli (passa il mouse per leggere il testo).", 20, Color("#cfc5b0"))
	vb.add_child(note)
	_center_full.call_deferred(vb.get_parent())


## Linee di edifici alternative pescate: per ognuna si decide se sostituire quella del tabellone.
func _lines_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var opts: Array = req["options"]
	var vb := _open_modal(_who_prefix(s) + str(req["title"]), 1240, true)
	var use := {}
	var cw := 230.0
	for L in opts:
		var box := VBoxContainer.new()
		var lab := UI.label("Linea %s: in alto quella del tabellone, sotto l'alternativa" % L, 20, Color("#cfc5b0"))
		box.add_child(lab)
		for alt in [false, true]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var ids: Array = D.ALT_LINES[L] if alt else D.LINES[L]
			for b in ids:
				var t := UI.icon_rect(UI.building_tex(b), Vector2(cw, cw * 268.0 / 480.0))
				t.mouse_filter = Control.MOUSE_FILTER_PASS
				t.tooltip_text = "%s · %d PV · %s\n%s" % [D.BUILDINGS[b]["name"], D.BUILDINGS[b]["vp"], D.cost_text(D.BUILDINGS[b]["cost"]), D.BUILDINGS[b]["text"]]
				row.add_child(t)
			box.add_child(row)
		var tb := UI.button("Tengo la linea del tabellone", 360, 46, 20)
		var Lc: String = L
		var paint := func():
			tb.text = "Uso la linea alternativa %s" % Lc if use.get(Lc, false) else "Tengo la linea del tabellone"
			if use.get(Lc, false):
				UI.primary(tb)
			else:
				tb.remove_theme_stylebox_override("normal")
				tb.remove_theme_stylebox_override("hover")
				tb.remove_theme_color_override("font_color")
				tb.remove_theme_color_override("font_hover_color")
		tb.pressed.connect(func():
			use[Lc] = not use.get(Lc, false)
			paint.call())
		box.add_child(tb)
		vb.add_child(box)
	var ok := UI.primary(UI.button("CONFERMA", 240, 56, 24))
	ok.pressed.connect(func():
		var out := []
		for L2 in opts:
			if use.get(L2, false):
				out.append(L2)
		_provide(out))
	vb.add_child(ok)
	_center_full.call_deferred(vb.get_parent())


func _draft_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var opts: Array = req["options"]
	var vb := _open_modal(_who_prefix(s) + str(req["title"]), 1000, true)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(980, minf(760.0, opts.size() * 140.0))
	vb.add_child(sc)
	var inner := VBoxContainer.new()
	sc.add_child(inner)
	for L in opts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := UI.button("Linea %s" % L, 110, 100, 22)
		var Lc: String = L
		b.pressed.connect(func(): _provide(Lc))
		row.add_child(b)
		for bid in D.ALT_LINES[L]:
			var t := UI.icon_rect(UI.building_tex(bid), Vector2(210, 117))
			t.mouse_filter = Control.MOUSE_FILTER_PASS
			t.tooltip_text = "%s · %d PV · %s\n%s" % [D.BUILDINGS[bid]["name"], D.BUILDINGS[bid]["vp"], D.cost_text(D.BUILDINGS[bid]["cost"]), D.BUILDINGS[bid]["text"]]
			row.add_child(t)
		inner.add_child(row)
	_center_full.call_deferred(vb.get_parent())


func _troops_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var vb := _open_modal(_who_prefix(s) + str(req["title"]), 640)
	var info := UI.label("%s\nHai %d soldati; i tuoi edifici danno %+d. Il gettone scelto indica quanti rinforzi ti manda il Re; a fine partita il gettone che ti resta vale altrettanti PV." % [_invader_info(s), engine.players[s]["sol"], engine.battle_bonus(s, "")], 21, Color("#ddd"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 0)
	vb.add_child(info)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	for v in req["options"]:
		var b := UI.button(str(v), 80, 80, 40)
		b.add_theme_font_override("font", UI.font_title)
		var vv: int = v
		b.pressed.connect(func(): _provide(vv))
		hb.add_child(b)
	vb.add_child(hb)


## Tenda fra un giocatore e l'altro quando la scelta è segreta (hotseat).
func _curtain(s: int, then: Callable) -> void:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.97)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(660, 380)
	vb.add_theme_constant_override("separation", 20)
	modal.add_child(vb)
	vb.add_child(UI.icon_rect(UI.coat(engine.players[s]["color"]), Vector2(120, 120)))
	vb.add_child(UI.title("Tocca a %s" % engine.pname(s), 44))
	vb.add_child(UI.label("Scelta segreta: gli altri non guardino lo schermo.", 24))
	var b := UI.primary(UI.button("SONO PRONTO", 280, 60, 26))
	b.pressed.connect(func():
		_clear_modal()
		then.call())
	vb.add_child(b)


func _yesno_modal(text: String, cb: Callable) -> void:
	var vb := _open_modal(text, 560)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	var y := UI.primary(UI.button("SÌ", 180, 56, 24))
	y.pressed.connect(func(): cb.call(true))
	var no := UI.button("NO", 180, 56, 24)
	no.pressed.connect(func(): cb.call(false))
	hb.add_child(y)
	hb.add_child(no)
	vb.add_child(hb)


func _statue_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var p: Dictionary = engine.players[s]
	var vb := _open_modal(_who_prefix(s) + "Statua: tutti i dadi sono uguali. Clic sul dado da rilanciare.", 600)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	var key: String = D.COLORS[p["color"]]["key"]
	for i in range(p["dice"].size()):
		var d: Dictionary = p["dice"][i]
		var b := TextureButton.new()
		b.texture_normal = UI.die_tex("white" if d["white"] else key, d["v"])
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(80, 80)
		b.pressed.connect(func(): _provide(i))
		hb.add_child(b)
	vb.add_child(hb)
	var no := UI.button("NON RILANCIARE", 260, 54, 22)
	no.pressed.connect(func(): _provide(-1))
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_child(no)
	vb.add_child(br)


func _invader_info(s: int) -> String:
	var y := engine.year
	var known: Array = engine.players[s]["known"].get(y, [])
	var mod := ""
	if engine.fate("feroci"):
		mod = " (Nemici Feroci: +1 forza)"
	elif engine.fate("numerosi"):
		mod = " (Nemici Numerosi: Goblin e Orchi +1)"
	if engine.deck2[y - 1] >= 0:
		mod += " · Manovra a Tenaglia: conta la più forte di due carte"
	if not known.is_empty():
		var parts := []
		for ci in known:
			var c: Dictionary = D.INVADERS[ci]
			parts.append("%s, forza %d" % [D.RACE_NAMES[c["race"]], c["str"]])
		return "Sai già chi arriva: %s.%s" % ["; ".join(parts), mod]
	return "Invasori di quest'anno: forza %s.%s" % [D.YEAR_RANGE[y], mod]


func _recruit_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var p: Dictionary = engine.players[s]
	var cp: int = req["cost_per"]
	var vb := _open_modal(_who_prefix(s) + "Mercenari: quanti soldati recluti?", 700)
	var reinf := "In inverno il dado del Re aggiunge da 1 a 6 soldati a tutti."
	if engine.mods.get("troops", false):
		reinf = "In inverno sceglierai un gettone Richiesta di Truppe (ti restano: %s)." % ", ".join(p["troops"].map(func(x): return str(x)))
	if engine.fate("nevicata"):
		reinf = "Nevicata Intensa: il Re invia solo 2 soldati (con i gettoni, uno in meno)."
	var info := UI.label("%s\nHai %d soldati; i tuoi edifici danno %+d (contro alcune razze può cambiare). %s\nOgni soldato costa %d merc%s a scelta%s." % [_invader_info(s), p["sol"], engine.battle_bonus(s, ""), reinf, cp, "e" if cp == 1 else "i", " (anche gettoni +2)" if req.get("p2ok", false) else ""], 21, Color("#ddd"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(660, 0)
	vb.add_child(info)
	var have: Dictionary = p["goods"].duplicate()
	var keys := ["g", "w", "s"]
	if req.get("p2ok", false):
		have["p2"] = p["p2"]
		keys.append("p2")
	var pay := {}
	for t in keys:
		pay[t] = 0
	var k := [0]
	var total := 0
	for t in keys:
		total += have[t]
	var maxk: int = total / cp
	var kl := UI.label("0", 40, UI.GOLD, UI.font_bold)
	var lbls := {}
	var ok := UI.primary(UI.button("CONFERMA", 220, 56, 24))
	var paid := func() -> int:
		var t0 := 0
		for t in keys:
			t0 += pay[t]
		return t0
	var upd := func():
		kl.text = str(k[0])
		var tot: int = paid.call()
		for t in keys:
			lbls[t].text = str(pay[t])
		ok.disabled = tot != k[0] * cp
		ok.text = "NESSUNO" if k[0] == 0 else ("RECLUTA %d" % k[0] if tot == k[0] * cp else "PAGA ANCORA %d" % (k[0] * cp - tot))
	var auto_pay := func():
		for t in keys:
			pay[t] = 0
		var need: int = k[0] * cp
		while need > 0:
			var best := ""
			for t in (["p2"] if keys.has("p2") else []) + ["w", "s", "g"]:
				if have[t] - pay[t] > 0 and (best == "" or (t == "p2") or (best != "p2" and have[t] - pay[t] > have[best] - pay[best])):
					best = t
					if t == "p2":
						break
			if best == "":
				break
			pay[best] += 1
			need -= 1
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var minus := UI.button("−", 60, 60, 30)
	var plus := UI.button("+", 60, 60, 30)
	minus.pressed.connect(func():
		if k[0] > 0:
			k[0] -= 1
			auto_pay.call()
			upd.call())
	plus.pressed.connect(func():
		if k[0] < maxk:
			k[0] += 1
			auto_pay.call()
			upd.call())
	row.add_child(UI.icon_rect(UI.icon("soldier"), Vector2(56, 56)))
	row.add_child(minus)
	kl.custom_minimum_size = Vector2(60, 0)
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(kl)
	row.add_child(plus)
	vb.add_child(row)
	vb.add_child(UI.label("Pagamento:", 21, Color("#cfc5b0")))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	for t in keys:
		var r2 := HBoxContainer.new()
		r2.add_child(UI.icon_rect(UI.tex("res://assets/tokens/plus2.png") if t == "p2" else UI.good_icon(t), Vector2(40, 40)))
		var mi := UI.button("−", 38, 38, 22)
		var l := UI.label("0", 26, Color.WHITE, UI.font_bold)
		l.custom_minimum_size = Vector2(28, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbls[t] = l
		var pl := UI.button("+", 38, 38, 22)
		var tc: String = t
		mi.pressed.connect(func():
			if pay[tc] > 0:
				pay[tc] -= 1
				upd.call())
		pl.pressed.connect(func():
			if pay[tc] < have[tc] and paid.call() < k[0] * cp:
				pay[tc] += 1
				upd.call())
		r2.add_child(mi)
		r2.add_child(l)
		r2.add_child(pl)
		r2.add_child(UI.label("/%d" % have[t], 19, Color("#9a9080")))
		hb.add_child(r2)
	vb.add_child(hb)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_child(ok)
	vb.add_child(br)
	ok.pressed.connect(func(): _provide({"n": k[0], "pay": pay.duplicate()}))
	upd.call()


# ------------------------------------------------------------------ pause e animazioni

func _on_pause(req: Dictionary) -> void:
	if req.get("ctx", "") == "battle":
		_battle_modal(int(req["card"]))
	elif req.get("ctx", "") == "fate":
		_fate_modal(int(req["card"]))
	else:
		engine.provide_decision(true)


func _fate_modal(fi: int) -> void:
	var vb := _open_modal("Anno %s · Carta Fato: %s" % [D.ROMAN[engine.year], D.FATE[fi]["name"]], 660)
	var cards := [fi]
	if engine.fate_extra >= 0:
		cards.append(engine.fate_extra)
	for c in cards:
		vb.add_child(UI.icon_rect(UI.fate_tex(c), Vector2(600, 394)))
	if D.FATE[fi]["key"] == "perdurante" and engine.fate_extra < 0:
		vb.add_child(UI.label("Resta in vigore: %s" % engine._fate_name(engine.fate_key), 22, UI.GOLD, UI.font_bold))
	var ok := UI.primary(UI.button("CONTINUA", 240, 56, 24))
	ok.pressed.connect(func():
		_clear_modal()
		engine.provide_decision(true))
	vb.add_child(ok)


func _battle_modal(ci: int) -> void:
	var card: Dictionary = D.INVADERS[ci]
	var vb := _open_modal("Inverno · Anno %s: arrivano i %s (forza %d)" % [D.ROMAN[engine.year], D.RACE_NAMES[card["race"]], engine.battle_str], 980)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var cards_box := VBoxContainer.new()
	hb.add_child(cards_box)
	var other := engine.revealed2 if engine.revealed2 >= 0 and engine.revealed2 != ci else (engine.revealed if engine.revealed2 >= 0 and engine.revealed != ci else -1)
	var csz := Vector2(260, 400) if other < 0 else Vector2(180, 277)
	cards_box.add_child(UI.icon_rect(UI.invader_tex(ci), csz))
	if other >= 0:
		var o := UI.icon_rect(UI.invader_tex(other), csz * 0.8)
		o.modulate = Color(0.6, 0.6, 0.6)
		cards_box.add_child(o)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var dr := HBoxContainer.new()
	if engine.mods.get("troops", false):
		dr.add_child(UI.label("Rinforzi scelti con i gettoni Richiesta di Truppe." + ("  Nevicata: uno in meno." if engine.fate("nevicata") else ""), 22, Color.WHITE))
	elif engine.fate("nevicata"):
		dr.add_child(UI.label("Nevicata Intensa: il Re manda 2 soldati a ogni governatore.", 22, Color.WHITE))
	else:
		dr.add_child(UI.icon_rect(UI.die_tex("white", engine.king_die), Vector2(52, 52)))
		dr.add_child(UI.label("  Il dado del Re manda %d soldat%s a ogni governatore." % [engine.king_die, "o" if engine.king_die == 1 else "i"], 22, Color.WHITE))
	right.add_child(dr)
	if engine.battle_str != card["str"]:
		right.add_child(UI.label("Forza modificata dalla carta Fato: %d → %d" % [card["str"], engine.battle_str], 20, Color("#f0b080")))
	for e in engine.battle:
		var s: int = e["seat"]
		var p: Dictionary = engine.players[s]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.icon_rect(UI.coat(p["color"]), Vector2(40, 40)))
		var res_txt: String = {"win": "VITTORIA", "tie": "PAREGGIO", "lose": "SCONFITTA"}[e["res"]]
		var res_col: Color = {"win": UI.GREEN, "tie": Color("#e8d27a"), "lose": UI.RED}[e["res"]]
		var l := UI.label("%s: %d soldati (di cui %d rinforzi) %+d edifici = %d" % [p["name"], e["sol"], e.get("reinf", 0), e["bonus"], e["total"]], 21, Color.WHITE, UI.font_bold)
		l.custom_minimum_size = Vector2(470, 0)
		row.add_child(l)
		row.add_child(UI.label(res_txt, 21, res_col, UI.font_bold))
		right.add_child(row)
		var det := ""
		if e["res"] == "win":
			det = "Riceve: " + str(e.get("got", ""))
			if not e["notes"].is_empty():
				det += " (" + ", ".join(e["notes"]) + ")"
		elif e["res"] == "lose":
			det = "Perde: " + str(e.get("lost", ""))
		if det != "":
			var l2 := UI.label("      " + det, 19, Color("#cfc5b0"))
			l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l2.custom_minimum_size = Vector2(560, 0)
			right.add_child(l2)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	var ok := UI.primary(UI.button("CONTINUA", 240, 56, 24))
	ok.pressed.connect(func():
		_clear_modal()
		engine.provide_decision(true))
	br.add_child(ok)
	vb.add_child(br)


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"peek":
			var s: int = data["seat"]
			if _can_see(s) and not engine.players[s]["ai"]:
				_peek_toast(s, int(data["card"]))
		"build":
			if int(data["seat"]) == viewer or engine.players[int(data["seat"])]["ai"]:
				pass


func _peek_toast(s: int, ci: int) -> void:
	for c in toast.get_children():
		c.queue_free()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#16120cf6"), Color("#8ab4ff"), 2, 10))
	box.position = Vector2(BOARD_POS.x + BOARD_SIZE - 330, BOARD_POS.y + 250)
	toast.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	var t := UI.label("%s: solo per te,\nla carta Invasori di quest'anno" % engine.pname(s), 20, Color("#cfe0ff"), UI.font_bold)
	vb.add_child(t)
	vb.add_child(UI.icon_rect(UI.invader_tex(ci), Vector2(280, 430)))
	var ok := UI.button("CHIUDI", 160, 44, 20)
	ok.pressed.connect(func(): box.queue_free())
	vb.add_child(ok)


## Clic sulla carta dell'anno: chi la conosce la rivede.
func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if engine == null or engine.phase >= 9:
			return
		var c := _bp(INV_POS) - INV_SIZE / 2.0 + BOARD_POS
		if Rect2(c, INV_SIZE).has_point(ev.position):
			for s in range(engine.n):
				var kn: Array = engine.players[s]["known"].get(engine.year, [])
				if _can_see(s) and not kn.is_empty() and not engine.players[s]["ai"]:
					_peek_toast(s, kn[kn.size() - 1])
					return


# ------------------------------------------------------------------ fine partita e menu

func _on_game_end(results: Array) -> void:
	for c in toast.get_children():
		c.queue_free()
	if online != null:
		online.finish()
		online_status("")
	refresh()
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.9)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#16120cf8"), UI.GOLD, 2, 12))
	box.custom_minimum_size = Vector2(900, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var w: Dictionary = engine.players[results[0]["seat"]]
	vb.add_child(UI.title("Re Tritus premia %s!" % w["name"], 40))
	vb.add_child(UI.label("Dopo cinque anni, il governatore più abile siederà nel Consiglio Reale.", 22, Color("#cfc5b0")))
	for e in results:
		var p: Dictionary = engine.players[e["seat"]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(UI.title("%d°" % e["place"], 34, Color.WHITE))
		row.add_child(UI.icon_rect(UI.coat(p["color"]), Vector2(56, 56)))
		var nm := UI.label(p["name"] + (" (IA)" if p["ai"] else ""), 28, D.COLORS[p["color"]]["light"], UI.font_bold)
		nm.custom_minimum_size = Vector2(300, 0)
		row.add_child(nm)
		row.add_child(UI.label("%d PV" % e["vp"], 30, UI.GOLD, UI.font_bold))
		row.add_child(UI.label("   %d edifici · %d merci" % [e["bld"], e["goods"]], 22, Color("#cfc5b0")))
		vb.add_child(row)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 16)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	if online == null:
		var again := UI.primary(UI.button("RIGIOCA", 240, 60, 26))
		again.pressed.connect(func():
			var cfg := config.duplicate(true)
			cfg.erase("seed")
			main.start_game(cfg))
		br.add_child(again)
	var see := UI.button("GUARDA IL TABELLONE", 300, 60, 24)
	see.pressed.connect(func():
		_clear_modal()
		_clear_actions()
		var m := UI.button("RISULTATI", 180, 52, 22)
		m.pressed.connect(func(): _on_game_end(results))
		action_row.add_child(m)
		var mm := UI.button("MENU", 140, 52, 22)
		mm.pressed.connect(func(): main.show_menu())
		action_row.add_child(mm))
	br.add_child(see)
	var menu := UI.button("MENU", 200, 60, 26)
	menu.pressed.connect(func(): main.show_menu())
	br.add_child(menu)
	vb.add_child(br)
	_center_full.call_deferred(box)


func _center_full(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = Vector2(960, 540) - box.size / 2.0


func _ask_quit() -> void:
	var keep := pending
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#16120cf8"), UI.GOLD, 2, 10))
	box.position = Vector2(660, 400)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Tornare al menu?", 32))
	vb.add_child(UI.label("La partita in corso andrà persa." if online == null else "Potrai rientrare nella stanza con lo stesso codice.", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var y := UI.primary(UI.button("SÌ, AL MENU", 240, 56, 24))
	y.pressed.connect(func(): main.show_menu())
	var n := UI.button("CONTINUA A GIOCARE", 300, 56, 24)
	n.pressed.connect(func(): layer.queue_free())
	hb.add_child(y)
	hb.add_child(n)
	vb.add_child(hb)


func _show_rules_popup() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var rv := preload("res://scripts/ui/rules_view.gd").new()
	rv.embedded = true
	rv.on_close = func(): layer.queue_free()
	layer.add_child(rv)


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color("#000000cc"), UI.GOLD, 2, 8))
	p.position = Vector2(30, 1010)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_lbl = UI.label("", 22, Color.WHITE)
	p.add_child(online_lbl)
	add_child(p)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	(online_lbl.get_meta("box") as Control).visible = t != ""


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, engine.pname(seat)]
	if is_slow:
		t += " (sta pensando da più di un minuto)"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	refresh()


## L'IA ha già giocato al posto di questo giocatore: si chiude il dialogo aperto.
func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	_clear_actions()
	refresh()
	online_status(t)
