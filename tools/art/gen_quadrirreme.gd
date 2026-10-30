extends SceneTree

## Desenho PROVISÓRIO do Quadrirreme (29/10/2026), até vir o do Gemini: a Galé
## espelhada (virada para o outro lado) e com a madeira mais escura, para não
## confundir as duas no mapa. Gera o sprite, a máscara da cor do time e o
## retrato (assets/sprites/units/ e retratos/). Rode na pasta do projeto:
##   godot_console.cmd --headless --path . --script tools/art/gen_quadrirreme.gd

const UNITS := "res://assets/sprites/units/"


func _initialize() -> void:
	for folder in [UNITS, UNITS + "retratos/"]:
		var path := ProjectSettings.globalize_path(folder)
		var image := Image.load_from_file(path + "gale.png")
		image.convert(Image.FORMAT_RGBA8)
		image.flip_x()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				# Madeira (tons quentes): mais escura e avermelhada
				if c.a > 0.0 and c.r > c.b + 0.08:
					image.set_pixel(x, y, Color(c.r * 0.72, c.g * 0.6, c.b * 0.55, c.a))
		image.save_png(path + "quadrirreme.png")
		if FileAccess.file_exists(path + "gale_time.png"):
			var mask := Image.load_from_file(path + "gale_time.png")
			mask.flip_x()
			mask.save_png(path + "quadrirreme_time.png")
		print("ok: ", folder)
	quit()
