extends SceneTree

## Ajusta o tamanho dos desenhos das cidades (e das ruínas) para crescerem a
## cada nível (26/10/2026, pedido do usuário): o desenho de cada classe passa a
## ter a largura de WIDTH, centralizado e com a base na linha BOTTOM. Mede a
## largura atual (a parte não transparente) e redimensiona até a da classe;
## rodar de novo não muda nada (o que já está na largura certa fica). A
## máscara da cor do dono (_time.png) passa pela mesma transformação.
##   godot_console.cmd --headless --path . --script tools/art/ajusta_tamanho_cidades.gd
## O importador das cidades do Gemini (import_cidades_gemini.gd, MAX_WIDTH) já
## grava nessas larguras.

const CITIES := "res://assets/sprites/cities/"
const SIZE := 128
const BOTTOM := 124
const WIDTH := {"povoado": 74, "vila": 92, "cidade": 108, "metropole": 122}
const VARIANTS := ["", "_capital", "_muralha", "_capital_muralha", "_ruinas", "_muralha_ruinas"]


func _initialize() -> void:
	for rank: String in WIDTH:
		for variant: String in VARIANTS:
			var name: String = rank + variant
			if FileAccess.file_exists(ProjectSettings.globalize_path(CITIES + name + ".png")):
				_fit(name, WIDTH[rank])
	quit()


func _fit(name: String, width: int) -> void:
	var path := ProjectSettings.globalize_path(CITIES + name + ".png")
	var image := Image.load_from_file(path)
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if absi(used.size.x - width) <= 3: # versões da mesma cidade do Gemini variam 1-2 px (escala comum)
		print("%s: já tem %d px" % [name, used.size.x])
		return
	var scale := float(width) / used.size.x
	var target := Vector2i(width, maxi(1, roundi(used.size.y * scale)))
	_place(image.get_region(used), target).save_png(path)
	var mask_path := ProjectSettings.globalize_path(CITIES + name + "_time.png")
	if FileAccess.file_exists(mask_path):
		var mask := Image.load_from_file(mask_path)
		mask.convert(Image.FORMAT_RGBA8)
		var placed := _place(mask.get_region(used), target)
		placed.convert(Image.FORMAT_L8)
		placed.save_png(mask_path)
	print("%s: %d -> %d px de largura" % [name, used.size.x, width])


## O recorte reduzido (ou ampliado) para [param target], num quadro SIZE x SIZE
## centralizado na horizontal e com a base em BOTTOM.
func _place(crop: Image, target: Vector2i) -> Image:
	var current := crop.get_size()
	while current.x > target.x * 2:
		current /= 2
		crop.resize(current.x, current.y, Image.INTERPOLATE_BILINEAR)
	crop.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.blit_rect(crop, Rect2i(Vector2i.ZERO, target), Vector2i((SIZE - target.x) / 2, BOTTOM - target.y))
	return out
