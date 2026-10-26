extends SceneTree

## Importa o desenho da Galé trazido pelo usuário (25/10/2026; guardado em
## tools/art/chatgpt/gale_original.png): barco longo de casco marrom, vela
## branca com listras cinza-escuro, escudos e remos, sobre fundo cinza-claro liso.
##   godot_console.cmd --headless --path . --script tools/art/import_gale.gd [-- <imagem>]
## Sem imagem, usa a original guardada. Passos:
##   1. fundo: inundação a partir das bordas pelos pixels cinza-claros neutros
##      (brilho 0,90-0,955; a vela é mais branca, 0,98+), e os bolsões fechados
##      só com esse cinza (entre as cordas, entre os remos);
##   2. as LISTRAS DA VELA (cinza-escuro neutro dentro da área da vela) viram a
##      cor do jogador: escuras na imagem e brancas na máscara gale_time.png
##      (Unit.team_texture soma a cor do jogador na proporção da máscara);
##   3. recorta, reduz para caber em 76x70 com o casco em y = 73 e grava
##      assets/sprites/units/gale.png e gale_time.png, e uma prévia com as cores
##      de dois jogadores em tools/art/chatgpt/prontos/gale_previa.png.

const ORIGINAL := "res://tools/art/chatgpt/gale_original.png"
const UNITS := "res://assets/sprites/units/"
const PRONTOS := "res://tools/art/chatgpt/prontos/"
const SIZE := 80
const MAX_SIZE := Vector2(76, 70)
const FEET := 73
## Área da vela na imagem original (114x105): onde o cinza-escuro é listra.
const SAIL_BOX := Rect2i(24, 17, 66, 44)


## Cinza do fundo (para os bolsões fechados: a vela, mais branca, fica).
func is_backdrop(p: Color) -> bool:
	return p.s < 0.05 and p.v > 0.895 and p.v < 0.958


## Na inundação a partir das bordas vale também o halo mais claro em volta do
## desenho (a vela fica protegida pelo contorno escuro).
func is_outer_backdrop(p: Color) -> bool:
	return p.s < 0.08 and p.v > 0.86


## Quanto o pixel é listra da vela: cinza neutro escuro (0 = não é).
func stripe_amount(p: Color) -> float:
	if p.s > 0.16:
		return 0.0 # marrom do mastro e do casco
	return 1.0 - smoothstep(0.42, 0.8, p.v)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var image := Image.load_from_file(args[0] if not args.is_empty() else ProjectSettings.globalize_path(ORIGINAL))
	image.convert(Image.FORMAT_RGBA8)
	if not args.is_empty():
		image.save_png(ProjectSettings.globalize_path(ORIGINAL))
	var w := image.get_width()
	var h := image.get_height()
	# 1. Fundo: inundação a partir das bordas
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] != 0 or not is_outer_backdrop(image.get_pixel(i % w, i / w)):
			continue
		bg[i] = 1
		var x := i % w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if i >= w: stack.append(i - w)
		if i < w * (h - 1): stack.append(i + w)
	# 1b. Bolsões fechados de fundo (4+ pixels, todos no cinza do fundo)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if bg[start] != 0 or seen[start] != 0 or not is_backdrop(image.get_pixel(start % w, start / w)):
			continue
		var members := PackedInt32Array()
		var queue := PackedInt32Array([start])
		seen[start] = 1
		while not queue.is_empty():
			var i := queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			members.append(i)
			var x := i % w
			for n in [i - 1, i + 1, i - w, i + w]:
				if n < 0 or n >= w * h or absi(n % w - x) > 1:
					continue
				if seen[n] == 0 and bg[n] == 0 and is_backdrop(image.get_pixel(n % w, n / w)):
					seen[n] = 1
					queue.append(n)
		if members.size() >= 4:
			for i in members:
				bg[i] = 1
	# 2. Desenho sem fundo e máscara das listras; recorte
	var box := Rect2i()
	var first := true
	var crop_full := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mask_full := Image.create(w, h, false, Image.FORMAT_RGBA8)
	mask_full.fill(Color.BLACK)
	for y in h:
		for x in w:
			var i := y * w + x
			if bg[i] != 0:
				crop_full.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
				continue
			var p := image.get_pixel(x, y)
			# Borda clara grudada no fundo (mistura com o cinza): transparente se
			# for quase só fundo, meio transparente se for meio a meio
			var alpha := 1.0
			for n in [i - 1, i + 1, i - w, i + w]:
				if n >= 0 and n < w * h and bg[n] != 0 and p.s < 0.2:
					alpha = minf(alpha, clampf((0.9 - p.v) / 0.35, 0.0, 1.0))
			if alpha <= 0.05:
				crop_full.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
				continue
			var amount := stripe_amount(p) if SAIL_BOX.has_point(Vector2i(x, y)) else 0.0
			# Na listra, a imagem fica escura (o jogo soma a cor do jogador)
			crop_full.set_pixel(x, y, Color(p.r * (1.0 - amount * 0.85), p.g * (1.0 - amount * 0.85), p.b * (1.0 - amount * 0.85), alpha))
			mask_full.set_pixel(x, y, Color(amount, amount, amount))
			var cell := Vector2i(x, y)
			box = Rect2i(cell, Vector2i.ONE) if first else box.expand(cell)
			first = false
	box.size += Vector2i.ONE
	print("desenho: %s" % box)
	var crop := crop_full.get_region(box)
	var mask := mask_full.get_region(box)
	# 3. Tamanho do jogo
	var scale := minf(MAX_SIZE.x / box.size.x, MAX_SIZE.y / box.size.y)
	var target := Vector2i(roundi(box.size.x * scale), roundi(box.size.y * scale))
	crop.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	mask.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	var sprite := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var sprite_mask := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var at := Vector2i((SIZE - target.x) / 2, FEET - target.y)
	sprite.blit_rect(crop, Rect2i(Vector2i.ZERO, target), at)
	mask.convert(Image.FORMAT_L8)
	sprite_mask.blit_rect(mask, Rect2i(Vector2i.ZERO, target), at)
	sprite.save_png(ProjectSettings.globalize_path(UNITS) + "gale.png")
	sprite_mask.save_png(ProjectSettings.globalize_path(UNITS) + "gale_time.png")
	# Prévia: vermelho e amarelo, ampliada 3x sobre a água
	var water := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/agua.png"))
	water.convert(Image.FORMAT_RGBA8)
	water.resize(SIZE * 3, SIZE * 3, Image.INTERPOLATE_BILINEAR)
	var preview := Image.create(SIZE * 6, SIZE * 3, false, Image.FORMAT_RGBA8)
	for k in 2:
		preview.blit_rect(water, Rect2i(Vector2i.ZERO, water.get_size()), Vector2i(k * SIZE * 3, 0))
		var tinted := _tint(sprite, sprite_mask, Color8(220, 40, 40) if k == 0 else Color8(250, 220, 40))
		tinted.resize(SIZE * 3, SIZE * 3, Image.INTERPOLATE_BILINEAR)
		preview.blend_rect(tinted, Rect2i(Vector2i.ZERO, tinted.get_size()), Vector2i(k * SIZE * 3, 0))
	preview.save_png(ProjectSettings.globalize_path(PRONTOS) + "gale_previa.png")
	print("ok: gale")
	quit()


## A cor do jogador aplicada como no jogo (Unit.team_texture): base + máscara x cor.
func _tint(sprite: Image, mask: Image, color: Color) -> Image:
	var result := sprite.duplicate()
	for y in sprite.get_height():
		for x in sprite.get_width():
			var m := mask.get_pixel(x, y).r
			if m > 0.0:
				var p := sprite.get_pixel(x, y)
				result.set_pixel(x, y, Color(minf(p.r + color.r * m, 1), minf(p.g + color.g * m, 1), minf(p.b + color.b * m, 1), p.a))
	return result
