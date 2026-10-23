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

## Pilhagem (tecla P): custo em movimentos, energia que a unidade recupera ao
## pilhar uma fazenda e ouro que o jogador ganha ao pilhar uma madeireira.
const PILLAGE_COST := 1
const PILLAGE_FARM_ENERGY := 30
const PILLAGE_MILL_GOLD := 5
## Pontos de reconstrução que um Trabalhador faz por turno numa ruína da cidade
## (a melhoria custa City.BUILDS[...]["cost"]: 4 turnos, como uma obra nova).
const REBUILD_PER_TURN := 1

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
## Tecnologia que o humano terminou de pesquisar neste início de turno (-1 =
## nenhuma): depois dos avisos, a janela pede a próxima pesquisa.
var _research_done := -1
## Dono de cada casa de território: {casa: City} (ver refresh_territories).
var _territory := {}
## Construções concluídas nas cidades do humano neste início de turno, à espera
## do aviso: [[City, City.Build], ...].
var _completion_notices: Array[Array] = []

@onready var game_map: GameMap = $GameMap
@onready var move_overlay: MoveOverlay = $MoveOverlay
@onready var territory_overlay: TerritoryOverlay = $TerritoryOverlay
@onready var ruins_layer: RuinsLayer = $Ruins
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
	hud.research_pressed.connect(_on_research_pressed)
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
	if (hud.city_window.visible or hud.city_name_dialog.visible or hud.notice_dialog.visible
			or hud.save_dialog.visible or hud.invasion_dialog.visible or hud.research_dialog.visible
			or hud.tech_dialog.visible):
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
			_end_human_turn()
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
			KEY_P:
				_pillage_with_selected()
			KEY_R:
				_rebuild_with_selected()
			KEY_J:
				_join_city_with_selected()
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


## Cidade de cujo território a casa faz parte (ou null: terra sem dono).
func territory_owner(cell: Vector2i) -> City:
	return _territory.get(cell)


## Recalcula o dono de cada casa a partir dos territórios das cidades e
## redesenha as fronteiras.
func refresh_territories() -> void:
	_territory = {}
	game_map.city_owners = {}
	for city in cities():
		game_map.city_owners[city.cell] = city.owner_player
		for cell in city.territory:
			_territory[cell] = city
	territory_overlay.set_territories(_territory)


## Território inicial da cidade (City.territory_offsets: 21 casas na capital,
## 9 nas outras), sem as casas que já são de outra cidade nem as que têm a
## madeireira remota de outro jogador: quem chegou primeiro fica com a casa.
func _claim_territory(city: City) -> void:
	city.territory.clear()
	for offset in City.territory_offsets(city.is_capital):
		var cell := city.cell + offset
		var mill := lumber_mill_at(cell)
		var owner_city := territory_owner(cell)
		if (game_map.is_in_bounds(cell) and (owner_city == null or owner_city == city)
				and (mill == null or mill.owner_player == city.owner_player)):
			city.territory.append(cell)
			# Ruína sem dono (de uma cidade destruída) passa a ser desta cidade
			if ruins_layer.improvements.has(cell):
				city.ruins[cell] = ruins_layer.improvements[cell]
				ruins_layer.improvements.erase(cell)
	ruins_layer.cities.erase(city.cell) # fundar em cima das ruínas de uma cidade as apaga
	ruins_layer.queue_redraw()


## Motivo pelo qual a casa não pode passar para [param city] ("" = pode): ela
## precisa estar no raio de ação da cidade (City.territory_offsets: 9 casas no
## povoado, 21 na capital) e ser território de outra cidade do mesmo jogador
## (menos a casa dessa outra cidade).
func transfer_error(city: City, cell: Vector2i) -> String:
	var current := territory_owner(cell)
	if current == city:
		return "A casa já é de %s." % city.city_name
	if current == null:
		return "A casa não é território de nenhuma cidade."
	if current.owner_player != city.owner_player:
		return "A casa é território de outro jogador."
	if current.cell == cell:
		return "É a casa de %s." % current.city_name
	if not City.territory_offsets(city.is_capital).has(cell - city.cell):
		return "Fora do raio de ação de %s." % city.city_name
	return ""


## A casa passa do território de outra cidade do jogador para [param city]
## (use transfer_error antes). A melhoria vem junto, de graça e sem
## trabalhador; quem trabalhava nela fica livre na cidade antiga. Retorna a
## cidade antiga.
func transfer_cell(city: City, cell: Vector2i) -> City:
	var previous := territory_owner(cell)
	city.receive_cell(cell, previous.give_up_cell(cell))
	refresh_territories()
	print("%s: casa (%d, %d) passou de %s para %s" % [city.owner_player.display_name, cell.x, cell.y,
			previous.city_name, city.city_name])
	return previous


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
	if ruins_layer.improvements.has(unit.cell):
		return "Esta casa tem uma melhoria em ruínas."
	if territory_owner(unit.cell):
		return "Esta casa é território de %s." % territory_owner(unit.cell).city_name
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
		if mill.pillaged:
			return "A madeireira foi destruída: use Reconstruir [R]."
		if not mill.has_room():
			return "A madeireira já tem %d trabalhadores (o máximo)." % LumberMill.MAX_WORKERS
		return ""
	if game_map.get_terrain(unit.cell) != Terrain.Type.FOREST:
		return "Madeireiras só podem ser construídas na floresta."
	if claiming_city(unit.cell):
		return "Esta casa já é usada por %s." % claiming_city(unit.cell).city_name
	var owner_city := territory_owner(unit.cell)
	if owner_city and owner_city.owner_player != unit.owner_player:
		return "Esta casa é território de %s (%s)." % [owner_city.city_name, owner_city.owner_player.display_name]
	return ""


## O que dá para pilhar na casa: {"build": City.Build.FARM ou LUMBER_MILL,
## "owner": Player, "city": City ou null, "mill": LumberMill ou null,
## "unfinished": bool}, ou {} se não houver nada. Contam as fazendas e
## madeireiras prontas e também a madeireira remota em obra ou em
## reconstrução (unfinished; senão os Trabalhadores lá dentro ficariam
## intocáveis). Ruína parada e obras da cidade não contam.
func pillage_target(cell: Vector2i) -> Dictionary:
	var city := claiming_city(cell)
	if city and city.improvement_at(cell) >= 0:
		return {"build": city.improvement_at(cell), "owner": city.owner_player, "city": city, "mill": null, "unfinished": false}
	var mill := lumber_mill_at(cell)
	if mill and (mill.is_done() or not mill.workers.is_empty() or mill.progress > 0 or not mill.pillaged):
		return {"build": City.Build.LUMBER_MILL, "owner": mill.owner_player, "city": null, "mill": mill,
				"unfinished": not mill.is_done()}
	return {}


## Se a casa tem uma melhoria que [param player] pode pilhar: pronta, de outro
## jogador e fora do território dele.
func is_pillageable_by(player: Player, cell: Vector2i) -> bool:
	var target := pillage_target(cell)
	var owner_city := territory_owner(cell)
	return not target.is_empty() and target["owner"] != player and (owner_city == null or owner_city.owner_player != player)


## Motivo pelo qual a unidade não pode pilhar a casa em que está ("" = pode).
func pillage_error(unit: Unit) -> String:
	if unit.attack <= 0:
		return "Só unidades militares pilham."
	var target := pillage_target(unit.cell)
	if target.is_empty():
		var city := claiming_city(unit.cell)
		var mill := lumber_mill_at(unit.cell)
		if (city and city.ruins.has(unit.cell)) or (mill and mill.pillaged):
			return "Esta melhoria já foi destruída."
		return "Não há fazenda nem madeireira nesta casa."
	if target["owner"] == unit.owner_player:
		return "Não dá para pilhar as próprias melhorias."
	if not is_pillageable_by(unit.owner_player, unit.cell):
		return "Não dá para pilhar no próprio território."
	if unit.moves_left < PILLAGE_COST:
		return "A unidade não tem mais movimentos neste turno."
	return ""


## A unidade militar destrói a fazenda ou madeireira inimiga da casa em que
## está (use pillage_error antes). Custa PILLAGE_COST movimento.
##   fazenda    : a unidade recupera PILLAGE_FARM_ENERGY de energia;
##   madeireira : o jogador ganha PILLAGE_MILL_GOLD de ouro.
## Da cidade: os cidadãos que trabalhavam ali são executados (a população
## pode chegar a 0). Remota: os Trabalhadores lá dentro são executados. A
## melhoria vira ruína, que um Trabalhador do dono pode reconstruir.
## Madeireira remota inacabada (unfinished): não dá recompensa; a obra nova
## some, e a reconstrução de uma ruína volta a 0.
## Retorna a mensagem do que aconteceu.
func pillage(unit: Unit) -> String:
	var target := pillage_target(unit.cell)
	var player := unit.owner_player
	var build: int = target["build"]
	unit.spend_moves(PILLAGE_COST)
	unit.fortified = false
	unit.goto_target = Unit.NO_TARGET
	var top := unit.position - Vector2(0, GameMap.TILE_SIZE / 2.0)
	var reward := ""
	if target["unfinished"]:
		reward = "obra destruída, sem nada para saquear"
	elif build == City.Build.FARM:
		var healed := mini(PILLAGE_FARM_ENERGY, unit.max_energy - unit.energy)
		unit.energy += healed
		reward = "+%d de energia" % healed if healed > 0 else "energia já estava cheia"
		if healed > 0:
			FloatingText.spawn(units_root, top, "+%d" % healed, Color(0.4, 1, 0.4))
	else:
		player.gold += PILLAGE_MILL_GOLD
		reward = "+%d de ouro" % PILLAGE_MILL_GOLD
		FloatingText.spawn(units_root, top, "+%d" % PILLAGE_MILL_GOLD, Icons.GOLD_COLOR)
	var executed := 0
	var victim := ""
	if target["city"]:
		var city: City = target["city"]
		executed = city.pillage(unit.cell)
		victim = city.city_name
	else:
		var mill: LumberMill = target["mill"]
		executed = mill.workers.size()
		for worker in mill.workers:
			worker.owner_player.units.erase(worker)
			worker.queue_free()
		mill.workers.clear()
		if target["unfinished"] and not mill.pillaged:
			_remove_lumber_mill(mill) # obra nova: não havia nada construído
		else:
			mill.pillage()
		victim = target["owner"].display_name
	var text := "%s (%s) pilhou a %s de %s (%s)." % [unit.type.display_name, player.display_name,
			String(City.BUILDS[build]["name"]).to_lower(), victim, reward]
	if executed > 0:
		text += " %d %s." % [executed, ("trabalhador executado" if executed == 1 else "trabalhadores executados") if target["mill"]
				else ("cidadão executado" if executed == 1 else "cidadãos executados")]
	print(text)
	if target["mill"]:
		_check_victory() # o dono pode ter perdido as últimas unidades
	return text


## Ruína na casa (fazenda ou madeireira pilhada), ou -1.
func ruin_at(cell: Vector2i) -> int:
	var city := claiming_city(cell)
	if city and city.ruins.has(cell):
		return city.ruins[cell]["build"]
	var mill := lumber_mill_at(cell)
	if mill and mill.pillaged:
		return City.Build.LUMBER_MILL
	return -1


## Motivo pelo qual o trabalhador não pode reconstruir a ruína da casa em que
## está ("" = pode).
func rebuild_error(unit: Unit) -> String:
	if not unit.type.can_rebuild:
		return "Só trabalhadores reconstroem."
	if unit.rebuilding:
		return "Já está reconstruindo."
	var city := claiming_city(unit.cell)
	var mill := lumber_mill_at(unit.cell)
	if mill and mill.pillaged:
		if mill.owner_player != unit.owner_player:
			return "Esta madeireira é de outro jogador."
		if not mill.has_room():
			return "A madeireira já tem %d trabalhadores (o máximo)." % LumberMill.MAX_WORKERS
	elif city and city.ruins.has(unit.cell):
		if city.owner_player != unit.owner_player:
			return "Esta ruína é de %s." % city.city_name
	else:
		return "Não há fazenda nem madeireira destruída nesta casa."
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	return ""


## O trabalhador começa a reconstruir a ruína da casa (use rebuild_error
## antes). Madeireira remota: ele entra nela, como numa obra nova. Ruína da
## cidade: ele fica na casa e faz REBUILD_PER_TURN por turno até terminar
## (_process_rebuilds); mover a unidade interrompe (o progresso fica).
func rebuild(unit: Unit) -> void:
	var mill := lumber_mill_at(unit.cell)
	if mill and mill.pillaged:
		work_lumber_mill(unit)
		return
	if unit == selected_unit:
		select_unit(null)
	unit.goto_target = Unit.NO_TARGET
	unit.fortified = false
	unit.rebuilding = true
	unit.skip_turn()


## Cidade do dono para onde a unidade pode migrar: a da casa em que ela está ou
## uma vizinha (a de menor população). null se não houver.
func join_target(unit: Unit) -> City:
	var best: City = null
	for city in unit.owner_player.cities:
		if city.cell == unit.cell:
			return city
		if maxi(absi(city.cell.x - unit.cell.x), absi(city.cell.y - unit.cell.y)) <= 1 \
				and (best == null or city.population < best.population):
			best = city
	return best


## Motivo pelo qual a unidade não pode migrar para uma cidade ("" = pode).
func join_city_error(unit: Unit) -> String:
	if not unit.type.can_join_city:
		return "Só trabalhadores migram para cidades."
	if join_target(unit) == null:
		return "Fique numa cidade sua ou numa casa vizinha a ela para migrar."
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	return ""


## A unidade migra para a cidade (use join_city_error antes): vira 1 de
## população dela e deixa de existir. É assim que uma cidade vazia (população
## 0, depois de uma pilhagem) volta a viver. Retorna a cidade.
func join_city(unit: Unit) -> City:
	var city := join_target(unit)
	city.add_citizen()
	if unit == selected_unit:
		select_unit(null)
	unit.owner_player.units.erase(unit)
	unit.queue_free()
	print("%s migrou para %s (população %d)" % [unit.type.display_name, city.city_name, city.population])
	return city


# --- Invasão e conquista -------------------------------------------------------

## Ouro do saque de [param city]: a fatia do tesouro do dono igual à fatia da
## população do império que mora nela. Ex.: 200 de ouro e duas cidades de 10
## -> 100. Cidade vazia não rende nada.
func loot_amount(city: City) -> int:
	var owner_player := city.owner_player
	var total := 0
	for other in owner_player.cities:
		total += other.population
	if total <= 0:
		return 0
	return owner_player.gold * city.population / total


## Depois de um movimento ou ataque: se uma unidade militar entrou numa cidade
## inimiga (a guarnição, se havia, já foi derrotada), o dono escolhe entre
## ocupar e saquear e destruir. O humano escolhe na InvasionDialog; a máquina
## decide sozinha (AIController.wants_to_raze).
func check_invasion(unit: Unit) -> void:
	if game_over or not is_instance_valid(unit) or unit.attack <= 0:
		return
	var city := get_city_at(unit.cell)
	if city == null or city.owner_player == unit.owner_player:
		return
	var raze := false
	if unit.owner_player.is_ai:
		raze = AIController.wants_to_raze(unit.owner_player, city)
	else:
		camera.pan_to(city.position)
		camera.locked = true
		hud.invasion_dialog.open("Invasão de %s" % city.city_name,
				"A cidade passa a ser sua, com o território, as fazendas, as madeireiras e os prédios.\nEla perde 1 de população e tudo o que estava em produção.",
				_raze_tooltip(city))
		raze = await hud.invasion_dialog.chosen
		camera.locked = false
	var text := raze_city(city, unit.owner_player) if raze else occupy_city(city, unit.owner_player)
	hud.show_message(text, Color(1, 0.75, 0.45))


## Tooltip do botão "Saquear e destruir": o ouro do saque e de onde ele vem.
func _raze_tooltip(city: City) -> String:
	var owner_player := city.owner_player
	return "Você leva %d de ouro (%d de %d de população do império, sobre %d de ouro do tesouro).\nA cidade vira ruínas." % [
		loot_amount(city), city.population,
		owner_player.cities.reduce(func(total: int, other: City) -> int: return total + other.population, 0),
		owner_player.gold]


## A cidade passa a ser de [param new_owner], com o território (ver
## City.change_owner). Se era a capital do perdedor, a maior cidade que sobrou
## para ele vira a capital; para o novo dono, ela só é capital se for a
## primeira cidade dele. Retorna a mensagem.
func occupy_city(city: City, new_owner: Player) -> String:
	var old_owner := city.owner_player
	old_owner.cities.erase(city)
	var was_capital := city.is_capital
	city.is_capital = new_owner.cities.is_empty()
	new_owner.cities.append(city)
	city.change_owner(new_owner)
	if was_capital:
		_reassign_capital(old_owner)
	refresh_territories()
	var text := "%s ocupou %s, de %s (população %d)." % [new_owner.display_name, city.city_name, old_owner.display_name, city.population]
	print(text)
	_check_victory()
	return text


## Saqueia e destrói a cidade: o ouro do saque (loot_amount) sai do tesouro do
## dono e vai para [param raider]. A casa vira as ruínas da cidade, o território
## vira terra sem dono e as fazendas e madeireiras viram ruínas sem dono
## (RuinsLayer). Obras em andamento se perdem. Retorna a mensagem.
func raze_city(city: City, raider: Player) -> String:
	var old_owner := city.owner_player
	var loot := loot_amount(city)
	old_owner.gold -= loot
	raider.gold += loot
	for cell: Vector2i in city.farms:
		ruins_layer.improvements[cell] = {"build": City.Build.FARM, "progress": 0}
	for cell: Vector2i in city.lumber_mills:
		ruins_layer.improvements[cell] = {"build": City.Build.LUMBER_MILL, "progress": 0}
	for cell: Vector2i in city.ruins:
		ruins_layer.improvements[cell] = city.ruins[cell]
	ruins_layer.add_city(city.cell, city.city_name, city.rank())
	ruins_layer.queue_redraw()
	# Apaga as fazendas pintadas no mapa antes de a cidade sumir
	city.farms.clear()
	city.lumber_mills.clear()
	city.ruins.clear()
	city.constructions.clear()
	city._notify_changed()
	old_owner.cities.erase(city)
	cities_root.remove_child(city)
	city.queue_free()
	if city.is_capital:
		_reassign_capital(old_owner)
	refresh_territories()
	FloatingText.spawn(units_root, city.position - Vector2(0, GameMap.TILE_SIZE / 2.0), "+%d" % loot, Icons.GOLD_COLOR)
	var text := "%s saqueou e destruiu %s, de %s: +%d de ouro." % [raider.display_name, city.city_name, old_owner.display_name, loot]
	print(text)
	_check_victory()
	return text


## O jogador perdeu a capital: a maior cidade que sobrou vira a capital (o
## território dela não muda).
func _reassign_capital(player: Player) -> void:
	if player.cities.is_empty() or player.cities.any(func(city: City) -> bool: return city.is_capital):
		return
	var biggest: City = player.cities[0]
	for city in player.cities:
		if city.population > biggest.population:
			biggest = city
	biggest.is_capital = true
	biggest.queue_redraw()


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
	await check_invasion(unit)


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
		await check_invasion(attacker) # derrotou a guarnição e entrou na cidade
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
	city.is_capital = player.cities.is_empty()
	_claim_territory(city)
	cities_root.add_child(city)
	player.cities.append(city)
	refresh_territories()
	print("%s fundou a cidade %s em %s (%s, território de %d casas)" % [
		player.display_name, city.city_name, city.cell, city.rank_text(), city.territory.size()])
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
		if is_instance_valid(unit) and unit.has_goto() and not game_over:
			await camera.pan_to(unit.position, 0.15)
			if is_instance_valid(unit): # um save pode ter sido carregado durante a câmera
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
		"pillage":
			_pillage_with_selected()
		"rebuild":
			_rebuild_with_selected()
		"join_city":
			_join_city_with_selected()


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


## Tecla P / botão "Pilhar": a unidade militar selecionada destrói a fazenda ou
## madeireira inimiga da casa em que está.
func _pillage_with_selected() -> void:
	var unit := selected_unit
	if unit == null or unit.attack <= 0:
		return
	var error := pillage_error(unit)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	hud.show_message(pillage(unit), Color(1, 0.75, 0.45))
	if game_over:
		return
	if can_move(unit):
		select_unit(unit) # ainda tem movimento (ex.: Cavaleiro)
	else:
		_select_next_unit()


## Tecla R / botão "Reconstruir": o trabalhador selecionado começa a
## reconstruir a fazenda ou madeireira destruída da casa em que está.
func _rebuild_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_rebuild:
		return
	var error := rebuild_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	var build := ruin_at(worker.cell)
	rebuild(worker)
	hud.show_message("Trabalhador reconstruindo a %s (%d turnos com 1 trabalhador)." % [
			String(City.BUILDS[build]["name"]).to_lower(), City.BUILDS[build]["cost"]], Color(0.75, 1, 0.75))
	_select_next_unit()


## Tecla J / botão "Migrar": o trabalhador selecionado vira população da cidade
## em que está (ou da vizinha).
func _join_city_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_join_city:
		return
	var error := join_city_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	var city := join_city(worker)
	hud.show_message("Trabalhador migrou para %s (população %d)." % [city.city_name, city.population], Color(0.75, 1, 0.75))
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
		if not unit.fortified and not unit.has_goto() and not unit.rebuilding and can_move(unit):
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
	_process_rebuilds(player)
	_process_research(player)
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
	if _research_done >= 0 and not game_over:
		# Pesquisa concluída no início da vez: escolher a próxima
		var done := _research_done
		_research_done = -1
		hud.tech_dialog.open(done) # nome, ilustração e descrição
		await hud.tech_dialog.closed
		await _choose_research(player, "Pesquisa concluída: %s" % Technology.tech_name(done))
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


## Início da vez do jogador: cada Trabalhador reconstruindo faz
## REBUILD_PER_TURN na ruína da casa em que está. Pronta, a melhoria volta a
## funcionar (sem trabalhador) e o humano recebe o aviso de construção
## concluída. Se a ruína não existe mais, ele para.
func _process_rebuilds(player: Player) -> void:
	var messages: Array[String] = []
	for unit in player.units:
		if not unit.rebuilding:
			continue
		var city := claiming_city(unit.cell)
		if city == null or city.owner_player != player or not city.ruins.has(unit.cell):
			unit.rebuilding = false
			continue
		var build: int = city.ruins[unit.cell]["build"]
		if city.add_rebuild_progress(unit.cell, REBUILD_PER_TURN):
			unit.rebuilding = false
			messages.append("%s: %s reconstruída em (%d, %d)" % [city.city_name, City.BUILDS[build]["name"], unit.cell.x, unit.cell.y])
			if not player.is_ai:
				_completion_notices.append([city, build])
	for message in messages:
		print(message)
	if not player.is_ai and not messages.is_empty():
		hud.show_message("\n".join(messages), Color(0.75, 1, 0.75))


## Início da vez do jogador: a ciência das Prefeituras vai para a pesquisa
## (Player.advance_research). A máquina escolhe sozinha a próxima pesquisa;
## o humano escolhe numa janela depois dos avisos (ver _start_human_turn).
func _process_research(player: Player) -> void:
	if player.is_ai and player.research < 0:
		AIController.choose_research(player)
	var done := player.advance_research()
	if done < 0:
		return
	print("%s pesquisou %s" % [player.display_name, Technology.tech_name(done)])
	if player.is_ai:
		AIController.choose_research(player)
	else:
		_research_done = done
		hud.show_message("Pesquisa concluída: %s!" % Technology.tech_name(done), Icons.SCIENCE_COLOR)


## Enter com o turno terminado: se o jogador já tem cidade e não escolheu uma
## pesquisa, a janela de pesquisa aparece antes (os pontos de ciência se
## perderiam). Depois a vez passa.
func _end_human_turn() -> void:
	var player := TurnManager.current_player()
	if player.research < 0 and not player.cities.is_empty() and not Technology.available(player.researched).is_empty():
		_awaiting_end_turn = false
		await _choose_research(player)
		if game_over or TurnManager.current_player() != player:
			return
	TurnManager.end_turn()


## Janela de pesquisa: o jogador escolhe a próxima tecnologia. Sem pesquisa em
## andamento, não dá para fechar sem escolher.
func _choose_research(player: Player, title := "Escolha uma pesquisa") -> void:
	if Technology.available(player.researched).is_empty():
		return
	camera.locked = true
	hud.research_dialog.open(player, player.research >= 0, title)
	var tech: int = await hud.research_dialog.closed
	camera.locked = false
	if tech >= 0:
		player.research = tech
		hud.show_message("Pesquisando %s (%d pontos de ciência)." % [Technology.tech_name(tech), Technology.cost(tech)], Icons.SCIENCE_COLOR)


## Clique no painel de Ciência do HUD: escolher ou trocar a pesquisa (só na
## vez do humano, sem nada acontecendo).
func _on_research_pressed() -> void:
	var player := TurnManager.current_player()
	if _is_busy or game_over or player.is_ai or hud.city_window.visible or hud.research_dialog.visible:
		return
	await _choose_research(player)
	if _awaiting_end_turn:
		hud.show_end_turn_prompt(true)


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
## tiver unidades ou cidades; vence quem for o último vivo. Cidades se perdem
## por invasão (ocupadas ou destruídas, ver check_invasion).
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
		if player.is_ai:
			data["ai_turns_waiting"] = _ais[player].turns_waiting if _ais.has(player) else 0
		players_data.append(data)
	return {"turn_manager": TurnManager.to_dict(), "map": game_map.to_dict(), "players": players_data,
			"ruins": ruins_layer.to_dict()}


## Troca a partida atual pela de [param data] (de capture_state, já lida do
## arquivo) e continua a vez de quem estava jogando, sem processar o início do
## turno de novo (as cidades já tinham produzido quando o jogo foi salvo).
func restore_state(data: Dictionary) -> void:
	select_unit(null)
	_set_goto_mode(false)
	_completion_notices.clear()
	_research_done = -1
	_awaiting_end_turn = false
	hud.show_end_turn_prompt(false)
	hud.hide_victory()
	game_over = false
	for root: Node in [units_root, cities_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()

	game_map.from_dict(data["map"])
	ruins_layer.from_dict(data.get("ruins", {}))
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
			mill.pillaged = mill_data.get("pillaged", false)
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
	refresh_territories()
	for city in cities():
		if city.territory.is_empty(): # save anterior aos territórios: território inicial
			city.is_capital = city == city.owner_player.cities[0]
			_claim_territory(city)
			refresh_territories()
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
	var existing := lumber_mill_at(unit.cell)
	if unit.type.can_build_lumber_mill and not (existing and existing.pillaged): # destruída: botão Reconstruir
		var error := lumber_mill_error(unit)
		actions.append({"id": "lumber_mill",
				"label": "Trabalhar na madeireira [M]" if existing else "Construir madeireira [M]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"O trabalhador entra na madeireira e trabalha nela (até %d por madeireira)." % LumberMill.MAX_WORKERS if existing else
					"Madeireira nesta floresta (%d de produção, 1 por trabalhador por turno). Pronta, cada trabalhador tira 1 de madeira por turno." % LumberMill.cost()})
	if unit.type.can_rebuild and ruin_at(unit.cell) >= 0:
		var error := rebuild_error(unit)
		var build := ruin_at(unit.cell)
		actions.append({"id": "rebuild", "label": "Reconstruir [R]", "disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"Reconstrói a %s destruída: %d turnos com 1 trabalhador, como uma obra nova." % [
						String(City.BUILDS[build]["name"]).to_lower(), City.BUILDS[build]["cost"]]})
	if unit.type.can_join_city and join_target(unit):
		var error := join_city_error(unit)
		actions.append({"id": "join_city", "label": "Migrar para %s [J]" % join_target(unit).city_name,
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"O trabalhador vira 1 de população da cidade (e deixa de ser uma unidade). Assim uma cidade vazia volta a viver."})
	if unit.attack > 0 and not pillage_target(unit.cell).is_empty():
		var error := pillage_error(unit)
		actions.append({"id": "pillage", "label": "Pilhar [P]", "disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"Destrói a melhoria inimiga (%d movimento). Fazenda: +%d de energia. Madeireira: +%d de ouro. Quem trabalhava nela é executado." % [
						PILLAGE_COST, PILLAGE_FARM_ENERGY, PILLAGE_MILL_GOLD]})
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
		var owner_city := territory_owner(_hover_cell)
		if owner_city:
			lines[-1] += " - território de %s (%s)" % [owner_city.city_name, owner_city.owner_player.display_name]
		var city := get_city_at(_hover_cell)
		var mill := lumber_mill_at(_hover_cell)
		if city:
			lines.append("Cidade %s (%s, %s) - População %d | Alimentos %d/%d (%+d por turno)" % [
				city.city_name, city.owner_player.display_name, city.rank_text(), city.population,
				city.food_stock, city.food_capacity(), city.food_per_turn(),
			])
		elif ruins_layer.cities.has(_hover_cell):
			lines.append("Ruínas de %s (cidade saqueada e destruída)" % ruins_layer.city_name_at(_hover_cell))
		elif ruins_layer.improvements.has(_hover_cell):
			lines.append("%s destruída, sem dono (uma cidade fundada perto fica com ela)" % City.BUILDS[ruins_layer.improvements[_hover_cell]["build"]]["name"])
		elif claiming_city(_hover_cell):
			lines.append(_city_improvement_text(claiming_city(_hover_cell), _hover_cell))
		elif mill:
			lines.append("Madeireira%s de %s - %s | %d/%d trabalhadores" % [
				" destruída" if mill.pillaged else "", mill.owner_player.display_name,
				("reconstrução %d/%d" if mill.pillaged else "em obra %d/%d") % [mill.progress, mill.cost()] if not mill.is_done() else
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
		if unit.rebuilding:
			lines[-1] += " | Reconstruindo"
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
	if city.ruins.has(cell):
		var ruin: Dictionary = city.ruins[cell]
		return "%s destruída de %s - um Trabalhador pode reconstruir (%d/%d)" % [
			City.BUILDS[ruin["build"]]["name"], city.city_name, ruin["progress"], City.BUILDS[ruin["build"]]["cost"]]
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
		hud.set_science(player)
		var in_production := {}
		for weapon: Arsenal.Weapon in Arsenal.NAMES:
			in_production[weapon] = player.weapons_in_production(weapon)
		hud.set_arsenal(player.arsenal, in_production)
