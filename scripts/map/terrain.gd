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
##   Cerrado  o que sobra da floresta explorada. Igual à Pradaria.
##   Colinas  verdes; como a floresta, +1 de defesa para quem defende e 1
##            movimento a mais (unidades com mais de 1 de movimento); não
##            aceitam fazendas; aceitam cidades.
##   Montanhas rochosas e intransponíveis: nenhuma unidade entra; não dão
##            alimento nem aceitam melhorias.
## Um cidadão trabalhando a casa sem melhoria tira TILE_FOOD de alimento por
## turno (pradaria, floresta, cerrado e colinas: 1; água e montanhas: não dá
## para trabalhar). Casa
## que encosta num rio (Rivers, GameMap.has_river) tira RIVER_FOOD a mais.

## A ordem do enum é a ordem das imagens no atlas do mapa (ver GameMap).
enum Type { WATER, GRASSLAND, FOREST, CERRADO, HILLS, MOUNTAINS }

const NAMES := {
	Type.WATER: "Água",
	Type.GRASSLAND: "Pradaria",
	Type.FOREST: "Floresta",
	Type.CERRADO: "Cerrado",
	Type.HILLS: "Colinas",
	Type.MOUNTAINS: "Montanhas",
}

## Imagem de cada terreno: um quadrado de pelo menos TILE_SIZE pixels (as do
## Gemini têm 160x160), que o shader repete uma vez por casa (ver GameMap).
## Se o arquivo não existir, o terreno é desenhado com a cor de COLORS.
const TEXTURE_PATHS := {
	Type.WATER: "res://assets/tiles/agua.png",
	Type.GRASSLAND: "res://assets/tiles/pradaria.png",
	Type.FOREST: "res://assets/tiles/floresta.png",
	Type.CERRADO: "res://assets/tiles/cerrado.png",
	Type.HILLS: "res://assets/tiles/colinas.png",
	Type.MOUNTAINS: "res://assets/tiles/montanhas.png",
}

## Cor de cada terreno no PNG do mapa (data/maps/). As cores são as da paleta
## do Paint. Também é a cor de reserva, usada quando não há imagem para o terreno.
const COLORS := {
	Type.WATER: Color8(63, 72, 204),      # azul
	Type.GRASSLAND: Color8(181, 230, 29), # verde-claro
	Type.FOREST: Color8(34, 177, 76),     # verde-escuro
	Type.CERRADO: Color8(239, 228, 176),  # bege
	Type.HILLS: Color8(195, 195, 195),    # cinza-claro
	Type.MOUNTAINS: Color8(127, 127, 127), # cinza-escuro
}

## Defesa extra de quem defende neste terreno (soma com a fortificação).
const DEFENSE_BONUS := {
	Type.FOREST: 1,
	Type.HILLS: 1,
}

## Movimento extra para entrar neste terreno, só para unidades com mais de
## 1 de movimento (Cavalaria Leve: 4 casas na pradaria, 2 na floresta).
const MOVE_PENALTY := {
	Type.FOREST: 1,
	Type.HILLS: 1,
}

## Alimento por turno de um cidadão trabalhando a casa sem melhoria. A fazenda
## soma City.FARM_BONUS a isso. Terreno fora da lista não pode ser trabalhado.
const TILE_FOOD := {
	Type.GRASSLAND: 1,
	Type.FOREST: 1,
	Type.CERRADO: 1,
	Type.HILLS: 1,
}

## Alimento a mais da casa que encosta num rio (soma no alimento base da casa:
## sem melhoria 1 + 1 = 2; com fazenda 2 + 1 = 3; na casa da cidade, também).
const RIVER_FOOD := 1
## Atravessar um rio (GameMap.crosses_river): custa RIVER_MOVE_PENALTY a mais
## para unidades com mais de 1 de movimento (como a floresta; os dois somam), e
## quem é atacado do outro lado do rio ganha RIVER_DEFENSE_BONUS de defesa.
const RIVER_MOVE_PENALTY := 1
const RIVER_DEFENSE_BONUS := 1

## Madeira de cada casa de floresta. Quando acaba, a casa vira Cerrado.
const WOOD_PER_FOREST := 100


## Se unidades terrestres podem andar neste terreno.
static func is_walkable(type: Type) -> bool:
	return type != Type.WATER and type != Type.MOUNTAINS


## Se unidades navais (Galé) andam neste terreno.
static func is_navigable(type: Type) -> bool:
	return type == Type.WATER


## Águas profundas: a Galé afunda se terminar UnitType.deep_water_turn_limit
## turnos seguidos nelas. O terreno ainda não existe (toda a água é rasa); quando
## entrar no enum, basta responder true para ele aqui.
static func is_deep_water(_type: Type) -> bool:
	return false


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
