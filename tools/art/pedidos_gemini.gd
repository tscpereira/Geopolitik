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
- Paint everything NEW. Do not copy or paste any part of the attached image into the result: no galley, no old drawings, no labels, no numbers.

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
	# Guarda o que o usuário salvou nas pastas (ex.: resultado.png), pelo nome do
	# tema (o número pode mudar), e apaga os pedidos antigos
	var kept := _keep_user_files()
	var dir := DirAccess.open(ProjectSettings.globalize_path("res://tools/art/gemini/"))
	if dir and dir.dir_exists("pedidos"):
		_remove_tree(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for theme: Dictionary in _themes():
		n += 1
		var folder := "%s%02d_%s/" % [OUT, n, theme["name"]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		for file_name: String in kept.get(theme["name"], {}):
			var saved := FileAccess.open(ProjectSettings.globalize_path(folder + file_name), FileAccess.WRITE)
			saved.store_buffer(kept[theme["name"]][file_name])
			saved.close()
			print("  mantido %s/%s" % [theme["name"], file_name])
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
	var list := [
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
		# Colinas e montanhas: o shader do mapa já desenha o relevo (morros e picos
		# com luz e sombra); a imagem é só a superfície do material, sem relevo.
		# A folha de 07_terrenos veio com relevo pintado e não serviu (26/10/2026).
		{"name": "terrenos_relevo", "what": "2 square surface textures for hills and mountains", "columns": 2, "cell": 170, "tile": true,
		"camera": """THESE ARE FLAT SURFACE TEXTURES, not landscapes:
- The game already draws the hills and the mountain peaks with their own light and shadow. These images are ONLY the surface material that goes on top: seen straight from above, like a photo of the ground taken from a drone pointing straight down, completely FLAT lighting.
- NO peaks, NO ridges, NO mounds, NO slopes, NO cast shadows, NO perspective, no horizon. Just an even, uniform surface pattern filling the whole square edge to edge.
- Each one SEAMLESS: it must tile perfectly when repeated side by side and top to bottom.""",
		"extra": "The squares are separated by thin flat green (#00B140) gutters.",
		"items": [
			["colinas", t + "colinas", "Hill grass: short green-olive grass with small tufts, a few small grey stones and patches of bare earth; slightly drier and stonier than a meadow."],
			["montanhas", t + "montanhas", "Mountain rock: grey and warm-grey stone surface with cracks, small loose pebbles and a few patches of lichen; even, no peaks."],
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
	# As cidades, uma classe por pedido (as 14 juntas o Gemini não conseguiu)
	return list.slice(0, 1) + _city_themes(c) + list.slice(1)



## Um pedido por classe de cidade: as versões da MESMA cidade lado a lado
## (normal, com palácio, com muralha, com os dois; o povoado não tem palácio).
func _city_themes(c: String) -> Array:
	var camera := """CAMERA AND LOOK:
- Three-quarter view from above (about 40 degrees), like a small diorama: the whole town sits on a small round island of dusty ground with a few olive trees and cypresses around its edge. Whitewashed houses with terracotta tile roofs.
- All versions in the row are the SAME town: same island, same houses in the same places, same size and camera. They differ ONLY in what the list adds (the ruler's palace temple, the city wall).
- The houses are small compared with the island (about the size of the houses of a village seen from a hill): %s"""
	var team := "banners on the towers, market awnings and the temple roof trim"
	var classes := [
		["povoado", "a hamlet", "a hamlet has only 4 or 5 houses, so its island is small.",
			[["", "Hamlet, plain: 4-5 houses, a market awning, a well, olive trees, a low dry-stone garden wall."],
			["_muralha", "The same hamlet surrounded by a short stone wall with a gate and two small towers with banners."]]],
		["vila", "a village", "about 10 houses around a small square.",
			[["", "Village, plain: about 10 houses around a square with a well, a fountain and a market."],
			["_capital", "The same village plus a small Greek temple with white columns on its highest point (the ruler's palace temple)."],
			["_muralha", "The same village (without the temple) surrounded by a stone wall with square towers and a gate."],
			["_capital_muralha", "The same village with both the temple and the wall."]]],
		["cidade", "a town", "about 20 houses on two levels.",
			[["", "Town, plain: about 20 houses on two levels, a market square with a fountain."],
			["_capital", "The same town plus a bigger Greek temple on a raised stone terrace (the ruler's palace temple)."],
			["_muralha", "The same town (without the temple) surrounded by a stone wall with several towers and a big gate."],
			["_capital_muralha", "The same town with both the temple and the wall."]]],
		["metropole", "a large city", "many houses filling a big island, a stoa and a small theatre.",
			[["", "City, plain: many houses filling the island, a stoa and a small theatre."],
			["_capital", "The same city plus an ACROPOLIS: a large columned temple on a high rocky terrace (the ruler's palace)."],
			["_muralha", "The same city (without the acropolis) surrounded by a tall stone wall with four big towers and a monumental gate."],
			["_capital_muralha", "The same city with both the acropolis and the wall."]]],
	]
	var themes := []
	for k: Array in classes:
		var items := []
		for v: Array in k[3]:
			items.append([k[0] + v[0], c + k[0] + v[0], v[1]])
		themes.append({"name": "cidades_" + k[0], "what": "%d versions of the same Greek town map icon: %s" % [items.size(), k[1]],
			"columns": items.size(), "cell": 170, "team_tint": true, "camera": camera % k[2], "team": team, "items": items})
	return themes

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
Cada pasta é um pedido, com uma folha do tema:
  01_unidades           9 unidades (3x3; a Galé já está pronta)
  02_cidades_povoado    povoado: normal e com muralha (o povoado não
                        tem palácio)
  03_cidades_vila       vila: normal, capital (palácio), com muralha,
                        capital com muralha
  04_cidades_cidade     cidade: as mesmas 4 versões
  05_cidades_metropole  metrópole: as mesmas 4 (o palácio é a acrópole)
  06_ruinas             8 ruínas (4x2: sem muralha / com muralha)
  07_terrenos           6 texturas (3x2); FEITO: pradaria, cerrado,
                        floresta e água (colinas e montanhas vieram com
                        relevo pintado e não serviram)
  08_terrenos_relevo    colinas e montanhas: só a superfície, SEM relevo
                        (o mapa já desenha morros e picos)
  09_melhorias          7 melhorias + o ícone do ferro (4x2)
  10_tecnologias        16 ilustrações (4x4, opcional)
  (As 14 cidades numa folha só o Gemini não conseguiu: copiou a
  referência. Por isso uma classe por pedido.)

Para cada pasta:
  1. Abra uma CONVERSA NOVA no Gemini.
  2. Anexe referencia.png (à esquerda o ESTILO, a Galé; à direita os
     desenhos ATUAIS do tema, numerados, na mesma grade que o prompt
     pede).
  3. Cole o texto de prompt.txt inteiro.
  4. Salve a imagem na pasta como resultado.png.

Se a folha sair errada, peça para refazer na mesma conversa, citando o
problema, ex.: "Redo it: keep the same 4x4 grid and order", "Redo it:
the background must be one flat green #00B140", "Redo it: the versions
must be the same town", "Redo it: same painted style as the
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


## Arquivos das pastas de pedido que não são gerados aqui (o resultado.png que
## o usuário salvou): {tema: {arquivo: bytes}}.
func _keep_user_files() -> Dictionary:
	var kept := {}
	var root_dir := DirAccess.open(ProjectSettings.globalize_path(OUT))
	if root_dir == null:
		return kept
	for folder in root_dir.get_directories():
		var theme := folder.substr(folder.find("_") + 1)
		var path := ProjectSettings.globalize_path(OUT).path_join(folder)
		for file_name in DirAccess.get_files_at(path):
			if file_name in ["prompt.txt", "referencia.png"]:
				continue
			if not kept.has(theme):
				kept[theme] = {}
			kept[theme][file_name] = FileAccess.get_file_as_bytes(path.path_join(file_name))
	return kept


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
