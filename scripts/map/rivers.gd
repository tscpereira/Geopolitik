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
## DESENHO (draw), no estilo do rio do Civilization do SNES: três camadas ao
## longo de uma curva suavizada que ondula em volta das bordas: a margem de
## areia (a mesma cor da praia da costa), uma faixa azul mais escura nas bordas
## da água e a água mais clara no meio. Ponta fina na nascente. Na foz, o rio
## se abre em leque e a cor se mistura à do mar até sumir (a areia some
## antes, junto da praia): ele se integra ao oceano em vez de entrar nele.

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

## Desenho, em frações do tamanho da casa. Meia largura da água na nascente e
## na foz (antes do leque).
const HALF_WIDTH_SOURCE := 0.055
const HALF_WIDTH_MOUTH := 0.12
## Margem de areia além da água, e a borda suave (esmaecida) de cada camada.
const SAND_EXTRA := 0.05
const FEATHER := 0.03
const SAND_FEATHER := 0.05
## Água clara do meio, em fração da largura da água.
const LIGHT_SHARE := 0.55
const WOBBLE := 0.15
## Até onde o desenho avança mar adentro, em fração do caminho do último canto
## até o centro das casas de água em volta dele.
const MOUTH_REACH := 0.55
## Trecho final (em casas) em que o rio se abre em leque, e quanto ele alarga.
const ESTUARY_LENGTH := 1.4
const ESTUARY_WIDEN := 2.6
## Trecho inicial (em casas) em que a nascente afina até uma ponta, e em que
## ela aparece aos poucos.
const SOURCE_TAPER := 0.9
const SOURCE_FADE := 0.3
## Trecho final em que a água some no mar e em que a areia some na praia.
const WATER_FADE := 0.5
const SAND_FADE_START := 0.35
const SAND_FADE := 0.4
## Cores: areia da margem (a da praia do shader do terreno, um pouco mais
## escura), azul escuro das bordas, azul claro do meio e o azul do mar raso.
const SAND_COLOR := Color(0.72, 0.65, 0.45)
const DARK_WATER_COLOR := Color(0.18, 0.33, 0.46)
const LIGHT_WATER_COLOR := Color(0.36, 0.57, 0.68)
const SEA_COLOR := Color(0.23, 0.38, 0.49)

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
		var river: Array = rivers[index]
		var points := _curve(map, river, cell_size, origin, index)
		if points.size() < 2:
			continue
		var is_mouth := not _all_land_around(map, river[-1]) # termina no mar (não noutro rio)
		# Comprimento acumulado (em casas) e a direção para os lados em cada ponto
		var along := PackedFloat32Array([0.0])
		for i in range(1, points.size()):
			along.append(along[i - 1] + points[i].distance_to(points[i - 1]) / cell_size)
		var total := along[along.size() - 1]
		var normals := PackedVector2Array()
		var water := PackedFloat32Array() # meia largura da água em cada ponto
		var water_alpha := PackedFloat32Array()
		var sand_alpha := PackedFloat32Array()
		var sea_mix := PackedFloat32Array()
		for i in points.size():
			var before := points[maxi(i - 1, 0)]
			var after := points[mini(i + 1, points.size() - 1)]
			normals.append((after - before).orthogonal().normalized())
			var half := lerpf(HALF_WIDTH_SOURCE, HALF_WIDTH_MOUTH, along[i] / total)
			var taper := smoothstep(0.0, SOURCE_TAPER, along[i]) # nascente: afina até uma ponta
			half *= lerpf(0.15, 1.0, taper)
			var appear := clampf(along[i] / SOURCE_FADE, 0.0, 1.0)
			var tail := total - along[i] # quanto falta até o fim (em casas)
			var estuary := clampf(1.0 - tail / ESTUARY_LENGTH, 0.0, 1.0) if is_mouth else 0.0
			water.append(half * (1.0 + ESTUARY_WIDEN * estuary * estuary) * cell_size)
			water_alpha.append(appear * (clampf(tail / WATER_FADE, 0.0, 1.0) if is_mouth else 1.0))
			sand_alpha.append(appear * (clampf((tail - SAND_FADE_START) / SAND_FADE, 0.0, 1.0) if is_mouth else 1.0))
			sea_mix.append(estuary)
		# Três camadas, de fora para dentro: areia, água escura e água clara
		var sand_sizes := PackedFloat32Array()
		var light_sizes := PackedFloat32Array()
		var sand_colors := PackedColorArray()
		var dark_colors := PackedColorArray()
		var light_colors := PackedColorArray()
		for i in points.size():
			# A margem também afina na nascente (senão a areia fica com a ponta grossa)
			sand_sizes.append(water[i] + SAND_EXTRA * cell_size * lerpf(0.3, 1.0, smoothstep(0.0, SOURCE_TAPER, along[i])))
			light_sizes.append(water[i] * LIGHT_SHARE)
			sand_colors.append(Color(SAND_COLOR, sand_alpha[i]))
			dark_colors.append(Color(DARK_WATER_COLOR.lerp(SEA_COLOR, sea_mix[i]), water_alpha[i]))
			light_colors.append(Color(LIGHT_WATER_COLOR.lerp(SEA_COLOR, sea_mix[i]), water_alpha[i]))
		_strip(canvas, points, normals, sand_sizes, sand_colors, SAND_FEATHER * cell_size)
		_strip(canvas, points, normals, water, dark_colors, FEATHER * cell_size)
		_strip(canvas, points, normals, light_sizes, light_colors, FEATHER * cell_size * 1.5)


## Uma faixa ao longo da curva: meia largura [param sizes] e cor [param colors]
## em cada ponto, com a borda esmaecendo até transparente em [param feather]
## pixels (fica suave, sem serrilhado). Desenhada como uma malha de triângulos
## com cor por vértice (degradê na foz).
static func _strip(canvas: CanvasItem, points: PackedVector2Array, normals: PackedVector2Array,
		sizes: PackedFloat32Array, colors: PackedColorArray, feather: float) -> void:
	var vertices := PackedVector2Array()
	var vertex_colors := PackedColorArray()
	for i in points.size():
		var clear := Color(colors[i], 0.0)
		var side := normals[i]
		# 4 vértices por ponto: borda de fora, borda de dentro (dos dois lados)
		vertices.append(points[i] - side * (sizes[i] + feather))
		vertices.append(points[i] - side * sizes[i])
		vertices.append(points[i] + side * sizes[i])
		vertices.append(points[i] + side * (sizes[i] + feather))
		vertex_colors.append_array([clear, colors[i], colors[i], clear])
	var indices := PackedInt32Array()
	for i in points.size() - 1:
		var a := i * 4
		var b := a + 4
		for k in 3: # as três tiras: borda esquerda, miolo, borda direita
			indices.append_array([a + k, a + k + 1, b + k, a + k + 1, b + k + 1, b + k])
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, vertex_colors)


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
		corners.append(mouth.lerp(water / count, MOUTH_REACH))
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
