extends SceneTree

## Importa a folha de TERRENOS do Gemini (tools/art/gemini/pedidos/07_terrenos:
## quadrados separados por faixas verdes). Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_terrenos_gemini.gd -- <folha.png> <nome1|-> <nome2|-> ...
## Os quadrados são achados pelas faixas verdes (colunas e linhas só de
## fundo) e lidos por linhas, da esquerda para a direita. Os nomes são os de
## assets/tiles/ (pradaria, cerrado, floresta, colinas, montanhas, agua); "-"
## pula. Ex. (26/10/2026: colinas e montanhas ficaram de fora, porque vieram
## com relevo pintado e o shader do mapa já desenha o relevo):
##   ... -- terrenos.png pradaria cerrado floresta - - agua
## Cada quadrado perde uma margem (a borda misturada com o verde), vira um
## quadrado, fica SEM EMENDA (mistura com uma cópia deslocada pela metade, que
## assume perto das bordas) e é gravado com SIZE x SIZE (o shader lê por
## coordenada: o tamanho não precisa ser o da casa). Guarda a folha em
## tools/art/gemini/terrenos_folha.png e uma prévia de cada textura repetida
## 3x3 em tools/art/gemini/terrenos_previa.png.

const TILES := "res://assets/tiles/"
const GEMINI := "res://tools/art/gemini/"
const SIZE := 160
## Margem cortada de cada lado do quadrado (pixels da folha).
const INSET := 6
## Largura da faixa de mistura nas bordas (fração da metade do quadrado).
const BLEND := 0.45


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("uso: -- <folha.png> <nome1|-> <nome2|-> ...")
		quit(1)
		return
	var sheet := Image.load_from_file(args[0])
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + "terrenos_folha.png"))
	var bg := sheet.get_pixel(1, 1)
	var columns := _runs(sheet, bg, true)
	var rows := _runs(sheet, bg, false)
	print("colunas %s, linhas %s" % [columns, rows])
	var names: Array = args.slice(1)
	if columns.size() * rows.size() != names.size():
		print("ERRO: %d quadrados para %d nomes" % [columns.size() * rows.size(), names.size()])
		quit(1)
		return
	var previews: Array[Image] = []
	var i := 0
	for row: Vector2i in rows:
		for column: Vector2i in columns:
			var name: String = names[i]
			i += 1
			if name == "-":
				continue
			var cell := Rect2i(column.x + INSET, row.x + INSET, column.y - column.x - INSET * 2, row.y - row.x - INSET * 2)
			var side := mini(cell.size.x, cell.size.y)
			cell = Rect2i(cell.position + (cell.size - Vector2i(side, side)) / 2, Vector2i(side, side))
			var tile := _seamless(sheet.get_region(cell))
			tile.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			tile.save_png(ProjectSettings.globalize_path(TILES + name + ".png"))
			previews.append(tile)
			print("ok: %s (%s -> %dx%d)" % [name, cell, SIZE, SIZE])
	_preview(previews)
	quit()


## Faixas de colunas (ou linhas) que têm algum pixel que não é o fundo:
## [Vector2i(início, fim)], ignorando faixas finas (sujeira).
func _runs(img: Image, bg: Color, vertical: bool) -> Array[Vector2i]:
	var length := img.get_width() if vertical else img.get_height()
	var across := img.get_height() if vertical else img.get_width()
	var runs: Array[Vector2i] = []
	var start := -1
	for a in length + 1:
		var used := false
		if a < length:
			var count := 0
			for b in range(0, across, 2):
				var p := img.get_pixel(a, b) if vertical else img.get_pixel(b, a)
				if absf(p.r - bg.r) + absf(p.g - bg.g) + absf(p.b - bg.b) > 0.25:
					count += 1
			used = count > across / 8 # mais de 1/4 da linha (amostrada de 2 em 2) não é fundo
		if used and start < 0:
			start = a
		elif not used and start >= 0:
			if a - start > length / 10:
				runs.append(Vector2i(start, a))
			start = -1
	return runs


## Sem emenda: o meio fica o original; perto das bordas entra a cópia
## deslocada pela metade (cujas bordas vêm do meio do original, então ela
## continua sozinha de um lado para o outro).
func _seamless(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := absf(x - (w - 1) / 2.0) / (w / 2.0)
			var dy := absf(y - (h - 1) / 2.0) / (h / 2.0)
			var keep := 1.0 - smoothstep(1.0 - BLEND, 1.0, maxf(dx, dy))
			var shifted := img.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			var p := img.get_pixel(x, y).lerp(shifted, 1.0 - keep)
			p.a = 1.0
			out.set_pixel(x, y, p)
	return out


func _preview(tiles: Array[Image]) -> void:
	var sheet := Image.create(SIZE * 3 * tiles.size() + 10 * (tiles.size() - 1), SIZE * 3, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(46, 50, 56))
	for t in tiles.size():
		for y in 3:
			for x in 3:
				sheet.blit_rect(tiles[t], Rect2i(0, 0, SIZE, SIZE), Vector2i(t * (SIZE * 3 + 10) + x * SIZE, y * SIZE))
	sheet.save_png(ProjectSettings.globalize_path(GEMINI + "terrenos_previa.png"))
