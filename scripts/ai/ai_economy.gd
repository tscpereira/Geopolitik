class_name AIEconomy
extends RefCounted

## Economia do jogador máquina: o que cada cidade constrói, onde os cidadãos
## trabalham, e para onde vão os Colonos e os Trabalhadores. Usa as mesmas
## regras e ações do humano (City.build_error / order_build, Game.buy_build,
## Game.found_city, Game.work_lumber_mill...). Os números vêm da personalidade
## (AIPersonality).
##
## A cada turno:
##   1. em todas as cidades, primeiro: compra de defesa com ouro, se há
##      inimigo perto e a cidade está sem guarnição;
##   2. em cada cidade, pedidos (um de cada tipo por vez):
##        comida   fazenda nova se o alimento não chega a food_surplus (e
##                 todas as fazendas já têm trabalhador);
##        defesa   Guerreiro (e a Lança dele) para a guarnição da cidade;
##        madeira  madeireira na floresta da cidade ou, sem floresta, um
##                 Trabalhador para fazer madeireira remota;
##        expansão Colono (população >= settler_population);
##        prédios  Marcenaria e depois Quartel General (na capital e em
##                 cidades grandes), guardando a madeira para eles;
##        armas    Lanças até spears_per_city por cidade;
##        exército Guerreiros até army_to_attack fora das cidades;
##   3. cidadãos, do zero: fazendas até o alimento bastar (no máximo 2/3 da
##      cidade, se não há fome), os impostos reservados (tax_workers), 1 em
##      cada madeireira (se falta madeira), as obras em ordem de prioridade
##      (_job_priority: comida > defesa > madeira > expansão > prédios > armas
##      > exército; todos na mais importante, o resto na seguinte),
##      madeireiras cheias e, por fim, a Marcenaria parada (impostos).

var _game: Game
var _player: Player
var _p: AIPersonality


func _init(game: Game, player: Player) -> void:
	_game = game
	_player = player
	_p = player.personality


# --- Cidades ---------------------------------------------------------------

func manage_cities() -> void:
	# Defesa primeiro, em todas as cidades: o plano de outra cidade poderia
	# gastar a Lança que a compra precisa
	for city in _player.cities:
		_buy_defense(city)
	for city in _player.cities:
		_plan(city)
		_distribute_workers(city)


## Pedidos da cidade, em ordem de prioridade (ver o topo do arquivo).
func _plan(city: City) -> void:
	# Comida (fazenda nova só quando todas as que existem já têm trabalhador;
	# senão ela fica pedindo fazendas que ninguém vai trabalhar)
	if city.food_per_turn() < _p.food_surplus and not _has_queued(city, City.Build.FARM) \
			and city.farm_workers() >= city.farms.size():
		var cells := _game.buildable_cells(city, City.Build.FARM)
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return city.farm_food(a) > city.farm_food(b))
		if not cells.is_empty():
			city.order_build(City.Build.FARM, cells[0])

	# Defesa: Guerreiro para a guarnição (e a Lança dele, se faltar)
	if _garrison_needed(city) > 0:
		if not city.weapons_error(City.Build.WARRIOR).is_empty() and _player.weapons_in_production(Arsenal.Weapon.SPEAR) == 0:
			_try_order(city, City.Build.SPEAR)
		_try_order(city, City.Build.WARRIOR)

	# Madeira
	if _player.wood_per_turn() < _p.wood_per_turn_goal and not _has_queued(city, City.Build.LUMBER_MILL):
		var forests := _game.buildable_cells(city, City.Build.LUMBER_MILL)
		if not forests.is_empty():
			city.order_build(City.Build.LUMBER_MILL, forests[0])
		elif _count_units(_is_worker) + _count_queued(City.Build.WORKER) < _p.workers_per_city * _player.cities.size() \
				and city.population >= 2:
			_try_order(city, City.Build.WORKER)

	# Expansão
	if city.population >= _p.settler_population \
			and _player.cities.size() + _count_units(_is_settler) + _count_queued(City.Build.SETTLER) < _p.max_cities:
		_try_order(city, City.Build.SETTLER)

	# Prédios (guardam a madeira para eles)
	var reserve := 0
	if city == _player.cities[0] or city.population >= 4:
		for building in [City.Build.CARPENTRY, City.Build.HEADQUARTERS]:
			if city.has_building(building) or _has_queued(city, building):
				continue
			if city.build_error(building).is_empty():
				city.order_build(building)
			else:
				reserve = City.BUILDS[building].get("wood", 0)
			break

	# Armas
	var spears: int = _player.arsenal[Arsenal.Weapon.SPEAR] + _player.weapons_in_production(Arsenal.Weapon.SPEAR)
	if city.has_building(City.Build.CARPENTRY) and spears < _p.spears_per_city * _player.cities.size() \
			and _player.wood - City.BUILDS[City.Build.SPEAR]["wood"] >= reserve:
		_try_order(city, City.Build.SPEAR)

	# Exército (fora das cidades)
	if _p.army_to_attack > 0 and city.population >= 3 \
			and _count_units(_is_field_soldier) + _count_queued(City.Build.WARRIOR) < _p.army_to_attack:
		_try_order(city, City.Build.WARRIOR)


## Pede a obra se as regras deixarem e se ainda não houver uma igual na fila.
func _try_order(city: City, build: int) -> void:
	if not _has_queued(city, build) and city.build_error(build).is_empty():
		city.order_build(build)


## Redistribui todos os cidadãos (ver o topo do arquivo).
func _distribute_workers(city: City) -> void:
	city.clear_workers()
	# Fazendas: as que rendem mais primeiro, até o alimento bastar. Cada
	# fazendeiro come quase tudo o que planta, então, sem fome, no máximo 2/3
	# da cidade vai para o campo (o resto produz)
	var farm_cells: Array = city.farms.keys()
	farm_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return city.farm_food(a) > city.farm_food(b))
	for farm_cell: Vector2i in farm_cells:
		var fed := city.food_per_turn() >= _p.food_surplus
		var enough_farmers := city.food_per_turn() > 0 and city.farm_workers() * 3 >= city.population * 2
		if city.free_citizens() <= 0 or fed or enough_farmers:
			break
		city.set_farm_worked(farm_cell, true)
	# Impostos: a personalidade pode reservar cidadãos na Marcenaria parada (só
	# em cidade de 4+; numa cidade pequena eles fariam falta para crescer)
	if _p.tax_workers > 0 and city.population >= 4 and city.has_building(City.Build.CARPENTRY) \
			and city.active_unit(City.Build.CARPENTRY) == null:
		city.set_building_workers(City.Build.CARPENTRY, mini(_p.tax_workers, city.free_citizens()))
	# Madeireiras: 1 em cada, se falta madeira
	var wood_short := _player.wood_per_turn() < _p.wood_per_turn_goal
	if wood_short:
		for mill_cell: Vector2i in city.lumber_mills:
			city.set_mill_workers(mill_cell, 1)
	# Obras e prédios com fila: foco na mais importante (todos nela, sem passar
	# do que falta), o resto vai para a seguinte; com poucos cidadãos,
	# espalhar deixaria tudo parado
	var jobs: Array[City.Construction] = []
	for construction in city.constructions:
		var is_front := not construction.is_produced() or city.active_unit(construction.producer()) == construction
		if is_front and not construction.is_done():
			jobs.append(construction)
	jobs.sort_custom(func(a: City.Construction, b: City.Construction) -> bool:
		return _job_priority(city, a) < _job_priority(city, b))
	for job in jobs:
		if city.free_citizens() <= 0:
			break
		var needed := job.cost() - job.progress
		city.set_construction_workers(job, city.workers_on(job) + mini(needed, city.free_citizens()))
	# O que sobrar: madeireiras cheias, depois a Marcenaria parada (impostos)
	for mill_cell: Vector2i in city.lumber_mills:
		city.set_mill_workers(mill_cell, LumberMill.MAX_WORKERS)
	if _p.collect_taxes and city.has_building(City.Build.CARPENTRY) and city.active_unit(City.Build.CARPENTRY) == null:
		city.set_building_workers(City.Build.CARPENTRY,
				city.building_workers.get(City.Build.CARPENTRY, 0) + city.free_citizens())
	# Ainda sobrando: as fazendas que faltam (comida a mais nunca faz mal)
	for farm_cell: Vector2i in farm_cells:
		if city.free_citizens() > 0 and city.farms[farm_cell] == 0:
			city.set_farm_worked(farm_cell, true)


## Ordem em que as obras recebem cidadãos (menor primeiro): comida abaixo da meta,
## defesa se falta guarnição, madeira se falta, expansão, prédios, armas e
## exército.
func _job_priority(city: City, job: City.Construction) -> int:
	var defense_short := _garrison_needed(city) + _queued_in(city, City.Build.WARRIOR) > 0
	var wood_short := _player.wood_per_turn() < _p.wood_per_turn_goal
	match job.build:
		City.Build.FARM:
			return 0 if city.food_per_turn() < _p.food_surplus else 5
		City.Build.SPEAR, City.Build.WARRIOR:
			return 1 if defense_short else 6
		City.Build.LUMBER_MILL, City.Build.WORKER:
			return 2 if wood_short else 7
		City.Build.CARPENTRY, City.Build.HEADQUARTERS:
			return 4
		City.Build.SETTLER:
			return 3
	return 8


func _queued_in(city: City, build: int) -> int:
	return city.constructions.filter(func(c: City.Construction) -> bool: return c.build == build).size()


## Inimigo perto e cidade sem guarnição: compra um Guerreiro (e a Lança, se faltar).
func _buy_defense(city: City) -> void:
	if not _p.buy_defense or _garrison_count(city) > 0 or not _enemy_near(city.cell, _p.threat_radius):
		return
	if _player.arsenal[Arsenal.Weapon.SPEAR] == 0 and _game.buy_error(city, City.Build.SPEAR).is_empty():
		_game.buy_build(city, City.Build.SPEAR)
	if _game.buy_error(city, City.Build.WARRIOR).is_empty():
		_game.buy_build(city, City.Build.WARRIOR)
		print("%s comprou um Guerreiro para defender %s" % [_player.display_name, city.city_name])


# --- Colonos e Trabalhadores -----------------------------------------------

## Colono: funda onde está, se o lugar for válido; senão anda até o melhor
## lugar por perto e funda lá.
## Trabalhador: anda até uma floresta livre (ou madeireira sua com vaga) e
## trabalha nela. [param focus] mostra a unidade ao jogador antes de fundar a
## cidade ou entrar na madeireira.
func move_civilians(focus: Callable) -> void:
	for unit in _player.units.duplicate():
		if _game.game_over or not is_instance_valid(unit) or unit.working_mill or unit.moves_left <= 0:
			continue
		if _is_settler(unit):
			await _move_settler(unit, focus)
		elif _is_worker(unit):
			await _move_worker(unit, focus)


## Colono parado num lugar válido (chegou ao destino ou já começou nele) funda
## ali mesmo; senão, escolhe o melhor lugar por perto e anda até lá. Sem isso,
## ele procuraria de novo a cada turno e poderia nunca parar de andar.
func _move_settler(settler: Unit, focus: Callable) -> void:
	if not settler.has_goto() and _game.city_site_error(settler).is_empty():
		await focus.call(settler)
		_game.found_city(settler)
		return
	if not settler.has_goto():
		var site := _best_city_site(settler)
		if site == Unit.NO_TARGET or site == settler.cell:
			return
		settler.goto_target = site
	await _game.advance_goto(settler)


func _move_worker(worker: Unit, focus: Callable) -> void:
	if _game.lumber_mill_error(worker).is_empty():
		await focus.call(worker)
		_game.work_lumber_mill(worker)
		return
	if not worker.has_goto():
		var target := _best_forest(worker)
		if target == Unit.NO_TARGET:
			return
		worker.goto_target = target
	await _game.advance_goto(worker)


## Melhor casa para uma cidade nova ao alcance do Colono (ou NO_TARGET).
## Nota = terreno da área (pradaria 3, cerrado e floresta 2, água 1) menos
## casas já usadas por outras cidades e menos a distância a andar.
func _best_city_site(settler: Unit) -> Vector2i:
	var map := _game.game_map
	var occupants := _game.occupants()
	occupants.erase(settler.cell)
	var reachable := Movement.find_reachable(map, settler, occupants, _p.settler_search_radius)
	var best := Unit.NO_TARGET
	var best_score := -INF
	for cell: Vector2i in reachable:
		if occupants.has(cell) or _game.claiming_city(cell) or _game.lumber_mill_at(cell):
			continue
		var too_close := false
		for city in _game.cities():
			if maxi(absi(city.cell.x - cell.x), absi(city.cell.y - cell.y)) <= City.MIN_DISTANCE:
				too_close = true
		if too_close:
			continue
		var score := 0.0
		for offset in City.area_offsets():
			var area_cell: Vector2i = cell + offset
			if not map.is_in_bounds(area_cell):
				continue
			match map.get_terrain(area_cell):
				Terrain.Type.GRASSLAND:
					score += 3.0
				Terrain.Type.CERRADO, Terrain.Type.FOREST:
					score += 2.0
				Terrain.Type.WATER:
					score += 1.0
			if _game.claiming_city(area_cell) or _game.get_city_at(area_cell):
				score -= 3.0
		score -= Movement.build_path(reachable, cell).size() * 1.5
		if score > best_score:
			best_score = score
			best = cell
	return best


## Floresta mais perto (pelo caminho) onde o Trabalhador pode fazer ou entrar
## numa madeireira, ou NO_TARGET.
func _best_forest(worker: Unit) -> Vector2i:
	var map := _game.game_map
	var occupants := _game.occupants()
	var reachable := Movement.find_reachable(map, worker, occupants, 30)
	var best := Unit.NO_TARGET
	var best_distance := INF
	for cell: Vector2i in reachable:
		if occupants.has(cell) or map.get_terrain(cell) != Terrain.Type.FOREST or _game.claiming_city(cell):
			continue
		var mill := _game.lumber_mill_at(cell)
		if mill and (mill.owner_player != _player or not mill.has_room()):
			continue
		var distance := Movement.build_path(reachable, cell).size()
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


# --- Contagens ---------------------------------------------------------------

func _has_queued(city: City, build: int) -> bool:
	return city.construction_of(build) != null


func _count_queued(build: int) -> int:
	var total := 0
	for city in _player.cities:
		for construction in city.constructions:
			if construction.build == build:
				total += 1
	return total


func _count_units(filter: Callable) -> int:
	return _player.units.filter(filter).size()


func _is_settler(unit: Unit) -> bool:
	return unit.type.can_found_city


func _is_worker(unit: Unit) -> bool:
	return unit.type.can_build_lumber_mill


## Unidade militar que não faz parte da guarnição de uma cidade.
func _is_field_soldier(unit: Unit) -> bool:
	return unit.attack > 0 and not is_garrison(unit)


## Guarnição: unidade militar fortificada na cidade ou numa casa vizinha.
func is_garrison(unit: Unit) -> bool:
	if unit.attack <= 0 or not unit.fortified:
		return false
	for city in _player.cities:
		if maxi(absi(city.cell.x - unit.cell.x), absi(city.cell.y - unit.cell.y)) <= 1:
			return true
	return false


func _garrison_count(city: City) -> int:
	var total := 0
	for unit in _player.units:
		if is_garrison(unit) and maxi(absi(city.cell.x - unit.cell.x), absi(city.cell.y - unit.cell.y)) <= 1:
			total += 1
	return total


## Quantos Guerreiros faltam na guarnição da cidade (contando os que já estão
## na fila e os soldados livres que podem ir para lá).
func _garrison_needed(city: City) -> int:
	var queued := 0
	for construction in city.constructions:
		if construction.build == City.Build.WARRIOR:
			queued += 1
	return _p.garrison_per_city - _garrison_count(city) - queued - _count_units(_is_field_soldier)


## Se há unidade militar inimiga a até [param radius] casas.
func _enemy_near(cell: Vector2i, radius: int) -> bool:
	for other in _game.players:
		if other == _player:
			continue
		for unit in other.units:
			if unit.attack > 0 and maxi(absi(unit.cell.x - cell.x), absi(unit.cell.y - cell.y)) <= radius:
				return true
	return false


# --- Guarnição -----------------------------------------------------------------

## Cada cidade fica com garrison_per_city soldados fortificados: o primeiro
## dentro da cidade (escondido), os outros nas casas vizinhas (de preferência
## floresta, que dá defesa). Usa os soldados livres mais próximos.
func garrison_cities(focus: Callable) -> void:
	for city in _player.cities:
		while _garrison_count(city) < _p.garrison_per_city and not _game.game_over:
			var post := _garrison_post(city)
			var soldier := _nearest_soldier(post) if post != Unit.NO_TARGET else null
			if soldier == null:
				break
			if soldier.cell != post:
				if soldier.moves_left <= 0:
					break
				soldier.goto_target = post
				await focus.call(soldier)
				await _game.advance_goto(soldier)
				if soldier.cell != post:
					break # ainda a caminho: continua no próximo turno
			soldier.goto_target = Unit.NO_TARGET
			soldier.fortify()
			soldier.hidden_in_city = _game.get_city_at(soldier.cell) != null


## Casa livre para mais um soldado da guarnição: a cidade, depois uma vizinha
## (floresta primeiro). NO_TARGET se não houver.
func _garrison_post(city: City) -> Vector2i:
	var occupants := _game.occupants()
	var occupant: Unit = occupants.get(city.cell)
	if occupant == null or (occupant.owner_player == _player and not is_garrison(occupant)):
		return city.cell
	var best := Unit.NO_TARGET
	for direction in Movement.DIRECTIONS:
		var cell: Vector2i = city.cell + direction
		if not _game.game_map.is_in_bounds(cell) or not Terrain.is_walkable(_game.game_map.get_terrain(cell)):
			continue
		var there: Unit = occupants.get(cell)
		if there and (there.owner_player != _player or is_garrison(there)):
			continue
		if best == Unit.NO_TARGET or _game.game_map.get_terrain(cell) == Terrain.Type.FOREST:
			best = cell
	return best


func _nearest_soldier(target: Vector2i) -> Unit:
	var best: Unit = null
	var best_distance := 1 << 30
	for unit in _player.units:
		if not _is_field_soldier(unit):
			continue
		var distance := maxi(absi(unit.cell.x - target.x), absi(unit.cell.y - target.y))
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best
