extends SceneTree

## Gera os desenhos do jogo (80x80 por casa, suavizados) em assets/:
##   sprites/units/<unidade>.png        + <unidade>_time.png (máscara)
##   sprites/cities/<classe>.png         + <classe>_time.png (máscara)
##   sprites/cities/<classe>_ruinas.png  (a mesma cidade, destruída)
##   sprites/improvements/fazenda_destruida.png, madeireira_destruida.png
##   tiles/pradaria.png, floresta.png, agua.png, cerrado.png (sem emenda)
##
## Cada desenho é feito com formas vetoriais (curvas, gradientes de luz e
## sombra) num canvas K vezes maior e reduzido com filtro: as bordas ficam
## suaves, sem serrilhado. Depois ganha um contorno escuro suave.
##
## COR DO JOGADOR: cada desenho é feito duas vezes, com a cor de time preta e
## branca. O PNG principal é a versão preta; a máscara (_time.png, tons de
## cinza) é a diferença entre as duas. No jogo, cada pixel recebe + máscara x
## cor do jogador (Unit.team_texture), o que funciona com bordas suavizadas.
##
## Precisa renderizar, então roda com janela (sem --headless):
##   godot_console.cmd --path . --script tools/art/gen_art.gd
## Atenção: SOBRESCREVE os PNGs (inclusive os editados à mão).

const S := 80
const K := 4
const UNITS_DIR := "res://assets/sprites/units/"
const CITIES_DIR := "res://assets/sprites/cities/"
const IMPROVEMENTS_DIR := "res://assets/sprites/improvements/"
const TILES_DIR := "res://assets/tiles/"
## Desenho das cidades: 128x128 (1,6 casa, City.SPRITE_SIZE), desenhado num
## espaço de 112 unidades.
const CITY_SIZE := 128
const CITY_DESIGN := 112.0

const OUTLINE := Color8(32, 22, 18)
const SKIN := Color8(236, 186, 140)
const SKIN_D := Color8(200, 140, 98)
const HAIR := Color8(92, 56, 32)
const BRONZE := Color8(212, 158, 66)
const BRONZE_L := Color8(250, 222, 140)
const BRONZE_D := Color8(146, 98, 38)
const IRON := Color8(184, 190, 200)
const IRON_L := Color8(240, 244, 250)
const WOOD := Color8(160, 108, 58)
const WOOD_D := Color8(108, 68, 36)
const LEATHER := Color8(132, 86, 48)
const LEATHER_D := Color8(88, 54, 30)
const LINEN := Color8(230, 216, 178)
const STRAW := Color8(236, 204, 104)
const HORSE := Color8(160, 100, 58)
const HORSE_D := Color8(110, 66, 38)
const MANE := Color8(58, 36, 24)
const WHITE := Color8(244, 244, 238)
const STONE := Color8(214, 206, 186)
const STONE_D := Color8(150, 140, 120)
const ROOF := Color8(190, 84, 54)
const THATCH := Color8(204, 168, 86)
const PLASTER := Color8(232, 214, 176)
const DOOR := Color8(54, 38, 28)
const ASH := Color8(70, 66, 62)
const EMBER := Color8(255, 140, 40)
## Pano queimado: a "cor de time" das ruínas (sem dono).
const BURNT_CLOTH := Color8(64, 50, 42)

var _vp: SubViewport
var _canvas: Node2D
var _job: Callable
var _scale := 1.0
var c: Node2D # canvas em que os desenhos são feitos
var team := Color.BLACK
var _rng := RandomNumberGenerator.new()
## Texturas usadas em desenhos compostos: guardadas até o fim, senão somem antes
## de o desenho ser renderizado.
var _keep: Array[ImageTexture] = []


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("TEMPO ESGOTADO")
		quit(99))
	_run()


func _run() -> void:
	_vp = SubViewport.new()
	_vp.msaa_2d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_canvas = Node2D.new()
	_canvas.draw.connect(_on_draw)
	_vp.add_child(_canvas)
	c = _canvas

	var units := {"guerreiro": warrior, "arqueiro": archer, "cavaleiro": horseman,
			"colono": settler, "trabalhador": worker}
	for unit_name: String in units:
		await save_team_art(UNITS_DIR + unit_name, S, units[unit_name])
	var tiles := {"pradaria": grassland, "floresta": forest, "agua": water, "cerrado": cerrado}
	for tile_name: String in tiles:
		var image := shrink(await render(S, tiles[tile_name], false), S, false)
		_modulate_noise(image, tile_name).save_png(TILES_DIR + tile_name + ".png")
	var cities := {"povoado": village, "vila": town, "cidade": walled_city, "metropole": metropolis}
	for city_name: String in cities:
		await save_team_art(CITIES_DIR + city_name, CITY_SIZE, cities[city_name], CITY_DESIGN)
		team = BURNT_CLOTH
		var intact := await render(CITY_SIZE, cities[city_name], true, CITY_DESIGN)
		var ruined := await ruin(intact, city_name)
		ruined.save_png(CITIES_DIR + city_name + "_ruinas.png")
	shrink(await render(S, burnt_farm), S).save_png(IMPROVEMENTS_DIR + "fazenda_destruida.png")
	shrink(await render(S, burnt_mill), S).save_png(IMPROVEMENTS_DIR + "madeireira_destruida.png")
	print("ok")
	quit()


# --- Renderização ------------------------------------------------------------

func _on_draw() -> void:
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _scale)
	_job.call()


## Desenha [param job] num canvas K vezes maior que [param size] (sem reduzir).
## [param design]: tamanho do espaço em que o desenho foi feito (padrão: size).
func render(size: int, job: Callable, transparent := true, design := 0.0) -> Image:
	_vp.transparent_bg = transparent
	_vp.size = Vector2i(size * K, size * K)
	_scale = float(K) * size / (design if design > 0.0 else float(size))
	_job = job
	_canvas.queue_redraw()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := _vp.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Reduz para [param size] (em etapas de 2x: média suave, sem serrilhado) e
## põe o contorno.
func shrink(image: Image, size: int, with_outline := true) -> Image:
	var current := image.get_width()
	while current > size * 2:
		current /= 2
		image.resize(current, current, Image.INTERPOLATE_BILINEAR)
	image.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return _outline(image) if with_outline else image


## Desenho com a cor do jogador: grava [param path].png (cor de time preta) e
## [param path]_time.png (máscara: quanto da cor do jogador entra em cada pixel).
func save_team_art(path: String, size: int, job: Callable, design := 0.0) -> void:
	team = Color.BLACK
	var dark := shrink(await render(size, job, true, design), size)
	team = Color.WHITE
	var light := shrink(await render(size, job, true, design), size)
	var mask := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var a := dark.get_pixel(x, y)
			var b := light.get_pixel(x, y)
			var amount := clampf(((b.r - a.r) + (b.g - a.g) + (b.b - a.b)) / 3.0, 0.0, 1.0)
			mask.set_pixel(x, y, Color(amount, amount, amount))
	dark.save_png(path + ".png")
	mask.save_png(path + "_time.png")


## Contorno escuro de ~1 pixel, suave (usa a transparência dos vizinhos).
func _outline(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var result := image.duplicate()
	for y in h:
		for x in w:
			var pixel := image.get_pixel(x, y)
			if pixel.a >= 0.99:
				continue
			var near := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
					near = maxf(near, image.get_pixelv(n).a * (1.0 if d.x == 0 or d.y == 0 else 0.7))
			var oa := near * 0.9
			var alpha := pixel.a + oa * (1.0 - pixel.a)
			if alpha <= 0.0:
				continue
			var color := (pixel * pixel.a + OUTLINE * oa * (1.0 - pixel.a)) / alpha
			color.a = alpha
			result.set_pixel(x, y, color)
	return result


## Variação de cor de grande escala, sem emenda (ruído que se repete na borda).
func _modulate_noise(image: Image, tile_name: String) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = tile_name.hash()
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var pattern := noise.get_seamless_image(S, S)
	var amount: float = {"pradaria": 0.16, "floresta": 0.12, "agua": 0.2, "cerrado": 0.14}[tile_name]
	for y in S:
		for x in S:
			var factor := 1.0 + (pattern.get_pixel(x, y).r - 0.5) * 2.0 * amount
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * factor, pixel.g * factor, pixel.b * factor, 1.0))
	return image


func _tex(image: Image) -> ImageTexture:
	var texture := ImageTexture.create_from_image(image)
	_keep.append(texture)
	return texture


# --- Formas -------------------------------------------------------------------

func ell_points(center: Vector2, r: Vector2, from := 0.0, to := TAU, n := 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(from, to, float(i) / n)
		points.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
	return points


## Elipse com volume: gradiente radial com a luz vindo de cima à esquerda.
func ball(center: Vector2, r: Vector2, color: Color, light := 0.22, shade := 0.25) -> void:
	var steps := 9
	for i in steps:
		var t := float(i) / (steps - 1)
		var radius := r * (1.0 - t * 0.8)
		var offset := Vector2(-0.32, -0.36) * r * t
		c.draw_colored_polygon(ell_points(center + offset, radius), color.darkened(shade).lerp(color.lightened(light), t))


## Polígono com gradiente vertical (claro em cima, escuro embaixo) e um leve
## gradiente horizontal (luz da esquerda).
func gpoly(points: PackedVector2Array, color: Color, light := 0.18, shade := 0.22) -> void:
	var top := INF
	var bottom := -INF
	var left := INF
	var right := -INF
	for p in points:
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	var colors := PackedColorArray()
	for p in points:
		var ty := (p.y - top) / maxf(bottom - top, 0.001)
		var tx := (p.x - left) / maxf(right - left, 0.001)
		colors.append(color.lightened(light).lerp(color.darkened(shade), clampf(ty * 0.75 + tx * 0.35, 0.0, 1.0)))
	c.draw_polygon(points, colors)


## Braço ou perna: traço arredondado com um brilho por cima.
func limb(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	c.draw_line(a, b, color.darkened(0.12), width, true)
	c.draw_circle(a, width / 2.0, color.darkened(0.12))
	c.draw_circle(b, width / 2.0, color.darkened(0.12))
	var side := (b - a).orthogonal().normalized() * width * 0.18
	c.draw_line(a - side, b - side, color.lightened(0.12), width * 0.45, true)


func stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	c.draw_polyline(points, color, width, true)


func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	c.draw_line(a, b, color, width, true)


func pts(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


# --- Partes do corpo ------------------------------------------------------------

func head(center: Vector2) -> void:
	ball(center, Vector2(7, 7.5), SKIN, 0.18, 0.18)
	ball(center + Vector2(7, 1), Vector2(1.6, 1.4), SKIN, 0.1, 0.1) # nariz
	c.draw_circle(center + Vector2(3.6, -1.0), 1.0, OUTLINE) # olho
	line(center + Vector2(2.4, -3.0), center + Vector2(4.8, -3.2), HAIR, 0.8) # sobrancelha


func legs(base_y := 58.0) -> void:
	limb(Vector2(37, base_y), Vector2(36, 70), 4.4, SKIN_D)
	limb(Vector2(44, base_y), Vector2(46, 70), 4.4, SKIN)
	ball(Vector2(35, 71.5), Vector2(3.8, 1.8), LEATHER_D)
	ball(Vector2(47.5, 71.5), Vector2(3.8, 1.8), LEATHER_D)


func tunic(top := 42.0, bottom := 61.0) -> void:
	gpoly(pts([31, top, 49, top, 52.5, bottom, 28.5, bottom]), team)
	for x in [35.0, 40.0, 45.0]:
		line(Vector2(x, top + 6), Vector2(x + (x - 40) * 0.25, bottom - 0.5), team.darkened(0.3), 0.7)


# --- Unidades -------------------------------------------------------------------

## Guerreiro (hoplita): escudo redondo, peitoral e elmo de bronze com crista.
func warrior() -> void:
	# Lança
	line(Vector2(58, 8), Vector2(58, 75), WOOD_D, 2.6)
	line(Vector2(57.4, 8), Vector2(57.4, 75), WOOD, 1.1)
	gpoly(pts([58, 0, 61.5, 8, 58, 14, 54.5, 8]), IRON, 0.3, 0.2)
	legs()
	tunic()
	# Peitoral de bronze e cinto
	gpoly(pts([32, 36, 48, 36, 49.5, 49, 46, 53, 34, 53, 30.5, 49]), BRONZE, 0.3, 0.3)
	ball(Vector2(43.5, 41.5), Vector2(3, 3.8), BRONZE_L, 0.1, 0.1)
	stroke(pts([34, 45, 40, 47, 46, 45]), BRONZE_D, 0.8)
	gpoly(pts([30, 51.5, 50, 51.5, 50.5, 55, 29.5, 55]), LEATHER)
	# Cabeça e elmo coríntio
	head(Vector2(41, 27))
	gpoly(pts([32, 24, 32.5, 34, 35.5, 37, 37.5, 28]), BRONZE, 0.2, 0.3) # nuca
	c.draw_colored_polygon(ell_points(Vector2(41, 26), Vector2(9, 8.5), PI, TAU), BRONZE)
	ball(Vector2(41, 23), Vector2(8, 5), BRONZE, 0.3, 0.05)
	gpoly(pts([45.5, 25, 50, 25.5, 49, 33, 46, 32.5]), BRONZE, 0.2, 0.3) # bochecha
	# Crista de crina na cor do time
	var crest := ell_points(Vector2(40, 22), Vector2(12, 10.5), PI * 1.05, PI * 1.75)
	var inner := ell_points(Vector2(40, 22.5), Vector2(8.5, 6.5), PI * 1.75, PI * 1.05)
	crest.append_array(inner)
	gpoly(crest, team, 0.25, 0.25)
	gpoly(pts([28.5, 19, 31.5, 18, 31, 30, 27, 28]), team.darkened(0.1), 0.15, 0.3)
	# Braço da frente segurando a lança
	limb(Vector2(46, 39), Vector2(55, 45), 3.8, SKIN)
	ball(Vector2(57.5, 45), Vector2(2.8, 2.8), SKIN)
	# Escudo redondo (hoplon)
	ball(Vector2(25, 48), Vector2(14.5, 15.5), BRONZE_D, 0.2, 0.2)
	ball(Vector2(25, 48), Vector2(12, 13), team, 0.25, 0.3)
	c.draw_arc(Vector2(25, 48), 6.5, 0, TAU, 32, team.lightened(0.35), 1.1, true)
	ball(Vector2(25, 48), Vector2(2.6, 2.6), BRONZE_L, 0.2, 0.2)


## Arqueiro: faixa na cabeça, colete de couro, aljava e arco retesado.
func archer() -> void:
	# Aljava nas costas
	gpoly(pts([23, 26, 30, 23, 35, 50, 28.5, 52]), LEATHER, 0.15, 0.3)
	for f in [[24.5, 25.5, WHITE], [27, 24, Color8(220, 70, 55)], [29.5, 23, WHITE]]:
		gpoly(pts([f[0] - 1.6, f[1], f[0] + 1.6, f[1], f[0] + 0.8, f[1] - 7, f[0] - 0.8, f[1] - 7]), f[2], 0.1, 0.2)
	legs()
	tunic()
	# Colete de couro e cinto
	gpoly(pts([32, 37, 46.5, 37, 47.5, 52, 31, 52]), LEATHER, 0.2, 0.25)
	for y in [41.0, 45.0, 49.0]:
		c.draw_circle(Vector2(40, y), 0.7, LEATHER_D)
	gpoly(pts([30, 51.5, 49.5, 51.5, 50, 55, 29.5, 55]), LEATHER_D)
	# Cabelo, cabeça e faixa
	ball(Vector2(38, 23.5), Vector2(8, 7), HAIR, 0.15, 0.2)
	head(Vector2(42, 27))
	var hair := ell_points(Vector2(41, 26.5), Vector2(8.2, 7.8), PI * 0.55, PI * 1.9, 20)
	hair.append(Vector2(38, 26))
	gpoly(hair, HAIR, 0.2, 0.2)
	stroke(ell_points(Vector2(41, 27), Vector2(8, 7.5), PI * 1.02, PI * 1.85, 16), team, 2.6)
	stroke(pts([33.5, 25, 29, 28, 27, 33]), team.darkened(0.15), 2.0)
	# Braço do arco esticado e mão puxando a corda
	limb(Vector2(45, 39), Vector2(60, 41), 3.6, SKIN)
	limb(Vector2(44, 41.5), Vector2(50, 42), 3.4, SKIN_D)
	# Arco
	var bow := ell_points(Vector2(57, 41.5), Vector2(9, 27), -PI * 0.42, PI * 0.42, 24)
	stroke(bow, WOOD_D, 3.0)
	stroke(bow, WOOD, 1.3)
	line(bow[0], Vector2(50, 42), LINEN, 0.8)
	line(Vector2(50, 42), bow[bow.size() - 1], LINEN, 0.8)
	# Flecha
	line(Vector2(42, 42), Vector2(72, 42), WOOD_D, 1.3)
	gpoly(pts([71, 39.5, 77, 42, 71, 44.5]), IRON, 0.3, 0.2)
	gpoly(pts([41, 39.5, 45, 42, 41, 44.5, 39, 42]), WHITE, 0.1, 0.2)


## Cavaleiro: cavalo com crina, manta na cor do time e cavaleiro com lança.
func horseman() -> void:
	# Cauda
	stroke(pts([18, 45, 13, 52, 12, 62]), MANE, 4.5)
	# Pernas do cavalo (as de trás mais escuras)
	for leg in [[23, HORSE_D, -1], [30, HORSE, 1], [48, HORSE_D, -1], [55, HORSE, 1]]:
		limb(Vector2(leg[0], 52), Vector2(leg[0] + leg[2], 70), 4.0, leg[1])
		ball(Vector2(leg[0] + leg[2], 72), Vector2(2.8, 1.8), OUTLINE.lightened(0.15), 0.1, 0.1)
	# Corpo e pescoço
	ball(Vector2(38, 49), Vector2(22, 10.5), HORSE, 0.2, 0.25)
	gpoly(pts([52, 46, 57, 29, 66, 31, 63, 49]), HORSE, 0.2, 0.2)
	# Cabeça
	gpoly(pts([57, 27, 64, 22, 72, 28, 77, 34, 75, 38, 70, 38, 62, 34]), HORSE, 0.25, 0.25)
	gpoly(pts([58, 25, 59, 17, 62.5, 23]), HORSE_D) # orelha
	c.draw_circle(Vector2(66, 28.5), 1.1, OUTLINE)
	c.draw_circle(Vector2(74.5, 35), 0.8, OUTLINE)
	stroke(pts([56, 25, 54, 33, 53, 42]), MANE, 3.5)
	# Manta e sela
	gpoly(pts([29, 39, 47, 39, 49, 53, 27, 53]), team, 0.25, 0.25)
	line(Vector2(27.5, 51.5), Vector2(48.5, 51.5), team.lightened(0.4), 1.0)
	gpoly(pts([31, 36, 45, 36, 44, 41, 32, 41]), LEATHER, 0.2, 0.2)
	# Cavaleiro
	limb(Vector2(40, 42), Vector2(42, 55), 4.4, SKIN_D)
	ball(Vector2(43, 56.5), Vector2(3.5, 2), LEATHER_D)
	gpoly(pts([33, 22, 45, 22, 46.5, 40, 32, 40]), team, 0.25, 0.25)
	gpoly(pts([34, 23, 44.5, 23, 45, 33, 33.5, 33]), BRONZE, 0.3, 0.3)
	limb(Vector2(44, 25), Vector2(51, 29), 3.6, SKIN)
	head(Vector2(40, 14))
	c.draw_colored_polygon(ell_points(Vector2(40, 13), Vector2(8.5, 8), PI, TAU), BRONZE)
	ball(Vector2(40, 10.5), Vector2(7.5, 4.5), BRONZE, 0.3, 0.05)
	gpoly(pts([31.5, 12, 32, 20, 35, 21, 36, 13]), BRONZE, 0.2, 0.3)
	var crest := ell_points(Vector2(39, 9.5), Vector2(10, 8), PI * 1.08, PI * 1.72)
	crest.append_array(ell_points(Vector2(39, 10), Vector2(7, 5), PI * 1.72, PI * 1.08))
	gpoly(crest, team, 0.25, 0.25)
	# Lança
	line(Vector2(52, 6), Vector2(52, 60), WOOD_D, 2.4)
	line(Vector2(51.5, 6), Vector2(51.5, 60), WOOD, 1.0)
	gpoly(pts([52, 0, 55, 7, 52, 11, 49, 7]), IRON, 0.3, 0.2)
	ball(Vector2(52.5, 29), Vector2(2.6, 2.6), SKIN)


## Colono: chapéu de palha, trouxa nas costas e pá.
func settler() -> void:
	# Trouxa nas costas e alça
	ball(Vector2(25, 38), Vector2(9, 12), LINEN, 0.15, 0.3)
	stroke(pts([27, 28, 33, 33, 38, 44]), team.darkened(0.2), 2.0)
	# Pá
	line(Vector2(58, 14), Vector2(58, 62), WOOD_D, 2.6)
	line(Vector2(57.4, 14), Vector2(57.4, 62), WOOD, 1.1)
	gpoly(pts([54.5, 60, 61.5, 60, 61.5, 71, 58, 75, 54.5, 71]), IRON, 0.3, 0.25)
	gpoly(pts([55.5, 12, 60.5, 12, 60.5, 15, 55.5, 15]), WOOD_D)
	legs()
	# Túnica de linho, lenço e faixa na cor do time
	gpoly(pts([31, 37, 49, 37, 52.5, 61, 28.5, 61]), LINEN, 0.15, 0.25)
	gpoly(pts([32, 35.5, 48, 35.5, 46, 40, 34, 40]), team, 0.2, 0.2)
	gpoly(pts([30, 48, 50.5, 48, 51, 51.5, 29.5, 51.5]), team, 0.2, 0.2)
	# Braço segurando a pá
	limb(Vector2(46, 40), Vector2(55, 45), 3.8, SKIN)
	ball(Vector2(57.5, 45), Vector2(2.8, 2.8), SKIN)
	# Cabeça com barba e chapéu de palha
	head(Vector2(41, 27))
	ball(Vector2(44, 33), Vector2(4.5, 3), HAIR, 0.15, 0.15)
	ball(Vector2(40, 21.5), Vector2(15, 3.6), STRAW, 0.2, 0.25)
	gpoly(pts([33, 21, 34.5, 12, 45.5, 12, 47, 21]), STRAW, 0.25, 0.2)
	gpoly(pts([33.6, 18, 46.4, 18, 46.8, 20.5, 33.2, 20.5]), team, 0.2, 0.2)


## Trabalhador: gorro na cor do time, avental de couro e machado.
func worker() -> void:
	# Machado
	line(Vector2(52, 70), Vector2(59, 18), WOOD_D, 2.8)
	line(Vector2(51.4, 70), Vector2(58.4, 18), WOOD, 1.2)
	gpoly(pts([55, 11, 66, 8, 70, 15, 67, 25, 57, 21]), IRON, 0.3, 0.25)
	stroke(pts([66, 8.5, 70, 15, 67, 24.5]), IRON_L, 1.2)
	legs()
	tunic()
	# Avental de couro
	gpoly(pts([34, 43, 47, 43, 48.5, 60, 32.5, 60]), LEATHER, 0.2, 0.3)
	gpoly(pts([30.5, 42, 49.5, 42, 49.5, 44.5, 30.5, 44.5]), LEATHER_D)
	# Braços
	limb(Vector2(33, 39), Vector2(29, 47), 3.8, SKIN_D)
	limb(Vector2(46, 39), Vector2(54, 43), 3.8, SKIN)
	ball(Vector2(55.5, 43), Vector2(2.8, 2.8), SKIN)
	# Cabeça com barba e gorro
	head(Vector2(41, 27))
	ball(Vector2(44, 33), Vector2(4.5, 3), HAIR, 0.15, 0.15)
	var cap := ell_points(Vector2(40, 23), Vector2(8.6, 7.5), PI, TAU)
	gpoly(cap, team, 0.25, 0.25)
	gpoly(pts([31, 22, 49.5, 22, 49.5, 25, 31, 25]), team.darkened(0.25), 0.1, 0.1)
	ball(Vector2(40, 15.5), Vector2(2.5, 2.2), team.lightened(0.2), 0.2, 0.2)


## Ícone do Templo: zigurate de pedra com santuário e chama.

# --- Terrenos (sem emenda: o que passa da borda aparece do outro lado) ----------

## Chama [param job](deslocamento) nas 9 cópias do quadro, para os enfeites
## que passam da borda continuarem na casa vizinha.
func tiled(job: Callable) -> void:
	for dy in [-S, 0, S]:
		for dx in [-S, 0, S]:
			job.call(Vector2(dx, dy))


func grassland() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(118, 172, 62))
	_rng.seed = 11
	var tufts := []
	for i in 150:
		tufts.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randi() % 3, _rng.randf_range(2.5, 4.5)])
	var flowers := []
	for i in 9:
		flowers.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randi() % 2])
	tiled(func(o: Vector2) -> void:
		for t in tufts:
			var color: Color = [Color8(92, 146, 46), Color8(146, 196, 80), Color8(104, 160, 52)][t[1]]
			var p: Vector2 = t[0] + o
			var h: float = t[2]
			for k in [-1.0, 0.0, 1.0]:
				line(p, p + Vector2(k * h * 0.35, -h + absf(k) * 0.8), color, 0.7)
		for f in flowers:
			var p: Vector2 = f[0] + o
			c.draw_circle(p, 1.0, WHITE if f[1] == 0 else Color8(250, 220, 80))
			c.draw_circle(p, 0.4, Color8(240, 160, 40)))


func forest() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(46, 92, 38))
	_rng.seed = 7
	# Árvores espalhadas ao acaso (sem ficarem coladas), copas de tamanhos
	# diferentes, cada uma com lóbulos irregulares
	var trees := []
	while trees.size() < 11:
		var p := Vector2(_rng.randf() * S, _rng.randf() * S)
		var ok := true
		for t in trees:
			var d: Vector2 = (t[0] - p).abs()
			d = Vector2(minf(d.x, S - d.x), minf(d.y, S - d.y)) # distância contando a repetição
			if d.length() < 17:
				ok = false
		if ok:
			var lobes := []
			for k in 6:
				var a := _rng.randf() * TAU
				lobes.append([Vector2(cos(a), sin(a) * 0.8) * _rng.randf_range(0.35, 0.6), _rng.randf_range(0.45, 0.62)])
			trees.append([p, _rng.randf_range(10, 14), _rng.randi() % 4, lobes])
	trees.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	tiled(func(o: Vector2) -> void:
		for t in trees:
			var p: Vector2 = t[0] + o
			c.draw_colored_polygon(ell_points(p + Vector2(3, 6), Vector2(t[1] * 1.05, t[1] * 0.7)), Color(0.04, 0.1, 0.03, 0.5)))
	tiled(func(o: Vector2) -> void:
		for t in trees:
			var p: Vector2 = t[0] + o
			var r: float = t[1]
			var color: Color = [Color8(62, 134, 50), Color8(80, 150, 56), Color8(52, 120, 62), Color8(96, 150, 50)][t[2]]
			for lobe in t[3]:
				ball(p + lobe[0] * r, Vector2.ONE * r * lobe[1], color, 0.12, 0.35)
			ball(p + Vector2(-0.15, -0.2) * r, Vector2(r * 0.55, r * 0.5), color, 0.32, 0.2))


func water() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(50, 108, 184))
	_rng.seed = 5
	var waves := []
	for i in 16:
		waves.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(3, 6)])
	tiled(func(o: Vector2) -> void:
		for w in waves:
			var p: Vector2 = w[0] + o
			stroke(ell_points(p, Vector2(w[1], w[1] * 0.45), PI * 1.15, PI * 1.85, 10), Color(0.75, 0.88, 1.0, 0.55), 0.9)
			stroke(ell_points(p + Vector2(0, 1.2), Vector2(w[1], w[1] * 0.45), PI * 1.15, PI * 1.85, 10), Color(0.1, 0.25, 0.5, 0.25), 0.8))


func cerrado() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(190, 172, 100))
	_rng.seed = 3
	var tufts := []
	for i in 70:
		tufts.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randi() % 3])
	var shrubs := []
	for i in 6:
		shrubs.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(2.5, 4)])
	var stones := []
	for i in 8:
		stones.append(Vector2(_rng.randf() * S, _rng.randf() * S))
	tiled(func(o: Vector2) -> void:
		for t in tufts:
			var color: Color = [Color8(150, 140, 64), Color8(214, 196, 120), Color8(132, 128, 60)][t[1]]
			var p: Vector2 = t[0] + o
			for k in [-1.0, 0.0, 1.0]:
				line(p, p + Vector2(k * 1.4, -3.2 + absf(k)), color, 0.7)
		for s in stones:
			ball(s + o, Vector2(1.2, 0.8), Color8(160, 150, 130), 0.2, 0.2)
		for s in shrubs:
			var p: Vector2 = s[0] + o
			c.draw_colored_polygon(ell_points(p + Vector2(1, 2), Vector2(s[1], s[1] * 0.5)), Color(0.2, 0.15, 0.05, 0.3))
			ball(p, Vector2(s[1], s[1] * 0.8), Color8(110, 128, 58), 0.2, 0.25))




# --- Cidades (128x128 = 1,6 casa; desenhadas num espaço de 112) -------------------

## Cabana redonda com telhado cônico de palha.
func hut(base: Vector2, w: float, h: float) -> void:
	gpoly(pts([base.x - w, base.y - h * 0.45, base.x + w, base.y - h * 0.45, base.x + w, base.y, base.x - w, base.y]), Color8(200, 170, 120), 0.15, 0.25)
	gpoly(pts([base.x - w * 0.3, base.y - h * 0.3, base.x + w * 0.1, base.y - h * 0.3, base.x + w * 0.1, base.y, base.x - w * 0.3, base.y]), DOOR, 0.05, 0.1)
	gpoly(pts([base.x - w * 1.25, base.y - h * 0.4, base.x, base.y - h * 1.2, base.x + w * 1.25, base.y - h * 0.4]), THATCH, 0.25, 0.3)
	for k in 3:
		var t := (k + 1) / 4.0
		line(Vector2(base.x - w * 1.25 * (1 - t), base.y - h * (0.4 + 0.8 * t)), Vector2(base.x - w * 1.25 * (1 - t) + 4, base.y - h * (0.4 + 0.8 * t) + 2.5), THATCH.darkened(0.3), 0.6)


## Casa de reboco com telhado de telha (duas águas).
func house(base: Vector2, w: float, h: float, roof := ROOF) -> void:
	gpoly(pts([base.x - w, base.y - h, base.x + w, base.y - h, base.x + w, base.y, base.x - w, base.y]), PLASTER, 0.15, 0.25)
	gpoly(pts([base.x - w * 0.25, base.y - h * 0.55, base.x + w * 0.2, base.y - h * 0.55, base.x + w * 0.2, base.y, base.x - w * 0.25, base.y]), DOOR, 0.05, 0.1)
	gpoly(pts([base.x + w * 0.45, base.y - h * 0.75, base.x + w * 0.8, base.y - h * 0.75, base.x + w * 0.8, base.y - h * 0.45, base.x + w * 0.45, base.y - h * 0.45]), DOOR.lightened(0.1), 0.05, 0.1)
	gpoly(pts([base.x - w - 2, base.y - h + 1, base.x - w * 0.4, base.y - h - w * 0.75, base.x + w * 0.4, base.y - h - w * 0.75, base.x + w + 2, base.y - h + 1]), roof, 0.25, 0.25)
	for k in 3:
		var y := base.y - h - w * 0.75 * (k + 1) / 4.0
		line(Vector2(base.x - w * (1.0 - 0.6 * (k + 1) / 4.0), y), Vector2(base.x + w * (1.0 - 0.6 * (k + 1) / 4.0), y), roof.darkened(0.3), 0.6)


func flag(pole: Vector2, height: float) -> void:
	line(pole, pole - Vector2(0, height), WOOD_D, 1.4)
	var top := pole - Vector2(0, height)
	gpoly(pts([top.x + 0.5, top.y, top.x + 11, top.y + 2, top.x + 9, top.y + 4.5, top.x + 11, top.y + 7, top.x + 0.5, top.y + 6.5]), team, 0.25, 0.25)


## Torre redonda de pedra com telhado cônico na cor do time e bandeira.
func tower(x: float, top: float, bottom: float, w: float) -> void:
	gpoly(pts([x - w, top, x + w, top, x + w, bottom, x - w, bottom]), STONE, 0.25, 0.3)
	for y in range(int(top) + 8, int(bottom), 8):
		line(Vector2(x - w, y), Vector2(x + w, y), STONE_D, 0.5)
	gpoly(pts([x - w - 2, top + 1, x, top - w * 2.2, x + w + 2, top + 1]), team, 0.25, 0.3)
	gpoly(pts([x - 2.5, top + 10, x + 2.5, top + 10, x + 2.5, top + 18, x - 2.5, top + 18]), DOOR, 0.05, 0.1)
	flag(Vector2(x, top - w * 2.1), 12)


## Muralha de pedra com ameias de [param left] a [param right], do topo [param top]
## até [param bottom].
func wall(left: float, right: float, top: float, bottom: float) -> void:
	gpoly(pts([left, top, right, top, right, bottom, left, bottom]), STONE, 0.2, 0.3)
	for x in range(int(left), int(right) - 2, 8):
		gpoly(pts([x, top - 6, x + 5, top - 6, x + 5, top, x, top]), STONE, 0.2, 0.2)
	for y in [top + (bottom - top) * 0.33, top + (bottom - top) * 0.66]:
		line(Vector2(left, y), Vector2(right, y), STONE_D, 0.6)


func gate(center: Vector2, w: float, h: float) -> void:
	var points := ell_points(Vector2(center.x, center.y - h + w), Vector2(w, w), PI, TAU, 16)
	points.append(Vector2(center.x + w, center.y))
	points.append(Vector2(center.x - w, center.y))
	gpoly(points, DOOR, 0.05, 0.1)


## Templo grego: degraus, colunas e frontão.
func greek_temple(left: float, right: float, base_y: float, height: float) -> void:
	var w := right - left
	gpoly(pts([left - 2, base_y - 4, right + 2, base_y - 4, right + 2, base_y, left - 2, base_y]), STONE_D, 0.2, 0.2)
	gpoly(pts([left, base_y - height, right, base_y - height, right, base_y - 4, left, base_y - 4]), STONE.darkened(0.2), 0.1, 0.2)
	var columns := int(w / 7.0)
	for k in columns:
		var x := left + 2 + k * (w - 6) / maxf(columns - 1, 1)
		gpoly(pts([x, base_y - height, x + 3.5, base_y - height, x + 3.5, base_y - 4, x, base_y - 4]), WHITE, 0.1, 0.25)
	gpoly(pts([left - 3, base_y - height, right + 3, base_y - height, right + 3, base_y - height - 3, left - 3, base_y - height - 3]), STONE, 0.2, 0.2)
	gpoly(pts([left - 3, base_y - height - 3, (left + right) / 2.0, base_y - height - 3 - w * 0.25, right + 3, base_y - height - 3]), STONE, 0.3, 0.2)


## Povoado: cabanas de palha, fogueira e bandeira.
func village() -> void:
	c.draw_colored_polygon(ell_points(Vector2(56, 80), Vector2(46, 20)), Color(0.42, 0.32, 0.18, 0.55))
	flag(Vector2(78, 66), 40)
	hut(Vector2(36, 66), 12, 30)
	hut(Vector2(74, 72), 11, 28)
	hut(Vector2(54, 84), 13, 32)
	hut(Vector2(30, 92), 10, 24)
	# Fogueira com fumaça
	for k in 4:
		c.draw_circle(Vector2(90 + k * 1.5, 70 - k * 9), 3.0 + k * 1.2, Color(0.85, 0.85, 0.85, 0.35 - k * 0.07))
	ball(Vector2(88, 88), Vector2(5, 2), WOOD_D, 0.1, 0.1)
	gpoly(pts([85, 88, 88, 78, 91, 88]), EMBER, 0.3, 0.1)


## Vila: casas de reboco e telha, poço e paliçada de madeira.
func town() -> void:
	c.draw_colored_polygon(ell_points(Vector2(56, 78), Vector2(50, 26)), Color(0.45, 0.36, 0.22, 0.5))
	house(Vector2(30, 64), 11, 13)
	house(Vector2(58, 58), 13, 15)
	house(Vector2(86, 64), 10, 12)
	house(Vector2(44, 86), 11, 13)
	house(Vector2(76, 88), 12, 14)
	# Poço no meio da praça
	ball(Vector2(60, 78), Vector2(5.5, 3), STONE_D, 0.2, 0.2)
	ball(Vector2(60, 77), Vector2(3.5, 1.6), Color8(40, 70, 110), 0.1, 0.1)
	# Faixa na cor do time na casa principal
	gpoly(pts([51, 48, 65, 48, 63, 53, 53, 53]), team, 0.25, 0.25)
	flag(Vector2(96, 72), 38)
	# Paliçada na frente, com a entrada no meio
	for x in range(8, 106, 5):
		if x > 48 and x < 64:
			continue
		var top := 92.0 + sin(x * 0.7) * 1.5
		gpoly(pts([x, top + 3, x + 2.5, top, x + 5, top + 3, x + 5, 106, x, 106]), WOOD, 0.2, 0.3)


## Cidade: muralha com portão, duas torres, casas e templo.
func walled_city() -> void:
	greek_temple(40, 72, 54, 16)
	for h in [[20, 58, 14], [80, 56, 14], [30, 48, 10], [88, 46, 10]]:
		house(Vector2(h[0], h[1] + 8), h[2], 16)
	wall(6, 106, 66, 100)
	gate(Vector2(56, 100), 9, 18)
	for x in [14.0, 98.0]:
		tower(x, 52, 102, 10)


## Metrópole: muralha alta, três torres, coliseu, templo grande e muitas casas.
func metropolis() -> void:
	# Casas ao fundo
	for h in [[12, 44, 8], [100, 42, 8], [92, 56, 9], [20, 58, 9], [48, 30, 7], [66, 28, 7]]:
		house(Vector2(h[0], h[1] + 6), h[2], 12)
	# Coliseu: anel de pedra com arcos
	ball(Vector2(34, 46), Vector2(24, 13), STONE, 0.25, 0.3)
	ball(Vector2(34, 44), Vector2(17, 7.5), Color8(196, 170, 120), 0.1, 0.2)
	for k in 9:
		var x := 14.0 + k * 5.0
		var y := 50.0 + sin(k / 8.0 * PI) * 5.0
		var arch := ell_points(Vector2(x, y), Vector2(1.6, 1.6), PI, TAU, 8)
		arch.append(Vector2(x + 1.6, y + 3.5))
		arch.append(Vector2(x - 1.6, y + 3.5))
		gpoly(arch, DOOR, 0.05, 0.1)
	# Templo grande
	greek_temple(60, 100, 50, 18)
	# Muralha alta com três torres e o portão na do meio
	wall(4, 108, 62, 104)
	for x in [10.0, 102.0]:
		tower(x, 50, 106, 9)
	tower(56, 46, 106, 12)
	gate(Vector2(56, 106), 7, 16)


# --- Ruínas ----------------------------------------------------------------------

## A cidade [param intact] (desenhada em tamanho grande, com a cor de time
## queimada) vira ruínas: o alto dos prédios desmorona (mais em cima que
## embaixo, num recorte irregular), as cores ficam acinzentadas e escuras com
## manchas de fuligem, e por cima entram entulho, brasas e fumaça.
func ruin(intact: Image, city_name: String) -> Image:
	var size := intact.get_width()
	var noise := FastNoiseLite.new()
	noise.seed = city_name.hash()
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var soot := FastNoiseLite.new()
	soot.seed = city_name.hash() + 1
	soot.frequency = 0.03
	for y in size:
		for x in size:
			var pixel := intact.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			if n + (1.0 - float(y) / size) * 1.1 > 1.05:
				intact.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var gray := pixel.get_luminance()
			var color := pixel.lerp(Color(gray, gray, gray), 0.55)
			color = color * (0.58 + 0.3 * (soot.get_noise_2d(x, y) * 0.5 + 0.5))
			color.a = pixel.a
			intact.set_pixel(x, y, color)
	var texture := _tex(intact)
	_rng.seed = city_name.hash()
	var rubble := []
	for i in 34:
		rubble.append([Vector2(_rng.randf_range(8, 104), _rng.randf_range(84, 106)), _rng.randf_range(1.5, 3.5), _rng.randi() % 3])
	var embers := []
	for i in 10:
		embers.append(Vector2(_rng.randf_range(14, 98), _rng.randf_range(78, 104)))
	var smokes := []
	for i in 3:
		smokes.append(Vector2(_rng.randf_range(24, 88), _rng.randf_range(60, 84)))
	var job := func() -> void:
		c.draw_colored_polygon(ell_points(Vector2(56, 94), Vector2(52, 14)), Color(0.12, 0.09, 0.07, 0.45))
		c.draw_texture_rect(texture, Rect2(0, 0, CITY_DESIGN, CITY_DESIGN), false)
		for r in rubble:
			var color: Color = [STONE_D.darkened(0.3), ASH, Color8(90, 70, 52)][r[2]]
			ball(r[0], Vector2(r[1], r[1] * 0.7), color, 0.15, 0.25)
		for e in embers:
			c.draw_circle(e, 1.6, Color(EMBER, 0.35))
			c.draw_circle(e, 0.8, EMBER)
		for s in smokes:
			for k in 4:
				c.draw_circle(s + Vector2(k * 2.0, -k * 8.0), 3.5 + k * 1.6, Color(0.5, 0.5, 0.5, 0.32 - k * 0.06))
	var image := await render(CITY_SIZE, job, true, CITY_DESIGN)
	return shrink(image, CITY_SIZE)


## Fazenda pilhada: campo queimado com fileiras de cinza, brasas e fumaça.
func burnt_farm() -> void:
	var field := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		var wobble := 1.0 + 0.05 * sin(a * 5.0 + 1.3)
		field.append(Vector2(40, 42) + Vector2(cos(a) * 33, sin(a) * 29) * wobble)
	gpoly(field, Color8(66, 50, 34), 0.15, 0.25)
	for k in 6:
		var y := 22.0 + k * 8.0
		stroke(pts([12, y, 26, y + 1.5, 40, y, 54, y + 1.5, 68, y]), Color(0.55, 0.53, 0.5, 0.75), 1.6)
	_rng.seed = 21
	for i in 26:
		var p := Vector2(_rng.randf_range(12, 68), _rng.randf_range(18, 66))
		line(p, p + Vector2(_rng.randf_range(-1, 1), -3), Color8(30, 22, 16), 0.9)
	for i in 8:
		var p := Vector2(_rng.randf_range(16, 64), _rng.randf_range(22, 62))
		c.draw_circle(p, 1.8, Color(EMBER, 0.35))
		c.draw_circle(p, 0.9, EMBER)
	for x in [10.0, 70.0]:
		line(Vector2(x, 44), Vector2(x + 1, 54), WOOD_D.darkened(0.4), 2.2)
	for k in 4:
		c.draw_circle(Vector2(46 + k * 2.0, 34 - k * 7.0), 3.5 + k * 1.5, Color(0.55, 0.55, 0.55, 0.38 - k * 0.07))


## Madeireira pilhada: toras carbonizadas sobre um monte de cinzas, com brasas
## e fumaça.
func burnt_mill() -> void:
	ball(Vector2(40, 56), Vector2(30, 13), ASH, 0.2, 0.25)
	for log_data in [[Vector2(16, 54), Vector2(62, 46)], [Vector2(20, 44), Vector2(60, 58)], [Vector2(28, 60), Vector2(66, 56)]]:
		limb(log_data[0], log_data[1], 7.0, Color8(46, 34, 26))
		c.draw_circle(log_data[1], 3.2, Color8(120, 90, 60))
		c.draw_circle(log_data[1], 1.6, Color8(70, 50, 34))
	for p in [Vector2(30, 52), Vector2(46, 50), Vector2(52, 58), Vector2(38, 60)]:
		c.draw_circle(p, 2.2, Color(EMBER, 0.4))
		c.draw_circle(p, 1.1, EMBER)
	for k in 4:
		c.draw_circle(Vector2(42 + k * 2.0, 36 - k * 8.0), 4.0 + k * 1.6, Color(0.55, 0.55, 0.55, 0.38 - k * 0.07))
