extends SceneTree

## Gera o mapa "tres_continentes" (29/10/2026): data/maps/tres_continentes.png
## (1 pixel por casa, cores de Terrain.COLORS) e tres_continentes_recursos.json
## (ferro, os 6 jogadores e a câmera). Sempre o mesmo mapa (sementes fixas).
## Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/mapas/gera_tres_continentes.gd
##
## - Três continentes separados por mar (o jogo transforma o mar longe da costa
##   em Águas Profundas): o do OESTE, alto, vai do norte ao sul; o do NORDESTE,
##   mais frio; o do SUDESTE, mais quente. DOIS jogadores em cada (desde
##   30/10/2026, pedido do usuário: 6 nações; antes, um).
## - Terreno pelo ruído: relevo (colinas e cordilheiras), umidade (floresta e
##   cerrado) e latitude (neve e tundra no norte, deserto e selva no sul), mais
##   alguns lagos. Os rios o jogo gera ao montar o mapa (Rivers).
## - Casas iniciais: em cada continente, a que tem mais pradaria em volta
##   (perto do meio) e a segunda, a pelo menos MIN_START_DISTANCE casas da
##   primeira (quanto mais longe, melhor); o terreno em volta é ajeitado (sem
##   montanha, pelo menos 12 casas de pradaria ou cerrado) e há sempre uma
##   colina com ferro perto. O primeiro jogador (oeste) é o humano; a tela de
##   início do jogo troca nomes e cores pelos das nações.

const NAME := "tres_continentes"
const MAPS := "res://data/maps/"
const SIZE := Vector2i(140, 90)
const SEED := 291026

## Continentes: centro e raios (em casas).
const CONTINENTS := [
	{"center": Vector2(31, 46), "radius": Vector2(20, 33)},
	{"center": Vector2(99, 22), "radius": Vector2(31, 14)},
	{"center": Vector2(101, 68), "radius": Vector2(29, 15)},
]
## Jogadores por continente e a distância mínima entre as casas iniciais
## do mesmo continente.
const PLAYERS_PER_CONTINENT := 2
const MIN_START_DISTANCE := 14
## Cores dos jogadores no JSON (sem a tela de início: testes e ferramentas).
const PLAYER_COLORS := ["dc2828", "fadc28", "a050dc", "2860dc", "28a050", "f08c28"]
## O mar entre dois continentes: uma casa só é terra se, para os outros, a
## distância normalizada passar de GAP.
const GAP := 1.3

var _terrain: Array = []
var _shape: FastNoiseLite
var _elevation: FastNoiseLite
var _moisture: FastNoiseLite
var _lakes: FastNoiseLite
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = SEED
	_shape = _noise(SEED + 1, 0.06)
	_elevation = _noise(SEED + 2, 0.07, 3)
	_moisture = _noise(SEED + 3, 0.07)
	_lakes = _noise(SEED + 4, 0.12)
	var T := Terrain.Type
	for y in SIZE.y:
		var row := []
		for x in SIZE.x:
			row.append(T.WATER)
		_terrain.append(row)

	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2(x, y)
			var own := -1
			for i in CONTINENTS.size():
				if _distance(i, p) < 1.0:
					own = i
			if own < 0:
				continue
			var too_close := false
			for i in CONTINENTS.size():
				if i != own and _distance(i, p) < GAP:
					too_close = true
			if not too_close:
				_terrain[y][x] = _land_type(p, _distance(own, p))

	var players := []
	var iron := {}
	for i in CONTINENTS.size():
		var placed: Array[Vector2i] = []
		for k in PLAYERS_PER_CONTINENT:
			var start := _pick_start(i, placed)
			placed.append(start)
			_prepare_start(start)
			var number := players.size() + 1
			players.append({"nome": "Jogador %d" % number, "cor": PLAYER_COLORS[(number - 1) % PLAYER_COLORS.size()],
					"maquina": number > 1, "inicio": [start.x, start.y]})
			iron[_iron_near(start)] = true
	# Mais ferro: algumas colinas sorteadas (1 em 12)
	for y in SIZE.y:
		for x in SIZE.x:
			if _terrain[y][x] == T.HILLS and _rng.randf() < 0.08:
				iron[Vector2i(x, y)] = true

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	var counts := {}
	for y in SIZE.y:
		for x in SIZE.x:
			image.set_pixel(x, y, Terrain.COLORS[_terrain[y][x]])
			counts[_terrain[y][x]] = counts.get(_terrain[y][x], 0) + 1
	image.save_png(ProjectSettings.globalize_path(MAPS + NAME + ".png"))
	var iron_list := []
	for cell: Vector2i in iron:
		iron_list.append([cell.x, cell.y])
	iron_list.sort()
	var info := {
		"_leia": "Mapa gerado por tools/mapas/gera_tres_continentes.gd (não edite à mão: rode o gerador). ferro: colinas [x, y]; jogadores: nome, cor (hex), maquina (IA) e a casa inicial do Colono; camera: casa onde a câmera começa.",
		"ferro": iron_list,
		"jogadores": players,
		"camera": players[0]["inicio"],
	}
	var file := FileAccess.open(ProjectSettings.globalize_path(MAPS + NAME + "_recursos.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "\t", false))
	file.close()
	for type: int in counts:
		print("  %-16s %d" % [Terrain.NAMES[type], counts[type]])
	for player: Dictionary in players:
		print("  %s em %s" % [player["nome"], player["inicio"]])
	print("ferro: %d colinas" % iron_list.size())
	quit()


func _noise(seed: int, frequency: float, octaves := 4) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


## 0 a 1.
func _value(noise: FastNoiseLite, p: Vector2) -> float:
	return noise.get_noise_2dv(p) * 0.5 + 0.5


## Distância normalizada ao centro do continente (1 = a costa), com o ruído
## que recorta a costa (baías e penínsulas).
func _distance(i: int, p: Vector2) -> float:
	var c: Dictionary = CONTINENTS[i]
	var d: float = ((p - c["center"]) / c["radius"]).length()
	return d + (_value(_shape, p + Vector2(i * 300, 0)) - 0.5) * 0.7


func _land_type(p: Vector2, d: float) -> Terrain.Type:
	var T := Terrain.Type
	# 0 = norte, 1 = sul; ondulada pelo ruído (as faixas de clima não ficam retas)
	var latitude := p.y / SIZE.y + (_value(_lakes, p * 0.4 + Vector2(500, 0)) - 0.5) * 0.12
	var elevation := _value(_elevation, p)
	var moisture := _value(_moisture, p)
	if d < 0.7 and _value(_lakes, p) > 0.78:
		return T.WATER # lago
	if elevation > 0.74 and d < 0.85:
		return T.MOUNTAINS
	if elevation > 0.67:
		return T.HILLS
	if moisture > 0.6:
		return T.JUNGLE if latitude > 0.7 else T.FOREST
	if latitude < 0.15:
		return T.SNOW
	if latitude < 0.24:
		return T.TUNDRA
	if moisture < 0.36:
		return T.DESERT if latitude > 0.72 else T.CERRADO
	return T.GRASSLAND


## Casa inicial: perto do meio do continente (até 0,45 do raio), a que tem
## mais pradaria e cerrado na área da capital (5x5 sem os cantos).
## Casa inicial no continente [param i], longe das já escolhidas
## ([param placed]): a primeira perto do meio (até 0,45 do raio); as outras
## até 0,75 do raio, a pelo menos MIN_START_DISTANCE casas e, quanto mais
## longe, melhor.
func _pick_start(i: int, placed: Array[Vector2i]) -> Vector2i:
	var best := Vector2i(CONTINENTS[i]["center"])
	var best_score := -INF
	var reach := 0.45 if placed.is_empty() else 0.75
	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2(x, y)
			if _distance(i, p) > reach or _terrain[y][x] != Terrain.Type.GRASSLAND:
				continue
			var nearest := INF
			for other in placed:
				nearest = minf(nearest, Vector2(other).distance_to(p))
			if nearest < MIN_START_DISTANCE:
				continue
			var score := 0.0
			for offset in City.area_offsets():
				var t: int = _at(Vector2i(x, y) + offset)
				if t == Terrain.Type.GRASSLAND or t == Terrain.Type.CERRADO:
					score += 1.0
				elif t == Terrain.Type.FOREST or t == Terrain.Type.HILLS:
					score += 0.5 # madeira e ferro por perto também valem
			if placed.is_empty():
				score -= (p - CONTINENTS[i]["center"]).length() * 0.05
			else:
				score += minf(nearest, 24.0) * 0.15 # o vizinho bem longe
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	return best


## Ajeita a área da capital: montanha, água e neve viram pradaria, e se houver
## menos de 12 casas de pradaria ou cerrado, as primeiras outras viram pradaria.
func _prepare_start(start: Vector2i) -> void:
	var T := Terrain.Type
	var open := 0
	for offset in City.area_offsets():
		var cell := start + offset
		var t: int = _at(cell)
		if t in [T.MOUNTAINS, T.WATER, T.SNOW, T.DEEP_WATER]:
			_terrain[cell.y][cell.x] = T.GRASSLAND
			t = T.GRASSLAND
		if t == T.GRASSLAND or t == T.CERRADO:
			open += 1
	for offset in City.area_offsets():
		if open >= 12:
			break
		var cell := start + offset
		if _terrain[cell.y][cell.x] in [T.DESERT, T.TUNDRA, T.JUNGLE]:
			_terrain[cell.y][cell.x] = T.GRASSLAND
			open += 1
	_terrain[start.y][start.x] = T.GRASSLAND


## Colina com ferro perto da casa inicial: a mais próxima (até 7 casas) fora
## da casa da cidade; sem nenhuma, uma pradaria a 3 casas vira colina.
func _iron_near(start: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(start.y - 7, start.y + 8):
		for x in range(start.x - 7, start.x + 8):
			var cell := Vector2i(x, y)
			if cell != start and _at(cell) == Terrain.Type.HILLS:
				var distance := Vector2(cell - start).length()
				if distance < best_distance:
					best_distance = distance
					best = cell
	if best.x < 0:
		best = start + Vector2i(3, 2)
		_terrain[best.y][best.x] = Terrain.Type.HILLS
	return best


func _at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE.x or cell.y >= SIZE.y:
		return Terrain.Type.WATER
	return _terrain[cell.y][cell.x]
