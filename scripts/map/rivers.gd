class_name Rivers
extends RefCounted

## Rios do mapa: correm pelas BORDAS das casas (no limiar entre uma casa e
## outra), de um canto da grade ao próximo. Cada rio é a lista dos cantos por
## onde ele passa: o canto (x, y) é o canto de cima à esquerda da casa (x, y).
## Toda casa que encosta num trecho de rio ganha Terrain.RIVER_FOOD de alimento
## (ver GameMap.has_river).
##
## GERAÇÃO (generate): o mapa de data/maps/ só tem os terrenos, então os rios
## são criados ao montar o mapa, sempre iguais para o mesmo mapa (semente fixa).
## Cada rio nasce no interior, longe da costa, e desce em direção ao mar pela
## distância até a água, com desvios para os lados (fica sinuoso). Termina ao
## chegar à costa ou ao encontrar outro rio (afluente). Só corre entre casas de
## terra; o save guarda os rios.
##
## DESENHO (draw): curva suavizada que ondula um pouco em volta das bordas,
## estreita na nascente e mais larga na foz, entrando um pouco no mar.

## Quantos rios o gerador tenta criar e o tamanho mínimo de cada um (trechos).
const RIVER_COUNT := 8
const MIN_LENGTH := 8
const MAX_LENGTH := 90
## Distância mínima (em cantos) da nascente até a costa. As nascentes mais
## longe da costa são tentadas primeiro (rios mais compridos).
const SOURCE_MIN_DISTANCE := 5
## Distância mínima entre a nascente e qualquer outro rio.
const SOURCE_SPACING := 7
## Semente do gerador (o mesmo mapa sempre tem os mesmos rios).
const SEED := 20261024
## Peso de cada passo pela mudança na distância até a costa: descer é o normal,
## andar de lado faz as curvas, subir é raro.
const STEP_WEIGHTS := {-1: 3.0, 0: 1.4, 1: 0.2}

## Desenho, em frações do tamanho da casa.
const WIDTH_SOURCE := 0.09
const WIDTH_MOUTH := 0.22
const BANK_EXTRA := 0.05
const WOBBLE := 0.15
const MOUTH_REACH := 0.4
const WATER_COLOR := Color(0.27, 0.43, 0.49)
const BANK_COLOR := Color(0.35, 0.36, 0.23)
const SHINE_COLOR := Color(0.72, 0.84, 0.86, 0.25)

const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Cria os rios do mapa (ver o topo). Retorna [[canto, canto, ...], ...].
static func generate(map: GameMap) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + map.width * 1000 + map.height
	var distance := _coast_distance(map)
	var sources: Array[Vector2i] = []
	for corner: Vector2i in distance:
		if distance[corner] >= SOURCE_MIN_DISTANCE and _all_land_around(map, corner):
			sources.append(corner)
	# Mais longe da costa primeiro; entre as de mesma distância, sorteio (estável)
	var order := {}
	sources.sort()
	for corner in sources:
		order[corner] = rng.randf()
	sources.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return distance[a] > distance[b] or (distance[a] == distance[b] and order[a] < order[b]))

	var rivers: Array = []
	var used := {} # cantos que já são de algum rio
	for source in sources:
		if rivers.size() >= RIVER_COUNT:
			break
		if _near_used(source, used, SOURCE_SPACING):
			continue
		var river := _walk(map, source, distance, used, rng)
		if river.size() > MIN_LENGTH:
			rivers.append(river)
			for corner in river:
				used[corner] = true
	return rivers


## Um rio a partir da nascente: a cada passo escolhe (com sorteio pelos
## STEP_WEIGHTS) um canto vizinho ligado por uma borda entre duas casas de
## terra, sem encostar no próprio caminho. Para na costa ou num outro rio.
## Retorna [] se ficar sem saída.
static func _walk(map: GameMap, source: Vector2i, distance: Dictionary, used: Dictionary,
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var path: Array[Vector2i] = [source]
	var in_path := {source: true}
	while path.size() <= MAX_LENGTH:
		var current: Vector2i = path[-1]
		if distance[current] == 0 or (used.has(current) and current != source):
			return path # chegou ao mar ou desaguou em outro rio
		var options: Array[Vector2i] = []
		var weights: Array[float] = []
		for step in STEPS:
			var next := current + step
			if not distance.has(next) or in_path.has(next) or not _is_land_edge(map, current, next):
				continue
			if _touches_path(next, current, in_path):
				continue
			var change: int = clampi(distance[next] - distance[current], -1, 1)
			var weight: float = STEP_WEIGHTS[change]
			if used.has(next):
				weight *= 4.0 # perto de outro rio: deságua nele
			options.append(next)
			weights.append(weight)
		if options.is_empty():
			return []
		var pick := _weighted(options, weights, rng)
		path.append(pick)
		in_path[pick] = true
	return []


## Distância (em passos pelos cantos) de cada canto até a costa: 0 = canto que
## encosta numa casa de água (ou na borda do mapa).
static func _coast_distance(map: GameMap) -> Dictionary:
	var distance := {}
	var queue: Array[Vector2i] = []
	for y in map.height + 1:
		for x in map.width + 1:
			var corner := Vector2i(x, y)
			if not _all_land_around(map, corner):
				distance[corner] = 0
				queue.append(corner)
	var head := 0
	while head < queue.size():
		var corner := queue[head]
		head += 1
		for step in STEPS:
			var next := corner + step
			if next.x < 0 or next.y < 0 or next.x > map.width or next.y > map.height or distance.has(next):
				continue
			distance[next] = distance[corner] + 1
			queue.append(next)
	return distance


## As 4 casas em volta do canto (a de cima à esquerda é a casa corner - (1, 1)).
static func cells_around(corner: Vector2i) -> Array[Vector2i]:
	return [corner + Vector2i(-1, -1), corner + Vector2i(0, -1), corner + Vector2i(-1, 0), corner]


static func _all_land_around(map: GameMap, corner: Vector2i) -> bool:
	for cell in cells_around(corner):
		if not map.is_in_bounds(cell) or map.get_terrain(cell) == Terrain.Type.WATER:
			return false
	return true


## As duas casas dos lados da borda entre os cantos [param a] e [param b].
static func edge_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var low := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	if a.y == b.y: # borda horizontal: casa de cima e casa de baixo
		return [low + Vector2i(0, -1), low]
	return [low + Vector2i(-1, 0), low] # borda vertical: esquerda e direita


static func _is_land_edge(map: GameMap, a: Vector2i, b: Vector2i) -> bool:
	for cell in edge_cells(a, b):
		if not map.is_in_bounds(cell) or map.get_terrain(cell) == Terrain.Type.WATER:
			return false
	return true


## Se o canto encosta no caminho (fora o canto de onde veio): evita que o rio
## dê voltas coladas nele mesmo.
static func _touches_path(corner: Vector2i, came_from: Vector2i, in_path: Dictionary) -> bool:
	for step in STEPS:
		var other := corner + step
		if other != came_from and in_path.has(other):
			return true
	return false


static func _near_used(corner: Vector2i, used: Dictionary, spacing: int) -> bool:
	for other: Vector2i in used:
		if absi(other.x - corner.x) + absi(other.y - corner.y) < spacing:
			return true
	return false


static func _weighted(options: Array[Vector2i], weights: Array[float], rng: RandomNumberGenerator) -> Vector2i:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[-1]


# --- Desenho ------------------------------------------------------------------

## Desenha os rios em [param canvas]: o canto (x, y) fica em
## [param origin] + (x, y) * [param cell_size]. Usado pelo mapa (RiverLayer no
## GameMap) e pela janela da cidade.
static func draw(canvas: CanvasItem, map: GameMap, rivers: Array, cell_size: float, origin := Vector2.ZERO) -> void:
	for index in rivers.size():
		var points := _curve(map, rivers[index], cell_size, origin, index)
		if points.size() < 2:
			continue
		# Margem e água; a largura cresce até a foz
		for layer in 2:
			var chunk := PackedVector2Array()
			var steps := 6
			for i in points.size():
				chunk.append(points[i])
				if (chunk.size() > steps or i == points.size() - 1) and chunk.size() >= 2:
					var t := float(i) / (points.size() - 1)
					var width := lerpf(WIDTH_SOURCE, WIDTH_MOUTH, t) * cell_size
					# Os pedaços têm larguras diferentes: um círculo no começo de cada
					# um tapa a emenda nas curvas
					match layer:
						0:
							canvas.draw_circle(chunk[0], (width + BANK_EXTRA * cell_size) / 2.0, BANK_COLOR)
							canvas.draw_polyline(chunk, BANK_COLOR, width + BANK_EXTRA * cell_size, true)
						1:
							canvas.draw_circle(chunk[0], width / 2.0, WATER_COLOR)
							canvas.draw_polyline(chunk, WATER_COLOR, width, true)
					chunk = PackedVector2Array([points[i]])
		# Reflexo claro no meio, numa linha só (transparente: emendas apareceriam)
		canvas.draw_polyline(points, SHINE_COLOR, (WIDTH_SOURCE + WIDTH_MOUTH) / 2.0 * cell_size * 0.3, true)


## Pontos da curva do rio: os cantos (a foz avança um pouco para o mar),
## suavizados (Chaikin) e com uma ondulação leve para os lados.
static func _curve(map: GameMap, river: Array, cell_size: float, origin: Vector2, index: int) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for corner: Vector2i in river:
		corners.append(origin + Vector2(corner) * cell_size)
	# Foz: segue até a água em volta do último canto
	var last: Vector2i = river[-1]
	var water := Vector2.ZERO
	var count := 0
	for cell in cells_around(last):
		if map.is_in_bounds(cell) and map.get_terrain(cell) == Terrain.Type.WATER:
			water += origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
			count += 1
	if count > 0:
		var mouth := corners[corners.size() - 1]
		corners.append(mouth.lerp(water / count, MOUTH_REACH * 2.0))
	var points := corners
	for i in 4:
		points = _chaikin(points)
	# Ondulação: desloca para os lados com duas senoides (nada na nascente e na foz)
	var result := PackedVector2Array()
	var length := 0.0
	for i in points.size():
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var normal := (after - before).orthogonal().normalized()
		var s := length / cell_size
		var fade := minf(1.0, minf(float(i), float(points.size() - 1 - i)) / 12.0)
		var wave := sin(s * 1.7 + index * 1.7) * 0.65 + sin(s * 3.9 + index * 3.1) * 0.35
		result.append(points[i] + normal * wave * WOBBLE * cell_size * fade)
	return result


## Um passo do algoritmo de Chaikin: corta os cantos da linha (as pontas ficam).
static func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	for i in points.size() - 1:
		result.append(points[i].lerp(points[i + 1], 0.25))
		result.append(points[i].lerp(points[i + 1], 0.75))
	result.append(points[points.size() - 1])
	return result
