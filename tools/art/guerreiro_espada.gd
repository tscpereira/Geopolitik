extends SceneTree

## Gera o desenho do Guerreiro de Espada Curta (estilo legionário) a partir do
## hoplita do ChatGPT (chatgpt/grandes/guerreiro.png, o desenho do Lanceiro):
## tira a lança, cobre o escudo redondo com um escudo retangular grande e
## curvo (scutum) com a face na cor do time (máscara), aro e umbo de bronze e
## faixas douradas, e põe uma espada curta (gládio) na mão direita.
##
## Uso (na pasta do projeto):
##   godot_console.cmd --headless --path . --script tools/art/guerreiro_espada.gd
## Grava chatgpt/grandes/guerreiro_espada(.png e _time.png) e o sprite 80x80 em
## chatgpt/prontos/ e em assets/sprites/units/ (como import_unit.gd).

const GRANDES := "res://tools/art/chatgpt/grandes/"
const PRONTOS := "res://tools/art/chatgpt/prontos/"
const UNITS := "res://assets/sprites/units/"
const NAME := "guerreiro_espada"
## Espaço a mais à esquerda para a lâmina (que passa do contorno do corpo).
const PAD_LEFT := 30
## Lança do hoplita (no desenho original): do topo até o pé, e a meia
## largura da faixa apagada (mais larga na ponta).
const SPEAR_TOP := Vector2(154.5, 0)
const SPEAR_BOTTOM := Vector2(128.5, 440)
const SPEAR_HALF := 6.0
const SPEAR_TIP_HALF := 10.0
const SPEAR_TIP_END := 64
## A ponta de baixo (o conto da lança, junto do pé) também é mais larga.
const SPEAR_BUTT_START := 400
## Escudo (já com PAD_LEFT): retângulo de cantos arredondados que cobre o
## escudo redondo e parte da perna esquerda.
const SHIELD := Rect2(Vector2(88 + PAD_LEFT, 158), Vector2(98, 210))
const SHIELD_CORNER := 12.0
const RIM := 5.0
const BOSS_RADIUS := 15.0
## Gládio: punho na mão direita, lâmina para cima e para a frente (esquerda).
const GRIP := Vector2(30 + PAD_LEFT, 296)
const SWORD_ANGLE := deg_to_rad(-125.0) # da mão para a ponta
const BLADE_LENGTH := 74.0
const BLADE_HALF := 5.0
const BRONZE := Color(0.72, 0.53, 0.22)
const GOLD := Color(0.86, 0.68, 0.3)
const STEEL := Color(0.78, 0.8, 0.83)


func _initialize() -> void:
	var body := Image.load_from_file(ProjectSettings.globalize_path(GRANDES + "guerreiro.png"))
	var body_mask := Image.load_from_file(ProjectSettings.globalize_path(GRANDES + "guerreiro_time.png"))
	body.convert(Image.FORMAT_RGBA8)
	body_mask.convert(Image.FORMAT_RGBA8)
	_erase_spear(body, body_mask)
	_remove_specks(body, body_mask)
	var size := Vector2i(body.get_width() + PAD_LEFT + 4, body.get_height())
	var art := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	art.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i(PAD_LEFT, 0))
	mask.blit_rect(body_mask, Rect2i(Vector2i.ZERO, body_mask.get_size()), Vector2i(PAD_LEFT, 0))
	_sword(art)
	_shield(art, mask)
	art.save_png(ProjectSettings.globalize_path(GRANDES + NAME + ".png"))
	mask.save_png(ProjectSettings.globalize_path(GRANDES + NAME + "_time.png"))
	_save_sprite(art, mask)
	print("Guerreiro de Espada Curta gerado (%dx%d)" % [size.x, size.y])
	quit()


## Apaga a lança: uma faixa ao longo da haste (mais larga na ponta de metal).
func _erase_spear(art: Image, mask: Image) -> void:
	for y in art.get_height():
		var t := float(y) / (SPEAR_BOTTOM.y - SPEAR_TOP.y)
		var center := lerpf(SPEAR_TOP.x, SPEAR_BOTTOM.x, t)
		var half := SPEAR_TIP_HALF if y < SPEAR_TIP_END or y >= SPEAR_BUTT_START else SPEAR_HALF
		for x in range(int(center - half), int(center + half) + 1):
			if x >= 0 and x < art.get_width():
				art.set_pixel(x, y, Color(0, 0, 0, 0))
				mask.set_pixel(x, y, Color.BLACK)


## Tira os grupinhos de pixels soltos (pedaços da lança fora da faixa apagada):
## grupos com menos de SPECK_MAX pixels que não se ligam ao corpo.
const SPECK_MAX := 80
func _remove_specks(art: Image, mask: Image) -> void:
	var w := art.get_width()
	var h := art.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if seen[start] != 0 or art.get_pixel(start % w, start / w).a <= 0.05:
			continue
		var group := PackedInt32Array([start])
		seen[start] = 1
		var k := 0
		while k < group.size():
			var i := group[k]
			k += 1
			var x := i % w
			var y := i / w
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var ni := n.y * w + n.x
				if seen[ni] == 0 and art.get_pixel(n.x, n.y).a > 0.05:
					seen[ni] = 1
					group.append(ni)
		if group.size() < SPECK_MAX:
			for i in group:
				art.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
				mask.set_pixel(i % w, i / w, Color.BLACK)


## Gládio: lâmina larga e curta de aço com a aresta central, guarda e pomo
## dourados; o punho fica na mão (a lâmina sai de cima do punho).
func _sword(art: Image) -> void:
	var direction := Vector2(cos(SWORD_ANGLE), sin(SWORD_ANGLE))
	var side := direction.orthogonal()
	var guard := GRIP + direction * 10.0
	var box := Rect2(GRIP, Vector2.ZERO).expand(guard + direction * BLADE_LENGTH).grow(BLADE_HALF + 8)
	for y in range(int(box.position.y), int(box.end.y) + 1):
		for x in range(int(box.position.x), int(box.end.x) + 1):
			if x < 0 or y < 0 or x >= art.get_width() or y >= art.get_height():
				continue
			var p := Vector2(x, y) + Vector2(0.5, 0.5) - guard
			var along := p.dot(direction)
			var across := p.dot(side)
			var color := Color(0, 0, 0, 0)
			if along >= 0.0 and along <= BLADE_LENGTH:
				# Lâmina: estreita perto da ponta (os últimos 14 px)
				var width := BLADE_HALF * clampf((BLADE_LENGTH - along) / 14.0, 0.0, 1.0)
				if absf(across) <= width + 0.6:
					var shade := 0.82 + 0.28 * (-across / BLADE_HALF) # luz de um lado
					color = Color(STEEL * shade, 1.0)
					if absf(across) < 0.9:
						color = Color(STEEL.lightened(0.25), 1.0) # aresta central
					color.a = clampf(width + 0.6 - absf(across), 0.0, 1.0)
			elif along < 0.0 and along > -4.0 and absf(across) <= 9.0:
				color = Color(GOLD * (0.85 + 0.25 * (-across / 9.0)), 1.0) # guarda
			if color.a > 0.0:
				var under := art.get_pixel(x, y)
				art.set_pixel(x, y, under.lerp(Color(color, 1.0), color.a) if under.a > 0.0 else color)


## Scutum: retângulo curvo (sombreado como um cilindro: claro um pouco à
## esquerda do meio, escuro nas bordas), face na cor do time (preto no desenho,
## tons de cinza na máscara), aro de bronze, faixas douradas em cruz e o umbo
## de bronze no meio.
func _shield(art: Image, mask: Image) -> void:
	var center := SHIELD.get_center()
	for y in range(int(SHIELD.position.y), int(SHIELD.end.y)):
		for x in range(int(SHIELD.position.x), int(SHIELD.end.x)):
			if x >= art.get_width():
				continue
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var inside := _rounded_distance(p) # > 0 dentro, em px até a borda
			if inside <= -0.5:
				continue
			var alpha := clampf(inside + 0.5, 0.0, 1.0)
			var t := (p.x - SHIELD.position.x) / SHIELD.size.x
			var curve := 0.62 + 0.42 * cos((t - 0.38) * PI) # cilindro
			var vertical := 1.0 - 0.12 * (p.y - SHIELD.position.y) / SHIELD.size.y
			var light := clampf(curve * vertical, 0.3, 1.05)
			var color: Color
			var team := 0.0
			var from_center := p - center
			if inside < RIM:
				color = BRONZE * (light + 0.15 * (1.0 - inside / RIM))
			elif from_center.length() < BOSS_RADIUS:
				var dome := 1.0 - from_center.length() / BOSS_RADIUS
				color = BRONZE.lightened(0.15) * (0.7 + 0.5 * dome - 0.25 * (from_center.x + from_center.y) / BOSS_RADIUS)
			elif absf(from_center.x) < 3.5 or absf(from_center.y) < 3.0:
				color = GOLD * light # faixas em cruz
			else:
				color = Color.BLACK
				team = light * 0.95 # face: a cor do time, com a luz do cilindro
			var under := art.get_pixel(x, y)
			art.set_pixel(x, y, Color(color, 1.0) if alpha >= 1.0 or under.a <= 0.0 else under.lerp(Color(color, 1.0), alpha))
			if under.a <= 0.0 and alpha < 1.0:
				art.set_pixel(x, y, Color(color, alpha))
			mask.set_pixel(x, y, Color(team, team, team) * alpha + mask.get_pixel(x, y) * (1.0 - alpha))


## Distância (em px) da borda do retângulo de cantos arredondados, positiva dentro.
func _rounded_distance(p: Vector2) -> float:
	var half := SHIELD.size / 2.0 - Vector2.ONE * SHIELD_CORNER
	var q := (p - SHIELD.get_center()).abs() - half
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	return SHIELD_CORNER - outside


## Reduz para 80x80 como o importador: cabe em 76x70, com os pés na linha 73.
func _save_sprite(art: Image, mask: Image) -> void:
	var scale := minf(76.0 / art.get_width(), 70.0 / art.get_height())
	var target := Vector2i(roundi(art.get_width() * scale), roundi(art.get_height() * scale))
	var small_art := art.duplicate()
	var small_mask := mask.duplicate()
	for img: Image in [small_art, small_mask]:
		var current: Vector2i = img.get_size()
		while current.x > target.x * 2:
			current /= 2
			img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var sprite := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	var sprite_mask := Image.create(80, 80, false, Image.FORMAT_L8)
	var at := Vector2i((80 - target.x) / 2, 73 - target.y)
	sprite.blit_rect(small_art, Rect2i(Vector2i.ZERO, target), at)
	small_mask.convert(Image.FORMAT_L8)
	sprite_mask.blit_rect(small_mask, Rect2i(Vector2i.ZERO, target), at)
	for folder in [PRONTOS, UNITS]:
		sprite.save_png(ProjectSettings.globalize_path(folder + NAME + ".png"))
		sprite_mask.save_png(ProjectSettings.globalize_path(folder + NAME + "_time.png"))
