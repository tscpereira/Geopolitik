class_name Movement
extends RefCounted

## Cálculo de alcance e caminho das unidades no grid.
## Movimento em 8 direções (diagonais incluídas). Entrar numa casa custa 1
## movimento, ou mais em terrenos difíceis (ver Terrain.move_cost: a floresta
## custa 2 para unidades com mais de 1 de movimento) e ao atravessar um rio
## (+1 para essas unidades; ver step_cost). Andar de uma casa com estrada para
## outra com estrada (a cidade conta como estrada; GameMap.has_road) custa meio
## movimento.
## Os custos são em PONTOS de movimento: POINTS por movimento (Unit.moves_left
## também é em pontos), para caber o meio movimento da estrada.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Sem limite de movimentos (busca de caminho da ordem "Mover").
const NO_LIMIT := 1 << 30
## Pontos de movimento por movimento (unit.movement) e o custo de um passo de
## estrada para estrada (meio movimento).
const POINTS := 2
const ROAD_STEP_POINTS := 1


## Retorna {casa: casa_anterior} com tudo que a unidade alcança com os
## movimentos restantes (inclui a casa da própria unidade e casas com aliados,
## que podem ser atravessadas). [param occupants] é {casa: Unit}.
## [param moves] substitui os movimentos restantes da unidade, em movimentos
## inteiros (ex.: para prever o próximo turno de um inimigo).
static func find_reachable(map: GameMap, unit: Unit, occupants: Dictionary, moves := -1) -> Dictionary:
	return _search(map, unit, occupants, unit.moves_left if moves < 0 else moves * POINTS)


## Casas onde a unidade pode terminar o movimento: alcançáveis e vazias. Com
## [param unit], também a casa de uma Galé dela com lugar (embarcar).
static func destinations(reachable: Dictionary, occupants: Dictionary, unit: Unit = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in reachable:
		if not occupants.has(cell) or (unit and occupants[cell].can_carry(unit)):
			result.append(cell)
	return result


## Se uma unidade do tipo [param type] pode ficar na casa: as navais na água, as
## outras em terra andável.
static func can_stand(map: GameMap, type: UnitType, cell: Vector2i) -> bool:
	if not map.is_in_bounds(cell):
		return false
	var terrain := map.get_terrain(cell)
	return Terrain.is_navigable(terrain) if type.is_naval else Terrain.is_walkable(terrain)


## Inimigos que a unidade pode atacar: {casa_do_inimigo: casa_de_onde_ataca}.
## Atacar encerra os movimentos, então a unidade precisa chegar a uma casa
## vizinha ao inimigo com algum movimento sobrando (meio movimento basta). Usa a casa de ataque mais próxima.
## Unidades com Ataque 0 não atacam.
## Ataque à distância (Unit.is_ranged): o alvo pode estar a até attack_range
## casas da casa de onde ela dispara, com a linha de tiro livre (has_line_of_fire).
static func attack_targets(map: GameMap, unit: Unit, reachable: Dictionary, occupants: Dictionary) -> Dictionary:
	if unit.attack <= 0 or unit.transport:
		return {} # sem ataque (ex.: Colono) ou embarcada: não ataca
	var targets := {}
	var best_distance := {}
	for cell in reachable:
		if cell != unit.cell and occupants.has(cell):
			continue # casa com aliado: dá para atravessar, mas não parar nela
		if cell != unit.cell and is_enemy_city(map, unit, cell):
			continue # quem entra numa cidade inimiga para lá (invasão), não ataca dali
		var distance := path_cost(map, unit, build_path(reachable, cell))
		if distance >= unit.moves_left:
			continue
		for offset in attack_offsets(unit):
			var target: Vector2i = cell + offset
			var occupant: Unit = occupants.get(target)
			if occupant == null or occupant.owner_player == unit.owner_player \
					or not in_attack_range(map, unit, cell, target):
				continue
			if not best_distance.has(target) or distance < best_distance[target]:
				targets[target] = cell
				best_distance[target] = distance
	return targets


## Deslocamentos até as casas que a unidade pode atingir: as vizinhas
## (DIRECTIONS) ou, à distância, o quadrado de lado 2 × attack_range + 1.
static func attack_offsets(unit: Unit) -> Array[Vector2i]:
	if not unit.is_ranged():
		return DIRECTIONS
	var reach := unit.type.attack_range
	var offsets: Array[Vector2i] = []
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			if x != 0 or y != 0:
				offsets.append(Vector2i(x, y))
	return offsets


## Distância em casas, contando a diagonal como 1 (o grid tem 8 direções).
static func grid_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Se a unidade, parada em [param from], alcança o alvo em [param target]:
## corpo a corpo, só a casa vizinha; à distância, até attack_range casas e com
## a linha de tiro livre.
static func in_attack_range(map: GameMap, unit: Unit, from: Vector2i, target: Vector2i) -> bool:
	var distance := grid_distance(from, target)
	if distance == 0:
		return false
	if not unit.is_ranged():
		# Corpo a corpo só contra quem está num terreno em que ela pode entrar:
		# a Galé luta na água, as tropas de terra em terra
		return distance == 1 and can_stand(map, unit.type, target)
	return distance <= unit.type.attack_range and (unit.type.indirect_fire or has_line_of_fire(map, from, target))


## Terrenos que bloqueiam o disparo quando estão ENTRE quem atira e o alvo (o
## alvo pode estar neles).
const BLOCKS_FIRE: Array[Terrain.Type] = [Terrain.Type.FOREST, Terrain.Type.HILLS, Terrain.Type.MOUNTAINS]


## Linha de tiro de [param from] até [param target]: em cada passo da reta entre
## as duas casas, a casa por onde ela passa não pode ser floresta, colina nem
## montanha. Quando a reta passa bem entre duas casas (ex.: 2 para o lado e 1
## para baixo), basta uma delas estar livre. Casas vizinhas sempre se veem.
static func has_line_of_fire(map: GameMap, from: Vector2i, target: Vector2i) -> bool:
	var delta := target - from
	var steps := grid_distance(from, target)
	for i in range(1, steps):
		var point := Vector2(from) + Vector2(delta) * i / steps
		var clear := false
		for x in _nearest(point.x):
			for y in _nearest(point.y):
				var cell := Vector2i(x, y)
				if map.is_in_bounds(cell) and not BLOCKS_FIRE.has(map.get_terrain(cell)):
					clear = true
		if not clear:
			return false
	return true


## Coordenada inteira mais perto de [param value]; as duas, se ele estiver bem
## no meio (ex.: 0,5 -> 0 e 1).
static func _nearest(value: float) -> Array[int]:
	if is_equal_approx(value - floorf(value), 0.5):
		return [floori(value), ceili(value)]
	return [roundi(value)]


## Caminho mais barato até uma casa distante, sem limite de movimentos (para a
## ordem "Mover"). Contorna água e inimigos; atravessa aliados. Retorna o
## caminho sem a casa de origem, ou vazio se não houver como chegar.
static func find_path(map: GameMap, unit: Unit, target: Vector2i, occupants: Dictionary) -> Array[Vector2i]:
	if target == unit.cell or not can_enter(map, unit, target, occupants):
		return []
	var came_from := _search(map, unit, occupants, NO_LIMIT, target)
	return build_path(came_from, target) if came_from.has(target) else []


## Caminho até [param target], sem a casa de origem.
static func build_path(reachable: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell := target
	while reachable[cell] != cell:
		path.push_front(cell)
		cell = reachable[cell]
	return path


## Pontos de movimento gastos para andar da casa [param from] para a vizinha
## [param cell]: de estrada para estrada, ROAD_STEP_POINTS (meio movimento, sem
## as penalidades); senão, o terreno de destino (floresta, colinas) mais
## Terrain.RIVER_MOVE_PENALTY se o passo atravessa um rio, os dois só para
## unidades com mais de 1 de movimento. Nunca passa do movimento cheio da
## unidade: com todos os movimentos ela sempre consegue entrar (Bigas, com 3:
## colina + rio = 3, o turno todo).
static func step_cost(map: GameMap, unit: Unit, from: Vector2i, cell: Vector2i) -> int:
	if map.has_road(from) and map.has_road(cell):
		return ROAD_STEP_POINTS
	var cost := Terrain.move_cost(map.get_terrain(cell), unit.movement)
	if unit.movement > 1 and not unit.is_naval() and map.crosses_river(from, cell):
		cost += Terrain.RIVER_MOVE_PENALTY
	return mini(cost, unit.movement) * POINTS


## Pontos de movimento gastos para andar o caminho inteiro, saindo de [param from]
## (a casa da unidade, se não for dada).
static func path_cost(map: GameMap, unit: Unit, path: Array[Vector2i], from := Unit.NO_TARGET) -> int:
	var total := 0
	var previous := unit.cell if from == Unit.NO_TARGET else from
	for cell in path:
		total += step_cost(map, unit, previous, cell)
		previous = cell
	return total


## Cidades inimigas: só unidades militares de corpo a corpo entram (para
## invadir; ver Game.check_invasion), e a unidade para nelas (não atravessa).
## Arqueiro e Catapulta derrubam a guarnição de longe, mas não tomam a cidade.
## A Galé só anda na água; a tropa de terra só entra na água para embarcar numa
## Galé sua com lugar (e para ali).
static func can_enter(map: GameMap, unit: Unit, cell: Vector2i, occupants: Dictionary) -> bool:
	if not can_stand(map, unit.type, cell):
		var boat: Unit = occupants.get(cell)
		return boat != null and boat.can_carry(unit)
	if is_enemy_city(map, unit, cell) and (unit.attack <= 0 or unit.is_ranged()):
		return false
	var occupant: Unit = occupants.get(cell)
	return occupant == null or occupant.owner_player == unit.owner_player


static func is_enemy_city(map: GameMap, unit: Unit, cell: Vector2i) -> bool:
	var city_owner: Player = map.city_owners.get(cell)
	return city_owner != null and city_owner != unit.owner_player


## Busca pelo menor custo (Dijkstra com "baldes": buckets[c] = casas
## alcançadas gastando c pontos de movimento). Para em [param target], se houver.
## Retorna {casa: casa_anterior}.
static func _search(map: GameMap, unit: Unit, occupants: Dictionary, budget: int,
		target := Vector2i(-1, -1)) -> Dictionary:
	var came_from := {unit.cell: unit.cell}
	var cost := {unit.cell: 0}
	var buckets: Array[Array] = [[unit.cell]]
	var current := 0
	while current < buckets.size():
		for cell: Vector2i in buckets[current]:
			if cost[cell] != current:
				continue # já foi alcançada mais barato
			if cell == target:
				return came_from
			if cell != unit.cell and is_enemy_city(map, unit, cell):
				continue # entrar numa cidade inimiga encerra o caminho (invasão)
			if cell != unit.cell and not can_stand(map, unit.type, cell):
				continue # embarcou numa Galé: o caminho acaba nela
			for direction in DIRECTIONS:
				var next := cell + direction
				if not can_enter(map, unit, next, occupants):
					continue
				var next_cost := current + step_cost(map, unit, cell, next)
				if next_cost > budget or (cost.has(next) and cost[next] <= next_cost):
					continue
				cost[next] = next_cost
				came_from[next] = cell
				while buckets.size() <= next_cost:
					buckets.append([])
				buckets[next_cost].append(next)
		current += 1
	return came_from
