extends SceneTree

## Importa uma folha de CIDADES (ou ruínas) do Gemini (fundo verde liso;
## tools/art/gemini/pedidos/0N_cidades_*). Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_cidades_gemini.gd -- <folha.png> <nome1> <nome2> ...
## Os desenhos são achados sozinhos (cada ilha é um grupo de pixels; pedaços
## soltos, como a fumaça, entram no desenho mais perto) e numerados por linha,
## de cima para baixo, e da esquerda para a direita. Os nomes vão nessa ordem;
## "-" pula um desenho (ex.: a vila veio com uma linha extra de 3 tentativas):
##   ... -- vila.png - - - vila vila_capital vila_muralha vila_capital_muralha
## Cada nome é um arquivo de assets/sprites/cities/ (<classe>[_capital]
## [_muralha][_ruinas]). Todos os desenhos da mesma folha usam a MESMA escala
## (são a mesma cidade): o maior cabe em MAX_WIDTH da classe e em MAX_HEIGHT,
## centralizado, com a base na linha BOTTOM (como os desenhos antigos). O azul
## do time vira a máscara <nome>_time.png (as ruínas não têm). Guarda a folha
## em tools/art/gemini/originais/<primeiro nome>_folha.png e grava uma prévia em
## tools/art/gemini/previas/<primeiro nome>_previa.png.

const CITIES := "res://assets/sprites/cities/"
## Originais do Gemini (guardados no git) e prévias (geradas, fora do git).
const GEMINI := "res://tools/art/gemini/originais/"
const PREVIEWS := "res://tools/art/gemini/previas/"
const SIZE := 128
const BOTTOM := 124
const MAX_HEIGHT := 120
## Largura máxima por classe: as cidades crescem a cada nível (26/10/2026; a
## mesma tabela de tools/art/ajusta_tamanho_cidades.gd).
const MAX_WIDTH := {"povoado": 74, "vila": 92, "cidade": 108, "metropole": 122}
## Fundo: resíduo máximo de p - k x fundo e a faixa de k (como import_folha_unidades.gd).
const KEY_RESIDUAL := 14.0 / 255.0
const KEY_K := Vector2(0.55, 1.2)
## Passadas de limpeza do verde na borda dos desenhos.
const EDGE_PASSES := 3
## Grupos com menos que isto (fração do maior) são pedaços soltos.
const PIECE := 0.08


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("uso: -- <folha.png> <nome1|-> <nome2|-> ...")
		quit(1)
		return
	var names: Array = args.slice(1)
	var sheet := Image.load_from_file(args[0])
	sheet.convert(Image.FORMAT_RGBA8)
	var first_name: String = names.filter(func(n: String) -> bool: return n != "-")[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEMINI))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + first_name + "_folha.png"))
	_remove_backdrop(sheet)
	var boxes := _find_drawings(sheet)
	print("%d desenhos achados: %s" % [boxes.size(), boxes])
	if boxes.size() != names.size():
		print("ERRO: %d nomes para %d desenhos" % [names.size(), boxes.size()])
		quit(1)
		return
	# Escala comum: o maior desenho (dos que serão usados) cabe no quadro
	var rank: String = first_name.split("_")[0]
	var scale := INF
	for i in boxes.size():
		if names[i] != "-":
			scale = minf(scale, minf(float(MAX_WIDTH[rank]) / boxes[i].size.x, float(MAX_HEIGHT) / boxes[i].size.y))
	print("escala: %.3f" % scale)
	var previews: Array[Image] = []
	for i in boxes.size():
		if names[i] == "-":
			continue
		previews.append(_install(sheet.get_region(boxes[i]), names[i], scale))
	_preview(previews, PREVIEWS + first_name + "_previa.png")
	quit()


func _remove_backdrop(img: Image) -> void:
	var bg := img.get_pixel(4, 4)
	var bg_v := Vector3(bg.r, bg.g, bg.b)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var v := Vector3(p.r, p.g, p.b)
			var k := v.dot(bg_v) / bg_v.dot(bg_v)
			if k > KEY_K.x and k < KEY_K.y and (v - bg_v * k).length() < KEY_RESIDUAL:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	# Borda: o verde do fundo vazou numa faixa de 2-3 pixels em volta das ilhas
	# (as árvores são verdes de verdade, então só na borda). A cada passada, os
	# pixels encostados no transparente: quase só fundo -> transparente; um
	# pouco de fundo -> sem o excesso de verde e meio transparente.
	for edge_pass in EDGE_PASSES:
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
				var excess := p.g - maxf(p.r, p.b)
				if excess > 0.2:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				else:
					img.set_pixel(x, y, Color(p.r, maxf(p.r, p.b), p.b, minf(p.a, 0.7)))


## Grupos de pixels: os grandes são os desenhos; os pedaços soltos (fumaça,
## uma árvore separada) entram no desenho cuja caixa fica mais perto. Ordem:
## por linhas (de cima para baixo), cada linha da esquerda para a direita.
func _find_drawings(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var groups: Array[Rect2i] = []
	var sizes: Array[int] = []
	for start in w * h:
		if label[start] >= 0 or img.get_pixel(start % w, start / w).a <= 0.5:
			continue
		var id := groups.size()
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
		groups.append(box)
		sizes.append(count)
	var biggest := 0
	for s in sizes:
		biggest = maxi(biggest, s)
	var drawings: Array[Rect2i] = []
	for i in groups.size():
		if sizes[i] >= biggest * PIECE:
			drawings.append(groups[i])
	for i in groups.size():
		if sizes[i] >= biggest * PIECE:
			continue
		var best := -1
		var best_distance := INF
		for j in drawings.size():
			var d := drawings[j].get_center().distance_to(groups[i].get_center())
			if d < best_distance:
				best_distance = d
				best = j
		# Só junta o que está encostado ou bem perto (pedaços longe são sujeira);
		# pedaço que toca a borda da imagem é resto de print (ex.: o ícone no canto)
		var at_border: bool = groups[i].position.x <= 0 or groups[i].position.y <= 0 \
				or groups[i].end.x >= w or groups[i].end.y >= h
		if best >= 0 and not at_border and drawings[best].grow(30).intersects(groups[i]):
			drawings[best] = drawings[best].merge(groups[i])
		else:
			for y in range(groups[i].position.y, groups[i].end.y):
				for x in range(groups[i].position.x, groups[i].end.x):
					if label[y * w + x] == i:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
	# Linhas: desenhos cujos centros verticais estão perto ficam na mesma
	drawings.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.get_center().y < b.get_center().y)
	var rows: Array = []
	for box in drawings:
		if rows.is_empty() or absf(box.get_center().y - rows[-1][0].get_center().y) > box.size.y * 0.5:
			rows.append([box])
		else:
			rows[-1].append(box)
	var ordered: Array[Rect2i] = []
	for row: Array in rows:
		row.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
		for box: Rect2i in row:
			ordered.append(box)
	return ordered


## Reduz, separa o azul do time na máscara e grava o desenho 128x128.
func _install(crop: Image, name: String, scale: float) -> Image:
	var w := crop.get_width()
	var h := crop.get_height()
	var mask := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ruins := name.ends_with("_ruinas")
	for y in h:
		for x in w:
			var p := crop.get_pixel(x, y)
			if p.a == 0.0:
				crop.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
				continue
			var blue := 0.0
			if not ruins and p.h > 0.56 and p.h < 0.74 and p.v > 0.12:
				blue = smoothstep(0.28, 0.5, p.s) * (1.0 - smoothstep(0.06, 0.1, absf(p.h - 0.64)))
			var amount := blue * clampf(p.v / 0.85, 0.0, 1.0)
			crop.set_pixel(x, y, Color(p.r * (1.0 - blue), p.g * (1.0 - blue), p.b * (1.0 - blue), p.a))
			mask.set_pixel(x, y, Color(amount, amount, amount, 1.0))
	var target := Vector2i(maxi(1, roundi(w * scale)), maxi(1, roundi(h * scale)))
	for img: Image in [crop, mask]:
		var current: Vector2i = img.get_size()
		while current.x > target.x * 2:
			current /= 2
			img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var sprite := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var sprite_mask := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var at := Vector2i((SIZE - target.x) / 2, BOTTOM - target.y)
	sprite.blit_rect(crop, Rect2i(Vector2i.ZERO, target), at)
	mask.convert(Image.FORMAT_L8)
	sprite_mask.blit_rect(mask, Rect2i(Vector2i.ZERO, target), at)
	sprite.save_png(ProjectSettings.globalize_path(CITIES + name + ".png"))
	if not ruins:
		sprite_mask.save_png(ProjectSettings.globalize_path(CITIES + name + "_time.png"))
	print("ok: %s (%s -> %s)" % [name, crop.get_size() if false else Vector2i(w, h), target])
	return _tint(sprite, sprite_mask, Color8(220, 40, 40))


## Prévia: os desenhos lado a lado, ampliados 2x, na cor vermelha, sobre a pradaria.
func _preview(images: Array[Image], path: String) -> void:
	var grass := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/pradaria.png"))
	grass.convert(Image.FORMAT_RGBA8)
	grass.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_BILINEAR)
	var sheet := Image.create(SIZE * 2 * images.size(), SIZE * 2, false, Image.FORMAT_RGBA8)
	for i in images.size():
		sheet.blit_rect(grass, Rect2i(Vector2i.ZERO, grass.get_size()), Vector2i(i * SIZE * 2, 0))
		var big := images[i].duplicate()
		big.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_BILINEAR)
		sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(i * SIZE * 2, 0))
	sheet.save_png(ProjectSettings.globalize_path(path))


func _tint(sprite: Image, mask: Image, color: Color) -> Image:
	var result := sprite.duplicate()
	for y in sprite.get_height():
		for x in sprite.get_width():
			var m := mask.get_pixel(x, y).r
			if m > 0.0:
				var p := sprite.get_pixel(x, y)
				result.set_pixel(x, y, Color(minf(p.r + color.r * m, 1), minf(p.g + color.g * m, 1), minf(p.b + color.b * m, 1), p.a))
	return result
