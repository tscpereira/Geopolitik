extends SceneTree

## Um PEDIDO por TEMA para o Gemini (tudo de uma vez ele não entendeu; um por
## desenho ficou granular demais). Rode COM janela (os títulos são desenhados
## pelo Godot):
##   godot_console.cmd --path . --script tools/art/pedidos_gemini.gd
## Grava tools/art/gemini/pedidos/<NN>_<tema>/ com:
##   referencia.png  à esquerda a Galé (o ESTILO); à direita os desenhos atuais
##                   do tema (o CONTEÚDO), na MESMA grade e ordem que o
##                   prompt pede, numerados;
##   prompt.txt      o prompt inteiro, com o estilo embutido.
## E tools/art/gemini/pedidos/LEIA-ME.txt com o passo a passo.

const OUT := "res://tools/art/gemini/pedidos/"
const STYLE_IMAGE := "res://tools/art/chatgpt/gale_avulsa.png"
const TEAM_BLUE := Color8(30, 80, 255)
const BACK := Color8(46, 50, 56)
const CARD := Color8(70, 76, 84)

const INTRO := """I am remaking the art of a 2D turn-based strategy game set in ancient Greece. The attached image has two parts:
- LEFT, "ESTILO": a galley. It is the STYLE REFERENCE: paint everything in exactly this style.
- RIGHT, "ATUAL": the current, low-quality versions of the items I need, numbered, in the same grid I want back. Use them only to know WHAT to draw (content and composition), not how they look.

Create ONE image: a sprite sheet with %s."""

const STYLE := """STYLE (copy it from the galley):
- Detailed painted digital illustration with realistic proportions: soft painted shading, visible wood grain and texture, warm earthy palette (warm brown wood, off-white linen and plaster, terracotta roof tiles, bronze, olive greens). Not cartoon, not chibi, not pixel art, no thick black outlines, no flat colors, not a photo.
- Strong, clean silhouettes that stay readable when shrunk to small game sprites: few big shapes, no thin clutter.
- Soft daylight from the TOP-LEFT. All items in the sheet share the same light, scale and camera."""

const GRID := """SHEET LAYOUT:
- A grid of %d columns x %d rows, evenly spaced, each item centered in its own cell, never touching or overlapping its neighbours, never cropped.
- Order, left to right, top to bottom (the numbers match the right side of the attached image):
%s
- No numbers, labels or text in the image."""

const TEAM := """TEAM COLOR:
- The player's color is ONE vivid royal blue (#1E50FF), used ONLY on: %s. Use lighter and darker shades of that blue there, nowhere else. No other blue, cyan, teal or purple anywhere: no blue sky, no water, no blue shadows."""

const NO_TEAM := "TEAM COLOR: none in this sheet (no blue at all)."

const GREEN := """BACKGROUND:
- One flat, solid chroma-key green (#00B140) filling the whole background and the space between the cells: no gradient, no texture, no vignette, no cast shadow on the background, no ground, no frame, no text, no signature."""

var _style: Image


func _initialize() -> void:
	_style = _load(STYLE_IMAGE)
	_run()


func _run() -> void:
	# Apaga os pedidos antigos (um por desenho)
	var dir := DirAccess.open(ProjectSettings.globalize_path("res://tools/art/gemini/"))
	if dir and dir.dir_exists("pedidos"):
		_remove_tree(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for theme: Dictionary in _themes():
		n += 1
		var folder := "%s%02d_%s/" % [OUT, n, theme["name"]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var file := FileAccess.open(ProjectSettings.globalize_path(folder + "prompt.txt"), FileAccess.WRITE)
		file.store_string(_prompt(theme) + "\n")
		file.close()
		await _reference(theme, folder + "referencia.png")
	_readme()
	print("ok: %d temas" % n)
	quit()


func _prompt(theme: Dictionary) -> String:
	var lines: Array[String] = []
	var number := 0
	var row := 0
	var items: Array = theme["items"]
	for i in items.size():
		if i % theme["columns"] == 0:
			row += 1
			lines.append("  Row %d%s:" % [row, " (" + theme["rows"][row - 1] + ")" if theme.has("rows") else ""])
		var item: Array = items[i]
		if item[0] == "":
			lines.append("    - (empty cell: leave it plain green)")
		else:
			number += 1
			lines.append("    %d. %s" % [number, item[2]])
	var parts: Array[String] = [INTRO % theme["what"], STYLE, theme["camera"],
			GRID % [theme["columns"], ceili(items.size() / float(theme["columns"])), "\n".join(lines)]]
	if theme.has("extra"):
		parts.append(theme["extra"])
	parts.append(TEAM % theme["team"] if theme.has("team") else NO_TEAM)
	if not theme.get("no_green", false):
		parts.append(GREEN)
	return "\n\n".join(parts)


# --- Os temas ------------------------------------------------------------------

func _themes() -> Array:
	var u := "res://assets/sprites/units/"
	var c := "res://assets/sprites/cities/"
	var t := "res://assets/tiles/"
	var m := "res://assets/sprites/improvements/"
	return [
		{"name": "unidades", "what": "9 game units", "columns": 3, "cell": 150, "team_tint": true,
		"camera": """CAMERA:
- Every unit in three-quarter view facing RIGHT, seen from slightly above (about 20-30 degrees), like the galley.
- All units at the SAME scale: people at natural human size; horses, chariot and catapult at the same scale as the people. Feet, hooves and wheels on the bottom line of each cell.""",
		"team": "crests, tunic trims, belts, sashes, headbands, cloaks, shield faces, the chariot's front panel and the catapult's pennant",
		"items": [
			["trabalhador", u + "trabalhador", "Laborer: bare arms, short off-white tunic, sandals, a heavy axe on his right shoulder."],
			["colono", u + "colono", "Settler walking: wide straw hat, off-white tunic, a big bundle on his back, a shovel in his hand."],
			["guerreiro", u + "guerreiro", "Rustic warrior: bare chest, short kilt with a sash, headband, a heavy club over the shoulder, a small round shield."],
			["lanceiro", u + "lanceiro", "Hoplite: bronze Corinthian helmet with a horsehair crest, bronze cuirass, a tall spear upright, a big round aspis shield with a white lambda."],
			["guerreiro_espada", u + "guerreiro_espada", "Swordsman in an attack pose: crested bronze helmet, segmented armor, short gladius raised, curved rectangular scutum with a gold eagle."],
			["arqueiro", u + "arqueiro", "Archer drawing a long wooden bow, off-white tunic, headband, a quiver on the back."],
			["cavalaria_leve", u + "cavalaria_leve", "Light cavalry: a brown horse in mid trot, the rider with a crested bronze helmet and a cloak, holding a spear."],
			["bigas", u + "bigas", "Two-horse war chariot: two brown horses side by side, a light wooden chariot with two spoked wheels and its painted front panel, one charioteer in a crested helmet holding the reins."],
			["catapulta", u + "catapulta", "Wooden torsion catapult (onager) on four solid wheels with bronze hubs, twisted rope at the base of the arm, a sling cup with a round stone, a small pennant at the back; no crew."],
		]},
		{"name": "cidades", "what": "14 Greek town map icons: 4 town sizes (rows) x 4 versions (columns)", "columns": 4, "cell": 150, "team_tint": true,
		"rows": ["hamlet", "village", "town", "city"],
		"camera": """CAMERA AND LOOK:
- Every town in three-quarter view from above (about 40 degrees), like a small diorama: the whole town sits on a small round island of dusty ground with a few olive trees and cypresses around its edge. Whitewashed houses with terracotta tile roofs.
- The 4 versions in a row are the SAME town (same houses, same island): column 1 plain; column 2 plus the ruler's palace temple on the highest point; column 3 plus a stone city wall with towers and a gate; column 4 with both the temple and the wall.
- The rows grow: hamlet (4-5 houses, the hamlet has no palace version), village (about 10 houses), town (about 20 houses on two levels), city (houses filling the island, a stoa and a small theatre; its palace is an ACROPOLIS: a big columned temple on a high rocky terrace). Houses have the same size in every row; only their number grows.""",
		"team": "banners on the towers, market awnings and the temple roof trim",
		"items": [
			["povoado", c + "povoado", "Hamlet, plain: a few houses, a market awning, a well, olive trees, a low dry-stone garden wall."],
			["", "", ""],
			["povoado_muralha", c + "povoado_muralha", "Hamlet with a short stone wall, a gate and two small towers with banners."],
			["", "", ""],
			["vila", c + "vila", "Village, plain: houses around a square with a well, a fountain and a market."],
			["vila_capital", c + "vila_capital", "Village + a small temple with white columns on the highest point."],
			["vila_muralha", c + "vila_muralha", "Village + a stone wall with square towers and a gate."],
			["vila_capital_muralha", c + "vila_capital_muralha", "Village + temple + wall."],
			["cidade", c + "cidade", "Town, plain: about 20 houses on two levels, a market square."],
			["cidade_capital", c + "cidade_capital", "Town + a bigger temple on a raised stone terrace."],
			["cidade_muralha", c + "cidade_muralha", "Town + a wall with several towers and a big gate."],
			["cidade_capital_muralha", c + "cidade_capital_muralha", "Town + temple + wall."],
			["metropole", c + "metropole", "City, plain: many houses filling the island, a stoa, a small theatre."],
			["metropole_capital", c + "metropole_capital", "City + an acropolis: a large columned temple on a high rocky terrace."],
			["metropole_muralha", c + "metropole_muralha", "City + a tall wall with four big towers and a monumental gate."],
			["metropole_capital_muralha", c + "metropole_capital_muralha", "City + acropolis + wall."],
		]},
		{"name": "ruinas", "what": "8 map icons of Greek towns after being sacked and burned", "columns": 4, "cell": 150,
		"rows": ["without a wall", "with a wall"],
		"camera": """CAMERA AND LOOK:
- Same camera and island as a Greek town map icon: three-quarter view from above (about 40 degrees), the town on a small round island of dusty ground with a few trees around its edge.
- Ruins: collapsed terracotta roofs, blackened whitewashed walls, broken columns, rubble and a little grey smoke. No people, no banners, no temple standing.
- Columns grow in size: hamlet (a few houses), village, town, city (many houses). Row 2 is the same as row 1 plus a broken stone city wall with fallen towers.""",
		"items": [
			["povoado_ruinas", c + "povoado_ruinas", "Hamlet in ruins."],
			["vila_ruinas", c + "vila_ruinas", "Village in ruins."],
			["cidade_ruinas", c + "cidade_ruinas", "Town in ruins."],
			["metropole_ruinas", c + "metropole_ruinas", "City in ruins."],
			["povoado_muralha_ruinas", c + "povoado_muralha_ruinas", "Walled hamlet in ruins."],
			["vila_muralha_ruinas", c + "vila_muralha_ruinas", "Walled village in ruins."],
			["cidade_muralha_ruinas", c + "cidade_muralha_ruinas", "Walled town in ruins."],
			["metropole_muralha_ruinas", c + "metropole_muralha_ruinas", "Walled city in ruins."],
		]},
		{"name": "terrenos", "what": "6 square terrain textures", "columns": 3, "cell": 150, "tile": true,
		"camera": """THESE ARE TERRAIN TEXTURES, not objects:
- Each one seen straight from above (top-down) and filling its whole square cell edge to edge.
- Each one SEAMLESS: it must tile perfectly when repeated side by side and top to bottom.
- No object in the middle, no horizon, no border inside the squares.""",
		"extra": "The squares are separated by thin flat green (#00B140) gutters.",
		"items": [
			["pradaria", t + "pradaria", "Grassland: short green grass with small tufts and a few tiny flowers."],
			["cerrado", t + "cerrado", "Dry savanna: yellow-tan dry grass and dusty soil, a few small low bushes."],
			["floresta", t + "floresta", "Forest canopy from above: dense round tree crowns in deep greens, soft shadows between them."],
			["colinas", t + "colinas", "Green rolling hills from above: soft grassy mounds with gentle light and shade."],
			["montanhas", t + "montanhas", "Rocky grey mountains from above: sharp rock ridges and scree, no snow."],
			["agua", t + "agua", "Sea from above: deep dark teal water with small painted wave crests (dark teal is fine here, clearly different from royal blue)."],
		]},
		{"name": "melhorias", "what": "7 terrain improvements for map tiles and 1 resource icon", "columns": 4, "cell": 150,
		"camera": """CAMERA:
- Improvements seen from above (about 60-70 degrees, almost top-down), because each one sits on top of the terrain of a square map tile; each fills most of its cell.
- The destroyed versions show the same place as the intact one, burned or collapsed, with a little smoke.""",
		"items": [
			["fazenda", m + "fazenda", "Farm: a patchwork of four small fields (golden wheat, green vegetable rows, brown ploughed soil) with low wooden fences."],
			["fazenda_obra", m + "fazenda_obra", "Farm being prepared: bare ploughed brown furrows, a few stakes and a fence, nothing grown."],
			["fazenda_destruida", m + "fazenda_destruida", "The same farm burned and trampled: scorched black patches, broken fences."],
			["madeireira", m + "madeireira", "Lumber camp in a clearing: a stack of cut logs, a sawhorse with a log, an axe in a stump, a few trees."],
			["madeireira_destruida", m + "madeireira_destruida", "The same lumber camp burned: charred logs, a collapsed sawhorse."],
			["mina", m + "mina", "Mine: a dark tunnel mouth framed by wooden beams, cut into a grey rocky mound, a small ore cart."],
			["mina_destruida", m + "mina_destruida", "The same mine collapsed: fallen beams and rubble blocking the tunnel."],
			["ferro", "res://assets/sprites/resources/ferro", "Resource icon: an iron anvil, dark grey metal with a soft highlight, three-quarter view."],
		]},
		{"name": "tecnologias", "what": "16 small illustrations, one per technology, in ancient Greece", "columns": 4, "cell": 170, "wide": true,
		"no_green": true,
		"camera": """FORMAT:
- Each illustration is a complete painted scene in a landscape rectangle (about 16:10), filling its cell.
- Separate the 16 scenes with thin dark gutters. No text, no titles.""",
		"items": [
			["alfabeto", "res://assets/tech/alfabeto", "Writing: a scribe writing Greek letters on a wax tablet."],
			["construcao", "res://assets/tech/construcao", "Construction: masons building a stone wall with a wooden crane."],
			["misticismo", "res://assets/tech/misticismo", "Mysticism: priests burning incense at an altar before a temple."],
			["bronze", "res://assets/tech/bronze", "Bronze working: a smith pouring molten bronze into a mold."],
			["montaria", "res://assets/tech/montaria", "Horseback riding: young riders taming wild horses."],
			["guerra_a_distancia", "res://assets/tech/guerra_a_distancia", "Ranged warfare: archers training at targets."],
			["navegacao", "res://assets/tech/navegacao", "Navigation: a galley with a striped sail at sea."],
			["literatura", "res://assets/tech/literatura", "Literature: a poet reading a scroll to listeners under a portico."],
			["matematica", "res://assets/tech/matematica", "Mathematics: geometers drawing circles and triangles on sand."],
			["trabalho_em_ferro", "res://assets/tech/trabalho_em_ferro", "Iron working: a blacksmith hammering red-hot iron on an anvil."],
			["moeda", "res://assets/tech/moeda", "Currency: minting silver drachmas with a hammer and die."],
			["guerra_de_movimento", "res://assets/tech/guerra_de_movimento", "Mobile warfare: war chariots charging across a plain."],
			["direito", "res://assets/tech/direito", "Law: citizens voting with pebbles before a magistrate."],
			["engenharia_civil", "res://assets/tech/engenharia_civil", "Civil engineering: workers paving a road, an aqueduct behind."],
			["republica", "res://assets/tech/republica", "Republic: a citizens' assembly on a hill, a speaker on a stone platform."],
			["pao_e_circo", "res://assets/tech/pao_e_circo", "Bread and circuses: games in an arena, a cheering crowd, bread handed out."],
		]},
	]


# --- Imagem de referência -----------------------------------------------------------

func _reference(theme: Dictionary, path: String) -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = BACK
	viewport.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	viewport.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	margin.add_child(row)
	# Esquerda: o estilo
	var left := VBoxContainer.new()
	left.add_child(_label("ESTILO (referência)", 22))
	left.add_child(_picture(_style, Vector2(420, 420)))
	row.add_child(left)
	# Direita: os desenhos atuais na grade pedida
	var right := VBoxContainer.new()
	right.add_child(_label("ATUAL: %s (só o conteúdo; mesma grade e ordem)" % theme["name"], 22))
	var grid := GridContainer.new()
	grid.columns = theme["columns"]
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	var cell: int = theme["cell"]
	var size := Vector2(cell, cell * 0.62) if theme.get("wide", false) else Vector2(cell, cell)
	var number := 0
	for item: Array in theme["items"]:
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = CARD if item[0] != "" else Color(CARD, 0.35)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(5)
		card.add_theme_stylebox_override("panel", style)
		var inner := VBoxContainer.new()
		card.add_child(inner)
		if item[0] == "":
			var empty := Control.new()
			empty.custom_minimum_size = size
			inner.add_child(empty)
			inner.add_child(_label("(vazio)", 13))
		else:
			number += 1
			var image := _tinted(item[1]) if theme.get("team_tint", false) else _load(item[1] + ".png")
			if theme.get("tile", false):
				image = _tiled(image, 2)
			inner.add_child(_picture(image, size))
			var name_label := _label("%d. %s" % [number, item[0]], 13)
			name_label.custom_minimum_size.x = size.x
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			inner.add_child(name_label)
		grid.add_child(card)
	row.add_child(right)
	for i in 3:
		await process_frame
	var total := margin.get_combined_minimum_size()
	viewport.size = Vector2i(ceili(total.x), ceili(total.y))
	background.size = total
	margin.size = total
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("  %s (%dx%d)" % [path.get_file(), viewport.size.x, viewport.size.y])
	viewport.queue_free()


func _picture(image: Image, size: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(image)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = size
	return picture


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(235, 235, 235))
	return label


func _readme() -> void:
	var text := """PEDIDOS PARA O GEMINI: UM POR TEMA
==================================
Cada pasta é um pedido, com uma folha do tema inteiro:
  01_unidades     9 unidades (3x3; a Galé já está pronta)
  02_cidades      14 cidades (4x4: linhas = povoado, vila, cidade,
                  metrópole; colunas = normal, capital com palácio,
                  com muralha, capital com muralha; o povoado não tem
                  as versões de capital: células vazias)
  03_ruinas       8 ruínas (4x2: sem muralha / com muralha)
  04_terrenos     6 texturas (3x2)
  05_melhorias    7 melhorias + o ícone do ferro (4x2)
  06_tecnologias  16 ilustrações (4x4, opcional)

Para cada pasta:
  1. Abra uma CONVERSA NOVA no Gemini.
  2. Anexe referencia.png (à esquerda o ESTILO, a Galé; à direita os
     desenhos ATUAIS do tema, numerados, na mesma grade que o prompt
     pede).
  3. Cole o texto de prompt.txt inteiro.
  4. Salve a imagem na pasta como resultado.png.

Se a folha sair errada, peça para refazer na mesma conversa, citando o
problema, ex.: "Redo it: keep the same 4x4 grid and order", "Redo it:
the background must be one flat green #00B140", "Redo it: the 4 versions
in a row must be the same town", "Redo it: same painted style as the
galley".

Lógica das cidades: classe pela população (povoado 1-5, vila 6-15,
cidade 16-30, metrópole 31+); capital = templo no alto (o Palácio; o
povoado não tem); muralha = só com o prédio Muralha, em qualquer classe.

Gerado por tools/art/pedidos_gemini.gd (os textos dos prompts ficam lá).
"""
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT + "LEIA-ME.txt"), FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Imagens ------------------------------------------------------------------------

func _load(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	image.convert(Image.FORMAT_RGBA8)
	return image


## Com a cor do time em azul (#1E50FF), como no jogo: base + máscara x cor.
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


## O terreno repetido [param times] x [param times] (para mostrar a emenda).
func _tiled(image: Image, times: int) -> Image:
	var tiled := Image.create(image.get_width() * times, image.get_height() * times, false, Image.FORMAT_RGBA8)
	for y in times:
		for x in times:
			tiled.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, y) * image.get_size())
	return tiled


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
