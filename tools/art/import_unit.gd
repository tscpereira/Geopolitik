extends SceneTree

## Importa UM desenho de unidade gerado no ChatGPT (prompts em
## PROMPTS-CHATGPT.txt) direto para o jogo. Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_unit.gd -- <imagem> <nome>
## ex.: ... -- C:/Users/.../cavalaria_leve.png cavalaria_leve
## Passos (os mesmos de import_sheet.gd, para uma imagem só):
##   1. remove o fundo xadrez "pintado" (o ChatGPT não gera transparência de
##      verdade): inundação a partir das bordas pelos pixels claros e neutros,
##      e os bolsões fechados que só têm os dois tons do xadrez;
##   2. recorta o desenho (todos os grupos de pixels que não são fundo);
##   3. separa o azul do time numa máscara (<nome>_time.png) e deixa essas
##      partes escuras no desenho (o jogo soma máscara x cor do jogador);
##   4. reduz para 80x80, pés em y = 73, e grava em assets/sprites/units/;
##      guarda a imagem original e o recorte grande em tools/art/chatgpt/
##      (grandes/) e uma prévia com as cores dos dois jogadores em prontos/.

const UNITS := "res://assets/sprites/units/"
const GRANDES := "res://tools/art/chatgpt/grandes/"
const PRONTOS := "res://tools/art/chatgpt/prontos/"
const ORIGINAIS := "res://tools/art/chatgpt/"
## Unidade: 80x80, desenho em até MAX_SIZE, pés na linha FEET.
const SIZE := 80
const MAX_SIZE := Vector2(76, 70)
const FEET := 73


func is_backdrop(p: Color) -> bool:
	var spread := maxf(p.r, maxf(p.g, p.b)) - minf(p.r, minf(p.g, p.b))
	return spread < 0.035 and p.v > 0.86


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("uso: -- <imagem> <nome>")
		quit(1)
		return
	var unit_name: String = args[1]
	var image := Image.load_from_file(args[0])
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(ProjectSettings.globalize_path(ORIGINAIS) + unit_name + "_original.png")
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
		if bg[i] != 0 or not is_backdrop(image.get_pixel(i % w, i / w)):
			continue
		bg[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	# 1b. Bolsões fechados (entre a lança e o pescoço, entre as patas): claros,
	# neutros e só com os dois tons do xadrez (o branco das roupas tem sombreado)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if bg[start] != 0 or seen[start] != 0 or not is_backdrop(image.get_pixel(start % w, start / w)):
			continue
		var members := PackedInt32Array()
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var dark := 0
		var light := 0
		while not queue.is_empty():
			var i := queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			members.append(i)
			var v := image.get_pixel(i % w, i / w).v
			if v > 0.89 and v < 0.95:
				dark += 1
			elif v > 0.97:
				light += 1
			var x := i % w
			for n in [i - 1, i + 1, i - w, i + w]:
				if n < 0 or n >= w * h or absi(n % w - x) > 1:
					continue
				if seen[n] == 0 and bg[n] == 0 and is_backdrop(image.get_pixel(n % w, n / w)):
					seen[n] = 1
					queue.append(n)
		var total := members.size()
		var two_tones := float(dark + light) / total
		var checker := total >= 12 and two_tones > 0.8 and dark > total * 0.15 and light > total * 0.15
		if checker:
			for i in members:
				bg[i] = 1
		if total > 40:
			print("  bolsão em %s: %d px, dois tons %.0f%% -> %s" % [Vector2i(start % w, start / w), total, two_tones * 100, "xadrez" if checker else "mantido"])
	# 2. Recorte: caixa de todos os pixels que não são fundo
	var box := Rect2i()
	var first := true
	for i in w * h:
		if bg[i] == 0:
			var cell := Vector2i(i % w, i / w)
			box = Rect2i(cell, Vector2i.ONE) if first else box.expand(cell)
			first = false
	box.size += Vector2i.ONE
	print("desenho: %s" % box)
	# 3. Desenho sem fundo e máscara do azul do time
	var crop := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	for y in box.size.y:
		for x in box.size.x:
			var i := (box.position.y + y) * w + box.position.x + x
			var p := image.get_pixel(box.position.x + x, box.position.y + y)
			var fringe := false
			for n in [i - 1, i + 1, i - w, i + w]:
				if n >= 0 and n < w * h and bg[n] != 0 and is_backdrop(p):
					fringe = true
			if bg[i] != 0 or fringe:
				crop.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
				continue
			var blue := 0.0
			if p.h > 0.56 and p.h < 0.74 and p.v > 0.12:
				blue = smoothstep(0.28, 0.5, p.s) * (1.0 - smoothstep(0.06, 0.1, absf(p.h - 0.64)))
			var amount := blue * clampf(p.v / 0.85, 0.0, 1.0)
			crop.set_pixel(x, y, Color(p.r * (1.0 - blue), p.g * (1.0 - blue), p.b * (1.0 - blue), 1.0))
			mask.set_pixel(x, y, Color(amount, amount, amount, 1.0))
	crop.save_png(ProjectSettings.globalize_path(GRANDES) + unit_name + ".png")
	mask.save_png(ProjectSettings.globalize_path(GRANDES) + unit_name + "_time.png")
	# 4. Tamanho do jogo
	var scale := minf(MAX_SIZE.x / box.size.x, MAX_SIZE.y / box.size.y)
	var target := Vector2i(roundi(box.size.x * scale), roundi(box.size.y * scale))
	for img: Image in [crop, mask]:
		var current: Vector2i = img.get_size()
		while current.x > target.x * 2:
			current /= 2
			img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var sprite := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var sprite_mask := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var at := Vector2i((SIZE - target.x) / 2, FEET - target.y)
	sprite.blit_rect(crop, Rect2i(Vector2i.ZERO, target), at)
	mask.convert(Image.FORMAT_L8)
	sprite_mask.blit_rect(mask, Rect2i(Vector2i.ZERO, target), at)
	sprite.save_png(ProjectSettings.globalize_path(UNITS) + unit_name + ".png")
	sprite_mask.save_png(ProjectSettings.globalize_path(UNITS) + unit_name + "_time.png")
	sprite.save_png(ProjectSettings.globalize_path(PRONTOS) + unit_name + ".png")
	sprite_mask.save_png(ProjectSettings.globalize_path(PRONTOS) + unit_name + "_time.png")
	# Prévia: as cores dos dois jogadores, ampliada 3x sobre a pradaria
	var grass := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/pradaria.png"))
	grass.convert(Image.FORMAT_RGBA8)
	var preview := Image.create(SIZE * 6, SIZE * 3, false, Image.FORMAT_RGBA8)
	grass.resize(SIZE * 3, SIZE * 3, Image.INTERPOLATE_BILINEAR)
	for k in 2:
		preview.blit_rect(grass, Rect2i(Vector2i.ZERO, grass.get_size()), Vector2i(k * SIZE * 3, 0))
		var tinted := tint(sprite, sprite_mask, Color8(220, 40, 40) if k == 0 else Color8(250, 220, 40))
		tinted.resize(SIZE * 3, SIZE * 3, Image.INTERPOLATE_BILINEAR)
		preview.blend_rect(tinted, Rect2i(Vector2i.ZERO, tinted.get_size()), Vector2i(k * SIZE * 3, 0))
	preview.save_png(ProjectSettings.globalize_path(PRONTOS) + unit_name + "_previa.png")
	print("ok: %s" % unit_name)
	quit()


## Aplica a cor do jogador como o jogo faz (Unit.team_texture): base + máscara x cor.
func tint(sprite: Image, mask: Image, color: Color) -> Image:
	var result := sprite.duplicate()
	for y in sprite.get_height():
		for x in sprite.get_width():
			var m := mask.get_pixel(x, y).r
			if m > 0.0:
				var p := sprite.get_pixel(x, y)
				result.set_pixel(x, y, Color(minf(p.r + color.r * m, 1), minf(p.g + color.g * m, 1), minf(p.b + color.b * m, 1), p.a))
	return result
