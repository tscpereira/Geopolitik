class_name StonePanelBox
extends StyleBox

## Fundo de pedra das janelas (StoneStyle): o mármore repetido e o chanfro de
## lápide em volta (faixas inclinadas claras em cima e à esquerda, escuras
## embaixo e à direita). Por ser um StyleBox, vale em qualquer PanelContainer
## (CityWindow.make_panel_style).

var texture: Texture2D = StoneStyle.MARBLE
var bevel := StoneStyle.BEVEL


func _init() -> void:
	set_content_margin_all(StoneStyle.BEVEL + 12.0)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if rect.size.x <= bevel * 2.0 + 2.0 or rect.size.y <= bevel * 2.0 + 2.0:
		return # ainda sem tamanho (antes do layout): os trapézios não fecham
	rs.canvas_item_add_texture_rect(to_canvas_item, rect, texture.get_rid(), true)
	var o := rect.position
	var e := rect.end
	var i0 := o + Vector2(bevel, bevel)
	var i1 := e - Vector2(bevel, bevel)
	var light := StoneStyle.LIGHT
	var shadow := StoneStyle.SHADOW
	_quad(to_canvas_item, [o, Vector2(e.x, o.y), Vector2(i1.x, i0.y), i0], light)
	_quad(to_canvas_item, [o, i0, Vector2(i0.x, i1.y), Vector2(o.x, e.y)], Color(light, light.a * 0.65))
	_quad(to_canvas_item, [Vector2(e.x, o.y), e, i1, Vector2(i1.x, i0.y)], Color(shadow, shadow.a * 0.7))
	_quad(to_canvas_item, [Vector2(o.x, e.y), Vector2(i0.x, i1.y), i1, e], shadow)
	# Arestas: contorno escuro por fora; por dentro, sombra em cima/esquerda e luz embaixo/direita
	var edge := StoneStyle.EDGE
	for pair in [[o, Vector2(e.x, o.y)], [Vector2(e.x, o.y), e], [e, Vector2(o.x, e.y)], [Vector2(o.x, e.y), o]]:
		rs.canvas_item_add_line(to_canvas_item, pair[0], pair[1], edge, 1.5)
	rs.canvas_item_add_line(to_canvas_item, i0, Vector2(i1.x, i0.y), Color(shadow, 0.35), 1.0)
	rs.canvas_item_add_line(to_canvas_item, i0, Vector2(i0.x, i1.y), Color(shadow, 0.35), 1.0)
	rs.canvas_item_add_line(to_canvas_item, Vector2(i0.x, i1.y), i1, Color(light, 0.8), 1.0)
	rs.canvas_item_add_line(to_canvas_item, Vector2(i1.x, i0.y), i1, Color(light, 0.6), 1.0)
	for corner in [[o, i0], [Vector2(e.x, o.y), Vector2(i1.x, i0.y)], [e, i1], [Vector2(o.x, e.y), Vector2(i0.x, i1.y)]]:
		rs.canvas_item_add_line(to_canvas_item, corner[0], corner[1], Color(shadow, 0.3), 1.0)


func _quad(item: RID, points: Array, color: Color) -> void:
	RenderingServer.canvas_item_add_polygon(item, PackedVector2Array(points), PackedColorArray([color]))
