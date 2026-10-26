class_name TechTreeDialog
extends Control

## Árvore de tecnologias (a techtree.drawio do usuário dentro do jogo): todas as
## tecnologias em colunas pela profundidade (as raízes à esquerda; cada uma
## fica uma coluna depois da exigência mais funda), com setas das exigidas para
## as que dependem delas. Cada cartão mostra o nome, o custo, o estado e o que
## a tecnologia libera:
##   pesquisada   verde;
##   pesquisando  azul, com a barra de progresso e os turnos que faltam;
##   disponível   dourado: clicar escolhe a pesquisa (na vez do jogador);
##   bloqueada    cinza, com as tecnologias que faltam.
## Abre pelo botão "Árvore [T]" do painel de Ciência do HUD ou pela tecla T.

## O jogador clicou numa tecnologia disponível para pesquisá-la.
signal research_chosen(tech: int)
signal closed

const CARD_SIZE := Vector2(232, 124)
const GAP := Vector2(54, 14)
const MARGIN := 16.0
const RESEARCHED_COLOR := Color(0.36, 0.8, 0.4)
const AVAILABLE_COLOR := Color(1.0, 0.82, 0.3)
const LOCKED_COLOR := Color(0.45, 0.45, 0.5)
const LINE_COLOR := Color(0.55, 0.55, 0.6, 0.8)

var _title: Label
var _footer: Label
var _scroll: ScrollContainer
var _canvas: Control
## Posição (canto de cima à esquerda) de cada cartão: {Tech: Vector2}.
var _positions := {}
var _player: Player
var _can_choose := false


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## Mostra a árvore do [param player]. [param can_choose] = dá para escolher a
## pesquisa clicando (vez do jogador, nada acontecendo).
func open(player: Player, can_choose: bool) -> void:
	_player = player
	_can_choose = can_choose
	_layout()
	_fill()
	show()


func close() -> void:
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ESCAPE, KEY_T]:
		get_viewport().set_input_as_handled()
		close()


# --- Montagem ------------------------------------------------------------------

func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set("offset_" + ["left", "top", "right", "bottom"][side], 24.0 if side < 2 else -24.0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
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
	header.add_child(_legend())
	var close_button := Button.new()
	close_button.text = "Fechar [Esc]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	CityWindow.style_button(close_button)
	header.add_child(close_button)
	box.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_canvas = Control.new()
	_canvas.draw.connect(_draw_links)
	_scroll.add_child(_canvas)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", CityWindow.MUTED_COLOR)
	_footer.add_theme_font_size_override("font_size", 13)
	box.add_child(_footer)


## Legenda das cores, no cabeçalho.
func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for item in [["Pesquisada", RESEARCHED_COLOR], ["Pesquisando", Icons.SCIENCE_COLOR],
			["Disponível", AVAILABLE_COLOR], ["Bloqueada", LOCKED_COLOR]]:
		var swatch := ColorRect.new()
		swatch.color = item[1]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = item[0]
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
	return row


## Coluna de cada tecnologia: 0 sem exigências; senão, 1 + a maior coluna das
## exigidas.
static func depth(tech: int) -> int:
	var deepest := -1
	for required: int in Technology.DATA[tech]["requires"]:
		deepest = maxi(deepest, depth(required))
	return deepest + 1


## Posições dos cartões. A primeira coluna segue a ordem do enum; nas outras,
## cada cartão tenta ficar na altura média das suas exigidas (menos cruzamento
## de setas), sem encostar no de cima.
func _layout() -> void:
	_positions = {}
	var columns := {}
	for tech: int in Technology.DATA:
		var column := depth(tech)
		if not columns.has(column):
			columns[column] = []
		columns[column].append(tech)
	var height := 0.0
	for column: int in range(columns.size()):
		var techs: Array = columns[column]
		var wanted := {}
		for tech: int in techs:
			var required: Array = Technology.DATA[tech]["requires"]
			if required.is_empty():
				wanted[tech] = 0.0
			else:
				var total := 0.0
				for other: int in required:
					total += _positions[other].y
				wanted[tech] = total / required.size()
		if column > 0:
			techs.sort_custom(func(a: int, b: int) -> bool: return wanted[a] < wanted[b] or (wanted[a] == wanted[b] and a < b))
		var y := MARGIN
		for tech: int in techs:
			if column > 0:
				y = maxf(y, wanted[tech])
			_positions[tech] = Vector2(MARGIN + column * (CARD_SIZE.x + GAP.x), y)
			y += CARD_SIZE.y + GAP.y
		height = maxf(height, y)
	_canvas.custom_minimum_size = Vector2(MARGIN * 2 + columns.size() * (CARD_SIZE.x + GAP.x) - GAP.x, height + MARGIN)


## Cria os cartões e os textos.
func _fill() -> void:
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	for tech: int in Technology.DATA:
		_canvas.add_child(_card(tech))
	_canvas.queue_redraw()
	var done := _player.researched.size()
	_title.text = "Árvore de tecnologias - %d de %d pesquisadas" % [done, Technology.DATA.size()]
	var per_turn := _player.science_per_turn()
	_footer.text = "Ciência: +%d por turno. %s Passe o mouse num cartão para ler a descrição." % [per_turn,
			"Clique numa tecnologia disponível (dourada) para pesquisá-la." if _can_choose else "Dá para escolher a pesquisa na sua vez."]


# --- Cartões -------------------------------------------------------------------

## Estado da tecnologia para o jogador: "researched", "researching",
## "available" ou "locked".
func _state(tech: int) -> String:
	if _player.researched.has(tech):
		return "researched"
	if _player.research == tech:
		return "researching"
	if Technology.available(_player.researched).has(tech):
		return "available"
	return "locked"


func _card(tech: int) -> Control:
	var state := _state(tech)
	var accent: Color = {"researched": RESEARCHED_COLOR, "researching": Icons.SCIENCE_COLOR,
			"available": AVAILABLE_COLOR, "locked": LOCKED_COLOR}[state]
	var card := PanelContainer.new()
	card.position = _positions[tech]
	card.size = CARD_SIZE
	card.custom_minimum_size = CARD_SIZE
	card.clip_contents = true
	card.tooltip_text = Technology.DATA[tech]["description"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.17) if state == "locked" else Color(0.16, 0.18, 0.22)
	if state == "researched":
		style.bg_color = Color(0.13, 0.22, 0.15)
	style.border_color = accent
	style.set_border_width_all(3 if state in ["researching", "available"] else 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	if state == "available" and _can_choose:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				research_chosen.emit(tech)
				_fill())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var name_label := _label(Technology.tech_name(tech), 17, Color.WHITE if state != "locked" else Color(0.7, 0.7, 0.72))
	name_label.clip_text = true
	box.add_child(name_label)
	var status := _label(_status_text(tech, state), 12, accent)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	box.add_child(status)
	if state == "researching":
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		bar.max_value = Technology.cost(tech)
		bar.value = _player.research_progress.get(tech, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Icons.SCIENCE_COLOR
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.3, 0.3, 0.33)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		box.add_child(bar)
	var unlocks := unlocks_of(tech)
	if not unlocks.is_empty():
		var label := _label("Libera: " + ", ".join(unlocks), 12, Color(0.82, 0.82, 0.85) if state != "locked" else Color(0.6, 0.6, 0.62))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 3
		box.add_child(label)
	return card


func _status_text(tech: int, state: String) -> String:
	var cost := Technology.cost(tech)
	match state:
		"researched":
			return "Pesquisada (%d pontos)" % cost
		"researching":
			var turns := _player.research_turns()
			return "Pesquisando %d/%d%s" % [_player.research_progress.get(tech, 0), cost, " - %d turnos" % turns if turns > 0 else ""]
		"available":
			var done: int = _player.research_progress.get(tech, 0)
			return "Disponível - %d pontos%s" % [cost, " (%d feitos)" % done if done > 0 else ""]
	var missing: Array = Technology.DATA[tech]["requires"].filter(func(r: int) -> bool: return not _player.researched.has(r))
	return "%d pontos - falta %s" % [cost, ", ".join(missing.map(Technology.tech_name))]


## O que a tecnologia libera: as construções e unidades de City.BUILDS com
## "tech" igual a ela e os textos de "unlocks" (regras, Estrada...).
static func unlocks_of(tech: int) -> Array[String]:
	var result: Array[String] = []
	for build: int in City.BUILDS:
		if City.BUILDS[build].get("tech", -1) == tech:
			result.append(City.BUILDS[build]["name"])
	for extra: String in Technology.DATA[tech].get("unlocks", []):
		result.append(extra)
	return result


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Setas das exigidas para as que dependem delas (atrás dos cartões): curva do
## lado direito da exigida até o lado esquerdo da outra; verde se a exigida já
## foi pesquisada.
func _draw_links() -> void:
	if _player == null:
		return
	for tech: int in Technology.DATA:
		for required: int in Technology.DATA[tech]["requires"]:
			var from: Vector2 = _positions[required] + Vector2(CARD_SIZE.x, CARD_SIZE.y / 2.0)
			var to: Vector2 = _positions[tech] + Vector2(0, CARD_SIZE.y / 2.0)
			var color := RESEARCHED_COLOR if _player.researched.has(required) else LINE_COLOR
			var curve := Curve2D.new()
			var pull := (to.x - from.x) * 0.5
			curve.add_point(from, Vector2.ZERO, Vector2(pull, 0))
			curve.add_point(to, Vector2(-pull, 0), Vector2.ZERO)
			_canvas.draw_polyline(curve.tessellate(), color, 2.5, true)
			_canvas.draw_colored_polygon(PackedVector2Array([to, to + Vector2(-10, -6), to + Vector2(-10, 6)]), color)
