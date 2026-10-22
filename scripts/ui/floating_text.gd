class_name FloatingText
extends Node2D

## Texto que sobe e desaparece sobre o mapa (ex.: dano "-30" sobre a unidade).

const FONT_SIZE := int(GameMap.TILE_SIZE * 0.55)
const DURATION := 0.9
const RISE := GameMap.TILE_SIZE * 1.0

var _text := ""
var _color := Color.WHITE


## [param delay] segura o texto antes de aparecer (útil para não sobrepor dois textos).
static func spawn(parent: Node, world_position: Vector2, text: String, color: Color, delay := 0.0) -> void:
	var floating := FloatingText.new()
	floating._text = text
	floating._color = color
	floating.position = world_position
	floating.z_index = 10
	parent.add_child(floating)

	var tween := floating.create_tween()
	if delay > 0.0:
		floating.hide()
		tween.tween_interval(delay)
		tween.tween_callback(floating.show)
	tween.tween_property(floating, "position:y", world_position.y - RISE, DURATION)
	tween.parallel().tween_property(floating, "modulate:a", 0.0, DURATION * 0.5).set_delay(DURATION * 0.5)
	tween.tween_callback(floating.queue_free)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var origin := Vector2(-font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x / 2.0, 0)
	draw_string_outline(font, origin, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, FONT_SIZE / 4, Color.BLACK)
	draw_string(font, origin, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _color)
