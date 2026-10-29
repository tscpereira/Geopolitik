extends SceneTree

## Gera as texturas de MÁRMORE do fundo das janelas (proposta de 28/10/2026),
## sem emenda (repetem lado a lado), por ruído:
##   - base branca levemente acinzentada, com nuvens suaves (ruído de baixa
##     frequência);
##   - veios cinza: as cristas de um ruído "ridged" deformado por outro
##     (domain warp), finos e irregulares;
##   - na versão dourada, um segundo conjunto de veios, mais raros, em ouro.
##   godot_console.cmd --headless --path . --script tools/art/gen_marmore.gd
## Grava assets/ui/marmore.png e assets/ui/marmore_dourado.png (512x512).

const SIZE := 512
const OUT := "res://assets/ui/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_make("marmore", false)
	_make("marmore_dourado", true)
	quit()


func _noise(seed: int, frequency: float, type: FastNoiseLite.FractalType, octaves: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = type
	noise.fractal_octaves = octaves
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = 40.0
	noise.domain_warp_frequency = frequency * 0.8
	return noise.get_seamless_image(SIZE, SIZE, false, false, 0.15)


func _make(name: String, gold: bool) -> void:
	# Os veios seguem as LINHAS DE NÍVEL do ruído (onde ele cruza 0,5): linhas
	# contínuas e sinuosas, finas onde o ruído muda rápido
	var clouds := _noise(11, 0.004, FastNoiseLite.FRACTAL_FBM, 5)
	var veins := _noise(23, 0.003, FastNoiseLite.FRACTAL_FBM, 5)
	var fine := _noise(37, 0.008, FastNoiseLite.FRACTAL_FBM, 4)
	var gold_veins := _noise(53, 0.0025, FastNoiseLite.FRACTAL_FBM, 4)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var base := Color(0.95, 0.945, 0.935)
	var shade := Color(0.84, 0.845, 0.86)
	var vein_color := Color(0.62, 0.64, 0.68)
	var gold_color := Color(0.80, 0.62, 0.26)
	for y in SIZE:
		for x in SIZE:
			var c := base.lerp(shade, smoothstep(0.35, 0.8, clouds.get_pixel(x, y).r) * 0.75)
			var v := 1.0 - smoothstep(0.0, 0.012, absf(veins.get_pixel(x, y).r - 0.5))
			var halo := (1.0 - smoothstep(0.0, 0.05, absf(veins.get_pixel(x, y).r - 0.5))) * 0.25
			var f := (1.0 - smoothstep(0.0, 0.006, absf(fine.get_pixel(x, y).r - 0.47))) * 0.5
			c = c.lerp(vein_color, clampf(v * 0.6 + halo * 0.6 + f * 0.45, 0.0, 0.6))
			if gold:
				var g := 1.0 - smoothstep(0.0, 0.008, absf(gold_veins.get_pixel(x, y).r - 0.55))
				c = c.lerp(gold_color, g * 0.75)
			image.set_pixel(x, y, c)
	image.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("gravado %s%s.png" % [OUT, name])
