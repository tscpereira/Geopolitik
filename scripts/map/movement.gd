class_name Movement
extends RefCounted

## Cálculo de alcance e caminho das unidades no grid.
## Movimento em 8 direções (diagonais incluídas). Entrar numa casa custa 1
## movimento, ou mais em terrenos difíceis (ver Terrain.move_cost: a floresta
## custa 2 para unidades com mais de 1 de movimento).

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Sem limite de movimentos (busca de caminho da ordem "Mover").
const NO_LIMIT := 1 << 30


## Retorna {casa: casa_anterior} com tudo que a unidade alcança com os
## movimentos restantes (inclui a casa da própria unidade e casas com aliados,
## que podem ser atravessadas). [param occupants] é {casa: Unit}.
## [param moves] substitui os movimentos restantes da unidade (ex.: para prever
## o próximo turno de um inimigo).
static func find_reachable(map: GameMap, unit: Unit, occupants: Dictionary, moves := -1) -> Dictionary:
	return _search(map, unit, occupants, unit.moves_left if moves < 0 else moves)


## Casas onde a unidade pode terminar o movimento: alcançáveis e vazias.
static func destinations(reachable: Dictionary, occupants: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in reachable:
		if not occupants.has(cell):
			result.append(cell)
	return result


## Inimigos que a unidade pode atacar: {casa_do_inimigo: casa_de_onde_ataca}.
## Atacar custa 1 movimento, então a unidade precisa chegar a uma casa vizinha
## ao inimigo com pelo menos 1 movimento sobrando. Usa a casa de ataque mais próxima.
## Unidades com Ataque 0 não atacam.
static func attack_targets(map: GameMap, unit: Unit, reachable: Dictionary, occupants: Dictionary) -> Dictionary:
	if unit.attack <= 0:
		return {} # unidades sem ataque (ex.: Colono) não atacam
	var targets := {}
	var best_distance := {}
	for cell in reachable:
		if cell != unit.cell and occupants.has(cell):
			continue # casa com aliado: dá para atravessar, mas não parar nela
		var distance := path_cost(map, unit, build_path(reachable, cell))
		if distance >= unit.moves_left:
			continue
		for direction in DIRECTIONS:
			var target: Vector2i = cell + direction
			var occupant: Unit = occupants.get(target)
			if occupant == null or occupant.owner_player == unit.owner_player:
				continue
			if not best_distance.has(target) or distance < best_distance[target]:
				targets[target] = cell
				best_distance[target] = distance
	return targets


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


## Movimentos gastos para entrar na casa.
static func step_cost(map: GameMap, unit: Unit, cell: Vector2i) -> int:
	return Terrain.move_cost(map.get_terrain(cell), unit.movement)


## Movimentos gastos para andar o caminho inteiro.
static func path_cost(map: GameMap, unit: Unit, path: Array[Vector2i]) -> int:
	var total := 0
	for cell in path:
		total += step_cost(map, unit, cell)
	return total


static func can_enter(map: GameMap, unit: Unit, cell: Vector2i, occupants: Dictionary) -> bool:
	if not map.is_in_bounds(cell) or not Terrain.is_walkable(map.get_terrain(cell)):
		return false
	var occupant: Unit = occupants.get(cell)
	return occupant == null or occupant.owner_player == unit.owner_player


## Busca pelo menor custo (Dijkstra com "baldes": buckets[c] = casas
## alcançadas gastando c movimentos). Para em [param target], se houver.
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
			for direction in DIRECTIONS:
				var next := cell + direction
				if not can_enter(map, unit, next, occupants):
					continue
				var next_cost := current + step_cost(map, unit, next)
				if next_cost > budget or (cost.has(next) and cost[next] <= next_cost):
					continue
				cost[next] = next_cost
				came_from[next] = cell
				while buckets.size() <= next_cost:
					buckets.append([])
				buckets[next_cost].append(next)
		current += 1
	return came_from
