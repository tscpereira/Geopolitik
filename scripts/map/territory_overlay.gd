class_name TerritoryOverlay
extends Node2D

## Desenha os territórios das cidades no mapa: a fronteira (borda) na cor do
## dono onde o território encontra o de outro jogador ou terra sem dono. Entre
## duas cidades do mesmo jogador, só uma linha fina. O terreno de dentro não é
## pintado (o véu na cor do dono saiu em 24/10/2026, a pedido do usuário).
## Os cantos convexos da fronteira são arredondados (CORNER_RADIUS_RATIO).
## Fica entre o mapa e as cidades na árvore de cena; o Game chama
## set_territories sempre que um território muda.

## Espessura da fronteira, proporcional ao tamanho da casa.
const BORDER_WIDTH := GameMap.TILE_SIZE / 13.0
## Linha entre duas cidades do mesmo jogador.
const INNER_ALPHA := 0.35
const INNER_WIDTH := 1.5

## Lados da casa: direção do vizinho e os dois cantos do lado (0 a 1).
const SIDES := [
	[Vector2i(0, -1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2i(1, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2i(0, 1), Vector2(0, 1), Vector2(1, 1)],
	[Vector2i(-1, 0), Vector2(0, 0), Vector2(0, 1)],
]
## Para cada lado de SIDES: o outro lado que encontra o canto "de" e o canto "até".
const CORNER_SIDES := [[3, 1], [0, 2], [3, 1], [0, 2]]
## Cantos da casa: posição (0 a 1), os dois lados que se encontram nele (índices
## em SIDES) e a direção para dentro da casa.
const CORNERS := [
	[Vector2(0, 0), 0, 3, Vector2(1, 1)],
	[Vector2(1, 0), 0, 1, Vector2(-1, 1)],
	[Vector2(1, 1), 2, 1, Vector2(-1, -1)],
	[Vector2(0, 1), 2, 3, Vector2(1, -1)],
]
## Raio dos cantos arredondados da fronteira, em fração do tamanho da casa.
const CORNER_RADIUS_RATIO := 0.18

@export var map: GameMap

## {casa: City} (ver Game.territory_owner).
var _owners := {}


func set_territories(owners: Dictionary) -> void:
	_owners = owners
	queue_redraw()


func _draw() -> void:
	var size := Vector2.ONE * GameMap.TILE_SIZE
	for cell: Vector2i in _owners:
		var city: City = _owners[cell]
		var color := city.owner_player.color
		var rect := Rect2(to_local(map.cell_to_world(cell)) - size / 2.0, size)
		var border := []
		for side: Array in SIDES:
			var neighbor: City = _owners.get(cell + side[0])
			border.append(neighbor != city and not (neighbor and neighbor.owner_player == city.owner_player))
			if neighbor and neighbor != city and neighbor.owner_player == city.owner_player:
				draw_line(rect.position + side[1] * size, rect.position + side[2] * size, Color(color, INNER_ALPHA), INNER_WIDTH, true)
		draw_border(self, rect, border, color, BORDER_WIDTH)


## Fronteira de uma casa ([param rect]) nos lados marcados em [param border]
## (um bool por lado de SIDES): um pouco para dentro da casa (as cores de dois
## vizinhos não se sobrepõem), com contorno escuro, pontas redondas e os cantos
## convexos arredondados. Também usada pela janela da cidade.
static func draw_border(canvas: CanvasItem, rect: Rect2, border: Array, color: Color, width: float) -> void:
	var radius := rect.size.x * CORNER_RADIUS_RATIO
	for pass_index in 2:
		var line_color := Color.BLACK.lerp(color, 0.25) if pass_index == 0 else color
		var line_width := width + 2.0 if pass_index == 0 else width
		for i in SIDES.size():
			if not border[i]:
				continue
			var side: Array = SIDES[i]
			var from: Vector2 = rect.position + side[1] * rect.size
			var to: Vector2 = rect.position + side[2] * rect.size
			var along := (to - from).normalized()
			var inward := (rect.get_center() - (from + to) / 2.0).normalized() * width / 2.0
			# O outro lado do canto também é fronteira: canto convexo (arco)
			if border[CORNER_SIDES[i][0]]:
				from += along * (radius + width / 2.0)
			if border[CORNER_SIDES[i][1]]:
				to -= along * (radius + width / 2.0)
			canvas.draw_line(from + inward, to + inward, line_color, line_width, true)
			canvas.draw_circle(from + inward, line_width / 2.0, line_color, true, -1.0, true)
			canvas.draw_circle(to + inward, line_width / 2.0, line_color, true, -1.0, true)
		for corner: Array in CORNERS:
			if not (border[corner[1]] and border[corner[2]]):
				continue
			var inside: Vector2 = corner[3]
			var center: Vector2 = rect.position + corner[0] * rect.size + inside * (width / 2.0 + radius)
			var start := atan2(0.0, -inside.x)
			var finish := atan2(-inside.y, 0.0)
			if finish - start > PI:
				finish -= TAU
			elif finish - start < -PI:
				finish += TAU
			canvas.draw_arc(center, radius, start, finish, 12, line_color, line_width, true)
