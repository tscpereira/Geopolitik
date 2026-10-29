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


## Passa a vez para o próximo jogador que ainda está no jogo (o derrotado,
## Player.eliminated, é pulado).
func end_turn() -> void:
	turn_ended.emit(current_player())
	for i in players.size():
		current_index = (current_index + 1) % players.size()
		if current_index == 0:
			turn_number += 1
		if not current_player().eliminated:
			break
	_begin_turn()


## Vez e número do turno, para o save (ver SaveGame).
func to_dict() -> Dictionary:
	return {"current_index": current_index, "turn_number": turn_number}


## Volta à vez de um jogo salvo, sem começar o turno de novo (as cidades já
## produziram no início desta vez; ver Game.restore_state).
func restore(p_players: Array[Player], data: Dictionary) -> void:
	players = p_players
	current_index = int(data["current_index"])
	turn_number = int(data["turn_number"])


func _begin_turn() -> void:
	current_player().start_turn()
	turn_started.emit(current_player(), turn_number)
