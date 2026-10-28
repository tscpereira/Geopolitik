class_name FogOfWar
extends Node2D

## Névoa de guerra (desde 27/10/2026): o mapa começa todo escuro para o jogador
## humano e vai sendo desvendado pelas unidades e cidades dele.
##   - Cada unidade enxerga UnitType.vision casas em volta (1 = as 8 vizinhas;
##     Arqueiro e Catapulta: 2, um quadrado 5x5); cada cidade, CITY_VISION.
##   - Casa nunca vista: preta. Casa já explorada mas fora da visão agora: o
##     terreno aparece escurecido, e as unidades de outros jogadores nela não
##     aparecem (Unit.fog_hidden); as cidades aparecem como estavam da última
##     vez que foram vistas (Player.seen_cities).
## O que o jogador já explorou fica em Player.explored (vai para o save).
## Fica na cena logo depois das cidades: cobre o terreno, as fronteiras, as
## ruínas e as cidades; o destaque de movimento e as unidades ficam por cima.
## Sem jogador humano (máquina contra máquina), a névoa fica desligada.

## Casas que uma cidade enxerga em volta (a capital tem território de raio 2).
const CITY_VISION := 2
const SHADER: Shader = preload("res://scripts/map/fog.gdshader")

## Casas à vista agora: {casa: true}.
var visible_cells := {}
## Névoa ligada (há um jogador humano olhando).
var enabled := true

var _map: GameMap
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
## Fontes de visão da última atualização ([casa.x, casa.y, alcance]) e quem
## olhava: se nada mudou, a névoa não precisa ser refeita.
var _sources: Array[Vector3i] = []
var _viewer: Player = null


func setup(map: GameMap) -> void:
	_map = map
	_image = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	_image.fill(Color(1, 1, 0, 1))
	_texture = ImageTexture.create_from_image(_image)
	_sprite = Sprite2D.new()
	_sprite.name = "FogView"
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * GameMap.TILE_SIZE
	_sprite.texture = _texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_sprite.material = material
	add_child(_sprite)


## Força refazer a névoa na próxima atualização (ex.: depois de carregar um save).
func reset() -> void:
	_sources = []
	_viewer = null


## Recalcula o que [param viewer] enxerga, marca como explorado e redesenha a
## névoa. Retorna true se algo mudou. [param viewer] null: névoa desligada.
func update(viewer: Player) -> bool:
	enabled = viewer != null
	_sprite.visible = enabled
	if not enabled:
		var changed := _viewer != null or not _sources.is_empty()
		_viewer = null
		_sources = []
		return changed
	var sources: Array[Vector3i] = []
	for unit in viewer.units:
		sources.append(Vector3i(unit.cell.x, unit.cell.y, unit.type.vision))
	for city in viewer.cities:
		sources.append(Vector3i(city.cell.x, city.cell.y, CITY_VISION))
	if viewer == _viewer and sources == _sources:
		return false
	_viewer = viewer
	_sources = sources
	visible_cells = {}
	for source in sources:
		for dy in range(-source.z, source.z + 1):
			for dx in range(-source.z, source.z + 1):
				var cell := Vector2i(source.x + dx, source.y + dy)
				if _map.is_in_bounds(cell):
					visible_cells[cell] = true
	if viewer.explored.size() != _map.width * _map.height:
		viewer.explored.resize(_map.width * _map.height)
	for cell: Vector2i in visible_cells:
		viewer.explored[cell.y * _map.width + cell.x] = 1
	for y in _map.height:
		for x in _map.width:
			var seen := viewer.explored[y * _map.width + x] != 0
			var now := visible_cells.has(Vector2i(x, y))
			_image.set_pixel(x, y, Color(0.0 if seen else 1.0, 0.0 if now else 1.0, 0.0, 1.0))
	_texture.update(_image)
	return true


## Se a casa está à vista agora (sempre, com a névoa desligada).
func is_visible_cell(cell: Vector2i) -> bool:
	return not enabled or visible_cells.has(cell)


## Se o jogador que olha já viu a casa alguma vez (sempre, com a névoa desligada).
func is_explored(cell: Vector2i) -> bool:
	if not enabled or _viewer == null:
		return true
	var index := cell.y * _map.width + cell.x
	return index >= 0 and index < _viewer.explored.size() and _viewer.explored[index] != 0
