class_name UnitPanel
extends Control

## Painel da unidade selecionada, no canto inferior esquerdo (desde 28/10/2026,
## a partir do mockup do usuário; no lugar das barras de informação e de ações):
##   - Retrato: círculo grande com o desenho da unidade em alta resolução
##     (assets/sprites/units/retratos/, os originais do Gemini) sobre o terreno
##     da casa em que ela está, com o anel na cor do dono. Para a madeireira
##     ou mina remota selecionada, o desenho dela.
##   - Energia: arco em meia-lua no lado esquerdo do círculo, enchendo de baixo
##     para cima; verde acima de 60%, amarelo acima de 30%, vermelho abaixo.
##   - Movimento: arco em meia-lua no lado direito, dourado, cheio no começo
##     do turno e esvaziando conforme a unidade anda (pedido do usuário).
##   - Cartão: nome, Ataque, Defesa, Movimento, Energia e dono; a situação (fortificada, a caminho, a bordo...); e
##     uma linha extra: a prévia do ataque sobre um inimigo, a unidade sob o
##     mouse, ou a casa sob o mouse.
##   - Ações: botões redondos em cima do cartão, com ícone e a tecla no canto;
##     o texto completo no tooltip. Sem unidade selecionada, o painel some.

signal action_pressed(action_id: String)

const RADIUS := 74.0
const RING := 5.0
const ARC_WIDTH := 9.0
const MARGIN := 8.0
const CARD_WIDTH := 400.0
const CARD_HEIGHT := 132.0
const BUTTON := 46.0
const BUTTON_GAP := 8.0
const PORTRAITS := "res://assets/sprites/units/retratos/"
const CARD_COLOR := Color(0.08, 0.09, 0.11, 0.88)
const GOLD := Color(0.85, 0.72, 0.4)
const TRACK_COLOR := Color(0, 0, 0, 0.55)
const MOVE_COLOR := Color(0.45, 0.78, 1.0)
const TEXT := Color(0.93, 0.93, 0.93)
const MUTED := Color(0.68, 0.7, 0.74)

var _unit: Unit
var _mill: LumberMill
var _owner_color := Color.WHITE
var _portrait: Texture2D
var _ground: Texture2D
var _buttons: HBoxContainer
var _name: RichTextLabel
var _stats: RichTextLabel
var _status: Label
var _extra: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(_center().x + CARD_WIDTH, _center().y + RADIUS + RING + ARC_WIDTH + 2.0)
	size = custom_minimum_size
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", int(BUTTON_GAP))
	_buttons.position = Vector2(_center().x + RADIUS * 0.95, 0)
	add_child(_buttons)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.position = Vector2(_center().x + RADIUS + 14.0, _card_rect().position.y + 22.0)
	box.size = Vector2(_card_rect().end.x - box.position.x - 12.0, CARD_HEIGHT - 26.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_name = _rich(21)
	box.add_child(_name)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.add_theme_font_size_override("normal_font_size", 15)
	_stats.add_theme_font_size_override("bold_font_size", 15)
	box.add_child(_stats)
	_status = _label(13, Color(1.0, 0.86, 0.45))
	box.add_child(_status)
	_extra = _label(13, MUTED)
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extra.max_lines_visible = 2
	_extra.custom_minimum_size.x = box.size.x
	box.add_child(_extra)
	hide()


## Mostra [param unit]. [param extra]: a linha de baixo (prévia de ataque,
## unidade ou casa sob o mouse).
func show_unit(unit: Unit, map: GameMap, extra := "") -> void:
	_unit = unit
	_mill = null
	_owner_color = unit.owner_player.color
	_portrait = portrait(unit.type, _owner_color)
	_ground = map.terrain_texture(map.get_terrain(unit.cell))
	_name.text = _title(unit.type.display_name, unit.owner_player)
	var attack := "Ataque [b]%d[/b]%s" % [unit.attack, " (alcance %d)" % unit.type.attack_range if unit.is_ranged() else ""]
	_stats.text = "%s   Defesa [b]%d[/b]\nMovimento [color=#73c7ff][b]%s[/b]/%d[/color]   Energia [b]%d[/b]/%d" % [
		attack, unit.defense, unit.moves_text(), unit.movement, unit.energy, unit.max_energy]
	var status: Array[String] = []
	if unit.fortified:
		status.append("Fortificada")
	if unit.terrain_defense_bonus() > 0:
		status.append("+%d de defesa (%s)" % [unit.terrain_defense_bonus(), Terrain.NAMES[map.get_terrain(unit.cell)].to_lower()])
	if unit.walls_defense_bonus() > 0:
		status.append("+%d muralha" % unit.walls_defense_bonus())
	if unit.has_goto():
		status.append("A caminho de (%d, %d)" % [unit.goto_target.x, unit.goto_target.y])
	if unit.type.cargo_capacity > 0:
		status.append("A bordo %d/%d" % [unit.cargo.size(), unit.type.cargo_capacity])
	if unit.transport:
		status.append("Embarcada na Galé")
	if unit.rebuilding:
		status.append("Trabalhando na obra")
	_set_lines(status, extra)


## Mostra a madeireira (ou mina) remota selecionada.
func show_mill(mill: LumberMill, map: GameMap, extra := "") -> void:
	_unit = null
	_mill = mill
	_owner_color = mill.owner_player.color
	_portrait = City.MINE_TEXTURE if mill.is_mine else LumberMill.TEXTURE
	_ground = map.terrain_texture(map.get_terrain(mill.cell))
	_name.text = _title(mill.display_name(), mill.owner_player)
	var production := "+%d de ferro por turno" % mill.iron_per_turn() if mill.is_mine else "+%d de madeira por turno" % mill.wood_per_turn()
	if not mill.is_done():
		production = "Em obra %d/%d" % [mill.progress, mill.cost()]
	_stats.text = "Trabalhadores [b]%d[/b]/%d   %s" % [mill.workers.size(), LumberMill.MAX_WORKERS, production]
	_set_lines(["Destruída: um Trabalhador pode reconstruir"] if mill.pillaged else [], extra)


func _set_lines(status: Array, extra: String) -> void:
	_status.text = "  ·  ".join(status)
	_status.visible = not status.is_empty()
	_extra.text = extra
	_extra.visible = not extra.is_empty()
	show()
	queue_redraw()


## Troca os botões de ação ([param actions]: os mesmos de Hud.set_unit_actions).
func set_actions(actions: Array[Dictionary]) -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for action in actions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(BUTTON, BUTTON)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = action.get("disabled", false)
		var label: String = action["label"]
		var tooltip: String = action.get("tooltip", "")
		button.tooltip_text = label + ("\n" + tooltip if not tooltip.is_empty() else "")
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = {"normal": Color(0.13, 0.15, 0.19), "hover": Color(0.24, 0.27, 0.33),
					"pressed": Color(0.3, 0.34, 0.42), "disabled": Color(0.1, 0.1, 0.12, 0.85)}[state]
			style.set_corner_radius_all(int(BUTTON / 2.0))
			style.border_color = GOLD if state != "disabled" else Color(0.35, 0.35, 0.38)
			style.set_border_width_all(2)
			button.add_theme_stylebox_override(state, style)
		var id: String = action["id"]
		var key := ""
		if label.contains("[") and label.ends_with("]"):
			key = label.substr(label.rfind("[") + 1, label.length() - label.rfind("[") - 2)
		key = "Esp" if key == "Espaço" else key
		button.draw.connect(func() -> void: _draw_action_icon(button, id, key))
		button.pressed.connect(action_pressed.emit.bind(id))
		_buttons.add_child(button)


## Só o círculo e o cartão pegam o mouse (o resto do retângulo deixa o clique
## passar para o mapa).
func _has_point(point: Vector2) -> bool:
	if not visible:
		return false
	return point.distance_to(_center()) <= RADIUS + RING + ARC_WIDTH or _card_rect().has_point(point)


func _center() -> Vector2:
	return Vector2(MARGIN + ARC_WIDTH + RING + RADIUS + 2.0, BUTTON / 2.0 + RADIUS + 6.0)


func _card_rect() -> Rect2:
	return Rect2(Vector2(_center().x, BUTTON / 2.0 + 6.0), Vector2(CARD_WIDTH, CARD_HEIGHT))


func _draw() -> void:
	if _unit == null and _mill == null:
		return
	var center := _center()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.set_corner_radius_all(14)
	style.border_color = Color(GOLD, 0.55)
	style.set_border_width_all(1)
	draw_style_box(style, _card_rect())
	# Energia: trilho e arco na meia-lua da esquerda, de baixo para cima
	var arc_radius := RADIUS + RING + ARC_WIDTH / 2.0 + 2.0
	draw_arc(center, arc_radius, PI / 2.0, PI * 1.5, 48, TRACK_COLOR, ARC_WIDTH + 3.0, true)
	if _unit:
		var ratio := float(_unit.energy) / _unit.max_energy
		var energy_color := Color(0.25, 0.85, 0.3) if ratio > 0.6 else Color(0.95, 0.8, 0.2) if ratio > 0.3 else Color(0.9, 0.25, 0.2)
		draw_arc(center, arc_radius, PI / 2.0, PI / 2.0 + PI * ratio, 48, energy_color, ARC_WIDTH, true)
		# Movimento: meia-lua da direita, de baixo para cima
		draw_arc(center, arc_radius, -PI / 2.0, PI / 2.0, 48, TRACK_COLOR, ARC_WIDTH + 3.0, true)
		var moves := clampf(float(_unit.moves_left) / maxf(_unit.max_points(), 1.0), 0.0, 1.0)
		if moves > 0.0:
			draw_arc(center, arc_radius, PI / 2.0 - PI * moves, PI / 2.0, 48, MOVE_COLOR, ARC_WIDTH, true)
	# Anel na cor do dono, o terreno da casa e o retrato
	draw_circle(center, RADIUS + RING, _owner_color.darkened(0.15))
	_draw_textured_circle(_ground, center, RADIUS)
	draw_circle(center, RADIUS, Color(0, 0, 0, 0.18))
	if _portrait:
		var image_size := Vector2(_portrait.get_size())
		var fit := minf(RADIUS * 1.55 / image_size.y, RADIUS * 1.7 / image_size.x)
		if _mill:
			fit = RADIUS * 1.5 / maxf(image_size.x, image_size.y)
		var rect := Rect2(center + Vector2(-image_size.x * fit / 2.0, RADIUS * 0.82 - image_size.y * fit), image_size * fit)
		if _mill:
			rect.position.y = center.y - image_size.y * fit / 2.0
		draw_texture_rect(_portrait, rect, false)
	draw_arc(center, RADIUS, 0, TAU, 64, Color(0, 0, 0, 0.7), 2.0, true)


## Textura recortada num círculo (polígono com coordenadas de textura).
func _draw_textured_circle(texture: Texture2D, center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var dir := Vector2.from_angle(TAU * i / 48.0)
		points.append(center + dir * radius)
		uvs.append(dir * 0.5 + Vector2(0.5, 0.5))
	draw_colored_polygon(points, Color(1, 1, 1), uvs, texture)


## Retrato em alta resolução do tipo de unidade, na cor do dono (o mesmo nome
## do desenho pequeno, em PORTRAITS; sem retrato, o desenho pequeno).
static func portrait(type: UnitType, color: Color) -> Texture2D:
	if type.sprite == null:
		return null
	var path := PORTRAITS + type.sprite.resource_path.get_file()
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else type.sprite
	return Unit.team_texture(texture, color)


## Ícone de cada ação, desenhado no botão redondo, e a tecla no canto.
func _draw_action_icon(button: Button, id: String, key: String) -> void:
	var s := button.size
	var c := s / 2.0
	var ink := Color(0.95, 0.9, 0.78) if not button.disabled else Color(0.45, 0.45, 0.47)
	var icon := Rect2(c - Vector2(13, 13), Vector2(26, 26))
	match id:
		"farm":
			Icons.draw_build(button, City.Build.FARM, icon, Color.WHITE)
		"lumber_mill":
			Icons.draw_build(button, City.Build.LUMBER_MILL, icon, Color.WHITE)
		"mine":
			Icons.draw_build(button, City.Build.MINE, icon, Color.WHITE)
		"found_city":
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -1), c + Vector2(0, -11), c + Vector2(11, -1)]), Color(0.8, 0.35, 0.2))
			button.draw_rect(Rect2(c + Vector2(-8, -1), Vector2(16, 12)), Color(0.93, 0.9, 0.82))
			button.draw_rect(Rect2(c + Vector2(-2, 4), Vector2(4, 7)), Color(0.4, 0.28, 0.18))
		"road":
			var road := PackedVector2Array([c + Vector2(-10, 11), c + Vector2(-3, 0), c + Vector2(3, -2), c + Vector2(10, -11)])
			button.draw_polyline(road, Color(0.75, 0.62, 0.42), 7.0)
			button.draw_polyline(road, Color(0.45, 0.35, 0.22), 1.5)
		"rebuild":
			button.draw_line(c + Vector2(-8, 9), c + Vector2(5, -4), Color(0.6, 0.42, 0.25), 3.5)
			button.draw_rect(Rect2(c + Vector2(1, -11), Vector2(11, 7)), Color(0.7, 0.72, 0.76))
		"join_city":
			for dx in [-6, 6]:
				button.draw_circle(c + Vector2(dx, -5), 4.0, ink)
				button.draw_rect(Rect2(c + Vector2(dx - 5, 0), Vector2(10, 10)), ink)
		"pillage":
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(8, 3), c + Vector2(0, 11), c + Vector2(-8, 3)]), Color(0.95, 0.45, 0.15))
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(4, 4), c + Vector2(0, 9), c + Vector2(-4, 4)]), Color(1, 0.85, 0.3))
		"goto":
			button.draw_line(c + Vector2(-9, 9), c + Vector2(6, -6), ink, 2.5)
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(10, -10), c + Vector2(0, -7), c + Vector2(7, 0)]), ink)
		"cancel_goto":
			button.draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), Color(0.95, 0.4, 0.35), 3.0)
			button.draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), Color(0.95, 0.4, 0.35), 3.0)
		"fortify":
			var shield := PackedVector2Array([c + Vector2(-9, -10), c + Vector2(9, -10), c + Vector2(9, 0), c + Vector2(0, 11), c + Vector2(-9, 0)])
			button.draw_colored_polygon(shield, Color(0.62, 0.55, 0.45))
			button.draw_polyline(shield + PackedVector2Array([shield[0]]), ink, 1.5)
		"skip":
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -10), c + Vector2(7, -10), c + Vector2(0, 0)]), ink)
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 10), c + Vector2(7, 10), c + Vector2(0, 0)]), ink)
		"unload":
			button.draw_line(c + Vector2(0, -10), c + Vector2(0, 6), ink, 2.5)
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 2), c + Vector2(7, 2), c + Vector2(0, 11)]), ink)
		"release_worker":
			button.draw_circle(c + Vector2(-3, -5), 4.0, ink)
			button.draw_rect(Rect2(c + Vector2(-8, 0), Vector2(10, 10)), ink)
			button.draw_line(c + Vector2(3, 3), c + Vector2(11, 3), ink, 2.5)
			button.draw_colored_polygon(PackedVector2Array([c + Vector2(12, 3), c + Vector2(7, -1), c + Vector2(7, 7)]), ink)
		_:
			button.draw_circle(c, 6, ink)
	if not key.is_empty():
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var badge := Rect2(Vector2(s.x - width - 6, s.y - 15), Vector2(width + 6, 14))
		button.draw_rect(badge, Color(0, 0, 0, 0.75))
		button.draw_string(font, badge.position + Vector2(3, 11), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.86, 0.45))


## Nome grande e o dono, menor, na cor dele.
func _title(name: String, owner: Player) -> String:
	return "%s  [font_size=14][color=#%s]%s[/color][/font_size]" % [name, owner.color.to_html(false), owner.display_name]


func _rich(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", TEXT)
	return label


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
