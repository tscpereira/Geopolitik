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
##   2. em cada cidade (menos as vazias), pedidos (um de cada tipo por vez):
##        Trabalhador para as tarefas dele (_worker_jobs): fazendas que faltam,
##                 madeireira (se falta madeira), ruínas (melhorias pilhadas)
##                 e cidades vazias para repovoar;
##        defesa   Guerreiro (e a Lança dele) para a guarnição da cidade;
##        expansão Colono (população >= settler_population);
##        bem-estar Templo (com Misticismo) quando a população chega aos
##                 contentes de base (City.base_content);
##        prédios  Marcenaria e depois Quartel General (na capital e em
##                 cidades grandes), guardando a madeira para eles;
##        armas    Lanças até spears_per_city por cidade;
##        exército Guerreiros até army_to_attack fora das cidades;
##   3. cidadãos, do zero: fazendas e depois casas sem melhoria até o
##      alimento bastar (no máximo 2/3 da cidade no campo), festividades até
##      sair da desordem civil, os
##      impostos reservados (tax_workers), 1 em
##      cada madeireira (se falta madeira), as obras em ordem de prioridade
##      (_job_priority: comida > defesa > madeira > expansão > prédios > armas
##      > exército; todos na mais importante, o resto na seguinte),
##      madeireiras cheias, a Marcenaria parada (impostos) e, por fim, as
##      fazendas e casas sem melhoria que sobrarem.
## Os Trabalhadores (move_civilians) andam até a tarefa e a fazem: fazenda ou
## madeireira da cidade no território (Game.build_improvement), madeireira
## remota fora dele, reconstrução e migração para a cidade vazia.

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
	if city.population <= 0:
		return # cidade vazia: espera um Trabalhador migrar para ela

	# Trabalhadores: fazem as fazendas e madeireiras, reconstroem as melhorias
	# pilhadas e repovoam as cidades vazias
	if city.population >= 2 and _count_units(_is_free_worker) + _count_queued(City.Build.WORKER) \
			< mini(_worker_jobs(), _p.workers_per_city * _player.cities.size() + 1):
		_try_order(city, City.Build.WORKER)

	# Defesa: Guerreiro para a guarnição (e a Lança dele, se faltar)
	if _garrison_needed(city) > 0:
		if not city.weapons_error(City.Build.WARRIOR).is_empty() and _player.weapons_in_production(Arsenal.Weapon.SPEAR) == 0:
			_try_order(city, City.Build.SPEAR)
		_try_order(city, City.Build.WARRIOR)

	# Expansão
	if city.population >= _p.settler_population \
			and _player.cities.size() + _count_units(_is_settler) + _count_queued(City.Build.SETTLER) < _p.max_cities:
		_try_order(city, City.Build.SETTLER)

	# Bem-estar: Templo quando a cidade já tem (ou está para ter) infelizes
	if city.population >= city.base_content():
		_try_order(city, City.Build.TEMPLE)

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
	# Casas sem melhoria (+1 de alimento) se ainda falta comida, até 2/3 da cidade no campo
	for tile_cell: Vector2i in _workable_tiles(city):
		if city.free_citizens() <= 0 or city.food_per_turn() >= _p.food_surplus \
				or (city.farm_workers() + city.worked_tiles.size()) * 3 >= city.population * 2:
			break
		city.set_tile_worked(tile_cell, true)
	# Bem-estar: festividades até sair da desordem civil (senão nada avança)
	while city.is_in_disorder() and city.free_citizens() > 0:
		city.set_festival_workers(city.festival_workers + 1)
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
	# Ainda sobrando: as fazendas que faltam e as casas sem melhoria (comida a
	# mais nunca faz mal)
	for farm_cell: Vector2i in farm_cells:
		if city.free_citizens() > 0 and city.farms[farm_cell] == 0:
			city.set_farm_worked(farm_cell, true)
	for tile_cell: Vector2i in _workable_tiles(city):
		if city.free_citizens() <= 0:
			break
		city.set_tile_worked(tile_cell, true)


## Casas do território que um cidadão pode trabalhar sem melhoria (sem a
## madeireira remota de alguém).
func _workable_tiles(city: City) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tile_cell in city.territory:
		if city.can_work_tile(tile_cell) and not city.worked_tiles.has(tile_cell) and _game.lumber_mill_at(tile_cell) == null:
			cells.append(tile_cell)
	return cells


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
		City.Build.WORKER:
			return 0 if _farm_jobs() > 0 else 1 if _rebuild_jobs() > 0 else 2 if wood_short else 7
		City.Build.LUMBER_MILL:
			return 2 if wood_short else 7
		City.Build.CARPENTRY, City.Build.HEADQUARTERS:
			return 4
		City.Build.TEMPLE:
			return 1 if city.mood()["unhappy"] > 0 else 4
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


## Trabalhador, nesta ordem: reconstrói a ruína em que está; migra para a
## cidade vazia vizinha; senão vai até a tarefa dele (_worker_job: cidade vazia
## ou ruína, fazenda que falta, madeireira) e a faz quando chega.
func _move_worker(worker: Unit, focus: Callable) -> void:
	if worker.rebuilding:
		return
	if _game.rebuild_error(worker).is_empty():
		await focus.call(worker)
		_game.rebuild(worker)
		return
	if _game.join_city_error(worker).is_empty() and _game.join_target(worker).population <= 0:
		await focus.call(worker)
		_game.join_city(worker)
		return
	var job := _worker_job(worker)
	if job.is_empty():
		return
	if worker.cell != job["cell"]:
		worker.goto_target = job["cell"]
		await _game.advance_goto(worker)
		if not is_instance_valid(worker) or worker.cell != job["cell"] or worker.moves_left <= 0:
			return # ainda a caminho
	worker.goto_target = Unit.NO_TARGET
	match job["build"]:
		City.Build.FARM:
			if _game.improvement_error(worker, City.Build.FARM).is_empty():
				await focus.call(worker)
				_game.build_improvement(worker, City.Build.FARM)
		City.Build.LUMBER_MILL:
			if _game.lumber_mill_error(worker).is_empty():
				await focus.call(worker)
				_game.build_lumber_mill(worker)
		_:
			# Cidade vazia ou ruína: migra ou reconstrói no próximo turno
			if _game.rebuild_error(worker).is_empty():
				await focus.call(worker)
				_game.rebuild(worker)


## Tarefa do Trabalhador: {"cell": casa, "build": Build.FARM, LUMBER_MILL ou -1
## (cidade vazia ou ruína)}, ou {} se não houver nada. Primeiro repovoar e
## reconstruir, depois a fazenda que falta mais perto, depois uma madeireira se
## falta madeira (da cidade, no território; senão remota). Casas que outro
## Trabalhador já ocupa ou tem como destino ficam de fora.
func _worker_job(worker: Unit) -> Dictionary:
	var rebuild := _rebuild_target(worker)
	if rebuild != Unit.NO_TARGET:
		return {"cell": rebuild, "build": -1}
	var taken := _taken_cells(worker)
	var farm := _nearest(worker.cell, _farm_cells().filter(func(c: Vector2i) -> bool: return not taken.has(c)))
	if farm != Unit.NO_TARGET:
		return {"cell": farm, "build": City.Build.FARM}
	if _player.wood_per_turn() >= _p.wood_per_turn_goal:
		return {}
	var forest := _nearest(worker.cell, _city_forest_cells().filter(func(c: Vector2i) -> bool: return not taken.has(c)))
	if forest == Unit.NO_TARGET:
		forest = _best_forest(worker)
	return {"cell": forest, "build": City.Build.LUMBER_MILL} if forest != Unit.NO_TARGET else {}


## Casas ocupadas por outras unidades ou que outro Trabalhador do jogador tem
## como destino.
func _taken_cells(worker: Unit) -> Dictionary:
	var taken := _game.occupants().duplicate()
	taken.erase(worker.cell)
	for unit in _player.units:
		if unit != worker and _is_worker(unit) and unit.has_goto():
			taken[unit.goto_target] = unit
	return taken


## A casa de [param cells] mais perto (em linha reta) de [param from], ou NO_TARGET.
func _nearest(from: Vector2i, cells: Array) -> Vector2i:
	var best := Unit.NO_TARGET
	var best_distance := 1 << 30
	for cell: Vector2i in cells:
		var distance := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## Se a cidade precisa de mais uma fazenda: uma por habitante (o cidadão na
## fazenda come o que planta; numa casa sem melhoria, falta 1), sem outra
## fazenda já em obra nela.
func _needs_farm(city: City) -> bool:
	if city.population <= 0 or city.sites.values().any(func(site: Dictionary) -> bool: return site["build"] == City.Build.FARM):
		return false
	return city.farms.size() < city.population


## Casas onde falta uma fazenda: as obras de fazenda paradas (sem ninguém) e,
## nas cidades que precisam de fazenda, as casas livres de pradaria e cerrado.
func _farm_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for city in _player.cities:
		for site_cell: Vector2i in city.sites:
			if city.sites[site_cell]["build"] == City.Build.FARM and not _is_worked_site(site_cell):
				cells.append(site_cell)
		if _needs_farm(city):
			cells.append_array(_game.buildable_cells(city, City.Build.FARM))
	return cells


## Florestas das cidades onde dá para fazer madeireira (e as obras de
## madeireira paradas).
func _city_forest_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for city in _player.cities:
		for site_cell: Vector2i in city.sites:
			if city.sites[site_cell]["build"] == City.Build.LUMBER_MILL and not _is_worked_site(site_cell):
				cells.append(site_cell)
		cells.append_array(_game.buildable_cells(city, City.Build.LUMBER_MILL))
	return cells


## Se um Trabalhador está fazendo a obra da casa.
func _is_worked_site(cell: Vector2i) -> bool:
	var unit := _game.get_unit_at(cell)
	return unit != null and unit.rebuilding


## Cidades que precisam de uma fazenda e têm onde fazê-la.
func _farm_jobs() -> int:
	return _player.cities.filter(func(city: City) -> bool:
		return _needs_farm(city) and not _game.buildable_cells(city, City.Build.FARM).is_empty()).size()


## Tarefas para Trabalhadores: reconstruir/repovoar, fazendas que faltam e uma
## madeireira se falta madeira.
func _worker_jobs() -> int:
	return _rebuild_jobs() + _farm_jobs() + (1 if _player.wood_per_turn() < _p.wood_per_turn_goal else 0)


## Casa mais perto (em linha reta) aonde o Trabalhador deve ir para reconstruir
## ou repovoar: uma cidade vazia primeiro, depois uma ruína (fazenda ou
## madeireira pilhada). NO_TARGET se não houver nada.
func _rebuild_target(worker: Unit) -> Vector2i:
	var best := Unit.NO_TARGET
	var best_distance := 1 << 30
	for city in _player.cities:
		if city.population <= 0:
			var distance := maxi(absi(city.cell.x - worker.cell.x), absi(city.cell.y - worker.cell.y))
			if distance < best_distance:
				best_distance = distance
				best = city.cell
	if best != Unit.NO_TARGET:
		return best
	for cell in _ruin_cells():
		var there := _game.get_unit_at(cell)
		if there and there != worker:
			continue # ocupada (ex.: o inimigo que pilhou ainda está lá)
		var distance := maxi(absi(cell.x - worker.cell.x), absi(cell.y - worker.cell.y))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## Ruínas do jogador: melhorias pilhadas das cidades e madeireiras remotas
## destruídas com vaga.
func _ruin_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for city in _player.cities:
		for ruin_cell: Vector2i in city.ruins:
			cells.append(ruin_cell)
	for mill in _player.lumber_mills:
		if mill.pillaged and mill.has_room():
			cells.append(mill.cell)
	return cells


## Trabalhadores que o jogador precisa para reconstruir: um por ruína e um por
## cidade vazia (no máximo 2 de uma vez).
func _rebuild_jobs() -> int:
	var empty := _player.cities.filter(func(city: City) -> bool: return city.population <= 0).size()
	return mini(_ruin_cells().size() + empty, 2)


## Melhor casa para uma cidade nova ao alcance do Colono (ou NO_TARGET), fora
## de qualquer território. Nota = terreno do território que ela teria (21 casas
## para a capital, 9 para as outras; pradaria 3, cerrado e floresta 2, água 1),
## sem as casas que já são de outra cidade, menos a distância a andar.
func _best_city_site(settler: Unit) -> Vector2i:
	var map := _game.game_map
	var occupants := _game.occupants()
	occupants.erase(settler.cell)
	var reachable := Movement.find_reachable(map, settler, occupants, _p.settler_search_radius)
	var best := Unit.NO_TARGET
	var best_score := -INF
	for cell: Vector2i in reachable:
		if occupants.has(cell) or _game.claiming_city(cell) or _game.lumber_mill_at(cell) or _game.territory_owner(cell):
			continue
		var too_close := false
		for city in _game.cities():
			if maxi(absi(city.cell.x - cell.x), absi(city.cell.y - cell.y)) <= City.MIN_DISTANCE:
				too_close = true
		if too_close:
			continue
		var score := 0.0
		for offset in City.territory_offsets(_player.cities.is_empty()):
			var area_cell: Vector2i = cell + offset
			if not map.is_in_bounds(area_cell) or _game.territory_owner(area_cell):
				continue # casa de outra cidade: não entra no território novo
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
		var owner_city := _game.territory_owner(cell)
		if owner_city and owner_city.owner_player != _player:
			continue # território de outro jogador
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


## Trabalhador no mapa (fora das madeireiras), que pode ir reconstruir.
func _is_free_worker(unit: Unit) -> bool:
	return unit.type.can_rebuild and unit.working_mill == null


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
