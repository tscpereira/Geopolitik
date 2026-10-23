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
## Tecnologias já pesquisadas (Technology.Tech), na ordem em que ficaram prontas.
var researched: Array[int] = []
## Pesquisa em andamento (Technology.Tech), ou -1 se nenhuma foi escolhida.
var research := -1
## Pontos de ciência já gastos em cada tecnologia: {Technology.Tech: pontos}.
## Trocar de pesquisa não perde o que já foi feito.
var research_progress := {}


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


## Ciência produzida por turno em todas as cidades (City.science_per_turn).
func science_per_turn() -> int:
	var total := 0
	for city in cities:
		total += city.science_per_turn()
	return total


## Gasta os pontos de ciência do turno na pesquisa escolhida. Retorna a
## tecnologia que ficou pronta, ou -1. Sem pesquisa, os pontos se perdem; a
## sobra de uma pesquisa concluída também (não se acumulam).
func advance_research() -> int:
	if research < 0:
		return -1
	var tech := research
	research_progress[tech] = research_progress.get(tech, 0) + science_per_turn()
	if research_progress[tech] < Technology.cost(tech):
		return -1
	research_progress.erase(tech)
	researched.append(tech)
	research = -1
	return tech


## Turnos até terminar a pesquisa atual, ou -1 (sem pesquisa ou sem ciência).
func research_turns() -> int:
	var per_turn := science_per_turn()
	if research < 0 or per_turn <= 0:
		return -1
	return ceili(float(Technology.cost(research) - research_progress.get(research, 0)) / per_turn)


## Armas deste tipo em produção em todas as cidades (na fila dos prédios).
func weapons_in_production(weapon: Arsenal.Weapon) -> int:
	var total := 0
	for city in cities:
		for construction in city.constructions:
			if City.BUILDS[construction.build].get("weapon", -1) == weapon:
				total += 1
	return total


## Jogador inteiro para o save, com as unidades, cidades e madeireiras remotas.
## Os trabalhadores das madeireiras são guardados pela posição na lista de
## unidades.
func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "color": color.to_html(), "is_ai": is_ai,
		"personality": personality.to_dict(), "wood": wood, "gold": gold,
		"arsenal": SaveGame.int_map_to_json(arsenal),
		"researched": researched.duplicate(), "research": research,
		"research_progress": SaveGame.int_map_to_json(research_progress),
		"units": units.map(func(unit: Unit) -> Dictionary: return unit.to_dict()),
		"cities": cities.map(func(city: City) -> Dictionary: return city.to_dict()),
		"lumber_mills": lumber_mills.map(func(mill: LumberMill) -> Dictionary: return mill.to_dict(units)),
	}


## Jogador de um save, sem as unidades, cidades e madeireiras (que são nós da
## cena; o Game cria cada uma, ver Game.restore_state).
static func from_dict(data: Dictionary) -> Player:
	var player := Player.new(int(data["id"]), data["name"], Color.html(data["color"]), data["is_ai"])
	player.personality = AIPersonality.from_dict(data["personality"])
	player.wood = int(data["wood"])
	player.gold = int(data["gold"])
	player.arsenal.merge(SaveGame.json_to_int_map(data["arsenal"]), true)
	for tech in data.get("researched", []):
		player.researched.append(int(tech))
	player.research = int(data.get("research", -1))
	player.research_progress = SaveGame.json_to_int_map(data.get("research_progress", []))
	return player


func start_turn() -> void:
	for unit in units:
		unit.reset_moves()
