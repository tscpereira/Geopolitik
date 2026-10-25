class_name GameMap
extends Node2D

## Mapa em grid quadrado. Guarda o terreno de cada casa (e a madeira das
## florestas) e desenha o mapa inteiro com o shader terrain.gdshader, que faz
## as transições naturais entre os terrenos (costa arredondada, borda das
## florestas, pradaria <-> cerrado, relevo das colinas e montanhas visto de
## cima) e as fazendas (set_improvement). Os rios
## (Rivers) correm pelas bordas das casas e são desenhados por cima do terreno
## (RiverLayer). O TileMapLayer só serve para converter posições em casas.

## Tamanho de cada casa em pixels. As imagens dos terrenos devem ter este tamanho.
## (80 desde 23/10/2026; antes 40, em pixel art.)
const TILE_SIZE := 80
## Desenha uma linha de grade (borda escurecida) por cima de cada casa.
const DRAW_GRID := true
## Escurecimento da borda de cada casa, para formar a grade.
const GRID_LINE_DARKEN := 0.15
const TERRAIN_SHADER: Shader = preload("res://scripts/map/terrain.gdshader")
## Pontos de obra de uma estrada (o Trabalhador faz Game.REBUILD_PER_TURN por turno).
const ROAD_COST := 2
## Desenho da estrada: terra batida com a borda mais escura (larguras em casas).
const ROAD_EDGE_COLOR := Color8(96, 74, 46)
const ROAD_COLOR := Color8(176, 148, 100)
const ROAD_EDGE_WIDTH := 0.2
const ROAD_WIDTH := 0.13
## Estrada em obra: mais transparente.
const ROAD_IN_PROGRESS_ALPHA := 0.4

## Melhoria desenhada pelo shader numa casa (ver set_improvement).
enum Improvement { NONE, FARM, FARM_IN_PROGRESS }
## Nome de cada textura de terreno no shader.
const SHADER_TEXTURES := {
	Terrain.Type.WATER: "water_tex",
	Terrain.Type.GRASSLAND: "grass_tex",
	Terrain.Type.FOREST: "forest_tex",
	Terrain.Type.CERRADO: "cerrado_tex",
	Terrain.Type.HILLS: "hill_tex",
	Terrain.Type.MOUNTAINS: "mountain_tex",
}

var width := 0
var height := 0
## Dono de cada casa com cidade: {casa: Player}. Mantido pelo Game
## (refresh_territories); o Movement usa para as regras de invasão.
var city_owners := {}
## Cidade em cada casa com cidade: {casa: City}. Também mantido pelo Game; a
## unidade usa para a defesa da Muralha (Unit.walls_defense_bonus).
var cities := {}

## Casas com ferro (recurso estratégico; só em colinas): {casa: true}. Vêm do
## arquivo de recursos do mapa (load_resources) e do save. A bigorna aparece
## no canto delas (ResourceLayer; onde há mina, a cidade a desenha de novo por
## cima da mina), só quando iron_visible (o jogador humano tem Trabalho em
## Ferro; o Game atualiza).
var iron := {}
var iron_visible := false:
	set(value):
		if value != iron_visible:
			iron_visible = value
			if _resource_layer:
				_resource_layer.queue_redraw()
var _resource_layer: Node2D

## Estradas prontas: {casa: true}. Obras de estrada: {casa: pontos feitos}
## (ROAD_COST). Feitas pelo Trabalhador (Game.build_road); a cidade também
## conta como estrada (has_road). De estrada para estrada, o passo custa meio
## movimento (Movement.step_cost).
var roads := {}
var road_progress := {}
var _road_layer: Node2D

var _terrain := PackedByteArray()
## Rios: cada um é a lista dos cantos da grade por onde passa (ver Rivers).
var rivers: Array = []
## Madeira que resta nas florestas já exploradas: {casa: quantidade}. Casa de
## floresta fora daqui ainda tem Terrain.WOOD_PER_FOREST.
var _wood := {}
## Casas que encostam num rio: {casa: true} (ver has_river).
var _river_cells := {}
## Bordas com rio entre duas casas vizinhas: {_edge_key(a, b): true}.
var _river_edges := {}
var _river_layer: Node2D
## Imagem de cada terreno, usada pelo shader e pela janela da cidade.
var _terrain_textures := {}
## Mapa de terrenos para o shader: 1 pixel por casa, tipo no canal vermelho.
var _terrain_image: Image
var _terrain_map: ImageTexture
var _view: Sprite2D
## Melhorias para o shader (fazendas): 1 pixel por casa, Improvement no vermelho.
var _improvement_image: Image
var _improvement_map: ImageTexture

@onready var _layer: TileMapLayer = $TerrainLayer


func _ready() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_layer.tile_set = tile_set
	for type: Terrain.Type in Terrain.TEXTURE_PATHS:
		var image := _load_tile_image(type)
		image.generate_mipmaps() # filtro suave também com o zoom afastado
		_terrain_textures[type] = ImageTexture.create_from_image(image)
	_view = Sprite2D.new()
	_view.name = "TerrainView"
	_view.centered = false
	_view.scale = Vector2.ONE * TILE_SIZE
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	for type: Terrain.Type in SHADER_TEXTURES:
		material.set_shader_parameter(SHADER_TEXTURES[type], _terrain_textures[type])
	material.set_shader_parameter("farm_tex", City.FARM_TEXTURE)
	material.set_shader_parameter("farm_new_tex", City.FARM_NEW_TEXTURE)
	material.set_shader_parameter("draw_grid", DRAW_GRID)
	material.set_shader_parameter("grid_darken", GRID_LINE_DARKEN)
	_view.material = material
	add_child(_view)
	move_child(_view, 0)
	# Rios por cima do terreno (e das fazendas, que o shader pinta)
	_river_layer = Node2D.new()
	_river_layer.name = "RiverLayer"
	_river_layer.draw.connect(func() -> void: Rivers.draw(_river_layer, self, rivers, TILE_SIZE))
	add_child(_river_layer)
	move_child(_river_layer, 1)
	# Estradas por cima do terreno e por baixo dos rios
	_road_layer = Node2D.new()
	_road_layer.name = "RoadLayer"
	_road_layer.draw.connect(_draw_roads)
	add_child(_road_layer)
	move_child(_road_layer, 1)
	# Bigornas das casas com ferro, por cima dos rios
	_resource_layer = Node2D.new()
	_resource_layer.name = "ResourceLayer"
	_resource_layer.draw.connect(_draw_resources)
	add_child(_resource_layer)
	move_child(_resource_layer, 3)


## Monta o mapa a partir de uma imagem: cada pixel vira uma casa.
func load_from_image(image: Image) -> void:
	if image.is_compressed():
		image.decompress()
	width = image.get_width()
	height = image.get_height()
	_terrain.resize(width * height)
	_terrain_image = Image.create(width, height, false, Image.FORMAT_R8)
	for y in height:
		for x in width:
			_terrain[y * width + x] = Terrain.from_color(image.get_pixel(x, y))
			_terrain_image.set_pixel(x, y, Color8(_terrain[y * width + x], 0, 0))
	_terrain_map = ImageTexture.create_from_image(_terrain_image)
	_view.texture = _terrain_map
	var material := _view.material as ShaderMaterial
	material.set_shader_parameter("terrain_map", _terrain_map)
	_improvement_image = Image.create(width, height, false, Image.FORMAT_R8)
	_improvement_map = ImageTexture.create_from_image(_improvement_image)
	material.set_shader_parameter("improvement_map", _improvement_map)
	material.set_shader_parameter("map_size", Vector2(width, height))
	set_rivers(Rivers.generate(self))


## Lê os recursos estratégicos do mapa de um JSON ({"ferro": [[x, y], ...]}).
## Ferro fora das colinas é ignorado (com um aviso no Output).
func load_resources(path: String) -> void:
	iron = {}
	if not FileAccess.file_exists(path):
		_resource_layer.queue_redraw()
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("%s não é um JSON válido." % path)
		return
	for entry: Array in data.get("ferro", []):
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if is_in_bounds(cell) and get_terrain(cell) == Terrain.Type.HILLS:
			iron[cell] = true
		else:
			push_warning("Ferro em %s ignorado: o ferro só aparece em colinas." % cell)
	_resource_layer.queue_redraw()


func has_iron(cell: Vector2i) -> bool:
	return iron.has(cell)


func iron_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(iron.keys())
	return cells


## Se a casa tem estrada pronta (ou é uma cidade).
func has_road(cell: Vector2i) -> bool:
	return roads.has(cell) or cities.has(cell)


## Começa (ou continua) a obra da estrada na casa.
func start_road(cell: Vector2i) -> void:
	if not road_progress.has(cell):
		road_progress[cell] = 0
	redraw_roads()


## +[param points] na obra da estrada. Retorna true se ela ficou pronta.
func add_road_progress(cell: Vector2i, points: int) -> bool:
	road_progress[cell] += points
	if road_progress[cell] < ROAD_COST:
		redraw_roads()
		return false
	road_progress.erase(cell)
	roads[cell] = true
	redraw_roads()
	return true


## Redesenha as estradas (também quando uma cidade nasce ou some: ela liga as
## estradas vizinhas).
func redraw_roads() -> void:
	_road_layer.queue_redraw()


## Estradas: de cada casa com estrada (pronta ou em obra) um trecho até o
## centro de cada vizinha com estrada ou cidade, nas 8 direções; casa sem
## vizinha, um trecho curto de terra. Em obra, mais transparente.
func _draw_roads() -> void:
	for layer in 2: # primeiro as bordas escuras, depois o miolo
		var color := ROAD_EDGE_COLOR if layer == 0 else ROAD_COLOR
		var width := (ROAD_EDGE_WIDTH if layer == 0 else ROAD_WIDTH) * TILE_SIZE
		for cell: Vector2i in roads.keys() + road_progress.keys():
			var alpha := 1.0 if roads.has(cell) else ROAD_IN_PROGRESS_ALPHA
			var center := (Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE
			var tint := Color(color, alpha)
			var linked := false
			for direction: Vector2i in Movement.DIRECTIONS:
				var other := cell + direction
				if roads.has(other) or road_progress.has(other) or cities.has(other):
					var other_alpha := alpha if roads.has(other) or cities.has(other) else ROAD_IN_PROGRESS_ALPHA
					_road_layer.draw_line(center, center + Vector2(direction) * TILE_SIZE * 0.5, Color(color, minf(alpha, other_alpha)), width, true)
					linked = true
			if not linked:
				_road_layer.draw_line(center - Vector2(TILE_SIZE * 0.3, 0), center + Vector2(TILE_SIZE * 0.3, 0), tint, width, true)
			_road_layer.draw_circle(center, width * 0.5, tint)


## Bigorna no canto de cada casa com ferro (Icons.draw_iron_marker).
func _draw_resources() -> void:
	if not iron_visible:
		return
	for cell: Vector2i in iron:
		Icons.draw_iron_marker(_resource_layer, Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE))


## Troca os rios do mapa (gerados ou de um save) e redesenha.
func set_rivers(new_rivers: Array) -> void:
	rivers = new_rivers
	_river_cells = {}
	_river_edges = {}
	for river: Array in rivers:
		for i in river.size() - 1:
			var sides := Rivers.edge_cells(river[i], river[i + 1])
			_river_edges[_edge_key(sides[0], sides[1])] = true
			for cell in sides:
				if is_in_bounds(cell):
					_river_cells[cell] = true
	_river_layer.queue_redraw()


## Se andar da casa [param from] para a vizinha [param to] atravessa um rio.
## Na diagonal, atravessa quando o rio separa as duas casas: os dois caminhos
## pelas casas do lado (por uma e pela outra) cruzam o rio. Passar em volta da
## nascente não conta.
func crosses_river(from: Vector2i, to: Vector2i) -> bool:
	if from.x == to.x or from.y == to.y:
		return _river_edges.has(_edge_key(from, to))
	var side_a := Vector2i(to.x, from.y)
	var side_b := Vector2i(from.x, to.y)
	return ((_river_edges.has(_edge_key(from, side_a)) or _river_edges.has(_edge_key(side_a, to)))
			and (_river_edges.has(_edge_key(from, side_b)) or _river_edges.has(_edge_key(side_b, to))))


## Chave da borda entre duas casas vizinhas (na horizontal ou na vertical), a
## mesma nos dois sentidos.
static func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y) if a < b else Vector4i(b.x, b.y, a.x, a.y)


## Se a casa encosta num rio (algum lado dela tem um trecho de rio): ganha
## Terrain.RIVER_FOOD de alimento.
func has_river(cell: Vector2i) -> bool:
	return _river_cells.has(cell)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_terrain(cell: Vector2i) -> Terrain.Type:
	return _terrain[cell.y * width + cell.x] as Terrain.Type


## Troca o terreno da casa (ex.: floresta esgotada vira cerrado) e redesenha.
func set_terrain(cell: Vector2i, type: Terrain.Type) -> void:
	_terrain[cell.y * width + cell.x] = type
	_wood.erase(cell)
	_terrain_image.set_pixelv(cell, Color8(type, 0, 0))
	_terrain_map.update(_terrain_image)


## Terreno de cada casa (as florestas viram cerrado ou pradaria durante o jogo),
## a madeira que resta nas florestas exploradas, o ferro e os rios, para o save.
func to_dict() -> Dictionary:
	return {"width": width, "height": height, "terrain": Marshalls.raw_to_base64(_terrain),
			"wood": SaveGame.cell_map_to_json(_wood), "iron": SaveGame.cells_to_json(iron_cells()),
			"roads": SaveGame.cell_map_to_json(roads), "road_progress": SaveGame.cell_map_to_json(road_progress),
			"rivers": rivers.map(func(river: Array) -> Array: return SaveGame.cells_to_json(river))}


## Volta ao terreno de um jogo salvo. O mapa precisa ter o mesmo tamanho (é
## carregado de data/maps/ antes). As melhorias são apagadas: cada cidade
## pinta as suas de novo.
func from_dict(data: Dictionary) -> void:
	var terrain := Marshalls.base64_to_raw(data["terrain"])
	if int(data["width"]) != width or int(data["height"]) != height or terrain.size() != width * height:
		push_error("O save é de um mapa de outro tamanho (%dx%d)." % [int(data["width"]), int(data["height"])])
		return
	_terrain = terrain
	for y in height:
		for x in width:
			_terrain_image.set_pixel(x, y, Color8(_terrain[y * width + x], 0, 0))
	_terrain_map.update(_terrain_image)
	_wood = SaveGame.json_to_cell_map(data["wood"])
	# Save antigo (sem rios): ficam os rios gerados ao montar o mapa
	if data.has("rivers"):
		set_rivers(data["rivers"].map(func(river: Array) -> Array: return SaveGame.json_to_cells(river)))
	roads = {}
	for road_cell: Vector2i in SaveGame.json_to_cell_map(data.get("roads", [])):
		roads[road_cell] = true
	road_progress = SaveGame.json_to_cell_map(data.get("road_progress", []))
	redraw_roads()
	# Save antigo (sem ferro): fica o ferro do arquivo de recursos do mapa
	if data.has("iron"):
		iron = {}
		for iron_cell in SaveGame.json_to_cells(data["iron"]):
			iron[iron_cell] = true
	_resource_layer.queue_redraw()
	_improvement_image.fill(Color8(Improvement.NONE, 0, 0))
	_improvement_map.update(_improvement_image)


## Madeira que ainda resta na casa (0 se não for floresta).
func wood_left(cell: Vector2i) -> int:
	if not is_in_bounds(cell) or get_terrain(cell) != Terrain.Type.FOREST:
		return 0
	return _wood.get(cell, Terrain.WOOD_PER_FOREST)


## Tira até [param amount] de madeira da floresta e retorna quanto tirou.
## Quando a madeira acaba, a floresta vira cerrado.
func harvest_wood(cell: Vector2i, amount: int) -> int:
	var taken := mini(amount, wood_left(cell))
	if taken <= 0:
		return 0
	_wood[cell] = wood_left(cell) - taken
	if _wood[cell] <= 0:
		set_terrain(cell, Terrain.Type.CERRADO)
	return taken


## Centro da casa, em coordenadas globais.
func cell_to_world(cell: Vector2i) -> Vector2:
	return _layer.to_global(_layer.map_to_local(cell))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return _layer.local_to_map(_layer.to_local(world_position))


func terrain_texture(type: Terrain.Type) -> Texture2D:
	return _terrain_textures[type]


## Material do shader do terreno que desenha só o pedaço do mapa que começa na
## casa [param origin] e tem [param cells] casas (janela da cidade). Usa as
## mesmas texturas do mapa, então acompanha as mudanças de terreno. As fazendas
## não são pintadas ([param with_farms] = false): a janela desenha as dela.
func make_view_material(origin: Vector2i, cells: Vector2i, with_farms := false) -> ShaderMaterial:
	var material := (_view.material as ShaderMaterial).duplicate() as ShaderMaterial
	material.set_shader_parameter("view_origin", Vector2(origin))
	material.set_shader_parameter("view_cells", Vector2(cells))
	material.set_shader_parameter("draw_farms", with_farms)
	return material


func get_pixel_size() -> Vector2:
	return Vector2(width, height) * TILE_SIZE


## Imagem do terreno vinda de assets/tiles/; sem arquivo, um quadrado na cor de reserva.
func _load_tile_image(type: Terrain.Type) -> Image:
	var path: String = Terrain.TEXTURE_PATHS[type]
	if not ResourceLoader.exists(path):
		var fallback := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback.fill(Terrain.COLORS[type])
		return fallback

	var image := (load(path) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_size() != Vector2i(TILE_SIZE, TILE_SIZE):
		push_warning("%s tem %s pixels; esperado %dx%d. A imagem foi redimensionada."
				% [path, image.get_size(), TILE_SIZE, TILE_SIZE])
		image.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_BILINEAR)
	return image


## Desenha (ou apaga, com Improvement.NONE) uma melhoria na casa. Usado pelas
## cidades para as fazendas, que o shader pinta integradas ao terreno.
func set_improvement(cell: Vector2i, improvement: Improvement) -> void:
	_improvement_image.set_pixelv(cell, Color8(improvement, 0, 0))
	_improvement_map.update(_improvement_image)
