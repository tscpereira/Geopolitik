class_name Diplomacy
extends RefCounted

## Diplomacia entre os jogadores (fase 1, 30/10/2026; pedido do usuário):
##
## ENCONTRO: dois jogadores se conhecem quando um vê uma unidade ou cidade do
## outro (Game._check_contacts). A relação começa em PAZ. Quem nunca se
## encontrou também não briga (não há como: um nem vê o outro).
##
## ESTADOS (por par de jogadores):
##   Paz      ninguém ataca ninguém e ninguém entra no território do outro
##            (Movement.can_enter); pilhar também não.
##   Guerra   atacar, invadir e pilhar valem. Só se chega a ela declarando:
##            declaração formal (declare_war) ou GUERRA SURPRESA (atacar uma
##            unidade de quem está em paz, sem aviso: traição).
##   Aliado   (fase 4) paz com fronteiras abertas e defesa mútua.
## Depois de um tratado de paz há uma TRÉGUA de TRUCE_TURNS turnos em que
## ninguém declara guerra.
##
## CONFIANÇA: como cada jogador vê cada outro, de -100 a +100 (não é simétrica:
## o que A pensa de B), em quatro faixas: Furioso, Indiferente, Amigável e
## Irmandade (trust_level). A máquina a usa para decidir guerra, paz e, nas
## próximas fases, negociações. Mexem nela: declarar guerra, guerra surpresa
## (também para quem conhece o traidor), ataques, cidades tomadas, inimigo em
## comum, paz longa, e o tempo, que a puxa devagar de volta ao zero.

enum State { PEACE, WAR, ALLIED }
enum Trust { FURIOUS, INDIFFERENT, FRIENDLY, BROTHERHOOD }

const STATE_NAMES := {State.PEACE: "Paz", State.WAR: "Guerra", State.ALLIED: "Aliado"}
const TRUST_NAMES := {
	Trust.FURIOUS: "Furioso", Trust.INDIFFERENT: "Indiferente",
	Trust.FRIENDLY: "Amigável", Trust.BROTHERHOOD: "Irmandade",
}
## Faixas: até FURIOUS_MAX é Furioso; até INDIFFERENT_MAX, Indiferente; até
## FRIENDLY_MAX, Amigável; acima, Irmandade.
const TRUST_MIN := -100
const TRUST_MAX := 100
const FURIOUS_MAX := -41
const INDIFFERENT_MAX := 20
const FRIENDLY_MAX := 60
## Variações de confiança (de quem sofre/vê, em relação a quem fez).
const DECLARE_WAR_TRUST := -50
const SURPRISE_WAR_TRUST := -80
const SURPRISE_WAR_WITNESS_TRUST := -20
const ATTACKED_TRUST := -5
const CITY_LOST_TRUST := -30
const PEACE_SIGNED_TRUST := 10
## Por turno, com um inimigo em comum (os dois em guerra com o mesmo jogador).
const COMMON_ENEMY_TRUST := 2
## +1 a cada LONG_PEACE_TURNS turnos de paz seguidos.
const LONG_PEACE_TURNS := 10
## Fora da guerra, a confiança volta 1 ponto para o zero a cada DRIFT_TURNS.
const DRIFT_TURNS := 5
## Trégua depois do tratado de paz.
const TRUCE_TURNS := 10
## Mínimo de turnos entre duas propostas do mesmo jogador para o mesmo outro.
const PROPOSAL_INTERVAL := 5

## Turno atual (o Game atualiza no começo de cada vez).
var turn := 1
var _met := {}           # "a:b" -> turno do encontro
var _state := {}         # "a:b" -> State
var _since := {}         # "a:b" -> turno em que o estado atual começou
var _truce_until := {}   # "a:b" -> turno em que a trégua acaba
var _trust := {}         # "a>b" -> o que a pensa de b
var _last_proposal := {} # "a>b" -> turno da última proposta de a para b


static func _pair(a: Player, b: Player) -> String:
	return "%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]


static func _arrow(from: Player, to: Player) -> String:
	return "%d>%d" % [from.id, to.id]


# --- Encontro e estado ---------------------------------------------------------

func have_met(a: Player, b: Player) -> bool:
	return a == b or _met.has(_pair(a, b))


## Primeiro encontro: a relação começa em paz. Retorna false se já se conheciam.
func meet(a: Player, b: Player) -> bool:
	if have_met(a, b):
		return false
	_met[_pair(a, b)] = turn
	set_state(a, b, State.PEACE)
	return true


## Jogadores que [param player] conhece (sem ele mesmo), na ordem de [param players].
func known_players(player: Player, players: Array) -> Array:
	return players.filter(func(other: Player) -> bool: return other != player and have_met(player, other))


func state(a: Player, b: Player) -> State:
	return _state.get(_pair(a, b), State.PEACE)


func at_war(a: Player, b: Player) -> bool:
	return a != b and state(a, b) == State.WAR


## Fronteiras abertas: por enquanto, só entre aliados (o tratado vem na fase 4).
func open_borders(a: Player, b: Player) -> bool:
	return a == b or state(a, b) == State.ALLIED


## Turnos no estado atual.
func turns_in_state(a: Player, b: Player) -> int:
	return turn - int(_since.get(_pair(a, b), turn))


func truce_turns_left(a: Player, b: Player) -> int:
	return maxi(0, int(_truce_until.get(_pair(a, b), 0)) - turn)


## Se [param a] pode declarar guerra a [param b] agora: já se conhecem, ainda
## não estão em guerra e a trégua acabou.
func can_declare_war(a: Player, b: Player) -> bool:
	return a != b and have_met(a, b) and not at_war(a, b) and truce_turns_left(a, b) == 0


## Guerra: declaração formal ou, com [param surprise], guerra surpresa (ataque
## sem aviso: traição). Quem sofre perde confiança em quem declarou; na guerra
## surpresa, todos os que conhecem o traidor também desconfiam dele.
func declare_war(aggressor: Player, target: Player, players: Array, surprise := false) -> void:
	set_state(aggressor, target, State.WAR)
	_truce_until.erase(_pair(aggressor, target))
	add_trust(target, aggressor, SURPRISE_WAR_TRUST if surprise else DECLARE_WAR_TRUST)
	if surprise:
		for witness: Player in players:
			if witness != aggressor and witness != target and have_met(witness, aggressor):
				add_trust(witness, aggressor, SURPRISE_WAR_WITNESS_TRUST)


## Tratado de paz: volta à paz, com trégua de TRUCE_TURNS turnos.
func make_peace(a: Player, b: Player) -> void:
	set_state(a, b, State.PEACE)
	_truce_until[_pair(a, b)] = turn + TRUCE_TURNS
	add_trust(a, b, PEACE_SIGNED_TRUST)
	add_trust(b, a, PEACE_SIGNED_TRUST)


## Muda o estado direto, sem efeitos na confiança (começo da partida, testes).
func set_state(a: Player, b: Player, new_state: State) -> void:
	_state[_pair(a, b)] = new_state
	_since[_pair(a, b)] = turn


# --- Confiança -----------------------------------------------------------------

## O que [param from] pensa de [param to] (-100 a 100).
func trust(from: Player, to: Player) -> int:
	return int(_trust.get(_arrow(from, to), 0))


func add_trust(from: Player, to: Player, amount: int) -> void:
	if from == to:
		return
	_trust[_arrow(from, to)] = clampi(trust(from, to) + amount, TRUST_MIN, TRUST_MAX)


func trust_level(from: Player, to: Player) -> Trust:
	return level_of(trust(from, to))


static func level_of(value: int) -> Trust:
	if value <= FURIOUS_MAX:
		return Trust.FURIOUS
	if value <= INDIFFERENT_MAX:
		return Trust.INDIFFERENT
	if value <= FRIENDLY_MAX:
		return Trust.FRIENDLY
	return Trust.BROTHERHOOD


## Unidade de [param attacker] atacou uma de [param victim].
func on_attacked(victim: Player, attacker: Player) -> void:
	add_trust(victim, attacker, ATTACKED_TRUST)


## [param loser] perdeu uma cidade para [param taker] (ocupada ou destruída).
func on_city_lost(loser: Player, taker: Player) -> void:
	add_trust(loser, taker, CITY_LOST_TRUST)


## Começo da vez de [param player]: a confiança dele nos outros muda com o
## tempo (inimigo em comum, paz longa, volta ao zero).
func update_trust(player: Player, players: Array) -> void:
	for other: Player in known_players(player, players):
		var common_enemy := false
		for third: Player in players:
			if third != player and third != other and at_war(player, third) and at_war(other, third):
				common_enemy = true
		if common_enemy:
			add_trust(player, other, COMMON_ENEMY_TRUST)
		if at_war(player, other):
			continue
		var peaceful := turns_in_state(player, other)
		if peaceful > 0 and peaceful % LONG_PEACE_TURNS == 0:
			add_trust(player, other, 1)
		if turn % DRIFT_TURNS == 0 and not common_enemy:
			var value := trust(player, other)
			if value != 0:
				add_trust(player, other, -signi(value))


# --- Propostas -----------------------------------------------------------------

## Se [param from] já pode fazer outra proposta a [param to] (PROPOSAL_INTERVAL).
func can_propose(from: Player, to: Player) -> bool:
	return not _last_proposal.has(_arrow(from, to)) or turn - int(_last_proposal[_arrow(from, to)]) >= PROPOSAL_INTERVAL


func note_proposal(from: Player, to: Player) -> void:
	_last_proposal[_arrow(from, to)] = turn


# --- Save ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"met": _met.duplicate(), "state": _state.duplicate(), "since": _since.duplicate(),
			"truce_until": _truce_until.duplicate(), "trust": _trust.duplicate(),
			"last_proposal": _last_proposal.duplicate()}


static func from_dict(data: Dictionary) -> Diplomacy:
	var diplomacy := Diplomacy.new()
	for field in ["met", "state", "since", "truce_until", "trust", "last_proposal"]:
		var target: Dictionary = diplomacy.get("_" + field)
		for key: String in data.get(field, {}):
			target[key] = int(data[field][key])
	return diplomacy
