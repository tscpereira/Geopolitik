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
		# Prompts a mais do pedido (ex.: as edições do rosto dos líderes)
		for extra_name: String in theme.get("extra_files", {}):
			var extra := FileAccess.open(ProjectSettings.globalize_path(folder + extra_name), FileAccess.WRITE)
			extra.store_string(theme["extra_files"][extra_name] + "\n")
			extra.close()
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
	var parts: Array[String] = [theme.get("intro", INTRO) % theme["what"], theme.get("style", STYLE), theme["camera"],
			GRID % [theme["columns"], ceili(items.size() / float(theme["columns"])), "\n".join(lines)]
			if not theme.get("no_current", false) else theme.get("items_title", "THE UNIT:") + "\n" + "\n".join(theme["items"].map(func(item: Array) -> String: return "- " + item[2]))]
	if theme.has("extra"):
		parts.append(theme["extra"])
	parts.append(theme["team_note"] if theme.has("team_note") else TEAM % theme["team"] if theme.has("team") else NO_TEAM)
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
		# Melhorias: madeireira, mina e o ferro já vieram bons na folha de 26/10/2026
		# (tools/art/gemini/melhorias_folha.png). As fazendas vieram com uma casa e
		# ocupando a casa inteira: o usuário quer só os canteiros, com a "cruz" entre
		# eles e a margem transparentes (o terreno do mapa aparece por baixo).
		# Fazendas no estilo das do Civilization VI (pedido do usuário, 26/10/2026):
		# mosaico de campos pequenos com listras de plantio, cercas baixas e árvores
		# nas bordas; à grega (vinhedo, oliveiras), sem construções, com o verde
		# entre os campos e na borda transparente. A versão anterior (4 canteiros
		# 2x2) está no jogo desde 26/10/2026.
		{"name": "fazendas", "what": "3 versions of the same small patch of Greek farmland, seen from high above", "columns": 3, "cell": 170,
		"camera": """LOOK (read carefully, this is the most important part):
- Like the farms of the strategy game Civilization VI, painted in the galley's style: a cosy PATCHWORK of 5 or 6 small fields of different sizes and colours, each field covered with neat parallel PLANTING STRIPES (crop rows), the stripe direction changing from one field to the next so the patchwork reads clearly from far away.
- Greek countryside crops: golden wheat, pale green barley, dark green vegetable rows, a VINEYARD (rows of low grapevines) and a few rows of small round OLIVE TREES. Warm, sunny, saturated but natural colours.
- The fields are slightly irregular rectangles (not a perfect grid), separated by thin LOW WOODEN FENCES or low dry-stone walls along some of their edges, with a few small round bushes or trees at some corners.
- High bird's-eye view, almost top-down (about 70-80 degrees): the fields are seen from above, and the fences and trees show just a little of their sides.
- The whole patch covers about 75-80% of its cell; its outline is organic and slightly irregular, not a square.
- Between the fields there are narrow gaps, and around the patch there is an empty margin: those gaps and the margin contain NOTHING, only the flat chroma-key green background (#00B140). The game makes that green transparent, so the map's own grass shows through. Do NOT paint grass, paths, roads or shadows in them.
- NO farmhouse, NO barn, NO building of any kind, NO people, NO animals, NO carts or machines.
- The 3 versions are the SAME patch with the same fields in the same places; only the crops change.""",
		"extra": "NOTE: here the right side of the attached image is not old art but a LAYOUT SKETCH: a patchwork of striped fields with plain green gaps and margin. Paint it in the galley's painted style, with the Civilization VI farm look described above; keep the idea of the layout, not its exact shapes. If a SECOND image is attached (a screenshot of farms in Civilization VI), use it only as a reference for the farm look (patchwork, stripes, fences, trees): ignore its icons, buildings and vehicles, and keep the galley's painted style.",
		"items": [
			["fazenda", "esquema:civ_producao", "Farmland in production: golden wheat, pale green barley, dark green vegetable rows, a small vineyard and a row of olive trees, with low fences."],
			["fazenda_obra", "esquema:civ_obra", "The same farmland just being prepared: every field freshly ploughed into brown furrows (still striped, in the same directions), nothing grown yet, the fences and the olive trees already there, a few wooden stakes."],
			["fazenda_destruida", "esquema:civ_queimada", "The same farmland burned and trampled: scorched black and dark brown fields with burned stubble, broken fences, charred olive trees, a thin wisp of smoke."],
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
		# Terrenos de 28/10/2026 (no jogo com texturas provisórias geradas por
		# tools/art/gen_terrenos_novos.gd). Importar com import_terrenos_gemini.gd:
		#   ... -- resultado.png aguas_profundas selva deserto tundra neve
		{"name": "terrenos_novos", "what": "5 square terrain textures", "columns": 5, "cell": 150, "tile": true,
		"camera": """THESE ARE TERRAIN TEXTURES, not objects:
- Each one seen straight from above (top-down) and filling its whole square cell edge to edge.
- Each one SEAMLESS: it must tile perfectly when repeated side by side and top to bottom.
- No object in the middle, no horizon, no border inside the squares.
- FLAT lighting, no big relief: the game draws hills and mountains by itself.""",
		"extra": "The squares are separated by thin flat green (#00B140) gutters.",
		"items": [
			["aguas_profundas", t + "aguas_profundas", "Deep open ocean from above: very dark navy-blue water, darker than the coastal teal sea, with a few small painted wave crests."],
			["selva", t + "selva", "Tropical jungle canopy from above: very dense, lush rainforest of round tree crowns in many greens, with many PALM TREES (star-shaped palm fronds) mixed in, deep shadows between them."],
			["deserto", t + "deserto", "Sand desert from above: warm golden sand with soft wind ripples and gentle dune shading, a few tiny pebbles."],
			["tundra", t + "tundra", "Tundra from above: cold brown-olive ground with low moss and lichen patches, small grey stones and thin patches of old snow."],
			["neve", t + "neve", "Snow field from above: clean white snow with soft blue-grey shadows of small drifts, a little sparkle."],
		]},
		# Quadrirreme (29/10/2026): barco de guerra da Cartografia, mais imponente
		# que a Galé (pedido do usuário). A 1ª tentativa, com a Galé como
		# referência de estilo, voltou uma cópia da Galé: aqui a referência são
		# unidades que não são barcos (style_images) e o desenho provisório não
		# aparece (no_current). Importado em 29/10/2026 (o 2º resultado).
		# Importar como avulsa:
		#   ... import_folha_unidades.gd -- resultado.png quadrirreme
		{"name": "quadrirreme", "what": "1 game unit: a big Greek warship", "columns": 1, "cell": 300, "team_tint": true,
		"style_images": [u + "retratos/lanceiro", u + "retratos/arqueiro", u + "retratos/catapulta"],
		"no_current": true,
		"intro": """I am making the art of a 2D turn-based strategy game set in ancient Greece. The attached image shows three units already made for the game (a hoplite, an archer and a wooden catapult). It is ONLY the STYLE REFERENCE: paint the new unit in exactly this painted style, with the same detail, palette and light. Do not copy or include any of those three units.

Create ONE image: %s.""",
		"style": """STYLE (copy it from the attached units):
- Detailed painted digital illustration with realistic proportions: soft painted shading, visible wood grain and texture, warm earthy palette (dark oak and warm brown wood, off-white linen, bronze, a little dark red paint). Not cartoon, not chibi, not pixel art, no thick black outlines, no flat colors, not a photo.
- Strong, clean silhouette that stays readable when shrunk to a small game sprite: few big shapes, no thin clutter.
- Soft daylight from the TOP-LEFT.""",
		"camera": """CAMERA:
- Three-quarter view of the side of the ship, the BOW (front, with the ram) pointing to the RIGHT and the stern on the LEFT, seen from slightly above (about 20-30 degrees).
- The hull floats on nothing: no water, no waves, no reflection, no splash; the bottom of the hull near the bottom of the image.

WHAT MAKES IT DIFFERENT (very important):
- This is NOT a small viking-like galley with one sail and a tall curled prow. Avoid that look completely: no dragon-like or spiral prow, no single big striped square sail dominating the picture.
- It is a HEAVY, IMPOSING Hellenistic battleship: a long, broad and LOW hull, much longer than it is tall, built like a floating fortress.""",
		"items": [
			["quadrirreme", u + "quadrirreme", "Quadrireme warship: a long, heavy, dark-oak hull painted with a dark red band, with an outrigger box along the side and TWO stacked rows of many short oars; a massive three-bladed bronze RAM sticking out at the waterline of the bow; a big painted eye on the bow; a flat fighting deck covered from end to end, with a solid wooden parapet lined with round shields; a square WOODEN COMBAT TOWER on the deck near the bow with three archers drawing their bows on top of it; TWO masts: a main mast amidships and a smaller one leaning forward over the bow, each with a modest furled or half-reefed sail (the sails are NOT the main feature); a stern that curves up into a fan-shaped ornament (aphlaston) and two big steering oars at the back; bronze fittings along the hull."],
		],
		"team": "the round shields along the parapet, the long pennant on the main mast and a painted stripe along the top of the combat tower",
		"extra": "The ship must fill most of the image width. Draw it big, alone and complete (bow, stern and all the oars inside the image).",
		},
	]
	# As cidades, uma classe por pedido (as 14 juntas o Gemini não conseguiu)
	return list.slice(0, 1) + _city_themes(c) + list.slice(1) + _leader_themes(u)


## Retratos dos LÍDERES (30/10/2026, pedido do usuário): um pedido por líder,
## com as 3 expressões (brava em guerra, neutra em paz, feliz com boa
## relação), da cintura para cima, no estilo das unidades (style_images; sem
## desenho atual: no_current), grandes e em pé: o retrato ocupa o palco do
## encontro, bem maior que os outros desenhos. Desde 30/10/2026 (pedido do
## usuário: as três num pedido só; nas edições do rosto uma a uma a imagem
## inteira mudava e a capa do grego saiu cortada): UMA FOLHA LARGA (16:9, 3K
## ou 4K) com três painéis iguais, a mesma pintura repetida e só o rosto
## mudando, cada figura inteira dentro do painel com margem verde dos lados.
## Importar: tools/art/import_lideres_gemini.gd -- <folha> <líder> (os três
## saem com o mesmo tamanho e enquadramento, e avisa se algo encostou na borda).
## Os líderes vão mudar com as eras (estes são os da era antiga).
func _leader_themes(u: String) -> Array:
	var leaders := [
		["gregos", "a young Macedonian king in the image of Alexander the Great: about 25 years old, clean-shaven, thick wavy light-brown hair swept up and back from the forehead, intense eyes; an ornate bronze muscle cuirass with a lion head on the chest and leather straps (pteruges) at the shoulders, a deep red cloak pinned at one shoulder"],
		["romanos", "a Roman consul: about 50 years old, short grey hair, strong jaw, clean-shaven; a white toga with a broad purple border draped over a white tunic, a green laurel wreath on the head, a gold ring"],
		["egipcios", "an Egyptian pharaoh: a striped gold-and-blue nemes headdress with the golden cobra (uraeus) on the brow, a braided ceremonial false beard, eyes lined with kohl, a wide broad collar of gold and lapis beads on the bare chest, golden arm bands, holding a crook"],
		["fenicios", "a Carthaginian general in the image of Hannibal Barca: about 35 years old, dark curly hair and a short dark beard, weathered tanned face; bronze scale armour over a red tunic, a Tyrian-purple cloak, a bronze crested helmet held under one arm"],
		["americanos", "an American colonial leader of the 1700s: about 40 years old, hair tied back, a black tricorn hat, a dark blue colonial coat with brass buttons over a buff waistcoat and a white shirt with a simple cravat"],
		["ingleses", "a Celtic chieftain of ancient Britain: about 40 years old, long red-brown hair and a long braided moustache, a heavy twisted gold torc around the neck, a checked wool cloak in green and brown pinned with a big bronze brooch, bronze arm rings"],
	]
	var themes := []
	for leader: Array in leaders:
		themes.append({"name": "lider_" + leader[0], "what": "the SAME leader painted THREE times, side by side, with three facial expressions", "columns": 3, "cell": 200,
		"style_images": [u + "retratos/lanceiro", u + "retratos/arqueiro", u + "retratos/colono"],
		"no_current": true,
		"intro": """I am making the art of a 2D turn-based strategy game about ancient civilizations. The attached image shows three units already made for the game. It is ONLY the STYLE REFERENCE: paint in exactly this painted style, with the same detail, palette and light. Do not copy or include those units.

Create ONE WIDE IMAGE with %s. Each portrait is cut out and shown BIG on the diplomacy screen, so the image must be as LARGE as you can make it: landscape 16:9, at least 3072 x 1728 pixels (4K if possible). Never a small image.""",
		"style": """STYLE (copy it from the attached units):
- Detailed painted digital illustration with realistic proportions and a dignified, heroic look: soft painted shading, visible texture of skin, cloth and metal, rich but natural colors. Not cartoon, not chibi, not anime, not pixel art, no thick black outlines, not a photo.
- Soft daylight from the TOP-LEFT, the same in the three portraits.""",
		"camera": """LAYOUT AND FRAMING (very important, follow every point):
- The image is split into THREE EQUAL VERTICAL PANELS (left, middle, right), each one third of the width, on ONE flat solid green background (#00B140) with no lines between the panels.
- One portrait per panel, centered in its panel: the leader from the top of the head down to the WAIST, facing the viewer (turned very slightly, three-quarter).
- THE WHOLE FIGURE STAYS INSIDE ITS PANEL: hair, shoulders, arms, hands, cloak, cape, weapons and every piece of clothing. Keep a clear band of green of at least 6% of the panel width on the LEFT and on the RIGHT of each figure, and green above the head. The cloak hangs close to the body, it does not spread out to the sides. Nothing is cut by the edges of the image or touches the neighbouring portrait. Only the waist (the bottom of the figure) may touch the bottom edge.
- The figure is tall in its panel: the head near the top, the body filling about 85% of the height.
- The three portraits are THE SAME PAINTING repeated: exactly the same man, face shape, hair, clothes, cloak, jewellery, colors, size, position, pose and hands, as if copied and pasted. ONLY THE FACE (brows, eyes, mouth, cheeks) changes between them. The hands do not change.
- Exactly three people in the image, one per panel. No throne, no room, no landscape, no props apart from what the leader wears or holds. No text, no labels, no numbers, no frames.""",
		"items_title": "THE LEADER, " + leader[1] + ".\n\nTHE THREE PANELS, from left to right:",
		"items": [
			["brava", "", "LEFT panel, ANGRY (used when at war): brows lowered and drawn together, a hard glare straight at the viewer, jaw clenched, mouth tight and turned down."],
			["neutra", "", "MIDDLE panel, NEUTRAL (used in peace): calm, composed and dignified, a steady attentive look, mouth relaxed and closed."],
			["feliz", "", "RIGHT panel, HAPPY (used when the relation is good): a warm, confident smile that reaches the eyes (a little of the teeth may show), relaxed brows, cheeks slightly raised."],
		],
		"team_note": "COLORS: normal colors for skin, clothes and metal (no team color in these images).",
		"extra": "No text, no labels, no frames, no borders.",
		})
	return themes



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
	left.add_child(_picture(_style_sheet(theme["style_images"]) if theme.has("style_images") else _style, Vector2(420, 420)))
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
		if theme.get("no_current", false):
			break # sem desenho atual (Quadrirreme, líderes): só a referência de estilo
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
			var image: Image
			if item[1].begins_with("esquema:civ_"):
				image = _farm_patchwork(item[1].trim_prefix("esquema:"))
			elif item[1].begins_with("esquema:"):
				image = _farm_layout(item[1].trim_prefix("esquema:"))
			else:
				image = _tinted(item[1]) if theme.get("team_tint", false) else _load(item[1] + ".png")
			if theme.get("tile", false):
				image = _tiled(image, 2)
			inner.add_child(_picture(image, size))
			var name_label := _label("%d. %s" % [number, item[0]], 13)
			name_label.custom_minimum_size.x = size.x
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			inner.add_child(name_label)
		grid.add_child(card)
	if theme.get("no_current", false):
		right.free() # só a referência de estilo (o desenho atual atrapalhava: ver Quadrirreme)
	else:
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


## Referência de estilo de um pedido (theme "style_images"): as imagens lado a
## lado, na mesma altura, com a cor do time em azul, sobre o verde do fundo.
func _style_sheet(paths: Array) -> Image:
	var height := 400
	var images: Array[Image] = []
	var width := 0
	for path: String in paths:
		var image := _tinted(path)
		image.resize(maxi(1, roundi(image.get_width() * float(height) / image.get_height())), height, Image.INTERPOLATE_LANCZOS)
		images.append(image)
		width += image.get_width() + 20
	var sheet := Image.create(width + 20, height + 40, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(0, 177, 64))
	var x := 20
	for image in images:
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, 20))
		x += image.get_width() + 20
	return sheet


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
  09_fazendas           as 3 fazendas no estilo do Civilization VI
                        (mosaico de campos listrados, vinhedo, oliveiras,
                        cercas baixas; o verde entre os campos e na borda
                        fica transparente; sem casa).
                        Madeireira, mina e ferro já vieram bons (folha em
                        tools/art/gemini/melhorias_folha.png)
  10_tecnologias        16 ilustrações (4x4, opcional)
  11_terrenos_novos     águas profundas, selva (com palmeiras), deserto,
                        tundra e neve (5x1; no jogo, provisórias geradas
                        por tools/art/gen_terrenos_novos.gd)
  13 a 18 lider_*       os LÍDERES (gregos, romanos, egípcios, fenícios,
                        americanos, ingleses): UMA folha larga com os 3
                        retratos do mesmo líder (bravo, neutro, feliz),
                        da cintura para cima. Um pedido por líder, cada
                        um numa CONVERSA NOVA, com referencia.png. Peça a
                        maior resolução (3K/4K). Importar: ...
                        import_lideres_gemini.gd -- folha.png <líder>
  12_quadrirreme        o Quadrirreme, barco de guerra mais imponente que
                        a Galé (importar como avulsa: ...
                        import_folha_unidades.gd -- resultado.png
                        quadrirreme)
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


## Esquema do formato da fazenda (no lugar do desenho antigo, que ocupava a
## casa inteira): fundo verde, 4 canteiros 2x2 com a "cruz" e a margem vazias.
## [param kind]: "producao", "obra" ou "queimada" (cores dos canteiros).
func _farm_layout(kind: String) -> Image:
	var size := 160
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 177, 64))
	var colors: Array = {
		"producao": [Color8(214, 178, 72), Color8(88, 140, 60), Color8(128, 96, 60), Color8(200, 168, 70)],
		"obra": [Color8(120, 84, 52), Color8(112, 78, 48), Color8(120, 84, 52), Color8(112, 78, 48)],
		"queimada": [Color8(70, 56, 40), Color8(48, 44, 38), Color8(90, 70, 46), Color8(40, 36, 32)],
	}[kind]
	var margin := size / 8
	var gap := size / 8
	var plot := (size - margin * 2 - gap) / 2
	for i in 4:
		var origin := Vector2i(margin + (i % 2) * (plot + gap), margin + (i / 2) * (plot + gap))
		image.fill_rect(Rect2i(origin, Vector2i(plot, plot)), Color8(60, 40, 24))
		image.fill_rect(Rect2i(origin + Vector2i(2, 2), Vector2i(plot - 4, plot - 4)), colors[i])
		# Sulcos (linhas um pouco mais escuras)
		for y in range(origin.y + 6, origin.y + plot - 4, 6):
			image.fill_rect(Rect2i(origin.x + 3, y, plot - 6, 1), colors[i].darkened(0.25))
	return image


## Esquema do mosaico no estilo do Civilization VI: campos listrados de
## tamanhos diferentes, com direções alternadas, e o verde entre eles e na
## borda. [param kind]: "civ_producao", "civ_obra" ou "civ_queimada".
func _farm_patchwork(kind: String) -> Image:
	var size := 160
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 177, 64))
	# Campos: [retângulo, listras na horizontal?]
	var fields := [
		[Rect2i(18, 22, 58, 38), true], [Rect2i(82, 16, 60, 30), false], [Rect2i(82, 52, 62, 40), true],
		[Rect2i(14, 66, 36, 58), false], [Rect2i(56, 66, 20, 64), true], [Rect2i(82, 98, 56, 42), false],
	]
	var colors: Array = {
		"civ_producao": [Color8(214, 178, 72), Color8(168, 196, 92), Color8(70, 120, 52), Color8(120, 150, 60), Color8(200, 168, 70), Color8(90, 110, 50)],
		"civ_obra": [Color8(128, 92, 58), Color8(118, 84, 52), Color8(128, 92, 58), Color8(112, 80, 50), Color8(124, 88, 56), Color8(116, 82, 52)],
		"civ_queimada": [Color8(70, 56, 40), Color8(48, 44, 38), Color8(86, 66, 44), Color8(40, 36, 32), Color8(66, 52, 38), Color8(52, 46, 40)],
	}[kind]
	for i in fields.size():
		var r: Rect2i = fields[i][0]
		image.fill_rect(r, colors[i])
		var horizontal: bool = fields[i][1]
		if horizontal:
			for y in range(r.position.y + 3, r.end.y, 5):
				image.fill_rect(Rect2i(r.position.x, y, r.size.x, 2), colors[i].darkened(0.22))
		else:
			for x in range(r.position.x + 3, r.end.x, 5):
				image.fill_rect(Rect2i(x, r.position.y, 2, r.size.y), colors[i].darkened(0.22))
		# Cerca baixa no lado de baixo
		image.fill_rect(Rect2i(r.position.x, r.end.y - 2, r.size.x, 2), Color8(96, 66, 36))
	# Arvorezinhas nas quinas
	for c in [Vector2i(78, 62), Vector2i(52, 62), Vector2i(144, 96), Vector2i(16, 20)]:
		for y in range(-4, 5):
			for x in range(-4, 5):
				if x * x + y * y <= 16:
					image.set_pixelv(c + Vector2i(x, y), Color8(60, 92, 44) if kind != "civ_queimada" else Color8(40, 34, 28))
	return image


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
