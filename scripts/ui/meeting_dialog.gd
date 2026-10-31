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
##     proposta e os botões: em guerra, propor a paz; em paz, declarar guerra;
##     encerrar. A negociação (comércio, tratados) entra aqui nas próximas fases.

signal peace_proposed(player: Player)
signal war_declared(player: Player)

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

	# Em cima: o palco com o líder
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	# O retrato do líder é grande (até 1600 px): reduzido com suavidade
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stage.draw.connect(_draw_stage)
	column.add_child(_stage)

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
		var war := _make_button("Declarar guerra", func() -> void: war_declared.emit(_other))
		war.disabled = not diplomacy.can_declare_war(human, _other)
		if diplomacy.truce_turns_left(human, _other) > 0:
			war.tooltip_text = "Trégua: ninguém declara guerra por mais %d turnos." % diplomacy.truce_turns_left(human, _other)
		_actions.add_child(war)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(spacer)
	_actions.add_child(_make_button("Encerrar encontro [Esc]", hide))


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
		hide()
