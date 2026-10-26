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
## Desligado desde 22/10/2026: os sprites novos têm a roupa na cor do jogador e
## ficam sobre uma sombra com um anel na cor dele (_draw_base).
const DRAW_BACKGROUND := false
## Sprites antigos, sem máscara (ver team_texture): pixels desta cor são
## trocados pela cor do jogador ("cor de time"). Os tons mais escuros do
## magenta (vermelho = azul, sem verde, ex.: #B000B0) viram a cor do jogador
## escurecida na mesma proporção: dá para sombrear.
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
## Galé em que a unidade está embarcada (null = em terra). A bordo, ela some do
## mapa, não ocupa a casa (Game.occupants) e anda junto com a Galé; desembarca
## andando para uma casa de terra vizinha.
var transport: Unit = null:
	set(value):
		transport = value
		_update_visibility()
## Unidades a bordo (só para quem tem UnitType.cargo_capacity).
var cargo: Array[Unit] = []
## Turnos seguidos terminados em águas profundas (ver UnitType.deep_water_turn_limit).
var deep_water_turns := 0
## Destino da ordem "Mover" (tecla G): a unidade anda até lá sozinha, turno
## após turno. NO_TARGET = sem ordem.
var goto_target := NO_TARGET
## Trabalhador construindo a fazenda ou madeireira da cidade na casa em que está
## (teclas C e M) ou reconstruindo a melhoria pilhada (tecla R): faz 1 ponto
## por turno, no início da vez do dono (Game._process_rebuilds). Não é
## selecionado sozinho; mover a unidade interrompe a obra.
var rebuilding := false:
	set(value):
		rebuilding = value
		queue_redraw()

var attack: int:
	get:
		return type.attack
## Defesa base + fortificação + terreno (ex.: +1 na floresta) + Muralha (+2
## dentro da própria cidade murada).
var defense: int:
	get:
		return type.defense + (FORTIFY_DEFENSE_BONUS if fortified else 0) + terrain_defense_bonus() \
				+ walls_defense_bonus()
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
	moves_left = max_points()
	energy = max_energy


## Estado da unidade para o save. Se ela está dentro de uma madeireira, quem
## guarda isso é a madeireira (LumberMill.to_dict).
func to_dict() -> Dictionary:
	return {
		"type": type.resource_path, "cell": SaveGame.cell_to_json(cell), "move_points": moves_left,
		"energy": energy, "fortified": fortified, "hidden_in_city": hidden_in_city,
		"goto": SaveGame.cell_to_json(goto_target), "rebuilding": rebuilding,
		"aboard": transport != null, "deep_water_turns": deep_water_turns,
	}


## Volta ao estado salvo (depois de setup, que já deu o tipo, o dono e a casa).
func apply_dict(data: Dictionary) -> void:
	# Save antigo: "moves_left" em movimentos inteiros
	moves_left = int(data["move_points"]) if data.has("move_points") else int(data["moves_left"]) * Movement.POINTS
	energy = int(data["energy"])
	fortified = data["fortified"]
	hidden_in_city = data["hidden_in_city"]
	goto_target = SaveGame.json_to_cell(data["goto"])
	rebuilding = data.get("rebuilding", false)
	deep_water_turns = int(data.get("deep_water_turns", 0))
	_update_exhausted_look()


## Ataca à distância (UnitType.attack_range > 0: Arqueiro, Catapulta).
func is_ranged() -> bool:
	return type.attack_range > 0


## Unidade naval (Galé): anda na água.
func is_naval() -> bool:
	return type.is_naval


## Se [param unit] pode embarcar nesta unidade: é uma Galé do mesmo dono, com
## lugar, e [param unit] é de terra.
func can_carry(unit: Unit) -> bool:
	return unit != self and unit.owner_player == owner_player and not unit.is_naval() \
			and cargo.size() < type.cargo_capacity


## Embarca [param unit] (que já está na casa desta Galé).
func board(unit: Unit) -> void:
	unit.fortified = false
	unit.goto_target = NO_TARGET
	unit.transport = self
	unit.cell = cell
	cargo.append(unit)
	queue_redraw()


## Sai da Galé (ao andar para a terra).
func leave_transport() -> void:
	if transport:
		transport.cargo.erase(self)
		transport.queue_redraw()
		transport = null


## Leva quem está a bordo para a casa e a posição atuais da Galé.
func _carry_cargo() -> void:
	for passenger in cargo:
		passenger.cell = cell
		passenger.position = position


## Defesa extra do terreno em que a unidade está (Terrain.DEFENSE_BONUS).
func terrain_defense_bonus() -> int:
	return Terrain.DEFENSE_BONUS.get(_map.get_terrain(cell), 0) if _map else 0


## Defesa extra da Muralha: a unidade está dentro de uma cidade do seu dono
## que tem a Muralha (City.garrison_defense; fortificada ou não).
func walls_defense_bonus() -> int:
	if _map == null:
		return 0
	var city = _map.cities.get(cell) # sem tipo: a cidade pode ter acabado de ser destruída
	if not is_instance_valid(city) or city.owner_player != owner_player:
		return 0
	return city.garrison_defense()


## Defesa extra contra um ataque vindo da casa [param attacker_cell]: o rio
## entre as duas casas dá Terrain.RIVER_DEFENSE_BONUS (ver Combat).
func river_defense_bonus(attacker_cell: Vector2i) -> int:
	return Terrain.RIVER_DEFENSE_BONUS if _map and _map.crosses_river(attacker_cell, cell) else 0


func reset_moves() -> void:
	moves_left = max_points()
	_update_exhausted_look()


## Movimento cheio em pontos (Movement.POINTS por movimento).
func max_points() -> int:
	return movement * Movement.POINTS


## Movimentos que sobram, para mostrar: "1", "1,5", "0,5".
func moves_text() -> String:
	var whole := moves_left / Movement.POINTS
	return str(whole) if moves_left % Movement.POINTS == 0 else "%d,5" % whole


## Abre mão dos movimentos restantes neste turno.
func skip_turn() -> void:
	moves_left = 0
	_update_exhausted_look()


## Gasta movimentos (inteiros) numa ação (ex.: pilhar custa 1).
func spend_moves(amount: int) -> void:
	moves_left = maxi(moves_left - amount * Movement.POINTS, 0)
	_update_exhausted_look()


## Fortifica a unidade; isso encerra os movimentos dela neste turno e cancela
## a ordem de mover.
func fortify() -> void:
	fortified = true
	rebuilding = false
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
## (Movement.step_cost, em pontos: 1 movimento, mais na floresta, nas colinas e
## ao atravessar um rio para quem tem mais de 1 de movimento, meio na estrada).
## Quem está embarcado desembarca (aparece na Galé e anda para a terra); a Galé
## leva quem está a bordo.
func move_along(path: Array[Vector2i], map: GameMap) -> void:
	fortified = false
	rebuilding = false
	moves_left -= Movement.path_cost(map, self, path)
	leave_transport()
	var tween := create_tween()
	for step in path:
		tween.tween_property(self, "position", map.cell_to_world(step), MOVE_STEP_TIME)
	cell = path[-1]
	await tween.finished
	_carry_cargo()
	_update_exhausted_look()


## Avança para a casa do inimigo derrotado (não gasta movimento).
func advance_to(target: Vector2i, map: GameMap) -> void:
	cell = target
	var tween := create_tween()
	tween.tween_property(self, "position", map.cell_to_world(target), MOVE_STEP_TIME)
	await tween.finished
	_carry_cargo()


## Investida rápida em direção ao alvo e volta.
func play_attack(target_position: Vector2) -> void:
	var origin := position
	z_index = 1
	var tween := create_tween()
	tween.tween_property(self, "position", origin.lerp(target_position, 0.5), 0.1)
	tween.tween_property(self, "position", origin, 0.1)
	await tween.finished
	z_index = 0


## Ataque à distância: um pequeno recuo e o projétil do tipo (flecha ou pedra)
## voando até o alvo.
func play_shot(target_position: Vector2) -> void:
	var origin := position
	var tween := create_tween()
	tween.tween_property(self, "position", origin - (target_position - origin).normalized() * MARGIN * 2.0, 0.08)
	tween.tween_property(self, "position", origin, 0.08)
	await tween.finished
	await Projectile.fire(get_parent(), type.projectile, origin, target_position)


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
	visible = not hidden_in_city and working_mill == null and transport == null


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
	else:
		_draw_base(rect)
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

	if rebuilding:
		_draw_hammer(rect)

	# Barra de energia na base da unidade, só quando ela já levou dano
	if energy < max_energy:
		var ratio := float(energy) / max_energy
		var bar := Rect2(rect.position.x, rect.end.y - ENERGY_BAR_HEIGHT, rect.size.x, ENERGY_BAR_HEIGHT)
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), _energy_color(ratio))

	# Galé: uma bolinha na cor do dono para cada unidade a bordo, no canto de cima
	# à esquerda (fora da vela)
	if type.cargo_capacity > 0:
		var radius := GameMap.TILE_SIZE / 16.0
		for i in type.cargo_capacity:
			var center := Vector2(rect.position.x + radius + 1.5 + i * radius * 2.6, rect.position.y + radius + 1.5)
			draw_circle(center, radius + 1.5, Color.BLACK)
			draw_circle(center, radius, owner_player.color if i < cargo.size() else Color(0.25, 0.25, 0.25))


## Base da unidade: sombra no chão e um anel na cor do jogador nos pés, para
## mostrar de quem é a unidade em qualquer terreno.
func _draw_base(rect: Rect2) -> void:
	var center := Vector2(0, rect.end.y - rect.size.y * 0.1)
	var radii := Vector2(rect.size.x * 0.42, rect.size.y * 0.13)
	draw_set_transform(center, 0.0, Vector2(1.0, radii.y / radii.x))
	draw_circle(Vector2.ZERO, radii.x, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_arc(Vector2.ZERO, radii.x, 0.0, TAU, 48, Color.BLACK, GameMap.TILE_SIZE / 10.0, true)
	draw_arc(Vector2.ZERO, radii.x, 0.0, TAU, 48, owner_player.color, GameMap.TILE_SIZE / 16.0, true)
	draw_set_transform(Vector2.ZERO)


## Muralha de pedra em volta da unidade fortificada (como no Civilization 1),
## com cantos arredondados e ameias no topo.
func _draw_fortification(rect: Rect2) -> void:
	var wall := MARGIN * 2.0
	var outer := rect.grow(MARGIN)
	var merlons := 4
	var merlon_width := outer.size.x / (merlons * 2 - 1)
	for i in merlons:
		var x := outer.position.x + i * 2 * merlon_width
		_rounded_box(Rect2(x, outer.position.y - wall * 1.6, merlon_width, wall * 2.0), wall * 0.4, FORTIFY_COLOR, 0.0)
	_rounded_box(outer.grow(wall / 2.0), wall * 1.8, Color.TRANSPARENT, wall)


## Retângulo de cantos arredondados com contorno escuro: cheio ([param fill])
## ou só a borda de pedra com [param border] de espessura.
func _rounded_box(box: Rect2, radius: float, fill: Color, border: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	style.corner_detail = 8
	style.anti_aliasing = true
	style.border_color = FORTIFY_COLOR
	style.set_border_width_all(int(border))
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 2
	style.draw(get_canvas_item(), box)


## Martelo num círculo no canto superior direito: o Trabalhador está
## reconstruindo a melhoria pilhada da casa.
func _draw_hammer(rect: Rect2) -> void:
	var radius := GameMap.TILE_SIZE * 0.17
	var center := Vector2(rect.end.x - radius * 0.6, rect.position.y + radius * 0.6)
	draw_circle(center, radius + 1.0, Color.BLACK)
	draw_circle(center, radius, Color(1, 0.85, 0.3))
	var handle := radius * 0.12
	draw_line(center + Vector2(-radius * 0.5, radius * 0.55), center + Vector2(radius * 0.2, -radius * 0.15), Color8(110, 70, 35), handle * 3.0)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.05, -radius * 0.65), center + Vector2(radius * 0.65, radius * 0.05),
		center + Vector2(radius * 0.4, radius * 0.3), center + Vector2(-radius * 0.3, -radius * 0.4),
	]), Color8(70, 70, 75))


## Sprite do tipo com os pixels magenta trocados pela cor do jogador (com cache).
func _team_texture() -> Texture2D:
	return team_texture(type.sprite, owner_player.color)


## [param sprite] na cor do jogador [param color] (com cache). Também usado
## pelos ícones das janelas (Icons.draw_build) e pelo desenho das cidades
## (City.draw_city_sprite).
##   - Com máscara (desenhos suavizados de 80x80, desde 23/10/2026): ao lado de
##     "x.png" existe "x_time.png", em tons de cinza. O sprite tem a roupa em
##     preto; cada pixel recebe + máscara × cor do jogador (branco = a cor
##     inteira). Funciona com bordas suavizadas, que o magenta não aguenta.
##   - Sem máscara (pixel art antiga): os pixels magenta viram [param color] e
##     os tons escuros do magenta, [param color] escurecida (TEAM_COLOR_KEY).
## A textura sai com mipmaps (fica suave também com o zoom afastado).
static func team_texture(sprite: Texture2D, color: Color) -> Texture2D:
	var key := "%d|%s" % [sprite.get_instance_id(), color.to_html()]
	if not _team_textures.has(key):
		var image := sprite.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.clear_mipmaps()
		var mask := _team_mask(sprite)
		if mask:
			for y in image.get_height():
				for x in image.get_width():
					var amount := mask.get_pixel(x, y).r
					if amount > 0.0:
						var pixel := image.get_pixel(x, y)
						image.set_pixel(x, y, Color(minf(pixel.r + color.r * amount, 1.0),
								minf(pixel.g + color.g * amount, 1.0), minf(pixel.b + color.b * amount, 1.0), pixel.a))
			image.generate_mipmaps()
			_team_textures[key] = ImageTexture.create_from_image(image)
			return _team_textures[key]
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.g8 == 0 and pixel.r8 == pixel.b8 and pixel.r8 > 0:
					var shade := pixel.r # 1.0 = magenta puro; menos = mais escuro
					image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, pixel.a))
		image.generate_mipmaps()
		_team_textures[key] = ImageTexture.create_from_image(image)
	return _team_textures[key]


## Máscara da cor do jogador do sprite ("x_time.png" ao lado de "x.png"), ou null.
static func _team_mask(sprite: Texture2D) -> Image:
	var path := sprite.resource_path.get_basename() + "_time.png"
	if sprite.resource_path.is_empty() or not ResourceLoader.exists(path):
		return null
	var mask := (load(path) as Texture2D).get_image()
	if mask.is_compressed():
		mask.decompress()
	mask.clear_mipmaps()
	mask.convert(Image.FORMAT_RGBA8)
	return mask


func _energy_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.2, 0.9, 0.2)
	if ratio > 0.3:
		return Color(1.0, 0.85, 0.1)
	return Color(1.0, 0.2, 0.1)
