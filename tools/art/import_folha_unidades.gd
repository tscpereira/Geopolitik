extends SceneTree

## Importa a folha das 9 unidades gerada no ChatGPT (25/10/2026: fundo verde
## liso, linha de cima em azul do time, linha de baixo em vermelho). Rode na
## pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/import_folha_unidades.gd -- <folha.png>
## Passos:
##   1. remove o fundo verde e as sombras no chão (pixel = k x cor do fundo);
##   2. retoque: tira o escudo solto do Guerreiro de Espada Curta e pinta o
##      antebraço que ele escondia (coordenadas desta folha);
##   3. separa as 9 unidades da linha azul pelas colunas vazias, na ordem de
##      NAMES;
##   4. máscara do azul do time (<nome>_time.png), como import_unit.gd;
##   5. reduz TODAS com a mesma escala (a folha já tem as proporções certas:
##      pessoa, cavalo, biga), cabendo em 76x70, pés em y = 73, e grava em
##      assets/sprites/units/, em tools/art/chatgpt/unidades/ (grande) e em
##      prontos/ (80x80 e prévia nas cores de dois jogadores).
## Desenho avulso (mesmo fundo verde) para trocar uma unidade da folha:
##   ... import_folha_unidades.gd -- <imagem.png> <nome>
## A imagem fica em tools/art/chatgpt/<nome>_avulsa.png e passa a valer
## também quando a folha for importada de novo. A altura no jogo vem de
## AVULSAS; o vermelho forte vira cor do time (o ChatGPT pintou o scutum de
## vermelho).

const NAMES := ["trabalhador", "colono", "guerreiro", "lanceiro", "guerreiro_espada", "arqueiro", "cavalaria_leve", "bigas", "catapulta"]
const UNITS := "res://assets/sprites/units/"
const GRANDES := "res://tools/art/chatgpt/unidades/"
const PRONTOS := "res://tools/art/chatgpt/prontos/"
const ORIGINAL := "res://tools/art/chatgpt/folha_unidades.png"
const AVULSA := "res://tools/art/chatgpt/%s_avulsa.png"
## Unidade avulsa -> altura do desenho no jogo, em pixels (a da folha, na
## mesma pose: o guerreiro em investida tinha 55).
const AVULSAS := {"guerreiro_espada": 55, "gale": 66}
const SIZE := 80
const MAX_SIZE := Vector2(76, 70)
const FEET := 73
## Fundo: resíduo máximo de p - k x fundo, e a faixa de k (sombra ... fundo).
const KEY_RESIDUAL := 14.0 / 255.0
const KEY_K := Vector2(0.55, 1.2)
## Retoque do Guerreiro de Espada Curta (coordenadas da folha).
const SHIELD := [Vector2(1131, 189), Vector2(1155, 189), Vector2(1159, 199), Vector2(1159, 284), Vector2(1134, 284),
	Vector2(1131, 268), Vector2(1122, 256), Vector2(1115, 249), Vector2(1115, 206), Vector2(1122, 199)]
const HAND_X := 1152
const ARM_FROM := Vector2(1117, 205)
const ARM_TO := Vector2(1157, 201)
const ARM_RADIUS := Vector2(5.6, 4.4)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("uso: -- <folha.png>   ou   -- <imagem.png> <nome>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GRANDES))
	if args.size() >= 2:
		var unit_name: String = args[1]
		if not AVULSAS.has(unit_name):
			print("%s não está em AVULSAS (altura no jogo)" % unit_name)
			quit(1)
			return
		var image := Image.load_from_file(args[0])
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(ProjectSettings.globalize_path(AVULSA % unit_name))
		_avulsa(unit_name)
		quit()
		return
	var sheet := Image.load_from_file(args[0])
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.save_png(ProjectSettings.globalize_path(ORIGINAL))
	_remove_backdrop(sheet)
	_remove_shield(sheet)
	var boxes := _split(sheet, Rect2i(0, 0, sheet.get_width(), sheet.get_height() / 2))
	if boxes.size() != NAMES.size():
		print("esperava %d unidades na linha de cima, achei %d: %s" % [NAMES.size(), boxes.size(), boxes])
		quit(1)
		return
	var scale := INF
	for box: Rect2i in boxes:
		scale = minf(scale, minf(MAX_SIZE.x / box.size.x, MAX_SIZE.y / box.size.y))
	print("escala comum: %.3f" % scale)
	for i in NAMES.size():
		if FileAccess.file_exists(ProjectSettings.globalize_path(AVULSA % NAMES[i])):
			_avulsa(NAMES[i])
		else:
			_install(sheet.get_region(boxes[i]), NAMES[i], scale)
	quit()


func _avulsa(unit_name: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(AVULSA % unit_name))
	image.convert(Image.FORMAT_RGBA8)
	_remove_backdrop(image)
	var box := Rect2i()
	var first := true
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a < 0.5:
				continue
			box = Rect2i(x, y, 1, 1) if first else box.expand(Vector2i(x, y))
			first = false
			# Vermelho forte -> azul do time (mesmo brilho e saturação)
			if (p.h < 0.03 or p.h > 0.95) and p.s > 0.55 and p.v > 0.15:
				image.set_pixel(x, y, Color.from_hsv(0.64, p.s, p.v, p.a))
	box.size += Vector2i.ONE
	# Altura de AVULSAS, sem passar da largura máxima (a Galé é quase tão larga quanto alta)
	_install(image.get_region(box), unit_name, minf(float(AVULSAS[unit_name]) / box.size.y, MAX_SIZE.x / box.size.x))


func _remove_backdrop(img: Image) -> void:
	var bg := img.get_pixel(4, 4)
	var bg_v := Vector3(bg.r, bg.g, bg.b)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var v := Vector3(p.r, p.g, p.b)
			var k := v.dot(bg_v) / bg_v.dot(bg_v)
			if k > KEY_K.x and k < KEY_K.y and (v - bg_v * k).length() < KEY_RESIDUAL:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	# Borda: tira o verde que vazou nos pixels encostados no fundo
	var src: Image = img.duplicate()
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			var p := src.get_pixel(x, y)
			if p.a == 0.0:
				continue
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if src.get_pixel(x + d.x, y + d.y).a == 0.0:
					edge = true
			if edge and p.g > maxf(p.r, p.b):
				img.set_pixel(x, y, Color(p.r, maxf(p.r, p.b), p.b, 0.75))


## O escudo do Guerreiro de Espada Curta flutuava na frente do corpo: apaga
## tudo dentro do contorno (menos a mão da espada) e pinta o antebraço.
func _remove_shield(img: Image) -> void:
	var poly := PackedVector2Array(SHIELD)
	for y in range(185, 290):
		for x in range(1110, 1165):
			if not Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				continue
			var p := img.get_pixel(x, y)
			var skin := p.h > 0.02 and p.h < 0.12 and p.s > 0.25 and p.s < 0.7 and p.v > 0.45
			if x >= HAND_X and skin:
				continue
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	# Antebraço: tubo de pele, luz de cima, contorno escuro
	var light := Color8(236, 178, 128)
	var mid := Color8(200, 130, 82)
	var dark := Color8(120, 66, 36)
	var line := Color8(70, 38, 22)
	var axis := ARM_TO - ARM_FROM
	var normal := Vector2(axis.y, -axis.x).normalized()
	if normal.y > 0:
		normal = -normal
	for y in range(190, 215):
		for x in range(1110, 1162):
			var q := Vector2(x, y)
			var t := clampf((q - ARM_FROM).dot(axis) / axis.length_squared(), 0.0, 1.0)
			var r := lerpf(ARM_RADIUS.x, ARM_RADIUS.y, t)
			var off := q - (ARM_FROM + axis * t)
			var dist := off.length()
			if dist > r or img.get_pixel(x, y).a > 0.0:
				continue
			# s: +1 em cima (luz), -1 embaixo (sombra)
			var s := off.dot(normal) / r
			var c := mid.lerp(light, clampf(s * 1.4 - 0.2, 0, 1)) if s > 0 else mid.lerp(dark, clampf(-s * 1.2, 0, 1))
			if dist > r - 1.0:
				c = c.lerp(line, 0.7)
			img.set_pixel(x, y, c)


## Separa as unidades de uma faixa pelas colunas sem nenhum pixel.
func _split(img: Image, band: Rect2i) -> Array[Rect2i]:
	var boxes: Array[Rect2i] = []
	var start := -1
	for x in band.size.x + 1:
		var used := false
		if x < band.size.x:
			for y in range(band.position.y, band.end.y):
				if img.get_pixel(x, y).a > 0.5:
					used = true
					break
		if used and start < 0:
			start = x
		elif not used and start >= 0:
			if x - start > 8:
				var top := band.end.y
				var bottom := band.position.y
				for yy in range(band.position.y, band.end.y):
					for xx in range(start, x):
						if img.get_pixel(xx, yy).a > 0.5:
							top = mini(top, yy)
							bottom = maxi(bottom, yy)
				boxes.append(Rect2i(start, top, x - start, bottom - top + 1))
			start = -1
	return boxes


func _install(crop: Image, unit_name: String, scale: float) -> void:
	var w := crop.get_width()
	var h := crop.get_height()
	var mask := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := crop.get_pixel(x, y)
			if p.a == 0.0:
				crop.set_pixel(x, y, Color(0.12, 0.1, 0.08, 0.0))
				continue
			var blue := 0.0
			if p.h > 0.56 and p.h < 0.74 and p.v > 0.12:
				blue = smoothstep(0.28, 0.5, p.s) * (1.0 - smoothstep(0.06, 0.1, absf(p.h - 0.64)))
			var amount := blue * clampf(p.v / 0.85, 0.0, 1.0)
			crop.set_pixel(x, y, Color(p.r * (1.0 - blue), p.g * (1.0 - blue), p.b * (1.0 - blue), p.a))
			mask.set_pixel(x, y, Color(amount, amount, amount, 1.0))
	crop.save_png(ProjectSettings.globalize_path(GRANDES) + unit_name + ".png")
	mask.save_png(ProjectSettings.globalize_path(GRANDES) + unit_name + "_time.png")
	var target := Vector2i(roundi(w * scale), roundi(h * scale))
	for img: Image in [crop, mask]:
		var current: Vector2i = img.get_size()
		while current.x > target.x * 2:
			current /= 2
			img.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
		img.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var sprite := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var sprite_mask := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var at := Vector2i((SIZE - target.x) / 2, FEET - target.y)
	sprite.blit_rect(crop, Rect2i(Vector2i.ZERO, target), at)
	mask.convert(Image.FORMAT_L8)
	sprite_mask.blit_rect(mask, Rect2i(Vector2i.ZERO, target), at)
	for dir in [UNITS, PRONTOS]:
		sprite.save_png(ProjectSettings.globalize_path(dir) + unit_name + ".png")
		sprite_mask.save_png(ProjectSettings.globalize_path(dir) + unit_name + "_time.png")
	print("ok: %s (%dx%d -> %s)" % [unit_name, w, h, target])
