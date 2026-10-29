class_name NoticeDialog
extends Control

## Aviso no meio da tela (ex.: "A construção da fazenda foi concluída").
## "Fechar" (Enter ou Esc) fecha; "Abrir cidade" fecha e pede para abrir a
## cidade, para o jogador já dar outra tarefa aos trabalhadores livres.

## O aviso foi fechado. [param open_city] = o jogador clicou em "Abrir cidade".
signal closed(open_city: bool)

var _title: Label
var _text: RichTextLabel


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## Mostra o aviso. [param text] aceita BBCode (ex.: [color]).
func open(title: String, text: String) -> void:
	_title.text = title
	_text.text = text
	show()


func _input(event: InputEvent) -> void:
	if (visible and event is InputEventKey and event.pressed and not event.echo
			and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]):
		get_viewport().set_input_as_handled()
		_finish(false)


func _build_layout() -> void:
	# Sem fundo escuro e na metade de baixo da tela: a câmera centraliza a
	# cidade, que continua visível acima do aviso
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
	box.add_child(_title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 420
	_text.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(_make_button("Abrir cidade", _finish.bind(true)))
	buttons.add_child(_make_button("Fechar [Enter]", _finish.bind(false)))


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _finish(open_city: bool) -> void:
	hide()
	closed.emit(open_city)
