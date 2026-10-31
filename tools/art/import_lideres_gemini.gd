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
## Os originais ficam em tools/art/gemini/lideres/.

const LEADERS := "res://assets/leaders/"
const SHEETS := "res://tools/art/gemini/lideres/"
const MOODS := ["brava", "neutra", "feliz"]
const MAX_HEIGHT := 1600
## Verde do fundo: quanto o verde passa do maior entre o vermelho e o azul.
const KEY_FULL := 0.22
const KEY_EDGE := 0.06


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
		for i in 3:
			var x := boxes[i].get_center().x - width / 2
			_save(sheet, Rect2i(x, top, width, bottom - top), leader, MOODS[i])
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
	# Fora da imagem fica transparente (o recorte mantém o tamanho pedido)
	var area := box.grow(4)
	var portrait := Image.create(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
	var inside := area.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	portrait.blit_rect(image, inside, inside.position - area.position)
	if portrait.get_height() > MAX_HEIGHT:
		var width := roundi(portrait.get_width() * float(MAX_HEIGHT) / portrait.get_height())
		portrait.resize(width, MAX_HEIGHT, Image.INTERPOLATE_LANCZOS)
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
