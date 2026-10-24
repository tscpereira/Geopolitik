extends SceneTree

## Monta as variantes das cidades (desde 24/10/2026) por colagem dos recortes
## grandes do ChatGPT (tools/art/chatgpt/grandes/, gravados por
## import_sheet.gd) e grava em tools/art/chatgpt/prontos/, já com os nomes do
## jogo. Rode depois do importador, na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/variantes_cidade.gd
## Nomes: <classe>[_capital][_muralha].png (+ _time.png, a máscara da cor):
##   _capital  com o templo/acrópole (o Palácio): só a capital usa;
##   _muralha  com a muralha: só com a construção Muralha (ainda não existe),
##             que vale para qualquer classe.
## O importador grava as versões originais da folha (povoado, vila_capital,
## cidade_capital_muralha, metropole_capital_muralha); aqui saem as outras:
##   cidade_capital, metropole_capital   sem muralha: a frente da vila no lugar
##                                       da muralha (a acrópole da metrópole
##                                       mais baixa, para não flutuar);
##   vila, cidade, cidade_muralha,       normais: o templo/acrópole sai e no
##   metropole, metropole_muralha        lugar entram grupos de casas e árvores
##                                       (o grupo da esquerda da vila e o miolo
##                                       de casas da cidade);
##   povoado_muralha, vila_muralha,      a muralha da frente da cidade (até o
##   vila_capital_muralha                alto das ameias, wall_top), menor, na
##                                       frente do povoado e da vila.
## Coordenadas em pixels dos recortes grandes (vila 344x302, cidade 375x337,
## metrópole 408x399).

const G := "res://tools/art/chatgpt/grandes/"
const OUT := "res://tools/art/chatgpt/prontos/"
## Grupo da esquerda da vila: casa grande, casa de baixo, ciprestes e oliveira
## (o topo dele é o topo natural do desenho).
const LEFT_GROUP := Rect2i(28, 30, 96, 120)
## Miolo de casas da cidade (sem topo natural: vai na frente de outro grupo).
const CITY_HOUSES := Rect2i(160, 100, 130, 80)


class Canvas:
	var color: Image
	var mask: Image
	func _init(w: int, h: int) -> void:
		color = Image.create(w, h, false, Image.FORMAT_RGBA8)
		mask = Image.create(w, h, false, Image.FORMAT_RGBA8)

	func pair() -> Array:
		return [color, mask]


func _initialize() -> void:
	var vila := load_piece("vila")
	var cidade := load_piece("cidade")
	var metro := load_piece("metropole")

	# CIDADE da capital sem muralha: fundo da cidade (templo e casas acima da
	# muralha) + a vila na frente, sem o templo dela
	var city_capital := Canvas.new(375, 337)
	paste(city_capital, cidade, func(x: int, y: int) -> float:
		var back := 1.0 - band(y, 104, 116) # torre do fundo (direita) e muro de trás (esquerda)
		return (1.0 - band(y, 132, 146)) * band(x, 52, 64) * (1.0 - band(x, 306, 318)) \
				* (1.0 - back * band(x, 268, 278)) * (1.0 - back * (1.0 - band(x, 100, 110))), 1.0, Vector2i.ZERO)
	paste(city_capital, vila, func(x: int, y: int) -> float:
		# só sai o templo da vila (e a casa colada nele); os lados de cima
		# (casa, ciprestes e oliveiras) ficam e escoram o templo da cidade
		var temple := band(x, 108, 118) * (1.0 - band(x, 262, 274))
		return 1.0 - temple * (1.0 - band(y, 94, 106)), 1.09, Vector2i(0, 337 - roundi(302 * 1.09)))
	save(city_capital, "cidade_capital")

	# METRÓPOLE da capital sem muralha: a de cima ampliada + a acrópole
	var metro_capital := Canvas.new(408, 399)
	paste(metro_capital, city_capital.pair(), func(_x: int, _y: int) -> float: return 1.0, 1.09, Vector2i(0, 399 - roundi(337 * 1.09)))
	paste(metro_capital, metro, func(x: int, y: int) -> float:
		# acrópole + o cipreste da esquerda (sem o muro do terraço embaixo dele)
		var acro := (1.0 - band(y, 128, 142)) * band(x, 90, 104)
		var cypress := band(x, 66, 74) * (1.0 - band(y, 104, 116))
		return maxf(acro, cypress) * (1.0 - band(x, 290, 304)), 1.0, Vector2i(0, 22))
	save(metro_capital, "metropole_capital")

	# VILA normal: dois grupos de casas no lugar do templo
	var town := Canvas.new(344, 302)
	cluster(town, vila, LEFT_GROUP, 1.0, Vector2i(118, 6))
	cluster(town, vila, LEFT_GROUP, 0.9, Vector2i(190, 22))
	over_with_hole(town, vila, Rect2i(112, 0, 162, 110))
	save(town, "vila")

	# CIDADE normal (com e sem muralha): dois grupos menores no lugar do templo
	var city := Canvas.new(375, 337)
	for variant in [["cidade_muralha", cidade], ["cidade", city_capital.pair()]]:
		var c := Canvas.new(375, 337)
		cluster(c, vila, LEFT_GROUP, 0.78, Vector2i(98, 14))
		cluster(c, vila, LEFT_GROUP, 0.72, Vector2i(150, 24))
		over_with_hole(c, variant[1], Rect2i(98, 0, 112, 100))
		save(c, variant[0])
		city = c

	# METRÓPOLE normal com muralha: fileira de trás (topo natural) e o miolo de
	# casas da cidade na frente, no lugar da acrópole
	var metro_walls := Canvas.new(408, 399)
	for i in 3:
		cluster(metro_walls, vila, LEFT_GROUP, 0.78, Vector2i(96 + i * 66, 12 + (i % 2) * 8))
	cluster(metro_walls, cidade, CITY_HOUSES, 1.0, Vector2i(96, 78), 8.0, false)
	cluster(metro_walls, cidade, CITY_HOUSES, 1.0, Vector2i(186, 84), 8.0, false)
	over_with_hole(metro_walls, metro, Rect2i(94, 0, 214, 148))
	save(metro_walls, "metropole_muralha")

	# METRÓPOLE normal sem muralha: a cidade normal ampliada, com uma fileira a
	# mais de casas atrás
	var metropolis := Canvas.new(408, 399)
	for i in 3:
		cluster(metropolis, vila, LEFT_GROUP, 0.75, Vector2i(98 + i * 60, 26 + (i % 2) * 8), 20.0)
	paste(metropolis, city.pair(), func(_x: int, _y: int) -> float: return 1.0, 1.09, Vector2i(0, 399 - roundi(337 * 1.09)))
	save(metropolis, "metropole")

	# POVOADO e VILA com muralha: a muralha da frente da cidade, menor, na
	# frente deles (as casas de trás aparecem por cima dela)
	var povoado := load_piece("povoado")
	save(walled(povoado, Vector2i(306, 281), 0.82), "povoado_muralha")
	save(walled(town.pair(), Vector2i(344, 302), 0.92), "vila_muralha")
	save(walled(vila, Vector2i(344, 302), 0.92), "vila_capital_muralha")
	print("ok")
	quit()


func load_piece(piece: String) -> Array:
	var c := Image.load_from_file(ProjectSettings.globalize_path(G + piece + ".png"))
	var m := Image.load_from_file(ProjectSettings.globalize_path(G + piece + "_time.png"))
	c.convert(Image.FORMAT_RGBA8)
	m.convert(Image.FORMAT_RGBA8)
	return [c, m]


func band(v: float, from: float, to: float) -> float:
	return clampf((v - from) / (to - from), 0.0, 1.0)


## Cola [param src] (cor, máscara) em [param dst], com o peso keep(x, y) do
## recorte, ampliado por [param scale], com o canto em [param at].
func paste(dst: Canvas, src: Array, keep: Callable, scale: float, at: Vector2i) -> void:
	var c: Image = src[0].duplicate()
	var m: Image = src[1].duplicate()
	for y in c.get_height():
		for x in c.get_width():
			var p := c.get_pixel(x, y)
			p.a *= keep.call(x, y)
			c.set_pixel(x, y, p)
	if scale != 1.0:
		var s := Vector2i(roundi(c.get_width() * scale), roundi(c.get_height() * scale))
		c.resize(s.x, s.y, Image.INTERPOLATE_CUBIC)
		m.resize(s.x, s.y, Image.INTERPOLATE_CUBIC)
	for y in c.get_height():
		for x in c.get_width():
			var d := Vector2i(x, y) + at
			if d.x < 0 or d.y < 0 or d.x >= dst.color.get_width() or d.y >= dst.color.get_height():
				continue
			var p := c.get_pixel(x, y)
			if p.a <= 0.001:
				continue
			var q := dst.color.get_pixelv(d)
			var a := clampf(p.a, 0, 1)
			var alpha := a + q.a * (1 - a)
			# cor sem pré-multiplicar
			var out := Color((p.r * a + q.r * q.a * (1 - a)) / alpha, (p.g * a + q.g * q.a * (1 - a)) / alpha,
					(p.b * a + q.b * q.a * (1 - a)) / alpha, alpha)
			dst.color.set_pixelv(d, out)
			var mv := m.get_pixel(x, y).r * a + dst.mask.get_pixelv(d).r * (1 - a)
			dst.mask.set_pixelv(d, Color(mv, mv, mv, 1))


## Pedaço [param rect] de [param src] (escala [param scale]) com o canto do
## recorte em [param dest]; bordas esmaecidas em [param fade] px, menos em
## cima quando [param top_open] (o topo natural do desenho fica como está).
func cluster(dst: Canvas, src: Array, rect: Rect2i, scale: float, dest: Vector2i, fade := 8.0, top_open := true) -> void:
	var keep := func(x: int, y: int) -> float:
		if not rect.has_point(Vector2i(x, y)):
			return 0.0
		var k := minf(band(x, rect.position.x, rect.position.x + fade), 1.0 - band(x, rect.end.x - fade, rect.end.x))
		k = minf(k, 1.0 - band(y, rect.end.y - fade, rect.end.y))
		if not top_open:
			k = minf(k, band(y, rect.position.y, rect.position.y + fade))
		return k
	paste(dst, src, keep, scale, dest - Vector2i((Vector2(rect.position) * scale).round()))


## [param base] por cima do que já está em [param dst], com o buraco
## [param hole] (onde estava o templo) esmaecido nas laterais e embaixo.
func over_with_hole(dst: Canvas, base: Array, hole: Rect2i, fade := 8.0) -> void:
	paste(dst, base, func(x: int, y: int) -> float:
		var inside := band(x, hole.position.x, hole.position.x + fade) * (1.0 - band(x, hole.end.x - fade, hole.end.x)) \
				* (1.0 - band(y, hole.end.y - fade, hole.end.y)) * float(y >= hole.position.y)
		return 1.0 - inside, 1.0, Vector2i.ZERO)


## Alto da muralha da cidade em cada coluna x do recorte grande (o topo das
## ameias): torre da esquerda, muro, torre do estandarte, muro, torre do
## meio, portão e torre da direita.
func wall_top(x: float) -> float:
	if x < 52:
		return 112.0
	if x < 100:
		return lerpf(146.0, 160.0, (x - 52) / 48.0)
	if x < 142:
		return 164.0
	if x < 187:
		return 198.0
	if x < 237:
		return 177.0
	if x < 320:
		return 192.0
	return 118.0


## [param base] (tamanho [param size]) com a muralha da cidade na frente: tudo
## da cidade abaixo do alto da muralha (wall_top), reduzido por
## [param scale], centrado e com a base no chão do desenho.
func walled(base: Array, size: Vector2i, scale: float) -> Canvas:
	var canvas := Canvas.new(size.x, size.y)
	paste(canvas, base, func(_x: int, _y: int) -> float: return 1.0, 1.0, Vector2i.ZERO)
	var wall := load_piece("cidade")
	var w := roundi(375 * scale)
	var h := roundi(337 * scale)
	paste(canvas, wall, func(x: int, y: int) -> float:
		var top := wall_top(x)
		return band(y, top - 6.0, top), scale, Vector2i((size.x - w) / 2, size.y - h))
	return canvas


## Reduz como o importador (cabe em 124x120, base em y = 124 de 128) e grava
## <nome>.png e <nome>_time.png em OUT.
func save(canvas: Canvas, file_name: String) -> void:
	var r := canvas.color.get_size()
	var scale := minf(124.0 / r.x, 120.0 / r.y)
	var target := Vector2i(roundi(r.x * scale), roundi(r.y * scale))
	var images: Array[Image] = []
	for img: Image in [canvas.color.duplicate(), canvas.mask.duplicate()]:
		var current := img.get_size()
		while current.x > target.x * 2:
			current /= 2
			img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
		var sprite := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		sprite.blit_rect(img, Rect2i(Vector2i.ZERO, target), Vector2i((128 - target.x) / 2, 124 - target.y))
		images.append(sprite)
	images[0].save_png(ProjectSettings.globalize_path(OUT + file_name + ".png"))
	images[1].convert(Image.FORMAT_L8)
	images[1].save_png(ProjectSettings.globalize_path(OUT + file_name + "_time.png"))
