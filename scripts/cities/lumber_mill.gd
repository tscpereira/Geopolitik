class_name LumberMill
extends Node2D

## Madeireira remota: construída por um Trabalhador numa casa de floresta,
## longe das cidades (tecla M). Os Trabalhadores alocados nela somem do mapa
## e trabalham lá dentro (no máximo MAX_WORKERS).
##
## A cada turno do dono (no início da vez dele):
##   - em obra: avança 1 ponto por trabalhador, até o custo da Madeireira
##     (o mesmo da madeireira da cidade, City.BUILDS[LUMBER_MILL]);
##   - pronta: cada trabalhador tira WOOD_PER_WORKER de madeira da floresta
##     para o estoque do jogador. Quando a madeira da casa acaba, a floresta
##     vira cerrado, a madeireira some e os trabalhadores saem (Game cuida disso).
##
## Também desenha as madeireiras da cidade (draw_icon, draw_wood_bar).

## Trabalhadores por madeireira (da cidade ou remota).
const MAX_WORKERS := 2
## Madeira tirada por trabalhador a cada turno.
const WOOD_PER_WORKER := 1

## Barra da madeira que resta na floresta.
const WOOD_BAR_COLOR := Color(0.3, 0.55, 1.0)
## Barra do progresso da obra (a mesma cor das obras na janela da cidade).
const PROGRESS_BAR_COLOR := Color(0.3, 0.8, 1.0)
const MARGIN := GameMap.TILE_SIZE / 16.0
const BADGE_FONT_SIZE := int(GameMap.TILE_SIZE * 0.3)
## Transparência da madeireira que ainda está em obra.
const CONSTRUCTION_ALPHA := 0.45

const LOG_COLOR := Color8(140, 90, 45)
const LOG_END_COLOR := Color8(220, 180, 120)

var owner_player: Player
var cell: Vector2i
## Pontos de obra já feitos; pronta quando chega a cost().
var progress := 0
## Trabalhadores (unidades) trabalhando aqui dentro.
var workers: Array[Unit] = []

var _map: GameMap


func setup(p_owner: Player, p_cell: Vector2i, map: GameMap) -> void:
	owner_player = p_owner
	cell = p_cell
	_map = map
	position = map.cell_to_world(p_cell)
	name = "Madeireira_%d_%d" % [p_cell.x, p_cell.y]


## Estado para o save. Os trabalhadores lá dentro são guardados pela posição
## deles em [param owner_units] (a lista de unidades do dono).
func to_dict(owner_units: Array[Unit]) -> Dictionary:
	return {"cell": SaveGame.cell_to_json(cell), "progress": progress,
			"workers": workers.map(func(worker: Unit) -> int: return owner_units.find(worker))}


static func cost() -> int:
	return City.BUILDS[City.Build.LUMBER_MILL]["cost"]


func is_done() -> bool:
	return progress >= cost()


func has_room() -> bool:
	return workers.size() < MAX_WORKERS


## Madeira que vai entrar no estoque no próximo turno.
func wood_per_turn() -> int:
	return mini(workers.size() * WOOD_PER_WORKER, _map.wood_left(cell)) if is_done() else 0


## Turnos até a obra terminar, ou -1 se não há trabalhadores.
func turns_to_finish() -> int:
	if workers.is_empty():
		return -1
	return ceili(float(cost() - progress) / workers.size())


## Avança a obra ou tira a madeira (ver regras no topo). Retorna a madeira obtida.
func process_turn() -> int:
	var wood := 0
	if not is_done():
		progress = mini(progress + workers.size(), cost())
	else:
		wood = _map.harvest_wood(cell, workers.size() * WOOD_PER_WORKER)
	queue_redraw()
	return wood


## A floresta acabou: a madeireira já não serve para nada.
func is_exhausted() -> bool:
	return is_done() and _map.wood_left(cell) <= 0


func _draw() -> void:
	var tile := Rect2(-Vector2.ONE * GameMap.TILE_SIZE / 2.0, Vector2.ONE * GameMap.TILE_SIZE)
	draw_icon(self, tile, 1.0 if is_done() else CONSTRUCTION_ALPHA)
	# Contorno na cor do dono: madeireira remota não tem cidade por perto
	draw_rect(tile.grow(-MARGIN), owner_player.color, false, MARGIN)
	if is_done():
		draw_wood_bar(self, tile, _map.wood_left(cell))
	else:
		draw_bar(self, tile, float(progress) / cost(), PROGRESS_BAR_COLOR)
	if not workers.is_empty():
		_draw_badge(tile, workers.size())


## Pilha de toras. [param alpha] menor = ainda em obra.
static func draw_icon(canvas: CanvasItem, rect: Rect2, alpha := 1.0) -> void:
	var log_height := rect.size.y * 0.16
	var log_width := rect.size.x * 0.34
	var center := rect.get_center() + Vector2(0, rect.size.y * 0.12)
	# Duas toras embaixo e uma em cima
	var logs := [
		center + Vector2(-log_width * 0.55, 0),
		center + Vector2(log_width * 0.55, 0),
		center + Vector2(0, -log_height),
	]
	for log_center: Vector2 in logs:
		var body := Rect2(log_center - Vector2(log_width, log_height) / 2.0, Vector2(log_width, log_height))
		canvas.draw_rect(body.grow(1.0), Color(Color.BLACK, alpha))
		canvas.draw_rect(body, Color(LOG_COLOR, alpha))
		canvas.draw_circle(Vector2(body.end.x, log_center.y), log_height / 2.0 + 1.0, Color(Color.BLACK, alpha))
		canvas.draw_circle(Vector2(body.end.x, log_center.y), log_height / 2.0, Color(LOG_END_COLOR, alpha))


## Barra azul no topo da casa: madeira que resta na floresta (de 30).
static func draw_wood_bar(canvas: CanvasItem, rect: Rect2, wood: int) -> void:
	draw_bar(canvas, rect, float(wood) / Terrain.WOOD_PER_FOREST, WOOD_BAR_COLOR)


## Barrinha no topo da casa, preenchida em [param ratio] (0 a 1).
static func draw_bar(canvas: CanvasItem, rect: Rect2, ratio: float, color: Color) -> void:
	var height := maxf(3.0, rect.size.y / 8.0)
	var margin := rect.size.x / 10.0
	var bar := Rect2(rect.position.x + margin, rect.position.y + margin, rect.size.x - margin * 2.0, height)
	canvas.draw_rect(bar.grow(1.0), Color.BLACK)
	canvas.draw_rect(bar, Color(0.25, 0.25, 0.25))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ratio, 0.0, 1.0), bar.size.y)), color)


## Número de trabalhadores num círculo branco, no canto inferior direito.
func _draw_badge(rect: Rect2, count: int) -> void:
	var radius := BADGE_FONT_SIZE * 0.6
	var center := rect.end - Vector2.ONE * (radius + MARGIN)
	draw_circle(center, radius + 1.0, Color.BLACK)
	draw_circle(center, radius, Color.WHITE)
	var font := ThemeDB.fallback_font
	var text := str(count)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE).x
	var baseline := (font.get_ascent(BADGE_FONT_SIZE) - font.get_descent(BADGE_FONT_SIZE)) / 2.0
	draw_string(font, center + Vector2(-width / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, Color.BLACK)
