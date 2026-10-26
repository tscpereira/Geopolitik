extends SceneTree

## Folha da EVOLUÇÃO das cidades: os níveis lado a lado (colunas: povoado,
## vila, cidade, metrópole) e as versões em linhas (normal, capital com o
## palácio, com muralha, capital com muralha), na escala real do jogo (todos
## os desenhos são 128x128 e aparecem do mesmo tamanho no mapa), ampliados 2x
## sobre a pradaria. Marca qual desenho já é do Gemini (pela data do arquivo
## não dá: a lista GEMINI abaixo é atualizada a cada importação).
## Rode COM janela:
##   godot_console.cmd --path . --script tools/art/evolucao_cidades.gd
## Grava tools/art/gemini/evolucao_cidades.png.

const OUT := "res://tools/art/gemini/evolucao_cidades.png"
const CITIES := "res://assets/sprites/cities/"
const TEAM_BLUE := Color8(30, 80, 255)
const ZOOM := 2.0
const CLASSES := [["povoado", "Povoado (1-5)"], ["vila", "Vila (6-15)"], ["cidade", "Cidade (16-30)"], ["metropole", "Metrópole (31+)"]]
const VERSIONS := [["", "Normal"], ["_capital", "Capital (palácio)"], ["_muralha", "Com muralha"], ["_capital_muralha", "Capital com muralha"]]
## Desenhos que já vieram do Gemini (o resto ainda é o antigo).
const GEMINI := ["vila", "vila_capital", "vila_muralha", "vila_capital_muralha"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color8(46, 50, 56)
	viewport.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	viewport.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(_label("Evolução das cidades (escala real do jogo, ampliada 2x)  -  verde = já é do Gemini, cinza = desenho antigo", 20))
	var grid := GridContainer.new()
	grid.columns = CLASSES.size() + 1
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	grid.add_child(_label("", 16))
	for k: Array in CLASSES:
		var head := _label(k[1], 18)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(head)
	var grass := _load("res://assets/tiles/pradaria.png")
	for v: Array in VERSIONS:
		var row_label := _label(v[1], 16)
		row_label.custom_minimum_size.x = 170
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(row_label)
		for k: Array in CLASSES:
			var name: String = k[0] + v[0]
			var file := name
			var note := ""
			if k[0] == "povoado" and v[0].begins_with("_capital"):
				file = k[0] + v[0].replace("_capital", "") # o povoado não tem palácio
				note = " (= " + file + ")"
			grid.add_child(_cell(grass, file, name + note, GEMINI.has(file)))
	for i in 3:
		await process_frame
	var size := margin.get_combined_minimum_size()
	viewport.size = Vector2i(ceili(size.x), ceili(size.y))
	background.size = size
	margin.size = size
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	print("gravado %s (%dx%d)" % [OUT, viewport.size.x, viewport.size.y])
	quit()


## Um desenho sobre a pradaria (como no mapa), com o nome e a origem embaixo.
func _cell(grass: Image, file: String, title: String, gemini: bool) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(70, 76, 84)
	style.border_color = Color8(60, 200, 90) if gemini else Color8(110, 110, 115)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)
	var inner := VBoxContainer.new()
	card.add_child(inner)
	var picture := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var tile := grass.duplicate()
	tile.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	for y in 2:
		for x in 2:
			picture.blit_rect(tile, Rect2i(0, 0, 64, 64), Vector2i(x, y) * 64)
	picture.blend_rect(_tinted(CITIES + file), Rect2i(0, 0, 128, 128), Vector2i.ZERO)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(picture)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.custom_minimum_size = Vector2(128, 128) * ZOOM
	inner.add_child(rect)
	var caption := _label("%s  [%s]" % [title, "Gemini" if gemini else "antigo"], 13)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size.x = 128 * ZOOM
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(caption)
	return card


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(235, 235, 235))
	return label


func _load(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	image.convert(Image.FORMAT_RGBA8)
	return image


func _tinted(path: String) -> Image:
	var image := _load(path + ".png")
	var mask_path := ProjectSettings.globalize_path(path + "_time.png")
	if not FileAccess.file_exists(mask_path):
		return image
	var mask := Image.load_from_file(mask_path)
	mask.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var m := mask.get_pixel(x, y).r
			if m > 0.0:
				var p := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(minf(p.r + TEAM_BLUE.r * m, 1.0), minf(p.g + TEAM_BLUE.g * m, 1.0),
						minf(p.b + TEAM_BLUE.b * m, 1.0), p.a))
	return image
