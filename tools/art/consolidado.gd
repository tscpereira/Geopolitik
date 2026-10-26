extends SceneTree

## Consolidado da arte das unidades. Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/consolidado.gd
## Grava em tools/art/chatgpt/:
##   consolidado_unidades.png: todas as unidades como estão no jogo (sprite
##     80x80 ampliado 3x), em azul e em vermelho, sobre a pradaria;
##   referencia_unidades.png: os desenhos grandes do ChatGPT (unidades/, da
##     folha importada por import_folha_unidades.gd), em azul do time
##     (#1E50FF), na mesma escala relativa do jogo. É a imagem para anexar
##     ao pedir uma unidade nova (PROMPTS-CHATGPT.txt, "UNIDADE NOVA").

const UNITS_DIR := "res://assets/sprites/units/"
const GRANDES := "res://tools/art/chatgpt/unidades/"
const OUT := "res://tools/art/chatgpt/"
## Ordem do consolidado (a mesma da lista de unidades do jogo).
const UNITS := ["trabalhador", "colono", "guerreiro", "lanceiro", "guerreiro_espada", "arqueiro", "cavalaria_leve", "bigas", "catapulta", "gale"]
const TEAM_BLUE := Color8(30, 80, 255)
const TEAM_RED := Color8(220, 40, 40)
const CELL := 240
## Referência: os desenhos no tamanho da folha (a escala já é a mesma para
## todos), cada um numa caixa BOX, pés na mesma linha.
const BOX := Vector2(250, 245)
const MARGIN := 24


func _initialize() -> void:
	_consolidado()
	_referencia()
	quit()


func _consolidado() -> void:
	var sheet := Image.create(CELL * UNITS.size(), CELL * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(96, 122, 60))
	for i in UNITS.size():
		var row := 0
		for color in [TEAM_BLUE, TEAM_RED]:
			var img := _tinted(UNITS_DIR + UNITS[i], color)
			img.resize(CELL, CELL, Image.INTERPOLATE_BILINEAR)
			sheet.blend_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, row * CELL))
			row += 1
	sheet.save_png(ProjectSettings.globalize_path(OUT + "consolidado_unidades.png"))


func _referencia() -> void:
	var w := int(BOX.x) * UNITS.size() + MARGIN * (UNITS.size() + 1)
	var h := int(BOX.y) + MARGIN * 2
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(240, 238, 232))
	var x := MARGIN
	for unit in UNITS:
		var img := _tinted(GRANDES + unit, TEAM_BLUE)
		var pos := Vector2i(x + (int(BOX.x) - img.get_width()) / 2, MARGIN + int(BOX.y) - img.get_height())
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
		x += int(BOX.x) + MARGIN
	sheet.save_png(ProjectSettings.globalize_path(OUT + "referencia_unidades.png"))


## O PNG tem a parte do time em preto e o _time.png diz quanto da cor entra.
func _tinted(path: String, color: Color) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path + ".png"))
	img.convert(Image.FORMAT_RGBA8)
	var mask_path := ProjectSettings.globalize_path(path + "_time.png")
	if not FileAccess.file_exists(mask_path):
		return img
	var mask := Image.load_from_file(mask_path)
	mask.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var m := mask.get_pixel(x, y).r
			var p := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(p.r + color.r * m, 1), minf(p.g + color.g * m, 1), minf(p.b + color.b * m, 1), p.a))
	return img
