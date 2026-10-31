class_name StartScreen
extends Control

## Tela de início de uma partida nova (desde 30/10/2026, pedido do usuário):
## no mármore das janelas, a escolha da NAÇÃO (Nation: Romanos, Gregos,
## Fenícios, Egípcios, Americanos, Ingleses) e da COR. Escolher a nação já põe
## a cor dela (dá para trocar depois). "Começar" (ou Enter) devolve a escolha
## ao Game, que monta os jogadores (Game._create_players).

## {"nation": Nation.Id, "color": Color}
signal chosen(choice: Dictionary)

var _nation: int = Nation.Id.ROMANS
var _color: Color = Nation.DATA[Nation.Id.ROMANS]["color"]
var _nation_buttons := {}
var _color_buttons: Array[Button] = []
var _summary: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = Color8(24, 22, 20)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	panel.theme = StoneStyle.theme()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 820
	panel.add_child(box)

	var title := Label.new()
	title.text = "Nova partida"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	box.add_child(title)
	box.add_child(StoneStyle.separator())

	box.add_child(_section("Escolha a sua nação"))
	var nations := GridContainer.new()
	nations.columns = 3
	nations.add_theme_constant_override("h_separation", 12)
	nations.add_theme_constant_override("v_separation", 12)
	box.add_child(nations)
	var group := ButtonGroup.new()
	for nation: int in Nation.DATA:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(260, 70)
		button.text = "%s\n%s" % [Nation.name_of(nation), Nation.DATA[nation]["description"]]
		button.add_theme_font_size_override("font_size", 16)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CityWindow.style_button(button)
		button.pressed.connect(_on_nation.bind(nation))
		# Moldura bronze na escolhida
		button.draw.connect(func() -> void:
			if _nation == nation:
				button.draw_rect(Rect2(Vector2(3, 3), button.size - Vector2(6, 6)), StoneStyle.BRONZE, false, 3.0))
		nations.add_child(button)
		_nation_buttons[nation] = button

	box.add_child(_section("Escolha a sua cor"))
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 10)
	box.add_child(colors)
	for color in Nation.COLORS:
		var swatch := Button.new()
		swatch.flat = true
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(46, 46)
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		swatch.draw.connect(_draw_swatch.bind(swatch, color))
		swatch.pressed.connect(_on_color.bind(color))
		colors.add_child(swatch)
		_color_buttons.append(swatch)

	box.add_child(StoneStyle.separator())
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.add_theme_font_size_override("normal_font_size", 18)
	_summary.add_theme_font_size_override("bold_font_size", 18)
	box.add_child(_summary)
	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(start_row)
	var start := Button.new()
	start.text = "Começar [Enter]"
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_size_override("font_size", 22)
	CityWindow.style_button(start)
	start.pressed.connect(_start)
	start_row.add_child(start)

	_on_nation(_nation)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", StoneStyle.BRONZE)
	return label


func _on_nation(nation: int) -> void:
	_nation = nation
	_nation_buttons[nation].button_pressed = true
	# A escolhida: afundada (botão apertado) e com o texto em bronze forte
	for other: int in _nation_buttons:
		var button: Button = _nation_buttons[other]
		var picked := other == nation
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, StoneStyle.BRONZE if picked else Color8(70, 44, 18))
		button.add_theme_font_size_override("font_size", 17 if picked else 16)
		for child in button.get_children():
			child.queue_redraw() # a placa de pedra (afundada ou não)
		button.queue_redraw()
	_on_color(Nation.DATA[nation]["color"])


func _on_color(color: Color) -> void:
	_color = color
	for swatch in _color_buttons:
		swatch.queue_redraw()
	_summary.text = "Você será o [b][color=#%s]%s[/color][/b].\nMapa: Três continentes, com 6 nações (2 em cada continente). As outras 5 são da máquina." % [
		_color.darkened(0.2).to_html(false), Nation.leader(_nation)]


## Cor escolhível: um círculo; a escolhida com um anel escuro em volta.
func _draw_swatch(swatch: Button, color: Color) -> void:
	var center := swatch.size / 2.0
	var radius := minf(swatch.size.x, swatch.size.y) / 2.0 - 4.0
	if color == _color:
		swatch.draw_circle(center, radius + 3.0, StoneStyle.INK)
	swatch.draw_circle(center, radius, Color(0, 0, 0, 0.6))
	swatch.draw_circle(center, radius - 2.0, color)


func _start() -> void:
	chosen.emit({"nation": _nation, "color": _color})


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_start()
