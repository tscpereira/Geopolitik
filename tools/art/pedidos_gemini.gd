extends SceneTree

## Um PEDIDO por desenho para o Gemini (ele se perdia com tudo de uma vez).
## Rode COM janela (os títulos são desenhados pelo Godot):
##   godot_console.cmd --path . --script tools/art/pedidos_gemini.gd
## Grava tools/art/gemini/pedidos/<NN>_<nome>/ com:
##   referencia.png  a Galé (o ESTILO) à esquerda e o desenho atual (o
##                   CONTEÚDO) à direita; o terreno aparece repetido 3x3;
##   prompt.txt      o prompt inteiro, com o estilo embutido: anexe a
##                   referência e cole o texto, numa conversa nova.
## E tools/art/gemini/pedidos/LEIA-ME.txt com a ordem e as dicas.

const OUT := "res://tools/art/gemini/pedidos/"
const STYLE_IMAGE := "res://tools/art/chatgpt/gale_avulsa.png"
const TEAM_BLUE := Color8(30, 80, 255)
const PANEL := 460

const STYLE := """STYLE (copy it from the LEFT image, the galley):
- Detailed painted digital illustration with realistic proportions: soft painted shading, visible wood grain and texture, warm earthy palette (warm brown wood, off-white linen and plaster, terracotta roof tiles, bronze, olive greens). Not cartoon, not chibi, not pixel art, no thick black outlines, no flat colors, not a photo.
- Strong, clean silhouette that stays readable when shrunk to a small game sprite: few big shapes, no thin clutter.
- Soft daylight from the TOP-LEFT."""

const TEAM := """TEAM COLOR:
- The player's color is ONE vivid royal blue (#1E50FF), used ONLY on: %s. Use lighter and darker shades of that blue there, nowhere else. No other blue, cyan, teal or purple anywhere: no blue sky, no water, no blue shadows."""

const GREEN := """BACKGROUND:
- One flat, solid chroma-key green (#00B140) filling the whole background: no gradient, no texture, no vignette, no cast shadow on the background, no ground, no frame, no text, no signature.
- One subject only, whole, never cropped, centered, with a small empty margin. Square image (1:1)."""

const INTRO := """I am remaking the art of a 2D turn-based strategy game set in ancient Greece. The attached image has two parts:
- LEFT, "ESTILO": a galley that is the STYLE REFERENCE. Paint in exactly this style.
- RIGHT, "ATUAL": the current, low-quality version of the item I need. Use it only to know WHAT to draw (content and composition), not how it looks.
Create ONE image: %s."""

const UNIT_CAMERA := """CAMERA:
- Three-quarter view facing RIGHT, seen from slightly above (about 20-30 degrees), like the galley.
- Feet, hooves and wheels on one common ground line at the bottom. People at natural human proportions; horses, chariots and machines at the same scale as the people."""

const CITY_CAMERA := """CAMERA AND LOOK:
- Three-quarter view from above (about 40 degrees), like a small diorama: the whole town sits on a small round island of dusty ground with a few olive trees and cypresses around its edge.
- Greek town: whitewashed houses with terracotta tile roofs. It must read well when shrunk to 128x128 pixels."""

const TILE_RULES := """THIS IS A TERRAIN TEXTURE, not an object:
- Seen straight from above (top-down), filling the whole square edge to edge.
- SEAMLESS: it must tile perfectly when repeated side by side and top to bottom (the right image shows the current one repeated 3x3).
- No object in the middle, no horizon, no border, no frame, no text. Square image (1:1)."""

const IMPROVEMENT_CAMERA := """CAMERA:
- Seen from above (about 60-70 degrees, almost top-down), because it sits on top of the terrain of a square map tile. Fill most of the square."""

var _style: Image


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_style = _load(STYLE_IMAGE)
	_run()


func _run() -> void:
	var n := 0
	for item: Dictionary in _items():
		n += 1
		var folder := "%s%02d_%s/" % [OUT, n, item["name"]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var file := FileAccess.open(ProjectSettings.globalize_path(folder + "prompt.txt"), FileAccess.WRITE)
		file.store_string(item["prompt"] + "\n")
		file.close()
		await _reference(item, folder + "referencia.png")
	_readme(n)
	print("ok: %d pedidos" % n)
	quit()


# --- Os pedidos ------------------------------------------------------------------

func _items() -> Array:
	var items := []
	var units := [
		["trabalhador", "a Greek laborer: bare arms, short off-white tunic, leather sandals, carrying a heavy axe on his right shoulder", "his belt and tunic trim"],
		["colono", "a Greek settler walking: wide straw hat, off-white tunic, a big bundle on his back, a shovel in his hand", "his tunic trim and belt"],
		["guerreiro", "a rustic ancient warrior: bare chest, short off-white kilt, a heavy club over the shoulder and a small round shield", "his sash, headband and the shield face"],
		["lanceiro", "a Greek hoplite standing guard: bronze Corinthian helmet with a horsehair crest, bronze muscle cuirass, off-white chiton, a tall spear held upright and a large round aspis shield with a bronze rim and a white lambda", "the helmet crest, tunic trim and the shield face"],
		["guerreiro_espada", "a legionary-style swordsman in an attack pose: bronze helmet with a crest, segmented armor, a short gladius raised, a curved rectangular scutum shield with a gold eagle", "the helmet crest and the shield face"],
		["arqueiro", "a Greek archer drawing a long wooden bow: off-white tunic, a quiver of arrows on the back", "his headband and tunic trim"],
		["cavalaria_leve", "light cavalry: a brown horse in mid trot, the rider with a bronze crested helmet and a cloak, holding a spear; horse and rider no wider than about 1.2 times their height", "the helmet crest and the cloak"],
		["bigas", "a two-horse war chariot: two brown horses side by side in mid trot, a light wooden chariot with two spoked wheels and one charioteer in a crested bronze helmet holding the reins; compact, no wider than 1.3 times its height", "the front panel of the chariot and the charioteer's crest"],
		["catapulta", "a wooden torsion catapult (onager) on four solid wooden wheels with bronze hubs, thick twisted rope at the base of the arm, a leather sling cup holding a round stone; no crew", "a small pennant on a pole at the back and a painted band on the frame"],
	]
	for unit: Array in units:
		items.append({"name": unit[0], "images": ["res://assets/sprites/units/" + unit[0]], "team": true,
			"prompt": "\n\n".join([INTRO % ("a game unit: " + unit[1]), STYLE, UNIT_CAMERA, TEAM % unit[2], GREEN])})
	# Cidades: a versão normal de cada classe primeiro; as outras EDITAM a anterior
	var towns := {
		"povoado": "a small hamlet: 4 or 5 whitewashed houses, one market awning, a well, olive trees and a low dry-stone wall around the gardens (fewer houses than a village, but each house the same size as in a bigger town)",
		"vila": "a village: about 10 houses around a small square with a well, a fountain and a market with awnings; cypresses between the houses",
		"cidade": "a town: about 20 houses on two levels, a larger market square with awnings, a fountain",
		"metropole": "a large city: many houses filling the whole island, a stoa and a small theatre",
	}
	var temples := {
		"vila": "a small Greek temple with white columns on the highest point (the ruler's palace temple)",
		"cidade": "a bigger Greek temple on a raised stone terrace (the ruler's palace temple)",
		"metropole": "an ACROPOLIS: a large columned temple on a high rocky terrace (the ruler's palace)",
	}
	var walls := {
		"povoado": "a short stone wall with a gate and two small towers",
		"vila": "a stone wall with square towers and a gate",
		"cidade": "a stone wall with several towers and a big gate",
		"metropole": "a tall stone wall with four big towers and a monumental gate",
	}
	var city_team := "banners, market awnings and the temple roof trim"
	for rank: String in ["povoado", "vila", "cidade", "metropole"]:
		var base := "res://assets/sprites/cities/" + rank
		items.append({"name": rank, "images": [base], "team": true,
			"prompt": "\n\n".join([INTRO % ("a Greek town seen as a map icon: " + towns[rank]), STYLE, CITY_CAMERA, TEAM % city_team, GREEN])})
		var variants := []
		if temples.has(rank):
			variants.append([rank + "_capital", rank, "add %s. Keep everything else identical." % temples[rank]])
		variants.append([rank + "_muralha", rank, "surround the same town with %s, with banners on the towers. Keep the houses identical." % walls[rank]])
		if temples.has(rank):
			variants.append([rank + "_capital_muralha", rank + "_capital", "surround the same town with %s, with banners on the towers. Keep the houses and the temple identical." % walls[rank]])
		variants.append([rank + "_ruinas", rank, "the same town after being sacked and burned: roofs collapsed, blackened walls, rubble and a little smoke; no people, no banners and NO blue at all. Keep the same island, size and camera."])
		variants.append([rank + "_muralha_ruinas", rank + "_muralha", "the same walled town after being sacked and burned: broken walls and towers, collapsed roofs, rubble and a little smoke; no people, no banners and NO blue at all. Keep the same island, size and camera."])
		for v: Array in variants:
			var edit := """EDIT, do not redraw: I am ALSO attaching the image you generated before for "%s". Edit THAT image: %s
Keep exactly the same painted style, camera, island, size and the green background (#00B140).""" % [v[1], v[2]]
			items.append({"name": v[0], "images": ["res://assets/sprites/cities/" + v[0]], "team": not v[0].ends_with("ruinas"),
				"prompt": "\n\n".join([INTRO % "an edited version of a town map icon (details below)", edit,
					TEAM % city_team if not v[0].ends_with("ruinas") else "TEAM COLOR: none in this image (ruins have no banners).", GREEN])})
	var tiles := [
		["pradaria", "grassland: short green grass with small tufts and a few tiny flowers, olive-green palette"],
		["cerrado", "dry savanna: yellow-tan dry grass and dusty soil, a few small low bushes"],
		["floresta", "a forest seen from above: a dense canopy of round deciduous tree crowns in deep greens, with soft shadows between them"],
		["colinas", "green rolling hills seen from above: soft grassy mounds with gentle painted light and shade"],
		["montanhas", "rocky grey mountains seen from above: sharp rock ridges and scree in light grey and warm grey, no snow"],
		["agua", "the sea seen from above: deep dark teal water with small painted wave crests (this dark teal is fine; it must be clearly different from royal blue)"],
	]
	for tile: Array in tiles:
		items.append({"name": "terreno_" + tile[0], "images": ["res://assets/tiles/" + tile[0]], "tile": true,
			"prompt": "\n\n".join([INTRO % ("a terrain texture: " + tile[1]), STYLE, TILE_RULES])})
	var improvements := [
		["fazenda", "a farm plot: a patchwork of four small fields (golden wheat, green rows of vegetables, brown ploughed soil) with low wooden fences between them", ""],
		["fazenda_obra", "a farm plot just being prepared: bare ploughed brown furrows, a few stakes and a wooden fence, nothing grown yet", ""],
		["fazenda_destruida", "a farm plot burned and trampled: scorched black patches over the fields, broken fences, a little smoke", "fazenda"],
		["madeireira", "a lumber camp in a small clearing: a stack of cut logs, a sawhorse with a log, an axe in a stump, a few trees around", ""],
		["madeireira_destruida", "a lumber camp burned: charred logs, a collapsed sawhorse, smoke", "madeireira"],
		["mina", "a mine entrance cut into a grey rocky mound: a dark tunnel mouth framed by wooden beams, a small ore cart", ""],
		["mina_destruida", "a collapsed mine: fallen beams and rubble blocking the tunnel, a little smoke", "mina"],
	]
	for imp: Array in improvements:
		var subject: String = imp[1]
		if imp[2] != "":
			subject += """. If you made the "%s" image before, attach it too and edit it, keeping the same layout""" % imp[2]
		items.append({"name": imp[0], "images": ["res://assets/sprites/improvements/" + imp[0]],
			"prompt": "\n\n".join([INTRO % ("a terrain improvement for a map tile: " + subject), STYLE, IMPROVEMENT_CAMERA,
				"TEAM COLOR: none (no blue at all).", GREEN])})
	items.append({"name": "ferro", "images": ["res://assets/sprites/resources/ferro"],
		"prompt": "\n\n".join([INTRO % "a small resource icon: an iron anvil, dark grey metal with a soft highlight, three-quarter view",
			STYLE, "TEAM COLOR: none (no blue at all).", GREEN])})
	var techs := [
		["alfabeto", "Escrita", "a scribe writing Greek letters on a wax tablet"],
		["construcao", "Construção", "masons building a stone wall with ropes and a wooden crane"],
		["misticismo", "Misticismo", "priests burning incense at an altar before a temple"],
		["bronze", "Trabalho em Bronze", "a smith pouring molten bronze into a mold"],
		["montaria", "Montaria", "young riders taming wild horses"],
		["guerra_a_distancia", "Guerra a distância", "archers training at targets"],
		["navegacao", "Navegação", "a galley with a striped sail at sea"],
		["literatura", "Literatura", "a poet reading from a scroll to listeners under a portico"],
		["matematica", "Matemática", "geometers drawing circles and triangles on sand with compasses"],
		["trabalho_em_ferro", "Trabalho em Ferro", "a blacksmith hammering red-hot iron on an anvil"],
		["moeda", "Moeda", "minting silver drachmas with a hammer and die"],
		["guerra_de_movimento", "Guerra de movimento", "war chariots charging across a plain"],
		["direito", "Direito", "citizens voting with pebbles before a magistrate"],
		["engenharia_civil", "Engenharia Civil", "workers paving a road with an aqueduct behind"],
		["republica", "República", "a citizens' assembly on a hill, a speaker on a stone platform"],
		["pao_e_circo", "Pão e Circo", "games in an arena with a cheering crowd and bread being handed out"],
	]
	for tech: Array in techs:
		items.append({"name": "tecnologia_" + tech[0], "images": ["res://assets/tech/" + tech[0]], "wide": true,
			"prompt": "\n\n".join([INTRO % ("an illustration for the technology \"%s\": %s in ancient Greece" % [tech[1], tech[2]]), STYLE,
				"FORMAT: landscape 16:10, a complete painted scene that fills the frame (no green background here), warm palette, soft light, no text, no frame. TEAM COLOR: does not apply."])})
	return items


# --- Imagem de referência ---------------------------------------------------------

func _reference(item: Dictionary, path: String) -> void:
	var current: Image = _load(item["images"][0] + ".png")
	if item.get("team", false):
		current = _tinted(item["images"][0])
	if item.get("tile", false):
		var tiled := Image.create(current.get_width() * 3, current.get_height() * 3, false, Image.FORMAT_RGBA8)
		for y in 3:
			for x in 3:
				tiled.blit_rect(current, Rect2i(Vector2i.ZERO, current.get_size()), Vector2i(x, y) * current.get_size())
		current = tiled
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.size = Vector2i(PANEL * 2 + 60, PANEL + 70)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var back := ColorRect.new()
	back.color = Color8(46, 50, 56)
	back.size = viewport.size
	viewport.add_child(back)
	for side in 2:
		var x := 20 + side * (PANEL + 20)
		var title := Label.new()
		title.text = "ESTILO (referência)" if side == 0 else "ATUAL: " + item["name"] + " (só o conteúdo)"
		title.position = Vector2(x, 12)
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color8(235, 235, 235))
		viewport.add_child(title)
		var frame := ColorRect.new()
		frame.color = Color8(70, 76, 84)
		frame.position = Vector2(x, 50)
		frame.size = Vector2(PANEL, PANEL)
		viewport.add_child(frame)
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(_style if side == 0 else current)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2(x + 10, 60)
		picture.size = Vector2(PANEL - 20, PANEL - 20)
		viewport.add_child(picture)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	viewport.queue_free()


func _readme(count: int) -> void:
	var text := """PEDIDOS PARA O GEMINI: UM DESENHO POR VEZ (%d pedidos)
==============================================================
Cada pasta é um pedido. Para cada uma:
  1. Abra uma CONVERSA NOVA no Gemini (assim ele não mistura os pedidos).
  2. Anexe referencia.png (à esquerda o ESTILO, a Galé; à direita o
     desenho ATUAL, que mostra só o que desenhar).
  3. Cole o texto de prompt.txt inteiro.
  4. Baixe a imagem e salve na própria pasta como resultado.png.

Cidades e ruínas (pastas com _capital, _muralha, _ruinas): são EDIÇÕES.
Anexe também o resultado.png da pasta indicada no prompt (ex.: para
vila_muralha, o resultado de "vila"). Por isso faça na ordem das pastas.

Lógica das cidades: classe pela população (povoado 1-5, vila 6-15,
cidade 16-30, metrópole 31+); "_capital" = só a capital, com o templo
no alto (o Palácio; o povoado não tem); "_muralha" = só com o prédio
Muralha, em qualquer classe; "_ruinas" = cidade destruída.

Se sair fora do padrão, peça para refazer na mesma conversa, citando o
problema: "Redo it: the background must be one flat green #00B140",
"Redo it: no water and no blue except the listed parts", "Redo it: same
painted style as the galley, not cartoon".

Ordem sugerida: unidades (01-09), cidades e ruínas, terrenos,
melhorias, ferro e, por último (opcional), as tecnologias.
Gerado por tools/art/pedidos_gemini.gd.
""" % count
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
