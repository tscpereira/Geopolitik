class_name CityMapView
extends Control

## Mapa da área de trabalho da cidade, na janela da cidade: a cidade no centro,
## as 8 casas vizinhas e as 12 seguintes (sem as pontas). Mostra o terreno, as
## fazendas, as madeireiras (com a madeira que resta), as obras (com progresso)
## e os cidadãos trabalhando. A borda na cor do dono marca o território (a
## área de trabalho); as casas de fora aparecem escurecidas.
## Casas do raio de ação que são território de outra cidade do mesmo jogador
## ficam em vermelho translúcido, com a melhoria da outra cidade por baixo:
## clicar numa delas a traz para esta cidade (cell_claimed; ver
## Game.transfer_cell).
## No modo de escolha, destaca as casas onde dá para construir e avisa o clique.

## [param keep_picking] = Shift apertado: o jogador quer pedir mais melhorias.
signal cell_picked(cell: Vector2i, keep_picking: bool)
signal pick_cancelled
## Clique numa casa vermelha (de outra cidade do jogador, no raio de ação).
signal cell_claimed(cell: Vector2i)

## Tamanho de cada casa na janela, em pixels.
const CELL_SIZE := 72
const HIGHLIGHT_COLOR := Color(0.4, 1.0, 0.4)
const BLOCKED_TINT := Color(0, 0, 0, 0.55)
## Casas fora do território da cidade.
const OUTSIDE_TINT := Color(0, 0, 0, 0.6)
## Casas de outra cidade do jogador que podem vir para esta (clique).
const TRANSFER_TINT := Color(1, 0.12, 0.1, 0.42)
const HOVER_COLOR := Color(1, 1, 1, 0.9)
## Espiga de milho (com o alimento por turno) no centro da fazenda trabalhada.
const CORN_SIZE := Vector2(38, 50)
const FOOD_FONT_SIZE := 20

## false = observando a cidade de outro jogador: sem casas vermelhas.
var allow_transfer := true
var _city: City
var _game: Game
## Casas destacadas no modo de escolha (vazio = fora do modo de escolha).
var _pick_cells: Array[Vector2i] = []
var _hover := Vector2i.MAX


## Terreno das 5x5 casas, desenhado pelo mesmo shader do mapa (transições
## suaves e bordas arredondadas), por baixo do resto (show_behind_parent).
var _terrain: ColorRect


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * CELL_SIZE * 5
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_terrain = ColorRect.new()
	_terrain.size = Vector2.ONE * CELL_SIZE * 5
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.show_behind_parent = true
	add_child(_terrain)


func setup(city: City, game: Game) -> void:
	_city = city
	_game = game
	_pick_cells = []
	_terrain.material = game.game_map.make_view_material(city.cell - Vector2i(2, 2), Vector2i(5, 5))
	queue_redraw()


## Entra no modo de escolha destacando [param cells]; vazio sai do modo.
func set_pick_cells(cells: Array[Vector2i]) -> void:
	_pick_cells = cells
	queue_redraw()


func is_picking() -> bool:
	return not _pick_cells.is_empty()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != _hover:
			_hover = cell
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and is_picking():
		if event.button_index == MOUSE_BUTTON_LEFT and _pick_cells.has(_cell_at(event.position)):
			cell_picked.emit(_cell_at(event.position), event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			pick_cancelled.emit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if _is_transferable(cell):
			cell_claimed.emit(cell)


## Casa vermelha: de outra cidade do jogador e no raio de ação desta.
func _is_transferable(cell: Vector2i) -> bool:
	return _city != null and allow_transfer and _view_cells().has(cell) and _game.transfer_error(_city, cell).is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i.MAX
		queue_redraw()


## Dica ao parar o mouse sobre uma casa.
func _get_tooltip(at_position: Vector2) -> String:
	var cell := _cell_at(at_position)
	if _city == null or not _view_cells().has(cell) or not _game.game_map.is_in_bounds(cell):
		return ""
	var map := _game.game_map
	var text := "(%d, %d) %s" % [cell.x, cell.y, Terrain.NAMES[map.get_terrain(cell)]]
	if map.get_terrain(cell) == Terrain.Type.FOREST:
		text += " (madeira %d/%d)" % [map.wood_left(cell), Terrain.WOOD_PER_FOREST]
	if _is_transferable(cell):
		var other := _game.territory_owner(cell)
		text += " - território de %s%s.\nClique para passar esta casa para %s: a melhoria vem junto e quem trabalhava nela fica livre em %s." % [
			other.city_name, _improvement_text(other, cell), _city.city_name, other.city_name]
	elif not _city.territory.has(cell):
		var owner_city := _game.territory_owner(cell)
		text += " - fora do território%s" % (" (território de %s)" % owner_city.city_name if owner_city else "")
		if _game.lumber_mill_at(cell):
			text += "; madeireira de %s" % _game.lumber_mill_at(cell).owner_player.display_name
	elif cell == _city.cell:
		text += " - %s (+%d alimento)" % [_city.city_name, City.CENTER_FOOD if _city.population > 0 else 0]
	elif _city.farms.has(cell):
		text += " - Fazenda %s" % ("trabalhada (+%d alimento)" % _city.farm_food(cell) if _city.farms[cell] > 0 else "sem trabalhador (renderia +%d)" % _city.farm_food(cell))
	elif _city.lumber_mills.has(cell):
		text += " - Madeireira, %d/%d trabalhadores (+%d madeira)" % [
			_city.lumber_mills[cell], LumberMill.MAX_WORKERS, _city.lumber_mills[cell] * LumberMill.WOOD_PER_WORKER]
	elif _city.ruins.has(cell):
		var ruin: Dictionary = _city.ruins[cell]
		text += " - %s destruída (pilhada); um Trabalhador reconstrói (%d/%d)" % [
			City.BUILDS[ruin["build"]]["name"], ruin["progress"], City.BUILDS[ruin["build"]]["cost"]]
	elif _city.construction_at(cell):
		var construction := _city.construction_at(cell)
		text += " - %s em obra (%d/%d)" % [construction.display_name(), construction.progress, construction.cost()]
	elif _game.claiming_city(cell):
		text += " - usada por %s" % _game.claiming_city(cell).city_name
	elif _game.lumber_mill_at(cell):
		text += " - madeireira de %s" % _game.lumber_mill_at(cell).owner_player.display_name
	return text


func _draw() -> void:
	if _city == null:
		return
	var map := _game.game_map
	var font := ThemeDB.fallback_font
	# Pontas do quadrado 5x5 (fora da área): escurecidas, como antes
	for corner in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		draw_rect(_cell_rect(_city.cell + corner), Color(0.06, 0.06, 0.08, 0.85))
	for cell in _view_cells():
		var rect := _cell_rect(cell)
		if not map.is_in_bounds(cell):
			draw_rect(rect, Color.BLACK)
			continue

		var construction := _city.construction_at(cell)
		if _city.farms.has(cell):
			City.draw_farm(self, rect)
			if _city.farms[cell] > 0:
				_draw_food(rect, _city.farm_food(cell) * _city.farms[cell])
				_draw_worker(rect, _city.farms[cell])
		elif _city.lumber_mills.has(cell):
			LumberMill.draw_icon(self, rect)
			LumberMill.draw_wood_bar(self, rect, map.wood_left(cell))
			if _city.lumber_mills[cell] > 0:
				_draw_worker(rect, _city.lumber_mills[cell])
		elif _city.ruins.has(cell):
			City.draw_ruin(self, _city.ruins[cell]["build"], rect)
		elif construction:
			City.draw_improvement(self, construction.build, rect, City.CONSTRUCTION_ALPHA)
			_draw_progress(rect, construction)
			if construction.workers > 0:
				_draw_worker(rect, construction.workers)
		elif _is_transferable(cell):
			# De outra cidade do jogador: mostra a melhoria dela sob o vermelho
			_draw_other_improvement(_game.territory_owner(cell), cell, rect)
			draw_rect(rect, TRANSFER_TINT)
		elif cell != _city.cell and (_game.claiming_city(cell) or _game.lumber_mill_at(cell)):
			draw_rect(rect, BLOCKED_TINT)
		if not _city.territory.has(cell) and not _is_transferable(cell):
			draw_rect(rect, OUTSIDE_TINT) # fora do território: a cidade não trabalha aqui

		if is_picking() and cell != _city.cell:
			if _pick_cells.has(cell):
				draw_rect(rect.grow(-2), HIGHLIGHT_COLOR, false, 3.0)
			else:
				draw_rect(rect, BLOCKED_TINT)

	_draw_border()
	# A cidade (desenho da classe) e a população no canto
	var center_rect := _cell_rect(_city.cell)
	City.draw_city_sprite(self, center_rect.grow(CELL_SIZE * 0.15), _city.owner_player.color, _city.rank())
	var badge_font := int(CELL_SIZE * 0.28)
	City.draw_population_badge(self, Vector2(center_rect.position.x + 2, center_rect.end.y - badge_font * 0.5),
			_city.population, _city.owner_player.color, badge_font)

	if _view_cells().has(_hover) and (not is_picking() or _pick_cells.has(_hover)):
		draw_rect(_cell_rect(_hover), HOVER_COLOR, false, 2.0 if not _is_transferable(_hover) else 3.0)

	if is_picking():
		var hint := "Escolha o terreno (Shift: vários)"
		draw_string_outline(font, Vector2(6, 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		draw_string(font, Vector2(6, 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, HIGHLIGHT_COLOR)


## Melhoria de outra cidade na casa (fazenda, madeireira, ruína ou obra), com
## os cidadãos dela, para o jogador ver o que ganha ao trazer a casa.
func _draw_other_improvement(other: City, cell: Vector2i, rect: Rect2) -> void:
	var construction := other.construction_at(cell)
	if other.farms.has(cell):
		City.draw_farm(self, rect)
		if other.farms[cell] > 0:
			_draw_worker(rect, other.farms[cell])
	elif other.lumber_mills.has(cell):
		LumberMill.draw_icon(self, rect)
		if other.lumber_mills[cell] > 0:
			_draw_worker(rect, other.lumber_mills[cell])
	elif other.ruins.has(cell):
		City.draw_ruin(self, other.ruins[cell]["build"], rect)
	elif construction:
		City.draw_improvement(self, construction.build, rect, City.CONSTRUCTION_ALPHA)


## " (fazenda com 1 cidadão)", " (ruína de madeireira)"... ou "".
func _improvement_text(other: City, cell: Vector2i) -> String:
	if other.farms.has(cell):
		return " (fazenda, %d %s)" % [other.farms[cell], "cidadão" if other.farms[cell] == 1 else "cidadãos"]
	if other.lumber_mills.has(cell):
		return " (madeireira, %d %s)" % [other.lumber_mills[cell], "cidadão" if other.lumber_mills[cell] == 1 else "cidadãos"]
	if other.ruins.has(cell):
		return " (%s destruída)" % String(City.BUILDS[other.ruins[cell]["build"]]["name"]).to_lower()
	if other.construction_at(cell):
		var construction := other.construction_at(cell)
		return " (%s em obra, %d/%d)" % [construction.display_name().to_lower(), construction.progress, construction.cost()]
	return ""


## Fronteira do território da cidade, na cor do dono (como no mapa).
func _draw_border() -> void:
	for cell in _city.territory:
		var border := TerritoryOverlay.SIDES.map(func(side: Array) -> bool: return not _city.territory.has(cell + side[0]))
		TerritoryOverlay.draw_border(self, _cell_rect(cell), border, _city.owner_player.color, 4.0)


## Casas mostradas na janela: a área de 21 casas em volta da cidade (o
## território inteiro da capital; nas outras, o que fica fora do território
## aparece escurecido).
func _view_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in City.area_offsets():
		cells.append(_city.cell + offset)
	return cells


## Barrinha de progresso na base da casa, com "progresso/custo" em cima.
func _draw_progress(rect: Rect2, construction: City.Construction) -> void:
	var ratio := float(construction.progress) / construction.cost()
	var bar := Rect2(rect.position.x + 4, rect.end.y - 12, rect.size.x - 8, 8)
	draw_rect(bar, Color.BLACK)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.3, 0.8, 1.0))
	var text := "%d/%d" % [construction.progress, construction.cost()]
	var font := ThemeDB.fallback_font
	var origin := Vector2(rect.position.x + 5, bar.position.y - 4)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Espiga de milho no centro da fazenda trabalhada, com o alimento que ela
## produz por turno no meio (fazenda sem trabalhador não mostra nada).
func _draw_food(rect: Rect2, food: int) -> void:
	var corn := Rect2(rect.get_center() - CORN_SIZE / 2.0, CORN_SIZE)
	Icons.draw_corn(self, corn)
	var font := ThemeDB.fallback_font
	var text := str(food)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FOOD_FONT_SIZE).x
	var baseline := (font.get_ascent(FOOD_FONT_SIZE) - font.get_descent(FOOD_FONT_SIZE)) / 2.0
	var origin := corn.get_center() + Vector2(-width / 2.0, baseline - corn.size.y * 0.04)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FOOD_FONT_SIZE, 5, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FOOD_FONT_SIZE, Color.WHITE)


## Bonequinho no canto da casa indicando cidadãos trabalhando nela.
func _draw_worker(rect: Rect2, count: int) -> void:
	var center := rect.position + Vector2(rect.size.x - 13, 13)
	draw_circle(center, 9, Color.BLACK)
	draw_circle(center, 7, Color.WHITE)
	var text := str(count)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, center + Vector2(-width / 2.0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)


func _cell_rect(cell: Vector2i) -> Rect2:
	var offset := cell - _city.cell + Vector2i(2, 2)
	return Rect2(Vector2(offset) * CELL_SIZE, Vector2.ONE * CELL_SIZE)


func _cell_at(local_position: Vector2) -> Vector2i:
	if _city == null:
		return Vector2i.MAX
	var offset := Vector2i((local_position / CELL_SIZE).floor())
	return _city.cell + offset - Vector2i(2, 2)
