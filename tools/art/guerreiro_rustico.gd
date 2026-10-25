extends SceneTree

## Gera o desenho do Guerreiro rústico a partir do Trabalhador do ChatGPT
## (chatgpt/grandes/trabalhador.png), no mesmo estilo pintado: a túnica branca
## vira couro escuro, ele ganha um escudo redondo de tábuas com aro e umbo de
## ferro e um anel pintado na cor do time (máscara), e fica com o machado.
## O antigo Guerreiro (o hoplita) virou o Lanceiro (desde 25/10/2026).
##
## Uso (na pasta do projeto):
##   godot_console.cmd --headless --path . --script tools/art/guerreiro_rustico.gd
## Grava chatgpt/grandes/guerreiro_rustico(.png e _time.png) e
## chatgpt/prontos/guerreiro(.png e _time.png), 80x80 como o importador
## (import_sheet.gd). Depois, copie os dois de prontos/ para assets/sprites/units/.

const GRANDES := "res://tools/art/chatgpt/grandes/"
const PRONTOS := "res://tools/art/chatgpt/prontos/"
## Espaço a mais à esquerda para o escudo (que passa do contorno do corpo).
const PAD_LEFT := 26
## Escudo (no desenho grande, já com PAD_LEFT): centro, raios, aro e umbo.
const SHIELD_CENTER := Vector2(54, 198)
const SHIELD_RADIUS := Vector2(44, 50)
const RIM := 6.0
const BOSS_RADIUS := 10.0
## Anel pintado na cor do time (entre o umbo e o aro).
const TEAM_RING := Vector2(19.0, 27.0)
const WOOD_LIGHT := Color(0.62, 0.43, 0.24)
const WOOD_DARK := Color(0.36, 0.23, 0.12)
const IRON := Color(0.42, 0.41, 0.4)
const LEATHER := Color(0.52, 0.33, 0.17)


func _initialize() -> void:
	var body := Image.load_from_file(ProjectSettings.globalize_path(GRANDES + "trabalhador.png"))
	var body_mask := Image.load_from_file(ProjectSettings.globalize_path(GRANDES + "trabalhador_time.png"))
	body.convert(Image.FORMAT_RGBA8)
	body_mask.convert(Image.FORMAT_RGBA8)
	var size := Vector2i(body.get_width() + PAD_LEFT, body.get_height())
	var art := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	art.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i(PAD_LEFT, 0))
	mask.blit_rect(body_mask, Rect2i(Vector2i.ZERO, body_mask.get_size()), Vector2i(PAD_LEFT, 0))
	_leather_tunic(art, mask)
	_shield(art, mask)
	art.save_png(ProjectSettings.globalize_path(GRANDES + "guerreiro_rustico.png"))
	mask.save_png(ProjectSettings.globalize_path(GRANDES + "guerreiro_rustico_time.png"))
	_save_sprite(art, mask, "guerreiro")
	print("Guerreiro rústico gerado (%dx%d)" % [size.x, size.y])
	quit()


## Túnica branca (pouco saturada e clara, fora da máscara) vira couro marrom,
## mantendo a luz e a sombra da pintura.
func _leather_tunic(art: Image, mask: Image) -> void:
	for y in art.get_height():
		for x in art.get_width():
			var p := art.get_pixel(x, y)
			if p.a < 0.05 or mask.get_pixel(x, y).r > 0.05:
				continue
			if p.s < 0.2 and p.v > 0.5:
				var light := clampf((p.v - 0.5) / 0.5, 0.0, 1.0)
				var c := LEATHER.darkened(0.35).lerp(LEATHER.lightened(0.25), light)
				art.set_pixel(x, y, Color(c, p.a))


## Escudo redondo de tábuas visto quase de frente, por cima do braço esquerdo:
## tábuas verticais com veios, luz de cima à esquerda, aro e umbo de ferro e o
## anel pintado na cor do time (preto no desenho, branco na máscara).
func _shield(art: Image, mask: Image) -> void:
	var box := Rect2i(Vector2i(SHIELD_CENTER - SHIELD_RADIUS) - Vector2i(3, 3), Vector2i(SHIELD_RADIUS * 2.0) + Vector2i(6, 6))
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if x < 0 or y < 0 or x >= art.get_width() or y >= art.get_height():
				continue
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - SHIELD_CENTER) / SHIELD_RADIUS
			var r := d.length() # 1 = borda do escudo
			if r > 1.0 + 1.6 / SHIELD_RADIUS.x:
				continue
			var radius_px := r * SHIELD_RADIUS.x
			var light := clampf(0.62 - (d.x + d.y) * 0.28, 0.25, 1.0) # luz de cima à esquerda
			var color: Color
			var team := 0.0
			if r > 1.0:
				color = Color(0.08, 0.06, 0.05) # contorno
			elif radius_px > SHIELD_RADIUS.x - RIM:
				# Aro de ferro com um brilho
				var t := (radius_px - (SHIELD_RADIUS.x - RIM)) / RIM
				color = IRON.darkened(0.45).lerp(IRON.lightened(0.25), sin(t * PI) * light)
			elif radius_px < BOSS_RADIUS:
				# Umbo: meia esfera de ferro com brilho
				var b := radius_px / BOSS_RADIUS
				var spot := Vector2(x, y) - (SHIELD_CENTER - Vector2(3, 3))
				color = IRON.darkened(0.4).lerp(IRON.lightened(0.45), clampf(1.0 - spot.length() / BOSS_RADIUS, 0.0, 1.0))
				color = color.darkened(smoothstep(0.85, 1.0, b) * 0.5)
			elif radius_px > TEAM_RING.x and radius_px < TEAM_RING.y:
				# Anel pintado na cor do time, com a mesma luz da madeira
				color = Color.BLACK
				team = clampf(0.55 + light * 0.45, 0.0, 1.0) * (1.0 - _edge(radius_px, TEAM_RING) * 0.4)
			else:
				# Tábuas verticais com veios e frestas
				var plank := floori((x - SHIELD_CENTER.x + 100.0) / 13.0)
				var grain := sin(y * 0.45 + plank * 2.1 + sin(y * 0.11 + plank) * 2.0) * 0.5 + 0.5
				var seam := 1.0 - smoothstep(0.0, 1.4, absf(fposmod(x - SHIELD_CENTER.x + 100.0, 13.0) - 0.5))
				color = WOOD_DARK.lerp(WOOD_LIGHT, light * (0.75 + grain * 0.25))
				color = color.darkened(seam * 0.45 + (0.08 if plank % 2 == 0 else 0.0))
			art.set_pixel(x, y, Color(color, 1.0))
			mask.set_pixel(x, y, Color(team, team, team, 1.0))


## 0 no meio do anel, 1 nas bordas (para escurecer as beiradas da tinta).
func _edge(value: float, ring: Vector2) -> float:
	var middle := (ring.x + ring.y) / 2.0
	return clampf(absf(value - middle) / ((ring.y - ring.x) / 2.0), 0.0, 1.0)


## Reduz para 80x80 como o importador (import_sheet.gd): cabe em 76x70, com os
## pés na linha 73, reduzindo pela metade antes do tamanho final.
func _save_sprite(art: Image, mask: Image, game_name: String) -> void:
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
	sprite.save_png(ProjectSettings.globalize_path(PRONTOS + game_name + ".png"))
	sprite_mask.save_png(ProjectSettings.globalize_path(PRONTOS + game_name + "_time.png"))
