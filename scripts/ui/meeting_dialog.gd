class_name MeetingDialog
extends Control

## Tela do ENCONTRO com outro imperador (desde 30/10/2026; aberta pelo botão
## "Propor encontro" da janela de Diplomacia, quando ele aceita receber você).
## Um retângulo grande no meio da tela (ANCHORS: as proporções do print do
## usuário, ~65% da largura e ~58% da altura, um pouco acima do centro), no
## mármore, com foco total: o fundo escurece e nenhum clique fora dele funciona
## (o Game também trava a câmera). Duas partes, como no esboço do usuário:
##   EM CIMA (a maior): o palco com o LÍDER (Nation.portrait) sobre um fundo
##     escuro na cor da nação, com o nome dele embaixo; a expressão segue a
##     relação: brava em guerra ou Furioso, feliz com Amigável ou Irmandade,
##     neutra no resto. Sem o retrato do Gemini ainda, uma silhueta.
##   EMBAIXO: como ele te recebe, o estado e a confiança, a resposta à última
##     proposta e as opções, como falas (pedido do usuário): em paz, "Gostaríamos
##     de fazer uma proposta de troca" e "Declarar guerra"; em guerra, "Propor
##     paz"; e encerrar.
## TROCA (desde 30/10/2026): o painel de troca aparece ao lado do líder (o palco
## fica mais estreito, mas com a mesma altura): à esquerda o que você oferece,
## à direita o que você pede (ouro, madeira, ferro, armas do arsenal, o mapa e
## tecnologias: Trade). Embaixo, a disposição dele ao vivo
## (AIDiplomacy.trade_verdict) e "Propor troca" / "Voltar".

signal peace_proposed(player: Player)
signal war_declared(player: Player)
## A proposta de troca: [param offer] sai do humano, [param ask] sai do outro.
signal trade_proposed(player: Player, offer: Dictionary, ask: Dictionary)

## Retângulo do encontro, em frações da tela (esquerda, cima, direita, baixo).
const ANCHORS := Vector4(0.187, 0.139, 0.834, 0.717)

var _game: Game
var _other: Player
var _stage: Control
var _portrait_texture: Texture2D
## Expressão da última resposta do líder (show_reply), que vale até o fim do
## encontro; -1 = pela relação (mood_for).
var _mood_override := -1
var _greeting: RichTextLabel
var _status: RichTextLabel
var _reply: RichTextLabel
var _actions: HBoxContainer
var _trade: PanelContainer
var _trade_columns: HBoxContainer
var _trade_hint: RichTextLabel
var _trade_button: Button
var _trading := false
## A proposta em montagem (Trade.empty): o que você oferece e o que pede.
var _offer := {}
var _ask := {}


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # foco total: o clique fora não passa
	add_child(dim)
	var panel := PanelContainer.new()
	var style := StonePanelBox.new()
	style.bevel = 10.0
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.theme = StoneStyle.theme()
	panel.anchor_left = ANCHORS.x
	panel.anchor_top = ANCHORS.y
	panel.anchor_right = ANCHORS.z
	panel.anchor_bottom = ANCHORS.w
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	# Em cima: o palco com o líder (e, na troca, o painel ao lado)
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	# O retrato do líder é grande (até 1600 px): reduzido com suavidade
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stage.draw.connect(_draw_stage)
	top.add_child(_stage)
	_build_trade_panel(top)

	# Embaixo: a conversa e as opções
	var talk := VBoxContainer.new()
	talk.add_theme_constant_override("separation", 6)
	column.add_child(talk)
	_greeting = _make_text(18)
	talk.add_child(_greeting)
	_status = _make_text(15)
	talk.add_child(_status)
	_reply = _make_text(16)
	talk.add_child(_reply)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	talk.add_child(_actions)


func _make_text(size: int) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_font_size_override("normal_font_size", size)
	text.add_theme_font_size_override("bold_font_size", size)
	text.add_theme_font_size_override("italics_font_size", size)
	return text


func open(game: Game, other: Player) -> void:
	_game = game
	_other = other
	_reply.text = ""
	_reply.hide()
	_mood_override = -1
	_trading = false
	refresh()
	show()


## Expressão do líder pela relação com o humano.
static func mood_for(diplomacy: Diplomacy, human: Player, other: Player) -> Nation.Mood:
	var level := diplomacy.trust_level(other, human)
	if diplomacy.at_war(human, other) or level == Diplomacy.Trust.FURIOUS:
		return Nation.Mood.ANGRY
	if level in [Diplomacy.Trust.FRIENDLY, Diplomacy.Trust.BROTHERHOOD]:
		return Nation.Mood.HAPPY
	return Nation.Mood.NEUTRAL


## Atualiza o líder, o estado e as propostas (depois de cada resposta).
func refresh() -> void:
	if _game == null or _other == null:
		return
	var human := _game.viewer()
	var diplomacy := _game.diplomacy
	var mood: Nation.Mood = (_mood_override as Nation.Mood) if _mood_override >= 0 else mood_for(diplomacy, human, _other)
	_portrait_texture = Nation.portrait(_other.nation, mood)
	_stage.queue_redraw()
	var level := diplomacy.trust_level(_other, human)
	_greeting.text = "[i]%s[/i]" % _greeting_for(level, diplomacy.at_war(human, _other))
	# Depois que ele responde, a fala dele toma o lugar da recepção (o palco do
	# líder não encolhe)
	_greeting.visible = not _reply.visible
	var state := diplomacy.state(human, _other)
	_status.text = "Relação: [b]%s[/b].   Confiança dele em você: [b]%s[/b] (%+d)." % [
		Diplomacy.STATE_NAMES[state], Diplomacy.TRUST_NAMES[level], diplomacy.trust(_other, human)]
	_trade.visible = _trading
	_actions.visible = not _trading
	if _trading:
		_update_trade_hint()
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if diplomacy.at_war(human, _other):
		var peace := _make_button("Propor paz", func() -> void: peace_proposed.emit(_other))
		# Recusou há pouco: não adianta insistir no mesmo encontro
		peace.disabled = not diplomacy.can_propose(human, _other)
		if peace.disabled:
			peace.tooltip_text = "Ele recusou há pouco: espere alguns turnos."
		_actions.add_child(peace)
	else:
		var trade := _make_button("Gostaríamos de fazer uma proposta de troca", open_trade)
		trade.disabled = diplomacy.trust_level(_other, human) == Diplomacy.Trust.FURIOUS
		if trade.disabled:
			trade.tooltip_text = "Furioso com você: ele não negocia."
		_actions.add_child(trade)
		var war := _make_button("Declarar guerra", func() -> void: war_declared.emit(_other))
		war.disabled = not diplomacy.can_declare_war(human, _other)
		if diplomacy.truce_turns_left(human, _other) > 0:
			war.tooltip_text = "Trégua: ninguém declara guerra por mais %d turnos." % diplomacy.truce_turns_left(human, _other)
		_actions.add_child(war)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(spacer)
	_actions.add_child(_make_button("Encerrar encontro [Esc]", hide))


# --- Troca -----------------------------------------------------------------

func _build_trade_panel(parent: Control) -> void:
	_trade = PanelContainer.new()
	_trade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade.size_flags_stretch_ratio = 1.5
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.55)
	box.border_color = Color(StoneStyle.BRONZE, 0.8)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	_trade.add_theme_stylebox_override("panel", box)
	_trade.hide()
	parent.add_child(_trade)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_trade.add_child(column)
	var title := _make_text(18)
	title.text = "[b]Proposta de troca[/b]"
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_trade_columns = HBoxContainer.new()
	_trade_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_columns.add_theme_constant_override("separation", 16)
	scroll.add_child(_trade_columns)
	_trade_hint = _make_text(15)
	column.add_child(_trade_hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_trade_button = _make_button("Propor troca", func() -> void: trade_proposed.emit(_other, _offer.duplicate(true), _ask.duplicate(true)))
	buttons.add_child(_trade_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	buttons.add_child(_make_button("Voltar", close_trade))


## "Gostaríamos de fazer uma proposta de troca": abre o painel, vazio.
func open_trade() -> void:
	_trading = true
	_offer = Trade.empty()
	_ask = Trade.empty()
	_fill_trade_columns()
	refresh()


func close_trade() -> void:
	_trading = false
	refresh()


## Depois de uma troca feita, o painel fecha (os estoques mudaram).
func trade_done() -> void:
	close_trade()


func _fill_trade_columns() -> void:
	for child in _trade_columns.get_children():
		_trade_columns.remove_child(child)
		child.queue_free()
	var human := _game.viewer()
	_trade_columns.add_child(_trade_side("Você oferece", human, _other, _offer))
	_trade_columns.add_child(_trade_side("Você pede", _other, human, _ask))


## Uma coluna da troca: o que [param giver] tem para dar a [param receiver].
func _trade_side(title: String, giver: Player, receiver: Player, side: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	var head := _make_text(16)
	head.text = "[b]%s[/b]" % title
	column.add_child(head)
	column.add_child(_amount_row("Ouro", giver.gold, 10, func(value: int) -> void: side["gold"] = value))
	column.add_child(_amount_row("Madeira", giver.wood, 1, func(value: int) -> void: side["wood"] = value))
	if giver.iron > 0:
		column.add_child(_amount_row("Ferro", giver.iron, 1, func(value: int) -> void: side["iron"] = value))
	for weapon: Arsenal.Weapon in Arsenal.NAMES:
		var stock: int = giver.arsenal.get(weapon, 0)
		if stock > 0:
			column.add_child(_amount_row(Arsenal.PLURAL_NAMES[weapon], stock, 1,
					func(value: int) -> void: side["weapons"][weapon] = value))
	var gain := Trade.map_gain(giver, receiver)
	if gain > 0:
		column.add_child(_check_row("O mapa %s (+%d casas)" % ["seu" if giver == _game.viewer() else "dele", gain],
				func(on: bool) -> void: side["map"] = on))
	for tech in Trade.techs_to_offer(giver, receiver):
		column.add_child(_check_row(Technology.tech_name(tech), func(on: bool) -> void:
				if on:
					side["techs"].append(tech)
				else:
					side["techs"].erase(tech)))
	if column.get_child_count() == 1:
		var none := _make_text(14)
		none.text = "[i](nada para trocar)[/i]"
		column.add_child(none)
	return column


## Linha "Ouro (tem 200)  [ 0 ]": quanto entra na proposta, até [param most].
func _amount_row(label: String, most: int, step: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "%s (tem %d)" % [label, most]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var amount := SpinBox.new()
	amount.min_value = 0
	amount.max_value = most
	amount.step = step if most >= step else 1
	amount.allow_greater = false
	amount.custom_minimum_size.x = 90
	for icon in ["up_icon_modulate", "up_hover_icon_modulate", "down_icon_modulate", "down_hover_icon_modulate"]:
		amount.add_theme_color_override(icon, StoneStyle.INK) # as setas apareçam no mármore
	amount.value_changed.connect(func(value: float) -> void:
		on_change.call(int(value))
		_update_trade_hint())
	row.add_child(amount)
	return row


func _check_row(label: String, on_toggle: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label
	check.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		check.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		check.add_theme_color_override(color, StoneStyle.INK)
	check.toggled.connect(func(on: bool) -> void:
		on_toggle.call(on)
		_update_trade_hint())
	return check


## A disposição dele com a proposta como está agora (AIDiplomacy.trade_verdict).
func _update_trade_hint() -> void:
	var human := _game.viewer()
	var verdict := AIDiplomacy.trade_verdict(_game, _other, human, _ask, _offer)
	_trade_button.disabled = verdict["reason"] != "" and verdict["reason"] != "tech"
	var text := ""
	match verdict["reason"]:
		"empty":
			text = "Escolha o que você oferece e o que pede."
		"furious":
			text = "[color=#%s]Furioso com você: ele não negocia.[/color]" % StoneStyle.NEGATIVE.to_html(false)
		"tech":
			text = "[color=#%s]Ele só ensina tecnologias a quem é Amigável ou mais.[/color]" % StoneStyle.NEGATIVE.to_html(false)
		"war":
			text = "Em guerra não há comércio."
		"missing":
			text = "Alguém não tem o que a proposta pede."
		_:
			var ratio: float = verdict["ratio"]
			if ratio >= 1.0:
				text = "[color=#%s]Ele parece interessado.[/color]" % StoneStyle.POSITIVE.to_html(false)
			elif ratio >= 0.75:
				text = "Ele hesita: ofereça um pouco mais ou peça um pouco menos."
			else:
				text = "[color=#%s]Ele acha pouco: ofereça bem mais ou peça menos.[/color]" % StoneStyle.NEGATIVE.to_html(false)
	_trade_hint.text = text


## Resposta do imperador a uma proposta, mostrada embaixo; com [param mood], o
## retrato muda para essa expressão (bravo na guerra, feliz na paz aceita...).
func show_reply(text: String, mood: int = -1) -> void:
	_reply.text = text
	_reply.show()
	_mood_override = mood
	refresh()


## O palco: fundo escuro na cor da nação (mais claro no meio, atrás do líder),
## o líder inteiro no centro (proporção mantida, apoiado embaixo) ou, sem o
## retrato ainda, uma silhueta; o nome numa placa embaixo e uma moldura.
func _draw_stage() -> void:
	var rect := Rect2(Vector2.ZERO, _stage.size)
	var color := _other.color if _other else Color.GRAY
	_stage.draw_rect(rect, color.darkened(0.8))
	var center := Vector2(rect.size.x / 2.0, rect.size.y * 0.55)
	for ring in 12: # luz atrás do líder, em anéis
		var t := ring / 12.0
		_stage.draw_circle(center, rect.size.y * (0.95 - t * 0.7), Color(color.darkened(0.45), 0.06 + t * 0.03))
	if _portrait_texture:
		var image_size := Vector2(_portrait_texture.get_size())
		var scale := (rect.size.y - 8.0) / image_size.y
		var drawn := image_size * scale
		_stage.draw_texture_rect(_portrait_texture, Rect2(Vector2((rect.size.x - drawn.x) / 2.0, rect.size.y - drawn.y), drawn), false)
	else:
		var shade := color.darkened(0.88)
		var width := rect.size.y * 0.75
		_stage.draw_circle(Vector2(center.x, rect.size.y * 0.33), width * 0.2, shade)
		_stage.draw_colored_polygon(PackedVector2Array([Vector2(center.x - width * 0.5, rect.size.y),
				Vector2(center.x - width * 0.38, rect.size.y * 0.6), Vector2(center.x + width * 0.38, rect.size.y * 0.6),
				Vector2(center.x + width * 0.5, rect.size.y)]), shade)
		_stage.draw_string(ThemeDB.fallback_font, Vector2(0, 30), "Retrato em breve", HORIZONTAL_ALIGNMENT_CENTER,
				rect.size.x, 16, Color(1, 1, 1, 0.55))
	# Nome do líder numa placa escura embaixo, no centro
	if _other:
		var font := ThemeDB.fallback_font
		var title := Game.leader_name(_other)
		var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var plate := Rect2(Vector2((rect.size.x - text_size.x) / 2.0 - 16, rect.size.y - 44), Vector2(text_size.x + 32, 34))
		_stage.draw_rect(plate, Color(0, 0, 0, 0.6))
		_stage.draw_rect(plate, Color(StoneStyle.BRONZE, 0.9), false, 2.0)
		_stage.draw_string(font, Vector2(plate.position.x + 16, plate.position.y + 25), title, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 22, Color(1, 0.93, 0.78))
	_stage.draw_rect(rect, Color.BLACK, false, 3.0)
	_stage.draw_rect(rect.grow(-4), Color(StoneStyle.BRONZE, 0.7), false, 2.0)


static func _greeting_for(level: Diplomacy.Trust, at_war: bool) -> String:
	var war := " Mesmo em guerra, ele aceita ouvir o que você tem a dizer." if at_war else ""
	match level:
		Diplomacy.Trust.FURIOUS:
			return "O imperador o recebe de pé, sem esconder a raiva. \"Diga logo o que quer.\"" + war
		Diplomacy.Trust.INDIFFERENT:
			return "O imperador o recebe com cortesia fria. \"Fale, estrangeiro.\"" + war
		Diplomacy.Trust.FRIENDLY:
			return "O imperador o recebe com cordialidade. \"É bom vê-lo, vizinho.\"" + war
	return "O imperador o recebe de braços abertos, como a um irmão." + war


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _trading:
			close_trade() # Esc na troca volta ao encontro
		else:
			hide()
