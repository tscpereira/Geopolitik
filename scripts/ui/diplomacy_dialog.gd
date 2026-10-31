class_name DiplomacyDialog
extends Control

## Janela de Diplomacia (botão "Diplomacia" ao lado do Menu; desde 30/10/2026):
## no mármore das janelas, uma linha por império que o jogador humano já
## encontrou: o líder (na cor do jogador), o estado da relação (Paz, Guerra,
## Aliado), a confiança DELE em você (rosto e faixa) e a situação (trégua,
## tempo de guerra). Na sua vez, o botão da linha declara guerra (em paz) ou
## propõe a paz (em guerra); o Game confirma e resolve. As negociações
## (encontros, comércio, tratados) vêm nas próximas fases.

signal declare_war_requested(player: Player)
signal peace_requested(player: Player)

var _game: Game
var _rows: VBoxContainer
var _hint: Label


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	panel.theme = StoneStyle.theme()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 760
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Diplomacia"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Fechar [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	CityWindow.style_button(close)
	header.add_child(close)
	box.add_child(StoneStyle.separator())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	box.add_child(_rows)
	box.add_child(StoneStyle.separator())
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", StoneStyle.INK_MUTED)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 760
	_hint.text = "Paz: ninguém ataca o outro nem entra no território dele. Guerra: só declarando (ou atacando de surpresa, uma traição). A confiança é a que o outro imperador tem em você: Furioso, Indiferente, Amigável ou Irmandade."
	box.add_child(_hint)


func open(game: Game) -> void:
	_game = game
	_rebuild()
	show()


## Atualiza as linhas (o Game chama quando a diplomacia muda).
func refresh() -> void:
	if visible and _game:
		_rebuild()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		hide()


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var human := _game.viewer()
	if human == null:
		return
	var diplomacy := _game.diplomacy
	var known: Array = diplomacy.known_players(human, _game.players)
	if known.is_empty():
		var empty := Label.new()
		empty.text = "Você ainda não encontrou nenhum outro império. Explore o mapa: o primeiro encontro acontece quando uma unidade ou cidade de um vê a do outro."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 760
		_rows.add_child(empty)
		return
	var can_act := _game.can_act_in_diplomacy()
	for other: Player in known:
		_rows.add_child(_make_row(human, other, can_act))


func _make_row(human: Player, other: Player, can_act: bool) -> Control:
	var diplomacy := _game.diplomacy
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	# Cor e nome do líder
	var swatch := ColorRect.new()
	swatch.color = other.color
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var name_label := Label.new()
	name_label.text = Game.leader_name(other) + ("  (eliminado)" if other.eliminated else "")
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.custom_minimum_size.x = 250
	row.add_child(name_label)
	# Estado
	var state := diplomacy.state(human, other)
	var state_label := Label.new()
	state_label.text = Diplomacy.STATE_NAMES[state]
	state_label.add_theme_font_size_override("font_size", 18)
	state_label.add_theme_color_override("font_color", {Diplomacy.State.PEACE: StoneStyle.POSITIVE,
			Diplomacy.State.WAR: StoneStyle.NEGATIVE, Diplomacy.State.ALLIED: StoneStyle.SCIENCE}[state])
	state_label.custom_minimum_size.x = 80
	row.add_child(state_label)
	# Confiança dele em você
	var level := diplomacy.trust_level(other, human)
	var face := Control.new()
	face.custom_minimum_size = Vector2(22, 22)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mood: City.Mood = {Diplomacy.Trust.FURIOUS: City.Mood.UNHAPPY, Diplomacy.Trust.INDIFFERENT: City.Mood.CONTENT,
			Diplomacy.Trust.FRIENDLY: City.Mood.HAPPY, Diplomacy.Trust.BROTHERHOOD: City.Mood.HAPPY}[level]
	face.draw.connect(func() -> void: Icons.draw_face(face, Vector2(11, 11), 9.0, mood))
	row.add_child(face)
	var trust_label := Label.new()
	trust_label.text = "%s (%+d)" % [Diplomacy.TRUST_NAMES[level], diplomacy.trust(other, human)]
	trust_label.custom_minimum_size.x = 140
	trust_label.tooltip_text = "Confiança do %s em você, de -100 a +100." % Game.leader_name(other)
	trust_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(trust_label)
	# Situação
	var info := Label.new()
	info.add_theme_color_override("font_color", StoneStyle.INK_MUTED)
	info.add_theme_font_size_override("font_size", 14)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state == Diplomacy.State.WAR:
		info.text = "Em guerra há %d turnos" % diplomacy.turns_in_state(human, other)
	elif diplomacy.truce_turns_left(human, other) > 0:
		info.text = "Trégua: mais %d turnos" % diplomacy.truce_turns_left(human, other)
	else:
		info.text = "Em paz há %d turnos" % diplomacy.turns_in_state(human, other)
	row.add_child(info)
	# Ação
	if other.eliminated:
		return row
	var action := Button.new()
	action.focus_mode = Control.FOCUS_NONE
	CityWindow.style_button(action)
	if state == Diplomacy.State.WAR:
		action.text = "Propor paz"
		action.pressed.connect(func() -> void: peace_requested.emit(other))
		action.disabled = not can_act
	else:
		action.text = "Declarar guerra"
		action.pressed.connect(func() -> void: declare_war_requested.emit(other))
		action.disabled = not can_act or not diplomacy.can_declare_war(human, other)
		if diplomacy.truce_turns_left(human, other) > 0:
			action.tooltip_text = "Trégua: ninguém declara guerra por mais %d turnos." % diplomacy.truce_turns_left(human, other)
	if not can_act:
		action.tooltip_text = "Só na sua vez."
	row.add_child(action)
	return row
