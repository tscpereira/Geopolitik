class_name AIController
extends RefCounted

## Inteligência do jogador máquina. Joga com as mesmas regras e ações do humano
## (Game.attack / Game.move_unit / City.order_build...), guiada pela
## personalidade do jogador (Player.personality, AIPersonality).
##
## Ordem do turno:
##   1. economia (AIEconomy): o que cada cidade constrói, onde os cidadãos
##      trabalham e compra de defesa com ouro;
##   2. Colonos vão até um bom lugar e fundam cidades; Trabalhadores vão até
##      uma floresta e fazem madeireiras;
##   3. guarnição: soldados se fortificam nas cidades (e ao redor);
##   4. ataques dos soldados de campo, sempre o de maior nota primeiro (a
##      guarnição não sai da cidade);
##   5. avanço contra o inimigo, só com exército de army_to_attack soldados,
##      mantendo a formação e sem parar na zona de ameaça do inimigo;
##   6. novos ataques de quem chegou perto e ainda tem movimento.
## Depois dos ataques, os soldados de campo invadem as cidades inimigas sem
## guarnição que alcançam (ocupam ou, com max_cities cidades, saqueiam e
## destroem: wants_to_raze) e pilham a fazenda ou madeireira inimiga em que
## estão; no avanço, vão em direção às unidades e cidades inimigas e preferem
## parar numa melhoria inimiga.

## Pausa antes de cada ação, para o jogador acompanhar.
const ACTION_DELAY := 0.4
## Sem pausas nem câmera (testes automáticos com a máquina jogando sozinha).
static var fast_mode := false
## Peso do dano recebido na nota de um ataque. Abaixo de 1 = mais agressiva.
const CAUTION := 0.8
## Bônus para ataques que devem destruir o alvo.
const KILL_BONUS := 60.0
## Penalidade para ataques em que a própria unidade pode morrer sem destruir o alvo.
const DEATH_PENALTY := 200.0
## Quantas casas uma unidade pode ficar à frente da aliada mais avançada.
const MAX_SPREAD := 2
## Turnos seguidos que a IA aceita esperar fora da zona de ameaça antes de
## avançar mesmo assim (evita as duas partes ficarem paradas para sempre).
const PATIENCE := 2
## Distância usada para casas de onde não se chega a nenhum inimigo.
const UNREACHABLE := 1 << 30

## Turnos seguidos em que alguma unidade segurou o avanço por causa da ameaça.
## Vai para o save (Game.capture_state).
var turns_waiting := 0
var _economy: AIEconomy


func play_turn(game: Game, player: Player) -> void:
	if _economy == null:
		_economy = AIEconomy.new(game, player)
	var focus := func(unit: Unit) -> void: await _focus(game, unit)
	_economy.manage_cities()
	await _economy.move_civilians(focus)
	if game.game_over:
		return
	_economy.manage_cities() # cidades fundadas agora já recebem ordens
	await _economy.garrison_cities(focus)
	if game.game_over:
		return
	await _attack_phase(game, player)
	if game.game_over:
		return
	await _invade_phase(game, player)
	if game.game_over:
		return
	await _pillage_phase(game, player)
	if _army_ready(player):
		await _advance_phase(game, player)
		if game.game_over:
			return
		await _attack_phase(game, player)
		if game.game_over:
			return
		await _pillage_phase(game, player)


## Escolhe a próxima pesquisa: a tecnologia disponível mais barata (as
## personalidades científica e cultural vão escolher de outro jeito).
static func choose_research(player: Player) -> void:
	var options := Technology.available(player.researched)
	if options.is_empty():
		return
	options.sort_custom(func(a: int, b: int) -> bool: return Technology.cost(a) < Technology.cost(b))
	player.research = options[0]


## Ao invadir uma cidade: ocupa, a não ser que já tenha as cidades que quer
## (personality.max_cities); aí saqueia e destrói.
static func wants_to_raze(player: Player, _city: City) -> bool:
	return player.cities.size() >= player.personality.max_cities


## Soldados de campo que alcançam neste turno uma cidade inimiga sem guarnição
## entram nela (Game.move_unit chama a invasão).
func _invade_phase(game: Game, player: Player) -> void:
	for unit in player.units.duplicate():
		if game.game_over:
			return
		if not is_instance_valid(unit) or unit.moves_left <= 0 or not _is_field_soldier(unit):
			continue
		var occupants := game.occupants()
		var reachable := Movement.find_reachable(game.game_map, unit, occupants)
		for cell in Movement.destinations(reachable, occupants):
			if Movement.is_enemy_city(game.game_map, unit, cell):
				await _focus(game, unit)
				await game.move_unit(unit, cell)
				break


## Soldados de campo em cima de uma melhoria inimiga pilham (a guarnição não sai
## da cidade).
func _pillage_phase(game: Game, player: Player) -> void:
	for unit in player.units.duplicate():
		if game.game_over:
			return
		if is_instance_valid(unit) and _is_field_soldier(unit) and game.pillage_error(unit).is_empty():
			await _focus(game, unit)
			game.hud.show_message(game.pillage(unit), Color(1, 0.75, 0.45))


## Soldados de campo (fora da guarnição) suficientes para partir para o ataque.
func _army_ready(player: Player) -> bool:
	var army := player.personality.army_to_attack
	return army > 0 and player.units.filter(_is_field_soldier).size() >= army


func _is_field_soldier(unit: Unit) -> bool:
	return unit.attack > 0 and not _economy.is_garrison(unit)


func _attack_phase(game: Game, player: Player) -> void:
	while not game.game_over:
		var best := _best_attack(game, player)
		if best.is_empty():
			return
		await _focus(game, best["unit"])
		await game.attack(best["unit"], best["target"])


## Move as unidades na direção do inimigo, das mais atrasadas para as mais
## adiantadas, para que as da frente respeitem a formação.
func _advance_phase(game: Game, player: Player) -> void:
	var distance := _distance_to_enemies(game, player)
	var threatened := _threatened_cells(game, player) if turns_waiting < PATIENCE else {}
	var held_back := false
	# Só os soldados de campo avançam (nem civis nem a guarnição)
	var movers := player.units.filter(func(unit: Unit) -> bool: return _is_field_soldier(unit) and game.can_move(unit))
	movers.sort_custom(func(a: Unit, b: Unit) -> bool:
		return distance.get(a.cell, UNREACHABLE) > distance.get(b.cell, UNREACHABLE))
	for unit: Unit in movers:
		if game.game_over:
			return
		var advance := _best_advance(game, player, unit, distance, threatened)
		held_back = held_back or advance["held_back"]
		if advance["cell"] != unit.cell:
			await _focus(game, unit)
			await game.move_unit(unit, advance["cell"])
	turns_waiting = turns_waiting + 1 if held_back else 0


## Melhor ataque disponível com nota positiva:
## {"unit": Unit, "target": Vector2i, "score": float}, ou {} se não houver.
func _best_attack(game: Game, player: Player) -> Dictionary:
	var best := {}
	var occupants := game.occupants()
	for unit in player.units:
		if unit.moves_left <= 0 or not _is_field_soldier(unit):
			continue # a guarnição não sai da cidade para atacar
		var reachable := Movement.find_reachable(game.game_map, unit, occupants)
		for target: Vector2i in Movement.attack_targets(game.game_map, unit, reachable, occupants):
			var score := _attack_score(unit, occupants[target])
			if score > 0.0 and (best.is_empty() or score > best["score"]):
				best = {"unit": unit, "target": target, "score": score}
	return best


## Nota do ataque = dano causado − dano recebido × cautela, com bônus para quem
## deve destruir o alvo e penalidade para quem arrisca morrer.
func _attack_score(attacker: Unit, defender: Unit) -> float:
	var expected := Combat.expected_damage(attacker, defender)
	var dealt: float = expected["to_defender"]
	var taken: float = expected["to_attacker"]
	var score := dealt - taken * CAUTION
	if dealt >= defender.energy:
		# Se o defensor cai, o atacante sobrevive (regra do combate)
		score += KILL_BONUS
	elif taken * (1.0 + Combat.LUCK) >= attacker.energy:
		score -= DEATH_PENALTY
	return score


## Casa ao alcance que mais aproxima a unidade do inimigo, sem passar do limite
## da formação e sem entrar na zona de ameaça (se a unidade ainda está fora dela).
## Retorna {"cell": Vector2i, "held_back": bool}; "cell" é a própria casa se for
## melhor ficar parada, e "held_back" indica que a ameaça segurou o avanço.
func _best_advance(game: Game, player: Player, unit: Unit, distance: Dictionary,
		threatened: Dictionary) -> Dictionary:
	var occupants := game.occupants()
	var reachable := Movement.find_reachable(game.game_map, unit, occupants)
	var front_limit := _front_limit(player, unit, distance)
	var avoid_threat := not threatened.has(unit.cell)
	var best := unit.cell
	var best_distance: int = distance.get(unit.cell, UNREACHABLE)
	var held_back := false
	# Melhoria inimiga ao alcance (fora da zona de ameaça): para nela e pilha
	if not game.is_pillageable_by(player, unit.cell):
		for cell in Movement.destinations(reachable, occupants):
			if game.is_pillageable_by(player, cell) and not (avoid_threat and threatened.has(cell)):
				return {"cell": cell, "held_back": false}
	for cell in Movement.destinations(reachable, occupants):
		var cell_distance: int = distance.get(cell, UNREACHABLE)
		if cell_distance < front_limit or cell_distance >= best_distance:
			continue
		if avoid_threat and threatened.has(cell):
			held_back = true
			continue
		best = cell
		best_distance = cell_distance
	return {"cell": best, "held_back": held_back and best == unit.cell}


## Casas que algum inimigo consegue atacar no próximo turno dele: vizinhas de
## qualquer casa aonde ele chega guardando 1 movimento para o ataque.
func _threatened_cells(game: Game, player: Player) -> Dictionary:
	var threatened := {}
	var occupants := game.occupants()
	for other in game.players:
		if other == player:
			continue
		for enemy in other.units:
			if enemy.attack <= 0:
				continue # não ataca, não ameaça
			var reachable := Movement.find_reachable(game.game_map, enemy, occupants, enemy.movement - 1)
			for cell: Vector2i in reachable:
				if cell != enemy.cell and occupants.has(cell):
					continue # casa com aliado dele: atravessa, mas não para
				for direction in Movement.DIRECTIONS:
					threatened[cell + direction] = true
	return threatened


## Menor distância ao inimigo que a unidade pode ter sem ficar mais de
## MAX_SPREAD casas à frente da aliada mais avançada.
func _front_limit(player: Player, unit: Unit, distance: Dictionary) -> int:
	var closest_ally := UNREACHABLE
	for ally in player.units:
		if ally != unit:
			closest_ally = mini(closest_ally, distance.get(ally.cell, UNREACHABLE))
	if closest_ally == UNREACHABLE:
		return 0
	return closest_ally - MAX_SPREAD


## Distância (em casas de terra, 8 direções) de cada casa até o inimigo mais
## próximo, contornando a água: {casa: distância}.
func _distance_to_enemies(game: Game, player: Player) -> Dictionary:
	var distance := {}
	var queue: Array[Vector2i] = []
	for other in game.players:
		if other == player:
			continue
		for enemy in other.units:
			if not distance.has(enemy.cell):
				distance[enemy.cell] = 0
				queue.append(enemy.cell)
		for city in other.cities: # as cidades inimigas também são alvo (invasão)
			if not distance.has(city.cell):
				distance[city.cell] = 0
				queue.append(city.cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for direction in Movement.DIRECTIONS:
			var next := cell + direction
			if distance.has(next) or not game.game_map.is_in_bounds(next) \
					or not Terrain.is_walkable(game.game_map.get_terrain(next)):
				continue
			distance[next] = distance[cell] + 1
			queue.append(next)
	return distance


## Mostra ao jogador qual unidade vai agir: seleciona, leva a câmera até ela e espera.
func _focus(game: Game, unit: Unit) -> void:
	if fast_mode:
		return
	game.select_unit(unit)
	await game.camera.pan_to(unit.position)
	await game.get_tree().create_timer(ACTION_DELAY).timeout
