class_name Player
extends RefCounted

## Um jogador, suas unidades, suas cidades, suas madeireiras remotas, o
## tesouro (ouro), o estoque de recursos estratégicos (por enquanto, só
## madeira) e o arsenal (armas).

## Ouro inicial de cada jogador. Valor de teste, até existir uma economia.
const START_GOLD := 200

var id: int
var display_name: String
var color: Color
## Controlado pela máquina (AIController) em vez de por cliques.
var is_ai := false
## Estilo de jogo da máquina (só vale com is_ai).
var personality := AIPersonality.balanced()
var units: Array[Unit] = []
var cities: Array[City] = []
## Madeireiras construídas por Trabalhadores longe das cidades.
var lumber_mills: Array[LumberMill] = []
## Estoque de madeira (recurso estratégico). Futuras obras vão consumi-lo.
var wood := 0
## Tesouro: ouro para comprar unidades e prédios na hora (ver Game.buy_build).
var gold := START_GOLD
## Arsenal: armas estocadas, {Arsenal.Weapon: quantidade}.
var arsenal := Arsenal.empty()


func _init(p_id: int, p_display_name: String, p_color: Color, p_is_ai := false) -> void:
	id = p_id
	display_name = p_display_name
	color = p_color
	is_ai = p_is_ai


## Madeira que vai entrar no estoque no início do próximo turno do jogador
## (madeireiras das cidades e remotas).
func wood_per_turn() -> int:
	var total := 0
	for city in cities:
		total += city.wood_per_turn()
	for mill in lumber_mills:
		total += mill.wood_per_turn()
	return total


## Ouro que entra no início do próximo turno (impostos das Marcenarias sem
## armas em produção; ver City.gold_per_turn).
func gold_per_turn() -> int:
	var total := 0
	for city in cities:
		total += city.gold_per_turn()
	return total


## Armas deste tipo em produção em todas as cidades (na fila dos prédios).
func weapons_in_production(weapon: Arsenal.Weapon) -> int:
	var total := 0
	for city in cities:
		for construction in city.constructions:
			if City.BUILDS[construction.build].get("weapon", -1) == weapon:
				total += 1
	return total


func start_turn() -> void:
	for unit in units:
		unit.reset_moves()
