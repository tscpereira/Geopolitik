extends SceneTree

## Gera os sprites de melhoria destruída (40x40, pixel art):
##   assets/sprites/improvements/fazenda_destruida.png
##   assets/sprites/improvements/madeireira_destruida.png

const S := 40
var img: Image
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/sprites/improvements")
	farm()
	img.save_png("res://assets/sprites/improvements/fazenda_destruida.png")
	mill()
	img.save_png("res://assets/sprites/improvements/madeireira_destruida.png")
	print("ok")
	quit()


func new_image() -> void:
	img = Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))


func put(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
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


## Contorno escuro de 1 pixel em volta do desenho (estilo dos outros sprites).
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


func inside_field(x: float, y: float) -> bool:
	# Retângulo de cantos redondos, com a borda um pouco ondulada
	var half := Vector2(16.0, 14.0)
	var radius := 6.0
	var p := Vector2(x - 20.0, y - 21.0)
	var angle := p.angle()
	half += Vector2.ONE * sin(angle * 5.0 + 1.3) * 0.8
	var q := Vector2(absf(p.x), absf(p.y)) - (half - Vector2.ONE * radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() <= radius


## Fazenda pilhada: campo queimado (terra escura, manchas de cinza e de
## carvão), fileiras quebradas, cerca viva chamuscada com falhas, mourões
## caídos, brasas e um fio de fumaça.
func farm() -> void:
	new_image()
	rng.seed = 7
	var soil := Color8(78, 55, 38)
	var burnt := Color8(38, 30, 26)
	var ash := Color8(128, 122, 114)
	var hedge := Color8(62, 58, 34)
	for y in S:
		for x in S:
			if not inside_field(x + 0.5, y + 0.5):
				continue
			var edge := not (inside_field(x + 2.5, y + 0.5) and inside_field(x - 1.5, y + 0.5)
					and inside_field(x + 0.5, y + 2.5) and inside_field(x + 0.5, y - 1.5))
			if edge:
				# Cerca viva queimada, com buracos
				if rng.randf() < 0.22:
					continue
				put(x, y, hedge.darkened(rng.randf() * 0.35))
			else:
				put(x, y, soil.darkened(rng.randf() * 0.18))
	# Manchas de carvão e de cinza
	for spot in [Vector3(13, 16, 4.5), Vector3(26, 25, 5.0), Vector3(22, 13, 3.0), Vector3(11, 27, 3.0)]:
		for y in range(int(spot.y - spot.z) - 1, int(spot.y + spot.z) + 2):
			for x in range(int(spot.x - spot.z) - 1, int(spot.x + spot.z) + 2):
				var d := Vector2(x - spot.x, y - spot.y).length() + rng.randf() * 1.6
				if d < spot.z and inside_field(x + 0.5, y + 0.5) and img.get_pixel(x, y).a > 0.0:
					put(x, y, burnt.lightened(rng.randf() * 0.08))
	for spot in [Vector2(28, 15), Vector2(16, 24), Vector2(9, 19)]:
		for i in 9:
			var p: Vector2 = spot + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
			if inside_field(p.x, p.y):
				put(int(p.x), int(p.y), ash.darkened(rng.randf() * 0.25))
	# Fileiras quebradas (sulcos de terra queimada)
	for row in 5:
		var y0 := 12.0 + row * 4.2
		var x := 7
		while x < 34:
			var segment := rng.randi_range(3, 7)
			for k in segment:
				var px := x + k
				var py := int(y0 + sin(px * 0.35 + row) * 0.8)
				if inside_field(px + 0.5, py + 0.5) and inside_field(px + 2.5, py + 0.5) and inside_field(px - 1.5, py + 0.5):
					put(px, py, Color8(30, 22, 18))
			x += segment + rng.randi_range(2, 4)
	# Mourões quebrados e tombados
	thick_line(Vector2(6, 9), Vector2(8, 13), 0.7, Color8(105, 74, 46))
	put(6, 9, Color8(25, 20, 18))
	thick_line(Vector2(31, 31), Vector2(35, 30), 0.7, Color8(105, 74, 46))
	put(35, 30, Color8(25, 20, 18))
	thick_line(Vector2(33, 9), Vector2(33, 12), 0.7, Color8(95, 66, 40))
	put(33, 9, Color8(25, 20, 18))
	# Brasas
	for ember in [Vector2i(14, 16), Vector2i(25, 26), Vector2i(27, 24), Vector2i(21, 13), Vector2i(12, 27), Vector2i(17, 20)]:
		put(ember.x, ember.y, Color8(240, 120, 35))
	for ember in [Vector2i(26, 25), Vector2i(13, 16)]:
		put(ember.x, ember.y, Color8(255, 214, 90))
	outline(Color(0.08, 0.06, 0.05, 0.9))
	smoke(Vector2(25.0, 22.0))


## Madeireira pilhada: toras queimadas e espalhadas em volta de um monte de
## cinzas, pontas carbonizadas, brasas e fumaça.
func mill() -> void:
	new_image()
	rng.seed = 11
	# Monte de cinzas no meio
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - 20.0, (y + 0.5 - 25.0) * 1.5).length() + rng.randf() * 1.5
			if d < 9.0:
				put(x, y, Color8(110, 105, 98).darkened(rng.randf() * 0.3 + (0.25 if d < 4.0 else 0.0)))
	# Toras: corpo marrom chamuscado, trechos de carvão e ponta clara
	var logs := [
		[Vector2(5, 30), Vector2(16, 26), 2.2],
		[Vector2(24, 31), Vector2(35, 33), 2.2],
		[Vector2(9, 15), Vector2(17, 21), 2.0],
		[Vector2(26, 13), Vector2(32, 23), 2.0],
		[Vector2(15, 33), Vector2(22, 35), 1.6],
	]
	for log: Array in logs:
		var a: Vector2 = log[0]
		var b: Vector2 = log[1]
		var r: float = log[2]
		thick_line(a, b, r, Color8(92, 60, 36))
		thick_line(a, b, r * 0.45, Color8(70, 44, 26))
		# Trecho queimado perto de uma das pontas
		thick_line(a.lerp(b, 0.55), b, r, Color8(34, 26, 22))
		# Ponta cortada (anéis)
		disc(a.x, a.y, r, Color8(176, 136, 88))
		put(int(a.x), int(a.y), Color8(120, 86, 52))
	outline(Color(0.06, 0.05, 0.04, 0.95))
	# Brasas nas pontas queimadas e no meio das cinzas
	for ember in [Vector2i(16, 26), Vector2i(35, 33), Vector2i(17, 21), Vector2i(32, 23), Vector2i(19, 25), Vector2i(22, 24), Vector2i(20, 27)]:
		put(ember.x, ember.y, Color8(240, 120, 35))
	for ember in [Vector2i(20, 25), Vector2i(21, 26)]:
		put(ember.x, ember.y, Color8(255, 214, 90))
	smoke(Vector2(20.0, 22.0))


## Fio de fumaça cinza subindo e se abrindo, meio transparente.
func smoke(base: Vector2) -> void:
	for i in 14:
		var t := i / 13.0
		var p := base + Vector2(sin(t * 5.0) * 3.0 + t * 4.0, -t * 19.0)
		disc(p.x, p.y, 1.2 + t * 2.2, Color(0.78, 0.78, 0.78, 0.38 - t * 0.2))
