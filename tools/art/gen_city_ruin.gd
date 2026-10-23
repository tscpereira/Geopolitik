extends SceneTree

## Gera assets/sprites/improvements/cidade_destruida.png (40x40, pixel art):
## muralha de pedra quebrada, torre caída, entulho, vigas queimadas, brasas e
## fumaça.

const S := 40
var img: Image
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	img = Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	rng.seed = 23
	city()
	img.save_png("res://assets/sprites/improvements/cidade_destruida.png")
	print("ok")
	quit()


func put(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= S or y >= S:
		return
	if c.a < 1.0:
		var under := img.get_pixel(x, y)
		if under.a > 0.0:
			c = Color(under.lerp(Color(c, 1.0), c.a), maxf(under.a, c.a))
	img.set_pixel(x, y, c)


func disc(cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				put(x, y, c)


func thick_line(a: Vector2, b: Vector2, r: float, c: Color) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		disc(p.x, p.y, r, c)


## Bloco de pedra com luz em cima e sombra embaixo.
func stone(x: int, y: int, w: int, h: int, base: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var c := base.darkened(rng.randf() * 0.12)
			if yy == y:
				c = c.lightened(0.18)
			elif yy == y + h - 1 or xx == x + w - 1:
				c = c.darkened(0.25)
			put(xx, yy, c)


func outline(c: Color) -> void:
	var copy := img.duplicate()
	for y in S:
		for x in S:
			if copy.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < S and n.y < S and copy.get_pixelv(n).a > 0.5:
					img.set_pixel(x, y, c)
					break


func city() -> void:
	var rock := Color8(150, 144, 132)
	var dark_rock := Color8(112, 106, 98)
	# Chão de entulho e cinza
	for y in S:
		for x in S:
			var d := Vector2((x + 0.5 - 20.0) / 17.0, (y + 0.5 - 33.0) / 5.0).length() + rng.randf() * 0.15
			if d < 1.0:
				put(x, y, Color8(92, 82, 70).darkened(rng.randf() * 0.3))
	# Muralha da esquerda: alta e quebrada em degraus
	var heights := [21, 21, 18, 12, 9, 5]
	for i in heights.size():
		var top: int = 30 - heights[i]
		var y := 30
		while y > top:
			stone(4 + i * 3, y - 3, 3, 3, rock if (i + y) % 2 == 0 else dark_rock)
			y -= 3
	# Torre da direita: só a base, com uma brecha
	for row in 5:
		for col in 4:
			if (row == 0 and col == 1) or (row == 4 and col % 2 == 1) or (row == 3 and col == 3):
				continue # brecha
			stone(25 + col * 3, 28 - row * 3, 3, 3, rock if (row + col) % 2 == 0 else dark_rock)
	# Pedras caídas na frente
	for p in [Vector2i(14, 32), Vector2i(18, 33), Vector2i(21, 31), Vector2i(10, 34), Vector2i(27, 33), Vector2i(31, 31)]:
		stone(p.x, p.y, 3, 2, dark_rock)
	# Vigas queimadas cruzadas no meio
	thick_line(Vector2(17, 24), Vector2(24, 31), 1.0, Color8(52, 36, 26))
	thick_line(Vector2(23, 23), Vector2(18, 31), 1.0, Color8(40, 28, 22))
	outline(Color(0.06, 0.05, 0.05, 0.95))
	# Brasas
	for e in [Vector2i(18, 24), Vector2i(20, 27), Vector2i(23, 28), Vector2i(16, 21), Vector2i(29, 26)]:
		put(e.x, e.y, Color8(240, 120, 35))
	for e in [Vector2i(19, 25), Vector2i(21, 26)]:
		put(e.x, e.y, Color8(255, 214, 90))
	# Duas colunas de fumaça
	for base in [Vector2(19.0, 22.0), Vector2(29.0, 22.0)]:
		for i in 14:
			var t := i / 13.0
			var p: Vector2 = base + Vector2(sin(t * 5.0) * 2.5 + t * 3.0, -t * 20.0)
			disc(p.x, p.y, 1.2 + t * 2.2, Color(0.75, 0.75, 0.75, 0.4 - t * 0.22))
