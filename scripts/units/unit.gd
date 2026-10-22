class_name Unit
extends Node2D

## Unidade no mapa. Os atributos base vêm do UnitType;
## aqui fica o estado dela na partida (dono, posição, movimentos restantes).

## Medidas proporcionais ao tamanho da casa.
const FONT_SIZE := int(GameMap.TILE_SIZE * 0.65)
const MARGIN := GameMap.TILE_SIZE / 16.0
const ENERGY_BAR_HEIGHT := GameMap.TILE_SIZE / 8.0
## Duração da animação de cada casa andada.
const MOVE_STEP_TIME := 0.12
## Cor aplicada à unidade quando ela não tem mais movimentos no turno.
const EXHAUSTED_TINT := Color(0.55, 0.55, 0.55)
## Desenha um quadrado na cor do jogador atrás do sprite (estilo Civilization 1).
const DRAW_BACKGROUND := true
## Pixels desta cor no sprite são trocados pela cor do jogador ("cor de time").
const TEAM_COLOR_KEY := Color(1, 0, 1)
## Defesa extra da unidade fortificada.
const FORTIFY_DEFENSE_BONUS := 1
## Energia recuperada por turno pela unidade fortificada (se estiver ferida).
const FORTIFY_HEAL := 5
const FORTIFY_COLOR := Color8(150, 140, 120)
## Valor de goto_target quando a unidade não tem destino.
const NO_TARGET := Vector2i(-1, -1)

## Sprites já recoloridos, por sprite + cor do jogador.
static var _team_textures := {}

var type: UnitType
var owner_player: Player
var cell: Vector2i
var moves_left := 0
var energy := 0:
	set(value):
		energy = maxi(value, 0)
		queue_redraw()
## Fortificada: +FORTIFY_DEFENSE_BONUS de defesa e recupera energia a cada
## turno. Fica assim até se mover ou atacar.
var fortified := false:
	set(value):
		fortified = value
		if not value:
			hidden_in_city = false
		queue_redraw()
## Fortificada dentro de uma cidade: some do mapa e aparece na janela da
## cidade (seção "Unidades na cidade"). Volta a aparecer ao ser ativada.
var hidden_in_city := false:
	set(value):
		hidden_in_city = value
		_update_visibility()
## Trabalhador alocado numa madeireira remota: some do mapa, não ocupa a casa
## e não recebe ordens até sair dela (ver Game.release_mill_worker).
var working_mill: LumberMill = null:
	set(value):
		working_mill = value
		_update_visibility()
## Destino da ordem "Mover" (tecla G): a unidade anda até lá sozinha, turno
## após turno. NO_TARGET = sem ordem.
var goto_target := NO_TARGET

var attack: int:
	get:
		return type.attack
## Defesa base + fortificação + terreno (ex.: +1 na floresta).
var defense: int:
	get:
		return type.defense + (FORTIFY_DEFENSE_BONUS if fortified else 0) + terrain_defense_bonus()
var movement: int:
	get:
		return type.movement
var max_energy: int:
	get:
		return type.max_energy

var _blink_tween: Tween
var _map: GameMap


func setup(p_type: UnitType, p_owner: Player, p_cell: Vector2i, map: GameMap) -> void:
	type = p_type
	owner_player = p_owner
	cell = p_cell
	_map = map
	moves_left = movement
	energy = max_energy


## Estado da unidade para o save. Se ela está dentro de uma madeireira, quem
## guarda isso é a madeireira (LumberMill.to_dict).
func to_dict() -> Dictionary:
	return {
		"type": type.resource_path, "cell": SaveGame.cell_to_json(cell), "moves_left": moves_left,
		"energy": energy, "fortified": fortified, "hidden_in_city": hidden_in_city,
		"goto": SaveGame.cell_to_json(goto_target),
	}


## Volta ao estado salvo (depois de setup, que já deu o tipo, o dono e a casa).
func apply_dict(data: Dictionary) -> void:
	moves_left = int(data["moves_left"])
	energy = int(data["energy"])
	fortified = data["fortified"]
	hidden_in_city = data["hidden_in_city"]
	goto_target = SaveGame.json_to_cell(data["goto"])
	_update_exhausted_look()


## Defesa extra do terreno em que a unidade está (Terrain.DEFENSE_BONUS).
func terrain_defense_bonus() -> int:
	return Terrain.DEFENSE_BONUS.get(_map.get_terrain(cell), 0) if _map else 0


func reset_moves() -> void:
	moves_left = movement
	_update_exhausted_look()


## Abre mão dos movimentos restantes neste turno.
func skip_turn() -> void:
	moves_left = 0
	_update_exhausted_look()


## Fortifica a unidade; isso encerra os movimentos dela neste turno e cancela
## a ordem de mover.
func fortify() -> void:
	fortified = true
	goto_target = NO_TARGET
	skip_turn()


func has_goto() -> bool:
	return goto_target != NO_TARGET


## Início do turno da unidade fortificada: recupera energia se estiver ferida.
## Retorna quanto recuperou.
func heal_if_fortified() -> int:
	if not fortified or energy >= max_energy:
		return 0
	var before := energy
	energy = mini(energy + FORTIFY_HEAL, max_energy)
	return energy - before


## Anda casa a casa pelo caminho, gastando o custo de cada casa
## (Movement.step_cost: 1, ou 2 na floresta para quem tem mais de 1 de movimento).
func move_along(path: Array[Vector2i], map: GameMap) -> void:
	fortified = false
	var tween := create_tween()
	for step in path:
		tween.tween_property(self, "position", map.cell_to_world(step), MOVE_STEP_TIME)
	moves_left -= Movement.path_cost(map, self, path)
	cell = path[-1]
	await tween.finished
	_update_exhausted_look()


## Avança para a casa do inimigo derrotado (não gasta movimento).
func advance_to(target: Vector2i, map: GameMap) -> void:
	cell = target
	var tween := create_tween()
	tween.tween_property(self, "position", map.cell_to_world(target), MOVE_STEP_TIME)
	await tween.finished


## Investida rápida em direção ao alvo e volta.
func play_attack(target_position: Vector2) -> void:
	var origin := position
	z_index = 1
	var tween := create_tween()
	tween.tween_property(self, "position", origin.lerp(target_position, 0.5), 0.1)
	tween.tween_property(self, "position", origin, 0.1)
	await tween.finished
	z_index = 0


func play_death() -> void:
	set_selected(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	await tween.finished
	queue_free()


## Unidade selecionada pisca, como no Civilization 1.
func set_selected(selected: bool) -> void:
	if _blink_tween:
		_blink_tween.kill()
		_blink_tween = null
	modulate.a = 1.0
	if selected:
		_blink_tween = create_tween().set_loops()
		_blink_tween.tween_property(self, "modulate:a", 0.3, 0.35)
		_blink_tween.tween_property(self, "modulate:a", 1.0, 0.35)


func _update_visibility() -> void:
	visible = not hidden_in_city and working_mill == null


func _update_exhausted_look() -> void:
	self_modulate = EXHAUSTED_TINT if moves_left <= 0 else Color.WHITE


## Quadrado na cor do jogador com o sprite (ou a letra) do tipo por cima,
## no estilo Civilization 1.
func _draw() -> void:
	var half := GameMap.TILE_SIZE / 2.0 - MARGIN
	var rect := Rect2(-half, -half, half * 2.0, half * 2.0)
	if DRAW_BACKGROUND:
		draw_rect(rect, owner_player.color)
		draw_rect(rect, Color.BLACK, false, MARGIN)
	if fortified:
		_draw_fortification(rect)

	if type.sprite:
		var tile_half := GameMap.TILE_SIZE / 2.0
		draw_texture_rect(_team_texture(), Rect2(-tile_half, -tile_half, GameMap.TILE_SIZE, GameMap.TILE_SIZE), false)
	else:
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(type.symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var baseline := (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
		draw_string(font, Vector2(-text_width / 2.0, baseline), type.symbol,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.BLACK)

	# Barra de energia na base da unidade, só quando ela já levou dano
	if energy < max_energy:
		var ratio := float(energy) / max_energy
		var bar := Rect2(rect.position.x, rect.end.y - ENERGY_BAR_HEIGHT, rect.size.x, ENERGY_BAR_HEIGHT)
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), _energy_color(ratio))


## Muralha de pedra em volta da unidade fortificada (como no Civilization 1),
## com ameias no topo.
func _draw_fortification(rect: Rect2) -> void:
	var wall := MARGIN * 2.0
	var outer := rect.grow(MARGIN)
	draw_rect(outer, FORTIFY_COLOR, false, wall)
	var merlons := 4
	var merlon_width := outer.size.x / (merlons * 2 - 1)
	for i in merlons:
		var x := outer.position.x + i * 2 * merlon_width
		draw_rect(Rect2(x, outer.position.y - wall, merlon_width, wall), FORTIFY_COLOR)
	draw_rect(outer.grow(wall / 2.0), Color.BLACK, false, 1.0)


## Sprite do tipo com os pixels magenta trocados pela cor do jogador (com cache).
func _team_texture() -> Texture2D:
	return team_texture(type.sprite, owner_player.color)


## [param sprite] com os pixels magenta trocados por [param color] (com cache).
## Também usado pelos ícones das janelas (Icons.draw_build).
static func team_texture(sprite: Texture2D, color: Color) -> Texture2D:
	var key := "%d|%s" % [sprite.get_instance_id(), color.to_html()]
	if not _team_textures.has(key):
		var image := sprite.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0 and Color(pixel, 1.0).is_equal_approx(TEAM_COLOR_KEY):
					image.set_pixel(x, y, Color(color, pixel.a))
		_team_textures[key] = ImageTexture.create_from_image(image)
	return _team_textures[key]


func _energy_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.2, 0.9, 0.2)
	if ratio > 0.3:
		return Color(1.0, 0.85, 0.1)
	return Color(1.0, 0.2, 0.1)
