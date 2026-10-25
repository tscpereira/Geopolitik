class_name Icons
extends RefCounted

## Ícones desenhados pelo código, usados no HUD e nas janelas: moeda de ouro
## e o ícone de cada construção e unidade (build_icon).

const GOLD_COLOR := Color8(255, 200, 40)
const GOLD_DARK := Color8(170, 115, 0)
const GOLD_LIGHT := Color8(255, 240, 160)

## Tamanho padrão dos ícones de construção nas janelas.
const ICON_SIZE := 24
const STONE_COLOR := Color8(235, 228, 205)
const STONE_SHADE := Color8(165, 155, 130)
const STEEL_COLOR := Color8(215, 222, 232)
const STEEL_SHADE := Color8(140, 150, 165)
const LEATHER_COLOR := Color8(110, 65, 30)
const WOOD_SHAFT_COLOR := Color8(165, 115, 60)
const CORN_COLOR := Color8(250, 205, 50)
const CORN_KERNEL_COLOR := Color8(215, 160, 20)
const HUSK_COLOR := Color8(90, 170, 60)
## Cor do texto do ferro (resumo da janela da cidade).
const IRON_COLOR := Color8(175, 190, 210)
## Bigorna: o ícone do ferro (no mapa, no HUD e nas janelas; tools/art/gen_art.gd).
const IRON_TEXTURE: Texture2D = preload("res://assets/sprites/resources/ferro.png")
## Marcador do ferro no mapa: tamanho (fração da casa) e fundo escuro redondo.
const IRON_MARKER_SIZE := 0.42
const IRON_MARKER_BACK := Color(0.08, 0.07, 0.06, 0.55)


## Ícone de uma construção ou unidade (City.Build) para pôr numa linha da
## janela. Não pega o mouse: o tooltip da linha continua funcionando.
## [param player_color] pinta o fundo das unidades (como no mapa).
static func build_icon(build: int, player_color: Color, size := ICON_SIZE) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * size
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # desenho suave, também pequeno
	icon.draw.connect(func() -> void:
		draw_build(icon, build, Rect2(Vector2.ZERO, icon.size), player_color))
	return icon


## Desenha o ícone de [param build] em [param rect]:
##   unidades        sprite da unidade (roupa na cor do jogador) sobre um
##                   quadrado escuro com borda na cor do jogador;
##   Fazenda         plantação (o mesmo desenho do mapa);
##   Madeireira      pilha de toras (o mesmo desenho do mapa);
##   Mina            boca da galeria na pedra (o mesmo desenho do mapa);
##   Prefeitura      prédio romano (frontão e colunas);
##   Quartel General espada;
##   Marcenaria      serrote;
##   Templo          zigurate com chama;
##   Muralha         trecho de muralha com ameias e portão;
##   Escola          pergaminho aberto com escrita e um estilete;
##   Biblioteca      estante de madeira cheia de rolos;
##   Mercado         barraca com toldo listrado e frutas no balcão;
##   Forja           bigorna (o ferro) com um martelo;
##   Arena           anfiteatro de pedra com dois andares de arcos;
##   armas           o desenho da arma (Lança: lança).
static func draw_build(canvas: CanvasItem, build: int, rect: Rect2, player_color: Color) -> void:
	var info: Dictionary = City.BUILDS[build]
	if info.has("unit"):
		var type: UnitType = info["unit"]
		canvas.draw_rect(rect, Color(0.16, 0.17, 0.2))
		canvas.draw_rect(rect, player_color, false, maxf(1.0, rect.size.x / 14.0))
		if type.sprite:
			canvas.draw_texture_rect(Unit.team_texture(type.sprite, player_color), rect, false)
		return
	match build:
		City.Build.FARM:
			City.draw_farm(canvas, rect)
		City.Build.LUMBER_MILL:
			LumberMill.draw_icon(canvas, rect)
		City.Build.MINE:
			City.draw_mine(canvas, rect)
		City.Build.CITY_HALL:
			draw_city_hall(canvas, rect)
		City.Build.HEADQUARTERS:
			draw_sword(canvas, rect)
		City.Build.CARPENTRY:
			draw_saw(canvas, rect)
		City.Build.TEMPLE:
			draw_temple(canvas, rect)
		City.Build.WALLS:
			draw_walls(canvas, rect)
		City.Build.SCHOOL:
			draw_school(canvas, rect)
		City.Build.LIBRARY:
			draw_library(canvas, rect)
		City.Build.MARKET:
			draw_market(canvas, rect)
		City.Build.FORGE:
			draw_forge(canvas, rect)
		City.Build.ARENA:
			draw_arena(canvas, rect)
	if info.has("weapon"):
		draw_weapon(canvas, info["weapon"], rect)


## Bigorna (o ferro) em [param rect].
static func draw_iron(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_texture_rect(IRON_TEXTURE, rect, false)


## Marca de ferro na casa [param cell_rect]: a bigorna sobre um fundo escuro
## redondo, no canto de cima à esquerda (fica visível com uma unidade na casa,
## cujo anel cobre a base, e não esbarra nas setas e no número de cidadãos da
## janela da cidade).
static func draw_iron_marker(canvas: CanvasItem, cell_rect: Rect2) -> void:
	var size := cell_rect.size * IRON_MARKER_SIZE
	var margin := cell_rect.size * 0.04
	var box := Rect2(cell_rect.position + margin, size)
	canvas.draw_circle(box.get_center(), size.x * 0.5, IRON_MARKER_BACK)
	draw_iron(canvas, box.grow(-size.x * 0.06))


## Ícone de uma arma do arsenal (também usado no painel Arsenal do HUD).
static func draw_weapon(canvas: CanvasItem, weapon: Arsenal.Weapon, rect: Rect2) -> void:
	match weapon:
		Arsenal.Weapon.SPEAR:
			draw_spear(canvas, rect)
		Arsenal.Weapon.SHORT_SWORD:
			draw_sword(canvas, rect.grow(-rect.size.x * 0.14)) # espada curta: a espada menor


## Lança na diagonal: cabo de madeira comprido e ponta de aço em folha.
static func draw_spear(canvas: CanvasItem, rect: Rect2) -> void:
	var w := rect.size.x
	var length := w * 1.3
	var line := maxf(1.0, w / 24.0)
	var shaft := maxf(1.5, w * 0.07)
	canvas.draw_set_transform(rect.get_center(), PI / 4.0, Vector2.ONE)
	var tip := -length / 2.0
	var head_base := tip + length * 0.28
	# Cabo
	_draw_block(canvas, Rect2(-shaft / 2.0, head_base, shaft, length / 2.0 - head_base), WOOD_SHAFT_COLOR, line)
	# Ponta em forma de folha
	var head := PackedVector2Array([Vector2(0, tip), Vector2(w * 0.11, tip + length * 0.16),
			Vector2(0, head_base), Vector2(-w * 0.11, tip + length * 0.16), Vector2(0, tip)])
	canvas.draw_colored_polygon(head, STEEL_COLOR)
	canvas.draw_line(Vector2(0, tip + line * 2.0), Vector2(0, head_base - line), STEEL_SHADE, line)
	canvas.draw_polyline(head, Color.BLACK, line)
	# Amarração entre a ponta e o cabo
	_draw_block(canvas, Rect2(-shaft * 0.9, head_base, shaft * 1.8, length * 0.05), LEATHER_COLOR, line)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Serrote de marceneiro: lâmina de aço com dentes embaixo e cabo de madeira.
static func draw_saw(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	# Lâmina: mais alta perto do cabo, afinando para a ponta
	var top_left := o + Vector2(w * 0.32, h * 0.3)
	var blade := PackedVector2Array([top_left, o + Vector2(w * 0.95, h * 0.52),
			o + Vector2(w * 0.95, h * 0.66), o + Vector2(w * 0.32, h * 0.72), top_left])
	canvas.draw_colored_polygon(blade, STEEL_COLOR)
	# Dentes na borda de baixo
	var teeth := 6
	for i in teeth:
		var a := o + Vector2(w * (0.34 + 0.6 * i / teeth), h * (0.72 - 0.06 * i / teeth))
		var b := o + Vector2(w * (0.34 + 0.6 * (i + 1) / teeth), h * (0.72 - 0.06 * (i + 1) / teeth))
		var point := (a + b) / 2.0 + Vector2(0, h * 0.07)
		canvas.draw_colored_polygon(PackedVector2Array([a, point, b]), STEEL_SHADE)
	canvas.draw_polyline(blade, Color.BLACK, line)
	# Cabo com um furo para a mão
	var handle := Rect2(o + Vector2(w * 0.06, h * 0.26), Vector2(w * 0.28, h * 0.5))
	_draw_block(canvas, handle, WOOD_SHAFT_COLOR, line)
	_draw_block(canvas, Rect2(handle.position + handle.size * Vector2(0.3, 0.25), handle.size * Vector2(0.4, 0.4)),
			Color(0.1, 0.1, 0.12), line)


## Prédio romano: frontão triangular, colunas e degraus de pedra clara.
static func draw_city_hall(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	var roof := PackedVector2Array([o + Vector2(w * 0.5, h * 0.06), o + Vector2(w * 0.96, h * 0.32),
			o + Vector2(w * 0.04, h * 0.32), o + Vector2(w * 0.5, h * 0.06)])
	canvas.draw_colored_polygon(roof, STONE_COLOR)
	canvas.draw_polyline(roof, Color.BLACK, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.08, h * 0.32), Vector2(w * 0.84, h * 0.1)), STONE_SHADE, line)
	for i in 4:
		var x := w * (0.14 + i * 0.2)
		_draw_block(canvas, Rect2(o + Vector2(x, h * 0.42), Vector2(w * 0.12, h * 0.38)), STONE_COLOR, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.06, h * 0.8), Vector2(w * 0.88, h * 0.07)), STONE_SHADE, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.02, h * 0.87), Vector2(w * 0.96, h * 0.09)), STONE_COLOR, line)


## Templo: zigurate de degraus de pedra com um santuário e uma chama no topo.
static func draw_temple(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	# Três degraus, do mais largo (embaixo) ao mais estreito
	for i in 3:
		_draw_block(canvas, Rect2(o + Vector2(w * (0.04 + i * 0.1), h * (0.8 - i * 0.16)), Vector2(w * (0.92 - i * 0.2), h * 0.16)),
				STONE_COLOR if i % 2 == 0 else STONE_SHADE, line)
	# Escadaria no meio
	_draw_block(canvas, Rect2(o + Vector2(w * 0.43, h * 0.48), Vector2(w * 0.14, h * 0.48)), STONE_SHADE.darkened(0.15), line)
	# Santuário com porta escura
	_draw_block(canvas, Rect2(o + Vector2(w * 0.34, h * 0.31), Vector2(w * 0.32, h * 0.17)), STONE_COLOR, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.45, h * 0.36), Vector2(w * 0.1, h * 0.12)), Color(0.12, 0.1, 0.1), line)
	# Chama
	var flame := PackedVector2Array([o + Vector2(w * 0.5, h * 0.03), o + Vector2(w * 0.6, h * 0.19),
			o + Vector2(w * 0.55, h * 0.3), o + Vector2(w * 0.45, h * 0.3), o + Vector2(w * 0.4, h * 0.19), o + Vector2(w * 0.5, h * 0.03)])
	canvas.draw_colored_polygon(flame, Color8(255, 150, 30))
	canvas.draw_circle(o + Vector2(w * 0.5, h * 0.22), w * 0.04, Color8(255, 230, 120))
	canvas.draw_polyline(flame, Color.BLACK, line)


## Muralha: trecho de muro de pedra com ameias, duas torres e um portão.
static func draw_walls(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	# Muro do meio, com ameias
	_draw_block(canvas, Rect2(o + Vector2(w * 0.2, h * 0.42), Vector2(w * 0.6, h * 0.5)), STONE_SHADE, line)
	for i in 3:
		_draw_block(canvas, Rect2(o + Vector2(w * (0.26 + i * 0.18), h * 0.32), Vector2(w * 0.1, h * 0.1)), STONE_SHADE, line)
	# Torres dos lados, mais altas, com ameias
	for x in [0.04, 0.74]:
		_draw_block(canvas, Rect2(o + Vector2(w * x, h * 0.22), Vector2(w * 0.22, h * 0.7)), STONE_COLOR, line)
		_draw_block(canvas, Rect2(o + Vector2(w * x, h * 0.1), Vector2(w * 0.07, h * 0.12)), STONE_COLOR, line)
		_draw_block(canvas, Rect2(o + Vector2(w * (x + 0.15), h * 0.1), Vector2(w * 0.07, h * 0.12)), STONE_COLOR, line)
	# Portão em arco
	var gate := PackedVector2Array([o + Vector2(w * 0.4, h * 0.92), o + Vector2(w * 0.4, h * 0.66),
			o + Vector2(w * 0.5, h * 0.56), o + Vector2(w * 0.6, h * 0.66), o + Vector2(w * 0.6, h * 0.92)])
	canvas.draw_colored_polygon(gate, Color(0.12, 0.1, 0.1))
	gate.append(gate[0])
	canvas.draw_polyline(gate, Color.BLACK, line)


## Escola: pergaminho aberto com linhas de escrita e um estilete.
static func draw_school(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	var parchment := Color8(236, 220, 176)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.14, h * 0.2), Vector2(w * 0.72, h * 0.56)), parchment, line)
	for x in [0.08, 0.86]:
		_draw_block(canvas, Rect2(o + Vector2(w * x, h * 0.16), Vector2(w * 0.08, h * 0.64)), Color8(196, 170, 120), line)
	for i in 4:
		var y := h * (0.31 + i * 0.11)
		canvas.draw_line(o + Vector2(w * 0.22, y), o + Vector2(w * (0.72 if i < 3 else 0.5), y), Color8(80, 60, 40), line)
	canvas.draw_line(o + Vector2(w * 0.5, h * 0.94), o + Vector2(w * 0.9, h * 0.6), Color.BLACK, line * 3.0)
	canvas.draw_line(o + Vector2(w * 0.5, h * 0.94), o + Vector2(w * 0.9, h * 0.6), WOOD_SHAFT_COLOR, line * 1.6)


## Biblioteca: estante de madeira com rolos de pergaminho deitados.
static func draw_library(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.08, h * 0.08), Vector2(w * 0.84, h * 0.86)), LEATHER_COLOR, line)
	for row in 3:
		var y := h * (0.12 + row * 0.27)
		_draw_block(canvas, Rect2(o + Vector2(w * 0.14, y), Vector2(w * 0.72, h * 0.22)), Color8(60, 36, 20), line)
		for k in 3:
			var center := o + Vector2(w * (0.27 + k * 0.23), y + h * 0.11)
			canvas.draw_circle(center, w * 0.095 + line, Color.BLACK)
			canvas.draw_circle(center, w * 0.095, Color8(236, 220, 176))
			canvas.draw_circle(center, w * 0.03, Color8(160, 130, 90))


## Mercado: barraca com toldo listrado e frutas no balcão.
static func draw_market(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	for x in [0.12, 0.82]:
		_draw_block(canvas, Rect2(o + Vector2(w * x, h * 0.3), Vector2(w * 0.06, h * 0.62)), WOOD_SHAFT_COLOR, line)
	for i in 5:
		var stripe := Rect2(o + Vector2(w * (0.06 + i * 0.176), h * 0.12), Vector2(w * 0.176, h * 0.2))
		canvas.draw_rect(stripe, Color8(200, 50, 40) if i % 2 == 0 else Color8(240, 230, 210))
		var tooth := PackedVector2Array([stripe.position + Vector2(0, stripe.size.y), stripe.end,
				stripe.position + Vector2(stripe.size.x * 0.5, stripe.size.y * 1.45)])
		canvas.draw_colored_polygon(tooth, Color8(200, 50, 40) if i % 2 == 0 else Color8(240, 230, 210))
	canvas.draw_rect(Rect2(o + Vector2(w * 0.06, h * 0.12), Vector2(w * 0.88, h * 0.2)), Color.BLACK, false, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.1, h * 0.66), Vector2(w * 0.8, h * 0.14)), Color8(140, 96, 52), line)
	var fruits := [Color8(230, 140, 30), Color8(120, 170, 50), Color8(190, 40, 40), Color8(230, 140, 30)]
	for i in 4:
		var center := o + Vector2(w * (0.24 + i * 0.17), h * 0.6)
		canvas.draw_circle(center, w * 0.07 + line * 0.7, Color.BLACK)
		canvas.draw_circle(center, w * 0.07, fruits[i])


## Forja: a bigorna do ferro com um martelo por cima.
static func draw_forge(canvas: CanvasItem, rect: Rect2) -> void:
	var w := rect.size.x
	var line := maxf(1.0, w / 24.0)
	draw_iron(canvas, rect.grow(-w * 0.04))
	var o := rect.position
	canvas.draw_line(o + Vector2(w * 0.3, w * 0.5), o + Vector2(w * 0.72, w * 0.08), Color.BLACK, line * 3.0)
	canvas.draw_line(o + Vector2(w * 0.3, w * 0.5), o + Vector2(w * 0.72, w * 0.08), WOOD_SHAFT_COLOR, line * 1.7)
	canvas.draw_set_transform(o + Vector2(w * 0.72, w * 0.1), -PI / 4.0, Vector2.ONE)
	_draw_block(canvas, Rect2(-w * 0.16, -w * 0.07, w * 0.32, w * 0.14), STEEL_SHADE, line)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Arena: anfiteatro de pedra com dois andares de arcos escuros.
static func draw_arena(canvas: CanvasItem, rect: Rect2) -> void:
	var o := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var line := maxf(1.0, w / 24.0)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.04, h * 0.2), Vector2(w * 0.92, h * 0.72)), STONE_COLOR, line)
	_draw_block(canvas, Rect2(o + Vector2(w * 0.04, h * 0.2), Vector2(w * 0.92, h * 0.08)), STONE_SHADE, line)
	for floor_index in 2:
		var top := h * (0.32 + floor_index * 0.3)
		for k in 4:
			var x := w * (0.11 + k * 0.215)
			var arch := PackedVector2Array([o + Vector2(x, top + h * 0.24), o + Vector2(x, top + h * 0.08),
					o + Vector2(x + w * 0.07, top), o + Vector2(x + w * 0.14, top + h * 0.08), o + Vector2(x + w * 0.14, top + h * 0.24)])
			canvas.draw_colored_polygon(arch, Color(0.15, 0.12, 0.1))


## Rosto de um cidadão (bem-estar social): feliz (dourado, sorrindo), contente
## (bege, boca reta) ou infeliz (vermelho, boca para baixo).
static func draw_face(canvas: CanvasItem, center: Vector2, radius: float, mood: City.Mood) -> void:
	var color: Color = {City.Mood.HAPPY: City.HAPPY_COLOR, City.Mood.CONTENT: City.CONTENT_COLOR,
			City.Mood.UNHAPPY: City.UNHAPPY_COLOR}[mood]
	var line := maxf(1.0, radius / 5.0)
	canvas.draw_circle(center, radius + line * 0.6, Color.BLACK)
	canvas.draw_circle(center, radius, color)
	var eye := radius * 0.14
	canvas.draw_circle(center + Vector2(-radius * 0.35, -radius * 0.25), eye, Color.BLACK)
	canvas.draw_circle(center + Vector2(radius * 0.35, -radius * 0.25), eye, Color.BLACK)
	match mood:
		City.Mood.HAPPY:
			canvas.draw_arc(center + Vector2(0, radius * 0.05), radius * 0.5, PI * 0.15, PI * 0.85, 8, Color.BLACK, line)
		City.Mood.CONTENT:
			canvas.draw_line(center + Vector2(-radius * 0.38, radius * 0.38), center + Vector2(radius * 0.38, radius * 0.38), Color.BLACK, line)
		City.Mood.UNHAPPY:
			canvas.draw_arc(center + Vector2(0, radius * 0.75), radius * 0.45, PI * 1.2, PI * 1.8, 8, Color.BLACK, line)


## Espada na diagonal: lâmina de aço, guarda e pomo dourados, cabo de couro.
static func draw_sword(canvas: CanvasItem, rect: Rect2) -> void:
	var w := rect.size.x
	var length := w * 1.15
	var half_blade := w * 0.075
	var guard_y := length * 0.12
	var line := maxf(1.0, w / 24.0)
	# Desenha a espada de pé, centrada, e gira 45° (ponta para cima e à direita)
	canvas.draw_set_transform(rect.get_center(), PI / 4.0, Vector2.ONE)
	var tip := -length / 2.0
	var blade := PackedVector2Array([Vector2(-half_blade, guard_y), Vector2(-half_blade, tip + half_blade * 2.5),
			Vector2(0, tip), Vector2(half_blade, tip + half_blade * 2.5), Vector2(half_blade, guard_y),
			Vector2(-half_blade, guard_y)])
	canvas.draw_colored_polygon(blade, STEEL_COLOR)
	canvas.draw_line(Vector2(0, guard_y), Vector2(0, tip + half_blade * 3.0), STEEL_SHADE, maxf(1.0, half_blade * 0.6))
	canvas.draw_polyline(blade, Color.BLACK, line)
	_draw_block(canvas, Rect2(-length * 0.18, guard_y, length * 0.36, length * 0.065), GOLD_COLOR, line)
	_draw_block(canvas, Rect2(-half_blade * 0.75, guard_y + length * 0.065, half_blade * 1.5, length * 0.2), LEATHER_COLOR, line)
	var pommel := Vector2(0, guard_y + length * 0.3)
	canvas.draw_circle(pommel, half_blade * 1.3 + line, Color.BLACK)
	canvas.draw_circle(pommel, half_blade * 1.3, GOLD_COLOR)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Espiga de milho: grãos amarelos com palha verde dos lados, de baixo para
## cima. A espiga ocupa o meio de [param rect] (para um número em cima dela).
static func draw_corn(canvas: CanvasItem, rect: Rect2) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var center := rect.get_center() - Vector2(0, h * 0.04)
	var radius := Vector2(w * 0.27, h * 0.42)
	var line := maxf(1.0, w / 30.0)
	# Espiga (elipse)
	var ear := PackedVector2Array()
	for i in 25:
		var angle := TAU * i / 24.0
		ear.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_colored_polygon(ear, CORN_COLOR)
	# Grãos: fileiras de pontinhos mais escuros dentro da espiga
	var kernel := maxf(1.0, w / 26.0)
	for row in range(-4, 5):
		var y := center.y + row * radius.y * 0.2
		var row_half := radius.x * sqrt(maxf(0.0, 1.0 - pow((y - center.y) / radius.y, 2.0)))
		for column in range(-2, 3):
			var x := center.x + column * radius.x * 0.38
			if absf(x - center.x) < row_half - kernel:
				canvas.draw_circle(Vector2(x, y), kernel, CORN_KERNEL_COLOR)
	canvas.draw_polyline(ear, Color.BLACK, line)
	# Palha: duas folhas verdes saindo de baixo, abraçando a espiga
	var base := Vector2(center.x, rect.end.y - h * 0.02)
	for side in [-1.0, 1.0]:
		var leaf := PackedVector2Array([base,
				Vector2(center.x + side * w * 0.42, center.y + h * 0.1),
				Vector2(center.x + side * w * 0.3, center.y - h * 0.22),
				Vector2(center.x + side * w * 0.12, center.y + h * 0.3), base])
		canvas.draw_colored_polygon(leaf, HUSK_COLOR)
		canvas.draw_polyline(leaf, Color.BLACK, line)


## Cor da ciência (HUD, janela da cidade e janela de pesquisa).
const SCIENCE_COLOR := Color8(110, 200, 255)


## Ciência: frasco de laboratório (erlenmeyer) com líquido azul e bolhas.
static func draw_science(canvas: CanvasItem, rect: Rect2) -> void:
	var s := rect.size
	var o := rect.position
	var line := maxf(1.0, s.x / 14.0)
	var neck_left := o.x + s.x * 0.4
	var neck_right := o.x + s.x * 0.6
	var top := o.y + s.y * 0.1
	var shoulder := o.y + s.y * 0.42
	var bottom := o.y + s.y * 0.9
	var glass := PackedVector2Array([
		Vector2(neck_left, top), Vector2(neck_right, top), Vector2(neck_right, shoulder),
		Vector2(o.x + s.x * 0.88, bottom), Vector2(o.x + s.x * 0.12, bottom), Vector2(neck_left, shoulder),
	])
	canvas.draw_colored_polygon(glass, Color(0.9, 0.95, 1.0, 0.85))
	# Líquido: a parte de baixo do frasco
	var level := o.y + s.y * 0.6
	var t := (level - shoulder) / (bottom - shoulder)
	var liquid := PackedVector2Array([
		Vector2(lerpf(neck_left, o.x + s.x * 0.12, t), level), Vector2(lerpf(neck_right, o.x + s.x * 0.88, t), level),
		Vector2(o.x + s.x * 0.88, bottom), Vector2(o.x + s.x * 0.12, bottom),
	])
	canvas.draw_colored_polygon(liquid, SCIENCE_COLOR)
	canvas.draw_circle(Vector2(o.x + s.x * 0.45, o.y + s.y * 0.75), s.x * 0.06, Color.WHITE)
	canvas.draw_circle(Vector2(o.x + s.x * 0.58, o.y + s.y * 0.68), s.x * 0.04, Color.WHITE)
	var outline := glass.duplicate()
	outline.append(glass[0])
	canvas.draw_polyline(outline, Color.BLACK, line)
	# Boca do frasco
	canvas.draw_line(Vector2(neck_left - s.x * 0.05, top), Vector2(neck_right + s.x * 0.05, top), Color.BLACK, line * 1.5)


## Retângulo preenchido com contorno preto.
static func _draw_block(canvas: CanvasItem, block: Rect2, color: Color, line: float) -> void:
	canvas.draw_rect(block, color)
	canvas.draw_rect(block, Color.BLACK, false, line)

## Texturas de moeda já desenhadas, por tamanho.
static var _coins := {}


## Moeda de ouro de [param size] x [param size] pixels: disco dourado com
## borda escura, um anel interno e um brilho no canto.
static func gold_coin(size := 20) -> Texture2D:
	if _coins.has(size):
		return _coins[size]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) / 2.0
	var radius := size / 2.0 - 0.5
	for y in size:
		for x in size:
			var distance := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center)
			if distance > radius:
				continue
			var color := GOLD_COLOR
			if distance > radius - maxf(1.0, size / 10.0):
				color = GOLD_DARK # borda
			elif absf(distance - radius * 0.62) < maxf(0.6, size / 24.0):
				color = GOLD_DARK.lightened(0.25) # anel interno
			image.set_pixel(x, y, color)
	# Brilho no canto superior esquerdo
	var shine := Vector2i(roundi(size * 0.32), roundi(size * 0.3))
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
		image.set_pixelv(shine + offset, GOLD_LIGHT)
	_coins[size] = ImageTexture.create_from_image(image)
	return _coins[size]
