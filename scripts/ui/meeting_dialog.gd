class_name MeetingDialog
extends Control

## Tela do ENCONTRO com outro imperador (desde 30/10/2026; aberta pelo botão
## "Propor encontro" da janela de Diplomacia, quando ele aceita receber você).
## No mármore: o líder (na cor dele), como ele te recebe (pela confiança), o
## estado da relação e as propostas possíveis: em guerra, propor a paz; em paz,
## declarar guerra. A resposta dele aparece na própria tela. A negociação
## (comércio, tratados) entra aqui nas próximas fases.

signal peace_proposed(player: Player)
signal war_declared(player: Player)

var _game: Game
var _other: Player
var _title: Label
var _greeting: RichTextLabel
var _status: RichTextLabel
var _reply: RichTextLabel
var _actions: HBoxContainer


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
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
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 620
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)
	_greeting = _make_text(19)
	box.add_child(_greeting)
	box.add_child(StoneStyle.separator())
	_status = _make_text(16)
	box.add_child(_status)
	_reply = _make_text(18)
	box.add_child(_reply)
	box.add_child(StoneStyle.separator())
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	box.add_child(_actions)


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
	refresh()
	show()


## Atualiza o estado e as propostas (depois de cada resposta).
func refresh() -> void:
	if _game == null or _other == null:
		return
	var human := _game.viewer()
	var diplomacy := _game.diplomacy
	_title.text = "Encontro com o %s" % Game.leader_name(_other)
	_title.add_theme_color_override("font_color", _other.color.darkened(0.25))
	var level := diplomacy.trust_level(_other, human)
	_greeting.text = "[i]%s[/i]" % _greeting_for(level, diplomacy.at_war(human, _other))
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


## Resposta do imperador a uma proposta, mostrada na tela.
func show_reply(text: String) -> void:
	_reply.text = text
	_reply.show()
	refresh()


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
