extends SceneTree

## Importa as 3 FAZENDAS do Gemini (tools/art/gemini/pedidos/09_fazendas: estilo
## do Civilization VI, um mosaico de campos listrados) a partir de uma folha com
## as 3 lado a lado (em produção, em obra, queimada) sobre o fundo verde.
##   godot_console.cmd --headless --path . --script tools/art/import_fazendas_gemini.gd -- <folha.png> [cerca]
## Com "cerca", grava a variante com cerca (<nome>_cerca.png); o mapa sorteia
## por casa qual das duas usar (City.farm_fenced). O verde entre os campos e em
## volta vira TRANSPARENTE (o terreno do mapa aparece; o shader usa o alfa).
## As 3 fazendas são achadas pelas faixas verticais de colunas vazias e usam a
## mesma escala (são o mesmo lugar): a maior cabe em FILL do quadro SIZE x SIZE,
## centralizada. Grava em assets/sprites/improvements/; guarda a folha em
## tools/art/gemini/fazendas[_cerca]_folha.png e uma prévia sobre a pradaria em
## tools/art/gemini/fazendas[_cerca]_previa.png.

const IMPROVEMENTS := "res://assets/sprites/improvements/"
const GEMINI := "res://tools/art/gemini/"
const SIZE := 160
## Fração do quadro ocupada pela fazenda: quase a casa inteira, para fazendas
## vizinhas parecerem uma plantação contínua (pedido do usuário). Cada fazenda é
## esticada para um QUADRADO (as do Gemini são ~15% mais altas que largas).
const FILL := 0.97
## Vãos de colunas vazias menores que isto (pixels da folha) ficam dentro da
## mesma fazenda (o vão entre dois campos).
const MERGE_GAP := 14
const FARMS := ["fazenda", "fazenda_obra", "fazenda_destruida"]
const KEY_RESIDUAL := 14.0 / 255.0
const KEY_K := Vector2(0.55, 1.2)
## Distância de matiz (0-1) até o verde do fundo que ainda é fundo.
const BG_HUE_RANGE := 0.045
## Cor dos pixels transparentes (evita borda escura com os mipmaps).
const CLEAR := Color(0.42, 0.31, 0.2, 0.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("uso: -- <folha.png> [cerca]")
		quit(1)
		return
	var suffix := "_cerca" if args.size() > 1 and args[1] == "cerca" else ""
	var sheet := Image.load_from_file(args[0])
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + "fazendas%s_folha.png" % suffix))
	_remove_backdrop(sheet)
	var boxes := _find_farms(sheet)
	if boxes.size() != FARMS.size():
		print("ERRO: achei %d fazendas, esperava %d: %s" % [boxes.size(), FARMS.size(), boxes])
		quit(1)
		return
	var scale := INF
	for box in boxes:
		scale = minf(scale, SIZE * FILL / maxf(box.size.x, box.size.y))
	print("escala comum: %.3f" % scale)
	var previews: Array[Image] = []
	for i in FARMS.size():
		var crop := sheet.get_region(boxes[i])
		if FARMS[i] == "fazenda_destruida":
			_remove_green_smoke(crop)
		var side := roundi(SIZE * FILL)
		var target := Vector2i(side, side)
		var current := crop.get_size()
		while current.x > target.x * 2:
			current /= 2
			crop.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		crop.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
		var farm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		farm.fill(CLEAR)
		farm.blend_rect(crop, Rect2i(Vector2i.ZERO, target), (Vector2i(SIZE, SIZE) - target) / 2)
		_fill_clear(farm)
		farm.save_png(ProjectSettings.globalize_path(IMPROVEMENTS + FARMS[i] + suffix + ".png"))
		previews.append(farm)
		print("ok: %s%s (%s -> %s)" % [FARMS[i], suffix, boxes[i].size, target])
	_preview(previews, GEMINI + "fazendas%s_previa.png" % suffix)
	quit()


## Tira o fundo verde e o verde vazado na borda (só na borda: as plantas são
## verdes de verdade).
func _remove_backdrop(img: Image) -> void:
	var bg := img.get_pixel(4, 4)
	var bg_v := Vector3(bg.r, bg.g, bg.b)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var v := Vector3(p.r, p.g, p.b)
			var k := v.dot(bg_v) / bg_v.dot(bg_v)
			# Também pelo matiz: o verde do fundo na sombra dos campos (vãos
			# estreitos) é mais escuro, mas continua verde-azulado e saturado; as
			# plantas e as oliveiras são verde-amareladas
			var hue_key := absf(p.h - bg.h) < BG_HUE_RANGE and p.s > 0.55
			if hue_key or (k > KEY_K.x and k < KEY_K.y and (v - bg_v * k).length() < KEY_RESIDUAL):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	for edge_pass in 3:
		var src: Image = img.duplicate()
		for y in range(1, img.get_height() - 1):
			for x in range(1, img.get_width() - 1):
				var p := src.get_pixel(x, y)
				if p.a == 0.0 or p.g <= maxf(p.r, p.b):
					continue
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if src.get_pixel(x + d.x, y + d.y).a == 0.0:
						edge = true
				if not edge:
					continue
				if p.g - maxf(p.r, p.b) > 0.2:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				else:
					img.set_pixel(x, y, Color(p.r, maxf(p.r, p.b), p.b, minf(p.a, 0.7)))


## As fazendas: faixas de colunas com algum pixel (juntando vãos menores que
## MERGE_GAP, que são os vãos entre campos, de ~10 px; entre as fazendas a
## folha sem cerca de 26/10/2026 deixou só ~20 px) e, em cada faixa, a caixa do que
## não é transparente.
func _find_farms(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	var used: Array[bool] = []
	# Coluna ocupada: mais de 25% dos pixels da coluna mais cheia (a folha sem
	# cerca de 26/10/2026 tem restos esparsos, 30-50 por coluna, nos vãos)
	var counts: Array[int] = []
	var fullest := 0
	for x in w:
		var count := 0
		for y in range(0, h, 2):
			if img.get_pixel(x, y).a > 0.5:
				count += 1
		counts.append(count)
		fullest = maxi(fullest, count)
	for x in w:
		used.append(counts[x] > fullest * 0.25)
	var runs: Array[Vector2i] = []
	var start := -1
	for x in w + 1:
		var u := x < w and used[x]
		if u and start < 0:
			start = x
		elif not u and start >= 0:
			if not runs.is_empty() and start - runs[-1].y < MERGE_GAP:
				runs[-1].y = x
			else:
				runs.append(Vector2i(start, x))
			start = -1
	var boxes: Array[Rect2i] = []
	for run in runs:
		if run.y - run.x < w / 12:
			continue # sujeira fina
		# Linhas ocupadas da faixa, com o mesmo critério das colunas (as sobras
		# esparsas não esticam a caixa até a borda da folha)
		var rows: Array[int] = []
		var fullest_row := 0
		for y in h:
			var count := 0
			for x in range(run.x, run.y):
				if img.get_pixel(x, y).a > 0.5:
					count += 1
			rows.append(count)
			fullest_row = maxi(fullest_row, count)
		var top := -1
		var bottom := -1
		for y in h:
			if rows[y] > fullest_row * 0.1:
				if top < 0:
					top = y
				bottom = y
		var box := Rect2i(run.x, top, run.y - run.x, bottom - top + 1)
		# Fora da caixa só há sobras: apaga
		for y in h:
			for x in range(run.x, run.y):
				if not box.has_point(Vector2i(x, y)):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
		boxes.append(box)
	return boxes


## Fazenda queimada: nada nela é verde de verdade (as árvores estão
## carbonizadas). A fumaça que passou sobre o fundo ficou esverdeada: o verde
## claro some e o resto perde o excesso de verde.
func _remove_green_smoke(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a == 0.0 or p.g <= maxf(p.r, p.b):
				continue
			if p.g - maxf(p.r, p.b) > 0.06 and p.v > 0.4:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(p.r, maxf(p.r, p.b), p.b, p.a))


## Pixels transparentes com a cor da terra (os mipmaps misturam a cor deles
## na borda; preto faria um contorno escuro).
func _fill_clear(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a == 0.0:
				img.set_pixel(x, y, CLEAR)


func _preview(farms: Array[Image], path: String) -> void:
	var grass := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/pradaria.png"))
	grass.convert(Image.FORMAT_RGBA8)
	grass.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var sheet := Image.create(SIZE * 2 * farms.size(), SIZE * 2, false, Image.FORMAT_RGBA8)
	for i in farms.size():
		for y in 2:
			for x in 2:
				sheet.blit_rect(grass, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE * 2 + x * SIZE, y * SIZE))
		var big := farms[i].duplicate()
		big.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_BILINEAR)
		sheet.blend_rect(big, Rect2i(0, 0, SIZE * 2, SIZE * 2), Vector2i(i * SIZE * 2, 0))
	sheet.save_png(ProjectSettings.globalize_path(path))
