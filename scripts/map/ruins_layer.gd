class_name RuinsLayer
extends Node2D

## Ruínas sem dono no mapa, deixadas por uma cidade saqueada e destruída
## (Game.raze_city):
##   cities       {casa: nome}   a cidade em ruínas (sprite cidade_destruida.png
##                               e "Ruínas de <nome>" embaixo);
##   improvements {casa: {"build", "progress"}}  fazendas e madeireiras dela,
##                               destruídas (mesmo desenho das ruínas pilhadas).
## Ninguém reconstrói uma ruína sem dono. Uma cidade fundada depois cujo
## território pegue a casa fica com a ruína (Game._claim_territory), e aí um
## Trabalhador dela pode reconstruir. Fundar na casa da cidade em ruínas apaga
## a ruína.

const TEXTURE: Texture2D = preload("res://assets/sprites/improvements/cidade_destruida.png")
const NAME_COLOR := Color(0.8, 0.78, 0.74)

var cities := {}
var improvements := {}


func _draw() -> void:
	var tile := Vector2.ONE * GameMap.TILE_SIZE
	var map: GameMap = get_parent().get_node("GameMap")
	for cell: Vector2i in improvements:
		City.draw_ruin(self, improvements[cell]["build"], Rect2(to_local(map.cell_to_world(cell)) - tile / 2.0, tile))
	var font := ThemeDB.fallback_font
	for cell: Vector2i in cities:
		var center := to_local(map.cell_to_world(cell))
		draw_texture_rect(TEXTURE, Rect2(center - tile / 2.0, tile), false)
		var text := "Ruínas de %s" % cities[cell]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE).x
		var origin := center + Vector2(-width / 2.0, tile.y / 2.0 + City.NAME_FONT_SIZE)
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE, City.NAME_FONT_SIZE / 3, Color.BLACK)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE, NAME_COLOR)


## Para o save.
func to_dict() -> Dictionary:
	return {
		"cities": cities.keys().map(func(cell: Vector2i) -> Array: return [cell.x, cell.y, cities[cell]]),
		"improvements": improvements.keys().map(func(cell: Vector2i) -> Array:
			return [cell.x, cell.y, improvements[cell]["build"], improvements[cell]["progress"]]),
	}


func from_dict(data: Dictionary) -> void:
	cities.clear()
	improvements.clear()
	for entry: Array in data.get("cities", []):
		cities[Vector2i(int(entry[0]), int(entry[1]))] = entry[2]
	for entry: Array in data.get("improvements", []):
		improvements[Vector2i(int(entry[0]), int(entry[1]))] = {"build": int(entry[2]), "progress": int(entry[3])}
	queue_redraw()
