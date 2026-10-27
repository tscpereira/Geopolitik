extends SceneTree

## Monta as 3 FAZENDAS a partir da folha do Gemini (tools/art/gemini/pedidos/
## 09_fazendas). Em 26/10/2026 a folha veio com canteiros SOLTOS: 3 grupos
## (em produção, em obra, queimada), cada um com 6 canteiros em 2 colunas x 3
## linhas, sobre o fundo verde. Este script tira o fundo e a fumaça, acha os
## canteiros, escolhe 4 de cada grupo (PICKS) e monta cada fazenda em 2x2 num
## quadro SIZE x SIZE, com a "cruz" entre os canteiros e a margem em volta
## TRANSPARENTES (o terreno do mapa aparece por baixo; o shader usa o alfa).
##   godot_console.cmd --headless --path . --script tools/art/import_fazendas_gemini.gd -- <folha.png>
## Grava assets/sprites/improvements/fazenda.png, fazenda_obra.png e
## fazenda_destruida.png; guarda a folha em tools/art/gemini/fazendas_folha.png
## e uma prévia sobre a pradaria em tools/art/gemini/fazendas_previa.png.

const IMPROVEMENTS := "res://assets/sprites/improvements/"
const GEMINI := "res://tools/art/gemini/"
const SIZE := 160
## Margem em volta e largura da "cruz" (fração do quadro): 1/8 cada.
const MARGIN := 0.125
const GAP := 0.125
## Fazendas na ordem dos grupos da folha (da esquerda para a direita) e os 4
## canteiros de cada uma (índices no grupo, por linhas: 0 1 / 2 3 / 4 5), na
## ordem cima-esquerda, cima-direita, baixo-esquerda, baixo-direita.
const FARMS := ["fazenda", "fazenda_obra", "fazenda_destruida"]
const PICKS := [[0, 1, 3, 5], [0, 1, 2, 3], [0, 1, 2, 3]]
const KEY_RESIDUAL := 14.0 / 255.0
const KEY_K := Vector2(0.55, 1.2)
## Distância (pixels da folha) em que um pedaço solto ainda é do canteiro.
const PIECE_REACH := 6
## Cor dos pixels transparentes (evita borda escura com os mipmaps).
const CLEAR := Color(0.42, 0.31, 0.2, 0.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("uso: -- <folha.png>")
		quit(1)
		return
	var sheet := Image.load_from_file(args[0])
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + "fazendas_folha.png"))
	_remove_backdrop(sheet)
	var plots := _split_tall(sheet, _find_plots(sheet))
	# Grupos: os canteiros separados pelos 2 maiores vãos na horizontal
	plots.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.get_center().x < b.get_center().x)
	var groups := _split_groups(plots, FARMS.size())
	# Confere antes de usar (um erro de script deixa o Godot preso aberto)
	for g in groups.size():
		for index: int in PICKS[g]:
			if index >= groups[g].size():
				print("ERRO: o grupo %d (%s) tem %d canteiros; precisa do %d" % [g, FARMS[g], groups[g].size(), index])
				quit(1)
				return
	var scale := INF
	var box := SIZE * (1.0 - MARGIN * 2.0 - GAP) / 2.0
	for g in groups.size():
		for index: int in PICKS[g]:
			var r: Rect2i = groups[g][index]
			scale = minf(scale, minf(box / r.size.x, box / r.size.y))
	print("escala comum dos canteiros: %.3f" % scale)
	var previews: Array[Image] = []
	for g in groups.size():
		var farm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		farm.fill(CLEAR)
		for slot in 4:
			var r: Rect2i = groups[g][PICKS[g][slot]]
			var plot := sheet.get_region(r)
			var target := Vector2i(roundi(r.size.x * scale), roundi(r.size.y * scale))
			var current := plot.get_size()
			while current.x > target.x * 2:
				current /= 2
				plot.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
			plot.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
			var cell := Vector2(SIZE * MARGIN + (slot % 2) * (box + SIZE * GAP), SIZE * MARGIN + (slot / 2) * (box + SIZE * GAP))
			var at := Vector2i(cell + (Vector2(box, box) - Vector2(target)) / 2.0)
			farm.blend_rect(plot, Rect2i(Vector2i.ZERO, target), at)
		if FARMS[g] == "fazenda_destruida":
			_remove_green_smoke(farm)
		_fill_clear(farm)
		farm.save_png(ProjectSettings.globalize_path(IMPROVEMENTS + FARMS[g] + ".png"))
		previews.append(farm)
		print("ok: %s" % FARMS[g])
	_preview(previews)
	quit()


## Tira o fundo verde (como nos outros importadores do Gemini), o verde vazado
## na borda e a FUMAÇA (cinza claro sem cor: nada mais nos canteiros é assim).
func _remove_backdrop(img: Image) -> void:
	var bg := img.get_pixel(4, 4)
	var bg_v := Vector3(bg.r, bg.g, bg.b)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var v := Vector3(p.r, p.g, p.b)
			var k := v.dot(bg_v) / bg_v.dot(bg_v)
			var backdrop := k > KEY_K.x and k < KEY_K.y and (v - bg_v * k).length() < KEY_RESIDUAL
			# Só o cinza MUITO claro e sem cor é fumaça: as cinzas dos canteiros
			# queimados também são cinza, mas escuras (o filtro antigo, com brilho
			# > 0,5, apagava as cinzas e partia os canteiros)
			var smoke := p.s < 0.08 and p.v > 0.72
			if backdrop or smoke:
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


## Caixas dos canteiros: grupos de pixels grandes (os pedaços pequenos que
## sobram, como restos de fumaça, são apagados).
func _find_plots(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var boxes: Array[Rect2i] = []
	var sizes: Array[int] = []
	for start in w * h:
		if label[start] >= 0 or img.get_pixel(start % w, start / w).a <= 0.5:
			continue
		var id := boxes.size()
		var box := Rect2i(start % w, start / w, 1, 1)
		var count := 0
		var stack := PackedInt32Array([start])
		label[start] = id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var x := i % w
			box = box.expand(Vector2i(x, i / w))
			for n in [i - 1, i + 1, i - w, i + w]:
				if n < 0 or n >= w * h or absi(n % w - x) > 1 or label[n] >= 0:
					continue
				if img.get_pixel(n % w, n / w).a > 0.5:
					label[n] = id
					stack.append(n)
		box.size += Vector2i.ONE
		boxes.append(box)
		sizes.append(count)
	var biggest := 0
	for s in sizes:
		biggest = maxi(biggest, s)
	# Pedaços grandes que se tocam são o mesmo canteiro (um canteiro queimado
	# pode se partir); pedaços pequenos encostados num canteiro entram nele; o
	# resto (sujeira longe de tudo) é apagado.
	var plots: Array[Rect2i] = []
	for i in boxes.size():
		if sizes[i] < biggest * 0.1:
			continue
		var merged := false
		for j in plots.size():
			if plots[j].grow(PIECE_REACH).intersects(boxes[i]):
				plots[j] = plots[j].merge(boxes[i])
				merged = true
				break
		if not merged:
			plots.append(boxes[i])
	for i in boxes.size():
		if sizes[i] >= biggest * 0.1:
			continue
		var owner := -1
		for j in plots.size():
			if plots[j].grow(PIECE_REACH).intersects(boxes[i]):
				owner = j
				break
		if owner >= 0:
			plots[owner] = plots[owner].merge(boxes[i])
		else:
			for y in range(boxes[i].position.y, boxes[i].end.y):
				for x in range(boxes[i].position.x, boxes[i].end.x):
					if label[y * w + x] == i:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
	print("%d canteiros" % plots.size())
	return plots


## A fumaça dos canteiros queimados sobe até o canteiro de cima e liga os 3 da
## coluna num bloco alto. As linhas dos canteiros normais (altura parecida com
## a mediana) dão as faixas de cada linha; um bloco alto é cortado nelas: em
## cada faixa, a caixa do que não é transparente (a fumaça entre as faixas
## fica de fora).
func _split_tall(img: Image, plots: Array[Rect2i]) -> Array[Rect2i]:
	var heights: Array = plots.map(func(r: Rect2i) -> int: return r.size.y)
	heights.sort()
	var median: int = heights[heights.size() / 2]
	var bands: Array[Vector2i] = []
	for r in plots:
		if r.size.y > median * 1.3:
			continue
		var placed := false
		for b in bands.size():
			if r.position.y < bands[b].y and r.end.y > bands[b].x:
				bands[b] = Vector2i(mini(bands[b].x, r.position.y), maxi(bands[b].y, r.end.y))
				placed = true
		if not placed:
			bands.append(Vector2i(r.position.y, r.end.y))
	var result: Array[Rect2i] = []
	for r in plots:
		if r.size.y <= median * 1.5:
			result.append(r)
			continue
		for band in bands:
			var top := maxi(r.position.y, band.x)
			var bottom := mini(r.end.y, band.y)
			if bottom - top < median / 2:
				continue
			var piece := Rect2i()
			var first := true
			for y in range(top, bottom):
				for x in range(r.position.x, r.end.x):
					if img.get_pixel(x, y).a > 0.5:
						piece = Rect2i(x, y, 1, 1) if first else piece.expand(Vector2i(x, y))
						first = false
			if not first:
				piece.size += Vector2i.ONE
				result.append(piece)
	print("faixas das linhas: %s; %d canteiros depois de cortar os blocos altos" % [bands, result.size()])
	return result


## Separa os canteiros (já em ordem de x) em [param count] grupos pelos maiores
## vãos entre eles; dentro de cada grupo, ordena por linhas (de cima para
## baixo) e, na linha, da esquerda para a direita.
func _split_groups(plots: Array[Rect2i], count: int) -> Array:
	var gaps := []
	for i in range(1, plots.size()):
		gaps.append([plots[i].position.x - plots[i - 1].end.x, i])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var cuts := []
	for i in count - 1:
		cuts.append(gaps[i][1])
	cuts.sort()
	var groups := []
	var start := 0
	for cut: int in cuts + [plots.size()]:
		var group: Array = plots.slice(start, cut)
		group.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
			var row_a := a.get_center().y
			var row_b := b.get_center().y
			if absf(row_a - row_b) > a.size.y * 0.5:
				return row_a < row_b
			return a.position.x < b.position.x)
		groups.append(group)
		start = cut
	print("grupos: %s canteiros" % [groups.map(func(g: Array) -> int: return g.size())])
	return groups


## Fazenda queimada: nada nela é verde de verdade. A fumaça que passou sobre o
## fundo ficou esverdeada: o verde claro some e o resto perde o excesso de verde.
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
## na borda dos canteiros; preto faria um contorno escuro).
func _fill_clear(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a == 0.0:
				img.set_pixel(x, y, CLEAR)


func _preview(farms: Array[Image]) -> void:
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
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + "fazendas_previa.png"))
