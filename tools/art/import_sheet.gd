extends SceneTree

## Importador da folha de sprites gerada no ChatGPT (tools/art/chatgpt/folha.png,
## prompt em tools/art/PROMPTS-CHATGPT.txt). AINDA NÃO APLICADO NO JOGO: grava
## em tools/art/chatgpt/prontos/; para aplicar, copiar para assets/ (ver a
## documentação, BACKLOG). Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_sheet.gd
## Passos:
##   1. remove o fundo xadrez "pintado" (o ChatGPT não gera transparência de
##      verdade): inundação a partir das bordas por pixels claros e neutros, e
##      os bolsões fechados que trocam de tom a cada ~11 px (os quadrados);
##   2. separa os 9 desenhos pelo contorno (5 unidades em cima, 4 cidades
##      embaixo, da esquerda para a direita);
##   3. separa o azul do time numa máscara (<nome>_time.png) e deixa essas
##      partes escuras no desenho (o jogo soma máscara x cor do jogador);
##   4. reduz para 80x80 (unidades, pés em y = 73) e 128x128 (cidades);
##   5. grava uma prévia no tamanho do jogo (zoom 1,0 e 0,5, vermelho e amarelo).

const SRC := "res://tools/art/chatgpt/folha.png"
const OUT := "res://tools/art/chatgpt/prontos/"


## Grade do xadrez "pintado": quadrados de 1536/144 px, a partir de x = y = 0,667.
const CHECKER := 1536.0 / 144.0
const CHECKER_OFFSET := 0.667


func is_backdrop(p: Color) -> bool:
	var spread := maxf(p.r, maxf(p.g, p.b)) - minf(p.r, minf(p.g, p.b))
	return spread < 0.035 and p.v > 0.86


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var image := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var start := Time.get_ticks_msec()
	# 1. Inundação do fundo a partir das bordas
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
		if bg[i] != 0:
			continue
		var x := i % w
		var y := i / w
		if not is_backdrop(image.get_pixel(x, y)):
			continue
		bg[i] = 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	print("fundo: %d ms" % (Time.get_ticks_msec() - start))
	# 1b. Bolsões fechados de xadrez (dentro do arco, entre a lança e a perna):
	# grupos de pixels claros e neutros que a inundação não alcançou e que
	# têm só os dois tons do xadrez (o branco das túnicas tem sombreado)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start_i in w * h:
		if bg[start_i] != 0 or seen[start_i] != 0 or not is_backdrop(image.get_pixel(start_i % w, start_i / w)):
			continue
		var members := PackedInt32Array()
		var queue := PackedInt32Array([start_i])
		seen[start_i] = 1
		var dark := 0
		var light := 0
		while not queue.is_empty():
			var i := queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			members.append(i)
			var v := image.get_pixel(i % w, i / w).v
			if v > 0.9 and v < 0.945:
				dark += 1
			elif v > 0.97:
				light += 1
			var x := i % w
			var y := i / w
			for n in [i - 1, i + 1, i - w, i + w]:
				if n < 0 or n >= w * h or absi(n % w - x) > 1:
					continue
				if seen[n] == 0 and bg[n] == 0 and is_backdrop(image.get_pixel(n % w, n / w)):
					seen[n] = 1
					queue.append(n)
		# O xadrez segue uma grade fixa: quadrados de CHECKER px a partir de
		# CHECKER_OFFSET. Conta quantos pixels têm o tom que a grade prevê
		# (fora de 1 px da borda de cada quadrado)
		# No xadrez o tom troca a cada quadrado (~11 px) na horizontal e na
		# vertical, e se repete na diagonal; no branco das túnicas, não.
		# Compara só com vizinhos (a ~11 px, nas 4 direções) que também estão no
		# bolsão: assim funciona até nos bolsões estreitos.
		var total := members.size()
		var inside := {}
		for i in members:
			inside[i] = true
		var tested := 0
		var matching := 0
		var step := roundi(CHECKER)
		for i in members:
			var tone := image.get_pixel(i % w, i / w).v > 0.955
			for n in [i - step, i + step, i - step * w, i + step * w]:
				if inside.has(n):
					tested += 1
					if (image.get_pixel(n % w, n / w).v > 0.955) != tone:
						matching += 1
		var agreement := float(matching) / maxi(tested, 1)
		var checker := total > 60 and tested > 20 and agreement > 0.6
		if total > 150:
			print("  bolsão em %s: %d px, segue a grade em %.0f%% -> %s" % [Vector2i(start_i % w, start_i / w), total, agreement * 100, "xadrez" if checker else "mantido"])
		if checker:
			for i in members:
				bg[i] = 1
	# 2. Desenhos: grupos de pixels que não são fundo (8 vizinhos)
	var label := PackedInt32Array()
	label.resize(w * h)
	var boxes := []
	for start_i in w * h:
		if bg[start_i] != 0 or label[start_i] != 0:
			continue
		var id := boxes.size() + 1
		var box := Rect2i(start_i % w, start_i / w, 1, 1)
		var count := 0
		var queue := PackedInt32Array([start_i])
		label[start_i] = id
		while not queue.is_empty():
			var i := queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			count += 1
			var x := i % w
			var y := i / w
			box = box.expand(Vector2i(x, y))
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var n := ny * w + nx
					if bg[n] == 0 and label[n] == 0:
						label[n] = id
						queue.append(n)
		boxes.append([id, Rect2i(box.position, box.size + Vector2i.ONE), count])
	var big := boxes.filter(func(b: Array) -> bool: return b[2] > 2000)
	print("grupos: %d, grandes: %d (%d ms)" % [boxes.size(), big.size(), Time.get_ticks_msec() - start])
	big.sort_custom(func(a: Array, b: Array) -> bool:
		var ra: int = 0 if a[1].get_center().y < h / 2 else 1
		var rb: int = 0 if b[1].get_center().y < h / 2 else 1
		return ra < rb if ra != rb else a[1].position.x < b[1].position.x)
	for b in big:
		print("  %s  %d px" % [b[1], b[2]])
	# 3. Cada desenho: recorte no tamanho do jogo, máscara do azul do time
	var names := ["guerreiro", "arqueiro", "cavaleiro", "colono", "trabalhador", "povoado", "vila", "cidade", "metropole"]
	var made := {}
	for k in big.size():
		var r: Rect2i = big[k][1]
		var crop := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		var mask := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		for y in r.size.y:
			for x in r.size.x:
				var i := (r.position.y + y) * w + r.position.x + x
				if bg[i] != 0:
					crop.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
					continue
				var p := image.get_pixel(r.position.x + x, r.position.y + y)
				# Franja clara do xadrez colada no contorno: some
				var fringe := false
				for n in [i - 1, i + 1, i - w, i + w]:
					if n >= 0 and n < w * h and bg[n] != 0 and is_backdrop(p):
						fringe = true
				if fringe:
					crop.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
					continue
				# Azul do time: peso pela saturação e pela distância do matiz azul
				var blue := 0.0
				if p.h > 0.56 and p.h < 0.74 and p.v > 0.12:
					blue = smoothstep(0.28, 0.5, p.s) * (1.0 - smoothstep(0.06, 0.1, absf(p.h - 0.64)))
				var amount := blue * clampf(p.v / 0.85, 0.0, 1.0)
				crop.set_pixel(x, y, Color(p.r * (1.0 - blue), p.g * (1.0 - blue), p.b * (1.0 - blue), 1.0))
				mask.set_pixel(x, y, Color(amount, amount, amount, 1.0))
		var is_unit := k < 5
		var size := 80 if is_unit else 128
		var max_size := Vector2(76, 70) if is_unit else Vector2(124, 120)
		var scale := minf(max_size.x / r.size.x, max_size.y / r.size.y)
		var target := Vector2i(roundi(r.size.x * scale), roundi(r.size.y * scale))
		for img: Image in [crop, mask]:
			var current: Vector2i = img.get_size()
			while current.x > target.x * 2:
				current /= 2
				img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
			img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
		var sprite := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var sprite_mask := Image.create(size, size, false, Image.FORMAT_L8)
		var bottom := 73 if is_unit else 124
		var at := Vector2i((size - target.x) / 2, bottom - target.y)
		sprite.blit_rect(crop, Rect2i(Vector2i.ZERO, target), at)
		var mask_l8 := mask.duplicate()
		mask_l8.convert(Image.FORMAT_L8)
		sprite_mask.blit_rect(mask_l8, Rect2i(Vector2i.ZERO, target), at)
		sprite.save_png(ProjectSettings.globalize_path(OUT) + names[k] + ".png")
		sprite_mask.save_png(ProjectSettings.globalize_path(OUT) + names[k] + "_time.png")
		made[names[k]] = [sprite, sprite_mask]
	print("recortes prontos (%d ms)" % (Time.get_ticks_msec() - start))
	# 4. Prévia no tamanho do jogo: zoom 1,0 (80 px por casa) e zoom 0,5 (o
	# inicial), em vermelho (J1) e amarelo (J2), sobre a pradaria do jogo
	var grass := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/pradaria.png"))
	grass.convert(Image.FORMAT_RGBA8)
	var sheet := Image.create(1200, 560, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(22, 24, 30))
	for zoom_row in 2:
		var z := 1.0 if zoom_row == 0 else 0.5
		var top := 10 if zoom_row == 0 else 380
		var tile := roundi(80 * z)
		var g := grass.duplicate()
		g.resize(tile, tile, Image.INTERPOLATE_BILINEAR)
		var cols := 15 if zoom_row == 0 else 30
		var rows := 4 if zoom_row == 0 else 4
		for ty in rows:
			for tx in cols:
				sheet.blit_rect(g, Rect2i(0, 0, tile, tile), Vector2i(tx * tile, top + ty * tile))
		var x := 0
		for side in 2:
			var color := Color8(220, 40, 40) if side == 0 else Color8(250, 220, 40)
			for k in names.size():
				var pair: Array = made[names[k]]
				var tinted: Image = tint(pair[0], pair[1], color)
				var s := roundi(tinted.get_width() * z)
				tinted.resize(s, s, Image.INTERPOLATE_BILINEAR)
				var y := top + (tile * 2 - s if k >= 5 else tile)
				if k >= 5:
					y = top + tile * 2 - roundi(s * 0.85)
				sheet.blend_rect(tinted, Rect2i(0, 0, s, s), Vector2i(x, y))
				x += s + roundi(8 * z)
			x += roundi(30 * z)
	sheet.save_png(ProjectSettings.globalize_path(OUT) + "previa_tamanho_real.png")
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
