class_name RuinsLayer
extends Node2D

## Ruínas sem dono no mapa, deixadas por uma cidade saqueada e destruída
## (Game.raze_city):
##   cities       {casa: {"name": nome, "rank": City.Rank, "walls": bool}}
##                               a cidade em ruínas, com o desenho da classe
##                               que ela tinha, com ou sem muralha
##                               (RUIN_SPRITES: uma metrópole vira uma grande
##                               cidade em ruínas) e "Ruínas de <nome>" embaixo;
##   improvements {casa: {"build", "progress"}}  fazendas e madeireiras dela,
##                               destruídas (mesmo desenho das ruínas pilhadas).
## Ninguém reconstrói uma ruína sem dono. Uma cidade fundada depois cujo
## território pegue a casa fica com a ruína (Game._claim_territory), e aí um
## Trabalhador dela pode reconstruir. Fundar na casa da cidade em ruínas apaga
## a ruína.

## Ruínas de cada classe, [sem muralha, com muralha] (PNGs de 128x128 em
## assets/sprites/cities/, <classe>[_muralha]_ruinas.png, gerados por
## tools/art/gen_art.gd a partir da cidade normal intacta). A capital usa a
## mesma ruína: o desmoronamento leva o alto, onde ficava o templo.
## Desenhadas no tamanho e na posição da cidade (City.SPRITE_SIZE).
const RUIN_SPRITES := {
	City.Rank.SETTLEMENT: [
		preload("res://assets/sprites/cities/povoado_ruinas.png"), preload("res://assets/sprites/cities/povoado_muralha_ruinas.png")],
	City.Rank.TOWN: [
		preload("res://assets/sprites/cities/vila_ruinas.png"), preload("res://assets/sprites/cities/vila_muralha_ruinas.png")],
	City.Rank.CITY: [
		preload("res://assets/sprites/cities/cidade_ruinas.png"), preload("res://assets/sprites/cities/cidade_muralha_ruinas.png")],
	City.Rank.METROPOLIS: [
		preload("res://assets/sprites/cities/metropole_ruinas.png"), preload("res://assets/sprites/cities/metropole_muralha_ruinas.png")],
}
const NAME_COLOR := Color(0.8, 0.78, 0.74)

var cities := {}
var improvements := {}


## Marca as ruínas da cidade [param city_name], da classe [param rank], com ou
## sem muralha, na casa.
func add_city(cell: Vector2i, city_name: String, rank: City.Rank, walls := false) -> void:
	cities[cell] = {"name": city_name, "rank": rank, "walls": walls}
	queue_redraw()


func city_name_at(cell: Vector2i) -> String:
	return cities[cell]["name"]


func _draw() -> void:
	var tile := Vector2.ONE * GameMap.TILE_SIZE
	var map: GameMap = get_parent().get_node("GameMap")
	for cell: Vector2i in improvements:
		City.draw_ruin(self, improvements[cell]["build"], Rect2(to_local(map.cell_to_world(cell)) - tile / 2.0, tile))
	var font := ThemeDB.fallback_font
	for cell: Vector2i in cities:
		var center := to_local(map.cell_to_world(cell))
		# Mesmo lugar e tamanho do desenho da cidade (City._draw)
		var sprite := City.sprite_rect(cities[cell]["rank"])
		sprite.position += center
		draw_texture_rect(RUIN_SPRITES[cities[cell]["rank"]][int(cities[cell]["walls"])], sprite, false)
		var text := "Ruínas de %s" % cities[cell]["name"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE).x
		var origin := Vector2(center.x - width / 2.0, sprite.end.y + City.NAME_FONT_SIZE * 0.9)
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE, City.NAME_FONT_SIZE / 3, Color.BLACK)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, City.NAME_FONT_SIZE, NAME_COLOR)


## Para o save: [x, y, nome, classe, muralha] e [x, y, melhoria, progresso].
func to_dict() -> Dictionary:
	return {
		"cities": cities.keys().map(func(cell: Vector2i) -> Array:
			return [cell.x, cell.y, cities[cell]["name"], cities[cell]["rank"], cities[cell]["walls"]]),
		"improvements": improvements.keys().map(func(cell: Vector2i) -> Array:
			return [cell.x, cell.y, improvements[cell]["build"], improvements[cell]["progress"]]),
	}


## Save antigo sem a classe: as ruínas aparecem como as de um povoado; sem a
## muralha: sem muralha.
func from_dict(data: Dictionary) -> void:
	cities.clear()
	improvements.clear()
	for entry: Array in data.get("cities", []):
		var rank: int = int(entry[3]) if entry.size() > 3 else City.Rank.SETTLEMENT
		var walls: bool = bool(entry[4]) if entry.size() > 4 else false
		cities[Vector2i(int(entry[0]), int(entry[1]))] = {"name": entry[2], "rank": rank, "walls": walls}
	for entry: Array in data.get("improvements", []):
		improvements[Vector2i(int(entry[0]), int(entry[1]))] = {"build": int(entry[2]), "progress": int(entry[3])}
	queue_redraw()
