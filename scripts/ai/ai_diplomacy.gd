class_name AIDiplomacy
extends RefCounted

## Decisões diplomáticas da máquina (fase 1, 30/10/2026), no começo da vez dela
## (play), antes de mover as unidades:
##   GUERRA: declara (sempre formalmente; a guerra surpresa é só do humano) a
##     quem ela alcança por terra, conforme a confiança e a força militar
##     (strength): Furiosa, se for pelo menos tão forte; Indiferente, só com o
##     dobro da força e o exército pronto (personality.army_to_attack). Amigável
##     e Irmandade, nunca. Personalidade que não ataca (army_to_attack = 0),
##     nunca. Já em guerra com alguém, só declara outra se estiver Furiosa.
##   PAZ: aceita (ou propõe) depois de MIN_WAR_TURNS de guerra quando está
##     perdendo (força menor que LOSING_RATIO da do outro) ou cansada
##     (WEARY_WAR_TURNS de guerra). Furiosa, só perdendo feio (FURIOUS_LOSING_RATIO).
##     Quem não ataca aceita a paz assim que der. Para o humano, a proposta
##     chega como um aviso (no máximo uma a cada Diplomacy.PROPOSAL_INTERVAL).

const MIN_WAR_TURNS := 5
const WEARY_WAR_TURNS := 30
const LOSING_RATIO := 0.8
const FURIOUS_LOSING_RATIO := 0.5
## Força para declarar guerra (sua / do alvo).
const FURIOUS_WAR_RATIO := 1.0
const INDIFFERENT_WAR_RATIO := 2.0


## Força militar do jogador: ataque + defesa de cada unidade militar de terra,
## proporcional à energia que ela tem.
static func strength(player: Player) -> float:
	var total := 0.0
	for unit in player.units:
		if unit.attack > 0 and not unit.is_naval():
			total += (unit.attack + unit.type.defense) * float(unit.energy) / unit.max_energy
	return total


## Força de [param player] dividida pela de [param other] (outro sem exército: 1).
static func ratio(player: Player, other: Player) -> float:
	return strength(player) / maxf(1.0, strength(other))


## Se [param ai] aceita fazer a paz com [param other] agora.
static func accepts_peace(game: Game, ai: Player, other: Player) -> bool:
	var diplomacy := game.diplomacy
	if not diplomacy.at_war(ai, other) or diplomacy.turns_in_state(ai, other) < MIN_WAR_TURNS:
		return false
	if ai.personality.army_to_attack <= 0:
		return true
	var power := ratio(ai, other)
	if diplomacy.trust_level(ai, other) == Diplomacy.Trust.FURIOUS:
		return power < FURIOUS_LOSING_RATIO
	return power < LOSING_RATIO or diplomacy.turns_in_state(ai, other) >= WEARY_WAR_TURNS


## Se [param ai] quer declarar guerra a [param target] agora.
static func wants_war(game: Game, ai: Player, target: Player) -> bool:
	var diplomacy := game.diplomacy
	if ai.personality.army_to_attack <= 0 or target.eliminated or not diplomacy.can_declare_war(ai, target):
		return false
	if not reachable(game, ai, target):
		return false
	var level := diplomacy.trust_level(ai, target)
	var at_war_elsewhere := game.players.any(func(other: Player) -> bool: return diplomacy.at_war(ai, other))
	var power := ratio(ai, target)
	match level:
		Diplomacy.Trust.FURIOUS:
			return power >= FURIOUS_WAR_RATIO
		Diplomacy.Trust.INDIFFERENT:
			var army := ai.units.filter(func(unit: Unit) -> bool: return unit.attack > 0 and not unit.is_naval()).size()
			return not at_war_elsewhere and power >= INDIFFERENT_WAR_RATIO and army >= ai.personality.army_to_attack
	return false


## Se [param ai] alcança [param target] por terra: alguma cidade dela na mesma
## massa de terra que uma cidade ou unidade dele (sem barcos ainda).
static func reachable(game: Game, ai: Player, target: Player) -> bool:
	var map := game.game_map
	var lands := {}
	for city in ai.cities:
		lands[map.landmass(city.cell)] = true
	if lands.is_empty():
		for unit in ai.units:
			lands[map.landmass(unit.cell)] = true
	for city in target.cities:
		if lands.has(map.landmass(city.cell)):
			return true
	for unit in target.units:
		if lands.has(map.landmass(unit.cell)):
			return true
	return false


## Decisões do começo da vez de [param ai]: paz com quem convém, guerra contra
## quem convém (ver o topo).
static func play(game: Game, ai: Player) -> void:
	var diplomacy := game.diplomacy
	for other: Player in diplomacy.known_players(ai, game.players):
		if other.eliminated:
			continue
		if diplomacy.at_war(ai, other):
			if accepts_peace(game, ai, other) and diplomacy.can_propose(ai, other):
				diplomacy.note_proposal(ai, other)
				if other.is_ai:
					if accepts_peace(game, other, ai):
						game.sign_peace(ai, other)
				else:
					game.offer_peace_to_human(ai, other)
		elif wants_war(game, ai, other):
			game.declare_war(ai, other)
