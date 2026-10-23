extends SceneTree

## Gera os sprites das unidades (40x40, pixel art) em assets/sprites/units/.
## Magenta (#FF00FF) e os tons escuros dele viram a cor do jogador (com sombra).

const S := 40
var img: Image

const OUT := Color8(28, 20, 18)
const SKIN := Color8(236, 184, 138)
const SKIN_D := Color8(196, 136, 94)
const HAIR := Color8(92, 56, 32)
const BRONZE := Color8(206, 152, 62)
const BRONZE_L := Color8(244, 206, 120)
const BRONZE_D := Color8(142, 96, 36)
const IRON := Color8(178, 184, 194)
const IRON_L := Color8(232, 236, 242)
const IRON_D := Color8(112, 118, 130)
const WOOD := Color8(156, 104, 56)
const WOOD_D := Color8(104, 66, 34)
const LEATHER := Color8(128, 82, 46)
const LEATHER_D := Color8(86, 52, 28)
const LINEN := Color8(226, 212, 172)
const LINEN_D := Color8(184, 166, 124)
const STRAW := Color8(232, 200, 96)
const STRAW_D := Color8(184, 146, 56)
const TEAM := Color8(255, 0, 255)
const TEAM_D := Color8(176, 0, 176)
const TEAM_L := Color8(255, 0, 255)
const HORSE := Color8(156, 98, 56)
const HORSE_L := Color8(192, 134, 82)
const HORSE_D := Color8(108, 64, 36)
const MANE := Color8(58, 36, 24)
const WHITE := Color8(240, 240, 236)


func _initialize() -> void:
	var units := {
		"guerreiro": warrior, "arqueiro": archer, "cavaleiro": horseman,
		"colono": settler, "trabalhador": worker,
	}
	for unit_name: String in units:
		img = Image.create(S, S, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		units[unit_name].call()
		outline()
		img.save_png("res://assets/sprites/units/%s.png" % unit_name)
	print("ok")
	quit()


# --- Primitivas ---------------------------------------------------------------

func px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)


func rect(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			px(x, y, c)


func line(x0: float, y0: float, x1: float, y1: float, c: Color, width := 1) -> void:
	var steps := int(maxf(absf(x1 - x0), absf(y1 - y0))) + 1
	for i in steps + 1:
		var t := float(i) / steps
		var x := roundi(lerpf(x0, x1, t))
		var y := roundi(lerpf(y0, y1, t))
		rect(x, y, x + width - 1, y + width - 1, c)


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			if pow((x + 0.5 - cx) / rx, 2) + pow((y + 0.5 - cy) / ry, 2) <= 1.0:
				px(x, y, c)


## Contorno escuro de 1 pixel em volta de tudo.
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


# --- Partes do corpo ------------------------------------------------------------

## Cabeça de perfil 3/4 virada para a direita: rosto de 6x6 a partir de (x, y).
func head(x: int, y: int) -> void:
	rect(x, y, x + 5, y + 5, SKIN)
	rect(x, y + 4, x + 1, y + 5, SKIN_D) # nuca na sombra
	px(x + 4, y + 2, OUT) # olho
	px(x + 6, y + 3, SKIN) # nariz
	px(x + 3, y + 5, SKIN_D) # queixo


## Pernas e sandálias, a partir da barra da túnica (y).
func legs(x: int, y: int, length := 5) -> void:
	rect(x, y, x + 1, y + length - 1, SKIN)
	rect(x + 4, y, x + 5, y + length - 1, SKIN_D)
	rect(x - 1, y + length, x + 1, y + length, LEATHER_D)
	rect(x + 4, y + length, x + 6, y + length, LEATHER_D)


## Túnica na cor do time, com a sombra do lado esquerdo e da barra.
func tunic(x0: int, y0: int, x1: int, y1: int) -> void:
	rect(x0, y0, x1, y1, TEAM)
	rect(x0, y0, x0 + 1, y1, TEAM_D)
	rect(x0 - 1, y1 - 2, x1 + 1, y1, TEAM)
	rect(x0 - 1, y1, x1 + 1, y1, TEAM_D)


# --- Unidades ---------------------------------------------------------------------

## Guerreiro (hoplita): elmo de bronze com crista na cor do time, peitoral de
## bronze, escudo redondo e lança.
func warrior() -> void:
	# Lança atrás do corpo, na mão da frente
	line(28, 3, 28, 37, WOOD)
	line(29, 4, 29, 37, WOOD_D)
	rect(27, 1, 29, 5, IRON)
	px(28, 0, IRON_L)
	px(27, 2, IRON_L)
	legs(16, 29)
	tunic(15, 20, 23, 29)
	# Peitoral de bronze e cinto
	rect(16, 19, 23, 25, BRONZE)
	rect(16, 19, 17, 25, BRONZE_D)
	rect(20, 20, 22, 21, BRONZE_L)
	rect(15, 26, 24, 26, LEATHER)
	# Braço da frente segurando a lança
	rect(24, 20, 26, 22, SKIN)
	rect(26, 22, 27, 24, SKIN)
	# Cabeça e elmo coríntio
	head(17, 12)
	rect(16, 9, 23, 13, BRONZE)
	rect(16, 13, 17, 17, BRONZE_D) # proteção da nuca
	rect(22, 13, 23, 16, BRONZE) # guarda da bochecha
	rect(18, 10, 21, 10, BRONZE_L)
	px(16, 9, BRONZE_D)
	# Crista de crina na cor do time
	rect(15, 6, 22, 8, TEAM)
	rect(13, 7, 15, 10, TEAM_D)
	rect(16, 5, 21, 5, TEAM_L)
	# Escudo redondo (hoplon) na frente do corpo, à esquerda
	ellipse(13, 24, 6.5, 7, BRONZE_D)
	ellipse(13, 24, 5.5, 6, TEAM)
	ellipse(12, 23, 3.5, 4, TEAM_D.lerp(TEAM, 0.5))
	ellipse(13, 24, 1.6, 1.6, BRONZE_L)


## Arqueiro: faixa na cabeça na cor do time, colete de couro, aljava e arco
## retesado com a flecha.
func archer() -> void:
	# Aljava nas costas, com as penas das flechas
	rect(11, 13, 14, 25, LEATHER)
	rect(11, 13, 12, 25, LEATHER_D)
	rect(11, 10, 12, 12, WHITE)
	rect(13, 9, 14, 12, Color8(220, 60, 50))
	legs(16, 29)
	tunic(15, 20, 23, 29)
	# Colete de couro e cinto
	rect(16, 19, 22, 25, LEATHER)
	rect(16, 19, 17, 25, LEATHER_D)
	px(20, 21, LEATHER_D)
	px(20, 23, LEATHER_D)
	rect(15, 26, 24, 26, LEATHER_D)
	# Cabeça com cabelo e faixa
	head(17, 12)
	rect(16, 10, 22, 12, HAIR)
	rect(16, 12, 17, 15, HAIR)
	rect(16, 11, 23, 11, TEAM)
	rect(13, 11, 15, 13, TEAM_D) # pontas da faixa
	# Braços esticados para o arco
	rect(23, 20, 29, 21, SKIN)
	rect(23, 22, 25, 22, SKIN_D)
	# Arco
	line(30, 8, 33, 13, WOOD)
	line(33, 13, 33, 27, WOOD)
	line(33, 27, 30, 32, WOOD)
	line(34, 14, 34, 26, WOOD_D)
	line(30, 8, 25, 21, LINEN) # corda puxada até a mão
	line(25, 21, 30, 32, LINEN)
	# Flecha
	line(20, 21, 35, 21, WOOD_D)
	rect(35, 20, 37, 22, IRON)
	px(38, 21, IRON_L)
	rect(19, 20, 20, 22, WHITE)


## Cavaleiro: cavalo marrom com crina, sela na cor do time e cavaleiro de
## elmo com lança.
func horseman() -> void:
	# Cauda
	line(7, 21, 5, 30, MANE, 2)
	# Pernas do cavalo (as de trás mais escuras)
	for leg in [[11, HORSE_D], [15, HORSE], [25, HORSE_D], [29, HORSE]]:
		rect(leg[0], 28, leg[0] + 1, 35, leg[1])
		rect(leg[0], 36, leg[0] + 2, 36, OUT.lightened(0.15))
	# Corpo, peito e pescoço
	ellipse(19, 25, 12, 5.5, HORSE)
	ellipse(19, 27, 11, 3, HORSE_D)
	ellipse(20, 23, 9, 2.2, HORSE_L)
	line(28, 22, 32, 14, HORSE, 4)
	# Cabeça do cavalo
	rect(31, 11, 36, 15, HORSE)
	rect(35, 14, 38, 17, HORSE)
	rect(37, 16, 38, 17, HORSE_D)
	px(34, 13, OUT)
	rect(31, 9, 32, 10, HORSE_D) # orelha
	line(28, 13, 31, 21, MANE, 2) # crina
	# Sela e manta na cor do time
	rect(15, 19, 24, 24, TEAM)
	rect(15, 23, 24, 24, TEAM_D)
	rect(17, 18, 22, 19, LEATHER)
	# Cavaleiro: perna, tronco, braço, cabeça e elmo
	rect(19, 20, 21, 26, SKIN_D)
	rect(18, 26, 21, 27, LEATHER_D)
	rect(17, 11, 22, 18, TEAM)
	rect(17, 11, 18, 18, TEAM_D)
	rect(18, 13, 21, 16, BRONZE)
	rect(22, 13, 25, 14, SKIN)
	head(18, 4)
	rect(17, 2, 24, 5, BRONZE)
	rect(19, 2, 22, 2, BRONZE_L)
	rect(17, 5, 18, 9, BRONZE_D)
	rect(18, 0, 23, 1, TEAM)
	rect(16, 1, 17, 3, TEAM_D)
	# Lança
	line(26, 3, 26, 26, WOOD)
	rect(25, 0, 27, 3, IRON)


## Colono: chapéu de palha, roupa de linho com lenço na cor do time, trouxa
## nas costas e pá.
func settler() -> void:
	# Trouxa nas costas
	ellipse(12, 19, 4.5, 6, LINEN_D)
	ellipse(11, 18, 3, 4, LINEN)
	line(13, 13, 19, 22, TEAM_D) # alça
	# Pá
	line(29, 8, 29, 31, WOOD)
	rect(27, 31, 31, 36, IRON)
	rect(27, 31, 28, 36, IRON_D)
	px(30, 32, IRON_L)
	rect(28, 7, 30, 8, WOOD_D)
	legs(16, 29)
	# Túnica de linho
	rect(15, 19, 23, 29, LINEN)
	rect(15, 19, 16, 29, LINEN_D)
	rect(14, 27, 24, 29, LINEN)
	rect(14, 29, 24, 29, LINEN_D)
	# Lenço e faixa na cor do time
	rect(16, 18, 22, 19, TEAM)
	rect(15, 24, 24, 25, TEAM)
	rect(15, 25, 24, 25, TEAM_D)
	# Braço segurando a pá
	rect(24, 20, 26, 21, SKIN)
	rect(26, 21, 28, 23, SKIN)
	# Cabeça com barba e chapéu de palha
	head(17, 12)
	rect(21, 16, 23, 17, HAIR)
	rect(13, 10, 26, 11, STRAW)
	rect(13, 11, 26, 11, STRAW_D)
	rect(16, 6, 23, 9, STRAW)
	rect(16, 6, 17, 9, STRAW_D)
	rect(16, 9, 23, 9, TEAM_D) # fita


## Trabalhador: gorro na cor do time, avental de couro e machado no ombro.
func worker() -> void:
	# Machado na mão da frente, apoiado no chão
	line(26, 34, 29, 10, WOOD)
	line(27, 34, 30, 10, WOOD_D)
	rect(28, 5, 33, 10, IRON)
	rect(32, 5, 34, 12, IRON_D)
	rect(29, 6, 30, 7, IRON_L)
	legs(16, 29)
	tunic(15, 20, 23, 29)
	# Avental de couro e cinto
	rect(17, 22, 23, 29, LEATHER)
	rect(17, 22, 18, 29, LEATHER_D)
	rect(15, 22, 24, 22, LEATHER_D)
	# Braços: o da frente segura o cabo
	rect(14, 21, 16, 23, SKIN)
	rect(23, 19, 25, 21, SKIN)
	rect(25, 21, 28, 22, SKIN)

	# Cabeça com gorro
	head(17, 12)
	rect(21, 16, 23, 17, HAIR)
	rect(16, 9, 23, 12, TEAM)
	rect(16, 9, 17, 12, TEAM_D)
	rect(15, 12, 23, 12, TEAM_D)
	rect(18, 7, 21, 8, TEAM)
