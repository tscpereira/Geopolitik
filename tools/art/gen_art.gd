extends SceneTree

## Gera os desenhos do jogo (80x80 por casa) em assets/, no estilo pintado
## (desde 23/10/2026; referência aprovada pelo usuário): proporções reais,
## paleta terrosa, volume sombreado (tubos e esferas com luz de cima à
## esquerda), textura de materiais (cota de malha, palha, pedra, madeira),
## contorno fino e discreto e prédios em perspectiva 3/4 sobre uma "ilha" de
## chão com árvores. O lanceiro é um hoplita (Antiguidade); os outros seguem a
## referência medieval.
##   sprites/units/<unidade>.png        + <unidade>_time.png (máscara)
##   sprites/cities/<classe>.png         + <classe>_time.png (máscara)
##   sprites/cities/<classe>_ruinas.png  (a mesma cidade, destruída)
##   sprites/improvements/madeireira.png, madeireira_destruida.png,
##       fazenda.png (vista de cima, lotes em retalhos), fazenda_obra.png
##       (terra lavrada), fazenda_destruida.png
##   tiles/pradaria.png, floresta.png, agua.png, cerrado.png (sem emenda)
##
## COR DO JOGADOR: cada desenho com cor de time é feito duas vezes, com a cor
## preta e branca. O PNG principal é a versão preta; a máscara (_time.png, em
## tons de cinza) é a diferença. No jogo, cada pixel recebe + máscara x cor do
## jogador (Unit.team_texture).
##
## Precisa renderizar, então roda com janela (sem --headless):
##   godot_console.cmd --path . --script tools/art/gen_art.gd
## Atenção: SOBRESCREVE os PNGs (inclusive os editados à mão).

const S := 80
const K := 6
const LIGHT := Vector2(-0.6, -0.8)
const UNITS_DIR := "res://assets/sprites/units/"
const CITIES_DIR := "res://assets/sprites/cities/"
const IMPROVEMENTS_DIR := "res://assets/sprites/improvements/"
const TILES_DIR := "res://assets/tiles/"
## Cidades: 128x128 (1,6 casa, City.SPRITE_SIZE), desenhadas num espaço de 112.
const CITY_SIZE := 128
const CITY_DESIGN := 112.0

const RIM := Color8(28, 22, 18)
const SKIN := Color8(196, 146, 108)
const MAIL := Color8(132, 136, 140)
const STEEL := Color8(168, 172, 176)
const BRONZE := Color8(176, 130, 58)
const LEATHER := Color8(98, 64, 38)
const LEATHER_L := Color8(132, 90, 54)
const LINEN := Color8(206, 194, 164)
const BOOT := Color8(70, 48, 30)
const HOSE := Color8(78, 66, 52)
const WOOD := Color8(118, 82, 50)
const WOOD_D := Color8(78, 54, 32)
const HAIR := Color8(70, 50, 34)
const HORSE := Color8(112, 68, 40)
const MANE := Color8(42, 28, 20)
const BRASS := Color8(196, 158, 80)
const THATCH := Color8(170, 138, 78)
const PLASTER := Color8(206, 190, 156)
const TIMBER := Color8(72, 50, 32)
const STONE := Color8(150, 144, 132)
const ROOF_RED := Color8(150, 52, 40)
const GRASS := Color8(92, 110, 50)
const GRASS_L := Color8(122, 136, 64)
const DIRT := Color8(112, 90, 60)
const FOLIAGE := Color8(62, 86, 40)
const CROP := Color8(196, 164, 82)
const SOIL := Color8(84, 62, 40)
const CABBAGE := Color8(96, 132, 70)
const ASH := Color8(64, 60, 56)
const EMBER := Color8(255, 140, 40)
## Pano queimado: a "cor de time" das ruínas (sem dono).
const BURNT_CLOTH := Color8(60, 46, 38)

var _vp: SubViewport
var _canvas: Node2D
var _job: Callable
var _scale := 1.0
var _zoom := 1.0
var _pivot := Vector2.ZERO
var c: Node2D
var team := Color.BLACK
var _rng := RandomNumberGenerator.new()
var _keep: Array[ImageTexture] = []


func _initialize() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		print("TEMPO ESGOTADO")
		quit(99))
	_run()


func _run() -> void:
	_vp = SubViewport.new()
	_vp.msaa_2d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_canvas = Node2D.new()
	# _zoom amplia o desenho a partir do ponto _pivot (os pés das unidades)
	_canvas.draw.connect(func() -> void:
		_canvas.draw_set_transform(_pivot * _scale * (1.0 - _zoom), 0.0, Vector2.ONE * _scale * _zoom)
		_job.call())
	_vp.add_child(_canvas)
	c = _canvas

	var units := {"guerreiro": hoplite, "arqueiro": archer, "cavaleiro": horseman, "colono": settler, "trabalhador": worker}
	_zoom = 1.1
	_pivot = Vector2(42, 75)
	for unit_name: String in units:
		await save_team_art(UNITS_DIR + unit_name, S, units[unit_name])
	_zoom = 1.0
	var cities := {"povoado": village, "vila": town, "cidade": castle, "metropole": metropolis}
	for city_name: String in cities:
		await save_team_art(CITIES_DIR + city_name, CITY_SIZE, cities[city_name], CITY_DESIGN)
		team = BURNT_CLOTH
		var intact := await render(CITY_SIZE, cities[city_name], true, CITY_DESIGN)
		(await ruin(intact, city_name, CITY_SIZE, CITY_DESIGN)).save_png(CITIES_DIR + city_name + "_ruinas.png")
	team = BURNT_CLOTH
	var mill := await render(S, lumber_camp)
	shrink(mill.duplicate(), S).save_png(IMPROVEMENTS_DIR + "madeireira.png")
	(await ruin(mill, "madeireira", S, float(S))).save_png(IMPROVEMENTS_DIR + "madeireira_destruida.png")
	shrink(await render(S, farm_patchwork, false), S, false, false).save_png(IMPROVEMENTS_DIR + "fazenda.png")
	shrink(await render(S, farm_new, false), S, false, false).save_png(IMPROVEMENTS_DIR + "fazenda_obra.png")
	shrink(await render(S, burnt_farm, false), S, false, false).save_png(IMPROVEMENTS_DIR + "fazenda_destruida.png")
	var tiles := {"pradaria": grass_tile, "floresta": forest_tile, "agua": water_tile, "cerrado": cerrado_tile}
	for tile_name: String in tiles:
		shrink(await render(S, tiles[tile_name], false), S, false, false).save_png(TILES_DIR + tile_name + ".png")
	print("ok")
	quit()


# --- Renderização ------------------------------------------------------------

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


## Textura (granulado e manchas), redução em etapas de 2x e contorno fino.
## Terrenos ficam sem textura extra (ela marcaria a emenda entre as casas).
func shrink(image: Image, size: int, with_rim := true, with_grain := true) -> Image:
	if with_grain:
		_grain(image)
	var current := image.get_width()
	while current > size * 2:
		current /= 2
		image.resize(current, current, Image.INTERPOLATE_BILINEAR)
	image.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return _rim(image) if with_rim else image


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


## Textura: granulado fino e manchas maiores, só onde há desenho.
func _grain(image: Image) -> void:
	var fine := FastNoiseLite.new()
	fine.seed = 3
	fine.frequency = 0.09
	var blotch := FastNoiseLite.new()
	blotch.seed = 8
	blotch.frequency = 0.012
	blotch.fractal_octaves = 3
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var k := 1.0 + fine.get_noise_2d(x, y) * 0.07 + blotch.get_noise_2d(x, y) * 0.08
			image.set_pixel(x, y, Color(pixel.r * k, pixel.g * k, pixel.b * k, pixel.a))


## Contorno fino e discreto (meia força, só nos 4 vizinhos).
func _rim(image: Image) -> Image:
	var w := image.get_width()
	var result := image.duplicate()
	for y in w:
		for x in w:
			var pixel := image.get_pixel(x, y)
			if pixel.a >= 0.99:
				continue
			var near := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < w:
					near = maxf(near, image.get_pixelv(n).a)
			var oa := near * 0.45
			var alpha := pixel.a + oa * (1.0 - pixel.a)
			if alpha <= 0.0:
				continue
			var color := (pixel * pixel.a + RIM * oa * (1.0 - pixel.a)) / alpha
			color.a = alpha
			result.set_pixel(x, y, color)
	return result


func _tex(image: Image) -> ImageTexture:
	var texture := ImageTexture.create_from_image(image)
	_keep.append(texture)
	return texture


## O desenho [param intact] (em tamanho grande, com a cor de time queimada) vira
## ruínas: o alto desmorona num recorte irregular (mais em cima que embaixo),
## as cores ficam acinzentadas e escuras com fuligem, e por cima entram
## entulho, brasas e fumaça. [param design]: espaço do desenho.
func ruin(intact: Image, ruin_name: String, size: int, design: float) -> Image:
	var full := intact.get_width()
	var noise := FastNoiseLite.new()
	noise.seed = ruin_name.hash()
	noise.frequency = 0.008
	noise.fractal_octaves = 3
	var soot := FastNoiseLite.new()
	soot.seed = ruin_name.hash() + 1
	soot.frequency = 0.02
	for y in full:
		for x in full:
			var pixel := intact.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			if n + (1.0 - float(y) / full) * 1.1 > 1.05:
				intact.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var gray := pixel.get_luminance()
			var color := pixel.lerp(Color(gray, gray, gray), 0.55)
			color = color * (0.55 + 0.3 * (soot.get_noise_2d(x, y) * 0.5 + 0.5))
			color.a = pixel.a
			intact.set_pixel(x, y, color)
	var texture := _tex(intact)
	var u := design / 112.0 # medidas abaixo pensadas para as cidades (112)
	_rng.seed = ruin_name.hash()
	var rubble := []
	for i in 34:
		rubble.append([Vector2(_rng.randf_range(10, 102), _rng.randf_range(80, 104)) * u, _rng.randf_range(1.2, 3.0) * u, _rng.randi() % 3])
	var embers := []
	for i in 10:
		embers.append(Vector2(_rng.randf_range(16, 96), _rng.randf_range(76, 102)) * u)
	var smokes := []
	for i in 3:
		smokes.append(Vector2(_rng.randf_range(26, 86), _rng.randf_range(58, 82)) * u)
	var job := func() -> void:
		c.draw_texture_rect(texture, Rect2(0, 0, design, design), false)
		for r in rubble:
			var color: Color = [STONE.darkened(0.35), ASH, Color8(84, 66, 48)][r[2]]
			sphere(r[0], Vector2(r[1], r[1] * 0.7), color)
		for e in embers:
			c.draw_circle(e, 1.6 * u, Color(EMBER, 0.35))
			c.draw_circle(e, 0.8 * u, EMBER)
		for s in smokes:
			for k in 4:
				c.draw_circle(s + Vector2(k * 2.0, -k * 8.0) * u, (3.5 + k * 1.6) * u, Color(0.5, 0.5, 0.5, 0.3 - k * 0.06))
	return shrink(await render(size, job, true, design), size)


func lit(color: Color, k: float) -> Color:
	return Color(clampf(color.r * k, 0, 1), clampf(color.g * k, 0, 1), clampf(color.b * k, 0, 1), color.a)


func ell(center: Vector2, r: Vector2, from := 0.0, to := TAU, n := 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(from, to, float(i) / n)
		points.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
	return points


func pts(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


## Esfera / elipsoide: gradiente radial deslocado para a luz, borda escura e um
## brilho especular ([param shine] 0 = fosco).
func sphere(center: Vector2, r: Vector2, color: Color, shine := 0.0) -> void:
	var steps := 16
	for i in steps:
		var t := float(i) / (steps - 1)
		var radius := r * (1.0 - t * 0.92)
		var offset := LIGHT * r * 0.42 * t
		c.draw_colored_polygon(ell(center + offset, radius, 0, TAU, 32), lit(color, 0.5 + 0.7 * pow(t, 0.8)))
	if shine > 0.0:
		c.draw_colored_polygon(ell(center + LIGHT * r * 0.5, r * 0.18, 0, TAU, 16), Color(1, 1, 0.95, shine))


## Tubo afinando ao longo de [param line] (braço, perna, pescoço, tronco),
## sombreado como cilindro: claro do lado da luz, escuro do outro.
func tube(line: Array, radii: Array, color: Color) -> void:
	var bands := [-1.0, -0.6, -0.2, 0.2, 0.6, 1.0]
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var n := (b - a).orthogonal().normalized()
		var facing := n.dot(LIGHT)
		for k in bands.size() - 1:
			var t0: float = bands[k]
			var t1: float = bands[k + 1]
			var quad := PackedVector2Array([a + n * radii[i] * t0, a + n * radii[i] * t1,
					b + n * radii[i + 1] * t1, b + n * radii[i + 1] * t0])
			var colors := PackedColorArray()
			for t in [t0, t1, t1, t0]:
				colors.append(lit(color, 0.72 + 0.38 * facing * t + 0.28 * sqrt(maxf(0.0, 1.0 - t * t))))
			c.draw_polygon(quad, colors)
	for i in range(1, line.size() - 1):
		sphere(line[i], Vector2.ONE * radii[i] * 0.98, color)


## Polígono com luz: os vértices do lado da luz mais claros, os de baixo mais
## escuros (oclusão no pé da forma).
func shaded(points: PackedVector2Array, color: Color, strength := 0.35) -> void:
	var center := Vector2.ZERO
	var top := INF
	var bottom := -INF
	for p in points:
		center += p
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	center /= points.size()
	var span := maxf(bottom - top, 1.0)
	var colors := PackedColorArray()
	for p in points:
		var toward := -(p - center).dot(LIGHT) / span
		colors.append(lit(color, 1.0 + strength * toward - 0.15 * (p.y - top) / span))
	c.draw_polygon(points, colors)


func stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	c.draw_polyline(points, color, width, true)


func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	c.draw_line(a, b, color, width, true)


## Dobras do tecido: traços escuros e claros finos.
func folds(from: Vector2, to: Vector2, count: int, length: float, color: Color) -> void:
	for i in count:
		var p := from.lerp(to, (i + 0.5) / count)
		line(p, p + Vector2((i - count / 2.0) * 0.3, length), lit(color, 0.7), 0.5)
		line(p + Vector2(0.6, 0), p + Vector2(0.6 + (i - count / 2.0) * 0.3, length * 0.8), lit(color, 1.15), 0.35)




# --- Texturas de material ---------------------------------------------------------

## Cota de malha: fileiras de aneizinhos (arcos) num retângulo.
func chainmail(left: float, top: float, right: float, bottom: float, color: Color) -> void:
	var y := top + 0.6
	var row := 0
	while y < bottom:
		var x := left + (0.6 if row % 2 == 1 else 0.0)
		while x < right:
			c.draw_arc(Vector2(x, y), 0.5, 0, PI, 4, lit(color, 0.62), 0.22, true)
			c.draw_arc(Vector2(x, y - 0.15), 0.45, PI * 1.1, PI * 1.6, 3, lit(color, 1.35), 0.15, true)
			x += 1.2
		y += 1.0
		row += 1


## Pedras irregulares num retângulo: cada bloco com um tom, juntas escuras.
func stone_blocks(left: float, top: float, right: float, bottom: float, color: Color, block := Vector2(4.5, 2.6)) -> void:
	var y := top
	var row := 0
	while y < bottom - 0.2:
		var h := minf(block.y, bottom - y)
		var x := left - (block.x * 0.5 if row % 2 == 1 else 0.0)
		while x < right:
			var w := block.x * _rng.randf_range(0.75, 1.25)
			var x0 := maxf(x, left)
			var x1 := minf(x + w, right)
			if x1 > x0:
				var tone := _rng.randf_range(0.82, 1.12)
				c.draw_rect(Rect2(x0 + 0.15, y + 0.15, x1 - x0 - 0.3, h - 0.3), lit(color, tone))
				c.draw_line(Vector2(x0 + 0.3, y + 0.35), Vector2(x1 - 0.3, y + 0.35), lit(color, tone * 1.15), 0.25)
			x += w
		y += block.y
		row += 1


## Palha: muitos fios do cume para o beiral, em tons variados.
func thatch(ridge_a: Vector2, ridge_b: Vector2, eave_a: Vector2, eave_b: Vector2, density := 90) -> void:
	shaded(PackedVector2Array([ridge_a, ridge_b, eave_b, eave_a]), THATCH, 0.35)
	for i in density:
		var t := _rng.randf()
		var top := ridge_a.lerp(ridge_b, t)
		var bottom := eave_a.lerp(eave_b, t)
		var s := _rng.randf_range(0.2, 0.75)
		var e := minf(s + _rng.randf_range(0.2, 0.45), 1.0)
		line(top.lerp(bottom, s), top.lerp(bottom, e), lit(THATCH, _rng.randf_range(0.62, 1.22)), 0.35)
	# Beiral grosso e escuro, cumeeira
	line(eave_a, eave_b, lit(THATCH, 0.55), 1.1)
	line(ridge_a, ridge_b, lit(THATCH, 0.7), 1.0)


## Telhas: fileiras de arcos num cone (torre) ou num plano.
func roof_tiles_cone(apex: Vector2, base_center: Vector2, r: float, color: Color) -> void:
	var cone := ell(base_center, Vector2(r, r * 0.38), 0, PI, 16)
	cone.append(apex)
	shaded(cone, color, 0.55)
	for k in 5:
		var t := (k + 1) / 6.0
		var center := apex.lerp(base_center, t)
		c.draw_arc(center, r * t, 0.25, PI - 0.25, 10, lit(color, 0.65), 0.3, true)


# --- Corpo do soldado (de pé, virado para a direita; pés em y = 74) ----------------

func soldier_legs() -> void:
	tube([Vector2(37.5, 48), Vector2(37, 60)], [2.8, 2.2], HOSE.darkened(0.15))
	tube([Vector2(43.5, 48), Vector2(44.5, 60)], [2.8, 2.2], HOSE)
	tube([Vector2(37, 59), Vector2(36.2, 71.5)], [2.3, 1.9], BOOT.darkened(0.15))
	tube([Vector2(44.5, 59), Vector2(45.8, 71.5)], [2.3, 1.9], BOOT)
	sphere(Vector2(35.8, 73), Vector2(3.0, 1.4), BOOT.darkened(0.2))
	sphere(Vector2(47.6, 73), Vector2(3.2, 1.5), BOOT)
	line(Vector2(34.5, 60), Vector2(39.5, 60), LEATHER_L, 0.6) # dobra da bota
	line(Vector2(42.2, 60), Vector2(47, 60), LEATHER_L, 0.6)


## Cota de malha (camisão até a coxa) e o tabardo na cor do time por cima,
## com barra mais escura e cinto de couro com fivela.
func hauberk_and_tabard(tabard := true) -> void:
	shaded(pts([33, 40, 47, 40, 48.6, 54, 31.4, 54]), MAIL, 0.4)
	chainmail(32.5, 41, 48, 53.5, MAIL)
	shaded(pts([34, 25, 46.5, 25, 47.5, 33, 46.5, 41, 33.5, 41, 32.5, 33]), MAIL, 0.45)
	chainmail(33.5, 26, 46.5, 40.5, MAIL)
	if tabard:
		var front := pts([35.8, 25.5, 45, 25.5, 45.6, 41, 46.4, 56, 34.6, 56, 35.2, 41])
		shaded(front, team, 0.45)
		folds(Vector2(35.5, 46), Vector2(45.5, 46), 5, 9, team)
		stroke(pts([34.6, 56, 46.4, 56]), lit(team, 0.55), 0.9) # barra
		stroke(pts([35.8, 25.5, 35.2, 41, 34.6, 56]), lit(team, 0.7), 0.4)
		stroke(pts([45, 25.5, 45.6, 41, 46.4, 56]), lit(team, 0.75), 0.4)
	shaded(pts([33, 40, 47.6, 40, 47.6, 42.2, 33, 42.2]), LEATHER, 0.3)
	sphere(Vector2(42, 41.1), Vector2(1.0, 0.9), BRASS, 0.5)
	line(Vector2(44, 42), Vector2(44.5, 46), LEATHER, 0.6) # ponta do cinto


func back_arm() -> void:
	tube([Vector2(34.5, 28), Vector2(33, 35), Vector2(33.5, 41)], [2.1, 1.8, 1.6], MAIL.darkened(0.12))
	sphere(Vector2(33.6, 42), Vector2(1.6, 1.6), LEATHER)


## Cabeça com a coifa de malha em volta (pescoço e queixo).
func head_with_coif(center: Vector2) -> void:
	sphere(center + Vector2(-0.8, 1.4), Vector2(5.0, 5.5), MAIL)
	chainmail(center.x - 5.0, center.y - 1.5, center.x + 3.5, center.y + 6.4, MAIL)
	sphere(center + Vector2(0.6, 0.2), Vector2(3.3, 3.9), SKIN)
	sphere(center + Vector2(3.6, 0.8), Vector2(0.9, 1.1), SKIN)
	c.draw_circle(center + Vector2(2.2, -0.5), 0.42, Color8(24, 18, 14))
	line(center + Vector2(1.4, -1.4), center + Vector2(3.0, -1.5), HAIR, 0.45)


## Elmo cônico com nasal (normando).
func nasal_helmet(center: Vector2) -> void:
	var dome := pts([center.x - 4.6, center.y - 0.6, center.x - 3.8, center.y - 4.4, center.x - 0.2, center.y - 7.6,
			center.x + 3.8, center.y - 4.4, center.x + 4.8, center.y - 0.6])
	shaded(dome, STEEL, 0.65)
	line(Vector2(center.x - 4.7, center.y - 0.5), Vector2(center.x + 4.9, center.y - 0.5), lit(STEEL, 0.6), 1.0)
	line(Vector2(center.x - 0.4, center.y - 7.2), Vector2(center.x - 2.6, center.y - 1.2), Color(1, 1, 1, 0.45), 0.5)
	line(Vector2(center.x + 3.6, center.y - 0.4), Vector2(center.x + 3.9, center.y + 3.2), lit(STEEL, 0.85), 0.9)


## Chapéu de ferro de aba larga (arqueiro).
func kettle_hat(center: Vector2) -> void:
	sphere(center + Vector2(0, -0.6), Vector2(6.8, 1.7), STEEL.darkened(0.05), 0.3)
	shaded(ell(center + Vector2(0, -0.8), Vector2(4.4, 5.0), PI, TAU, 18), STEEL, 0.65)
	line(Vector2(center.x - 6.8, center.y - 0.4), Vector2(center.x + 6.8, center.y - 0.4), lit(STEEL, 0.55), 0.5)


# --- Unidades ---------------------------------------------------------------------

## Arqueiro: túnica longa na cor do time, gibão de couro, chapéu de ferro,
## aljava na cintura e arco longo retesado.
func archer() -> void:
	soldier_legs()
	tube([Vector2(34.5, 28), Vector2(38, 33), Vector2(46.5, 30.5)], [2.0, 1.7, 1.5], team.darkened(0.2)) # braço da corda
	shaded(pts([33, 25, 46.5, 25, 47.5, 33, 48.5, 56, 31.5, 56, 32.5, 33]), team, 0.45)
	folds(Vector2(33, 47), Vector2(48, 47), 6, 9, team)
	shaded(pts([34.5, 26, 46, 26, 46.8, 40, 34, 40]), LEATHER_L, 0.5) # gibão
	for y in [29.0, 32.5, 36.0]:
		line(Vector2(36, y), Vector2(44.5, y), LEATHER, 0.35)
	shaded(pts([33, 40, 47.6, 40, 47.6, 42, 33, 42]), LEATHER, 0.3)
	sphere(Vector2(42, 41), Vector2(0.9, 0.8), BRASS, 0.5)
	# Aljava pendurada na cintura, com as penas das flechas
	shaded(pts([30.5, 39, 34, 38, 35.5, 53, 32, 54]), LEATHER, 0.5)
	for i in 4:
		shaded(pts([30.4 + i * 1.0, 39.5, 31.4 + i * 1.0, 39, 31 + i * 1.0, 35.5]), Color8(214, 208, 192), 0.3)
	# Braço do arco esticado
	tube([Vector2(45.5, 28), Vector2(52, 28.8), Vector2(58, 29.2)], [2.0, 1.7, 1.4], team.darkened(0.1))
	sphere(Vector2(58.6, 29.3), Vector2(1.6, 1.6), LEATHER)
	head_with_coif(Vector2(41.5, 19))
	kettle_hat(Vector2(41.5, 17))
	# Arco longo e corda puxada até o rosto
	var bow := PackedVector2Array([Vector2(56.5, 4), Vector2(59, 10), Vector2(60, 19), Vector2(59.8, 29.2),
			Vector2(60, 40), Vector2(59, 48), Vector2(56.5, 55)])
	stroke(bow, WOOD_D, 1.7)
	stroke(bow, WOOD.lightened(0.1), 0.55)
	line(Vector2(56.5, 4), Vector2(46.5, 29.2), Color8(214, 206, 186), 0.32)
	line(Vector2(46.5, 29.2), Vector2(56.5, 55), Color8(214, 206, 186), 0.32)
	line(Vector2(45.5, 29.2), Vector2(67, 29.2), WOOD, 0.6)
	shaded(pts([67, 28.2, 70, 29.2, 67, 30.2]), STEEL, 0.5)
	shaded(pts([45, 28.2, 47.8, 29.2, 45, 30.2, 44, 29.2]), Color8(214, 208, 192), 0.2)


## Cavaleiro: cavalo com manta (caparazão) na cor do time, cavaleiro de cota
## de malha com tabardo, elmo de nasal e lança.
func horseman() -> void:
	var far := HORSE.darkened(0.25)
	for i in 5:
		stroke(pts([13, 39, 10.5 - i * 0.3, 46, 9.5 + i * 0.5, 57]), lit(MANE, 0.8 + i * 0.1), 1.0)
	tube([Vector2(21, 48), Vector2(23, 58), Vector2(20, 65), Vector2(20.5, 72)], [4.2, 2.4, 1.6, 1.4], far)
	tube([Vector2(46, 50), Vector2(45, 61), Vector2(46, 72)], [3.0, 1.8, 1.4], far)
	sphere(Vector2(20.8, 73), Vector2(1.9, 1.2), MANE)
	sphere(Vector2(46.3, 73), Vector2(1.9, 1.2), MANE)
	sphere(Vector2(23, 43), Vector2(10.5, 9.5), HORSE, 0.15)
	sphere(Vector2(35, 45), Vector2(14, 8.5), HORSE, 0.1)
	sphere(Vector2(48, 43), Vector2(7.5, 8.5), HORSE, 0.12)
	tube([Vector2(49, 41), Vector2(55, 31), Vector2(59, 24)], [6.5, 5.0, 3.8], HORSE)
	tube([Vector2(59, 22), Vector2(65, 26.5), Vector2(69.5, 30.5)], [3.8, 3.0, 2.3], HORSE)
	sphere(Vector2(69.8, 30.8), Vector2(2.6, 2.2), HORSE.darkened(0.1))
	shaded(pts([57.5, 20, 58.5, 14.5, 60.5, 19.5]), HORSE, 0.3)
	c.draw_circle(Vector2(62.5, 23.5), 0.6, Color8(16, 10, 8))
	for i in 6:
		var p := Vector2(48, 38).lerp(Vector2(58, 20), i / 5.0)
		stroke(pts([p.x, p.y, p.x - 2.5, p.y + 3, p.x - 3.5, p.y + 6]), lit(MANE, 0.9 + 0.2 * (i % 2)), 1.0)
	# Rédeas
	line(Vector2(66, 28), Vector2(47, 31), LEATHER, 0.4)
	tube([Vector2(26, 49), Vector2(29, 58), Vector2(26.5, 65), Vector2(27, 72)], [4.4, 2.5, 1.7, 1.4], HORSE)
	tube([Vector2(50, 50), Vector2(51, 61), Vector2(51.5, 72)], [3.1, 1.9, 1.4], HORSE)
	sphere(Vector2(27.3, 73), Vector2(2.0, 1.2), MANE)
	sphere(Vector2(51.8, 73), Vector2(2.0, 1.2), MANE)
	# Caparazão: manta longa na cor do time, com barra recortada
	var cloth := pts([13, 37, 50, 35, 53, 48, 52, 54])
	for i in 9:
		var x := 52.0 - i * 4.4
		cloth.append(Vector2(x - 1.2, 56.5))
		cloth.append(Vector2(x - 2.4, 54.5))
	cloth.append(Vector2(12, 52))
	shaded(cloth, team, 0.5)
	folds(Vector2(15, 44), Vector2(50, 44), 9, 9, team)
	stroke(pts([12.5, 51, 52.5, 53]), BRASS, 0.5)
	# Cavaleiro
	tube([Vector2(37, 35), Vector2(42, 43), Vector2(41.5, 52)], [2.8, 2.1, 1.6], HOSE)
	tube([Vector2(41.6, 47), Vector2(41.5, 53)], [1.8, 1.7], BOOT)
	sphere(Vector2(42.6, 54), Vector2(2.3, 1.2), BOOT)
	shaded(pts([33.5, 19, 42.5, 19, 43.5, 28, 42.5, 36, 33, 36, 32.5, 28]), MAIL, 0.45)
	chainmail(33, 20, 43, 35.5, MAIL)
	shaded(pts([35, 19.5, 41.5, 19.5, 42, 36, 34.5, 36]), team, 0.45)
	shaded(pts([33, 30, 43, 30, 43, 31.8, 33, 31.8]), LEATHER, 0.3)
	tube([Vector2(41.5, 22), Vector2(45, 28), Vector2(48.5, 27)], [1.9, 1.6, 1.4], MAIL)
	sphere(Vector2(49, 27), Vector2(1.6, 1.6), LEATHER)
	head_with_coif(Vector2(38.5, 13))
	nasal_helmet(Vector2(38.5, 11.8))
	line(Vector2(49, -1), Vector2(49, 60), WOOD_D, 1.7)
	line(Vector2(48.6, -1), Vector2(48.6, 60), WOOD, 0.6)
	shaded(pts([49, -3, 51, 3, 49, 7, 47, 3]), STEEL, 0.6)
	shaded(pts([49.3, 5, 55, 6.5, 49.3, 9]), team, 0.3) # flâmula


## Colono: túnica na cor do time, capuz de lã, trouxa nas costas e pá.
func settler() -> void:
	sphere(Vector2(30.5, 32), Vector2(5.5, 7.5), Color8(170, 150, 112)) # trouxa
	stroke(pts([31.5, 25, 36, 29, 40, 38]), LEATHER, 0.9)
	line(Vector2(53, 13), Vector2(54, 64), WOOD_D, 1.8)
	line(Vector2(52.6, 13), Vector2(53.6, 64), WOOD, 0.6)
	shaded(pts([51, 62, 57, 62, 57, 70, 54, 73.5, 51, 70]), STEEL, 0.6)
	soldier_legs()
	shaded(pts([33.5, 25, 46.5, 25, 47.5, 33, 48.5, 55, 31.5, 55, 32.5, 33]), team, 0.45)
	folds(Vector2(33, 46), Vector2(48, 46), 6, 9, team)
	shaded(pts([33, 40, 47.6, 40, 47.6, 42, 33, 42]), LEATHER, 0.3)
	sphere(Vector2(44.5, 44), Vector2(2.0, 2.4), LEATHER_L) # bolsa
	tube([Vector2(45.5, 28), Vector2(49, 35), Vector2(53, 36)], [2.0, 1.7, 1.4], team.darkened(0.1))
	sphere(Vector2(53.5, 36), Vector2(1.7, 1.7), SKIN)
	# Cabeça com capuz de lã
	sphere(Vector2(40, 20), Vector2(5.6, 6.0), Color8(120, 96, 64))
	sphere(Vector2(41.8, 19.6), Vector2(3.3, 3.9), SKIN)
	sphere(Vector2(44.8, 20.2), Vector2(0.9, 1.1), SKIN)
	c.draw_circle(Vector2(43.4, 18.9), 0.42, Color8(24, 18, 14))
	c.draw_colored_polygon(ell(Vector2(42.4, 22.6), Vector2(2.4, 1.6), 0.0, PI, 14), HAIR)
	shaded(pts([34.5, 22, 38, 26, 42, 26.5, 38.5, 28.5, 34, 27]), Color8(120, 96, 64), 0.3) # gola do capuz


## Trabalhador: túnica na cor do time, avental de couro, gorro e machado erguido.
func worker() -> void:
	soldier_legs()
	shaded(pts([33.5, 25, 46.5, 25, 47.5, 33, 48.5, 53, 31.5, 53, 32.5, 33]), team, 0.45)
	folds(Vector2(33, 45), Vector2(48, 45), 6, 7, team)
	shaded(pts([35.5, 32, 45.5, 32, 46.5, 54, 34.5, 54]), LEATHER, 0.4) # avental
	shaded(pts([33, 39, 47.6, 39, 47.6, 41, 33, 41]), LEATHER.darkened(0.2), 0.3)
	back_arm()
	# Machado erguido em diagonal, com as duas mãos
	line(Vector2(38, 44), Vector2(57, 12), WOOD_D, 1.9)
	line(Vector2(37.6, 43.6), Vector2(56.6, 11.6), WOOD.lightened(0.05), 0.6)
	shaded(pts([53.5, 9.5, 59.5, 5.5, 63.5, 9.5, 61.5, 16, 57, 15]), STEEL, 0.65)
	line(Vector2(59.8, 5.8), Vector2(63.3, 9.8), Color(1, 1, 1, 0.55), 0.5)
	tube([Vector2(45.5, 28), Vector2(48.5, 33), Vector2(48, 29)], [2.0, 1.7, 1.4], team.darkened(0.1))
	sphere(Vector2(48.2, 28.6), Vector2(1.6, 1.6), SKIN)
	sphere(Vector2(42.5, 38.5), Vector2(1.6, 1.6), SKIN)
	head_with_coif(Vector2(41, 19))
	shaded(ell(Vector2(40.6, 17.6), Vector2(4.6, 4.2), PI, TAU, 16), LEATHER_L, 0.5) # gorro de couro
	line(Vector2(36, 17.6), Vector2(45.2, 17.6), LEATHER, 0.8)


# --- Cenário dos prédios ------------------------------------------------------------

## "Ilha" de chão sob o prédio: grama com borda que some aos poucos e terra
## batida no meio.
func ground_base(center: Vector2, r: Vector2, dirt := 0.55) -> void:
	for i in 10:
		var t := float(i) / 9.0
		c.draw_colored_polygon(ell(center, r * (1.0 - t * 0.25), 0, TAU, 40), Color(lit(GRASS, 0.9 + t * 0.15), 0.12 + t * 0.1))
	for i in 8:
		var t := float(i) / 7.0
		c.draw_colored_polygon(ell(center + Vector2(0, 1), r * dirt * (1.0 - t * 0.35), 0, TAU, 40), Color(lit(DIRT, 0.9 + t * 0.15), 0.18))
	for i in 40:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.3, 0.95)
		var p := center + Vector2(cos(a) * r.x, sin(a) * r.y) * d
		line(p, p + Vector2(_rng.randf_range(-0.5, 0.5), -1.4), lit(GRASS_L, _rng.randf_range(0.8, 1.2)), 0.35)


## Árvore de copa larga (vista de lado/cima): sombra, tronco e copa em bolos.
func tree(base: Vector2, size: float) -> void:
	c.draw_colored_polygon(ell(base + Vector2(size * 0.4, size * 0.15), Vector2(size * 0.9, size * 0.35)), Color(0.05, 0.06, 0.02, 0.35))
	tube([base, base + Vector2(0, -size * 0.6)], [size * 0.16, size * 0.12], WOOD_D)
	var crown := base + Vector2(0, -size * 1.05)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		sphere(crown + Vector2(cos(a) * size * 0.42, sin(a) * size * 0.3), Vector2.ONE * size * 0.5, lit(FOLIAGE, _rng.randf_range(0.85, 1.1)))
	sphere(crown + Vector2(-size * 0.15, -size * 0.18), Vector2.ONE * size * 0.5, lit(FOLIAGE, 1.15), 0.08)


## Casa de enxaimel (vigas aparentes) com telhado de palha ou de telha, em 3/4.
func cottage(x: float, y: float, w: float, h: float, d: float, tiled := false, roof := THATCH) -> void:
	var rh := h * 0.9 # altura do telhado
	var ridge_l := Vector2(x + d * 0.25, y - d * 0.22 - rh)
	var ridge_r := Vector2(x + w + d * 0.25, y - d * 0.22 - rh)
	# Sombra no chão
	c.draw_colored_polygon(pts([x, y + h, x + w + d * 0.5 + 6, y + h - d * 0.45 + 3, x + w + d * 0.5 + 8, y + h + 3, x + 4, y + h + 3]), Color(0.05, 0.04, 0.02, 0.35))
	# Parede da frente com vigas, porta e janela
	shaded(pts([x, y, x + w, y, x + w, y + h, x, y + h]), PLASTER, 0.3)
	for bx in [x, x + w * 0.5, x + w]:
		line(Vector2(bx, y), Vector2(bx, y + h), TIMBER, 0.8)
	line(Vector2(x, y + 0.3), Vector2(x + w, y + 0.3), TIMBER, 0.8)
	line(Vector2(x, y + h - 0.3), Vector2(x + w, y + h - 0.3), TIMBER, 0.8)
	line(Vector2(x, y + h), Vector2(x + w * 0.5, y), TIMBER, 0.6)
	shaded(pts([x + w * 0.62, y + h * 0.35, x + w * 0.85, y + h * 0.35, x + w * 0.85, y + h, x + w * 0.62, y + h]), Color8(70, 46, 28), 0.2)
	shaded(pts([x + w * 0.14, y + h * 0.3, x + w * 0.34, y + h * 0.3, x + w * 0.34, y + h * 0.6, x + w * 0.14, y + h * 0.6]), Color8(40, 32, 26), 0.1)
	# Empena da direita (mais escura)
	var gable := pts([x + w, y, x + w + d * 0.5, y - d * 0.45, x + w + d * 0.5, y + h - d * 0.45, x + w, y + h])
	shaded(gable, PLASTER.darkened(0.3), 0.2)
	shaded(PackedVector2Array([Vector2(x + w, y), Vector2(x + w + d * 0.5, y - d * 0.45), ridge_r]), PLASTER.darkened(0.25), 0.2)
	line(Vector2(x + w, y), ridge_r, TIMBER, 0.6)
	line(Vector2(x + w + d * 0.5, y - d * 0.45), ridge_r, TIMBER, 0.6)
	# Telhado (água da frente)
	var eave_l := Vector2(x - 1.5, y + 1)
	var eave_r := Vector2(x + w + 1.5, y + 1)
	if tiled:
		shaded(PackedVector2Array([ridge_l, ridge_r + Vector2(1, 0), eave_r, eave_l]), roof, 0.4)
		for k in 6:
			var t := (k + 0.5) / 6.0
			var a := ridge_l.lerp(eave_l, t)
			var b := (ridge_r + Vector2(1, 0)).lerp(eave_r, t)
			line(a, b, lit(roof, 0.65), 0.35)
		for k in int(w / 1.6):
			var t := (k + 0.5) / int(w / 1.6)
			line(ridge_l.lerp(ridge_r, t), eave_l.lerp(eave_r, t), lit(roof, 0.8), 0.2)
		line(eave_l, eave_r, lit(roof, 0.5), 0.8)
	else:
		thatch(ridge_l, ridge_r + Vector2(1.2, 0), eave_l, eave_r, int(w * 6))


func banner(pole: Vector2, height: float) -> void:
	line(pole, pole - Vector2(0, height), WOOD_D, 0.9)
	var top := pole - Vector2(0, height)
	line(top + Vector2(-2.5, 0.6), top + Vector2(2.5, 0.6), WOOD_D, 0.6)
	shaded(pts([top.x - 2.5, top.y + 0.8, top.x + 2.5, top.y + 0.8, top.x + 2.5, top.y + 8, top.x, top.y + 6.5, top.x - 2.5, top.y + 8]), team, 0.4)
	line(top + Vector2(0, 2.5), top + Vector2(0, 5.5), Color(1, 1, 1, 0.7), 0.6)
	line(top + Vector2(-1.2, 3.5), top + Vector2(1.2, 3.5), Color(1, 1, 1, 0.7), 0.6)


## Povoado: casas de enxaimel com palha, fogueira, paliçada e árvores.
func village() -> void:
	_rng.seed = 31
	ground_base(Vector2(56, 74), Vector2(54, 34))
	for t in [[Vector2(16, 58), 7.0], [Vector2(28, 48), 8.0], [Vector2(92, 52), 7.5], [Vector2(80, 46), 6.5]]:
		tree(t[0], t[1])
	cottage(26, 62, 18, 10, 12)
	cottage(62, 58, 20, 11, 12)
	banner(Vector2(52, 74), 26)
	# Fogueira com pedras e fumaça
	for k in 8:
		var a := k * TAU / 8.0
		sphere(Vector2(56, 84) + Vector2(cos(a) * 3.6, sin(a) * 1.6), Vector2(1.1, 0.8), STONE)
	shaded(pts([53.5, 84, 56, 77.5, 58.5, 84]), Color8(236, 140, 50), 0.6)
	shaded(pts([54.8, 84, 56, 80.5, 57.2, 84]), Color8(255, 220, 120), 0.3)
	for k in 5:
		c.draw_circle(Vector2(57 + k * 1.2, 74 - k * 7), 2.2 + k * 1.2, Color(0.7, 0.7, 0.7, 0.28 - k * 0.05))
	cottage(18, 82, 16, 9, 10)
	cottage(68, 86, 18, 10, 11)
	# Paliçada na frente
	for i in 22:
		var x := 8.0 + i * 4.6
		var y := 102.0 - absf(x - 56) * 0.18
		tube([Vector2(x, y), Vector2(x, y - 7)], [1.0, 0.9], WOOD)
		shaded(pts([x - 1, y - 7, x, y - 9, x + 1, y - 7]), WOOD, 0.3)
	for t in [[Vector2(8, 96), 6.0], [Vector2(104, 92), 6.5]]:
		tree(t[0], t[1])


## Torre redonda de pedra com telhado cônico de telhas na cor do time.
func stone_tower(x: float, top: float, bottom: float, r: float, roof := true) -> void:
	c.draw_colored_polygon(pts([x - r, bottom, x + r + 6, bottom - 2, x + r + 8, bottom + 3, x - r + 3, bottom + 3]), Color(0.05, 0.04, 0.02, 0.35))
	tube([Vector2(x, top), Vector2(x, bottom)], [r, r], STONE)
	var y := top + 2.0
	var row := 0
	while y < bottom:
		c.draw_arc(Vector2(x, y), r, 0.12, PI - 0.12, 12, lit(STONE, 0.7), 0.3, true)
		var a := 0.5 + (row % 2) * 0.35
		while a < PI - 0.3:
			var p := Vector2(x + cos(a) * r, y + sin(a) * r * 0.25)
			line(p, p + Vector2(0, -2.2), lit(STONE, 0.72), 0.25)
			a += 0.7
		y += 2.4
		row += 1
	shaded(pts([x - 0.9, top + 5, x + 0.9, top + 5, x + 0.9, top + 8.5, x - 0.9, top + 8.5]), Color8(30, 24, 20), 0.1)
	if roof:
		roof_tiles_cone(Vector2(x, top - r * 2.3), Vector2(x, top), r * 1.3, ROOF_RED)
		var pole := Vector2(x, top - r * 2.25)
		line(pole, pole - Vector2(0, 6), WOOD_D, 0.6)
		shaded(pts([pole.x, pole.y - 6, pole.x + 5.5, pole.y - 5, pole.x, pole.y - 3]), team, 0.4)
	else:
		for k in 4:
			var cx := x - r + k * r * 0.66
			shaded(pts([cx, top - 2.2, cx + r * 0.4, top - 2.2, cx + r * 0.4, top, cx, top]), STONE, 0.3)


## Muralha reta (frente) de [param left] a [param right], com ameias e blocos.
func curtain_wall(left: float, right: float, top: float, bottom: float) -> void:
	c.draw_colored_polygon(pts([left, bottom, right, bottom, right + 6, bottom + 3, left + 6, bottom + 3]), Color(0.05, 0.04, 0.02, 0.35))
	shaded(pts([left, top, right, top, right, bottom, left, bottom]), STONE, 0.3)
	stone_blocks(left, top + 0.5, right, bottom, STONE)
	shaded(pts([left - 0.5, top - 2.5, right + 0.5, top - 2.5, right + 0.5, top + 0.5, left - 0.5, top + 0.5]), STONE.lightened(0.08), 0.25)
	var x := left
	while x < right - 2:
		shaded(pts([x, top - 6, x + 3.2, top - 6, x + 3.2, top - 2.5, x, top - 2.5]), STONE.lightened(0.05), 0.35)
		x += 5.4


## Cidade: castelo de pedra com muralhas, torres de telhado vermelho, torre de
## menagem, casas de telha, portão com estandartes e árvores em volta.
func castle() -> void:
	_rng.seed = 47
	ground_base(Vector2(56, 74), Vector2(56, 34), 0.5)
	for t in [[Vector2(8, 60), 6.5], [Vector2(104, 58), 7.0], [Vector2(14, 98), 6.0], [Vector2(100, 100), 6.5]]:
		tree(t[0], t[1])
	# Muralha do fundo e torres de trás
	curtain_wall(26, 86, 44, 54)
	stone_tower(26, 38, 56, 5.5)
	stone_tower(86, 38, 56, 5.5)
	# Torre de menagem no meio e casas de telha
	c.draw_colored_polygon(pts([48, 66, 72, 64, 74, 68, 50, 68]), Color(0.05, 0.04, 0.02, 0.35))
	shaded(pts([48, 30, 62, 30, 62, 66, 48, 66]), STONE, 0.3)
	stone_blocks(48, 30.5, 62, 66, STONE)
	shaded(pts([62, 30, 67, 26, 67, 62, 62, 66]), STONE.darkened(0.25), 0.2)
	roof_tiles_cone(Vector2(57, 14), Vector2(57, 30), 9.5, ROOF_RED)
	shaded(pts([53.5, 40, 56.5, 40, 56.5, 45, 53.5, 45]), Color8(30, 24, 20), 0.1)
	var pole := Vector2(57, 15)
	line(pole, pole - Vector2(0, 7), WOOD_D, 0.6)
	shaded(pts([pole.x, pole.y - 7, pole.x + 6, pole.y - 6, pole.x, pole.y - 4]), team, 0.4)
	cottage(30, 60, 12, 7, 8, true, ROOF_RED)
	cottage(70, 58, 12, 7, 8, true, ROOF_RED)
	# Muralhas laterais (vão para o fundo) e a da frente
	shaded(pts([18, 66, 26, 52, 26, 60, 18, 76]), STONE.darkened(0.2), 0.25)
	shaded(pts([86, 52, 94, 66, 94, 76, 86, 60]), STONE.darkened(0.3), 0.2)
	curtain_wall(16, 96, 76, 94)
	# Portão com casa de guarda, porta de madeira e estandartes
	shaded(pts([46, 70, 66, 70, 66, 96, 46, 96]), STONE, 0.3)
	stone_blocks(46, 70.5, 66, 96, STONE)
	var gate := ell(Vector2(56, 86), Vector2(5.5, 5.5), PI, TAU, 16)
	gate.append(Vector2(61.5, 96))
	gate.append(Vector2(50.5, 96))
	shaded(gate, Color8(84, 58, 36), 0.3)
	for gx in [53.0, 56.0, 59.0]:
		line(Vector2(gx, 81.5), Vector2(gx, 96), Color8(52, 36, 22), 0.35)
	for bx in [48.5, 63.5]:
		shaded(pts([bx - 1.8, 74, bx + 1.8, 74, bx + 1.8, 82, bx, 80.5, bx - 1.8, 82]), team, 0.4)
	var x := 46.0
	while x < 65:
		shaded(pts([x, 66, x + 3, 66, x + 3, 70, x, 70]), STONE.lightened(0.05), 0.35)
		x += 5.0
	stone_tower(16, 66, 98, 6.5)
	stone_tower(96, 66, 98, 6.5)


# --- Madeireira (3/4) --------------------------------------------------------------

func log_end(end: Vector2, r: float, length: Vector2) -> void:
	var back := end + length
	tube([back, end], [r * 0.95, r], Color8(90, 64, 40))
	for k in 4:
		var p := back.lerp(end, (k + 0.5) / 4.0)
		c.draw_arc(p, r * 0.98, PI * 0.6, PI * 1.4, 6, Color8(56, 38, 24), 0.3, true)
	sphere(end, Vector2(r * 0.95, r), Color8(196, 160, 110))
	for k in 3:
		c.draw_arc(end + Vector2(0.2, 0.2), r * (0.25 + k * 0.22), 0, TAU, 18, Color8(146, 108, 68), 0.3, true)


## Madeireira: telheiro de tábuas, pilhas de toras, cavalete, tocos e árvores.
func lumber_camp() -> void:
	_rng.seed = 12
	ground_base(Vector2(40, 52), Vector2(38, 24), 0.7)
	for t in [[Vector2(10, 34), 6.0], [Vector2(70, 32), 6.5], [Vector2(62, 22), 5.5]]:
		tree(t[0], t[1])
	# Telheiro: postes e telhado de tábuas inclinado
	c.draw_colored_polygon(pts([28, 50, 62, 46, 66, 50, 32, 54]), Color(0.05, 0.04, 0.02, 0.35))
	for p in [Vector2(30, 48), Vector2(56, 45)]:
		tube([p, p + Vector2(0, -12)], [0.9, 0.9], WOOD_D)
	var roof := pts([26, 37, 58, 32, 63, 25, 31, 30])
	shaded(roof, Color8(110, 82, 54), 0.5)
	for k in 10:
		var t := (k + 0.5) / 10.0
		line(Vector2(26, 37).lerp(Vector2(58, 32), t), Vector2(31, 30).lerp(Vector2(63, 25), t), Color8(70, 50, 32), 0.3)
	line(Vector2(26, 37), Vector2(58, 32), Color8(60, 42, 26), 0.8)
	# Toras sob o telheiro e na frente
	for i in 3:
		log_end(Vector2(33 + i * 4.6, 46), 2.3, Vector2(14, -2.4))
	for log_data in [[Vector2(14, 60), 3.6], [Vector2(21.5, 60), 3.6], [Vector2(29, 60), 3.6], [Vector2(17.8, 53.8), 3.6], [Vector2(25.3, 53.8), 3.6]]:
		log_end(log_data[0], log_data[1], Vector2(15, -3))
	# Cavalete com tora e serra
	for x in [52.0, 62.0]:
		line(Vector2(x - 2.5, 66), Vector2(x + 2, 57), WOOD_D, 0.9)
		line(Vector2(x + 2.5, 66), Vector2(x - 2, 57), WOOD_D, 0.9)
	tube([Vector2(48, 58), Vector2(67, 56)], [2.2, 2.0], Color8(98, 70, 44))
	shaded(pts([56, 53, 63, 51.5, 63, 53.5, 56, 55]), STEEL, 0.6)
	# Tocos com machado e lascas
	for p in [Vector2(70, 62), Vector2(42, 68)]:
		tube([p, p + Vector2(0, 4)], [3.2, 3.5], Color8(92, 66, 42))
		sphere(p, Vector2(3.2, 1.3), Color8(186, 150, 102))
	line(Vector2(69.5, 61.5), Vector2(74, 54.5), WOOD, 0.8)
	shaded(pts([68, 61.5, 71, 59.8, 72.4, 62]), STEEL, 0.5)
	for i in 30:
		var p := Vector2(_rng.randf_range(16, 70), _rng.randf_range(58, 72))
		line(p, p + Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.5, 0.5)), Color8(200, 168, 120), 0.45)


# --- Fazendas vistas de cima (80x80), 3 opções --------------------------------------

## Cerca de varas na borda (vista de cima): trilhos e moirões.
func fence_border(inset: float) -> void:
	var r := Rect2(inset, inset, S - inset * 2, S - inset * 2)
	for side in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		line(side[0] + Vector2(0.6, 0.6), side[1] + Vector2(0.6, 0.6), Color(0, 0, 0, 0.3), 0.9)
		line(side[0], side[1], WOOD, 0.7)
		for k in 9:
			var p: Vector2 = side[0].lerp(side[1], k / 8.0)
			sphere(p, Vector2.ONE * 0.9, WOOD_D)


## Chão de terra lavrada com torrões.
func tilled(rect: Rect2, horizontal := true) -> void:
	c.draw_rect(rect, SOIL)
	var count := int((rect.size.y if horizontal else rect.size.x) / 2.2)
	for k in count:
		var off := (k + 0.5) * 2.2
		if horizontal:
			line(Vector2(rect.position.x, rect.position.y + off), Vector2(rect.end.x, rect.position.y + off), lit(SOIL, 0.7), 0.7)
			line(Vector2(rect.position.x, rect.position.y + off - 0.8), Vector2(rect.end.x, rect.position.y + off - 0.8), lit(SOIL, 1.2), 0.4)
		else:
			line(Vector2(rect.position.x + off, rect.position.y), Vector2(rect.position.x + off, rect.end.y), lit(SOIL, 0.7), 0.7)
			line(Vector2(rect.position.x + off - 0.8, rect.position.y), Vector2(rect.position.x + off - 0.8, rect.end.y), lit(SOIL, 1.2), 0.4)
	for i in int(rect.size.x * rect.size.y / 40.0):
		var p := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		c.draw_circle(p, _rng.randf_range(0.25, 0.5), lit(SOIL, _rng.randf_range(0.7, 1.3)))


## Trigo maduro visto de cima: espigas densas em tons de dourado, com ondas.
func wheat(rect: Rect2, density := 1.0) -> void:
	c.draw_rect(rect, lit(CROP, 0.62))
	for i in int(rect.size.x * rect.size.y * 0.55 * density):
		var p := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		var wave := sin(p.x * 0.18 + p.y * 0.35) * 0.12
		var tone := _rng.randf_range(0.78, 1.12) + wave
		var dir := Vector2(0.45, -1.0).normalized() * _rng.randf_range(0.9, 1.8)
		line(p, p + dir, lit(CROP, tone), 0.32)
		c.draw_circle(p + dir, 0.3, lit(CROP, tone * 1.12))


## Repolhos em grade: cada um com folhas externas e o miolo claro.
func cabbages(rect: Rect2, step := 4.0) -> void:
	tilled(rect)
	var y := rect.position.y + step * 0.5
	while y < rect.end.y:
		var x := rect.position.x + step * 0.5
		while x < rect.end.x:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
			sphere(p, Vector2.ONE * step * 0.42, lit(CABBAGE, _rng.randf_range(0.85, 1.05)))
			for k in 4:
				var a := k * TAU / 4.0 + _rng.randf()
				c.draw_arc(p, step * 0.3, a, a + 1.0, 4, lit(CABBAGE, 0.65), 0.25, true)
			sphere(p + Vector2(-0.2, -0.2), Vector2.ONE * step * 0.17, Color8(170, 196, 120))
			x += step
		y += step


## Fileiras de hortaliças (folhas em tufos) sobre a terra.
func leafy_rows(rect: Rect2, spacing := 4.4, color := Color8(80, 120, 54)) -> void:
	tilled(rect)
	var y := rect.position.y + spacing * 0.5
	while y < rect.end.y:
		var x := rect.position.x + 0.8
		while x < rect.end.x - 0.5:
			var p := Vector2(x, y + _rng.randf_range(-0.3, 0.3))
			sphere(p, Vector2(1.5, 1.2), lit(color, _rng.randf_range(0.8, 1.15)))
			x += _rng.randf_range(1.4, 2.0)
		y += spacing


## Opção A: trigal único, com caminho de terra e cerca.
func farm_wheat() -> void:
	_rng.seed = 101
	c.draw_rect(Rect2(0, 0, S, S), DIRT)
	wheat(Rect2(4, 4, 72, 72))
	fence_border(3)


## Opção B: lotes em retalhos (trigo, repolho, terra lavrada com brotos e
## hortaliças) separados por caminhos de terra.
func farm_patchwork() -> void:
	_rng.seed = 202
	c.draw_rect(Rect2(0, 0, S, S), lit(DIRT, 1.1))
	wheat(Rect2(4, 4, 34, 34))
	cabbages(Rect2(42, 4, 34, 34))
	tilled(Rect2(4, 42, 34, 34), false)
	for i in 70:
		var p := Vector2(_rng.randf_range(5, 37), _rng.randf_range(43, 75))
		p.x = 4.0 + floorf((p.x - 4.0) / 2.2) * 2.2 + 1.0
		line(p, p + Vector2(0.4, -1.0), Color8(120, 160, 70), 0.4)
	leafy_rows(Rect2(42, 42, 34, 34))
	fence_border(2)


## Opção C: fileiras longas de hortaliças alternadas com trigo e um monte de feno.
func farm_rows() -> void:
	_rng.seed = 303
	c.draw_rect(Rect2(0, 0, S, S), DIRT)
	leafy_rows(Rect2(4, 4, 72, 34), 4.2)
	wheat(Rect2(4, 42, 72, 34))
	line(Vector2(4, 40), Vector2(76, 40), lit(DIRT, 1.15), 2.6)
	sphere(Vector2(66, 66), Vector2(6, 4.5), Color8(196, 170, 98))
	for i in 20:
		var a := _rng.randf() * TAU
		line(Vector2(66, 66) + Vector2(cos(a), sin(a)) * 2.0, Vector2(66, 66) + Vector2(cos(a), sin(a)) * 5.0, lit(Color8(196, 170, 98), _rng.randf_range(0.75, 1.15)), 0.35)
	fence_border(2)


## Grama sugerida (80x80, sem emenda): verde-oliva com manchas, tufos em vários
## tons, terra aparecendo e florzinhas, como na referência.
func grass_tile() -> void:
	_rng.seed = 77
	c.draw_rect(Rect2(0, 0, S, S), Color8(88, 104, 48))
	var blots := []
	for i in 14:
		blots.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(6, 14), _rng.randi() % 3])
	var tufts := []
	for i in 420:
		tufts.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(0.7, 1.25), _rng.randf_range(1.2, 2.6)])
	var flowers := []
	for i in 7:
		flowers.append(Vector2(_rng.randf() * S, _rng.randf() * S))
	for dy in [-S, 0, S]:
		for dx in [-S, 0, S]:
			var o := Vector2(dx, dy)
			for b in blots:
				var color: Color = [Color8(72, 88, 40), Color8(110, 122, 58), Color8(104, 92, 60)][b[2]]
				c.draw_colored_polygon(ell(b[0] + o, Vector2(b[1], b[1] * 0.7), 0, TAU, 24), Color(color, 0.45))
			for t in tufts:
				var p: Vector2 = t[0] + o
				var base := Color8(98, 116, 52)
				for k in [-1.0, 0.0, 1.0]:
					line(p, p + Vector2(k * 0.6, -t[2] + absf(k) * 0.4), lit(base, t[1] * (1.1 if k == 0.0 else 0.9)), 0.3)
			for f in flowers:
				c.draw_circle(f + o, 0.5, Color8(226, 214, 160))


# --- Hoplita (o lanceiro é da Antiguidade) ---------------------------------------

## Pernas nuas com grevas de bronze e sandálias.
func bare_legs_greaves() -> void:
	tube([Vector2(37.5, 47), Vector2(37, 59), Vector2(36.2, 71)], [2.8, 2.2, 1.7], SKIN.darkened(0.15))
	tube([Vector2(43.5, 47), Vector2(44.5, 59), Vector2(45.8, 71)], [2.8, 2.2, 1.7], SKIN)
	tube([Vector2(36.9, 59.5), Vector2(36.3, 69.5)], [2.4, 1.9], BRONZE.darkened(0.15))
	tube([Vector2(44.6, 59.5), Vector2(45.6, 69.5)], [2.4, 1.9], BRONZE)
	line(Vector2(43.8, 62), Vector2(45, 67), Color(1, 0.9, 0.7, 0.35), 0.4) # brilho na greva
	sphere(Vector2(35.8, 72.6), Vector2(2.8, 1.2), LEATHER.darkened(0.2))
	sphere(Vector2(47.4, 72.6), Vector2(3.0, 1.3), LEATHER)


## Hoplita: elmo coríntio de bronze com crista de crina na cor do time, couraça
## de bronze com musculatura, quíton na cor do time, pteruges de couro,
## grevas, aspis (escudo grande) pintado e lança com conto.
func hoplite() -> void:
	# Lança (dory) com ponta de ferro e conto de bronze
	line(Vector2(53, 3), Vector2(53, 77), WOOD_D, 1.8)
	line(Vector2(52.6, 3), Vector2(52.6, 77), WOOD, 0.7)
	shaded(pts([53, -1, 55.2, 5, 53, 9.5, 50.8, 5]), STEEL, 0.65)
	shaded(pts([52.1, 72, 53.9, 72, 53, 77.5]), BRONZE, 0.5)
	bare_legs_greaves()
	tube([Vector2(34.5, 28), Vector2(33, 35), Vector2(33.5, 41)], [2.0, 1.7, 1.5], SKIN.darkened(0.12))
	# Quíton na cor do time e pteruges
	shaded(pts([33.5, 38, 46.5, 38, 48.5, 52, 31.5, 52]), team, 0.45)
	folds(Vector2(33, 45), Vector2(48, 45), 6, 7, team)
	stroke(pts([31.5, 52, 48.5, 52]), lit(team, 0.55), 0.8)
	for i in 7:
		var x := 33.0 + i * 2.1
		shaded(pts([x, 41, x + 1.9, 41, x + 1.9, 47, x, 47]), LEATHER_L, 0.25)
		line(Vector2(x + 0.3, 46.6), Vector2(x + 1.6, 46.6), BRASS, 0.3)
	# Couraça de bronze com musculatura
	shaded(pts([34, 25, 46.5, 25, 47.5, 33, 46, 42, 34.5, 42, 33, 33]), BRONZE, 0.6)
	sphere(Vector2(43, 30), Vector2(2.9, 2.6), BRONZE, 0.35)
	sphere(Vector2(38.4, 30), Vector2(2.7, 2.5), BRONZE.darkened(0.08), 0.2)
	stroke(pts([36, 36.5, 40, 38, 44.5, 36.5]), BRONZE.darkened(0.45), 0.45)
	stroke(pts([40.3, 33, 40.3, 40]), BRONZE.darkened(0.35), 0.35)
	line(Vector2(35.5, 26), Vector2(45, 26), BRONZE.lightened(0.15), 0.4)
	# Braço da lança
	tube([Vector2(45.8, 27), Vector2(49, 34), Vector2(52.4, 33)], [2.0, 1.7, 1.4], SKIN)
	sphere(Vector2(53.2, 33), Vector2(1.8, 1.8), SKIN)
	# Cabeça e elmo coríntio (cobre o rosto, com fenda dos olhos e protetores)
	tube([Vector2(40.5, 23), Vector2(40.5, 26.5)], [1.9, 2.1], SKIN.darkened(0.1))
	var helmet := ell(Vector2(40.6, 18.4), Vector2(5.0, 5.4), PI * 0.88, PI * 2.14, 26)
	helmet.append(Vector2(45.8, 22.5))
	helmet.append(Vector2(44.6, 25.5))
	helmet.append(Vector2(42.8, 25))
	helmet.append(Vector2(43.2, 20.4))
	helmet.append(Vector2(38.4, 20.4))
	helmet.append(Vector2(36.4, 25.5))
	helmet.append(Vector2(35.4, 22.2))
	shaded(helmet, BRONZE, 0.65)
	line(Vector2(38.6, 18.9), Vector2(44.6, 18.9), Color8(30, 20, 14), 0.8) # fenda dos olhos
	sphere(Vector2(39.2, 15.4), Vector2(2.4, 1.6), BRONZE.lightened(0.12), 0.45)
	# Crista de crina (na cor do time), com fios
	var crest := ell(Vector2(39.6, 15), Vector2(8.6, 6.2), PI * 1.04, PI * 1.82, 20)
	crest.append_array(ell(Vector2(40, 15.5), Vector2(5.4, 3.2), PI * 1.82, PI * 1.04, 20))
	shaded(crest, team, 0.5)
	for i in 8:
		var a := lerpf(PI * 1.08, PI * 1.78, i / 7.0)
		line(Vector2(39.6, 15) + Vector2(cos(a), sin(a)) * Vector2(5.6, 3.5), Vector2(39.6, 15) + Vector2(cos(a), sin(a)) * Vector2(8.3, 6.0), lit(team, 0.68), 0.32)
	shaded(pts([30.5, 15, 33, 14, 32.6, 24, 29.4, 22]), team.darkened(0.1), 0.4) # rabo da crista
	# Aspis: borda de bronze, frente pintada na cor do time, emblema
	sphere(Vector2(31, 42), Vector2(11.4, 13.0), BRONZE, 0.4)
	sphere(Vector2(31, 42), Vector2(9.6, 11.2), team, 0.15)
	stroke(pts([27, 38.5, 31, 46.5, 35, 38.5]), Color8(226, 214, 186), 1.4) # lambda
	c.draw_arc(Vector2(31, 42), 10.5, PI * 1.05, PI * 1.6, 12, Color(1, 0.95, 0.8, 0.35), 0.6, true)
	c.draw_arc(Vector2(31, 42), 10.6, PI * 0.1, PI * 0.7, 12, Color(0, 0, 0, 0.3), 0.6, true)


# --- Vila e metrópole -----------------------------------------------------------------

## Poço de pedra com telhadinho.
func well(base: Vector2) -> void:
	c.draw_colored_polygon(ell(base + Vector2(3, 1.5), Vector2(5, 1.8)), Color(0.05, 0.04, 0.02, 0.35))
	tube([base + Vector2(0, -3), base], [3.6, 3.8], STONE)
	sphere(base + Vector2(0, -3), Vector2(3.4, 1.3), Color8(40, 52, 60))
	line(base + Vector2(-3, -3), base + Vector2(-3, -9), WOOD_D, 0.6)
	line(base + Vector2(3, -3), base + Vector2(3, -9), WOOD_D, 0.6)
	shaded(pts([base.x - 4.5, base.y - 8.5, base.x, base.y - 12, base.x + 4.5, base.y - 8.5]), THATCH, 0.4)


## Vila: mais casas (palha e telha), poço, capela de pedra, paliçada e árvores.
func town() -> void:
	_rng.seed = 53
	ground_base(Vector2(56, 74), Vector2(56, 34))
	for t in [[Vector2(10, 58), 7.0], [Vector2(22, 46), 7.5], [Vector2(96, 50), 7.5], [Vector2(84, 42), 6.5]]:
		tree(t[0], t[1])
	# Capela de pedra com torre sineira ao fundo
	c.draw_colored_polygon(pts([46, 58, 70, 56, 74, 60, 50, 60]), Color(0.05, 0.04, 0.02, 0.35))
	shaded(pts([46, 44, 64, 44, 64, 58, 46, 58]), STONE, 0.3)
	stone_blocks(46, 44.5, 64, 58, STONE)
	roof_tiles_cone(Vector2(55, 30), Vector2(55, 44), 10.5, ROOF_RED)
	shaded(pts([53, 50, 57, 50, 57, 58, 53, 58]), Color8(70, 46, 28), 0.2)
	banner(Vector2(68, 60), 26)
	cottage(24, 58, 16, 9, 10)
	cottage(72, 60, 16, 9, 10, true, ROOF_RED)
	well(Vector2(57, 78))
	cottage(14, 80, 17, 10, 11, true, ROOF_RED)
	cottage(38, 84, 15, 9, 10)
	cottage(74, 84, 18, 10, 11)
	# Paliçada na frente
	for i in 22:
		var x := 8.0 + i * 4.6
		var y := 104.0 - absf(x - 56) * 0.16
		tube([Vector2(x, y), Vector2(x, y - 7)], [1.0, 0.9], WOOD)
		shaded(pts([x - 1, y - 7, x, y - 9, x + 1, y - 7]), WOOD, 0.3)


## Metrópole: castelo maior, com três torres na frente, torre de menagem alta,
## catedral com torre, muitas casas de telha dentro e fora dos muros.
func metropolis() -> void:
	_rng.seed = 61
	ground_base(Vector2(56, 72), Vector2(58, 38), 0.55)
	for t in [[Vector2(6, 56), 6.0], [Vector2(106, 54), 6.5], [Vector2(8, 100), 6.0], [Vector2(104, 102), 6.0]]:
		tree(t[0], t[1])
	# Muralha do fundo, torres de trás e casas do bairro alto
	curtain_wall(22, 90, 40, 50)
	stone_tower(22, 32, 52, 5.5)
	stone_tower(90, 32, 52, 5.5)
	cottage(26, 50, 11, 6, 7, true, ROOF_RED.darkened(0.1))
	cottage(76, 48, 11, 6, 7, true, ROOF_RED.darkened(0.1))
	# Catedral (nave + torre com agulha)
	c.draw_colored_polygon(pts([30, 66, 50, 64, 54, 68, 34, 68]), Color(0.05, 0.04, 0.02, 0.35))
	shaded(pts([30, 50, 48, 50, 48, 66, 30, 66]), STONE.lightened(0.05), 0.3)
	stone_blocks(30, 50.5, 48, 66, STONE.lightened(0.05))
	shaded(pts([29, 50, 49, 50, 46, 43, 32, 43]), ROOF_RED.darkened(0.15), 0.4)
	shaded(pts([36.5, 55, 41.5, 55, 41.5, 66, 36.5, 66]), Color8(60, 42, 28), 0.2)
	c.draw_circle(Vector2(39, 51.8), 1.6, Color8(70, 90, 120))
	stone_tower(26, 34, 66, 4.0, false)
	roof_tiles_cone(Vector2(26, 16), Vector2(26, 34), 5.2, Color8(90, 96, 104))
	# Torre de menagem alta
	c.draw_colored_polygon(pts([56, 66, 82, 64, 84, 68, 58, 68]), Color(0.05, 0.04, 0.02, 0.35))
	shaded(pts([56, 24, 72, 24, 72, 66, 56, 66]), STONE, 0.3)
	stone_blocks(56, 24.5, 72, 66, STONE)
	shaded(pts([72, 24, 77, 20, 77, 62, 72, 66]), STONE.darkened(0.25), 0.2)
	roof_tiles_cone(Vector2(66, 6), Vector2(66, 24), 10.5, ROOF_RED)
	var pole := Vector2(66, 7)
	line(pole, pole - Vector2(0, 7), WOOD_D, 0.6)
	shaded(pts([pole.x, pole.y - 7, pole.x + 6, pole.y - 6, pole.x, pole.y - 4]), team, 0.4)
	for wy in [32.0, 44.0]:
		shaded(pts([62.5, wy, 65.5, wy, 65.5, wy + 5, 62.5, wy + 5]), Color8(30, 24, 20), 0.1)
	cottage(80, 60, 12, 7, 8, true, ROOF_RED)
	# Muralhas laterais e a da frente, com três torres e o portão no meio
	shaded(pts([14, 68, 22, 48, 22, 58, 14, 80]), STONE.darkened(0.2), 0.25)
	shaded(pts([90, 48, 98, 68, 98, 80, 90, 58]), STONE.darkened(0.3), 0.2)
	curtain_wall(12, 100, 78, 98)
	shaded(pts([46, 72, 66, 72, 66, 99, 46, 99]), STONE, 0.3)
	stone_blocks(46, 72.5, 66, 99, STONE)
	var gate := ell(Vector2(56, 89), Vector2(5.5, 5.5), PI, TAU, 16)
	gate.append(Vector2(61.5, 99))
	gate.append(Vector2(50.5, 99))
	shaded(gate, Color8(84, 58, 36), 0.3)
	for gx in [53.0, 56.0, 59.0]:
		line(Vector2(gx, 84.5), Vector2(gx, 99), Color8(52, 36, 22), 0.35)
	for bx in [48.5, 63.5]:
		shaded(pts([bx - 1.8, 76, bx + 1.8, 76, bx + 1.8, 84, bx, 82.5, bx - 1.8, 84]), team, 0.4)
	var x := 46.0
	while x < 65:
		shaded(pts([x, 68, x + 3, 68, x + 3, 72, x, 72]), STONE.lightened(0.05), 0.35)
		x += 5.0
	stone_tower(12, 66, 101, 7.0)
	stone_tower(100, 66, 101, 7.0)
	stone_tower(56, 60, 76, 5.0)


# --- Fazenda em obra e destruída (vistas de cima) -------------------------------------

## Fazenda em obra: terra lavrada, com estacas e a cerca começando.
func farm_new() -> void:
	_rng.seed = 404
	c.draw_rect(Rect2(0, 0, S, S), DIRT)
	tilled(Rect2(4, 4, 72, 72))
	for k in 5:
		sphere(Vector2(2 + k * 19, 2), Vector2.ONE * 0.9, WOOD_D)
	line(Vector2(2, 2), Vector2(40, 2), WOOD, 0.7)
	for i in 8:
		var p := Vector2(_rng.randf_range(8, 72), _rng.randf_range(8, 72))
		sphere(p, Vector2(1.4, 1.0), STONE.darkened(0.2))


## Fazenda pilhada: os lotes queimados (fuligem e cinza), brasas e fumaça.
func burnt_farm() -> void:
	farm_patchwork()
	_rng.seed = 505
	for i in 40:
		var p := Vector2(_rng.randf() * S, _rng.randf() * S)
		c.draw_colored_polygon(ell(p, Vector2(_rng.randf_range(4, 10), _rng.randf_range(3, 7)), 0, TAU, 16), Color(0.06, 0.05, 0.04, 0.45))
	for i in 25:
		var p := Vector2(_rng.randf() * S, _rng.randf() * S)
		c.draw_colored_polygon(ell(p, Vector2(_rng.randf_range(2, 5), _rng.randf_range(1.5, 3)), 0, TAU, 12), Color(ASH, 0.55))
	for i in 9:
		var p := Vector2(_rng.randf_range(8, 72), _rng.randf_range(8, 72))
		c.draw_circle(p, 1.8, Color(EMBER, 0.35))
		c.draw_circle(p, 0.9, EMBER)
	for k in 4:
		c.draw_circle(Vector2(44 + k * 2.0, 40 - k * 7.0), 4.0 + k * 1.6, Color(0.55, 0.55, 0.55, 0.38 - k * 0.07))


# --- Terrenos no estilo da referência (sem emenda) --------------------------------------

## Repete [param job](deslocamento) nas 9 cópias do quadro, para o que passa
## da borda continuar na casa vizinha.
func repeat_tiles(job: Callable) -> void:
	for dy in [-S, 0, S]:
		for dx in [-S, 0, S]:
			job.call(Vector2(dx, dy))


## Floresta vista de cima: copas de árvores em bolos, com sombras entre elas.
func forest_tile() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(38, 52, 26))
	_rng.seed = 7
	var trees := []
	while trees.size() < 13:
		var p := Vector2(_rng.randf() * S, _rng.randf() * S)
		var ok := true
		for t in trees:
			var d: Vector2 = (t[0] - p).abs()
			d = Vector2(minf(d.x, S - d.x), minf(d.y, S - d.y))
			if d.length() < 15:
				ok = false
		if ok:
			var lobes := []
			for k in 6:
				var a := _rng.randf() * TAU
				lobes.append([Vector2(cos(a), sin(a) * 0.8) * _rng.randf_range(0.35, 0.6), _rng.randf_range(0.45, 0.62)])
			trees.append([p, _rng.randf_range(9, 13), _rng.randf_range(0.82, 1.12), lobes])
	trees.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	repeat_tiles(func(o: Vector2) -> void:
		for t in trees:
			c.draw_colored_polygon(ell(t[0] + o + Vector2(3, 5), Vector2(t[1] * 1.05, t[1] * 0.75), 0, TAU, 24), Color(0.03, 0.05, 0.02, 0.5)))
	repeat_tiles(func(o: Vector2) -> void:
		for t in trees:
			var p: Vector2 = t[0] + o
			var r: float = t[1]
			var color := lit(FOLIAGE, t[2])
			for lobe in t[3]:
				sphere(p + lobe[0] * r, Vector2.ONE * r * lobe[1], color)
			sphere(p + Vector2(-0.15, -0.2) * r, Vector2(r * 0.55, r * 0.5), lit(color, 1.12)))


## Água: azul acinzentado, com manchas e ondinhas claras.
func water_tile() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(54, 84, 106))
	_rng.seed = 5
	var blots := []
	for i in 10:
		blots.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(8, 16), _rng.randi() % 2])
	var waves := []
	for i in 22:
		waves.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(2.5, 5.5)])
	repeat_tiles(func(o: Vector2) -> void:
		for b in blots:
			c.draw_colored_polygon(ell(b[0] + o, Vector2(b[1], b[1] * 0.6), 0, TAU, 24), Color(Color8(40, 66, 88) if b[2] == 0 else Color8(70, 102, 122), 0.45))
		for w in waves:
			stroke(ell(w[0] + o, Vector2(w[1], w[1] * 0.4), PI * 1.15, PI * 1.85, 10), Color(0.75, 0.85, 0.9, 0.45), 0.5))


## Cerrado: chão seco de terra e capim amarelado, com moitas e pedrinhas.
func cerrado_tile() -> void:
	c.draw_rect(Rect2(0, 0, S, S), Color8(140, 126, 80))
	_rng.seed = 3
	var blots := []
	for i in 12:
		blots.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(6, 12), _rng.randi() % 2])
	var tufts := []
	for i in 160:
		tufts.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(0.75, 1.2)])
	var shrubs := []
	for i in 5:
		shrubs.append([Vector2(_rng.randf() * S, _rng.randf() * S), _rng.randf_range(2.5, 4.0)])
	repeat_tiles(func(o: Vector2) -> void:
		for b in blots:
			c.draw_colored_polygon(ell(b[0] + o, Vector2(b[1], b[1] * 0.7), 0, TAU, 20), Color(Color8(120, 100, 66) if b[2] == 0 else Color8(150, 140, 86), 0.45))
		for t in tufts:
			var p: Vector2 = t[0] + o
			for k in [-1.0, 0.0, 1.0]:
				line(p, p + Vector2(k * 0.7, -2.0 + absf(k) * 0.5), lit(Color8(170, 152, 88), t[1]), 0.32)
		for s in shrubs:
			var p: Vector2 = s[0] + o
			c.draw_colored_polygon(ell(p + Vector2(1.5, 2), Vector2(s[1], s[1] * 0.55), 0, TAU, 16), Color(0.08, 0.06, 0.03, 0.35))
			sphere(p, Vector2(s[1], s[1] * 0.8), Color8(92, 102, 52)))
