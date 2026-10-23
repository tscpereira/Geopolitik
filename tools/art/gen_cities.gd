extends SceneTree

## Gera as cidades (56x56, pixel art) em assets/sprites/cities/, uma por classe:
## povoado (cabanas), vila (casas e paliçada), cidade (muralha, torres e
## templo) e metropole (muralha alta, coliseu, templo e muitas casas).
## Magenta e os tons escuros dele viram a cor do dono (bandeiras e toldos).

const S := 56
var img: Image
var rng := RandomNumberGenerator.new()

const OUT := Color8(30, 22, 20)
const DIRT := Color8(170, 140, 98)
const DIRT_D := Color8(140, 112, 76)
const STONE := Color8(204, 194, 170)
const STONE_L := Color8(232, 225, 204)
const STONE_D := Color8(150, 140, 120)
const PLASTER := Color8(238, 228, 204)
const PLASTER_D := Color8(198, 184, 154)
const ROOF := Color8(196, 92, 56)
const ROOF_L := Color8(228, 132, 86)
const ROOF_D := Color8(146, 62, 38)
const THATCH := Color8(208, 172, 92)
const THATCH_L := Color8(234, 204, 126)
const THATCH_D := Color8(160, 124, 60)
const WOOD := Color8(150, 100, 56)
const WOOD_D := Color8(100, 64, 34)
const DARK := Color8(54, 38, 30)
const WATER := Color8(80, 140, 200)
const FIRE := Color8(250, 150, 40)
const FIRE_L := Color8(255, 226, 110)
const TEAM := Color8(255, 0, 255)
const TEAM_D := Color8(176, 0, 176)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/sprites/cities")
	var ranks := {"povoado": settlement, "vila": town, "cidade": city, "metropole": metropolis}
	for rank_name: String in ranks:
		img = Image.create(S, S, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		rng.seed = 5
		ranks[rank_name].call()
		outline()
		img.save_png("res://assets/sprites/cities/%s.png" % rank_name)
	print("ok")
	quit()


# --- Primitivas -------------------------------------------------------------------

func px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)


func rect(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			px(x, y, c)


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color, noise := 0.0) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var d := pow((x + 0.5 - cx) / rx, 2) + pow((y + 0.5 - cy) / ry, 2)
			if d <= 1.0 - rng.randf() * noise:
				px(x, y, c)


func outline() -> void:
	var copy := img.duplicate()
	for y in S:
		for x in S:
			if copy.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < S and n.y < S and copy.get_pixelv(n).a > 0.5:
					img.set_pixel(x, y, OUT)
					break


## Chão de terra batida embaixo da cidade.
func ground(cx: float, cy: float, rx: float, ry: float) -> void:
	ellipse(cx, cy, rx, ry, DIRT_D, 0.12)
	ellipse(cx, cy - 1, rx - 2, ry - 2, DIRT, 0.15)


## Casa vista de frente: parede de reboco com porta e janela e telhado de duas
## águas (lado direito na sombra). (x, base) = canto inferior esquerdo.
func house(x: int, base: int, w: int, wall_h: int, roof_h: int, thatch := false) -> void:
	var top := base - wall_h
	rect(x, top, x + w - 1, base - 1, PLASTER)
	rect(x + w - 2, top, x + w - 1, base - 1, PLASTER_D)
	var door := x + w / 2 - 1
	rect(door, base - 3, door + 1, base - 1, DARK)
	if w >= 7:
		px(x + 1, top + 1, DARK)
		px(x + w - 3, top + 1, DARK)
	var main := THATCH if thatch else ROOF
	var light := THATCH_L if thatch else ROOF_L
	var shade := THATCH_D if thatch else ROOF_D
	for r in roof_h:
		var y := top - 1 - r
		var inset := int(round(float(r) * (w / 2.0 + 1) / roof_h))
		var x0 := x - 1 + inset
		var x1 := x + w - inset
		var mid := (x0 + x1) / 2
		rect(x0, y, mid, y, main)
		rect(mid + 1, y, x1, y, shade)
		if r == 0:
			rect(x0, y, x1, y, shade) # beiral
	rect(x + w / 2 - 1, top - roof_h, x + w / 2, top - roof_h, light) # cumeeira


## Cabana redonda de palha.
func hut(cx: int, base: int, r: int) -> void:
	rect(cx - r + 1, base - 3, cx + r - 1, base - 1, WOOD)
	rect(cx + r - 2, base - 3, cx + r - 1, base - 1, WOOD_D)
	rect(cx - 1, base - 3, cx, base - 1, DARK)
	for i in r + 2:
		var y := base - 4 - i
		var half := r - int(round(float(i) * r / (r + 1)))
		rect(cx - half, y, cx, y, THATCH)
		rect(cx + 1, y, cx + half, y, THATCH_D)
	px(cx, base - 5 - r, THATCH_L)


## Mastro com bandeira na cor do time.
func flag(x: int, base: int, h: int) -> void:
	rect(x, base - h, x, base - 1, WOOD_D)
	rect(x + 1, base - h, x + 5, base - h + 2, TEAM)
	rect(x + 1, base - h + 2, x + 5, base - h + 3, TEAM_D)
	px(x + 5, base - h + 3, Color(0, 0, 0, 0))


## Trecho de muralha de pedra com ameias e juntas.
func wall(x0: int, x1: int, base: int, h: int) -> void:
	var top := base - h
	rect(x0, top, x1, base - 1, STONE)
	rect(x0, base - 2, x1, base - 1, STONE_D)
	for y in range(top + 2, base - 1, 2):
		for x in range(x0 + (y / 2) % 2 * 2, x1, 4):
			px(x, y, STONE_D)
	for x in range(x0, x1 + 1, 3):
		rect(x, top - 2, x + 1, top - 1, STONE)
	rect(x0, top, x1, top, STONE_L)


## Torre quadrada com ameias, seteira e bandeira.
func tower(x: int, base: int, w: int, h: int, with_flag := true) -> void:
	var top := base - h
	rect(x, top, x + w - 1, base - 1, STONE)
	rect(x + w - 2, top, x + w - 1, base - 1, STONE_D)
	rect(x, top, x + w - 1, top, STONE_L)
	for xx in range(x, x + w, 2):
		rect(xx, top - 2, xx, top - 1, STONE)
	rect(x + w / 2 - 1, top + 3, x + w / 2 - 1, top + 5, DARK)
	if with_flag:
		flag(x + w / 2, top - 2, 8)


## Paliçada de troncos pontudos.
func palisade(x0: int, x1: int, base: int, h: int) -> void:
	for x in range(x0, x1 + 1):
		var c := WOOD if x % 2 == 0 else WOOD_D
		rect(x, base - h + (1 if x % 2 else 0), x, base - 1, c)


## Templo com escadaria, colunas e frontão (toldo na cor do time).
func temple(x: int, base: int, w: int, h: int) -> void:
	rect(x - 1, base - 2, x + w, base - 1, STONE_D) # escadaria
	rect(x, base - 3, x + w - 1, base - 3, STONE)
	var top := base - 3 - h
	rect(x, top, x + w - 1, base - 4, DARK.lightened(0.15)) # interior
	for cx in range(x, x + w, 3):
		rect(cx, top, cx + 1, base - 4, STONE_L)
		px(cx + 1, base - 4, STONE_D)
	rect(x - 1, top - 1, x + w, top - 1, STONE)
	var roof := 4
	for r in roof:
		var y := top - 2 - r
		var inset := r * (w / 2 + 1) / roof
		rect(x - 1 + inset, y, x + w - inset, y, STONE_L if r < roof - 1 else STONE)
	rect(x + w / 2 - 2, top - 3, x + w / 2 + 1, top - 2, TEAM)


## Coliseu: arena oval com duas fileiras de arcos.
func colosseum(cx: int, base: int, rx: int, h: int) -> void:
	for y in range(base - h, base):
		rect(cx - rx, y, cx + rx, y, STONE)
	rect(cx + rx - 2, base - h, cx + rx, base - 1, STONE_D)
	for row in 2:
		var y := base - h + 2 + row * (h / 2)
		for x in range(cx - rx + 1, cx + rx - 1, 3):
			rect(x, y, x, y + 1, DARK)
	rect(cx - rx, base - h, cx + rx, base - h, STONE_L)
	rect(cx - rx + 2, base - h - 1, cx + rx - 2, base - h - 1, STONE)


func well(x: int, base: int) -> void:
	rect(x, base - 3, x + 3, base - 1, STONE)
	rect(x + 1, base - 3, x + 2, base - 3, WATER)
	rect(x, base - 7, x, base - 4, WOOD_D)
	rect(x + 3, base - 7, x + 3, base - 4, WOOD_D)
	rect(x, base - 8, x + 3, base - 8, WOOD)


func campfire(x: int, base: int) -> void:
	rect(x - 1, base - 1, x + 2, base - 1, WOOD_D)
	rect(x, base - 3, x + 1, base - 2, FIRE)
	px(x, base - 4, FIRE_L)


# --- Classes ---------------------------------------------------------------------

## Povoado: três cabanas de palha, fogueira e bandeira.
func settlement() -> void:
	ground(28, 42, 20, 9)
	hut(20, 39, 6)
	hut(36, 38, 5)
	hut(28, 49, 7)
	campfire(39, 47)
	flag(11, 47, 13)


## Vila: casas de reboco e telha, uma de palha, poço e paliçada nos fundos.
func town() -> void:
	ground(28, 39, 23, 12)
	palisade(9, 46, 29, 6)
	house(12, 34, 9, 5, 4)
	house(23, 32, 10, 6, 5)
	house(35, 34, 9, 5, 4)
	house(8, 44, 9, 5, 4, true)
	house(30, 46, 11, 6, 5)
	well(21, 47)
	flag(44, 47, 12)


## Cidade: muralha de pedra com portão e duas torres, casas e templo dentro.
func city() -> void:
	ground(28, 40, 26, 13)
	temple(18, 28, 18, 6)
	house(6, 34, 8, 5, 4)
	house(38, 34, 9, 5, 4)
	house(15, 40, 9, 5, 4)
	house(29, 40, 9, 5, 4)
	wall(4, 51, 51, 7)
	rect(24, 46, 31, 50, DARK) # portão
	rect(25, 45, 30, 45, DARK)
	tower(1, 52, 7, 14)
	tower(48, 52, 7, 14)


## Metrópole: muralha alta com três torres, coliseu, templo grande e muitas casas.
func metropolis() -> void:
	ground(28, 36, 28, 18)
	colosseum(14, 22, 10, 8)
	temple(31, 22, 20, 7)
	for spot in [[3, 30], [12, 31], [21, 30], [41, 30], [48, 31]]:
		house(spot[0], spot[1], 8, 5, 4)
	for spot in [[6, 38], [16, 39], [27, 37], [38, 39], [47, 38]]:
		house(spot[0], spot[1], 8, 5, 4)
	wall(2, 53, 52, 9)
	rect(24, 46, 31, 51, DARK) # portão
	rect(25, 45, 30, 45, DARK)
	tower(0, 53, 7, 17)
	tower(24, 44, 8, 12)
	tower(49, 53, 7, 17)
