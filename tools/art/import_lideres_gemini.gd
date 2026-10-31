extends SceneTree

## Importa os retratos de um LÍDER feitos pelo Gemini (pedidos 13 a 18,
## lider_<líder>: as 3 expressões, brava, neutra e feliz, sobre o verde
## #00B140). O pedido é de TRÊS IMAGENS SEPARADAS e grandes (o retrato ocupa o
## palco do encontro); se o Gemini juntar as três numa folha, também serve.
## Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_lideres_gemini.gd -- <brava.png> <neutra.png> <feliz.png> <líder>
##   godot_console.cmd --headless --path . --script tools/art/import_lideres_gemini.gd -- <folha.png> <líder>
##   godot_console.cmd --headless --path . --script tools/art/import_lideres_gemini.gd -- <imagem> <líder> <brava|neutra|feliz>
## (a última forma importa uma expressão só: desde 30/10/2026 o pedido é o
## neutro primeiro e depois as edições do rosto, uma de cada vez).
## <líder>: gregos, romanos, egipcios, fenicios, americanos ou ingleses
## (Nation.DATA "leader").
## Passos:
##   1. tira o fundo verde (e o verde que vaza nas bordas);
##   2. na folha, acha as 3 figuras pelas colunas com desenho (sem achar 3,
##      divide a folha em três partes iguais), avisa se alguma encosta na
##      borda (cortada) e recorta as três com o mesmo tamanho e enquadramento;
##   3. recorta cada uma no tamanho da figura, reduz só se passar de
##      MAX_HEIGHT de altura (a resolução alta é o que importa aqui) e grava
##      em assets/leaders/<líder>_<brava|neutra|feliz>.png (Nation.portrait).
## Os originais ficam em tools/art/gemini/originais/lideres/.

const LEADERS := "res://assets/leaders/"
const SHEETS := "res://tools/art/gemini/originais/lideres/"
const MOODS := ["brava", "neutra", "feliz"]
const MAX_HEIGHT := 1600
## Verde do fundo: quanto o verde passa do maior entre o vermelho e o azul.
const KEY_FULL := 0.22
const KEY_EDGE := 0.06
const DIVIDER_MARGIN := 4
## Rosto que vem do bravo e do feliz (o resto é o neutro), em frações da
## altura da figura: a cabeça nas FACE_ROWS de cima (para alinhar), o centro
## do rosto em FACE_CENTER e a meia-altura FACE_HEIGHT; a meia-largura é
## FACE_WIDTH da largura da cabeça nessa altura; a borda suave é a fração
## FACE_FEATHER de fora da elipse.
const FACE_ROWS := 0.34
const FACE_CENTER := 0.17
const FACE_HEIGHT := 0.14
const FACE_WIDTH := 0.8
const FACE_FEATHER := 0.35
## Deslocamento máximo procurado entre as figuras dos painéis (px).
const ALIGN_REACH := 18


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 4 or (args.size() == 3 and not MOODS.has(args[2])):
		print("uso: -- <brava.png> <neutra.png> <feliz.png> <líder>   ou   -- <folha.png> <líder>   ou   -- <imagem> <líder> <brava|neutra|feliz>")
		quit(1)
		return
	var leader: String = args[1] if args.size() == 3 else args[-1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHEETS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEADERS))
	if args.size() == 3:
		# Uma expressão só
		var single := _open(args[0])
		if single == null:
			quit(1)
			return
		single.save_png(ProjectSettings.globalize_path("%s%s_%s_original.png" % [SHEETS, leader, args[2]]))
		_remove_green(single)
		var box := _bounding_box(single, Vector2i(0, single.get_width() - 1))
		if box.position.x <= 0 or box.end.x >= single.get_width() or box.position.y <= 0:
			print("  aviso: o retrato encosta na borda (pode estar cortado)")
		_save(single, box, leader, args[2])
	elif args.size() == 4:
		# Três imagens separadas, na ordem brava, neutra, feliz
		for i in 3:
			var image := _open(args[i])
			if image == null:
				quit(1)
				return
			image.save_png(ProjectSettings.globalize_path("%s%s_%s_original.png" % [SHEETS, leader, MOODS[i]]))
			_remove_green(image)
			var whole := Vector2i(0, image.get_width() - 1)
			_save(image, _bounding_box(image, whole), leader, MOODS[i])
	else:
		var sheet := _open(args[0])
		if sheet == null:
			quit(1)
			return
		sheet.save_png(ProjectSettings.globalize_path(SHEETS + leader + "_folha.png"))
		_remove_green(sheet)
		_remove_dividers(sheet)
		var columns := _figure_columns(sheet)
		var boxes: Array[Rect2i] = []
		for i in 3:
			boxes.append(_bounding_box(sheet, columns[i]))
			if boxes[i].position.x <= columns[i].x or boxes[i].end.x > columns[i].y or boxes[i].position.y <= 0:
				print("  aviso: o retrato %s encosta na borda (pode estar cortado; peça de novo com mais margem)" % MOODS[i])
		# Os três com o MESMO tamanho e enquadramento (as mesmas linhas, a mesma
		# largura em volta do centro de cada figura): ao mudar de expressão no
		# encontro, só o rosto muda, a imagem não pula.
		var top: int = boxes.map(func(b: Rect2i) -> int: return b.position.y).min()
		var bottom: int = boxes.map(func(b: Rect2i) -> int: return b.end.y).max()
		var width: int = boxes.map(func(b: Rect2i) -> int: return b.size.x).max()
		var portraits: Array[Image] = []
		for i in 3:
			var x := boxes[i].get_center().x - width / 2
			portraits.append(_crop(sheet, Rect2i(x, top, width, bottom - top)))
		# O corpo NÃO MEXE UM PIXEL (pedido do usuário, 30/10/2026): o bravo e o
		# feliz são o neutro com só o rosto trocado
		for i in [0, 2]:
			portraits[i] = _transplant_face(portraits[1], portraits[i], MOODS[i])
		for i in 3:
			_write(portraits[i], leader, MOODS[i])
	quit()


func _open(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		print("não consegui abrir ", path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## Recorta a figura em [param box] e grava o retrato (reduzido só acima de MAX_HEIGHT).
func _save(image: Image, box: Rect2i, leader: String, mood: String) -> void:
	if box.size.x <= 0:
		print("ERRO: retrato %s vazio" % mood)
		return
	_write(_crop(image, box), leader, mood)


## O retrato em [param box] (fora da imagem fica transparente: o recorte
## mantém o tamanho pedido), reduzido só acima de MAX_HEIGHT.
func _crop(image: Image, box: Rect2i) -> Image:
	var area := box.grow(4)
	var portrait := Image.create(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
	var inside := area.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	portrait.blit_rect(image, inside, inside.position - area.position)
	if portrait.get_height() > MAX_HEIGHT:
		var width := roundi(portrait.get_width() * float(MAX_HEIGHT) / portrait.get_height())
		portrait.resize(width, MAX_HEIGHT, Image.INTERPOLATE_LANCZOS)
	return portrait


## Rosto de [param expression] sobre o retrato [param base] (o neutro): o
## resultado é o neutro pixel por pixel, menos o rosto. A cabeça da expressão
## é alinhada à do neutro (_align: o Gemini desloca a figura uns pixels de um
## painel para o outro) e entra por uma elipse em volta do rosto (FACE_*), com
## a borda suave (FACE_FEATHER); fora dela, o neutro.
func _transplant_face(base: Image, expression: Image, mood: String) -> Image:
	var figure := _bounding_box(base, Vector2i(0, base.get_width() - 1))
	var head_rows := Rect2i(figure.position.x, figure.position.y, figure.size.x, roundi(figure.size.y * FACE_ROWS))
	# Centro do rosto: o meio da cabeça na altura dos olhos
	var center_y := figure.position.y + figure.size.y * FACE_CENTER
	var left := -1
	var right := -1
	for x in base.get_width():
		if base.get_pixel(x, roundi(center_y)).a > 0.5:
			if left < 0:
				left = x
			right = x
	var center := Vector2((left + right) / 2.0, center_y)
	var radius := Vector2((right - left) / 2.0 * FACE_WIDTH, figure.size.y * FACE_HEIGHT)
	var offset := _align(base, expression, head_rows)
	var result := base.duplicate() as Image
	for y in range(maxi(roundi(center.y - radius.y), 0), mini(roundi(center.y + radius.y) + 1, base.get_height())):
		for x in range(maxi(roundi(center.x - radius.x), 0), mini(roundi(center.x + radius.x) + 1, base.get_width())):
			var d := Vector2((x - center.x) / radius.x, (y - center.y) / radius.y).length()
			if d >= 1.0:
				continue
			var source := Vector2i(x, y) + offset
			if source.x < 0 or source.y < 0 or source.x >= expression.get_width() or source.y >= expression.get_height():
				continue
			var weight := clampf((1.0 - d) / FACE_FEATHER, 0.0, 1.0)
			result.set_pixel(x, y, base.get_pixel(x, y).lerp(expression.get_pixel(source.x, source.y), weight))
	print("  %s: rosto sobre o neutro (deslocamento %s); o resto é o neutro" % [mood, offset])
	return result


## Deslocamento de [param moved] em relação a [param base] que melhor encaixa
## a região [param area] (menor diferença de cor; busca grossa e depois fina).
func _align(base: Image, moved: Image, area: Rect2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_cost := INF
	for step: int in [3, 1]:
		var around := best
		var reach := ALIGN_REACH if step == 3 else 2
		for dy in range(-reach, reach + 1, step):
			for dx in range(-reach, reach + 1, step):
				var offset := around + Vector2i(dx, dy)
				var cost := _difference(base, moved, area, offset)
				if cost < best_cost:
					best_cost = cost
					best = offset
	return best


func _difference(base: Image, moved: Image, area: Rect2i, offset: Vector2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 4):
		for x in range(area.position.x, area.end.x, 4):
			var other := Vector2i(x, y) + offset
			if other.x < 0 or other.y < 0 or other.x >= moved.get_width() or other.y >= moved.get_height():
				total += 1.0
				count += 1
				continue
			var a := base.get_pixel(x, y)
			var b := moved.get_pixel(other.x, other.y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			count += 1
	return total / maxi(count, 1)


## Grava o retrato em assets/leaders/<líder>_<expressão>.png.
func _write(portrait: Image, leader: String, mood: String) -> void:
	var path := "%s%s_%s.png" % [LEADERS, leader, mood]
	portrait.save_png(ProjectSettings.globalize_path(path))
	print("ok: %s (%s)" % [path, portrait.get_size()])
	if portrait.get_height() < 700:
		print("  aviso: só %d px de altura; o palco do encontro pede mais (peça a imagem maior)" % portrait.get_height())


## Fundo verde transparente; na borda (verde misturado), o verde some e o
## pixel fica meio transparente.
func _remove_green(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			var key := p.g - maxf(p.r, p.b)
			if key >= KEY_FULL:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif key > KEY_EDGE:
				var alpha := 1.0 - (key - KEY_EDGE) / (KEY_FULL - KEY_EDGE)
				image.set_pixel(x, y, Color(p.r, maxf(p.r, p.b), p.b, alpha * p.a))


## Linhas escuras entre os painéis (o Gemini às vezes desenha, mesmo pedindo
## que não; 30/10/2026): colunas quase inteiras opacas e escuras ficam
## transparentes, com DIVIDER_MARGIN colunas de cada lado (a borda borrada
## da linha).
func _remove_dividers(image: Image) -> void:
	var lines: Array[int] = []
	for x in image.get_width():
		var dark := 0
		for y in image.get_height():
			var p := image.get_pixel(x, y)
			if p.a > 0.5 and p.get_luminance() < 0.25:
				dark += 1
		if dark > image.get_height() * 0.9:
			lines.append(x)
	for line in lines:
		for x in range(maxi(line - DIVIDER_MARGIN, 0), mini(line + DIVIDER_MARGIN + 1, image.get_width())):
			for y in image.get_height():
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	if not lines.is_empty():
		print("  linhas entre os painéis apagadas (colunas %s)" % str(lines))


## Faixas de colunas [início, fim] das 3 figuras: as 3 maiores faixas de
## colunas com desenho; sem 3, a folha em três partes iguais.
func _figure_columns(image: Image) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var start := -1
	for x in image.get_width() + 1:
		var used := false
		if x < image.get_width():
			for y in range(0, image.get_height(), 3):
				if image.get_pixel(x, y).a > 0.5:
					used = true
					break
		if used and start < 0:
			start = x
		elif not used and start >= 0:
			runs.append(Vector2i(start, x - 1))
			start = -1
	runs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y - a.x > b.y - b.x)
	if runs.size() >= 3 and runs[2].y - runs[2].x > image.get_width() / 12:
		var three := runs.slice(0, 3)
		three.sort()
		var result: Array[Vector2i] = []
		result.assign(three)
		return result
	var third := image.get_width() / 3
	print("aviso: não achei 3 figuras separadas; dividindo a folha em três")
	return [Vector2i(0, third - 1), Vector2i(third, 2 * third - 1), Vector2i(2 * third, image.get_width() - 1)]


## Retângulo do desenho dentro das colunas [param columns].
func _bounding_box(image: Image, columns: Vector2i) -> Rect2i:
	var box := Rect2i()
	var first := true
	for y in image.get_height():
		for x in range(columns.x, columns.y + 1):
			if image.get_pixel(x, y).a > 0.3:
				if first:
					box = Rect2i(x, y, 1, 1)
					first = false
				else:
					box = box.expand(Vector2i(x, y))
	if not first:
		box.size += Vector2i.ONE
	return box
