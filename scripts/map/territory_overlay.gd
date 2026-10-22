class_name TerritoryOverlay
extends Node2D

## Desenha os territórios das cidades no mapa: um véu leve na cor do dono e a
## fronteira (borda) na cor dele onde o território encontra o de outro jogador
## ou terra sem dono. Entre duas cidades do mesmo jogador, só uma linha fina.
## Fica entre o mapa e as cidades na árvore de cena; o Game chama
## set_territories sempre que um território muda.

## Transparência do véu sobre as casas do território.
const FILL_ALPHA := 0.1
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
		draw_rect(rect, Color(color, FILL_ALPHA))
		for side: Array in SIDES:
			var neighbor: City = _owners.get(cell + side[0])
			if neighbor == city:
				continue
			var from: Vector2 = rect.position + side[1] * size
			var to: Vector2 = rect.position + side[2] * size
			if neighbor and neighbor.owner_player == city.owner_player:
				draw_line(from, to, Color(color, INNER_ALPHA), INNER_WIDTH)
				continue
			# Fronteira: um pouco para dentro da casa, para as cores de dois
			# vizinhos não se sobreporem
			var inward := (rect.get_center() - (from + to) / 2.0).normalized() * BORDER_WIDTH / 2.0
			draw_line(from + inward, to + inward, Color.BLACK.lerp(color, 0.25), BORDER_WIDTH + 2.0)
			draw_line(from + inward, to + inward, color, BORDER_WIDTH)
