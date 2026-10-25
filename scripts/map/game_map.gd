class_name GameMap
extends Node2D

## Mapa em grid quadrado. Guarda o terreno de cada casa (e a madeira das
## florestas) e desenha o mapa inteiro com o shader terrain.gdshader, que faz
## as transições naturais entre os terrenos (costa arredondada, borda das
## florestas, pradaria <-> cerrado) e as fazendas (set_improvement). Os rios
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

## Melhoria desenhada pelo shader numa casa (ver set_improvement).
enum Improvement { NONE, FARM, FARM_IN_PROGRESS }
## Nome de cada textura de terreno no shader.
const SHADER_TEXTURES := {
	Terrain.Type.WATER: "water_tex",
	Terrain.Type.GRASSLAND: "grass_tex",
	Terrain.Type.FOREST: "forest_tex",
	Terrain.Type.CERRADO: "cerrado_tex",
}

var width := 0
var height := 0
## Dono de cada casa com cidade: {casa: Player}. Mantido pelo Game
## (refresh_territories); o Movement usa para as regras de invasão.
var city_owners := {}
## Cidade em cada casa com cidade: {casa: City}. Também mantido pelo Game; a
## unidade usa para a defesa da Muralha (Unit.walls_defense_bonus).
var cities := {}

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
## a madeira que resta nas florestas exploradas e os rios, para o save.
func to_dict() -> Dictionary:
	return {"width": width, "height": height, "terrain": Marshalls.raw_to_base64(_terrain),
			"wood": SaveGame.cell_map_to_json(_wood),
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
