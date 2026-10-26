class_name MoveOverlay
extends Node2D

## Destaca a unidade selecionada, as casas para onde ela pode ir (branco)
## e os inimigos que ela pode atacar (vermelho; laranja para o ataque à
## distância do Arqueiro e da Catapulta). Também mostra o caminho da
## ordem "Mover" (pontos amarelos e bandeira no destino, com os turnos).
## Fica entre o mapa e as unidades na árvore de cena.

const REACHABLE_COLOR := Color(1, 1, 1, 0.35)
const ATTACK_COLOR := Color(1, 0.15, 0.15)
const RANGED_ATTACK_COLOR := Color(1, 0.55, 0.05)
const SELECTED_COLOR := Color.WHITE
const PATH_COLOR := Color(1, 0.9, 0.3)
## Espessura dos contornos, proporcional ao tamanho da casa.
const LINE_WIDTH := GameMap.TILE_SIZE / 12.0

@export var map: GameMap

var _cells: Array[Vector2i] = []
var _attack_cells: Array = []
var _ranged := false
var _selected_cell := Vector2i.ZERO
var _has_selection := false
## Caminho da ordem "Mover" (prévia ou destino da unidade selecionada).
var _path: Array[Vector2i] = []
var _path_turns := 0


## [param ranged]: os alvos são de ataque à distância (destaque laranja).
func show_moves(selected_cell: Vector2i, cells: Array[Vector2i], attack_cells: Array, ranged := false) -> void:
	_selected_cell = selected_cell
	_cells = cells
	_attack_cells = attack_cells
	_ranged = ranged
	_has_selection = true
	queue_redraw()


func clear() -> void:
	_cells = []
	_attack_cells = []
	_has_selection = false
	_path = []
	queue_redraw()


func _draw() -> void:
	for cell in _cells:
		draw_rect(_cell_rect(cell), REACHABLE_COLOR)
	var attack_color := RANGED_ATTACK_COLOR if _ranged else ATTACK_COLOR
	for cell in _attack_cells:
		draw_rect(_cell_rect(cell), Color(attack_color, 0.5))
		draw_rect(_cell_rect(cell).grow(LINE_WIDTH / 2.0), attack_color, false, LINE_WIDTH)
	if _has_selection:
		draw_rect(_cell_rect(_selected_cell).grow(LINE_WIDTH / 2.0), SELECTED_COLOR, false, LINE_WIDTH)
	if not _path.is_empty():
		_draw_path()


func _cell_rect(cell: Vector2i) -> Rect2:
	var size := Vector2.ONE * GameMap.TILE_SIZE
	return Rect2(to_local(map.cell_to_world(cell)) - size / 2.0, size)


## Mostra o caminho até o destino; [param turns] = turnos para chegar.
## Caminho vazio esconde.
func show_path(path: Array[Vector2i], turns: int) -> void:
	_path = path
	_path_turns = turns
	queue_redraw()


## Pontos pelo caminho e uma bandeira no destino com o número de turnos.
func _draw_path() -> void:
	var radius := GameMap.TILE_SIZE / 10.0
	for cell in _path.slice(0, -1):
		var center := _cell_rect(cell).get_center()
		draw_circle(center, radius + 1.0, Color.BLACK)
		draw_circle(center, radius, PATH_COLOR)
	var rect := _cell_rect(_path[-1])
	draw_rect(rect.grow(-LINE_WIDTH), PATH_COLOR, false, LINE_WIDTH)
	# Bandeira: mastro e pano
	var base := rect.position + Vector2(rect.size.x * 0.3, rect.size.y * 0.85)
	var top := base - Vector2(0, rect.size.y * 0.7)
	draw_line(base, top, Color.BLACK, LINE_WIDTH)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(rect.size.x * 0.45, rect.size.y * 0.15),
			top + Vector2(0, rect.size.y * 0.3)]), PATH_COLOR)
	var font := ThemeDB.fallback_font
	var font_size := int(GameMap.TILE_SIZE * 0.4)
	var text := "%dt" % _path_turns
	var origin := rect.position + Vector2(rect.size.x * 0.45, rect.size.y * 0.9)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
