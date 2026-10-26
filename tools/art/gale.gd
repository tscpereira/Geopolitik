extends SceneTree

## Desenho da Galé, feito por código a partir do modelo trazido pelo usuário
## (25/10/2026: barco longo de casco escuro de tábuas, cabeça de animal
## entalhada na popa, proa alta e curva com aríete de bronze, vela quadrada
## com listras verticais presa numa verga com cordas, escudos redondos na
## amurada e remos saindo por furos, inclinados para trás). Simplificado para
## 80x80. As listras da vela e os escudos ficam na cor do jogador: pretos na
## imagem e brancos na máscara gale_time.png (Unit.team_texture soma a cor do
## jogador na proporção da máscara, sem franja nas bordas).
## Uso: godot --headless --path . --script tools/art/gale.gd
## Grava assets/sprites/units/gale.png e gale_time.png (80x80).

const SIZE := 80
## Desenha em escala maior e reduz no fim (bordas suaves).
const SCALE := 4
const OUT := "res://assets/sprites/units/gale.png"
const OUT_MASK := "res://assets/sprites/units/gale_time.png"

const OUTLINE := Color8(28, 22, 16)
const HULL := Color8(104, 80, 56)
const HULL_DARK := Color8(72, 55, 38)
const HULL_LIGHT := Color8(138, 108, 76)
const PLANK := Color8(58, 44, 30)
const OAR := Color8(150, 118, 78)
const MAST := Color8(110, 82, 52)
const ROPE := Color8(70, 56, 40)
const SAIL := Color8(238, 234, 222)
const SAIL_SHADE := Color8(208, 204, 192)
const BRONZE := Color8(214, 168, 60)
## Marca das áreas na cor do jogador (vira preto na imagem e branco na máscara).
const TEAM := Color(1, 0, 1)


var _mask: Image


func _initialize() -> void:
	var big := Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	big.fill(Color(0, 0, 0, 0))
	_mask = Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	_mask.fill(Color.BLACK)
	# Coordenadas em pixels da imagem final (0..80).
	# Remos de trás (mais escuros, por baixo do casco)
	for i in 5:
		var x := 25.0 + i * 9.0
		_line(big, Vector2(x + 2, 55), Vector2(x - 6, 69), 2.6, OUTLINE)
		_line(big, Vector2(x + 2, 55), Vector2(x - 6, 69), 1.2, HULL_DARK)
	# Cordas do mastro até as pontas da verga e até a proa e a popa
	for target in [Vector2(20, 14), Vector2(60, 14), Vector2(10, 40), Vector2(72, 40)]:
		_line(big, Vector2(40, 7), target, 0.9, ROPE)
	# Mastro
	_poly(big, [Vector2(38.8, 6), Vector2(41.2, 6), Vector2(41.2, 50), Vector2(38.8, 50)], OUTLINE, MAST)
	# Vela: quadrada, um pouco estufada, com 3 listras na cor do time
	var sail := [Vector2(22, 15), Vector2(58, 15), Vector2(60, 28), Vector2(58, 41), Vector2(24, 40), Vector2(22, 28)]
	_poly(big, sail, OUTLINE, SAIL)
	_poly(big, [Vector2(24, 34), Vector2(58, 34), Vector2(58, 40), Vector2(24, 39)], SAIL_SHADE, SAIL_SHADE, false)
	for stripe in [[28.0, 34.0], [40.0, 46.0], [52.0, 57.5]]:
		var a: float = stripe[0]
		var b: float = stripe[1]
		_poly(big, [Vector2(a, 16), Vector2(b, 16), Vector2(b + 0.4, 39.5), Vector2(a + 0.4, 39.5)], TEAM, TEAM, false)
	# Verga, com as amarrações
	_poly(big, [Vector2(19, 13), Vector2(61, 13), Vector2(61, 15.6), Vector2(19, 15.6)], OUTLINE, MAST)
	# Casco: comprido e curvo; popa à esquerda (sobe até a cabeça de animal) e
	# proa à direita (poste alto e curvo)
	var hull := [Vector2(6, 38), Vector2(10, 37), Vector2(13, 44), Vector2(68, 44), Vector2(72, 37),
			Vector2(74, 30), Vector2(77, 31), Vector2(76, 42), Vector2(70, 54), Vector2(62, 59),
			Vector2(22, 59), Vector2(12, 54), Vector2(7, 46)]
	_poly(big, hull, OUTLINE, HULL)
	# Tábuas (linhas escuras ao longo do casco) e a faixa clara da amurada
	_poly(big, [Vector2(12, 44.5), Vector2(69, 44.5), Vector2(68.5, 46.5), Vector2(12.5, 46.5)], HULL_LIGHT, HULL_LIGHT, false)
	for y in [50.0, 54.0]:
		_line(big, Vector2(12 + (y - 50) * 0.8, y), Vector2(70 - (y - 50) * 1.6, y), 0.8, PLANK)
	_poly(big, [Vector2(16, 56.5), Vector2(66, 56.5), Vector2(62, 58.5), Vector2(22, 58.5)], HULL_DARK, HULL_DARK, false)
	# Cabeça de animal entalhada na popa
	_poly(big, [Vector2(4, 37), Vector2(6, 32), Vector2(10, 31), Vector2(13, 33), Vector2(12, 36),
			Vector2(9, 36), Vector2(8, 39)], OUTLINE, HULL_LIGHT)
	_circle(big, Vector2(9.5, 33.2), 0.8, OUTLINE)
	# Aríete de bronze na proa, na linha d'água
	_poly(big, [Vector2(68, 54), Vector2(79, 56.5), Vector2(67, 58.5)], OUTLINE, BRONZE)
	# Escudos redondos na amurada (cor do time, com o centro de bronze)
	for i in 4:
		var center := Vector2(30.0 + i * 8.5, 42.5)
		_circle(big, center, 3.6, OUTLINE)
		_circle(big, center, 2.8, TEAM)
		_circle(big, center, 0.9, BRONZE)
	# Furos dos remos e os remos da frente (claros), inclinados para trás
	for i in 5:
		var hole := Vector2(26.0 + i * 9.0, 50)
		_circle(big, hole, 1.7, OUTLINE)
		var blade := hole + Vector2(-9, 17)
		_line(big, hole, blade, 2.8, OUTLINE)
		_line(big, hole, blade, 1.3, OAR)
		_poly(big, [blade + Vector2(-1.2, -2.5), blade + Vector2(1.8, -1.5), blade + Vector2(0.4, 3), blade + Vector2(-2.2, 2)],
				OUTLINE, OAR)

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
