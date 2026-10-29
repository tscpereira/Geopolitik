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
## Pilhada por um inimigo (Game.pillage): os Trabalhadores lá dentro são
## executados, a obra volta a 0 e ela aparece destruída. A floresta não ganha
## de volta a madeira já tirada. Um Trabalhador do dono reconstrói entrando
## nela (tecla R): é a mesma obra de uma madeireira nova.
##
## MINA REMOTA (is_mine; desde 25/10/2026): a mesma coisa numa colina com ferro
## fora dos territórios (tecla M). Pronta, cada trabalhador tira
## City.IRON_PER_WORKER de ferro por turno, e ela não se esgota (sem barra).
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

## Desenho da madeireira (ver draw_icon).
const TEXTURE: Texture2D = preload("res://assets/sprites/improvements/madeireira.png")

var owner_player: Player
var cell: Vector2i
## Pontos de obra já feitos; pronta quando chega a cost().
var progress := 0
## Trabalhadores (unidades) trabalhando aqui dentro.
var workers: Array[Unit] = []
## Destruída por um inimigo: não produz até ser reconstruída (a obra, de 0
## até cost(), é a reconstrução).
var pillaged := false
## Mina de ferro (numa colina com ferro) em vez de madeireira.
var is_mine := false

var _map: GameMap


func setup(p_owner: Player, p_cell: Vector2i, map: GameMap, p_is_mine := false) -> void:
	owner_player = p_owner
	cell = p_cell
	_map = map
	is_mine = p_is_mine
	position = map.cell_to_world(p_cell)
	name = "%s_%d_%d" % ["Mina" if is_mine else "Madeireira", p_cell.x, p_cell.y]


## "Madeireira" ou "Mina".
func display_name() -> String:
	return "Mina" if is_mine else "Madeireira"


## A melhoria da cidade equivalente (para o desenho de ruína e as mensagens).
func build() -> int:
	return City.Build.MINE if is_mine else City.Build.LUMBER_MILL


## Estado para o save. Os trabalhadores lá dentro são guardados pela posição
## deles em [param owner_units] (a lista de unidades do dono).
func to_dict(owner_units: Array[Unit]) -> Dictionary:
	return {"cell": SaveGame.cell_to_json(cell), "progress": progress, "pillaged": pillaged, "mine": is_mine,
			"workers": workers.map(func(worker: Unit) -> int: return owner_units.find(worker))}


## Destruída por um inimigo: a obra volta a 0 (os Trabalhadores de dentro são
## tirados pelo Game, que os executa).
func pillage() -> void:
	pillaged = true
	progress = 0
	queue_redraw()


static func cost() -> int:
	return City.BUILDS[City.Build.LUMBER_MILL]["cost"]


func is_done() -> bool:
	return progress >= cost()


func has_room() -> bool:
	return workers.size() < MAX_WORKERS


## Madeira que vai entrar no estoque no próximo turno (mina: 0).
func wood_per_turn() -> int:
	if is_mine or not is_done():
		return 0
	return mini(workers.size() * WOOD_PER_WORKER, _map.wood_left(cell))


## Ferro que vai entrar no estoque no próximo turno (madeireira: 0).
func iron_per_turn() -> int:
	return workers.size() * City.IRON_PER_WORKER if is_mine and is_done() else 0


## Turnos até a obra terminar, ou -1 se não há trabalhadores.
func turns_to_finish() -> int:
	if workers.is_empty():
		return -1
	return ceili(float(cost() - progress) / workers.size())


## Avança a obra ou tira a madeira ou o ferro (ver regras no topo). Retorna
## quanto foi tirado (madeira na madeireira, ferro na mina).
func process_turn() -> int:
	var taken := 0
	if not is_done():
		progress = mini(progress + workers.size(), cost())
		if is_done():
			pillaged = false # reconstruída
	elif is_mine:
		taken = iron_per_turn()
	else:
		taken = _map.harvest_wood(cell, workers.size() * WOOD_PER_WORKER)
	queue_redraw()
	return taken


## A floresta acabou: a madeireira já não serve para nada (a mina nunca acaba).
func is_exhausted() -> bool:
	return not is_mine and is_done() and _map.wood_left(cell) <= 0


func _draw() -> void:
	var tile := Rect2(-Vector2.ONE * GameMap.TILE_SIZE / 2.0, Vector2.ONE * GameMap.TILE_SIZE)
	if pillaged:
		City.draw_ruin(self, build(), tile)
	elif is_mine:
		City.draw_mine(self, tile, 1.0 if is_done() else CONSTRUCTION_ALPHA)
	else:
		draw_icon(self, tile, 1.0 if is_done() else CONSTRUCTION_ALPHA)
	if is_mine and _map.iron_visible:
		Icons.draw_iron_marker(self, tile)
	# Contorno na cor do dono: madeireira remota não tem cidade por perto
	draw_rect(tile.grow(-MARGIN), owner_player.color, false, MARGIN)
	if is_done():
		if not is_mine: # a mina não se esgota: sem barra
			draw_wood_bar(self, tile, _map.wood_left(cell), _map.wood_total(cell))
	elif not pillaged or progress > 0:
		draw_bar(self, tile, float(progress) / cost(), PROGRESS_BAR_COLOR)
	if not workers.is_empty():
		_draw_badge(tile, workers.size())


## Madeireira: telheiro de tábuas, pilhas de toras, cavalete e tocos (o PNG de
## TEXTURE, 80x80, gerado por tools/art/gen_art.gd). [param alpha] menor =
## ainda em obra. Também é o ícone da madeira no HUD e nas janelas.
static func draw_icon(canvas: CanvasItem, rect: Rect2, alpha := 1.0) -> void:
	canvas.draw_texture_rect(TEXTURE, rect, false, Color(1, 1, 1, alpha))


## Barra azul no topo da casa: madeira que resta na mata ([param wood] de
## [param total]: GameMap.wood_total).
static func draw_wood_bar(canvas: CanvasItem, rect: Rect2, wood: int, total: int) -> void:
	draw_bar(canvas, rect, float(wood) / maxi(total, 1), WOOD_BAR_COLOR)


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
