class_name Minimap
extends Control

## Minimapa no canto esquerdo da tela (desde 27/10/2026): o mapa inteiro, 1
## casa = SCALE pixels, com o que o jogador humano já desvendou:
##   - casa nunca vista: preta;
##   - casa explorada: a cor média do terreno (mais escura se estiver fora da
##     visão agora);
##   - cidades: um ponto na cor do dono (as próprias sempre; as dos outros,
##     como foram vistas da última vez: Player.seen_cities);
##   - o retângulo branco é a parte do mapa que a câmera mostra.
## Clicar (ou arrastar) no minimapa leva a câmera até lá.

const SCALE := 2
const UNEXPLORED := Color(0.03, 0.035, 0.05)
const FOG_DIM := 0.55
const CITY_RADIUS := 3.0

var _game: Game
var _texture: ImageTexture
var _image: Image
## Cor média de cada terreno (Terrain.Type -> Color), tirada das texturas.
var _terrain_colors := {}


func setup(game: Game) -> void:
	_game = game
	var map := game.game_map
	custom_minimum_size = Vector2(map.width, map.height) * SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Mapa: o que você já explorou. Clique para levar a câmera até lá."
	for type: Terrain.Type in Terrain.TEXTURE_PATHS:
		var image := map.terrain_texture(type).get_image()
		if image.is_compressed():
			image.decompress()
		image = image.duplicate()
		image.clear_mipmaps()
		image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		_terrain_colors[type] = image.get_pixel(0, 0)
	_image = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	refresh()


## Refaz as cores das casas (quando a visão muda).
func refresh() -> void:
	if _game == null:
		return
	var map := _game.game_map
	var fog := _game.fog
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var color := UNEXPLORED
			if fog.is_explored(cell):
				color = _terrain_colors.get(map.get_terrain(cell), Color.MAGENTA)
				if not fog.is_visible_cell(cell):
					color = color.darkened(FOG_DIM)
			_image.set_pixel(x, y, color)
	_texture.update(_image)
	queue_redraw()


func _process(_delta: float) -> void:
	if _game:
		queue_redraw() # a câmera e as cidades mudam o tempo todo


func _draw() -> void:
	if _game == null:
		return
	var map := _game.game_map
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(map.width, map.height) * SCALE), false)
	# Cidades
	var viewer := _game.viewer()
	for city in _game.cities():
		var known := viewer == null or city.owner_player == viewer or viewer.seen_cities.has(city.cell)
		if known:
			_draw_city(city.cell, city.owner_player.color)
	if viewer:
		# Cidades vistas que já não existem mais (só se sabe quando voltar a ver)
		for cell: Vector2i in viewer.seen_cities:
			if _game.get_city_at(cell) == null:
				var owner := _game.player_by_id(viewer.seen_cities[cell])
				if owner:
					_draw_city(cell, owner.color)
	# Parte do mapa que a câmera mostra
	var camera := _game.camera
	var half := get_viewport_rect().size / camera.zoom / 2.0
	var view := Rect2((camera.get_screen_center_position() - half) / GameMap.TILE_SIZE * SCALE, half * 2.0 / GameMap.TILE_SIZE * SCALE)
	view = view.intersection(Rect2(Vector2.ZERO, size))
	draw_rect(view, Color(1, 1, 1, 0.9), false, 1.5)


func _draw_city(cell: Vector2i, color: Color) -> void:
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * SCALE
	draw_circle(center, CITY_RADIUS + 1.0, Color.BLACK)
	draw_circle(center, CITY_RADIUS, color)


func _gui_input(event: InputEvent) -> void:
	if _game == null:
		return
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var dragging: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressed or dragging:
		if _game.camera.locked:
			return
		_game.camera.center_on(event.position / SCALE * GameMap.TILE_SIZE)
		accept_event()
