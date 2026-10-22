class_name City
extends Node2D

## Cidade no mapa: população, estoque de alimentos, fazendas, madeireiras e
## obras em andamento. Também desenha a cidade e as melhorias dela no mapa.
##
## A cada turno do dono (no início da vez dele):
##   0. prédios com "idle_gold" (Marcenaria) sem nada na fila rendem ouro:
##      +1 por trabalhador (impostos);
##   1. obras avançam 1 ponto de produção por cidadão trabalhando nelas; em
##      cada prédio, a unidade ou arma da frente da fila avança com os
##      trabalhadores do prédio (building_workers). Arma pronta vai para o
##      arsenal do jogador;
##   2. cada cidadão numa madeireira tira 1 de madeira da floresta para o
##      estoque do jogador. Floresta esgotada vira cerrado e a madeireira some;
##   3. alimento = CENTER_FOOD + alimento de cada fazenda trabalhada (3 na
##                 pradaria, 2 no cerrado: farm_food)
##                 − FOOD_PER_CITIZEN (2) por habitante;
##   4. a sobra vai para o estoque (como no Civilization II). Quando o
##      estoque enche, a cidade ganha 1 de população e o estoque esvazia.
##      Tamanho do estoque = (população atual + 1) × FOOD_BOX_PER_SIZE (10).
##      Com o estoque negativo, passa fome e perde 1 (mínimo 1);
##   5. quem ficou livre neste turno (obra pronta, cidadão novo, madeireira
##      esgotada) vai para a próxima obra da fila ou, sem obras, para uma
##      fazenda sem trabalhador e depois para uma madeireira com vaga.
##
## TERRITÓRIO: as casas da cidade, marcadas no mapa com a borda na cor do dono
## (TerritoryOverlay). A primeira cidade do jogador é a capital e começa com a
## área de 21 casas (area_offsets); as outras começam com as 8 vizinhas
## (territory_offsets). Casa que já é território de outra cidade (ou tem a
## madeireira remota de outro jogador) fica com quem chegou primeiro. A área de
## trabalho (fazendas, madeireiras) é o território. Por enquanto ele não cresce.
##
## CLASSE: só uma classificação pelo tamanho (rank): Povoado (1-5 de população),
## Vila (6-15), Cidade (16-30) e Metrópole (31+). Ser a capital é à parte.
##
## PILHAGEM (Game.pillage): uma unidade militar inimiga destrói uma fazenda ou
## madeireira pronta da cidade. A melhoria vira ruína (ruins) e não produz; os
## cidadãos que trabalhavam nela são executados e saem da população, que pode
## chegar a 0. Cidade vazia não produz nem come nem cresce: precisa que um
## Trabalhador migre para ela (Game.join_city). Um Trabalhador do dono
## reconstrói a ruína em cost() turnos (add_rebuild_progress).
##
## Cada cidadão trabalha em uma coisa só: numa obra (gera produção), numa
## fazenda (gera alimento) ou numa madeireira (gera madeira). Quem o jogador
## deixar livre (botão "-") continua livre e não produz nada.
##
## Obras podem ser melhorias numa casa (Fazenda, Madeireira), unidades
## (Guerreiro, Colono, Trabalhador), armas (Lança) ou prédios (Quartel
## General, Marcenaria).
## Unidade pronta sai na cidade e consome população (BUILDS[...]["population"]);
## se a cidade não tiver população para isso, a unidade fica esperando.
## Cada unidade ou arma é produzida num prédio da cidade ("requires"): Colono
## e Trabalhador na Prefeitura (que toda cidade já tem), unidades militares no
## Quartel General, armas na Marcenaria. Os trabalhadores ficam no prédio e
## passam de um item da fila para o próximo. Prédios são únicos por cidade.

signal changed

enum Build { FARM, LUMBER_MILL, WARRIOR, WORKER, SETTLER, CITY_HALL, HEADQUARTERS, CARPENTRY, SPEAR }

## Classe da cidade, pelo tamanho (ver rank).
enum Rank { SETTLEMENT, TOWN, CITY, METROPOLIS }

const RANK_NAMES := {
	Rank.SETTLEMENT: "Povoado",
	Rank.TOWN: "Vila",
	Rank.CITY: "Cidade",
	Rank.METROPOLIS: "Metrópole",
}

## População mínima de cada classe (o Povoado vai de 0 a 5).
const RANK_MIN_POPULATION := {
	Rank.SETTLEMENT: 0,
	Rank.TOWN: 6,
	Rank.CITY: 16,
	Rank.METROPOLIS: 31,
}

## Classes da lista "Construir", na ordem em que aparecem.
enum Category { UNIT, WEAPON, TERRAIN_IMPROVEMENT, BUILDING }

const CATEGORY_NAMES := {
	Category.UNIT: "Unidades",
	Category.WEAPON: "Armas",
	Category.TERRAIN_IMPROVEMENT: "Melhorias de terreno",
	Category.BUILDING: "Prédios",
}

## O que a cidade pode construir:
##   name        nome mostrado
##   article     "a" ou "o" (para "a construção da Fazenda", "do Guerreiro")
##   category    classe na lista "Construir" (Category)
##   cost        pontos de produção necessários
##   gold        preço em ouro para concluir na hora (ver Game.buy_error)
##   wood        madeira gasta ao pedir a obra ou ao comprar (Player.wood); volta
##               para o estoque se a obra for cancelada
##   on_tile     true = é feita numa casa da área da cidade (melhoria)
##   unit        tipo de unidade criada ao terminar (só para unidades)
##   population  população consumida quando a unidade fica pronta
##   weapons     armas do arsenal gastas ao pedir ou comprar a unidade
##               ({Arsenal.Weapon: quantidade}); voltam se a obra for cancelada
##   weapon      arma que vai para o arsenal ao ficar pronta (só para armas)
##   idle_gold   ouro por turno de cada trabalhador do prédio quando não há nada
##               em produção nele (impostos; ver gold_per_turn)
##   requires    prédio que produz a unidade ou a arma (a cidade precisa tê-lo)
##   native      prédio que toda cidade já tem ao nascer (não aparece na lista)
##   description texto explicativo (tooltip da lista de construções)
## Em que terreno cada melhoria pode ser feita: ver allows_terrain.
## Prédios são únicos: cada cidade tem no máximo um de cada (ver build_error).
const BUILDS := {
	Build.FARM: {
		"name": "Fazenda", "article": "a", "category": Category.TERRAIN_IMPROVEMENT,
		"cost": 4, "gold": 50, "on_tile": true,
		"description": "Melhoria em pradaria ou cerrado. Com 1 cidadão, produz +3 de alimento por turno na pradaria e +2 no cerrado.",
	},
	Build.LUMBER_MILL: {
		"name": "Madeireira", "article": "a", "category": Category.TERRAIN_IMPROVEMENT,
		"cost": 4, "gold": 50, "on_tile": true,
		"description": "Melhoria em floresta. Até 2 cidadãos, cada um tira 1 de madeira por turno. A floresta tem 30 de madeira e depois vira cerrado.",
	},
	Build.WARRIOR: {
		"name": "Guerreiro", "article": "o", "category": Category.UNIT,
		"cost": 10, "gold": 50, "weapons": {Arsenal.Weapon.SPEAR: 1}, "on_tile": false,
		"unit": preload("res://data/units/guerreiro.tres"), "population": 1,
		"requires": Build.HEADQUARTERS,
		"description": "Unidade militar (Ataque 1, Defesa 1, Movimento 1). Feita no Quartel General; leva 1 Lança do arsenal.",
	},
	Build.SETTLER: {
		"name": "Colono", "article": "o", "category": Category.UNIT,
		"cost": 10, "gold": 50, "on_tile": false,
		"unit": preload("res://data/units/colono.tres"), "population": 1,
		"requires": Build.CITY_HALL,
		"description": "Sem ataque nem defesa (Movimento 1). Funda uma nova cidade (tecla B). Feito na Prefeitura.",
	},
	Build.WORKER: {
		"name": "Trabalhador", "article": "o", "category": Category.UNIT,
		"cost": 5, "gold": 50, "on_tile": false,
		"unit": preload("res://data/units/trabalhador.tres"), "population": 1,
		"requires": Build.CITY_HALL,
		"description": "Sem ataque nem defesa (Movimento 1). Constrói madeireiras na floresta e trabalha nelas. Feito na Prefeitura.",
	},
	Build.CITY_HALL: {
		"name": "Prefeitura", "article": "a", "category": Category.BUILDING,
		"cost": 0, "gold": 0, "on_tile": false, "native": true,
		"description": "Toda cidade já nasce com ela. Permite fazer Colonos e Trabalhadores.",
	},
	Build.HEADQUARTERS: {
		"name": "Quartel General", "article": "o", "category": Category.BUILDING,
		"cost": 15, "gold": 50, "wood": 15, "on_tile": false,
		"description": "Prédio militar: permite fazer unidades militares (hoje, o Guerreiro). Gasta 15 de madeira.",
	},
	Build.CARPENTRY: {
		"name": "Marcenaria", "article": "a", "category": Category.BUILDING,
		"cost": 10, "gold": 50, "wood": 10, "on_tile": false, "idle_gold": 1,
		"description": "Produz armas (Lanças). Sem armas na fila, cada trabalhador rende +1 de ouro por turno. Gasta 10 de madeira.",
	},
	Build.SPEAR: {
		"name": "Lança", "article": "a", "category": Category.WEAPON,
		"cost": 5, "gold": 50, "wood": 2, "on_tile": false,
		"weapon": Arsenal.Weapon.SPEAR, "requires": Build.CARPENTRY,
		"description": "Arma do arsenal: cada Guerreiro leva 1. Feita na Marcenaria; gasta 2 de madeira.",
	},
}

## Alimento de uma fazenda trabalhada na pradaria (no cerrado rende menos:
## ver Terrain.FARM_FOOD e farm_food).
const FARM_FOOD := 3
## Alimento que a casa da cidade produz sozinha (sem isso, uma cidade nova
## passaria fome antes de terminar a primeira fazenda).
const CENTER_FOOD := 2
## Alimento que cada habitante come por turno (Civilization II).
const FOOD_PER_CITIZEN := 2
## Tamanho do estoque = (população + 1) × FOOD_BOX_PER_SIZE (ver food_capacity).
const FOOD_BOX_PER_SIZE := 10
## Distância mínima (em casas, contando diagonais) entre duas cidades.
const MIN_DISTANCE := 3

## Nomes dados às novas cidades, na ordem.
const NAMES: Array[String] = [
	"Aurora", "Porto Alto", "Vila Rica", "Boa Vista", "Monte Claro",
	"Santa Luz", "Rio Fundo", "Pedra Branca", "Campo Belo", "Serra Azul",
	"Lagoa Seca", "Bom Retiro", "Vale Verde", "Três Pontas", "Nova Esperança",
]

## Medidas do desenho no mapa, proporcionais ao tamanho da casa.
const FONT_SIZE := int(GameMap.TILE_SIZE * 0.55)
const NAME_FONT_SIZE := int(GameMap.TILE_SIZE * 0.35)
const MARGIN := GameMap.TILE_SIZE / 16.0
## Transparência das fazendas que ainda estão em obra.
const CONSTRUCTION_ALPHA := 0.35

## Barra do estoque de alimentos (no mapa, acima da cidade, e na janela).
const FOOD_BAR_COLOR := Color(0.45, 0.85, 0.3)
const FOOD_BAR_STARVING_COLOR := Color(1, 0.35, 0.3)
const FOOD_BAR_HEIGHT := GameMap.TILE_SIZE / 8.0

## Aviso de trabalhadores ociosos (acima da cidade): "!" azul + quantidade.
const IDLE_COLOR := Color(0.25, 0.55, 1.0)
const IDLE_ICON_RADIUS := GameMap.TILE_SIZE * 0.22
const IDLE_FONT_SIZE := int(GameMap.TILE_SIZE * 0.4)

## Desenho das melhorias destruídas (pilhadas), no mapa e na janela da cidade.
## PNGs de 40x40 em assets/sprites/improvements/ (dá para redesenhar).
const RUIN_TEXTURES := {
	Build.FARM: preload("res://assets/sprites/improvements/fazenda_destruida.png"),
	Build.LUMBER_MILL: preload("res://assets/sprites/improvements/madeireira_destruida.png"),
}

const FARM_COLOR := Color8(205, 170, 80)
const FARM_FURROW_COLOR := Color8(130, 90, 35)
const FARM_SOIL_COLOR := Color8(150, 105, 58)


## Uma obra da cidade: melhoria numa casa (com [member cell]) ou unidade.
class Construction:
	var build: int
	## Casa da melhoria; não usada para unidades.
	var cell: Vector2i
	var progress := 0
	var workers := 0
	## Unidade pronta já avisou que está esperando população (avisa uma vez só).
	var waiting_reported := false
	## Madeira e armas pagas ao pedir a obra; voltam se ela for cancelada.
	var wood_paid := 0
	var weapons_paid := {}

	func cost() -> int:
		return City.BUILDS[build]["cost"]

	func display_name() -> String:
		return City.BUILDS[build]["name"]

	func is_on_tile() -> bool:
		return City.BUILDS[build]["on_tile"]

	func is_building() -> bool:
		return City.BUILDS[build]["category"] == City.Category.BUILDING

	func is_unit() -> bool:
		return City.BUILDS[build].has("unit")

	func is_weapon() -> bool:
		return City.BUILDS[build].has("weapon")

	## Unidades e armas são produzidas num prédio, numa fila, pelos
	## trabalhadores do prédio (City.building_workers).
	func is_produced() -> bool:
		return City.BUILDS[build].has("requires")

	## Prédio onde a unidade ou arma é produzida (ex.: Quartel General), ou -1.
	func producer() -> int:
		return City.BUILDS[build].get("requires", -1)

	func population_cost() -> int:
		return City.BUILDS[build].get("population", 0)

	func is_done() -> bool:
		return progress >= cost()

	func to_dict() -> Dictionary:
		return {"build": build, "cell": SaveGame.cell_to_json(cell), "progress": progress, "workers": workers,
				"waiting_reported": waiting_reported, "wood_paid": wood_paid,
				"weapons_paid": SaveGame.int_map_to_json(weapons_paid)}

	static func from_dict(data: Dictionary) -> Construction:
		var construction := Construction.new()
		construction.build = int(data["build"])
		construction.cell = SaveGame.json_to_cell(data["cell"])
		construction.progress = int(data["progress"])
		construction.workers = int(data["workers"])
		construction.waiting_reported = data["waiting_reported"]
		construction.wood_paid = int(data["wood_paid"])
		construction.weapons_paid = SaveGame.json_to_int_map(data["weapons_paid"])
		return construction


var city_name := ""
var owner_player: Player
var cell: Vector2i
## Primeira cidade do jogador: começa com um território maior.
var is_capital := false
## Casas do território (inclui a casa da cidade). É também a área de trabalho.
## Definido ao fundar (Game.found_city); por enquanto não cresce.
var territory: Array[Vector2i] = []
var population := 1
var food_stock := 0
## Fazendas prontas: {casa: cidadãos trabalhando (0 ou 1)}.
var farms := {}
## Madeireiras prontas: {casa: cidadãos trabalhando (0 a LumberMill.MAX_WORKERS)}.
var lumber_mills := {}
## Melhorias pilhadas: {casa: {"build": Build.FARM ou LUMBER_MILL, "progress":
## pontos de reconstrução}}. A casa continua da cidade, mas não produz.
var ruins := {}
## Construções (City.Build) concluídas no último turno: melhorias prontas e
## unidades que saíram da cidade. O Game mostra um aviso para cada uma.
var completed: Array[int] = []
var constructions: Array[Construction] = []
## Prédios prontos (City.Build), na ordem em que ficaram prontos. Toda cidade
## nasce com os prédios "native" (a Prefeitura).
var buildings: Array[int] = []
## Trabalhadores de cada prédio: {prédio: cidadãos}. Eles produzem a unidade ou
## arma da frente da fila do prédio e ficam lá quando ela fica pronta. Sem nada
## na fila, saem (ou, num prédio com "idle_gold", ficam rendendo ouro).
var building_workers := {}

## Força de trabalho: 1 ponto de produção por cidadão a cada turno.
var production: int:
	get:
		return population

var _map: GameMap
## Melhorias que a cidade já pintou no mapa: {casa: GameMap.Improvement}.
var _painted_improvements := {}


func setup(p_name: String, p_owner: Player, p_cell: Vector2i, map: GameMap) -> void:
	city_name = p_name
	owner_player = p_owner
	cell = p_cell
	_map = map
	position = map.cell_to_world(p_cell)
	name = "Cidade_%s" % p_name.replace(" ", "_")
	for build: int in BUILDS:
		if BUILDS[build].get("native", false):
			buildings.append(build)


## Estado da cidade para o save.
func to_dict() -> Dictionary:
	return {
		"name": city_name, "cell": SaveGame.cell_to_json(cell), "is_capital": is_capital,
		"territory": SaveGame.cells_to_json(territory), "population": population,
		"food_stock": food_stock, "farms": SaveGame.cell_map_to_json(farms),
		"lumber_mills": SaveGame.cell_map_to_json(lumber_mills),
		"constructions": constructions.map(func(construction: Construction) -> Dictionary: return construction.to_dict()),
		"buildings": buildings.duplicate(), "building_workers": SaveGame.int_map_to_json(building_workers),
		"ruins": ruins.keys().map(func(ruin_cell: Vector2i) -> Array:
			return [ruin_cell.x, ruin_cell.y, ruins[ruin_cell]["build"], ruins[ruin_cell]["progress"]]),
	}


## Volta ao estado salvo (depois de setup, que já deu o nome, o dono e a casa).
func apply_dict(data: Dictionary) -> void:
	is_capital = data.get("is_capital", false)
	if data.has("territory"):
		territory = SaveGame.json_to_cells(data["territory"])
	population = int(data["population"])
	food_stock = int(data["food_stock"])
	farms = SaveGame.json_to_cell_map(data["farms"])
	lumber_mills = SaveGame.json_to_cell_map(data["lumber_mills"])
	constructions.clear()
	for construction_data: Dictionary in data["constructions"]:
		constructions.append(Construction.from_dict(construction_data))
	buildings.clear()
	for build in data["buildings"]:
		buildings.append(int(build))
	building_workers = SaveGame.json_to_int_map(data["building_workers"])
	ruins.clear()
	for entry: Array in data.get("ruins", []):
		ruins[Vector2i(int(entry[0]), int(entry[1]))] = {"build": int(entry[2]), "progress": int(entry[3])}
	_painted_improvements.clear()
	_notify_changed()


func has_building(build: int) -> bool:
	return buildings.has(build)


## Obra da fila que faz [param build] (ou null).
func construction_of(build: int) -> Construction:
	for construction in constructions:
		if construction.build == build:
			return construction
	return null


## Motivo pelo qual a cidade não pode fazer [param build] ("" = pode). Não
## olha o terreno das melhorias (ver Game.buildable_cells) nem o ouro.
##   - prédio: só um por cidade (pronto ou em obra);
##   - unidade: precisa do prédio de "requires";
##   - madeira: o jogador precisa ter a madeira do item no estoque.
func build_error(build: int) -> String:
	var info: Dictionary = BUILDS[build]
	if info["category"] == Category.BUILDING:
		if has_building(build):
			return "A cidade já tem %s." % info["name"]
		if construction_of(build):
			return "Já está em obra."
	if info.has("requires") and not has_building(info["requires"]):
		return "Precisa de %s." % BUILDS[info["requires"]]["name"]
	var error := wood_error(build)
	return error if not error.is_empty() else weapons_error(build)


## Motivo pelo qual falta madeira para [param build] ("" = tem o suficiente).
func wood_error(build: int) -> String:
	var wood: int = BUILDS[build].get("wood", 0)
	if owner_player.wood < wood:
		return "Madeira insuficiente: precisa de %d (estoque: %d)." % [wood, owner_player.wood]
	return ""


## Motivo pelo qual faltam armas no arsenal para [param build] ("" = tem).
func weapons_error(build: int) -> String:
	var weapons: Dictionary = BUILDS[build].get("weapons", {})
	for weapon: Arsenal.Weapon in weapons:
		if owner_player.arsenal[weapon] < weapons[weapon]:
			return "Faltam armas: precisa de %s (arsenal: %d)." % [
				Arsenal.amount_text(weapon, weapons[weapon]), owner_player.arsenal[weapon]]
	return ""


## Tira do jogador a madeira e as armas de [param build] (use build_error
## antes). Retorna o que foi pago: {"wood": int, "weapons": {arma: qtd}}.
func pay_resources(build: int) -> Dictionary:
	var info: Dictionary = BUILDS[build]
	var weapons: Dictionary = info.get("weapons", {}).duplicate()
	owner_player.wood -= info.get("wood", 0)
	for weapon: Arsenal.Weapon in weapons:
		owner_player.arsenal[weapon] -= weapons[weapon]
	return {"wood": info.get("wood", 0), "weapons": weapons}


## O prédio fica pronto (por produção ou comprado). Se ele estava na fila de
## obras, sai dela e os trabalhadores vão para outra obra ou fazenda.
func add_building(build: int) -> void:
	var queued := construction_of(build)
	if queued:
		constructions.erase(queued)
		_assign_free_citizens(queued.workers)
	buildings.append(build)
	_notify_changed()


# --- Classe e território -------------------------------------------------------

## Classe pelo tamanho: Povoado, Vila, Cidade ou Metrópole (RANK_MIN_POPULATION).
func rank() -> Rank:
	var result := Rank.SETTLEMENT
	for candidate: Rank in RANK_MIN_POPULATION:
		if population >= RANK_MIN_POPULATION[candidate]:
			result = candidate
	return result


## "Povoado", "Vila (capital)"...
func rank_text() -> String:
	return RANK_NAMES[rank()] + (" (capital)" if is_capital else "")


## Faixa de população da classe: "1-5", "31+".
static func rank_range_text(value: Rank) -> String:
	var next: int = RANK_MIN_POPULATION.get(value + 1, -1)
	if next < 0:
		return "%d+" % RANK_MIN_POPULATION[value]
	return "%d-%d" % [maxi(RANK_MIN_POPULATION[value], 1), next - 1]


## Território inicial: a capital fica com a área de 21 casas (area_offsets); as
## outras cidades, com a casa delas e as 8 vizinhas.
static func territory_offsets(capital: bool) -> Array[Vector2i]:
	if capital:
		return area_offsets()
	var offsets: Array[Vector2i] = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			offsets.append(Vector2i(x, y))
	return offsets


# --- Área da cidade ----------------------------------------------------------

## Deslocamentos da área de 21 casas: as 8 casas vizinhas mais as 12 seguintes,
## sem as 4 pontas (um quadrado 5x5 sem os cantos). Inclui a própria cidade
## (0, 0). É o território inicial da capital e o que a janela da cidade mostra.
static func area_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for y in range(-2, 3):
		for x in range(-2, 3):
			if absi(x) == 2 and absi(y) == 2:
				continue
			offsets.append(Vector2i(x, y))
	# Casas mais próximas primeiro (útil para quem procura onde construir)
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return maxi(absi(a.x), absi(a.y)) < maxi(absi(b.x), absi(b.y)))
	return offsets


## Casas da área de trabalho no mapa (o território), incluindo a casa da cidade.
func area_cells() -> Array[Vector2i]:
	return territory.duplicate()


func construction_at(target: Vector2i) -> Construction:
	for construction in constructions:
		if construction.is_on_tile() and construction.cell == target:
			return construction
	return null


## Se a casa já tem uma fazenda, madeireira, ruína ou obra desta cidade.
func is_claimed(target: Vector2i) -> bool:
	return farms.has(target) or lumber_mills.has(target) or ruins.has(target) or construction_at(target) != null


# --- Pilhagem e reconstrução ---------------------------------------------------

## Melhoria pronta que pode ser pilhada na casa (Build.FARM ou LUMBER_MILL), ou -1.
func improvement_at(target: Vector2i) -> int:
	if farms.has(target):
		return Build.FARM
	if lumber_mills.has(target):
		return Build.LUMBER_MILL
	return -1


## Um inimigo pilhou a fazenda ou madeireira da casa: ela vira ruína e os
## cidadãos que trabalhavam nela são executados (a população pode chegar a 0).
## Retorna quantos cidadãos morreram.
func pillage(target: Vector2i) -> int:
	var build := improvement_at(target)
	var executed: int = farms.get(target, 0) + lumber_mills.get(target, 0)
	farms.erase(target)
	lumber_mills.erase(target)
	ruins[target] = {"build": build, "progress": 0}
	population = maxi(population - executed, 0)
	_release_extra_workers()
	_notify_changed()
	return executed


## Um Trabalhador reconstrói a ruína da casa: +[param points] pontos. Quando
## chega ao custo da melhoria, ela volta a funcionar (sem trabalhador).
## Retorna true se ficou pronta.
func add_rebuild_progress(target: Vector2i, points: int) -> bool:
	var ruin: Dictionary = ruins[target]
	ruin["progress"] += points
	if ruin["progress"] < BUILDS[ruin["build"]]["cost"]:
		_notify_changed()
		return false
	ruins.erase(target)
	_complete_at(ruin["build"], target)
	_notify_changed()
	return true


## A casa sai do território (vai para outra cidade do mesmo jogador, ver
## Game.transfer_cell) e leva junto o que a cidade tinha nela: fazenda,
## madeireira, ruína ou obra. Quem trabalhava ali fica livre nesta cidade.
## Retorna o que saiu, para receive_cell.
func give_up_cell(target: Vector2i) -> Dictionary:
	var taken := {}
	if farms.has(target):
		taken["farm"] = true
		farms.erase(target)
	if lumber_mills.has(target):
		taken["lumber_mill"] = true
		lumber_mills.erase(target)
	if ruins.has(target):
		taken["ruin"] = ruins[target]
		ruins.erase(target)
	var construction := construction_at(target)
	if construction:
		constructions.erase(construction)
		construction.workers = 0
		taken["construction"] = construction
	territory.erase(target)
	_notify_changed()
	return taken


## A casa entra no território com o que veio dela (de give_up_cell), sem
## trabalhadores: a melhoria vem de graça.
func receive_cell(target: Vector2i, taken: Dictionary) -> void:
	territory.append(target)
	if taken.has("farm"):
		farms[target] = 0
	if taken.has("lumber_mill"):
		lumber_mills[target] = 0
	if taken.has("ruin"):
		ruins[target] = taken["ruin"]
	if taken.has("construction"):
		constructions.append(taken["construction"])
	_notify_changed()


## Um Trabalhador migrou para a cidade: +1 de população, e o cidadão novo vai
## trabalhar na primeira obra (ou fazenda, madeireira...).
func add_citizen() -> void:
	population += 1
	_assign_free_citizens(1)
	_notify_changed()


## Se a melhoria [param build] pode ser feita num terreno do tipo [param type]:
## fazenda em pradaria ou cerrado; madeireira só em floresta.
static func allows_terrain(build: int, type: Terrain.Type) -> bool:
	match build:
		Build.FARM:
			return Terrain.can_farm(type)
		Build.LUMBER_MILL:
			return type == Terrain.Type.FOREST
	return false


# --- Números da cidade ------------------------------------------------------

## Cidadãos nas obras e nos prédios.
func construction_workers() -> int:
	var total := 0
	for construction in constructions:
		total += construction.workers
	for workers: int in building_workers.values():
		total += workers
	return total


## Trabalhadores que fazem a obra avançar: os da própria obra ou, para unidades
## e armas, os do prédio (só a primeira da fila avança).
func workers_on(construction: Construction) -> int:
	if not construction.is_produced():
		return construction.workers
	if active_unit(construction.producer()) != construction:
		return 0
	return building_workers.get(construction.producer(), 0)


## Ouro por turno: trabalhadores de prédios com "idle_gold" (Marcenaria) sem
## nada em produção rendem impostos.
func gold_per_turn() -> int:
	var total := 0
	for building in buildings:
		if active_unit(building) == null:
			total += building_workers.get(building, 0) * BUILDS[building].get("idle_gold", 0)
	return total


func farm_workers() -> int:
	var total := 0
	for workers: int in farms.values():
		total += workers
	return total


func mill_workers() -> int:
	var total := 0
	for workers: int in lumber_mills.values():
		total += workers
	return total


## Cidadãos que não estão trabalhando em nada.
func free_citizens() -> int:
	return population - construction_workers() - farm_workers() - mill_workers()


## Madeira que as madeireiras da cidade vão tirar no próximo turno.
func wood_per_turn() -> int:
	var total := 0
	for mill_cell: Vector2i in lumber_mills:
		total += mini(lumber_mills[mill_cell] * LumberMill.WOOD_PER_WORKER, _map.wood_left(mill_cell))
	return total


## Alimento produzido por turno. Cidade vazia (população 0) não produz nada,
## nem na casa da cidade: ela só volta a viver com um Trabalhador que migre.
func food_produced() -> int:
	if population <= 0:
		return 0
	var total := CENTER_FOOD
	for farm_cell: Vector2i in farms:
		total += farm_food(farm_cell) * farms[farm_cell]
	return total


## Alimento por turno da fazenda em [param farm_cell] com 1 cidadão: depende do
## terreno (pradaria 3, cerrado 2; Terrain.FARM_FOOD).
func farm_food(farm_cell: Vector2i) -> int:
	return Terrain.FARM_FOOD.get(_map.get_terrain(farm_cell), FARM_FOOD)


func food_consumed() -> int:
	return FOOD_PER_CITIZEN * population


## Saldo de alimento por turno (positivo = sobra, negativo = fome).
func food_per_turn() -> int:
	return food_produced() - food_consumed()


## Tamanho do estoque de alimentos: quando enche, a cidade cresce.
## (População atual + 1) × 10: 20 com 1 habitante, 30 com 2, 40 com 3...
func food_capacity() -> int:
	return (population + 1) * FOOD_BOX_PER_SIZE


## Turnos até a população crescer, ou -1 se o alimento não está sobrando.
func turns_to_grow() -> int:
	var surplus := food_per_turn()
	if surplus <= 0:
		return -1
	return maxi(1, ceili(float(food_capacity() - food_stock) / surplus))


## Turnos até a obra terminar (0 = pronta), ou -1 se ninguém está trabalhando nela.
func turns_to_finish(construction: Construction) -> int:
	if construction.is_done():
		return 0
	var workers := workers_on(construction)
	if workers <= 0:
		return -1
	return ceili(float(construction.cost() - construction.progress) / workers)


# --- Ordens do jogador ------------------------------------------------------

## Se a cidade tem população para entregar a unidade sem ficar abaixo de 1.
func can_afford_population(construction: Construction) -> bool:
	return population - construction.population_cost() >= 1


## A cidade entrega população (unidade pronta ou comprada); se faltar gente,
## tira trabalhadores das obras, depois das madeireiras e das fazendas.
func pay_population(amount: int) -> void:
	population -= amount
	_release_extra_workers()
	_notify_changed()


## Ordena uma obra: melhoria na casa [param target] ou unidade (sem casa).
## Os cidadãos livres passam a trabalhar nela (dá para mudar depois com
## set_construction_workers).
## Unidade ou arma: entra na fila do prédio que a produz; os cidadãos livres
## vão para os trabalhadores do prédio.
## A madeira e as armas do item saem do estoque agora (use build_error antes).
func order_build(build: int, target := Vector2i.ZERO) -> Construction:
	var construction := Construction.new()
	construction.build = build
	construction.cell = target
	var paid := pay_resources(build)
	construction.wood_paid = paid["wood"]
	construction.weapons_paid = paid["weapons"]
	if construction.is_produced():
		var building := construction.producer()
		building_workers[building] = building_workers.get(building, 0) + free_citizens()
	else:
		construction.workers = free_citizens()
	constructions.append(construction)
	_notify_changed()
	return construction


## Cancela a obra; o progresso é perdido, mas a madeira e as armas pagas
## voltam. Os trabalhadores de um prédio continuam nele se ainda houver algo na
## fila (ou se ele render ouro parado); os outros vão para outra obra ou
## fazenda (ver _assign_free_citizens).
func cancel_construction(construction: Construction) -> void:
	constructions.erase(construction)
	owner_player.wood += construction.wood_paid
	for weapon: Arsenal.Weapon in construction.weapons_paid:
		owner_player.arsenal[weapon] += construction.weapons_paid[weapon]
	if construction.is_produced():
		_release_idle_building(construction.producer())
	else:
		_assign_free_citizens(construction.workers)
	_notify_changed()


## Prédio sem nada para produzir: os trabalhadores saem e vão para outra obra
## ou fazenda, menos num prédio que rende ouro parado ("idle_gold").
func _release_idle_building(building: int) -> void:
	if active_unit(building) != null or BUILDS[building].get("idle_gold", 0) > 0:
		return
	var workers: int = building_workers.get(building, 0)
	building_workers[building] = 0
	_assign_free_citizens(workers)


## Unidades e armas na fila do prédio [param building], na ordem em que foram pedidas.
func unit_queue(building: int) -> Array[Construction]:
	var queue: Array[Construction] = []
	for construction in constructions:
		if construction.producer() == building:
			queue.append(construction)
	return queue


## Unidade que está avançando no prédio: a primeira da fila que ainda não
## ficou pronta (as outras esperam, sem trabalhadores). null se não houver.
func active_unit(building: int) -> Construction:
	for construction in unit_queue(building):
		if not construction.is_done():
			return construction
	return null


## Todos os cidadãos ficam livres (fazendas, madeireiras, obras e prédios).
## Usado pela máquina para redistribuir a cidade inteira a cada turno.
func clear_workers() -> void:
	for farm_cell: Vector2i in farms:
		farms[farm_cell] = 0
	for mill_cell: Vector2i in lumber_mills:
		lumber_mills[mill_cell] = 0
	for construction in constructions:
		construction.workers = 0
	for building: int in building_workers:
		building_workers[building] = 0
	_notify_changed()


## Unidade ou arma: muda os trabalhadores do prédio que a produz.
func set_construction_workers(construction: Construction, workers: int) -> void:
	if construction.is_produced():
		set_building_workers(construction.producer(), workers)
		return
	if construction.is_done():
		workers = 0 # obra pronta não precisa de mais ninguém
	construction.workers = clampi(workers, 0, construction.workers + free_citizens())
	_notify_changed()


## Cidadãos no prédio (limitado aos livres).
func set_building_workers(building: int, workers: int) -> void:
	var current: int = building_workers.get(building, 0)
	building_workers[building] = clampi(workers, 0, current + free_citizens())
	_notify_changed()


func set_farm_worked(farm_cell: Vector2i, worked: bool) -> void:
	if worked and (farms[farm_cell] > 0 or free_citizens() <= 0):
		return
	farms[farm_cell] = 1 if worked else 0
	_notify_changed()


## Cidadãos na madeireira, de 0 a LumberMill.MAX_WORKERS (limitado aos livres).
func set_mill_workers(mill_cell: Vector2i, workers: int) -> void:
	var current: int = lumber_mills[mill_cell]
	lumber_mills[mill_cell] = clampi(workers, 0, mini(LumberMill.MAX_WORKERS, current + free_citizens()))
	_notify_changed()


# --- Turno ------------------------------------------------------------------

## Avança as obras, a madeira e o alimento (ver regras no topo). A madeira vai
## para o estoque do dono (Player.wood). Retorna as mensagens do que aconteceu
## (obra concluída, unidade pronta, floresta esgotada, crescimento, fome).
## [param spawn_unit] é chamado como spawn_unit(tipo, cidade) -> bool para pôr
## uma unidade pronta no mapa; retorna false se não houver espaço.
func process_turn(spawn_unit: Callable) -> Array[String]:
	var events: Array[String] = []
	completed.clear()
	# Livres por escolha do jogador (botão "-"): continuam livres. Só os que
	# ficarem livres agora (obra pronta, crescimento) são realocados no fim.
	var idle_by_choice := free_citizens()
	# Primeiro todas as obras avançam (unidades e armas: a da frente da fila de
	# cada prédio, com os trabalhadores do prédio); prédio que rende ouro parado
	# paga os impostos. Depois as prontas são resolvidas.
	owner_player.gold += gold_per_turn()
	var advancing := {}
	for building in buildings:
		var active := active_unit(building)
		if active:
			advancing[active] = building_workers.get(building, 0)
	for construction in constructions:
		var workers: int = advancing.get(construction, 0) if construction.is_produced() else construction.workers
		construction.progress = mini(construction.progress + workers, construction.cost())
	for construction in constructions.duplicate():
		if not construction.is_done():
			continue
		construction.workers = 0
		if construction.is_on_tile():
			constructions.erase(construction)
			_complete_at(construction.build, construction.cell)
			completed.append(construction.build)
			events.append("%s concluída em (%d, %d)" % [construction.display_name(), construction.cell.x, construction.cell.y])
		elif construction.is_building():
			constructions.erase(construction)
			buildings.append(construction.build)
			completed.append(construction.build)
			events.append("%s concluíd%s" % [construction.display_name(), BUILDS[construction.build]["article"]])
		elif construction.is_weapon():
			# Arma pronta vai para o arsenal (sem aviso: os trabalhadores continuam no prédio)
			var weapon: Arsenal.Weapon = BUILDS[construction.build]["weapon"]
			constructions.erase(construction)
			owner_player.arsenal[weapon] += 1
			events.append("%s pront%s (arsenal: %s)" % [construction.display_name(), BUILDS[construction.build]["article"],
					Arsenal.amount_text(weapon, owner_player.arsenal[weapon])])
		elif not can_afford_population(construction):
			if not construction.waiting_reported:
				construction.waiting_reported = true
				events.append("%s pronto, esperando a população chegar a %d" % [
					construction.display_name(), construction.population_cost() + 1])
		elif spawn_unit.call(BUILDS[construction.build]["unit"], self):
			constructions.erase(construction)
			completed.append(construction.build)
			pay_population(construction.population_cost())
			events.append("%s pronto (população caiu para %d)" % [construction.display_name(), population])
		else:
			events.append("%s pronto, mas não há espaço livre ao redor da cidade" % construction.display_name())
	# Prédio que ficou sem nada na fila libera os trabalhadores (realocados no fim)
	for building: int in building_workers:
		if active_unit(building) == null and BUILDS[building].get("idle_gold", 0) == 0:
			building_workers[building] = 0

	for mill_cell: Vector2i in lumber_mills.keys():
		owner_player.wood += _map.harvest_wood(mill_cell, lumber_mills[mill_cell] * LumberMill.WOOD_PER_WORKER)
		if _map.wood_left(mill_cell) <= 0:
			lumber_mills.erase(mill_cell) # os cidadãos dela ficam livres
			events.append("a floresta da madeireira em (%d, %d) acabou e virou cerrado" % [mill_cell.x, mill_cell.y])

	food_stock += food_per_turn()
	if food_stock >= food_capacity():
		food_stock = 0 # estoque cheio: cresce e o estoque esvazia (Civilization II)
		var old_rank := rank()
		population += 1
		events.append("cresceu para %d de população" % population)
		if rank() != old_rank:
			events.append("agora é %s %s" % ["uma" if rank() in [Rank.TOWN, Rank.CITY, Rank.METROPOLIS] else "um", RANK_NAMES[rank()]])
	elif food_stock < 0:
		food_stock = 0
		if population > 1:
			population -= 1
			_release_extra_workers()
			events.append("passou fome e caiu para %d de população" % population)

	_assign_free_citizens(free_citizens() - idle_by_choice)
	_notify_changed()
	return events


## A melhoria fica pronta, sem trabalhador (obra concluída ou ruína
## reconstruída; os trabalhadores da obra são realocados no fim do turno).
func _complete_at(build: int, target: Vector2i) -> void:
	match build:
		Build.FARM:
			farms[target] = 0
		Build.LUMBER_MILL:
			lumber_mills[target] = 0


## Evita cidadãos ociosos: põe até [param count] cidadãos livres na primeira
## obra da fila que ainda não terminou; se não houver obra, nas fazendas sem
## trabalhador e depois nas madeireiras com vaga. O que sobrar fica livre.
func _assign_free_citizens(count: int) -> void:
	count = mini(count, free_citizens())
	if count <= 0:
		return
	for construction in constructions:
		if construction.is_produced():
			# Unidade ou arma: os cidadãos vão para o prédio, se ela for a da frente
			if active_unit(construction.producer()) == construction:
				building_workers[construction.producer()] = building_workers.get(construction.producer(), 0) + count
				return
		elif not construction.is_done():
			construction.workers += count
			return
	for farm_cell in farms:
		if count > 0 and farms[farm_cell] == 0:
			farms[farm_cell] = 1
			count -= 1
	for mill_cell in lumber_mills:
		var added := mini(count, LumberMill.MAX_WORKERS - lumber_mills[mill_cell])
		lumber_mills[mill_cell] += added
		count -= added


## Depois de perder população, tira trabalhadores (primeiro das obras, depois
## das madeireiras e por fim das fazendas) até o total caber na população.
func _release_extra_workers() -> void:
	for construction in constructions:
		while free_citizens() < 0 and construction.workers > 0:
			construction.workers -= 1
	for building: int in building_workers:
		while free_citizens() < 0 and building_workers[building] > 0:
			building_workers[building] -= 1
	for mill_cell in lumber_mills:
		while free_citizens() < 0 and lumber_mills[mill_cell] > 0:
			lumber_mills[mill_cell] -= 1
	for farm_cell in farms:
		if free_citizens() < 0 and farms[farm_cell] > 0:
			farms[farm_cell] = 0


func _notify_changed() -> void:
	_sync_map_improvements()
	queue_redraw()
	changed.emit()


## Mostra no mapa (GameMap.set_improvement) as fazendas da cidade, prontas ou
## em obra, e apaga as que deixaram de existir (obra cancelada).
func _sync_map_improvements() -> void:
	var current := {}
	for farm_cell: Vector2i in farms:
		current[farm_cell] = GameMap.Improvement.FARM
	for construction in constructions:
		if construction.is_on_tile() and construction.build == Build.FARM:
			current[construction.cell] = GameMap.Improvement.FARM_IN_PROGRESS
	for painted_cell: Vector2i in _painted_improvements:
		if not current.has(painted_cell):
			_map.set_improvement(painted_cell, GameMap.Improvement.NONE)
	for improvement_cell: Vector2i in current:
		if _painted_improvements.get(improvement_cell, -1) != current[improvement_cell]:
			_map.set_improvement(improvement_cell, current[improvement_cell])
	_painted_improvements = current


# --- Desenho ----------------------------------------------------------------

func _draw() -> void:
	var tile := Vector2.ONE * GameMap.TILE_SIZE
	for mill_cell in lumber_mills:
		var mill_rect := Rect2(_local_center(mill_cell) - tile / 2.0, tile)
		LumberMill.draw_icon(self, mill_rect)
		LumberMill.draw_wood_bar(self, mill_rect, _map.wood_left(mill_cell))
	for construction in constructions:
		if construction.is_on_tile() and construction.build != Build.FARM: # fazendas: no shader do mapa
			draw_improvement(self, construction.build, Rect2(_local_center(construction.cell) - tile / 2.0, tile), CONSTRUCTION_ALPHA)
	for ruin_cell: Vector2i in ruins:
		var ruin_rect := Rect2(_local_center(ruin_cell) - tile / 2.0, tile)
		draw_ruin(self, ruins[ruin_cell]["build"], ruin_rect)
		if ruins[ruin_cell]["progress"] > 0:
			LumberMill.draw_bar(self, ruin_rect, float(ruins[ruin_cell]["progress"]) / BUILDS[ruins[ruin_cell]["build"]]["cost"],
					LumberMill.PROGRESS_BAR_COLOR)

	draw_city_icon(self, Rect2(-tile / 2.0, tile).grow(-MARGIN), owner_player.color, population, FONT_SIZE)
	_draw_food_bar(Rect2(-tile / 2.0, tile).grow(-MARGIN))
	if free_citizens() > 0 and not owner_player.is_ai:
		_draw_idle_warning(Rect2(-tile / 2.0, tile).grow(-MARGIN), free_citizens())

	# Nome embaixo da cidade, com contorno para ler em qualquer terreno
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x
	var origin := Vector2(-width / 2.0, tile.y / 2.0 + NAME_FONT_SIZE)
	draw_string_outline(font, origin, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, NAME_FONT_SIZE / 3, Color.BLACK)
	draw_string(font, origin, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, Color.WHITE)
	if is_capital:
		var star_center := Vector2(origin.x - NAME_FONT_SIZE * 0.7, origin.y - NAME_FONT_SIZE * 0.35)
		draw_star(self, star_center, NAME_FONT_SIZE * 0.55)


## Barrinha do estoque de alimentos logo acima da cidade. Vermelha quando a
## cidade está passando fome (saldo negativo).
func _draw_food_bar(icon: Rect2) -> void:
	var bar := Rect2(icon.position.x, icon.position.y - FOOD_BAR_HEIGHT - MARGIN, icon.size.x, FOOD_BAR_HEIGHT)
	var ratio := clampf(float(food_stock) / food_capacity(), 0.0, 1.0)
	var color := FOOD_BAR_STARVING_COLOR if food_per_turn() < 0 else FOOD_BAR_COLOR
	draw_rect(bar.grow(1.0), Color.BLACK)
	draw_rect(bar, Color(0.25, 0.25, 0.25))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), color)


## Trabalhadores ociosos: círculo azul com "!" acima da barra de alimentos e,
## à direita, a quantidade de cidadãos livres. Só nas cidades do jogador humano.
func _draw_idle_warning(icon: Rect2, idle: int) -> void:
	var font := ThemeDB.fallback_font
	var count := str(idle)
	var count_width := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, IDLE_FONT_SIZE).x
	var gap := MARGIN
	# Círculo + número centralizados juntos sobre a cidade
	var group_width := IDLE_ICON_RADIUS * 2.0 + gap + count_width
	var food_bar_top := icon.position.y - FOOD_BAR_HEIGHT - MARGIN
	var center := Vector2(-group_width / 2.0 + IDLE_ICON_RADIUS, food_bar_top - MARGIN - IDLE_ICON_RADIUS)
	var baseline := (font.get_ascent(IDLE_FONT_SIZE) - font.get_descent(IDLE_FONT_SIZE)) / 2.0

	draw_circle(center, IDLE_ICON_RADIUS + 1.5, Color.BLACK)
	draw_circle(center, IDLE_ICON_RADIUS, IDLE_COLOR)
	var mark_width := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, IDLE_FONT_SIZE).x
	draw_string(font, center + Vector2(-mark_width / 2.0, baseline), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, IDLE_FONT_SIZE, Color.WHITE)

	var origin := Vector2(center.x + IDLE_ICON_RADIUS + gap, center.y + baseline)
	draw_string_outline(font, origin, count, HORIZONTAL_ALIGNMENT_LEFT, -1, IDLE_FONT_SIZE, IDLE_FONT_SIZE / 3, Color.BLACK)
	draw_string(font, origin, count, HORIZONTAL_ALIGNMENT_LEFT, -1, IDLE_FONT_SIZE, IDLE_COLOR.lightened(0.3))


## Texto do aviso de construção concluída: "A construção da fazenda foi concluída."
static func completion_text(build: int) -> String:
	var info: Dictionary = BUILDS[build]
	return "A construção d%s %s foi concluída." % [info["article"], String(info["name"]).to_lower()]


func _local_center(target: Vector2i) -> Vector2:
	return to_local(_map.cell_to_world(target))


## Cidade no estilo Civilization 1: quadrado na cor do dono com a população no meio.
## Também usado pela janela da cidade.
static func draw_city_icon(canvas: CanvasItem, rect: Rect2, color: Color, pop: int, font_size: int) -> void:
	var border := rect.size.x / 14.0
	canvas.draw_rect(rect, color)
	canvas.draw_rect(rect, Color.BLACK, false, border)
	canvas.draw_rect(rect.grow(-border * 1.5), Color.WHITE, false, border / 2.0)
	var font := ThemeDB.fallback_font
	var text := str(pop)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := rect.get_center() + Vector2(-text_size.x / 2.0, (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)


## Desenho da melhoria (fazenda ou madeireira). [param alpha] menor = em obra
## (a fazenda em obra aparece só com a terra arada).
static func draw_improvement(canvas: CanvasItem, build: int, rect: Rect2, alpha := 1.0) -> void:
	if build == Build.LUMBER_MILL:
		LumberMill.draw_icon(canvas, rect, alpha)
	else:
		draw_farm(canvas, rect, alpha >= 1.0)


## Estrela dourada da capital (ao lado do nome, no mapa e na janela da cidade).
static func draw_star(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * 0.45))
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_colored_polygon(points, Color(1, 0.82, 0.2))
	canvas.draw_polyline(outline, Color.BLACK, maxf(1.0, radius / 5.0))


## Melhoria destruída (pilhada): o PNG de RUIN_TEXTURES.
static func draw_ruin(canvas: CanvasItem, build: int, rect: Rect2) -> void:
	canvas.draw_texture_rect(RUIN_TEXTURES[build], rect, false)


## Fazenda (janela da cidade e ícones): campo arredondado de contorno um pouco
## ondulado, com cerca viva em volta e fileiras curvas recortadas no formato
## do campo. [param planted] = false: em obra, só terra arada. No mapa
## principal, as fazendas são desenhadas pelo shader do terreno.
static func draw_farm(canvas: CanvasItem, rect: Rect2, planted := true) -> void:
	var field := rect.grow(-rect.size.x * 0.1)
	var radius := field.size.x * 0.3
	var center := field.get_center()
	# Contorno: retângulo de cantos redondos com uma ondulação leve
	var outline := PackedVector2Array()
	var steps := 32
	for i in steps + 1:
		var angle := TAU * i / steps
		var direction := Vector2(cos(angle), sin(angle))
		var wobble := 1.0 + 0.04 * sin(angle * 5.0 + 1.3)
		outline.append(center + _rounded_rect_point(field.size / 2.0, radius, direction) * wobble)
	var hedge := Color8(70, 108, 44)
	canvas.draw_colored_polygon(outline, hedge)
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(center + (point - center) * 0.86)
	canvas.draw_colored_polygon(inner, FARM_COLOR if planted else FARM_SOIL_COLOR)
	# Fileiras: linhas onduladas, cortadas na largura do campo em cada altura
	var half := field.size / 2.0 * 0.86
	var inner_radius := radius * 0.86
	var rows := 5
	var thickness := maxf(1.0, rect.size.y / 22.0)
	for row in rows:
		var dy := -half.y + half.y * 2.0 * (row + 0.5) / rows
		var half_width := _rounded_rect_half_width(half, inner_radius, dy) - thickness
		if half_width <= 0.0:
			continue
		var line := PackedVector2Array()
		for k in 9:
			var x := -half_width + half_width * 2.0 * k / 8.0
			line.append(center + Vector2(x, dy + sin(x / half.x * 2.2 + row) * thickness * 0.8))
		canvas.draw_polyline(line, FARM_FURROW_COLOR if planted else FARM_SOIL_COLOR.darkened(0.3), thickness)


## Ponto do contorno de um retângulo de cantos redondos (meia-medida [param half],
## raio [param radius]) na direção [param direction], a partir do centro.
static func _rounded_rect_point(half: Vector2, radius: float, direction: Vector2) -> Vector2:
	# Avança do centro até sair do retângulo arredondado (busca binária simples)
	var low := 0.0
	var high := half.length()
	for i in 12:
		var middle := (low + high) / 2.0
		var point := direction * middle
		if _inside_rounded_rect(point, half, radius):
			low = middle
		else:
			high = middle
	return direction * low


static func _inside_rounded_rect(point: Vector2, half: Vector2, radius: float) -> bool:
	var q := Vector2(absf(point.x), absf(point.y)) - (half - Vector2.ONE * radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() <= radius and maxf(q.x, q.y) <= radius


## Meia-largura do retângulo arredondado na altura [param dy] (a partir do centro).
static func _rounded_rect_half_width(half: Vector2, radius: float, dy: float) -> float:
	var straight := half.y - radius
	if absf(dy) <= straight:
		return half.x
	var over := absf(dy) - straight
	if over >= radius:
		return 0.0
	return half.x - radius + sqrt(radius * radius - over * over)
