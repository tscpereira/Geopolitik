class_name Terrain
extends RefCounted

## Tipos de terreno, como cada um é representado e as regras de cada um.
##
##   Água     unidades terrestres não entram.
##   Pradaria terreno comum: fazendas, cidades.
##   Floresta +1 de defesa para quem defende; custa 1 movimento a mais para
##            unidades com mais de 1 de movimento; não aceita fazendas. Cada
##            casa tem o seu estoque de madeira (WOOD_PER_FOREST, guardado no
##            GameMap); a madeireira só extrai dele. Esgotada, vira Cerrado.
##   Cerrado  o que sobra da floresta explorada. Igual à Pradaria, mas a
##            fazenda rende menos (FARM_FOOD: 2 em vez de 3).

## A ordem do enum é a ordem das imagens no atlas do mapa (ver GameMap).
enum Type { WATER, GRASSLAND, FOREST, CERRADO }

const NAMES := {
	Type.WATER: "Água",
	Type.GRASSLAND: "Pradaria",
	Type.FOREST: "Floresta",
	Type.CERRADO: "Cerrado",
}

## Imagem de cada terreno (TILE_SIZE x TILE_SIZE pixels, ver GameMap).
## Se o arquivo não existir, o terreno é desenhado com a cor de COLORS.
const TEXTURE_PATHS := {
	Type.WATER: "res://assets/tiles/agua.png",
	Type.GRASSLAND: "res://assets/tiles/pradaria.png",
	Type.FOREST: "res://assets/tiles/floresta.png",
	Type.CERRADO: "res://assets/tiles/cerrado.png",
}

## Cor de cada terreno no PNG do mapa (data/maps/). As cores são as da paleta
## do Paint. Também é a cor de reserva, usada quando não há imagem para o terreno.
const COLORS := {
	Type.WATER: Color8(63, 72, 204),      # azul
	Type.GRASSLAND: Color8(181, 230, 29), # verde-claro
	Type.FOREST: Color8(34, 177, 76),     # verde-escuro
	Type.CERRADO: Color8(239, 228, 176),  # bege
}

## Defesa extra de quem defende neste terreno (soma com a fortificação).
const DEFENSE_BONUS := {
	Type.FOREST: 1,
}

## Movimento extra para entrar neste terreno, só para unidades com mais de
## 1 de movimento (Cavaleiro: 2 casas na pradaria, 1 na floresta).
const MOVE_PENALTY := {
	Type.FOREST: 1,
}

## Alimento por turno de uma fazenda trabalhada, por terreno. O cerrado é
## menos fértil que a pradaria.
const FARM_FOOD := {
	Type.GRASSLAND: 3,
	Type.CERRADO: 2,
}

## Madeira de cada casa de floresta. Quando acaba, a casa vira Cerrado.
const WOOD_PER_FOREST := 100


## Se unidades terrestres podem andar neste terreno.
static func is_walkable(type: Type) -> bool:
	return type != Type.WATER


## Se dá para construir uma fazenda neste terreno.
static func can_farm(type: Type) -> bool:
	return type == Type.GRASSLAND or type == Type.CERRADO


## Movimentos gastos para entrar numa casa deste terreno.
static func move_cost(type: Type, unit_movement: int) -> int:
	return 1 + (MOVE_PENALTY.get(type, 0) if unit_movement > 1 else 0)


## Converte a cor de um pixel do mapa-fonte no terreno de cor mais parecida
## (ver COLORS).
static func from_color(color: Color) -> Type:
	var best := Type.WATER
	var best_distance := INF
	for type: Type in COLORS:
		var other: Color = COLORS[type]
		var distance := Vector3(color.r - other.r, color.g - other.g, color.b - other.b).length_squared()
		if distance < best_distance:
			best = type
			best_distance = distance
	return best
