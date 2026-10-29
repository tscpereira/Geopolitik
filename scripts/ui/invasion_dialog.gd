class_name InvasionDialog
extends Control

## Escolha do jogador quando uma unidade militar dele entra numa cidade inimiga
## sem guarnição (Game.check_invasion): só o título e dois botões,
##   "Ocupar"              a cidade passa a ser dele (tecla O);
##   "Saquear e destruir"  ganha o ouro do saque e a cidade vira ruína (tecla S).
## O que cada opção faz (e o ouro do saque) fica no tooltip de cada botão.
## Não dá para fechar sem escolher.

## [param raze] = true: saquear e destruir; false: ocupar.
signal chosen(raze: bool)

var _title: Label
var _occupy_button: Button
var _raze_button: Button


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## [param occupy_tip] e [param raze_tip]: tooltips dos dois botões.
func open(title: String, occupy_tip: String, raze_tip: String) -> void:
	_title.text = title
	_occupy_button.tooltip_text = occupy_tip
	_raze_button.tooltip_text = raze_tip
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
	panel.theme = StoneStyle.theme()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_occupy_button = _make_button("Ocupar", _finish.bind(false))
	buttons.add_child(_occupy_button)
	_raze_button = _make_button("Saquear e destruir", _finish.bind(true))
	buttons.add_child(_raze_button)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.x = 180
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _finish(raze: bool) -> void:
	hide()
	chosen.emit(raze)
