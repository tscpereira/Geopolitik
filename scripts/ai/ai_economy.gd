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
##        defesa   soldado (Lanceiro com Trabalho em Bronze, e a Lança dele;
##                 senão Guerreiro, que não leva Lança) para a guarnição;
##        expansão Colono (população >= settler_population);
##        bem-estar Templo (com Misticismo) quando a população chega aos
##                 contentes de base (City.base_content);
##        prédios  Marcenaria e depois Quartel General (na capital e em
##                 cidades grandes), guardando a madeira para eles;
##        muralha  Muralha (com Construção e o Quartel) na capital e nas
##                 cidades com inimigo por perto;
##        era antiga Escola, Mercado, Biblioteca, Forja e Arena (com as
##                 tecnologias), um de cada vez, na capital e em cidades de 4+;
##        armas    Lanças até spears_per_city por cidade (só com o Lanceiro);
##        exército soldados até army_to_attack fora das cidades, 1 em cada
##                 ranged_share de ataque à distância (Catapulta ou Arqueiro,
##                 com a máquina ou o Arco feitos antes na Marcenaria);
##   3. cidadãos, do zero (_distribute_workers): fazendas e casas sem
##      melhoria até a cidade não passar fome, festividades até sair da
##      desordem civil, 1 em cada madeireira (se falta madeira), a RESERVA das
##      obras (1/4 da cidade, pelo menos 1), mais comida até food_surplus (no
##      máximo 2/3 da cidade no campo), os impostos reservados (tax_workers),
##      o resto das obras em ordem de prioridade (_job_priority: comida >
##      defesa > madeira > expansão > prédios > armas > exército; todos na
##      mais importante, o resto na seguinte), madeireiras cheias, a
##      Marcenaria parada (impostos) e as fazendas e casas que sobrarem.
## Os Trabalhadores (move_civilians) andam até a tarefa e a fazem: fazenda ou
## madeireira da cidade no território (Game.build_improvement), madeireira
## remota fora dele, reconstrução e migração para a cidade vazia. Se falta
## madeira (_wood_short: pouca entrando E estoque abaixo de WOOD_RESERVE) e há
## menos madeireiras que cidades, a madeireira vem antes das fazendas.

## Com pelo menos isto de madeira guardada, a madeira não falta (mesmo com pouca
## entrando por turno): a máquina não faz mais Trabalhadores e madeireiras só por
## ela (cada Trabalhador custa 1 de população).
const WOOD_RESERVE := 40
## Prédios da era antiga, na ordem em que a máquina os pede.
const ANCIENT_BUILDINGS: Array[int] = [City.Build.SCHOOL, City.Build.MARKET, City.Build.LIBRARY, City.Build.FORGE, City.Build.ARENA]
## Distância somada aos Arqueiros e Catapultas na escolha da guarnição
## (_nearest_soldier): maior que qualquer mapa, então só vão se não houver outro.
const RANGED_GARRISON_PENALTY := 10000
## Unidades que a máquina faz para o exército (ver _army_unit).
const ARMY_BUILDS: Array[int] = [City.Build.WARRIOR, City.Build.SPEARMAN, City.Build.ARCHER, City.Build.CATAPULT]

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

	# Defesa: soldado para a guarnição (e a Lança dele, se faltar)
	if _garrison_needed(city) > 0:
		if not city.weapons_error(_soldier()).is_empty() and _player.weapons_in_production(Arsenal.Weapon.SPEAR) == 0:
			_try_order(city, City.Build.SPEAR)
		_try_order(city, _soldier())

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

	# Muralha (exige Construção): na capital e nas cidades com inimigo por perto,
	# depois do Quartel General (a madeira dos prédios vem antes)
	if city.has_building(City.Build.HEADQUARTERS) \
			and (city == _player.cities[0] or _enemy_near(city.cell, _p.threat_radius)):
		_try_order(city, City.Build.WALLS)

	# Prédios da era antiga: um de cada vez, depois do Quartel General
	if city.has_building(City.Build.HEADQUARTERS) and (city == _player.cities[0] or city.population >= 4) \
			and not city.constructions.any(func(c: City.Construction) -> bool: return c.build in ANCIENT_BUILDINGS):
		for building: int in ANCIENT_BUILDINGS:
			if not city.has_building(building) and city.build_error(building).is_empty() \
					and _player.wood - City.BUILDS[building].get("wood", 0) >= reserve:
				city.order_build(building)
				break

	# Armas (só para o soldado que leva Lança: o Guerreiro não leva)
	var spears: int = _player.arsenal[Arsenal.Weapon.SPEAR] + _player.weapons_in_production(Arsenal.Weapon.SPEAR)
	if _soldier_needs_spear() and city.has_building(City.Build.CARPENTRY) and spears < _p.spears_per_city * _player.cities.size() \
			and _player.wood - City.BUILDS[City.Build.SPEAR]["wood"] >= reserve:
		_try_order(city, City.Build.SPEAR)

	# Exército (fora das cidades), com 1 em cada ranged_share atacando à distância
	var queued_army := 0
	for build: int in ARMY_BUILDS:
		queued_army += _count_queued(build)
	if _p.army_to_attack > 0 and city.population >= 3 \
			and _count_units(_is_field_soldier) + queued_army < _p.army_to_attack:
		var unit := _army_unit(city, reserve)
		var weapon_build := _missing_weapon_build(unit)
		if weapon_build < 0:
			_try_order(city, unit)
		elif _player.weapons_in_production(City.BUILDS[weapon_build]["weapon"]) == 0:
			# A arma primeiro (Arco, máquina da Catapulta); a unidade vem quando
			# ela estiver no arsenal
			_try_order(city, weapon_build)


## Unidade do exército que falta: uma de ataque à distância enquanto houver
## menos que army_to_attack / ranged_share (Catapulta, se der para fazer a
## máquina sem mexer na [param reserve] de madeira dos prédios; senão
## Arqueiro), ou o soldado de corpo a corpo (_soldier). Só escolhe a unidade à
## distância se a arma dela já existe (no arsenal ou em produção) ou se a
## [param city] tem a Marcenaria para fazê-la.
func _army_unit(city: City, reserve: int) -> int:
	if _p.ranged_share <= 0:
		return _soldier()
	var ranged := _count_units(func(unit: Unit) -> bool: return _is_field_soldier(unit) and unit.is_ranged()) \
			+ _count_queued(City.Build.ARCHER) + _count_queued(City.Build.CATAPULT)
	if ranged >= _p.army_to_attack / _p.ranged_share:
		return _soldier()
	if _player.researched.has(Technology.Tech.MATHEMATICS) and _can_equip(city, City.Build.CATAPULT, reserve):
		return City.Build.CATAPULT
	if _player.researched.has(Technology.Tech.RANGED_WARFARE) and _can_equip(city, City.Build.ARCHER, reserve):
		return City.Build.ARCHER
	return _soldier()


## Se a arma de [param build] já está no arsenal ou em produção, ou se a
## [param city] pode fazê-la agora (tem o prédio e a madeira sem mexer na
## [param reserve]).
func _can_equip(city: City, build: int, reserve: int) -> bool:
	var weapon_build := _missing_weapon_build(build)
	if weapon_build < 0:
		return true
	var info: Dictionary = City.BUILDS[weapon_build]
	return _player.weapons_in_production(info["weapon"]) > 0 \
			or (city.has_building(info["requires"]) and _player.wood - info.get("wood", 0) >= reserve)


## Obra que faz a primeira arma que falta no arsenal para [param build] (ex.:
## Arco para o Arqueiro), ou -1 se não falta nenhuma.
func _missing_weapon_build(build: int) -> int:
	var weapons: Dictionary = City.BUILDS[build].get("weapons", {})
	for weapon: Arsenal.Weapon in weapons:
		if _player.arsenal[weapon] < weapons[weapon]:
			for maker: int in City.BUILDS:
				if City.BUILDS[maker].get("weapon", -1) == weapon:
					return maker
	return -1


## Pede a obra se as regras deixarem e se ainda não houver uma igual na fila.
func _try_order(city: City, build: int) -> void:
	if not _has_queued(city, build) and city.build_error(build).is_empty():
		city.order_build(build)


## Redistribui todos os cidadãos (ver o topo do arquivo). A cidade primeiro
## não passa fome, sai da desordem e põe gente na madeira (se falta); depois
## reserva 1/4 dos cidadãos para as obras ANTES de buscar mais comida (sem essa
## reserva, a cidade inteira ia para as fazendas e as obras ficavam paradas).
func _distribute_workers(city: City) -> void:
	city.clear_workers()
	var farm_cells: Array = city.farms.keys()
	farm_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return city.farm_food(a) > city.farm_food(b))
	# Obras e prédios com fila, a mais importante primeiro
	var jobs: Array[City.Construction] = []
	for construction in city.constructions:
		var is_front := not construction.is_produced() or city.active_unit(construction.producer()) == construction
		if is_front and not construction.is_done():
			jobs.append(construction)
	jobs.sort_custom(func(a: City.Construction, b: City.Construction) -> bool:
		return _job_priority(city, a) < _job_priority(city, b))
	# 1. Comida mínima: a cidade não passa fome
	_feed(city, farm_cells, 0, false)
	# 2. Bem-estar: festividades até sair da desordem civil (senão nada avança)
	while city.is_in_disorder() and city.free_citizens() > 0:
		city.set_festival_workers(city.festival_workers + 1)
	# 3. Madeira: 1 em cada madeireira, se falta
	if _wood_short():
		for mill_cell: Vector2i in city.lumber_mills:
			city.set_mill_workers(mill_cell, 1)
	# 4. Reserva para as obras: 1/4 da cidade (pelo menos 1)
	if not jobs.is_empty():
		_staff_jobs(city, jobs, maxi(1, city.population / 4))
	# 5. Comida até a meta da personalidade, com no máximo 2/3 da cidade no campo
	_feed(city, farm_cells, _p.food_surplus, true)
	# 6. Impostos: a personalidade pode reservar cidadãos na Marcenaria parada (só
	# em cidade de 4+; numa cidade pequena eles fariam falta para crescer)
	if _p.tax_workers > 0 and city.population >= 4 and city.has_building(City.Build.CARPENTRY) \
			and city.active_unit(City.Build.CARPENTRY) == null:
		city.set_building_workers(City.Build.CARPENTRY, mini(_p.tax_workers, city.free_citizens()))
	# 7. O resto das obras
	_staff_jobs(city, jobs, city.free_citizens())
	# O que sobrar: madeireiras cheias, depois a Marcenaria parada (impostos)
	for mill_cell: Vector2i in city.lumber_mills:
		city.set_mill_workers(mill_cell, LumberMill.MAX_WORKERS)
	# Prédios parados com vagas (Mercado: ouro; Biblioteca: ciência; Forja), antes dos impostos da Marcenaria
	for building: int in [City.Build.MARKET, City.Build.LIBRARY, City.Build.FORGE]:
		if city.has_building(building) and city.active_unit(building) == null and city.free_citizens() > 0:
			city.set_building_workers(building, city.building_workers.get(building, 0) + city.free_citizens())
	if _p.collect_taxes and city.has_building(City.Build.CARPENTRY) and city.active_unit(City.Build.CARPENTRY) == null:
		city.set_building_workers(City.Build.CARPENTRY,
				city.building_workers.get(City.Build.CARPENTRY, 0) + city.free_citizens())
	# Minas (o ferro ainda não tem uso: só quem sobrou)
	for mine_cell: Vector2i in city.mines:
		city.set_mine_workers(mine_cell, City.MINE_MAX_WORKERS)
	# Ainda sobrando: as fazendas que faltam e as casas sem melhoria (comida a
	# mais nunca faz mal)
	for farm_cell: Vector2i in farm_cells:
		if city.free_citizens() > 0 and city.farms[farm_cell] == 0:
			city.set_farm_worked(farm_cell, true)
	for tile_cell: Vector2i in _workable_tiles(city):
		if city.free_citizens() <= 0:
			break
		city.set_tile_worked(tile_cell, true)


## Põe cidadãos livres nas fazendas (as que rendem mais primeiro) e depois nas
## casas sem melhoria até o saldo de alimento chegar a [param target]. Com
## [param capped], para quando 2/3 da cidade já está no campo (se não há fome).
func _feed(city: City, farm_cells: Array, target: int, capped: bool) -> void:
	var tiles := _workable_tiles(city)
	while city.free_citizens() > 0 and city.food_per_turn() < target:
		if capped and city.food_per_turn() >= 0 \
				and (city.farm_workers() + city.worked_tiles.size()) * 3 >= city.population * 2:
			return
		var farm_cell: Vector2i = Unit.NO_TARGET
		for candidate: Vector2i in farm_cells:
			if city.farms[candidate] == 0:
				farm_cell = candidate
				break
		if farm_cell != Unit.NO_TARGET:
			city.set_farm_worked(farm_cell, true)
		elif not tiles.is_empty():
			city.set_tile_worked(tiles.pop_front(), true)
		else:
			return


## Até [param count] cidadãos livres nas obras, em ordem de prioridade: todos na
## mais importante (sem passar do que falta), o resto na seguinte; com poucos
## cidadãos, espalhar deixaria tudo parado.
func _staff_jobs(city: City, jobs: Array[City.Construction], count: int) -> void:
	for job in jobs:
		var free := mini(count, city.free_citizens())
		if free <= 0:
			return
		var needed := job.cost() - job.progress - city.workers_on(job)
		var added := mini(maxi(needed, 0), free)
		if added > 0:
			city.set_construction_workers(job, city.workers_on(job) + added)
			count -= added


## Casas do território que um cidadão pode trabalhar sem melhoria (sem a
## madeireira remota de alguém).
func _workable_tiles(city: City) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tile_cell in city.territory:
		if city.can_work_tile(tile_cell) and not city.worked_tiles.has(tile_cell) and _game.lumber_mill_at(tile_cell) == null:
			cells.append(tile_cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return city.tile_food(a) > city.tile_food(b))
	return cells


## Ordem em que as obras recebem cidadãos (menor primeiro): comida abaixo da meta,
## defesa se falta guarnição, madeira se falta, expansão, prédios, armas e
## exército.
func _job_priority(city: City, job: City.Construction) -> int:
	var defense_short := _garrison_needed(city) + _queued_in(city, City.Build.WARRIOR) + _queued_in(city, City.Build.SPEARMAN) > 0
	var wood_short := _wood_short()
	match job.build:
		City.Build.FARM:
			return 0 if city.food_per_turn() < _p.food_surplus else 5
		City.Build.SPEAR, City.Build.WARRIOR, City.Build.SPEARMAN:
			return 1 if defense_short else 6
		City.Build.ARCHER, City.Build.CATAPULT, City.Build.BOW, City.Build.CATAPULT_FRAME:
			return 6
		City.Build.WORKER:
			return 0 if _farm_jobs() > 0 else 1 if _rebuild_jobs() > 0 else 2 if wood_short else 7
		City.Build.LUMBER_MILL:
			return 2 if wood_short else 7
		City.Build.CARPENTRY, City.Build.HEADQUARTERS:
			return 4
		City.Build.TEMPLE:
			return 1 if city.mood()["unhappy"] > 0 else 4
		City.Build.WALLS:
			return 1 if _enemy_near(city.cell, _p.threat_radius) else 4
		City.Build.SETTLER:
			return 3
		City.Build.SCHOOL, City.Build.MARKET, City.Build.LIBRARY, City.Build.FORGE, City.Build.ARENA:
			return 5
	return 8


func _queued_in(city: City, build: int) -> int:
	return city.constructions.filter(func(c: City.Construction) -> bool: return c.build == build).size()


## Inimigo perto e cidade sem guarnição: compra um soldado (e a Lança, se faltar).
func _buy_defense(city: City) -> void:
	if not _p.buy_defense or _garrison_count(city) > 0 or not _enemy_near(city.cell, _p.threat_radius):
		return
	if not city.weapons_error(_soldier()).is_empty() and _game.buy_error(city, City.Build.SPEAR).is_empty():
		_game.buy_build(city, City.Build.SPEAR)
	if _game.buy_error(city, _soldier()).is_empty():
		var bought := _soldier()
		_game.buy_build(city, bought)
		print("%s comprou um %s para defender %s" % [_player.display_name, City.BUILDS[bought]["name"], city.city_name])


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
		City.Build.MINE:
			if _game.improvement_error(worker, City.Build.MINE).is_empty():
				await focus.call(worker)
				_game.build_improvement(worker, City.Build.MINE)
		_:
			# Cidade vazia ou ruína: migra ou reconstrói no próximo turno
			if _game.rebuild_error(worker).is_empty():
				await focus.call(worker)
				_game.rebuild(worker)


## Tarefa do Trabalhador: {"cell": casa, "build": Build.FARM, LUMBER_MILL, MINE
## ou -1 (cidade vazia ou ruína)}, ou {} se não houver nada. Primeiro repovoar e
## reconstruir, depois a fazenda que falta mais perto, depois uma madeireira se
## falta madeira (da cidade, no território; senão remota) e, por último, uma
## mina no ferro do território. Casas que outro Trabalhador já ocupa ou tem
## como destino ficam de fora.
func _worker_job(worker: Unit) -> Dictionary:
	var rebuild := _rebuild_target(worker)
	if rebuild != Unit.NO_TARGET:
		return {"cell": rebuild, "build": -1}
	var taken := _taken_cells(worker)
	# Sem madeira e com menos madeireiras que cidades, a madeira vem antes das
	# fazendas (sem ela não há prédios: Marcenaria, Quartel, Templo)
	var wood_short := _wood_short()
	var mills := _player.lumber_mills.size()
	for city in _player.cities:
		mills += city.lumber_mills.size() + city.sites.values().filter(func(site: Dictionary) -> bool:
				return site["build"] == City.Build.LUMBER_MILL).size()
	if wood_short and mills < _player.cities.size():
		var first_forest := _forest_job(worker, taken)
		if not first_forest.is_empty():
			return first_forest
	var farm := _nearest(worker.cell, _farm_cells().filter(func(c: Vector2i) -> bool: return not taken.has(c)))
	if farm != Unit.NO_TARGET:
		return {"cell": farm, "build": City.Build.FARM}
	if wood_short:
		var forest := _forest_job(worker, taken)
		if not forest.is_empty():
			return forest
	var mine := _nearest(worker.cell, _mine_cells().filter(func(c: Vector2i) -> bool: return not taken.has(c)))
	return {"cell": mine, "build": City.Build.MINE} if mine != Unit.NO_TARGET else {}


## Madeireira para o Trabalhador: numa floresta do território (da cidade) ou,
## sem nenhuma, na floresta livre mais próxima (remota). {} se não houver.
func _forest_job(worker: Unit, taken: Dictionary) -> Dictionary:
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


## Se a cidade precisa de mais uma fazenda: até 2/3 da população + 1 (o campo
## fica com no máximo 2/3 da cidade; ver _distribute_workers), sem outra
## fazenda já em obra nela.
func _needs_farm(city: City) -> bool:
	if city.population <= 0 or city.sites.values().any(func(site: Dictionary) -> bool: return site["build"] == City.Build.FARM):
		return false
	return city.farms.size() < (city.population * 2 + 2) / 3 + 1


## Casas onde falta uma fazenda: as obras de fazenda paradas (sem ninguém) e,
## nas cidades que precisam de fazenda, as casas livres de pradaria e cerrado.
func _farm_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for city in _player.cities:
		for site_cell: Vector2i in city.sites:
			if city.sites[site_cell]["build"] == City.Build.FARM and not _is_worked_site(site_cell):
				cells.append(site_cell)
		if _needs_farm(city):
			# À beira do rio a fazenda rende mais: se houver, só essas casas
			var options := _game.buildable_cells(city, City.Build.FARM)
			var by_river := options.filter(func(c: Vector2i) -> bool: return _game.game_map.has_river(c))
			cells.append_array(by_river if not by_river.is_empty() else options)
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


## Colinas com ferro das cidades onde dá para fazer mina (e as obras de mina
## paradas).
func _mine_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _player.researched.has(Technology.Tech.IRON_WORKING):
		return cells
	for city in _player.cities:
		for site_cell: Vector2i in city.sites:
			if city.sites[site_cell]["build"] == City.Build.MINE and not _is_worked_site(site_cell):
				cells.append(site_cell)
		cells.append_array(_game.buildable_cells(city, City.Build.MINE))
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
	return _rebuild_jobs() + _farm_jobs() + (1 if _wood_short() else 0)


## Falta madeira: entra menos que a meta da personalidade por turno E o estoque
## está abaixo de WOOD_RESERVE.
func _wood_short() -> bool:
	return _player.wood_per_turn() < _p.wood_per_turn_goal and _player.wood < WOOD_RESERVE


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
## para a capital, 9 para as outras; pradaria 3, cerrado e floresta 2, água 1,
## +1,5 à beira do rio), sem as casas que já são de outra cidade, menos a
## distância a andar.
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
				Terrain.Type.CERRADO, Terrain.Type.FOREST, Terrain.Type.JUNGLE, Terrain.Type.HILLS:
					score += 2.0
				Terrain.Type.DESERT, Terrain.Type.TUNDRA, Terrain.Type.WATER, Terrain.Type.DEEP_WATER:
					score += 1.0
			if map.has_river(area_cell):
				score += 1.5 # casa à beira do rio: +1 de alimento
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
	occupants.erase(worker.cell) # a casa em que ele está serve (senão ele vai e volta sem construir)
	var reachable := Movement.find_reachable(map, worker, occupants, 30)
	var best := Unit.NO_TARGET
	var best_distance := INF
	for cell: Vector2i in reachable:
		if occupants.has(cell) or not Terrain.has_wood(map.get_terrain(cell)) or _game.claiming_city(cell):
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


## Unidade militar de terra que não faz parte da guarnição de uma cidade (a
## máquina ainda não usa Galés nem embarca tropas).
func _is_field_soldier(unit: Unit) -> bool:
	return unit.attack > 0 and not unit.is_naval() and unit.transport == null and not is_garrison(unit)


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


## Soldado que a máquina faz: o Lanceiro (Defesa 2, forte contra cavalaria)
## quando já tem Trabalho em Bronze; senão, o Guerreiro.
func _soldier() -> int:
	return City.Build.SPEARMAN if _player.researched.has(Technology.Tech.BRONZE_WORKING) else City.Build.WARRIOR


## Se o soldado da máquina gasta Lanças do arsenal (o Lanceiro sim, o Guerreiro não).
func _soldier_needs_spear() -> bool:
	return City.BUILDS[_soldier()].get("weapons", {}).has(Arsenal.Weapon.SPEAR)


## Quantos soldados faltam na guarnição da cidade (contando os que já estão
## na fila e os soldados livres que podem ir para lá).
func _garrison_needed(city: City) -> int:
	var queued := 0
	for construction in city.constructions:
		if construction.build in [City.Build.WARRIOR, City.Build.SPEARMAN]:
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
## (floresta ou colina primeiro: +1 de defesa). NO_TARGET se não houver.
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
		if best == Unit.NO_TARGET or Terrain.DEFENSE_BONUS.has(_game.game_map.get_terrain(cell)):
			best = cell
	return best


## Soldado de campo mais perto de [param target] para a guarnição. Arqueiro e
## Catapulta (Defesa 1) só vão se não houver nenhum de corpo a corpo.
func _nearest_soldier(target: Vector2i) -> Unit:
	var best: Unit = null
	var best_distance := 1 << 30
	for unit in _player.units:
		if not _is_field_soldier(unit):
			continue
		var distance := maxi(absi(unit.cell.x - target.x), absi(unit.cell.y - target.y)) \
				+ (RANGED_GARRISON_PENALTY if unit.is_ranged() else 0)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best
