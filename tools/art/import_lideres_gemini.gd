extends SceneTree

## Importa a folha de um LÍDER feita pelo Gemini (pedidos 13 a 18,
## lider_<líder>: 3 retratos lado a lado, da esquerda para a direita brava,
## neutra e feliz, sobre o verde #00B140). Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_lideres_gemini.gd -- <folha.png> <líder>
## <líder>: gregos, romanos, egipcios, fenicios, americanos ou ingleses
## (Nation.DATA "leader").
## Passos:
##   1. tira o fundo verde (e o verde que vaza nas bordas);
##   2. acha as 3 figuras pelas colunas com desenho (sem achar 3, divide a
##      folha em três partes iguais);
##   3. recorta cada uma no tamanho da figura, reduz para no máximo MAX_HEIGHT
##      de altura (o original grande fica guardado) e grava em
##      assets/leaders/<líder>_<brava|neutra|feliz>.png (Nation.portrait).
## A folha original fica em tools/art/gemini/lideres/<líder>_folha.png.

const LEADERS := "res://assets/leaders/"
const SHEETS := "res://tools/art/gemini/lideres/"
const MOODS := ["brava", "neutra", "feliz"]
const MAX_HEIGHT := 900
## Verde do fundo: quanto o verde passa do maior entre o vermelho e o azul.
const KEY_FULL := 0.22
const KEY_EDGE := 0.06


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("uso: -- <folha.png> <líder>")
		quit(1)
		return
	var sheet := Image.load_from_file(args[0])
	if sheet == null:
		print("não consegui abrir ", args[0])
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHEETS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEADERS))
	sheet.save_png(ProjectSettings.globalize_path(SHEETS + args[1] + "_folha.png"))
	_remove_green(sheet)
	var columns := _figure_columns(sheet)
	for i in 3:
		var box := _bounding_box(sheet, columns[i])
		if box.size.x <= 0:
			print("ERRO: figura %d vazia" % (i + 1))
			continue
		var portrait := sheet.get_region(box.grow(4).intersection(Rect2i(Vector2i.ZERO, sheet.get_size())))
		if portrait.get_height() > MAX_HEIGHT:
			var width := roundi(portrait.get_width() * float(MAX_HEIGHT) / portrait.get_height())
			portrait.resize(width, MAX_HEIGHT, Image.INTERPOLATE_LANCZOS)
		var path := "%s%s_%s.png" % [LEADERS, args[1], MOODS[i]]
		portrait.save_png(ProjectSettings.globalize_path(path))
		print("ok: %s (%s)" % [path, portrait.get_size()])
	quit()


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
