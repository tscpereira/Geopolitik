class_name InvasionDialog
extends Control

## Escolha do jogador quando uma unidade militar dele entra numa cidade inimiga
## sem guarnição (Game.check_invasion):
##   "Ocupar [O]"                 a cidade passa a ser dele;
##   "Saquear e destruir [S]"     ganha o ouro do saque e a cidade vira ruína.
## Não dá para fechar sem escolher.

## [param raze] = true: saquear e destruir; false: ocupar.
signal chosen(raze: bool)

var _title: Label
var _text: RichTextLabel
var _raze_button: Button


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## [param text] aceita BBCode. [param loot] = ouro do saque (no botão).
func open(title: String, text: String, loot: int) -> void:
	_title.text = title
	_text.text = text
	_raze_button.text = "Saquear e destruir (+%d ouro) [S]" % loot
	show()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_O:
		get_viewport().set_input_as_handled()
		_finish(false)
	elif event.keycode == KEY_S:
		get_viewport().set_input_as_handled()
		_finish(true)


func _build_layout() -> void:
	# Na metade de baixo: a câmera centraliza a cidade, que continua visível
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_top = 0.5
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	box.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 520
	_text.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(_make_button("Ocupar [O]", _finish.bind(false)))
	_raze_button = _make_button("Saquear e destruir [S]", _finish.bind(true))
	buttons.add_child(_raze_button)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _finish(raze: bool) -> void:
	hide()
	chosen.emit(raze)
