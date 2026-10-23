class_name ResearchDialog
extends Control

## Janela de escolha da pesquisa: as tecnologias disponíveis
## (Technology.available), cada uma com o custo em pontos de ciência, o que já
## foi feito nela, a estimativa de turnos e o botão "Pesquisar". Embaixo, a
## ciência por turno e as tecnologias já pesquisadas.
## Aparece ao finalizar o turno sem pesquisa escolhida, quando uma pesquisa
## termina e ao clicar no painel de Ciência do HUD. Sem pesquisa escolhida é
## preciso escolher (sem "Fechar"); trocando de pesquisa, Esc fecha.

## A janela fechou. [param tech] = tecnologia escolhida, ou -1 se fechou sem
## trocar.
signal closed(tech: int)

var _title: Label
var _rows: VBoxContainer
var _footer: Label
var _close_button: Button
var _can_close := false


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## Mostra as opções de [param player]. [param can_close] = já há uma pesquisa
## em andamento (dá para fechar sem trocar). [param title] muda o título (ex.:
## "Pesquisa concluída: Misticismo").
func open(player: Player, can_close: bool, title := "Escolha uma pesquisa") -> void:
	_can_close = can_close
	_title.text = title
	_close_button.visible = can_close
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var per_turn := player.science_per_turn()
	for tech in Technology.available(player.researched):
		_add_row(player, tech, per_turn)
	var done: Array = player.researched.map(func(tech: int) -> String: return Technology.tech_name(tech))
	_footer.text = "Ciência: +%d por turno (Prefeituras).   Os pontos não se acumulam: vão para a pesquisa escolhida.%s" % [
		per_turn, "\nJá pesquisadas: %s" % ", ".join(done) if not done.is_empty() else ""]
	show()


func _input(event: InputEvent) -> void:
	if visible and _can_close and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish(-1)


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.draw.connect(func() -> void: Icons.draw_science(icon, Rect2(Vector2.ZERO, icon.size)))
	header.add_child(icon)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close_button = _make_button("Fechar [Esc]", _finish.bind(-1))
	header.add_child(_close_button)
	box.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", CityWindow.MUTED_COLOR)
	_footer.add_theme_font_size_override("font_size", 13)
	box.add_child(_footer)


## Linha: nome, custo, progresso já feito, turnos estimados e "Pesquisar".
func _add_row(player: Player, tech: int, per_turn: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = Technology.DATA[tech]["description"]
	_rows.add_child(row)
	var name_label := Label.new()
	name_label.text = Technology.tech_name(tech)
	name_label.custom_minimum_size.x = 150
	name_label.add_theme_font_size_override("font_size", 18)
	row.add_child(name_label)
	var cost_label := Label.new()
	var done: int = player.research_progress.get(tech, 0)
	cost_label.text = "%d pontos de ciência%s" % [Technology.cost(tech), "  (%d feitos)" % done if done > 0 else ""]
	cost_label.custom_minimum_size.x = 260
	cost_label.add_theme_color_override("font_color", Icons.SCIENCE_COLOR)
	row.add_child(cost_label)
	var turns_label := Label.new()
	turns_label.text = "%d turnos" % ceili(float(Technology.cost(tech) - done) / per_turn) if per_turn > 0 else "sem ciência"
	turns_label.custom_minimum_size.x = 100
	turns_label.add_theme_color_override("font_color", CityWindow.MUTED_COLOR)
	row.add_child(turns_label)
	var current := player.research == tech
	var button := _make_button("Pesquisando" if current else "Pesquisar", _finish.bind(tech))
	button.custom_minimum_size.x = 130
	button.disabled = current
	row.add_child(button)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _finish(tech: int) -> void:
	hide()
	closed.emit(tech)
