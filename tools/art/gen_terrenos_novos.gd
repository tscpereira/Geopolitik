extends SceneTree

## Gera as texturas PROVISÓRIAS dos terrenos de 28/10/2026 (até virem as do
## Gemini: tools/art/gemini/pedidos/11_terrenos_novos), 160x160 e sem emenda,
## em assets/tiles/:
##   - aguas_profundas: a agua.png escurecida e mais azul;
##   - selva: copas redondas bem juntas, em vários verdes, e palmeiras por cima;
##   - deserto: areia com ondulações de duna;
##   - tundra: chão pardo com manchas de musgo, pedrinhas e neve rala;
##   - neve: branco-azulado com montes suaves e brilhos.
## Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/gen_terrenos_novos.gd

const TILES := "res://assets/tiles/"
const SIZE := 160

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 2810
	_save(_deep_water(), "aguas_profundas")
	_save(_jungle(), "selva")
	_save(_desert(), "deserto")
	_save(_tundra(), "tundra")
	_save(_snow(), "neve")
	quit()


func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(TILES + name + ".png"))
	print("ok: ", name)


## Ruído sem emenda de 0 a 1, SIZE x SIZE.
func _noise(seed: int, frequency: float, octaves := 4) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var image := noise.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	image.convert(Image.FORMAT_RGBA8)
	return image


func _value(noise: Image, x: int, y: int) -> float:
	return noise.get_pixel(posmod(x, SIZE), posmod(y, SIZE)).r


func _deep_water() -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(TILES + "agua.png"))
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	for y in SIZE:
		for x in SIZE:
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * 0.5, c.g * 0.58, c.b * 0.78 + 0.04))
	return image


func _desert() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var broad := _noise(11, 0.012)
	var warp := _noise(12, 0.01, 2)
	var light := Color8(236, 208, 150)
	var shadow := Color8(196, 154, 96)
	for y in SIZE:
		for x in SIZE:
			# Ondas com número inteiro de voltas no quadrado (sem emenda), entortadas pelo ruído
			var phase := TAU * (3.0 * y + 1.0 * x) / SIZE + 5.0 * _value(warp, x, y)
			var ripple := pow(0.5 + 0.5 * sin(phase), 1.6)
			var c := shadow.lerp(light, 0.35 + 0.55 * ripple)
			c = c * (0.88 + 0.22 * _value(broad, x, y))
			c = c * (0.97 + 0.06 * _rng.randf()) # grãos
			image.set_pixel(x, y, Color(c, 1.0))
	return image


func _tundra() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ground := _noise(21, 0.03)
	var moss := _noise(22, 0.025)
	var frost := _noise(23, 0.04)
	var soil := Color8(128, 112, 84)
	var dry := Color8(156, 142, 102)
	var moss_color := Color8(104, 116, 70)
	var snow := Color8(226, 232, 238)
	for y in SIZE:
		for x in SIZE:
			var c := soil.lerp(dry, _value(ground, x, y))
			c = c.lerp(moss_color, smoothstep(0.55, 0.75, _value(moss, x, y)) * 0.8)
			c = c.lerp(snow, smoothstep(0.68, 0.8, _value(frost, x, y)) * 0.85)
			c = c * (0.93 + 0.12 * _rng.randf())
			image.set_pixel(x, y, Color(c, 1.0))
	# Pedrinhas cinza, com luz em cima à esquerda
	for i in 26:
		var center := Vector2(_rng.randf() * SIZE, _rng.randf() * SIZE)
		var radius := _rng.randf_range(1.2, 2.8)
		_disc(image, center + Vector2(0.8, 0.8), radius, Color(0.25, 0.22, 0.18), 0.5)
		_disc(image, center, radius, Color8(150, 146, 138), 1.0)
		_disc(image, center - Vector2(0.5, 0.5), radius * 0.5, Color8(186, 182, 172), 0.8)
	return image


func _snow() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var drifts := _noise(31, 0.018)
	var detail := _noise(32, 0.06, 2)
	var white := Color8(244, 247, 251)
	var shade := Color8(196, 210, 230)
	for y in SIZE:
		for x in SIZE:
			# Luz pela inclinação dos montes (diferença do ruído em x e y)
			var h := _value(drifts, x, y)
			var slope := (_value(drifts, x + 2, y + 2) - h) * 9.0
			var c := white.lerp(shade, clampf(0.25 + slope + (1.0 - h) * 0.25, 0.0, 1.0))
			c = c * (0.97 + 0.05 * _value(detail, x, y))
			if _rng.randf() < 0.004:
				c = Color(1, 1, 1) # brilho
			image.set_pixel(x, y, Color(c, 1.0))
	return image


func _jungle() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color8(16, 44, 20))
	var greens := [Color8(34, 92, 36), Color8(46, 112, 40), Color8(28, 80, 44), Color8(60, 120, 46), Color8(40, 100, 54)]
	# Copas redondas bem juntas
	for i in 150:
		var center := Vector2(_rng.randf() * SIZE, _rng.randf() * SIZE)
		var radius := _rng.randf_range(7.0, 14.0)
		_crown(image, center, radius, greens[_rng.randi() % greens.size()])
	# Palmeiras por cima
	for i in 12:
		_palm(image, Vector2(_rng.randf() * SIZE, _rng.randf() * SIZE), _rng.randf_range(10.0, 19.0))
	return image


## Copa de árvore: disco com luz em cima à esquerda, borda escura e uma
## sombra embaixo à direita.
func _crown(image: Image, center: Vector2, radius: float, color: Color) -> void:
	_disc(image, center + Vector2(2.5, 2.5), radius, Color(0.03, 0.1, 0.04), 0.45)
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := Vector2(dx, dy) / radius
			if d.length() > 1.0:
				continue
			var light := 1.0 - 0.4 * (d.x + d.y) * 0.7 - 0.35 * pow(d.length(), 3.0)
			var c := color * clampf(light, 0.5, 1.35)
			c = c * (0.9 + 0.2 * _rng.randf()) # folhas
			_blend(image, int(center.x) + dx, int(center.y) + dy, Color(c, 1.0), 1.0)


## Palmeira vista de cima: folhas compridas e curvas saindo do centro, cada
## uma com a nervura clara e folíolos dos dois lados; sombra antes.
func _palm(image: Image, center: Vector2, length: float) -> void:
	var fronds := _rng.randi_range(7, 9)
	var turn := _rng.randf() * TAU
	var tint := Color8(58, 112, 38).lerp(Color8(96, 140, 48), _rng.randf())
	for pass_index in 2:
		var shadow := pass_index == 0
		var origin := center + (Vector2(3, 3) if shadow else Vector2.ZERO)
		for f in fronds:
			var angle := turn + TAU * f / fronds + _rng.randf_range(-0.15, 0.15)
			var direction := Vector2.from_angle(angle)
			var side := direction.orthogonal()
			var bend := _rng.randf_range(-0.35, 0.35)
			var steps := int(length * 2.0)
			for s in steps:
				var t := float(s) / steps
				var point := origin + direction * length * t + side * bend * length * t * t
				var leaflet := (1.0 - t) * 5.0 + 1.0
				var c := Color(0.03, 0.08, 0.03) if shadow else tint.lerp(tint.lightened(0.25), t * 0.6)
				var alpha := 0.4 if shadow else 1.0
				for k in range(-int(leaflet), int(leaflet) + 1):
					var q := point + side * k + direction * absf(k) * 0.5 # folíolos inclinados para fora
					_blend(image, int(q.x), int(q.y), c * (1.0 - 0.15 * absf(k) / leaflet), alpha)
				if not shadow:
					_blend(image, int(point.x), int(point.y), tint.lightened(0.4), 0.7) # nervura
		if not shadow:
			_disc(image, center, 2.2, Color8(110, 84, 40), 1.0) # tronco/coroa


func _disc(image: Image, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() <= radius:
				_blend(image, int(center.x) + dx, int(center.y) + dy, color, alpha)


## Pinta um pixel dando a volta nas bordas (a textura não tem emenda).
func _blend(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	x = posmod(x, SIZE)
	y = posmod(y, SIZE)
	var old := image.get_pixel(x, y)
	image.set_pixel(x, y, Color(old.lerp(color, alpha), 1.0))
