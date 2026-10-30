class_name StoneStyle
extends RefCounted

## Estilo "pedra" das janelas (proposta de 28/10/2026, em avaliação): fundo de
## mármore (assets/ui/marmore*.png, tools/art/gen_marmore.gd), borda CHANFRADA
## como uma lápide talhada (faixa inclinada clara em cima e à esquerda, onde a
## luz bate, e escura embaixo e à direita) e separadores ENTALHADOS (um sulco:
## linha escura com um fio claro logo abaixo).

const MARBLE: Texture2D = preload("res://assets/ui/marmore.png")
## Largura do chanfro, em pixels.
const BEVEL := 16.0
const LIGHT := Color(1, 1, 1, 0.8)
const SHADOW := Color(0.2, 0.19, 0.17, 0.7)
const EDGE := Color(0.25, 0.23, 0.21, 0.85)
## Texto escuro sobre o mármore.
const INK := Color8(40, 36, 33)
const INK_MUTED := Color8(78, 71, 64)
const BRONZE := Color8(122, 74, 28)
## Cores com significado, escurecidas para ler sobre o mármore.
const POSITIVE := Color8(34, 110, 44)
const NEGATIVE := Color8(170, 46, 28)
const WARNING := Color8(176, 88, 18)
const SCIENCE := Color8(28, 86, 150)

static var _theme: Theme


## Tema das janelas de pedra (posto no nó raiz de cada janela): texto escuro,
## campos de texto claros e botões de pedra de reserva (os botões feitos por
## CityWindow.style_button ganham o relevo completo).
static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.set_color("font_color", "Label", INK)
	_theme.set_color("default_color", "RichTextLabel", INK)
	_theme.set_color("font_color", "LineEdit", INK)
	_theme.set_color("caret_color", "LineEdit", INK)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.75)
	field.border_color = Color(EDGE, 0.6)
	field.set_border_width_all(1)
	field.set_corner_radius_all(3)
	field.set_content_margin_all(6)
	_theme.set_stylebox("normal", "LineEdit", field)
	_theme.set_stylebox("focus", "LineEdit", field)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var button := StyleBoxFlat.new()
		button.bg_color = {"normal": Color(0.88, 0.87, 0.84), "hover": Color(0.95, 0.94, 0.92),
				"pressed": Color(0.8, 0.79, 0.76), "disabled": Color(0.85, 0.84, 0.82, 0.6)}[state]
		button.border_color = Color(EDGE, 0.7)
		button.set_border_width_all(1)
		button.set_corner_radius_all(3)
		button.set_content_margin_all(6)
		_theme.set_stylebox(state, "Button", button)
	_theme.set_color("font_color", "Button", Color8(70, 44, 18))
	_theme.set_color("font_hover_color", "Button", Color8(95, 58, 22))
	_theme.set_color("font_pressed_color", "Button", Color8(70, 44, 18))
	_theme.set_color("font_disabled_color", "Button", Color8(140, 132, 124))
	# Dica (tooltip) das janelas de pedra: placa clara com texto escuro (com o
	# texto escuro do tema, a dica escura padrão ficava ilegível)
	var tooltip := StyleBoxFlat.new()
	tooltip.bg_color = Color8(246, 243, 236)
	tooltip.border_color = Color(BRONZE, 0.7)
	tooltip.set_border_width_all(1)
	tooltip.set_corner_radius_all(3)
	tooltip.set_content_margin_all(8)
	tooltip.shadow_color = Color(0, 0, 0, 0.25)
	tooltip.shadow_size = 4
	_theme.set_stylebox("panel", "TooltipPanel", tooltip)
	_theme.set_color("font_color", "TooltipLabel", INK)
	return _theme


## Fundo de mármore com margem para o chanfro (o desenho do chanfro vem de
## draw_bevel, ligado ao draw do painel).
static func panel_style(texture: Texture2D = MARBLE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.set_content_margin_all(BEVEL + 14.0)
	return style


## Aplica o mármore e o chanfro a [param panel].
static func apply(panel: Control, texture: Texture2D = MARBLE) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(texture))
	panel.draw.connect(func() -> void: draw_bevel(panel, Rect2(Vector2.ZERO, panel.size)))
	panel.queue_redraw()


## Chanfro de lápide em volta de [param rect]: quatro trapézios (a faixa
## inclinada de cada lado), com luz vinda de cima à esquerda, e um contorno
## escuro na aresta de fora e um fio na de dentro.
static func draw_bevel(canvas: CanvasItem, rect: Rect2, bevel := BEVEL) -> void:
	if rect.size.x <= bevel * 2.0 + 2.0 or rect.size.y <= bevel * 2.0 + 2.0:
		return
	var o := rect.position
	var e := rect.end
	var i0 := o + Vector2(bevel, bevel)
	var i1 := e - Vector2(bevel, bevel)
	var top := PackedVector2Array([o, Vector2(e.x, o.y), Vector2(i1.x, i0.y), i0])
	var left := PackedVector2Array([o, i0, Vector2(i0.x, i1.y), Vector2(o.x, e.y)])
	var right := PackedVector2Array([Vector2(e.x, o.y), e, i1, Vector2(i1.x, i0.y)])
	var bottom := PackedVector2Array([Vector2(o.x, e.y), Vector2(i0.x, i1.y), i1, e])
	canvas.draw_colored_polygon(top, LIGHT)
	canvas.draw_colored_polygon(left, Color(LIGHT, LIGHT.a * 0.65))
	canvas.draw_colored_polygon(right, Color(SHADOW, SHADOW.a * 0.7))
	canvas.draw_colored_polygon(bottom, SHADOW)
	# Arestas: a de fora escura; a de dentro, sombra em cima/esquerda e luz embaixo/direita
	canvas.draw_rect(rect.grow(-0.5), EDGE, false, 1.5)
	canvas.draw_line(i0, Vector2(i1.x, i0.y), Color(SHADOW, 0.35), 1.0)
	canvas.draw_line(i0, Vector2(i0.x, i1.y), Color(SHADOW, 0.35), 1.0)
	canvas.draw_line(Vector2(i0.x, i1.y), i1, Color(LIGHT, 0.8), 1.0)
	canvas.draw_line(Vector2(i1.x, i0.y), i1, Color(LIGHT, 0.6), 1.0)
	# Diagonais dos cantos (as quinas do chanfro)
	for corner in [[o, i0], [Vector2(e.x, o.y), Vector2(i1.x, i0.y)], [e, i1], [Vector2(o.x, e.y), Vector2(i0.x, i1.y)]]:
		canvas.draw_line(corner[0], corner[1], Color(SHADOW, 0.3), 1.0)


## Botão de PEDRA EM RELEVO (mais alto que o fundo): placa de mármore mais
## clara, com chanfro (luz em cima e à esquerda), contorno e sombra projetada
## embaixo à direita. Mouse em cima: mais clara. Apertado: afunda (sem sombra,
## chanfro invertido). Desabilitado: plana e apagada. Texto em bronze escuro.
static func style_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxEmpty.new()
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 7
		style.content_margin_bottom = 9
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color8(70, 44, 18))
	button.add_theme_color_override("font_hover_color", Color8(95, 58, 22))
	button.add_theme_color_override("font_pressed_color", Color8(70, 44, 18))
	button.add_theme_color_override("font_disabled_color", Color8(140, 132, 124))
	button.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.5))
	button.add_theme_constant_override("outline_size", 2)
	# A placa é desenhada num filho atrás do botão (o sinal draw do próprio botão
	# vem DEPOIS do texto e cobriria as letras)
	var plate := Control.new()
	plate.name = "StonePlate"
	plate.show_behind_parent = true
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.draw.connect(func() -> void: _draw_raised(button, plate))
	button.add_child(plate)
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "toggled"]:
		button.connect(signal_name, plate.queue_redraw.unbind(1) if signal_name == "toggled" else plate.queue_redraw)
	# Botão de menu: ele fica "apertado" enquanto a lista está aberta e solta
	# quando ela fecha, sem button_up (a placa ficava desenhada afundada)
	if button is MenuButton:
		var popup := (button as MenuButton).get_popup()
		popup.popup_hide.connect(plate.queue_redraw.call_deferred)
		popup.about_to_popup.connect(plate.queue_redraw)


static func _draw_raised(button: Button, canvas: Control) -> void:
	var pressed := button.is_pressed() or button.button_pressed
	var hover := button.is_hovered() and not button.disabled
	var rect := Rect2(Vector2.ZERO, button.size)
	var plate := rect.grow_individual(0, 0, -3, -3)
	if plate.size.x < 12.0 or plate.size.y < 12.0:
		return # ainda sem tamanho (antes do layout)
	if pressed:
		plate.position += Vector2(2, 2)
	elif not button.disabled:
		# Sombra projetada (a placa está acima do fundo)
		canvas.draw_rect(Rect2(plate.position + Vector2(3, 3), plate.size), Color(0, 0, 0, 0.35))
	var face := Color(0.97, 0.96, 0.94) if hover else Color(0.9, 0.89, 0.86)
	if button.disabled:
		face = Color(0.82, 0.81, 0.79, 0.7)
	canvas.draw_texture_rect(MARBLE, plate, true, face)
	var bevel := 4.0 if not button.disabled else 1.5
	var light := Color(1, 1, 1, 0.85)
	var dark := Color(0.25, 0.23, 0.2, 0.55)
	var o := plate.position
	var e := plate.end
	var i0 := o + Vector2(bevel, bevel)
	var i1 := e - Vector2(bevel, bevel)
	var top := PackedVector2Array([o, Vector2(e.x, o.y), Vector2(i1.x, i0.y), i0])
	var left := PackedVector2Array([o, i0, Vector2(i0.x, i1.y), Vector2(o.x, e.y)])
	var right := PackedVector2Array([Vector2(e.x, o.y), e, i1, Vector2(i1.x, i0.y)])
	var bottom := PackedVector2Array([Vector2(o.x, e.y), Vector2(i0.x, i1.y), i1, e])
	canvas.draw_colored_polygon(top, dark if pressed else light)
	canvas.draw_colored_polygon(left, Color(dark if pressed else light, 0.6))
	canvas.draw_colored_polygon(right, Color(light if pressed else dark, 0.6))
	canvas.draw_colored_polygon(bottom, light if pressed else dark)
	canvas.draw_rect(plate, EDGE, false, 1.5)


## Barra de progresso numa VALA talhada na pedra: canaleta funda (fundo
## escuro), sombra nas paredes de cima e da esquerda, luz no lábio de baixo e
## da direita, e a barra colorida lá no fundo, com um brilho na parte de cima.
static func style_progress(bar: ProgressBar, fill_color: Color) -> void:
	var empty := StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("background", empty)
	bar.add_theme_stylebox_override("fill", empty)
	bar.custom_minimum_size.y = maxf(bar.custom_minimum_size.y, 18.0)
	bar.draw.connect(func() -> void: _draw_trench(bar, fill_color))


static func _draw_trench(bar: ProgressBar, fill_color: Color) -> void:
	var r := Rect2(Vector2.ZERO, bar.size)
	if r.size.x < 12.0 or r.size.y < 10.0:
		return # ainda sem tamanho (antes do layout)
	var wall := 4.0
	# Fundo da vala (avermelhado com a meta "stone_alert": obra parada)
	bar.draw_rect(r, Color(0.38, 0.1, 0.08) if bar.get_meta("stone_alert", false) else Color(0.16, 0.15, 0.14))
	# Barra no fundo (recuada das paredes)
	var inner := r.grow(-wall)
	var ratio := 0.0 if bar.max_value <= bar.min_value else clampf((bar.value - bar.min_value) / (bar.max_value - bar.min_value), 0, 1)
	if ratio > 0.0:
		var fill := Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y))
		bar.draw_rect(fill, fill_color.darkened(0.15))
		bar.draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.35)), Color(fill_color.lightened(0.25), 0.9))
	# Paredes: sombra em cima e à esquerda (a pedra cobre a luz), luz no lábio de baixo e da direita
	var o := r.position
	var e := r.end
	var i0 := o + Vector2(wall, wall)
	var i1 := e - Vector2(wall, wall)
	bar.draw_colored_polygon(PackedVector2Array([o, Vector2(e.x, o.y), Vector2(i1.x, i0.y), i0]), Color(0, 0, 0, 0.7))
	bar.draw_colored_polygon(PackedVector2Array([o, i0, Vector2(i0.x, i1.y), Vector2(o.x, e.y)]), Color(0, 0, 0, 0.55))
	bar.draw_colored_polygon(PackedVector2Array([Vector2(e.x, o.y), e, i1, Vector2(i1.x, i0.y)]), Color(1, 1, 1, 0.35))
	bar.draw_colored_polygon(PackedVector2Array([Vector2(o.x, e.y), Vector2(i0.x, i1.y), i1, e]), Color(1, 1, 1, 0.6))
	# Sombra que a parede de cima joga no fundo
	bar.draw_rect(Rect2(i0, Vector2(i1.x - i0.x, 3)), Color(0, 0, 0, 0.35))


## Separador entalhado: um controle fino com o sulco (linha escura e um fio
## claro logo abaixo), mais fino nas pontas.
static func separator(height := 10.0) -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, height)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void: draw_groove(line, Vector2(0, height / 2.0), Vector2(line.size.x, height / 2.0)))
	return line


## O sulco entre [param a] e [param b] (horizontal): some nas pontas.
static func draw_groove(canvas: CanvasItem, a: Vector2, b: Vector2) -> void:
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var fade := sin(PI * (t0 + t1) / 2.0) # 0 nas pontas, 1 no meio
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		canvas.draw_line(p0, p1, Color(0.2, 0.18, 0.16, 0.9 * fade), 2.5)
		canvas.draw_line(p0 + Vector2(0, 2.5), p1 + Vector2(0, 2.5), Color(1, 1, 1, 0.95 * fade), 1.5)
