extends SceneTree

## Folha com TODOS os desenhos do jogo, com o nome de cada um, para mandar a
## uma ferramenta de imagem (Gemini) refazer tudo no mesmo padrão
## (tools/art/PROMPTS-GEMINI.txt). Rode COM janela (os títulos são desenhados
## pelo Godot):
##   godot_console.cmd --path . --script tools/art/folha_assets.gd
## Grava em tools/art/gemini/previas/:
##   assets_todos.png        tudo numa imagem só;
##   assets_unidades.png     as 10 unidades;
##   assets_cidades.png      as 15 cidades (classe x capital x muralha) e as
##                           8 ruínas;
##   assets_terreno.png      terrenos, melhorias e o ícone do ferro;
##   assets_tecnologias.png  as 16 ilustrações das tecnologias.
## As partes na cor do jogador (máscaras _time.png) aparecem no azul do time
## (#1E50FF), o padrão dos pedidos.

const OUT := "res://tools/art/gemini/previas/"
const TEAM_BLUE := Color8(30, 80, 255)
const BACK := Color8(46, 50, 56)
const CARD := Color8(70, 76, 84)
const TEXT := Color8(235, 235, 235)
const MUTED := Color8(170, 175, 182)

const UNITS := ["trabalhador", "colono", "guerreiro", "lanceiro", "guerreiro_espada", "arqueiro", "cavalaria_leve",
	"bigas", "catapulta", "gale"]
const CLASSES := ["povoado", "vila", "cidade", "metropole"]
const TILES := ["pradaria", "cerrado", "floresta", "colinas", "montanhas", "agua"]
const IMPROVEMENTS := ["fazenda_obra", "fazenda", "fazenda_destruida", "madeireira", "madeireira_destruida", "mina", "mina_destruida"]
const TECHS := ["alfabeto", "construcao", "misticismo", "bronze", "montaria", "guerra_a_distancia", "navegacao", "literatura",
	"matematica", "trabalho_em_ferro", "moeda", "guerra_de_movimento", "direito", "engenharia_civil", "republica", "pao_e_circo"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run()


func _run() -> void:
	var units := _section("UNIDADES (80x80 no jogo; vista 3/4 virada para a direita; azul = cor do jogador)",
			UNITS.map(func(n: String) -> Array: return [n, _tinted("res://assets/sprites/units/" + n)]), 2.0, 10)
	var cities := []
	for rank: String in CLASSES:
		for variant: String in ["", "_capital", "_muralha", "_capital_muralha"]:
			var file: String = rank + variant
			if rank == "povoado" and variant.begins_with("_capital"):
				file = rank + variant.replace("_capital", "") # o povoado não tem palácio
				cities.append([rank + variant + "  (= " + file + ")", _tinted("res://assets/sprites/cities/" + file)])
			else:
				cities.append([file, _tinted("res://assets/sprites/cities/" + file)])
	var city_section := _section("CIDADES (128x128; colunas: normal | capital (palácio) | com muralha | capital com muralha)",
			cities, 1.5, 4)
	var ruins := []
	for rank: String in CLASSES:
		for variant: String in ["_ruinas", "_muralha_ruinas"]:
			ruins.append([rank + variant, _image("res://assets/sprites/cities/" + rank + variant)])
	var ruin_section := _section("RUÍNAS DE CIDADES DESTRUÍDAS (128x128)", ruins, 1.0, 8)
	var tiles := _section("TERRENOS (80x80, vistos de cima, repetidos lado a lado; o jogo faz as transições)",
			TILES.map(func(n: String) -> Array: return [n, _image("res://assets/tiles/" + n)]), 2.0, 6)
	var improvements := _section("MELHORIAS DE TERRENO (80x80, vistas de cima, sobre o terreno) E RECURSO",
			IMPROVEMENTS.map(func(n: String) -> Array: return [n, _image("res://assets/sprites/improvements/" + n)])
				+ [["ferro (ícone 64x64)", _image("res://assets/sprites/resources/ferro")]], 2.0, 8)
	var techs := _section("ILUSTRAÇÕES DAS TECNOLOGIAS (janela de tecnologia descoberta)",
			TECHS.map(func(n: String) -> Array: return [n, _thumb("res://assets/tech/" + n, Vector2i(224, 140))]), 1.0, 8)
	await _save([units, city_section, ruin_section, tiles, improvements, techs], "assets_todos.png", "PROJETOGAME - TODOS OS DESENHOS")
	await _save([units], "assets_unidades.png", "PROJETOGAME - UNIDADES")
	await _save([city_section, ruin_section], "assets_cidades.png", "PROJETOGAME - CIDADES")
	await _save([tiles, improvements], "assets_terreno.png", "PROJETOGAME - TERRENO E MELHORIAS")
	await _save([techs], "assets_tecnologias.png", "PROJETOGAME - TECNOLOGIAS")
	quit()


## Monta as seções numa SubViewport do tamanho do conteúdo e grava o PNG.
func _save(sections: Array, file_name: String, title: String) -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = BACK
	viewport.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	viewport.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	margin.add_child(box)
	box.add_child(_label(title, 30, TEXT))
	for section: Control in sections:
		box.add_child(section.duplicate())
	for i in 3:
		await process_frame
	var size := margin.get_combined_minimum_size()
	viewport.size = Vector2i(ceili(size.x), ceili(size.y))
	background.size = size
	margin.size = size
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file_name))
	print("gravado %s (%dx%d)" % [file_name, viewport.size.x, viewport.size.y])
	viewport.queue_free()


## Título e uma grade de cartões (desenho + nome).
func _section(title: String, items: Array, zoom: float, columns: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label(title, 20, TEXT))
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for item: Array in items:
		var image: Image = item[1]
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = CARD
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", style)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		card.add_child(inner)
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(image)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(image.get_size()) * zoom
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		inner.add_child(picture)
		var name_label := _label(item[0], 13, MUTED)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.custom_minimum_size.x = image.get_width() * zoom
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(name_label)
		grid.add_child(card)
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path + ".png"))
	image.convert(Image.FORMAT_RGBA8)
	return image


## Desenho com a cor do time: base + máscara (_time.png) x azul, como no jogo
## (Unit.team_texture).
func _tinted(path: String) -> Image:
	var image := _image(path)
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


## Ilustração reduzida para caber em [param box], sem distorcer.
func _thumb(path: String, box: Vector2i) -> Image:
	var image := _image(path)
	var scale := minf(float(box.x) / image.get_width(), float(box.y) / image.get_height())
	image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	return image
