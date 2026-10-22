class_name Game
extends Node2D

## Monta a partida de exemplo e executa as ações do jogo (mover, atacar,
## fundar cidade, madeireira remota, encerrar turno). O jogador humano age por
## cliques; o jogador máquina, pelo AIController, usando exatamente as mesmas ações.

const MAP_TEXTURE: Texture2D = preload("res://data/maps/mapa_teste.png")
const WARRIOR: UnitType = preload("res://data/units/guerreiro.tres")
const ARCHER: UnitType = preload("res://data/units/arqueiro.tres")
const HORSEMAN: UnitType = preload("res://data/units/cavaleiro.tres")
const SETTLER: UnitType = preload("res://data/units/colono.tres")
## Cursor do modo "Mover" (tecla G). Ponta da seta no canto superior esquerdo.
const GO_CURSOR: Texture2D = preload("res://assets/sprites/ui/cursor_go.png")

## Casa onde a câmera começa (centro da ilha do mapa de teste).
const START_CAMERA_CELL := Vector2i(60, 41)
## Partida de teste com as tropas (Guerreiro, Arqueiro e Cavaleiro) de cada lado.
## Desligado para observar só o gerenciamento das cidades, sem guerra.
const WITH_TROOPS := false

var players: Array[Player] = []
var selected_unit: Unit = null
var game_over := false

## Resultado de Movement.find_reachable para a unidade selecionada.
var _reachable := {}
## Resultado de Movement.attack_targets para a unidade selecionada.
var _attack_targets := {}
var _rng := RandomNumberGenerator.new()
## Um AIController por jogador máquina (cada um guarda o próprio estado).
var _ais := {}
## Animação ou turno da máquina em andamento: o jogador humano não pode agir.
var _is_busy := false
var _awaiting_end_turn := false
var _hover_cell := Vector2i(-1, -1)
## Modo "Mover" (tecla G): o próximo clique escolhe o destino da unidade selecionada.
var _goto_mode := false
## Madeireira remota selecionada (clique nela): a barra de ações mostra
## "Retirar trabalhador". Só uma coisa fica selecionada: unidade ou madeireira.
var _selected_mill: LumberMill = null
## Construções concluídas nas cidades do humano neste início de turno, à espera
## do aviso: [[City, City.Build], ...].
var _completion_notices: Array[Array] = []

@onready var game_map: GameMap = $GameMap
@onready var move_overlay: MoveOverlay = $MoveOverlay
@onready var cities_root: Node2D = $Cities
@onready var units_root: Node2D = $Units
@onready var camera: MapCamera = $MapCamera
@onready var hud: Hud = $HUD


func _ready() -> void:
	_rng.randomize()
	game_map.load_from_image(MAP_TEXTURE.get_image())
	camera.set_bounds(game_map.get_pixel_size())
	camera.position = game_map.cell_to_world(START_CAMERA_CELL)

	players = [
		Player.new(1, "Jogador 1", Color8(220, 40, 40)),
		Player.new(2, "Jogador 2", Color8(250, 220, 40), true),
	]
	_spawn_example_units()

	hud.action_pressed.connect(_on_unit_action)
	hud.city_window.closed.connect(_on_city_window_closed)
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.start_game(players)


func _process(_delta: float) -> void:
	var cell := game_map.world_to_cell(get_global_mouse_position())
	if cell != _hover_cell:
		_hover_cell = cell
		_update_info()
		if _goto_mode:
			_preview_goto(cell)
	_update_resources()


func _unhandled_input(event: InputEvent) -> void:
	var is_enter: bool = (event is InputEventKey and event.pressed and not event.echo
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER])
	var key: int = event.keycode if event is InputEventKey and event.pressed and not event.echo else KEY_NONE
	if hud.city_window.visible or hud.city_name_dialog.visible or hud.notice_dialog.visible or hud.save_dialog.visible:
		return # as janelas cuidam dos próprios cliques e teclas
	if key == KEY_F9 and not _is_busy:
		_open_save_dialog(false) # carregar também vale na tela de vitória
		return
	if game_over:
		if is_enter:
			get_tree().reload_current_scene()
		return
	if _is_busy or TurnManager.current_player().is_ai:
		return
	if key == KEY_F5:
		_open_save_dialog(true)
		return

	if is_enter:
		if _awaiting_end_turn:
			TurnManager.end_turn()
	elif event is InputEventMouseButton:
		# Clique esquerdo vale ao soltar o botão: se o mouse foi arrastado, a
		# MapCamera moveu o mapa e consumiu o evento antes de chegar aqui.
		var cell := game_map.world_to_cell(get_global_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _goto_mode:
				_on_goto_clicked(cell)
			else:
				_on_cell_clicked(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_goto_mode_or_deselect()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_skip_selected_unit()
			KEY_F:
				_fortify_selected_unit()
			KEY_G:
				_start_goto_mode()
			KEY_B:
				_found_city_with_selected()
			KEY_M:
				_work_lumber_mill_with_selected()
			KEY_ESCAPE:
				_on_escape()


# --- Consultas -------------------------------------------------------------

func get_unit_at(cell: Vector2i) -> Unit:
	return occupants().get(cell)


## {casa: Unit} de todas as unidades no mapa. Trabalhadores dentro de uma
## madeireira remota não ocupam a casa.
func occupants() -> Dictionary:
	var result := {}
	for player in players:
		for unit in player.units:
			if unit.working_mill == null:
				result[unit.cell] = unit
	return result


## Se a unidade ainda tem alguma ação possível (mover ou atacar) neste turno.
func can_move(unit: Unit) -> bool:
	if unit.moves_left <= 0 or unit.working_mill:
		return false
	var current := occupants()
	var reachable := Movement.find_reachable(game_map, unit, current)
	return (not Movement.destinations(reachable, current).is_empty()
			or not Movement.attack_targets(game_map, unit, reachable, current).is_empty())


func cities() -> Array[City]:
	var result: Array[City] = []
	for player in players:
		result.append_array(player.cities)
	return result


func get_city_at(cell: Vector2i) -> City:
	for city in cities():
		if city.cell == cell:
			return city
	return null


## Cidade que tem uma fazenda ou obra na casa (ou null).
func claiming_city(cell: Vector2i) -> City:
	for city in cities():
		if city.is_claimed(cell):
			return city
	return null


## Madeireira remota (de qualquer jogador) na casa, ou null.
func lumber_mill_at(cell: Vector2i) -> LumberMill:
	for player in players:
		for mill in player.lumber_mills:
			if mill.cell == cell:
				return mill
	return null


## Casas da área da cidade onde dá para construir a melhoria [param build]:
## terreno certo (fazenda em pradaria/cerrado, madeireira em floresta), dentro
## do mapa e sem cidade, melhoria ou obra (de qualquer cidade) nem madeireira remota.
func buildable_cells(city: City, build: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in city.area_cells():
		if (cell != city.cell and game_map.is_in_bounds(cell)
				and City.allows_terrain(build, game_map.get_terrain(cell))
				and get_city_at(cell) == null and claiming_city(cell) == null
				and lumber_mill_at(cell) == null):
			result.append(cell)
	return result


## Motivo pelo qual a unidade não pode fundar uma cidade onde está ("" = pode).
func city_site_error(unit: Unit) -> String:
	if not unit.type.can_found_city:
		return "Só colonos podem construir cidades."
	if unit.moves_left <= 0:
		return "O colono não tem mais movimentos neste turno."
	for city in cities():
		var distance := maxi(absi(city.cell.x - unit.cell.x), absi(city.cell.y - unit.cell.y))
		if distance < City.MIN_DISTANCE:
			return "Muito perto de %s (as cidades precisam estar a %d casas uma da outra)." % [city.city_name, City.MIN_DISTANCE]
	if claiming_city(unit.cell):
		return "Esta casa já é usada por %s." % claiming_city(unit.cell).city_name
	if lumber_mill_at(unit.cell):
		return "Esta casa já tem uma madeireira."
	return ""


## Motivo pelo qual a cidade não pode comprar [param build] com ouro agora
## ("" = pode). Melhorias de terreno ainda não podem ser compradas.
func buy_error(city: City, build: int) -> String:
	var info: Dictionary = City.BUILDS[build]
	if info["category"] == City.Category.TERRAIN_IMPROVEMENT:
		return "Melhorias de terreno ainda não podem ser compradas."
	# Prédio em obra pode ser comprado (a obra sai da fila); o resto segue build_error
	var error := city.build_error(build)
	if not error.is_empty() and not (info["category"] == City.Category.BUILDING and city.construction_of(build)):
		return error
	var player := city.owner_player
	if player.gold < info["gold"]:
		return "Ouro insuficiente: custa %d e o tesouro tem %d." % [info["gold"], player.gold]
	if info.has("unit"):
		if city.population - info.get("population", 0) < 1:
			return "A cidade precisa ter pelo menos %d de população." % (info.get("population", 0) + 1)
		if free_cell_near(city.cell, 1) == Unit.NO_TARGET:
			return "Não há espaço livre ao redor da cidade para a unidade."
	return ""


## Compra com ouro: a unidade sai na cidade no mesmo instante (pagando também
## a população), a arma vai para o arsenal ou o prédio fica pronto; o preço sai
## do tesouro e a madeira e as armas do item, dos estoques (um prédio que já
## estava em obra já pagou ao ser pedido). Use buy_error antes.
func buy_build(city: City, build: int) -> void:
	var info: Dictionary = City.BUILDS[build]
	var player := city.owner_player
	player.gold -= info["gold"]
	if city.construction_of(build) == null or info.has("unit") or info.has("weapon"):
		city.pay_resources(build)
	if info.has("weapon"):
		player.arsenal[info["weapon"]] += 1
		city.changed.emit()
	elif info.has("unit"):
		_spawn_city_unit(info["unit"], city)
		city.pay_population(info.get("population", 0))
	elif info["category"] == City.Category.BUILDING:
		city.add_building(build)
	print("%s comprou %s em %s por %d de ouro" % [player.display_name, info["name"], city.city_name, info["gold"]])


## Motivo pelo qual o trabalhador não pode construir uma madeireira onde está,
## nem entrar na que já existe ali ("" = pode).
func lumber_mill_error(unit: Unit) -> String:
	if not unit.type.can_build_lumber_mill:
		return "Só trabalhadores constroem madeireiras."
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	var mill := lumber_mill_at(unit.cell)
	if mill:
		if mill.owner_player != unit.owner_player:
			return "Esta madeireira é de outro jogador."
		if not mill.has_room():
			return "A madeireira já tem %d trabalhadores (o máximo)." % LumberMill.MAX_WORKERS
		return ""
	if game_map.get_terrain(unit.cell) != Terrain.Type.FOREST:
		return "Madeireiras só podem ser construídas na floresta."
	if claiming_city(unit.cell):
		return "Esta casa já é usada por %s." % claiming_city(unit.cell).city_name
	return ""


# --- Ações (usadas pelo jogador humano e pela máquina) ----------------------

## Seleciona a unidade: ela pisca e o overlay mostra para onde pode ir e quem pode atacar.
func select_unit(unit: Unit) -> void:
	if selected_unit:
		selected_unit.set_selected(false)
	selected_unit = unit
	_selected_mill = null
	_reachable = {}
	_attack_targets = {}
	_set_goto_mode(false)
	if unit:
		unit.set_selected(true)
		var current := occupants()
		_reachable = Movement.find_reachable(game_map, unit, current)
		_attack_targets = Movement.attack_targets(game_map, unit, _reachable, current)
		move_overlay.show_moves(unit.cell, Movement.destinations(_reachable, current), _attack_targets.keys())
		if unit.has_goto():
			_show_goto_path(unit, unit.goto_target)
	else:
		move_overlay.clear()
	_update_unit_actions()
	_update_info()


## Move a unidade até [param target], que deve ser uma casa vazia ao alcance.
func move_unit(unit: Unit, target: Vector2i) -> void:
	move_overlay.clear()
	var reachable := Movement.find_reachable(game_map, unit, occupants())
	await unit.move_along(Movement.build_path(reachable, target), game_map)


## Anda até a casa de ataque (se precisar) e ataca o inimigo em [param target_cell].
## O ataque encerra os movimentos do atacante; se o defensor for destruído,
## o atacante ocupa a casa dele.
func attack(attacker: Unit, target_cell: Vector2i) -> void:
	move_overlay.clear()
	attacker.fortified = false
	var current := occupants()
	var defender: Unit = current[target_cell]
	var reachable := Movement.find_reachable(game_map, attacker, current)
	var from_cell: Vector2i = Movement.attack_targets(game_map, attacker, reachable, current)[target_cell]
	if from_cell != attacker.cell:
		await attacker.move_along(Movement.build_path(reachable, from_cell), game_map)

	await attacker.play_attack(defender.position)
	var result := Combat.resolve(attacker, defender, _rng)
	attacker.skip_turn()
	_show_damage(defender, result.damage_to_defender)
	_show_damage(attacker, result.damage_to_attacker, 0.45)
	print("%s (%s) ataca %s (%s): causa %d, recebe %d -> energia %d x %d" % [
		attacker.type.display_name, attacker.owner_player.display_name,
		defender.type.display_name, defender.owner_player.display_name,
		result.damage_to_defender, result.damage_to_attacker, attacker.energy, defender.energy,
	])

	if result.defender_destroyed:
		await _destroy_unit(defender)
		await attacker.advance_to(target_cell, game_map)
	elif result.attacker_destroyed:
		await _destroy_unit(attacker)


## O colono funda uma cidade na casa em que está e deixa de existir.
## Cidade fundada na floresta transforma a casa em pradaria.
## Use city_site_error antes para saber se o lugar é válido.
## [param city_name] vazio = próximo nome da lista City.NAMES.
func found_city(settler: Unit, city_name := "") -> City:
	var player := settler.owner_player
	if game_map.get_terrain(settler.cell) == Terrain.Type.FOREST:
		game_map.set_terrain(settler.cell, Terrain.Type.GRASSLAND)
	var city := City.new()
	city.setup(city_name if not city_name.is_empty() else _next_city_name(), player, settler.cell, game_map)
	cities_root.add_child(city)
	player.cities.append(city)
	print("%s fundou a cidade %s em %s" % [player.display_name, city.city_name, city.cell])
	FloatingText.spawn(units_root, city.position - Vector2(0, GameMap.TILE_SIZE / 2.0),
			city.city_name, Color.WHITE)

	if settler == selected_unit:
		select_unit(null)
	player.units.erase(settler)
	settler.queue_free()
	_check_victory()
	return city


## O trabalhador constrói uma madeireira remota na casa em que está (ou entra
## na que já existe ali) e passa a trabalhar nela: some do mapa e não recebe
## ordens até ser retirado. Use lumber_mill_error antes.
func work_lumber_mill(worker: Unit) -> LumberMill:
	var player := worker.owner_player
	var mill := lumber_mill_at(worker.cell)
	if mill == null:
		mill = LumberMill.new()
		mill.setup(player, worker.cell, game_map)
		cities_root.add_child(mill)
		player.lumber_mills.append(mill)
		print("%s começou uma madeireira em %s" % [player.display_name, worker.cell])
	if worker == selected_unit:
		select_unit(null)
	worker.goto_target = Unit.NO_TARGET
	worker.fortified = false
	worker.skip_turn()
	worker.working_mill = mill
	mill.workers.append(worker)
	mill.queue_redraw()
	return mill


## Um trabalhador sai da madeireira e volta ao mapa, na casa dela ou na casa
## livre mais próxima. Retorna o trabalhador, ou null se não houver espaço.
func release_mill_worker(mill: LumberMill) -> Unit:
	var cell := free_cell_near(mill.cell, 2)
	if mill.workers.is_empty() or cell == Unit.NO_TARGET:
		return null
	var worker: Unit = mill.workers.pop_back()
	worker.working_mill = null
	worker.cell = cell
	worker.position = game_map.cell_to_world(cell)
	mill.queue_redraw()
	return worker


## Casa de terra livre mais próxima de [param center] (a própria casa primeiro),
## até [param radius] casas de distância, ou Unit.NO_TARGET se não houver.
func free_cell_near(center: Vector2i, radius: int) -> Vector2i:
	var current := occupants()
	for distance in radius + 1:
		for y in range(-distance, distance + 1):
			for x in range(-distance, distance + 1):
				var cell := center + Vector2i(x, y)
				if (maxi(absi(x), absi(y)) == distance and game_map.is_in_bounds(cell)
						and Terrain.is_walkable(game_map.get_terrain(cell)) and not current.has(cell)):
					return cell
	return Unit.NO_TARGET


# --- Jogador humano ---------------------------------------------------------

func _on_cell_clicked(cell: Vector2i) -> void:
	var unit := get_unit_at(cell)
	var city := get_city_at(cell)
	var current := TurnManager.current_player()
	# Unidade escondida na cidade não é selecionada pelo mapa: o clique abre a
	# cidade, e ela é ativada pela janela da cidade.
	var own_unit := unit if unit and unit.owner_player == current and not unit.hidden_in_city else null
	var mill := lumber_mill_at(cell)
	if selected_unit and _attack_targets.has(cell):
		selected_unit.goto_target = Unit.NO_TARGET # ordem manual cancela o "Mover"
		_human_action(attack.bind(selected_unit, cell))
	elif own_unit and own_unit != selected_unit:
		select_unit(own_unit)
	elif selected_unit and _reachable.has(cell) and unit == null:
		selected_unit.goto_target = Unit.NO_TARGET
		_human_action(move_unit.bind(selected_unit, cell))
	elif city:
		_open_city(city) # cidade do adversário abre só para observar
	elif mill and mill.owner_player == current and unit == null:
		_select_mill(mill)
	elif own_unit:
		select_unit(own_unit)
	else:
		select_unit(null)


# --- Ordem "Mover" (tecla G) ------------------------------------------------

## Entra no modo de escolha do destino: cursor "Go >" e prévia do caminho.
func _start_goto_mode() -> void:
	if selected_unit and selected_unit.owner_player == TurnManager.current_player():
		_set_goto_mode(true)
		_preview_goto(_hover_cell)


func _set_goto_mode(enabled: bool) -> void:
	if enabled == _goto_mode:
		return
	_goto_mode = enabled
	if enabled:
		Input.set_custom_mouse_cursor(GO_CURSOR, Input.CURSOR_ARROW, Vector2.ZERO)
		hud.show_message("Escolha o destino (Esc ou botão direito cancela)", Color(1, 0.9, 0.3))
	else:
		Input.set_custom_mouse_cursor(null)
		if selected_unit:
			_show_goto_path(selected_unit, selected_unit.goto_target)


func _cancel_goto_mode_or_deselect() -> void:
	if _goto_mode:
		_set_goto_mode(false)
	else:
		select_unit(null)


## Esc: sai do modo "Mover"; se a unidade selecionada já tem um destino,
## cancela a caminhada; senão, tira a seleção.
func _on_escape() -> void:
	if not _goto_mode and selected_unit and selected_unit.has_goto():
		_cancel_goto(selected_unit)
	else:
		_cancel_goto_mode_or_deselect()


## Cancela a caminhada: a unidade para onde está e volta a receber ordens.
func _cancel_goto(unit: Unit) -> void:
	unit.goto_target = Unit.NO_TARGET
	hud.show_message("Caminhada cancelada.", Color(1, 0.9, 0.3))
	select_unit(unit) # redesenha sem o caminho e atualiza os botões


## Prévia: caminho da unidade selecionada até a casa sob o mouse.
func _preview_goto(cell: Vector2i) -> void:
	if selected_unit:
		_show_goto_path(selected_unit, cell)


## Desenha o caminho até [param target] com os turnos para chegar (ou nada,
## se não houver caminho).
func _show_goto_path(unit: Unit, target: Vector2i) -> void:
	var path: Array[Vector2i] = []
	if target != Unit.NO_TARGET and game_map.is_in_bounds(target):
		path = Movement.find_path(game_map, unit, target, occupants())
	move_overlay.show_path(path, _turns_for_path(unit, path))


## Turnos para andar o caminho: o que sobra neste turno, depois o movimento
## cheio por turno. Uma casa que custa mais do que o que sobra fica para o
## turno seguinte (ex.: Cavaleiro com 1 movimento diante de uma floresta).
func _turns_for_path(unit: Unit, path: Array[Vector2i]) -> int:
	var turns := 1
	var moves := unit.moves_left if unit.moves_left > 0 else unit.movement
	for cell in path:
		var cost := Movement.step_cost(game_map, unit, cell)
		if cost > moves:
			turns += 1
			moves = unit.movement
		moves -= cost
	return turns


## Clique no modo "Mover": guarda o destino e a unidade já começa a andar.
func _on_goto_clicked(cell: Vector2i) -> void:
	var unit := selected_unit
	_set_goto_mode(false)
	if unit == null:
		return
	if not game_map.is_in_bounds(cell) or Movement.find_path(game_map, unit, cell, occupants()).is_empty():
		hud.show_message("Não há caminho por terra até essa casa.", Color(1, 0.6, 0.4))
		_show_goto_path(unit, unit.goto_target)
		return
	unit.goto_target = cell
	unit.fortified = false
	_human_action(advance_goto.bind(unit))


## Anda o quanto der neste turno pelo caminho até o destino da ordem "Mover".
## Recalcula o caminho a cada vez (unidades podem ter entrado no caminho).
## Ao chegar, a ordem acaba. Se o destino estiver ocupado por um aliado e a
## unidade já estiver ao lado dele, também acaba (não dá para empilhar).
func advance_goto(unit: Unit) -> void:
	if not unit.has_goto() or unit.moves_left <= 0:
		return
	var current := occupants()
	var path := Movement.find_path(game_map, unit, unit.goto_target, current)
	if path.is_empty():
		unit.goto_target = Unit.NO_TARGET
		return
	# Casa mais distante do caminho alcançável neste turno e livre para parar
	var stop := -1
	var spent := 0
	for i in path.size():
		spent += Movement.step_cost(game_map, unit, path[i])
		if spent > unit.moves_left:
			break
		if not current.has(path[i]):
			stop = i
	if stop >= 0:
		await move_unit(unit, path[stop])
	if unit.cell == unit.goto_target or (path.size() == 1 and current.has(path[0])):
		unit.goto_target = Unit.NO_TARGET


## Início da vez do humano: as unidades com ordem "Mover" andam sozinhas.
func _run_goto_orders(player: Player) -> void:
	for unit in player.units.duplicate():
		if unit.has_goto() and not game_over:
			await camera.pan_to(unit.position, 0.15)
			await advance_goto(unit)


## Botões da barra de ações do HUD (os mesmos das teclas de atalho).
func _on_unit_action(action_id: String) -> void:
	if _is_busy or game_over or TurnManager.current_player().is_ai:
		return
	match action_id:
		"found_city":
			_found_city_with_selected()
		"skip":
			_skip_selected_unit()
		"fortify":
			_fortify_selected_unit()
		"goto":
			_start_goto_mode()
		"cancel_goto":
			if selected_unit:
				_cancel_goto(selected_unit)
		"lumber_mill":
			_work_lumber_mill_with_selected()
		"release_worker":
			_release_worker_from_selected_mill()


## Tecla B / botão "Construir nova cidade". Pergunta o nome da cidade, funda
## e abre a cidade para o jogador já escolher o que construir.
func _found_city_with_selected() -> void:
	var settler := selected_unit
	if settler == null or not settler.type.can_found_city:
		return
	var error := city_site_error(settler)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	camera.locked = true # setas/WASD e roda do mouse não mexem no mapa enquanto digita
	hud.city_name_dialog.open(_next_city_name())
	var city_name: String = await hud.city_name_dialog.confirmed
	camera.locked = false
	if city_name.is_empty():
		return # cancelou: o colono continua onde está
	var city := found_city(settler, city_name)
	if not game_over:
		_open_city(city)


## Tecla M / botão da madeireira: o trabalhador selecionado constrói uma
## madeireira onde está (ou entra na que já existe) e passa a trabalhar nela.
func _work_lumber_mill_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_build_lumber_mill:
		return
	var error := lumber_mill_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	var mill := work_lumber_mill(worker)
	var status := "em obra %d/%d" % [mill.progress, mill.cost()] if not mill.is_done() else "pronta"
	hud.show_message("Trabalhador na madeireira (%s, %d/%d trabalhadores)." % [
			status, mill.workers.size(), LumberMill.MAX_WORKERS], Color(0.75, 1, 0.75))
	_select_next_unit()


## Clique numa madeireira remota sua: seleciona a madeireira para retirar
## trabalhadores dela pela barra de ações.
func _select_mill(mill: LumberMill) -> void:
	select_unit(null)
	_selected_mill = mill
	move_overlay.show_moves(mill.cell, [], [])
	_update_unit_actions()


## Botão "Retirar trabalhador": o trabalhador volta ao mapa e fica selecionado.
func _release_worker_from_selected_mill() -> void:
	var mill := _selected_mill
	if mill == null:
		return
	var worker := release_mill_worker(mill)
	if worker == null:
		hud.show_message("Não há espaço livre perto da madeireira.", Color(1, 0.6, 0.4))
		return
	select_unit(worker)


func _open_city(city: City) -> void:
	camera.locked = true # setas/WASD e roda do mouse não mexem no mapa por trás da janela
	hud.city_window.open(city, self, city.owner_player != TurnManager.current_player())


func _on_city_window_closed() -> void:
	camera.locked = false
	_update_info()
	# Durante os avisos do início do turno (_is_busy), a seleção fica para o fim
	if selected_unit == null and not _is_busy and not TurnManager.current_player().is_ai and not game_over:
		_select_next_unit()


## Executa uma ação da unidade selecionada e decide o que selecionar em seguida.
func _human_action(action: Callable) -> void:
	var unit := selected_unit
	_is_busy = true
	await action.call()
	_is_busy = false
	if game_over:
		return
	if is_instance_valid(unit) and unit == selected_unit and can_move(unit):
		select_unit(unit)
	else:
		_select_next_unit()


## Espaço: a unidade selecionada não se move mais neste turno.
func _skip_selected_unit() -> void:
	if selected_unit:
		selected_unit.skip_turn()
		_select_next_unit()


## F: a unidade selecionada se fortifica (+1 de defesa e recupera energia a cada
## turno). Fica fortificada, sem ser selecionada sozinha, até receber outra ordem.
## Dentro de uma cidade, ela some do mapa e fica na janela da cidade.
func _fortify_selected_unit() -> void:
	var unit := selected_unit
	if unit and not unit.fortified:
		unit.fortify()
		unit.hidden_in_city = get_city_at(unit.cell) != null
		_select_next_unit()


## Botão "Ativar" da janela da cidade: a unidade sai da fortificação, volta a
## aparecer no mapa e fica selecionada.
func activate_unit(unit: Unit) -> void:
	unit.fortified = false
	hud.city_window.close()
	select_unit(unit)
	camera.pan_to(unit.position)


## Seleciona a próxima unidade do jogador que ainda pode agir. Se não houver
## nenhuma, pede a confirmação de fim de turno. Unidades fortificadas ou com
## ordem "Mover" ficam de fora (para dar outra ordem, clique nelas).
func _select_next_unit() -> void:
	for unit in TurnManager.current_player().units:
		if not unit.fortified and not unit.has_goto() and can_move(unit):
			select_unit(unit)
			return
	select_unit(null)
	_awaiting_end_turn = true
	hud.show_end_turn_prompt(true)


# --- Turnos e fim de jogo ---------------------------------------------------

func _on_turn_started(player: Player, turn_number: int) -> void:
	print("Turno %d - vez do %s" % [turn_number, player.display_name])
	_awaiting_end_turn = false
	hud.set_turn(turn_number, player)
	_heal_fortified_units(player)
	_process_cities(player)
	_process_lumber_mills(player)
	if player.is_ai:
		_play_ai_turn(player)
	else:
		_start_human_turn(player)


## Vez do humano: primeiro o salvamento automático, depois as ordens "Mover"
## andam sozinhas, aparecem os avisos de construção concluída e, por fim, a
## primeira unidade sem ordem é selecionada.
func _start_human_turn(player: Player, autosave := true) -> void:
	_is_busy = true
	if autosave and not game_over:
		var error := SaveGame.write(SaveGame.AUTOSAVE_SLOT, capture_state())
		if error != OK:
			push_warning("Salvamento automático falhou (%s)." % error_string(error))
	await _run_goto_orders(player)
	await _show_completion_notices()
	_is_busy = false
	if game_over:
		return
	if selected_unit == null: # pode ter sido ativada pela janela da cidade
		_select_next_unit()
	if selected_unit:
		camera.pan_to(selected_unit.position)


## A máquina joga o turno inteiro e passa a vez sozinha (sem confirmação).
func _play_ai_turn(player: Player) -> void:
	_is_busy = true
	select_unit(null)
	if not _ais.has(player):
		_ais[player] = AIController.new()
	await _ais[player].play_turn(self, player)
	select_unit(null)
	_is_busy = false
	if not game_over:
		TurnManager.end_turn.call_deferred()


## Início da vez do jogador: unidades fortificadas e feridas recuperam energia.
func _heal_fortified_units(player: Player) -> void:
	for unit in player.units:
		var healed := unit.heal_if_fortified()
		if healed > 0:
			var top := unit.position - Vector2(0, GameMap.TILE_SIZE / 2.0)
			FloatingText.spawn(units_root, top, "+%d" % healed, Color(0.4, 1, 0.4))


## Início da vez do jogador: as cidades dele produzem, comem e crescem.
## O jogador humano vê o resumo no topo da tela.
func _process_cities(player: Player) -> void:
	var messages: Array[String] = []
	for city in player.cities:
		for event in city.process_turn(_spawn_city_unit):
			messages.append("%s: %s" % [city.city_name, event])
		if not player.is_ai:
			for build in city.completed:
				_completion_notices.append([city, build])
	for message in messages:
		print(message)
	if not player.is_ai and not messages.is_empty():
		hud.show_message("\n".join(messages), Color(0.75, 1, 0.75))


## Um aviso por construção concluída: a câmera vai até a cidade e o modal diz
## o que ficou pronto e quantos cidadãos estão livres. "Abrir cidade" abre a
## janela da cidade (o próximo aviso espera ela fechar).
func _show_completion_notices() -> void:
	while not _completion_notices.is_empty() and not game_over:
		var notice: Array = _completion_notices.pop_front()
		var city: City = notice[0]
		if not is_instance_valid(city):
			continue
		camera.pan_to(city.position)
		hud.notice_dialog.open(city.city_name, _completion_notice_text(city, notice[1]))
		var open_city: bool = await hud.notice_dialog.closed
		if open_city:
			_open_city(city)
			await hud.city_window.closed


## "A construção da fazenda foi concluída." + situação dos cidadãos livres.
func _completion_notice_text(city: City, build: int) -> String:
	var text := City.completion_text(build)
	var idle := city.free_citizens()
	if idle > 0:
		text += "\n[color=#%s]%d %s sem tarefa nesta cidade.[/color] Abra a cidade para dar outra tarefa a %s." % [
			City.IDLE_COLOR.lightened(0.3).to_html(false), idle,
			"cidadão está" if idle == 1 else "cidadãos estão", "ele" if idle == 1 else "eles"]
	else:
		text += "\nTodos os cidadãos da cidade estão trabalhando."
	return text


## Início da vez do jogador: as madeireiras remotas avançam a obra ou tiram
## madeira (com um "+N" azul subindo). Floresta esgotada vira cerrado: a
## madeireira some e os trabalhadores voltam ao mapa.
func _process_lumber_mills(player: Player) -> void:
	var messages: Array[String] = []
	for mill: LumberMill in player.lumber_mills.duplicate():
		var was_done := mill.is_done()
		var wood := mill.process_turn()
		player.wood += wood
		if wood > 0:
			FloatingText.spawn(units_root, mill.position - Vector2(0, GameMap.TILE_SIZE / 2.0),
					"+%d" % wood, LumberMill.WOOD_BAR_COLOR)
		if mill.is_done() and not was_done:
			messages.append("Madeireira em (%d, %d) pronta" % [mill.cell.x, mill.cell.y])
		if mill.is_exhausted():
			messages.append("A floresta em (%d, %d) acabou e virou cerrado" % [mill.cell.x, mill.cell.y])
			_remove_lumber_mill(mill)
	for message in messages:
		print("%s: %s" % [player.display_name, message])
	if not player.is_ai and not messages.is_empty():
		hud.show_message("\n".join(messages), Color(0.75, 1, 0.75))


## Tira a madeireira do mapa; os trabalhadores voltam ao mapa ao redor dela.
func _remove_lumber_mill(mill: LumberMill) -> void:
	while not mill.workers.is_empty():
		if release_mill_worker(mill) == null:
			# Sem espaço livre por perto (raro): fica na própria casa
			var worker: Unit = mill.workers.pop_back()
			worker.working_mill = null
			push_warning("Trabalhador sem espaço livre ao sair da madeireira em %s." % mill.cell)
	if mill == _selected_mill:
		select_unit(null)
	mill.owner_player.lumber_mills.erase(mill)
	mill.queue_free()


## Unidade treinada por uma cidade: sai na própria cidade ou, se já houver uma
## unidade lá, na primeira casa vizinha de terra livre. Retorna false se não
## houver espaço (a cidade tenta de novo no próximo turno).
func _spawn_city_unit(type: UnitType, city: City) -> bool:
	var cell := free_cell_near(city.cell, 1)
	if cell == Unit.NO_TARGET:
		return false
	_spawn_unit(type, city.owner_player, cell)
	return true


func _destroy_unit(unit: Unit) -> void:
	print("%s (%s) foi destruído" % [unit.type.display_name, unit.owner_player.display_name])
	if unit == selected_unit:
		select_unit(null)
	unit.owner_player.units.erase(unit)
	_check_victory()
	await unit.play_death()


## Objetivo da partida: eliminar o adversário. Um jogador continua vivo enquanto
## tiver unidades ou cidades; vence quem for o último vivo. (As cidades ainda
## não podem ser atacadas.)
func _check_victory() -> void:
	var alive := players.filter(func(player: Player) -> bool: return not player.units.is_empty() or not player.cities.is_empty())
	if alive.size() != 1:
		return
	game_over = true
	_awaiting_end_turn = false
	hud.show_end_turn_prompt(false)
	hud.show_victory(alive[0])
	print("%s venceu!" % alive[0].display_name)


# --- Salvar e carregar (ver SaveGame) ----------------------------------------

## F5 / F9: janela dos espaços de save. Salvar só na vez do humano, sem nada
## acontecendo; carregar também na tela de vitória.
func _open_save_dialog(saving: bool) -> void:
	_set_goto_mode(false)
	camera.locked = true
	hud.save_dialog.open(saving)
	var slot: int = await hud.save_dialog.closed
	camera.locked = false
	if slot < 0:
		return
	if saving:
		var error := save_game(slot)
		if error == OK:
			hud.show_message("Partida salva (%s)." % SaveGame.slot_name(slot), Color(0.75, 1, 0.75))
		else:
			hud.show_message("Não foi possível salvar: %s." % error_string(error), Color(1, 0.6, 0.4))
	elif not load_game(slot):
		hud.show_message("Não foi possível carregar %s." % SaveGame.slot_name(slot), Color(1, 0.6, 0.4))


func save_game(slot: int) -> Error:
	return SaveGame.write(slot, capture_state())


## Carrega o espaço e continua a partida de onde ela foi salva. Retorna false
## se o arquivo não existir ou não puder ser lido.
func load_game(slot: int) -> bool:
	var data := SaveGame.read(slot)
	if data.is_empty():
		return false
	restore_state(data)
	hud.show_message("Partida carregada (%s, turno %d)." % [SaveGame.slot_name(slot), TurnManager.turn_number],
			Color(0.75, 1, 0.75))
	return true


## Tudo o que muda durante a partida, pronto para virar JSON: o turno, o mapa
## (terreno e madeira das florestas) e cada jogador com as unidades, cidades e
## madeireiras dele (ver os to_dict de cada classe). O estado da máquina
## (personalidade, turnos esperando) vai junto com o jogador.
func capture_state() -> Dictionary:
	var players_data := []
	for player in players:
		var data := player.to_dict()
		if _ais.has(player):
			data["ai_turns_waiting"] = _ais[player].turns_waiting
		players_data.append(data)
	return {"turn_manager": TurnManager.to_dict(), "map": game_map.to_dict(), "players": players_data}


## Troca a partida atual pela de [param data] (de capture_state, já lida do
## arquivo) e continua a vez de quem estava jogando, sem processar o início do
## turno de novo (as cidades já tinham produzido quando o jogo foi salvo).
func restore_state(data: Dictionary) -> void:
	select_unit(null)
	_set_goto_mode(false)
	_completion_notices.clear()
	_awaiting_end_turn = false
	hud.show_end_turn_prompt(false)
	hud.hide_victory()
	game_over = false
	for root: Node in [units_root, cities_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()

	game_map.from_dict(data["map"])
	players = []
	_ais = {}
	for player_data: Dictionary in data["players"]:
		var player := Player.from_dict(player_data)
		players.append(player)
		if player.is_ai:
			_ais[player] = AIController.new()
			_ais[player].turns_waiting = int(player_data.get("ai_turns_waiting", 0))
		var mills: Array[LumberMill] = []
		for mill_data: Dictionary in player_data["lumber_mills"]:
			var mill := LumberMill.new()
			mill.setup(player, SaveGame.json_to_cell(mill_data["cell"]), game_map)
			mill.progress = int(mill_data["progress"])
			cities_root.add_child(mill)
			player.lumber_mills.append(mill)
			mills.append(mill)
		for unit_data: Dictionary in player_data["units"]:
			var unit := Unit.new()
			unit.setup(load(unit_data["type"]), player, SaveGame.json_to_cell(unit_data["cell"]), game_map)
			unit.position = game_map.cell_to_world(unit.cell)
			unit.name = "%s_%s_%d" % [unit.type.display_name, player.id, player.units.size() + 1]
			units_root.add_child(unit)
			player.units.append(unit)
			unit.apply_dict(unit_data)
		# Trabalhadores dentro das madeireiras (pela posição na lista de unidades)
		for i in mills.size():
			for index in player_data["lumber_mills"][i]["workers"]:
				var worker := player.units[int(index)]
				worker.working_mill = mills[i]
				mills[i].workers.append(worker)
			mills[i].queue_redraw()
		for city_data: Dictionary in player_data["cities"]:
			var city := City.new()
			city.setup(city_data["name"], player, SaveGame.json_to_cell(city_data["cell"]), game_map)
			city.apply_dict(city_data)
			cities_root.add_child(city)
			player.cities.append(city)
	TurnManager.restore(players, data["turn_manager"])
	var current := TurnManager.current_player()
	print("Partida carregada: turno %d, vez do %s" % [TurnManager.turn_number, current.display_name])
	hud.set_turn(TurnManager.turn_number, current)
	if current.is_ai:
		_play_ai_turn(current)
	else:
		_start_human_turn(current, false)


# --- Montagem da partida e HUD ----------------------------------------------

func _spawn_example_units() -> void:
	# Com tropas: os dois jogadores frente a frente no centro da ilha, a 3 casas
	# de distância, para entrarem em combate logo nos primeiros turnos.
	if WITH_TROOPS:
		_spawn_unit(WARRIOR, players[0], Vector2i(58, 40))
		_spawn_unit(ARCHER, players[0], Vector2i(58, 42))
		_spawn_unit(HORSEMAN, players[0], Vector2i(57, 41))
		_spawn_unit(WARRIOR, players[1], Vector2i(61, 40))
		_spawn_unit(ARCHER, players[1], Vector2i(61, 42))
		_spawn_unit(HORSEMAN, players[1], Vector2i(62, 41))
	# Todo jogador começa com um Colono
	_spawn_unit(SETTLER, players[0], Vector2i(55, 41))
	_spawn_unit(SETTLER, players[1], Vector2i(64, 41))


func _next_city_name() -> String:
	var used := cities().map(func(city: City) -> String: return city.city_name)
	for city_name in City.NAMES:
		if not used.has(city_name):
			return city_name
	return "Cidade %d" % (used.size() + 1)


## Botões de ação da unidade (ou madeireira) selecionada, só para o jogador
## humano da vez.
func _update_unit_actions() -> void:
	if _selected_mill:
		_update_mill_actions(_selected_mill)
		return
	var unit := selected_unit
	if unit == null or unit.owner_player.is_ai or unit.owner_player != TurnManager.current_player():
		hud.set_unit_actions("", [])
		return
	var actions: Array[Dictionary] = []
	if unit.type.can_found_city:
		var error := city_site_error(unit)
		actions.append({"id": "found_city", "label": "Construir nova cidade [B]",
				"disabled": not error.is_empty(), "tooltip": error})
	if unit.type.can_build_lumber_mill:
		var error := lumber_mill_error(unit)
		var existing := lumber_mill_at(unit.cell)
		actions.append({"id": "lumber_mill",
				"label": "Trabalhar na madeireira [M]" if existing else "Construir madeireira [M]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"O trabalhador entra na madeireira e trabalha nela (até %d por madeireira)." % LumberMill.MAX_WORKERS if existing else
					"Madeireira nesta floresta (%d de produção, 1 por trabalhador por turno). Pronta, cada trabalhador tira 1 de madeira por turno." % LumberMill.cost()})
	actions.append({"id": "goto", "label": "Mover [G]",
			"tooltip": "Escolha uma casa distante: a unidade anda até lá sozinha, turno após turno."})
	if unit.has_goto():
		actions.append({"id": "cancel_goto", "label": "Cancelar caminhada [Esc]",
				"tooltip": "A unidade para onde está e esquece o destino (%d, %d)." % [unit.goto_target.x, unit.goto_target.y]})
	actions.append({"id": "fortify", "label": "Fortificar [F]", "disabled": unit.fortified,
			"tooltip": ("Já está fortificada." if unit.fortified else
				"+%d de defesa e recupera %d de energia por turno se estiver ferida. Fica assim até se mover ou atacar."
				% [Unit.FORTIFY_DEFENSE_BONUS, Unit.FORTIFY_HEAL])})
	actions.append({"id": "skip", "label": "Pular turno [Espaço]"})
	hud.set_unit_actions("Ações - %s" % unit.type.display_name, actions)


## Barra de ações da madeireira remota selecionada: retirar um trabalhador.
func _update_mill_actions(mill: LumberMill) -> void:
	var title := "Madeireira (%d, %d) - %d/%d trabalhadores" % [mill.cell.x, mill.cell.y, mill.workers.size(), LumberMill.MAX_WORKERS]
	hud.set_unit_actions(title, [{"id": "release_worker", "label": "Retirar trabalhador",
			"disabled": mill.workers.is_empty(),
			"tooltip": "Nenhum trabalhador na madeireira." if mill.workers.is_empty() else
				"O trabalhador sai da madeireira, volta ao mapa e fica selecionado."}])


func _spawn_unit(type: UnitType, player: Player, cell: Vector2i) -> void:
	if not game_map.is_in_bounds(cell) or not Terrain.is_walkable(game_map.get_terrain(cell)):
		push_warning("Unidade %s não criada: casa %s não é terra." % [type.display_name, cell])
		return
	var unit := Unit.new()
	unit.setup(type, player, cell, game_map)
	unit.position = game_map.cell_to_world(cell)
	unit.name = "%s_%s_%d" % [type.display_name, player.id, player.units.size() + 1]
	units_root.add_child(unit)
	player.units.append(unit)


func _show_damage(unit: Unit, amount: int, delay := 0.0) -> void:
	var top := unit.position - Vector2(0, GameMap.TILE_SIZE / 2.0)
	FloatingText.spawn(units_root, top, "-%d" % amount, Color(1, 0.35, 0.3), delay)


## Painel inferior: casa sob o mouse e a unidade nela (ou a selecionada).
func _update_info() -> void:
	var lines: Array[String] = []
	var unit := selected_unit
	if game_map.is_in_bounds(_hover_cell):
		lines.append("Casa (%d, %d): %s" % [_hover_cell.x, _hover_cell.y, _terrain_text(_hover_cell)])
		var city := get_city_at(_hover_cell)
		var mill := lumber_mill_at(_hover_cell)
		if city:
			lines.append("Cidade %s (%s) - População %d | Alimentos %d/%d (%+d por turno)" % [
				city.city_name, city.owner_player.display_name, city.population,
				city.food_stock, city.food_capacity(), city.food_per_turn(),
			])
		elif claiming_city(_hover_cell):
			lines.append(_city_improvement_text(claiming_city(_hover_cell), _hover_cell))
		elif mill:
			lines.append("Madeireira de %s - %s | %d/%d trabalhadores" % [
				mill.owner_player.display_name,
				"em obra %d/%d" % [mill.progress, mill.cost()] if not mill.is_done() else
					"+%d de madeira por turno" % mill.wood_per_turn(),
				mill.workers.size(), LumberMill.MAX_WORKERS,
			])
		var hovered := get_unit_at(_hover_cell)
		if hovered:
			unit = hovered
	if unit:
		var defense_notes: Array[String] = []
		if unit.fortified:
			defense_notes.append("fortificada")
		if unit.terrain_defense_bonus() > 0:
			defense_notes.append("+%d %s" % [unit.terrain_defense_bonus(), Terrain.NAMES[game_map.get_terrain(unit.cell)].to_lower()])
		lines.append("%s (%s) - Ataque %d | Defesa %d%s | Movimento %d/%d | Energia %d/%d" % [
			unit.type.display_name, unit.owner_player.display_name,
			unit.attack, unit.defense, " (%s)" % ", ".join(defense_notes) if not defense_notes.is_empty() else "",
			unit.moves_left, unit.movement, unit.energy, unit.max_energy,
		])
		if unit.has_goto():
			lines[-1] += " | Indo para (%d, %d)" % [unit.goto_target.x, unit.goto_target.y]
	if selected_unit and _attack_targets.has(_hover_cell):
		var defender := get_unit_at(_hover_cell)
		var expected := Combat.expected_damage(selected_unit, defender)
		lines.append("Atacar: %s (força %.2f) x %s (força %.2f) - dano estimado: causa ~%d | recebe ~%d" % [
			selected_unit.type.display_name, Combat.attack_strength(selected_unit, defender),
			defender.type.display_name, Combat.defense_strength(selected_unit, defender),
			roundi(expected["to_defender"]), roundi(expected["to_attacker"]),
		])
	hud.set_info("\n".join(lines))


## Nome do terreno com as regras dele (madeira que resta, defesa, movimento).
func _terrain_text(cell: Vector2i) -> String:
	var type := game_map.get_terrain(cell)
	var text: String = Terrain.NAMES[type]
	if type == Terrain.Type.FOREST:
		text += " (madeira %d/%d, defesa +%d, movimento -%d para quem anda mais de 1)" % [
			game_map.wood_left(cell), Terrain.WOOD_PER_FOREST, Terrain.DEFENSE_BONUS[type], Terrain.MOVE_PENALTY[type]]
	return text


## Fazenda, madeireira ou obra da cidade na casa.
func _city_improvement_text(city: City, cell: Vector2i) -> String:
	var construction := city.construction_at(cell)
	if construction:
		return "%s de %s (em obra %d/%d)" % [construction.display_name(), city.city_name, construction.progress, construction.cost()]
	if city.lumber_mills.has(cell):
		return "Madeireira de %s - %d/%d trabalhadores" % [city.city_name, city.lumber_mills[cell], LumberMill.MAX_WORKERS]
	return "Fazenda de %s - %s" % [city.city_name,
			"+%d alimento" % city.farm_food(cell) if city.farms[cell] > 0 else "sem trabalhador"]


## Painéis do topo (jogador humano): arsenal, ouro e madeira com o saldo por turno.
func _update_resources() -> void:
	var player := TurnManager.current_player() if not TurnManager.current_player().is_ai else null
	for other in players:
		if player == null and not other.is_ai:
			player = other
	if player:
		hud.set_resources(player.gold, player.gold_per_turn(), player.wood, player.wood_per_turn())
		var in_production := {}
		for weapon: Arsenal.Weapon in Arsenal.NAMES:
			in_production[weapon] = player.weapons_in_production(weapon)
		hud.set_arsenal(player.arsenal, in_production)
