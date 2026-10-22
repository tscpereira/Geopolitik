class_name UnitType
extends Resource

## Definição de um tipo de unidade (ex.: Guerreiro).
## Cada tipo é um arquivo .tres em data/units/.

@export var display_name := ""
## Desenho da unidade (TILE_SIZE x TILE_SIZE, fundo transparente).
## Pixels magenta (#FF00FF) viram a cor do jogador.
@export var sprite: Texture2D
## Letra desenhada no lugar do sprite, se ele não estiver definido.
@export var symbol := ""
@export_range(0, 99) var attack := 1
@export_range(0, 99) var defense := 1
## Quantas casas a unidade anda por turno.
@export_range(0, 99) var movement := 1
## Energia com que a unidade começa; ao chegar a 0 ela é destruída.
@export_range(1, 999) var max_energy := 100
## Pode construir uma nova cidade (tecla B), sendo consumida no processo.
@export var can_found_city := false
## Pode construir madeireiras remotas na floresta e trabalhar nelas (tecla M).
@export var can_build_lumber_mill := false
## Pode reconstruir fazendas e madeireiras pilhadas (tecla R).
@export var can_rebuild := false
## Pode migrar para uma cidade (tecla J): vira 1 de população dela.
@export var can_join_city := false
