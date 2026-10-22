class_name SaveDialog
extends Control

## Janela de salvar (F5) ou carregar (F9) a partida. Cada linha é um espaço
## (SaveGame): o nome, o que está guardado nele (turno, jogador da vez e data)
## e o botão "Salvar" / "Carregar". O salvamento automático só aparece para
## carregar. Esc ou "Cancelar" fecham sem fazer nada.

## A janela fechou. [param slot] = espaço escolhido, ou -1 se cancelou.
signal closed(slot: int)

var _title: Label
var _rows: VBoxContainer
var _saving := false


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## [param saving] true = salvar; false = carregar.
func open(saving: bool) -> void:
	_saving = saving
	_title.text = "Salvar partida" if saving else "Carregar partida"
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not saving:
		_add_row(SaveGame.AUTOSAVE_SLOT)
	for slot in range(1, SaveGame.SLOTS + 1):
		_add_row(slot)
	show()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
	box.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_make_button("Cancelar [Esc]", _finish.bind(-1)))
	box.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	var where := Label.new()
	where.text = "Os saves ficam em %s" % ProjectSettings.globalize_path(SaveGame.directory)
	where.add_theme_color_override("font_color", CityWindow.MUTED_COLOR)
	where.add_theme_font_size_override("font_size", 13)
	box.add_child(where)


func _add_row(slot: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_rows.add_child(row)
	var slot_label := Label.new()
	slot_label.text = SaveGame.slot_name(slot)
	slot_label.custom_minimum_size.x = 110
	row.add_child(slot_label)
	var info := Label.new()
	info.text = SaveGame.summary(slot)
	info.custom_minimum_size.x = 430
	info.add_theme_color_override("font_color", Color.WHITE if SaveGame.has_save(slot) else CityWindow.MUTED_COLOR)
	row.add_child(info)
	var button := _make_button("Salvar" if _saving else "Carregar", _finish.bind(slot))
	button.custom_minimum_size.x = 100
	if _saving and SaveGame.has_save(slot):
		button.tooltip_text = "Substitui o que está guardado neste espaço."
	if not _saving and SaveGame.read(slot).is_empty():
		button.disabled = true
		button.tooltip_text = "Nada para carregar neste espaço."
	row.add_child(button)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	CityWindow.style_button(button)
	return button


func _finish(slot: int) -> void:
	hide()
	closed.emit(slot)
