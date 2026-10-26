extends SceneTree

## Desenho provisório da Galé (até chegar a arte do ChatGPT): barco a remo
## visto de lado, casco de madeira com proa curva, remos, mastro e vela
## quadrada listrada. As listras da vela e os escudos ficam na cor do jogador:
## pretos na imagem e brancos na máscara gale_time.png (Unit.team_texture soma
## a cor do jogador na proporção da máscara, sem franja nas bordas).
## Uso: godot --headless --path . --script tools/art/gale.gd
## Grava assets/sprites/units/gale.png e gale_time.png (80x80).

const SIZE := 80
## Desenha em escala maior e reduz no fim (bordas suaves).
const SCALE := 4
const OUT := "res://assets/sprites/units/gale.png"
const OUT_MASK := "res://assets/sprites/units/gale_time.png"

const OUTLINE := Color8(30, 20, 12)
const HULL := Color8(122, 74, 38)
const HULL_DARK := Color8(84, 50, 26)
const HULL_LIGHT := Color8(160, 104, 56)
const OAR := Color8(190, 150, 100)
const MAST := Color8(96, 62, 32)
const SAIL := Color8(236, 226, 200)
## Marca das áreas na cor do jogador (vira preto na imagem e branco na máscara).
const TEAM := Color(1, 0, 1)
const WATER := Color8(220, 235, 245)


var _mask: Image


func _initialize() -> void:
	var big := Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	big.fill(Color(0, 0, 0, 0))
	_mask = Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	_mask.fill(Color.BLACK)
	# Coordenadas em pixels da imagem final (0..80); _poly escala.
	# Remos (atrás do casco), inclinados para trás
	for i in 5:
		var x := 24.0 + i * 8.0
		_line(big, Vector2(x, 54), Vector2(x - 7, 70), 3.2, OUTLINE)
		_line(big, Vector2(x, 54), Vector2(x - 7, 70), 1.6, OAR)
	# Espuma onde os remos tocam a água
	for i in 5:
		_circle(big, Vector2(17.0 + i * 8.0, 70.5), 2.2, WATER)
	# Mastro
	_poly(big, [Vector2(38.5, 10), Vector2(41.5, 10), Vector2(41.5, 52), Vector2(38.5, 52)], OUTLINE, MAST)
	# Vela quadrada com listras na cor do time
	var sail := [Vector2(24, 14), Vector2(56, 14), Vector2(58, 40), Vector2(22, 40)]
	_poly(big, sail, OUTLINE, SAIL)
	for stripe in [[26.5, 33.5], [46.5, 53.5]]:
		var a: float = stripe[0]
		var b: float = stripe[1]
		_poly(big, [Vector2(a, 15.5), Vector2(b, 15.5), Vector2(b + 1.2, 38.5), Vector2(a - 1.2, 38.5)], TEAM, TEAM, false)
	# Verga (a vara que segura a vela)
	_poly(big, [Vector2(21, 12), Vector2(59, 12), Vector2(59, 15), Vector2(21, 15)], OUTLINE, MAST)
	# Casco: proa alta e curva à direita, popa à esquerda
	var hull := [Vector2(8, 46), Vector2(66, 46), Vector2(72, 40), Vector2(75, 33), Vector2(77, 36),
			Vector2(74, 46), Vector2(66, 57), Vector2(18, 57), Vector2(10, 52)]
	_poly(big, hull, OUTLINE, HULL)
	# Faixa escura na linha d'água e faixa clara na borda
	_poly(big, [Vector2(14, 53), Vector2(68, 53), Vector2(66, 56), Vector2(18, 56)], HULL_DARK, HULL_DARK, false)
	_poly(big, [Vector2(10, 47), Vector2(66, 47), Vector2(65, 49), Vector2(11, 49)], HULL_LIGHT, HULL_LIGHT, false)
	# Escudos na amurada (cor do time)
	for i in 5:
		_circle(big, Vector2(22.0 + i * 9.0, 49.5), 3.4, OUTLINE)
		_circle(big, Vector2(22.0 + i * 9.0, 49.5), 2.5, TEAM)
	# Olho na proa
	_circle(big, Vector2(68, 47), 1.6, OUTLINE)

	# Reduz pela metade duas vezes (média de 4x4 pixels: bordas suaves)
	for half in [SIZE * 2, SIZE]:
		big.resize(half, half, Image.INTERPOLATE_BILINEAR)
		_mask.resize(half, half, Image.INTERPOLATE_BILINEAR)
	_mask.convert(Image.FORMAT_L8)
	big.save_png(ProjectSettings.globalize_path(OUT))
	_mask.save_png(ProjectSettings.globalize_path(OUT_MASK))
	print("gravados " + OUT + " e " + OUT_MASK)
	quit()


## Polígono preenchido com contorno (pontos em pixels da imagem final).
func _poly(image: Image, points: Array, outline: Color, fill: Color, with_outline := true) -> void:
	var scaled := PackedVector2Array()
	for p: Vector2 in points:
		scaled.append(p * SCALE)
	var box := Rect2(scaled[0], Vector2.ZERO)
	for p in scaled:
		box = box.expand(p)
	var border := 1.2 * SCALE if with_outline else 0.0
	for y in range(int(box.position.y - border), int(box.end.y + border) + 1):
		for x in range(int(box.position.x - border), int(box.end.x + border) + 1):
			var point := Vector2(x + 0.5, y + 0.5)
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Geometry2D.is_point_in_polygon(point, scaled):
				_put(image, x, y, fill)
			elif with_outline and _distance_to_polygon(point, scaled) <= border:
				_put(image, x, y, outline)


func _distance_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		best = minf(best, point.distance_to(closest))
	return best


func _line(image: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	a *= SCALE
	b *= SCALE
	var half := width * SCALE / 2.0
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(half)
	for y in range(int(box.position.y), int(box.end.y) + 1):
		for x in range(int(box.position.x), int(box.end.x) + 1):
			var point := Vector2(x + 0.5, y + 0.5)
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= half:
				_put(image, x, y, color)


func _circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	center *= SCALE
	var r := radius * SCALE
	for y in range(int(center.y - r), int(center.y + r) + 1):
		for x in range(int(center.x - r), int(center.x + r) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				_put(image, x, y, color)


## Pinta o pixel; a cor TEAM vira preto na imagem e branco na máscara (e
## qualquer outra cor apaga a máscara ali: o que fica por cima não é do time).
func _put(image: Image, x: int, y: int, color: Color) -> void:
	if color == TEAM:
		image.set_pixel(x, y, Color.BLACK)
		_mask.set_pixel(x, y, Color.WHITE)
	else:
		image.set_pixel(x, y, color)
		_mask.set_pixel(x, y, Color.BLACK)
