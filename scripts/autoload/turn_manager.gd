extends Node

## Controla a ordem dos turnos entre os jogadores.

signal turn_started(player: Player, turn_number: int)
signal turn_ended(player: Player)

var players: Array[Player] = []
var current_index := 0
var turn_number := 1


func current_player() -> Player:
	return players[current_index]


func start_game(p_players: Array[Player]) -> void:
	players = p_players
	current_index = 0
	turn_number = 1
	_begin_turn()


func end_turn() -> void:
	turn_ended.emit(current_player())
	current_index = (current_index + 1) % players.size()
	if current_index == 0:
		turn_number += 1
	_begin_turn()


func _begin_turn() -> void:
	current_player().start_turn()
	turn_started.emit(current_player(), turn_number)
