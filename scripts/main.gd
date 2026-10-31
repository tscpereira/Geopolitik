class_name Game
extends Node2D

## Monta a partida de exemplo e executa as ações do jogo (mover, atacar,
## fundar cidade, madeireira remota, encerrar turno). O jogador humano age por
## cliques; o jogador máquina, pelo AIController, usando exatamente as mesmas ações.

## Mapas: data/maps/<nome>.png (um pixel por casa, cores de Terrain.COLORS) e
## <nome>_recursos.json ao lado, com o ferro ("ferro"), os jogadores
## ("jogadores": nome, cor, se é máquina e a casa inicial) e a casa onde a
## câmera começa ("camera"). Ver _load_map.
const MAPS_DIR := "res://data/maps/"
## Mapa da próxima partida (fica entre partidas: "Enter" na vitória começa outra
## no mesmo mapa). Os testes antigos usam "mapa_teste" (a ilha de 2 jogadores).
static var map_name := "tres_continentes"
## Save de outro mapa à espera: o jogo recarrega a cena com o mapa dele e então
## o carrega (ver restore_state).
static var _pending_load := {}
## Começa com todos se conhecendo e em guerra (como era antes da diplomacia; os
## testes antigos usam).
static var start_at_war := false
## Mostra a tela de início (nação e cor) antes de uma partida nova. Os testes
## desligam: os jogadores vêm do JSON do mapa, como antes.
static var show_start_screen := true
const WARRIOR: UnitType = preload("res://data/units/guerreiro.tres")
const ARCHER: UnitType = preload("res://data/units/arqueiro.tres")
const LIGHT_CAVALRY: UnitType = preload("res://data/units/cavalaria_leve.tres")
## Tipos de unidade que saíram do jogo: o save antigo carrega o substituto.
## (O Cavaleiro virou a Cavalaria Leve em 25/10/2026.)
const REPLACED_UNIT_TYPES := {
	"res://data/units/cavaleiro.tres": "res://data/units/cavalaria_leve.tres",
}
const SETTLER: UnitType = preload("res://data/units/colono.tres")
const WORKER: UnitType = preload("res://data/units/trabalhador.tres")
## Cursor do modo "Mover" (tecla G). Ponta da seta no canto superior esquerdo.
const GO_CURSOR: Texture2D = preload("res://assets/sprites/ui/cursor_go.png")

## Partida de teste com as tropas (Guerreiro, Arqueiro e Cavalaria Leve) de cada lado.
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
## Aviso de início de turno (no lugar de um City.Build): a cidade entrou em
## desordem civil.
const DISORDER_NOTICE := -1

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
## do aviso: [[City, City.Build], ...] (DISORDER_NOTICE: entrou em desordem).
var _completion_notices: Array[Array] = []
## Trabalhadores do humano que terminaram uma melhoria no início da vez: em vez
## do aviso de construção concluída, o primeiro deles é selecionado (com a câmera).
var _finished_workers: Array[Unit] = []

@onready var game_map: GameMap = $GameMap
@onready var move_overlay: MoveOverlay = $MoveOverlay
@onready var territory_overlay: TerritoryOverlay = $TerritoryOverlay
@onready var ruins_layer: RuinsLayer = $Ruins
@onready var cities_root: Node2D = $Cities
@onready var units_root: Node2D = $Units
@onready var camera: MapCamera = $MapCamera
@onready var hud: Hud = $HUD
## Névoa de guerra (criada em _ready, logo depois das cidades na cena).
var fog: FogOfWar
## Relações entre os jogadores (ver Diplomacy). Também posta em Movement.diplomacy.
var diplomacy: Diplomacy
## Quadros desde a última busca de primeiros encontros (_check_contacts).
var _contact_frames := 0
## Avisos de diplomacia para o humano, um de cada vez: [{title, text,
## buttons, callback}] (ver _queue_diplomacy_notice).
var _diplomacy_queue: Array = []
## Audiências de primeiro encontro aceitas na vez da máquina: abrem no começo
## da vez do humano (_offer_audience).
var _pending_audiences: Array[Player] = []
## A partida já começou (depois da tela de início): até lá, _process e a
## entrada não fazem nada.
var _started := false


func _ready() -> void:
	_rng.randomize()
	var map_info := _load_map(map_name)
	camera.set_bounds(game_map.get_pixel_size())
	var camera_cell: Array = map_info.get("camera", [game_map.width / 2, game_map.height / 2])
	camera.position = game_map.cell_to_world(Vector2i(int(camera_cell[0]), int(camera_cell[1])))
	fog = FogOfWar.new()
	fog.name = "Fog"
	fog.setup(game_map)
	add_child(fog)
	move_child(fog, cities_root.get_index() + 1)

	# Partida nova: a tela de início (nação e cor). Save de outro mapa à espera
	# e testes: sem ela
	var choice := {}
	if show_start_screen and _pending_load.is_empty():
		var screen := StartScreen.new()
		screen.name = "StartScreen"
		hud.add_child(screen)
		choice = await screen.chosen
		screen.queue_free()
	_create_players(map_info["jogadores"], choice)
	var starts: Array[Vector2i] = []
	for entry: Dictionary in map_info["jogadores"]:
		starts.append(Vector2i(int(entry["inicio"][0]), int(entry["inicio"][1])))
	_spawn_starting_units(starts)
	if not choice.is_empty():
		camera.position = game_map.cell_to_world(starts[0])
	diplomacy = Diplomacy.new()
	Movement.diplomacy = diplomacy
	if start_at_war:
		for i in players.size():
			for j in range(i + 1, players.size()):
				diplomacy.meet(players[i], players[j])
				diplomacy.set_state(players[i], players[j], Diplomacy.State.WAR)

	hud.action_pressed.connect(_on_unit_action)
	hud.research_pressed.connect(_on_research_pressed)
	hud.tech_tree_pressed.connect(_open_tech_tree)
	hud.menu_opening.connect(func() -> void: hud.set_save_enabled(_can_save()))
	hud.menu_chosen.connect(_on_game_menu)
	hud.diplomacy_pressed.connect(func() -> void: hud.diplomacy_dialog.open(self))
	hud.diplomacy_dialog.meeting_requested.connect(request_meeting)
	hud.meeting_dialog.war_declared.connect(request_declare_war)
	hud.meeting_dialog.peace_proposed.connect(request_peace)
	# Encontro aberto: foco total (a câmera não anda com o teclado por trás)
	hud.meeting_dialog.visibility_changed.connect(func() -> void: camera.locked = hud.meeting_dialog.visible)
	Unit.watch = is_watched
	hud.tech_tree_dialog.research_chosen.connect(_on_tree_research_chosen)
	hud.city_window.closed.connect(_on_city_window_closed)
	hud.minimap.setup(self)
	_update_vision()
	TurnManager.turn_started.connect(_on_turn_started)
	_started = true
	TurnManager.start_game(players)
	if not _pending_load.is_empty():
		var data := _pending_load
		_pending_load = {}
		restore_state(data)


## Jogadores da partida, um por casa inicial do mapa ([param entries], do
## JSON). Com a escolha da tela de início ([param choice]: "nation" e "color"),
## o primeiro é o humano, com a nação e a cor escolhidas, e os outros são
## máquinas com as outras nações (sorteadas; mais casas que nações: elas se
## repetem), cada uma com a cor dela ou, se já usada, a próxima livre de
## Nation.COLORS, e o estilo de jogo da nação. Sem escolha (testes, mapas
## antigos): nome, cor e máquina do JSON, sem nação.
func _create_players(entries: Array, choice: Dictionary) -> void:
	players = []
	if choice.is_empty():
		for entry: Dictionary in entries:
			players.append(Player.new(players.size() + 1, entry["nome"], Color.html(entry["cor"]), entry.get("maquina", true)))
		return
	var others: Array = Nation.Id.values()
	others.erase(choice["nation"])
	for i in range(others.size() - 1, 0, -1): # sorteio das nações das máquinas
		var j := _rng.randi_range(0, i)
		var swap: int = others[i]
		others[i] = others[j]
		others[j] = swap
	var used_colors: Array[Color] = [choice["color"]]
	for i in entries.size():
		var nation: int = choice["nation"] if i == 0 else others[(i - 1) % others.size()]
		var color: Color = choice["color"]
		if i > 0:
			color = Nation.DATA[nation]["color"]
			if used_colors.has(color):
				for free in Nation.COLORS:
					if not used_colors.has(free):
						color = free
						break
			used_colors.append(color)
		var player := Player.new(i + 1, Nation.name_of(nation), color, i > 0)
		player.nation = nation
		if i > 0:
			player.personality = Nation.personality(nation)
		players.append(player)


## Monta o mapa [param name] (PNG + JSON de recursos, ver MAPS_DIR) e retorna o
## JSON (jogadores e câmera). Mapa sem a lista de jogadores: dois, um em cada
## terço do mapa (só para não quebrar).
func _load_map(name: String) -> Dictionary:
	var texture: Texture2D = load(MAPS_DIR + name + ".png")
	game_map.load_from_image(texture.get_image())
	var json_path := MAPS_DIR + name + "_recursos.json"
	game_map.load_resources(json_path)
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path)) if FileAccess.file_exists(json_path) else null
	if not info is Dictionary or not info.has("jogadores"):
		push_warning("O mapa %s não lista os jogadores: dois, no meio do mapa." % name)
		info = {"jogadores": [
			{"nome": "Jogador 1", "cor": "dc2828", "maquina": false, "inicio": [game_map.width / 3, game_map.height / 2]},
			{"nome": "Jogador 2", "cor": "fadc28", "maquina": true, "inicio": [game_map.width * 2 / 3, game_map.height / 2]}]}
	return info

func _process(_delta: float) -> void:
	if not _started:
		return
	_update_vision()
	_contact_frames += 1
	if _contact_frames >= CONTACT_CHECK_FRAMES:
		_contact_frames = 0
		_check_contacts()
	var cell := game_map.world_to_cell(get_global_mouse_position())
	if cell != _hover_cell:
		_hover_cell = cell
		_update_info()
		if _goto_mode:
			_preview_goto(cell)
	_update_resources()


func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	var is_enter: bool = (event is InputEventKey and event.pressed and not event.echo
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER])
	var key: int = event.keycode if event is InputEventKey and event.pressed and not event.echo else KEY_NONE
	if (hud.city_window.visible or hud.city_name_dialog.visible or hud.notice_dialog.visible
			or hud.save_dialog.visible or hud.invasion_dialog.visible or hud.research_dialog.visible
			or hud.tech_dialog.visible or hud.tech_tree_dialog.visible or hud.message_dialog.visible
			or hud.diplomacy_dialog.visible or hud.meeting_dialog.visible):
		return # as janelas cuidam dos próprios cliques e teclas
	# Carregar: L (no editor do Godot o F9 pausa o jogo embutido) ou F9
	if (key == KEY_L or key == KEY_F9) and not _is_busy:
		_open_save_dialog(false) # carregar também vale na tela de vitória
		return
	if game_over:
		if is_enter:
			get_tree().reload_current_scene()
		return
	if _is_busy or TurnManager.current_player().is_ai:
		return
	if key == KEY_F5 and _can_save():
		_open_save_dialog(true)
		return
	if key == KEY_T:
		_open_tech_tree()
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
				_mine_or_lumber_mill_with_selected()
			KEY_C:
				_build_farm_with_selected()
			KEY_E:
				_build_road_with_selected()
			KEY_P:
				_pillage_with_selected()
			KEY_R:
				_rebuild_with_selected()
			KEY_J:
				_join_city_with_selected()
			KEY_U:
				_select_passenger()
			KEY_ESCAPE:
				_on_escape()


# --- Consultas -------------------------------------------------------------

func get_unit_at(cell: Vector2i) -> Unit:
	return occupants().get(cell)


# --- Névoa de guerra (FogOfWar) ------------------------------------------------

## O jogador humano: é a visão dele que a névoa mostra. null se todos são
## máquinas (névoa desligada).
func viewer() -> Player:
	for player in players:
		if not player.is_ai:
			return player
	return null


func player_by_id(id: int) -> Player:
	for player in players:
		if player.id == id:
			return player
	return null


## Recalcula a visão do jogador humano: a névoa, as unidades dos outros que ele
## vê, as cidades dos outros de que ele sabe (Player.seen_cities) e o minimapa.
## Barato quando nada mudou; chamado a cada quadro e antes de selecionar.
func _update_vision() -> void:
	if fog == null:
		return
	var watcher := viewer()
	var changed := fog.update(watcher)
	for player in players:
		for unit in player.units:
			unit.fog_hidden = watcher != null and player != watcher and not fog.is_visible_cell(unit.cell)
	if watcher:
		# O que ele vê agora atualiza a lembrança das cidades dos outros
		for city in cities():
			if city.owner_player != watcher and fog.is_visible_cell(city.cell):
				watcher.seen_cities[city.cell] = city.owner_player.id
		for cell: Vector2i in watcher.seen_cities.keys():
			var there := get_city_at(cell)
			if fog.is_visible_cell(cell) and (there == null or there.owner_player == watcher):
				watcher.seen_cities.erase(cell)
	for city in cities():
		city.visible = watcher == null or city.owner_player == watcher or watcher.seen_cities.has(city.cell)
	if changed:
		hud.minimap.refresh()


## A unidade na casa, se o jogador humano a vê (as dos outros na névoa não).
func visible_unit_at(cell: Vector2i) -> Unit:
	var unit := get_unit_at(cell)
	if unit and unit.owner_player != viewer() and not fog.is_visible_cell(cell):
		return null
	return unit


## A cidade na casa, se o jogador humano sabe dela (as dos outros só depois de vistas).
func known_city_at(cell: Vector2i) -> City:
	var city := get_city_at(cell)
	return city if city and city.visible else null


## {casa: Unit} de todas as unidades no mapa. Trabalhadores dentro de uma
## madeireira remota e unidades embarcadas numa Galé não ocupam a casa.
func occupants() -> Dictionary:
	var result := {}
	for player in players:
		for unit in player.units:
			if unit.working_mill == null and unit.transport == null:
				result[unit.cell] = unit
	return result


## Se a unidade ainda tem alguma ação possível (mover ou atacar) neste turno.
func can_move(unit: Unit) -> bool:
	if unit.moves_left <= 0 or unit.working_mill:
		return false
	var current := occupants()
	var reachable := Movement.find_reachable(game_map, unit, current)
	return (not Movement.destinations(reachable, current, unit).is_empty()
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
	game_map.territory_owners = {}
	game_map.city_owners = {}
	game_map.cities = {}
	for city in cities():
		game_map.city_owners[city.cell] = city.owner_player
		game_map.cities[city.cell] = city
		for cell in city.territory:
			_territory[cell] = city
			game_map.territory_owners[cell] = city.owner_player
	territory_overlay.set_territories(_territory)
	game_map.redraw_roads() # a cidade liga as estradas vizinhas


## Território inicial da cidade (City.territory_offsets: 21 casas na capital,
## 9 nas outras), sem as casas que já são de outra cidade nem as que têm a
## madeireira remota de outro jogador: quem chegou primeiro fica com a casa.
func _claim_territory(city: City) -> void:
	city.territory.clear()
	for offset in City.territory_offsets(city.has_large_territory()):
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
	city.territory_expanded = city.has_large_territory() # a capital já nasce com a área grande
	ruins_layer.cities.erase(city.cell) # fundar em cima das ruínas de uma cidade as apaga
	ruins_layer.queue_redraw()


## A cidade chegou à classe Vila: o território cresce para a área da capital
## (City.territory_offsets(true)), com as casas livres (as de outra cidade e as
## com a madeireira remota de outro jogador ficam de fora, como ao fundar).
## Retorna quantas casas ganhou.
func expand_territory(city: City) -> int:
	city.territory_expanded = true
	var gained := 0
	for offset in City.territory_offsets(true):
		var cell := city.cell + offset
		if city.territory.has(cell) or not game_map.is_in_bounds(cell) or territory_owner(cell) != null:
			continue
		var mill := lumber_mill_at(cell)
		if mill and mill.owner_player != city.owner_player:
			continue
		city.territory.append(cell)
		gained += 1
		if ruins_layer.improvements.has(cell):
			city.ruins[cell] = ruins_layer.improvements[cell]
			ruins_layer.improvements.erase(cell)
	if gained > 0:
		ruins_layer.queue_redraw()
		refresh_territories()
	return gained


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
	if not City.territory_offsets(city.has_large_territory()).has(cell - city.cell):
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
## terreno certo (fazenda em pradaria/cerrado, madeireira em floresta, mina em
## colina com ferro), dentro do mapa e sem cidade, melhoria ou obra (de qualquer
## cidade) nem madeireira remota.
func buildable_cells(city: City, build: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in city.area_cells():
		if (cell != city.cell and game_map.is_in_bounds(cell)
				and City.allows_terrain(build, game_map.get_terrain(cell))
				and (build != City.Build.MINE or game_map.has_iron(cell))
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
## ("" = pode). Melhorias de terreno são feitas por Trabalhadores.
func buy_error(city: City, build: int) -> String:
	var info: Dictionary = City.BUILDS[build]
	if info["on_tile"]:
		return city.build_error(build)
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


## Motivo pelo qual o trabalhador não pode construir (ou continuar) a fazenda,
## madeireira ou mina [param build] da cidade na casa em que está ("" = pode):
## só no território de uma cidade sua, fora da casa dela, no terreno certo (a
## mina, numa colina com ferro) e numa casa sem outra melhoria (a obra parada da
## mesma melhoria pode continuar).
func improvement_error(unit: Unit, build: int) -> String:
	var info: Dictionary = City.BUILDS[build]
	if not (unit.type.can_build_farm if build == City.Build.FARM else unit.type.can_build_lumber_mill):
		return "Só trabalhadores constroem %ss." % String(info["name"]).to_lower()
	if build == City.Build.MINE and not unit.owner_player.researched.has(Technology.Tech.IRON_WORKING):
		return "Minas exigem a tecnologia Trabalho em Ferro."
	if unit.rebuilding:
		return "O trabalhador já está construindo."
	var city := territory_owner(unit.cell)
	if city == null or city.owner_player != unit.owner_player:
		return "%ss só podem ser feitas no território de uma cidade sua." % info["name"]
	if unit.cell == city.cell:
		return "Não dá para construir na casa da cidade."
	if not City.allows_terrain(build, game_map.get_terrain(unit.cell)) \
			or (build == City.Build.MINE and not game_map.has_iron(unit.cell)):
		match build:
			City.Build.FARM:
				return "Fazendas só em pradaria ou cerrado."
			City.Build.MINE:
				return "Minas só em colinas com ferro (a bigorna no canto da casa)."
		return "Madeireiras só na floresta."
	var site: Dictionary = city.sites.get(unit.cell, {})
	if site.is_empty() and (claiming_city(unit.cell) or lumber_mill_at(unit.cell)):
		return "Esta casa já tem uma melhoria."
	if not site.is_empty() and site["build"] != build:
		return "Esta casa já tem uma obra de %s." % String(City.BUILDS[site["build"]]["name"]).to_lower()
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	return ""


## Motivo pelo qual o trabalhador não pode construir (ou continuar) uma estrada
## na casa em que está ("" = pode): exige Engenharia Civil; não na cidade, numa
## casa que já tem estrada, no território de outro jogador nem numa casa com
## obra ou ruína de uma cidade (termine-a antes).
func road_error(unit: Unit) -> String:
	if not unit.type.can_build_lumber_mill:
		return "Só trabalhadores constroem estradas."
	if not unit.owner_player.researched.has(Technology.Tech.CIVIL_ENGINEERING):
		return "Estradas exigem a tecnologia Engenharia Civil."
	if unit.rebuilding:
		return "O trabalhador já está construindo."
	if get_city_at(unit.cell):
		return "A cidade já funciona como estrada."
	if game_map.roads.has(unit.cell):
		return "Esta casa já tem uma estrada."
	var owner_city := territory_owner(unit.cell)
	if owner_city and owner_city.owner_player != unit.owner_player:
		return "Esta casa é território de %s (%s)." % [owner_city.city_name, owner_city.owner_player.display_name]
	var city := claiming_city(unit.cell)
	if city and (city.sites.has(unit.cell) or city.ruins.has(unit.cell)):
		return "Termine primeiro a obra desta casa."
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	return ""


## O trabalhador começa (ou continua) a estrada na casa em que está (use
## road_error antes). Ele fica na casa e faz REBUILD_PER_TURN por turno até
## GameMap.ROAD_COST (_process_rebuilds); mover a unidade interrompe (o
## progresso fica na obra).
func build_road(unit: Unit) -> void:
	game_map.start_road(unit.cell)
	_start_tile_work(unit)


## O trabalhador começa (ou continua) a fazer a fazenda ou madeireira da cidade
## na casa em que está (use improvement_error antes). Ele fica na casa e faz
## REBUILD_PER_TURN por turno até terminar (_process_rebuilds); mover a unidade
## interrompe (o progresso fica na obra).
func build_improvement(unit: Unit, build: int) -> void:
	territory_owner(unit.cell).add_site(build, unit.cell)
	_start_tile_work(unit)


## A madeireira que o trabalhador faz na casa é da cidade? Sim no território de
## uma cidade sua (sem madeireira remota ali); fora dele, é remota.
func is_city_mill_site(unit: Unit) -> bool:
	var city := territory_owner(unit.cell)
	return city != null and city.owner_player == unit.owner_player and lumber_mill_at(unit.cell) == null


## Tecla M: madeireira da cidade (no território) ou remota (fora dele, ou entra
## na remota que já existe ali). Use lumber_mill_error antes.
func build_lumber_mill(worker: Unit) -> void:
	if is_city_mill_site(worker):
		build_improvement(worker, City.Build.LUMBER_MILL)
	else:
		work_lumber_mill(worker)


## Motivo pelo qual o trabalhador não pode construir uma mina onde está, nem
## entrar na mina remota que já existe ali ("" = pode). No território de uma
## cidade sua, a mina é da cidade (improvement_error); fora dos territórios, é
## remota, como a madeireira remota.
func mine_error(unit: Unit) -> String:
	if not unit.type.can_build_lumber_mill:
		return "Só trabalhadores constroem minas."
	if is_city_mill_site(unit):
		return improvement_error(unit, City.Build.MINE)
	if not unit.owner_player.researched.has(Technology.Tech.IRON_WORKING):
		return "Minas exigem a tecnologia Trabalho em Ferro."
	if unit.moves_left <= 0:
		return "O trabalhador não tem mais movimentos neste turno."
	var mine := lumber_mill_at(unit.cell)
	if mine:
		if not mine.is_mine:
			return "Esta casa já tem uma madeireira."
		if mine.owner_player != unit.owner_player:
			return "Esta mina é de outro jogador."
		if mine.pillaged:
			return "A mina foi destruída: use Reconstruir [R]."
		if not mine.has_room():
			return "A mina já tem %d trabalhadores (o máximo)." % LumberMill.MAX_WORKERS
		return ""
	if game_map.get_terrain(unit.cell) != Terrain.Type.HILLS or not game_map.has_iron(unit.cell):
		return "Minas só em colinas com ferro (a bigorna no canto da casa)."
	if claiming_city(unit.cell):
		return "Esta casa já é usada por %s." % claiming_city(unit.cell).city_name
	var owner_city := territory_owner(unit.cell)
	if owner_city and owner_city.owner_player != unit.owner_player:
		return "Esta casa é território de %s (%s)." % [owner_city.city_name, owner_city.owner_player.display_name]
	return ""


## Motivo pelo qual o trabalhador não pode construir uma madeireira onde está,
## nem entrar na que já existe ali ("" = pode). No território de uma cidade
## sua, a madeireira é da cidade (improvement_error).
func lumber_mill_error(unit: Unit) -> String:
	if not unit.type.can_build_lumber_mill:
		return "Só trabalhadores constroem madeireiras."
	if is_city_mill_site(unit):
		return improvement_error(unit, City.Build.LUMBER_MILL)
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
	if not Terrain.has_wood(game_map.get_terrain(unit.cell)):
		return "Madeireiras só podem ser construídas na floresta ou na selva."
	if claiming_city(unit.cell):
		return "Esta casa já é usada por %s." % claiming_city(unit.cell).city_name
	var owner_city := territory_owner(unit.cell)
	if owner_city and owner_city.owner_player != unit.owner_player:
		return "Esta casa é território de %s (%s)." % [owner_city.city_name, owner_city.owner_player.display_name]
	return ""


## O que dá para pilhar na casa: {"build": City.Build.FARM, LUMBER_MILL ou MINE,
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
		return {"build": mill.build(), "owner": mill.owner_player, "city": null, "mill": mill,
				"unfinished": not mill.is_done()}
	return {}


## Se a casa tem uma melhoria que [param player] pode pilhar: pronta, de outro
## jogador e fora do território dele.
func is_pillageable_by(player: Player, cell: Vector2i) -> bool:
	var target := pillage_target(cell)
	var owner_city := territory_owner(cell)
	return (not target.is_empty() and target["owner"] != player and (owner_city == null or owner_city.owner_player != player)
			and Movement.at_war(player, target["owner"]))


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
		return "Não há fazenda, madeireira nem mina nesta casa."
	if target["owner"] == unit.owner_player:
		return "Não dá para pilhar as próprias melhorias."
	if not Movement.at_war(unit.owner_player, target["owner"]):
		return "Só se pilha quem está em guerra com você (veja a Diplomacia)."
	if not is_pillageable_by(unit.owner_player, unit.cell):
		return "Não dá para pilhar no próprio território."
	if unit.moves_left < PILLAGE_COST * Movement.POINTS:
		return "A unidade não tem mais movimentos neste turno."
	return ""


## A unidade militar destrói a fazenda, madeireira ou mina inimiga da casa em
## que está (use pillage_error antes). Custa PILLAGE_COST movimento.
##   fazenda           : a unidade recupera PILLAGE_FARM_ENERGY de energia;
##   madeireira ou mina: o jogador ganha PILLAGE_MILL_GOLD de ouro.
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
	var reward := ""
	if target["unfinished"]:
		reward = "obra destruída, sem nada para saquear"
	elif build == City.Build.FARM:
		var healed := mini(PILLAGE_FARM_ENERGY, unit.max_energy - unit.energy)
		unit.energy += healed
		reward = "+%d de energia" % healed if healed > 0 else "energia já estava cheia"
		if healed > 0:
			_float_text(unit.cell, "+%d" % healed, Color(0.4, 1, 0.4))
	else:
		player.gold += PILLAGE_MILL_GOLD
		reward = "+%d de ouro" % PILLAGE_MILL_GOLD
		_float_text(unit.cell, "+%d" % PILLAGE_MILL_GOLD, Icons.GOLD_COLOR)
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
		return mill.build()
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
			return "Esta %s é de outro jogador." % mill.display_name().to_lower()
		if not mill.has_room():
			return "A %s já tem %d trabalhadores (o máximo)." % [mill.display_name().to_lower(), LumberMill.MAX_WORKERS]
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
	_start_tile_work(unit)


## O trabalhador passa a trabalhar na casa em que está (obra ou reconstrução):
## encerra o turno dele e não é mais selecionado sozinho.
func _start_tile_work(unit: Unit) -> void:
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
	if city == null or not Movement.at_war(unit.owner_player, city.owner_player):
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
	diplomacy.on_city_lost(old_owner, new_owner)
	old_owner.cities.erase(city)
	var was_capital := city.is_capital
	city.is_capital = new_owner.cities.is_empty()
	new_owner.cities.append(city)
	new_owner.founded_city = true
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
	diplomacy.on_city_lost(old_owner, raider)
	var loot := loot_amount(city)
	old_owner.gold -= loot
	raider.gold += loot
	for cell: Vector2i in city.farms:
		ruins_layer.improvements[cell] = {"build": City.Build.FARM, "progress": 0}
	for cell: Vector2i in city.lumber_mills:
		ruins_layer.improvements[cell] = {"build": City.Build.LUMBER_MILL, "progress": 0}
	for cell: Vector2i in city.mines:
		ruins_layer.improvements[cell] = {"build": City.Build.MINE, "progress": 0}
	for cell: Vector2i in city.ruins:
		ruins_layer.improvements[cell] = city.ruins[cell]
	ruins_layer.add_city(city.cell, city.city_name, city.rank(), city.has_walls())
	ruins_layer.queue_redraw()
	# Apaga as fazendas pintadas no mapa antes de a cidade sumir
	city.farms.clear()
	city.lumber_mills.clear()
	city.mines.clear()
	city.ruins.clear()
	city.sites.clear()
	city.constructions.clear()
	city._notify_changed()
	old_owner.cities.erase(city)
	cities_root.remove_child(city)
	city.queue_free()
	if city.is_capital:
		_reassign_capital(old_owner)
	refresh_territories()
	_float_text(city.cell, "+%d" % loot, Icons.GOLD_COLOR)
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
		_update_vision()
		var current := occupants()
		_reachable = Movement.find_reachable(game_map, unit, current)
		_attack_targets = Movement.attack_targets(game_map, unit, _reachable, current)
		if unit.owner_player == viewer():
			# O humano só ataca o que vê (névoa de guerra)
			for target: Vector2i in _attack_targets.keys():
				if not fog.is_visible_cell(target):
					_attack_targets.erase(target)
		move_overlay.show_moves(unit.cell, Movement.destinations(_reachable, current, unit), _attack_targets.keys(),
				unit.is_ranged())
		if unit.has_goto():
			_show_goto_path(unit, unit.goto_target)
	else:
		move_overlay.clear()
	_update_unit_actions()
	_update_info()


## Move a unidade até [param target], que deve ser uma casa vazia ao alcance
## (ou a casa de uma Galé dela com lugar: aí ela embarca).
func move_unit(unit: Unit, target: Vector2i) -> void:
	move_overlay.clear()
	var current := occupants()
	var boat: Unit = current.get(target)
	var reachable := Movement.find_reachable(game_map, unit, current)
	await unit.move_along(Movement.build_path(reachable, target), game_map)
	_check_contacts() # o primeiro encontro aparece na hora em que um vê o outro
	if boat and boat.can_carry(unit):
		boat.board(unit)
		hud.show_message("%s embarcou na Galé (%d/%d)." % [unit.type.display_name, boat.cargo.size(), boat.type.cargo_capacity],
				Color(0.6, 0.85, 1))
		return
	await check_invasion(unit)


## Se o jogador humano vê alguma das casas [param cells] agora (sem névoa,
## sempre), ou se [param unit] é dele (as unidades do humano sempre animam). O
## que ninguém vê acontece sem animação (Unit.watch, attack, _destroy_unit): a
## vez da máquina na névoa é instantânea.
func is_watched(cells: Array, unit: Unit = null) -> bool:
	if unit and unit.owner_player == viewer():
		return true
	for cell: Vector2i in cells:
		if fog.is_visible_cell(cell):
			return true
	return false


## Anda até a casa de ataque (se precisar) e ataca o inimigo em [param target_cell].
## O ataque encerra os movimentos do atacante; se o defensor for destruído,
## o atacante ocupa a casa dele. Quem ataca à distância (Arqueiro, Catapulta)
## dispara um projétil, não leva dano e fica onde está.
func attack(attacker: Unit, target_cell: Vector2i) -> void:
	move_overlay.clear()
	attacker.fortified = false
	var current := occupants()
	var defender: Unit = current[target_cell]
	var reachable := Movement.find_reachable(game_map, attacker, current)
	var from_cell: Vector2i = Movement.attack_targets(game_map, attacker, reachable, current)[target_cell]
	if from_cell != attacker.cell:
		await attacker.move_along(Movement.build_path(reachable, from_cell), game_map)

	if not is_watched([attacker.cell, target_cell], attacker) and defender.owner_player != viewer():
		pass # combate na névoa do humano: sem animação
	elif attacker.is_ranged():
		await attacker.play_shot(defender.position)
	else:
		await attacker.play_attack(defender.position)
	var result := Combat.resolve(attacker, defender, _rng)
	diplomacy.on_attacked(defender.owner_player, attacker.owner_player)
	attacker.skip_turn()
	_show_damage(defender, result.damage_to_defender)
	if not attacker.is_ranged():
		_show_damage(attacker, result.damage_to_attacker, 0.45)
	print("%s (%s) %s %s (%s): causa %d, recebe %d -> energia %d x %d" % [
		attacker.type.display_name, attacker.owner_player.display_name,
		"dispara em" if attacker.is_ranged() else "ataca",
		defender.type.display_name, defender.owner_player.display_name,
		result.damage_to_defender, result.damage_to_attacker, attacker.energy, defender.energy,
	])

	if result.defender_destroyed and attacker.is_ranged():
		await _destroy_unit(defender)
	elif result.defender_destroyed:
		await _destroy_unit(defender)
		await attacker.advance_to(target_cell, game_map)
		await check_invasion(attacker) # derrotou a guarnição e entrou na cidade
	elif result.attacker_destroyed:
		await _destroy_unit(attacker)


## O colono funda uma cidade na casa em que está e deixa de existir.
## Cidade fundada na floresta (ou na selva) transforma a casa em pradaria.
## Use city_site_error antes para saber se o lugar é válido.
## [param city_name] vazio = próximo nome da lista City.NAMES.
func found_city(settler: Unit, city_name := "") -> City:
	var player := settler.owner_player
	if Terrain.has_wood(game_map.get_terrain(settler.cell)):
		game_map.set_terrain(settler.cell, Terrain.Type.GRASSLAND)
	var city := City.new()
	city.setup(city_name if not city_name.is_empty() else _next_city_name(player), player, settler.cell, game_map)
	city.is_capital = player.cities.is_empty()
	_claim_territory(city)
	cities_root.add_child(city)
	player.cities.append(city)
	player.founded_city = true
	refresh_territories()
	city.assign_idle_citizens() # o primeiro cidadão já trabalha uma casa (+1 de alimento)
	print("%s fundou a cidade %s em %s (%s, território de %d casas)" % [
		player.display_name, city.city_name, city.cell, city.rank_text(), city.territory.size()])
	_float_text(city.cell, city.city_name, Color.WHITE)

	if settler == selected_unit:
		select_unit(null)
	player.units.erase(settler)
	settler.queue_free()
	_check_victory()
	return city


## O trabalhador constrói uma madeireira remota (ou, com [param is_mine], uma
## mina remota) na casa em que está, ou entra na que já existe ali, e passa a
## trabalhar nela: some do mapa e não recebe ordens até ser retirado. Use
## lumber_mill_error / mine_error antes.
func work_lumber_mill(worker: Unit, is_mine := false) -> LumberMill:
	var player := worker.owner_player
	var mill := lumber_mill_at(worker.cell)
	if mill == null:
		mill = LumberMill.new()
		mill.setup(player, worker.cell, game_map, is_mine)
		cities_root.add_child(mill)
		player.lumber_mills.append(mill)
		print("%s começou uma %s em %s" % [player.display_name, mill.display_name().to_lower(), worker.cell])
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
## até [param radius] casas de distância, ou Unit.NO_TARGET se não houver. Com
## [param ocean], uma casa de oceano livre (onde nasce a Galé).
func free_cell_near(center: Vector2i, radius: int, ocean := false) -> Vector2i:
	var current := occupants()
	for distance in radius + 1:
		for y in range(-distance, distance + 1):
			for x in range(-distance, distance + 1):
				var cell := center + Vector2i(x, y)
				if maxi(absi(x), absi(y)) != distance or not game_map.is_in_bounds(cell) or current.has(cell):
					continue
				if game_map.is_ocean(cell) if ocean else Terrain.is_walkable(game_map.get_terrain(cell)):
					return cell
	return Unit.NO_TARGET


# --- Jogador humano ---------------------------------------------------------

func _on_cell_clicked(cell: Vector2i) -> void:
	var unit := visible_unit_at(cell)
	var city := known_city_at(cell)
	var current := TurnManager.current_player()
	# Unidade escondida na cidade não é selecionada pelo mapa: o clique abre a
	# cidade, e ela é ativada pela janela da cidade.
	var own_unit := unit if unit and unit.owner_player == current and not unit.hidden_in_city else null
	var mill := lumber_mill_at(cell)
	if selected_unit and _attack_targets.has(cell):
		var attacker := selected_unit
		var victim: Unit = occupants().get(cell)
		# Unidade de quem está em paz: guerra surpresa (pergunta antes)
		if victim and not Movement.at_war(attacker.owner_player, victim.owner_player):
			if not await _confirm_surprise_attack(victim.owner_player) or not is_instance_valid(attacker) \
					or not is_instance_valid(victim) or attacker != selected_unit:
				return
		attacker.goto_target = Unit.NO_TARGET # ordem manual cancela o "Mover"
		_human_action(attack.bind(attacker, cell))
	elif selected_unit and own_unit and own_unit.can_carry(selected_unit) and _reachable.has(cell):
		selected_unit.goto_target = Unit.NO_TARGET
		_human_action(move_unit.bind(selected_unit, cell)) # embarca na Galé
	elif own_unit and own_unit != selected_unit:
		select_unit(own_unit)
	elif selected_unit and _reachable.has(cell) and unit == null:
		selected_unit.goto_target = Unit.NO_TARGET
		_human_action(move_unit.bind(selected_unit, cell))
	elif city and city.owner_player == current:
		_open_city(city)
	elif city:
		# Cidade de outro jogador: a janela dela não abre (desde 29/10/2026)
		hud.show_message("%s, cidade de %s." % [city.city_name, city.owner_player.display_name], Color(1, 0.85, 0.5))
	elif mill and mill.owner_player == current and unit == null:
		_select_mill(mill)
	elif own_unit:
		select_unit(own_unit)
	elif selected_unit and unit and unit.owner_player != current and not unit.hidden_in_city:
		# Inimigo fora do alcance (ou sem movimentos): explica em vez de só tirar a seleção
		hud.show_message(_no_attack_reason(selected_unit, unit), Color(1, 0.6, 0.4))
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
## turno seguinte (ex.: Cavalaria Leve com 1 movimento diante de uma floresta).
func _turns_for_path(unit: Unit, path: Array[Vector2i]) -> int:
	var turns := 1
	var moves := unit.moves_left if unit.moves_left > 0 else unit.max_points()
	var previous := unit.cell
	for cell in path:
		var cost := Movement.step_cost(game_map, unit, previous, cell)
		previous = cell
		if cost > moves:
			turns += 1
			moves = unit.max_points()
		moves -= cost
	return turns


## Clique no modo "Mover": guarda o destino e a unidade já começa a andar.
## Clique num inimigo: ataca se der; senão, o destino vira a casa vizinha a ele
## (ou, se a unidade já está ao lado, aparece o motivo de não poder atacar).
func _on_goto_clicked(cell: Vector2i) -> void:
	var unit := selected_unit
	_set_goto_mode(false)
	if unit == null:
		return
	var enemy := visible_unit_at(cell)
	if enemy and enemy.owner_player != unit.owner_player:
		if _attack_targets.has(cell):
			unit.goto_target = Unit.NO_TARGET
			_human_action(attack.bind(unit, cell))
			return
		var near := _cell_next_to(unit, cell)
		if near == Unit.NO_TARGET or near == unit.cell:
			hud.show_message(_no_attack_reason(unit, enemy), Color(1, 0.6, 0.4))
			_show_goto_path(unit, unit.goto_target)
			return
		cell = near
	if not game_map.is_in_bounds(cell) or Movement.find_path(game_map, unit, cell, occupants()).is_empty():
		hud.show_message("Não há caminho por terra até essa casa.", Color(1, 0.6, 0.4))
		_show_goto_path(unit, unit.goto_target)
		return
	unit.goto_target = cell
	unit.fortified = false
	_human_action(advance_goto.bind(unit))


## Casa vizinha a [param target] mais perto (pelo caminho) da unidade: a própria
## casa dela, se já estiver ao lado; NO_TARGET se não der para chegar a nenhuma.
func _cell_next_to(unit: Unit, target: Vector2i) -> Vector2i:
	var current := occupants()
	var best := Unit.NO_TARGET
	var best_length := 1 << 30
	for direction in Movement.DIRECTIONS:
		var cell: Vector2i = target + direction
		if cell == unit.cell:
			return cell
		var path := Movement.find_path(game_map, unit, cell, current)
		if not path.is_empty() and not current.has(cell) and path.size() < best_length:
			best_length = path.size()
			best = cell
	return best


## Por que a unidade não pode atacar o inimigo agora (mensagem para o jogador).
func _no_attack_reason(unit: Unit, enemy: Unit) -> String:
	if unit.attack <= 0:
		return "%s não ataca (Ataque 0)." % unit.type.display_name
	if unit.moves_left <= 0:
		return "%s está sem movimentos neste turno: dá para atacar o %s no próximo turno." % [
				unit.type.display_name, enemy.type.display_name]
	if unit.is_ranged() and Movement.grid_distance(unit.cell, enemy.cell) <= unit.type.attack_range \
			and not Movement.has_line_of_fire(game_map, unit.cell, enemy.cell):
		return "Floresta, colina ou montanha no caminho: %s não tem linha de tiro até o %s." % [
				unit.type.display_name, enemy.type.display_name]
	if unit.is_ranged():
		return "%s está fora do alcance de disparo (%d %s)." % [enemy.type.display_name,
				unit.type.attack_range, "casa" if unit.type.attack_range == 1 else "casas"]
	return "%s está fora do alcance de ataque neste turno." % enemy.type.display_name


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
		spent += Movement.step_cost(game_map, unit, unit.cell if i == 0 else path[i - 1], path[i])
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
		"mine":
			_build_mine_with_selected()
		"road":
			_build_road_with_selected()
		"farm":
			_build_farm_with_selected()
		"release_worker":
			_release_worker_from_selected_mill()
		"pillage":
			_pillage_with_selected()
		"rebuild":
			_rebuild_with_selected()
		"join_city":
			_join_city_with_selected()
		"unload":
			_select_passenger()


## Tecla U / botão "Desembarcar" na Galé: seleciona quem está a bordo (o
## próximo, a cada vez). Ela desembarca andando para uma casa de terra vizinha.
func _select_passenger() -> void:
	var boat := selected_unit
	if boat and boat.transport:
		boat = boat.transport # já há um passageiro selecionado: vai para o próximo
	if boat == null or boat.cargo.is_empty() or boat.owner_player != TurnManager.current_player():
		return
	var index := (boat.cargo.find(selected_unit) + 1) % boat.cargo.size()
	select_unit(boat.cargo[index])
	if selected_unit.moves_left <= 0:
		hud.show_message("%s está sem movimentos: desembarca no próximo turno." % selected_unit.type.display_name, Color(1, 0.6, 0.4))
	elif Movement.destinations(_reachable, occupants(), selected_unit).is_empty():
		hud.show_message("Leve a Galé até a costa para desembarcar.", Color(1, 0.9, 0.3))


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
	hud.city_name_dialog.open(_next_city_name(settler.owner_player))
	var city_name: String = await hud.city_name_dialog.confirmed
	camera.locked = false
	if city_name.is_empty():
		return # cancelou: o colono continua onde está
	var city := found_city(settler, city_name)
	if not game_over:
		_open_city(city)


## Tecla M / botão da madeireira: o trabalhador selecionado constrói uma
## madeireira onde está. No território de uma cidade sua, ela é da cidade (ele
## fica na casa até terminar); fora dele, é remota (ele entra nela, ou na que já
## existe ali, e passa a trabalhar nela).
func _work_lumber_mill_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_build_lumber_mill:
		return
	var error := lumber_mill_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	if is_city_mill_site(worker):
		_build_improvement_with(worker, City.Build.LUMBER_MILL)
		return
	var mill := work_lumber_mill(worker)
	var status := "em obra %d/%d" % [mill.progress, mill.cost()] if not mill.is_done() else "pronta"
	hud.show_message("Trabalhador na madeireira (%s, %d/%d trabalhadores)." % [
			status, mill.workers.size(), LumberMill.MAX_WORKERS], Color(0.75, 1, 0.75))
	_select_next_unit()


## Tecla M: numa colina, a mina (_build_mine_with_selected); no resto, a
## madeireira (_work_lumber_mill_with_selected).
func _mine_or_lumber_mill_with_selected() -> void:
	if selected_unit and game_map.get_terrain(selected_unit.cell) == Terrain.Type.HILLS:
		_build_mine_with_selected()
	else:
		_work_lumber_mill_with_selected()


## Tecla M numa colina / botão "Construir mina": o trabalhador selecionado faz
## uma mina da cidade onde está (colina com ferro, no território de uma cidade sua).
func _build_mine_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_build_lumber_mill:
		return
	var error := mine_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	if is_city_mill_site(worker):
		_build_improvement_with(worker, City.Build.MINE)
		return
	var mine := work_lumber_mill(worker, true)
	var status := "em obra %d/%d" % [mine.progress, mine.cost()] if not mine.is_done() else "pronta"
	hud.show_message("Trabalhador na mina (%s, %d/%d trabalhadores)." % [
			status, mine.workers.size(), LumberMill.MAX_WORKERS], Color(0.75, 1, 0.75))
	_select_next_unit()


## Tecla E / botão "Construir estrada": o trabalhador selecionado faz uma
## estrada onde está.
func _build_road_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_build_lumber_mill:
		return
	var error := road_error(worker)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	build_road(worker)
	hud.show_message("Trabalhador construindo a estrada (%d/%d, 1 por turno)." % [
			game_map.road_progress[worker.cell], GameMap.ROAD_COST], Color(0.75, 1, 0.75))
	_select_next_unit()


## Tecla C / botão "Construir fazenda": o trabalhador selecionado faz uma
## fazenda da cidade onde está (no território de uma cidade sua).
func _build_farm_with_selected() -> void:
	var worker := selected_unit
	if worker == null or not worker.type.can_build_farm:
		return
	var error := improvement_error(worker, City.Build.FARM)
	if not error.is_empty():
		hud.show_message(error, Color(1, 0.6, 0.4))
		return
	_build_improvement_with(worker, City.Build.FARM)


func _build_improvement_with(worker: Unit, build: int) -> void:
	var city := territory_owner(worker.cell)
	build_improvement(worker, build)
	var site: Dictionary = city.sites[worker.cell]
	hud.show_message("Trabalhador construindo a %s de %s (%d/%d, 1 por turno)." % [
			String(City.BUILDS[build]["name"]).to_lower(), city.city_name, site["progress"], City.BUILDS[build]["cost"]],
			Color(0.75, 1, 0.75))
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
		select_unit(unit) # ainda tem movimento (ex.: Cavalaria Leve)
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
	_update_info() # painel da madeireira


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
	diplomacy.turn = turn_number
	diplomacy.update_trust(player, players)
	_check_contacts()
	_expel_from_closed_borders(player)
	_awaiting_end_turn = false
	hud.set_turn(turn_number, player)
	_heal_fortified_units(player)
	_check_deep_water(player)
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
	# Audiências aceitas durante a vez da máquina: abrem agora
	while not _pending_audiences.is_empty() and not game_over:
		var guest: Player = _pending_audiences.pop_front()
		hud.meeting_dialog.open(self, guest)
		await hud.meeting_dialog.visibility_changed
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
	# Trabalhador que acabou de terminar uma melhoria: é ele que fica em foco
	for worker in _finished_workers:
		if selected_unit == null and is_instance_valid(worker) and can_move(worker):
			select_unit(worker)
	_finished_workers.clear()
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
	AIDiplomacy.play(self, player)
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
			_float_text(unit.cell, "+%d" % healed, Color(0.4, 1, 0.4))


## Início da vez do jogador: a Galé que terminou o turno anterior em águas
## profundas conta mais um; ao chegar a UnitType.deep_water_turn_limit, afunda
## com quem estiver a bordo. Fora delas, a contagem zera. (As águas profundas
## ainda não existem no mapa: ver Terrain.is_deep_water.)
func _check_deep_water(player: Player) -> void:
	for unit in player.units.duplicate():
		if unit.type.deep_water_turn_limit <= 0:
			continue
		if not Terrain.is_deep_water(game_map.get_terrain(unit.cell)):
			unit.deep_water_turns = 0
			continue
		unit.deep_water_turns += 1
		if unit.deep_water_turns >= unit.type.deep_water_turn_limit:
			if not player.is_ai:
				hud.show_message("A %s afundou em águas profundas%s." % [unit.type.display_name,
						" com %d unidade(s) a bordo" % unit.cargo.size() if not unit.cargo.is_empty() else ""], Color(1, 0.6, 0.4))
			_destroy_unit(unit)


## Início da vez do jogador: as cidades dele produzem, comem e crescem.
## O jogador humano vê o resumo no topo da tela.
func _process_cities(player: Player) -> void:
	var messages: Array[String] = []
	for city in player.cities:
		for event in city.process_turn(_spawn_city_unit):
			messages.append("%s: %s" % [city.city_name, event])
		if city.has_large_territory() and not city.territory_expanded:
			var gained := expand_territory(city)
			if gained > 0:
				messages.append("%s: o território cresceu (+%d casas)" % [city.city_name, gained])
		for cell: Vector2i in city.extracted:
			_show_extraction(player, cell, city.extracted[cell][0], city.extracted[cell][1])
		if not player.is_ai:
			for build in city.completed:
				_completion_notices.append([city, build])
			if city.disorder_turns == 1:
				_completion_notices.append([city, DISORDER_NOTICE]) # entrou em desordem neste turno
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
	if build == DISORDER_NOTICE:
		var mood := city.mood()
		return "[color=#%s]A cidade entrou em desordem civil[/color]: %d infelizes contra %d felizes.\nEnquanto durar, ela não avança obras nem rende ouro ou ciência. Abra a cidade para pôr cidadãos nas festividades, fortifique um soldado nela ou construa um Templo." % [
			City.UNHAPPY_COLOR.to_html(false), mood["unhappy"], mood["happy"]]
	var text := City.completion_text(build)
	var idle := city.free_citizens()
	if idle > 0:
		text += "\n[color=#%s]%d %s sem tarefa nesta cidade.[/color] Abra a cidade para dar outra tarefa a %s." % [
			City.IDLE_COLOR.lightened(0.3).to_html(false), idle,
			"cidadão está" if idle == 1 else "cidadãos estão", "ele" if idle == 1 else "eles"]
	else:
		text += "\nTodos os cidadãos da cidade estão trabalhando."
	return text


## "+N" de madeira ou ferro subindo da casa da madeireira ou mina. Só para o
## jogador humano: o que os outros extraem não aparece.
func _show_extraction(player: Player, cell: Vector2i, amount: int, is_mine: bool) -> void:
	if player != viewer():
		return
	_float_text(cell, "+%d" % amount, Icons.IRON_COLOR if is_mine else LumberMill.WOOD_BAR_COLOR)


## Texto subindo do topo da casa (ganhos, cura, nome da cidade fundada). Os
## textos ficam por cima da névoa: só aparece se o jogador humano vê a casa.
func _float_text(cell: Vector2i, text: String, color: Color) -> void:
	if not fog.is_visible_cell(cell):
		return
	FloatingText.spawn(units_root, game_map.cell_to_world(cell) - Vector2(0, GameMap.TILE_SIZE / 2.0), text, color)


## Início da vez do jogador: as madeireiras e minas remotas avançam a obra ou
## tiram madeira ou ferro (com um "+N" subindo). Floresta esgotada vira cerrado: a
## madeireira some e os trabalhadores voltam ao mapa.
func _process_lumber_mills(player: Player) -> void:
	var messages: Array[String] = []
	for mill: LumberMill in player.lumber_mills.duplicate():
		var was_done := mill.is_done()
		var taken := mill.process_turn()
		if mill.is_mine:
			player.iron += taken
		else:
			player.wood += taken
		if taken > 0:
			_show_extraction(player, mill.cell, taken, mill.is_mine)
		if mill.is_done() and not was_done:
			messages.append("%s em (%d, %d) pronta" % [mill.display_name(), mill.cell.x, mill.cell.y])
		if mill.is_exhausted():
			messages.append("A floresta em (%d, %d) acabou e virou cerrado" % [mill.cell.x, mill.cell.y])
			_remove_lumber_mill(mill)
	for message in messages:
		print("%s: %s" % [player.display_name, message])
	if not player.is_ai and not messages.is_empty():
		hud.show_message("\n".join(messages), Color(0.75, 1, 0.75))


## Início da vez do jogador: cada Trabalhador construindo ou reconstruindo faz
## REBUILD_PER_TURN na obra ou ruína da casa em que está. Pronta, a melhoria
## passa a funcionar e, para o humano, o Trabalhador é selecionado no começo da
## vez (_finished_workers; sem o aviso de construção concluída). Se a obra ou a
## ruína não existe mais, ele para.
func _process_rebuilds(player: Player) -> void:
	var messages: Array[String] = []
	for unit in player.units:
		if not unit.rebuilding:
			continue
		if game_map.road_progress.has(unit.cell):
			if game_map.add_road_progress(unit.cell, REBUILD_PER_TURN):
				unit.rebuilding = false
				messages.append("Estrada concluída em (%d, %d)" % [unit.cell.x, unit.cell.y])
				if not player.is_ai:
					_finished_workers.append(unit)
			continue
		var city := claiming_city(unit.cell)
		if city == null or city.owner_player != player or not (city.ruins.has(unit.cell) or city.sites.has(unit.cell)):
			unit.rebuilding = false
			continue
		if city.sites.has(unit.cell):
			var site_build: int = city.sites[unit.cell]["build"]
			if city.add_site_progress(unit.cell, REBUILD_PER_TURN):
				unit.rebuilding = false
				messages.append("%s: %s concluída em (%d, %d)" % [city.city_name, City.BUILDS[site_build]["name"], unit.cell.x, unit.cell.y])
				if not player.is_ai:
					_finished_workers.append(unit)
			continue
		var build: int = city.ruins[unit.cell]["build"]
		if city.add_rebuild_progress(unit.cell, REBUILD_PER_TURN):
			unit.rebuilding = false
			messages.append("%s: %s reconstruída em (%d, %d)" % [city.city_name, City.BUILDS[build]["name"], unit.cell.x, unit.cell.y])
			if not player.is_ai:
				_finished_workers.append(unit)
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


## Tecla T / botão "Árvore [T]": a árvore de tecnologias do jogador humano. Na
## vez dele, sem nada acontecendo, dá para escolher a pesquisa clicando.
func _open_tech_tree() -> void:
	var player := TurnManager.current_player()
	if player.is_ai:
		for other in players:
			if not other.is_ai:
				player = other
	if player.is_ai or hud.city_window.visible or hud.research_dialog.visible:
		return
	hud.tech_tree_dialog.open(player, not _is_busy and not game_over and player == TurnManager.current_player())


## Clique numa tecnologia disponível na árvore: vira a pesquisa.
func _on_tree_research_chosen(tech: int) -> void:
	var player := TurnManager.current_player()
	if _is_busy or player.is_ai:
		return
	player.research = tech
	_update_resources()
	hud.show_message("Pesquisando %s (%d pontos de ciência)." % [Technology.tech_name(tech), Technology.cost(tech)], Icons.SCIENCE_COLOR)


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
## unidade lá, na primeira casa vizinha de terra livre (a Galé, numa casa
## vizinha de oceano). Retorna false se não houver espaço (a cidade tenta de
## novo no próximo turno).
func _spawn_city_unit(type: UnitType, city: City) -> bool:
	var cell := free_cell_near(city.cell, 1, type.is_naval)
	if cell == Unit.NO_TARGET:
		return false
	_spawn_unit(type, city.owner_player, cell)
	return true


func _destroy_unit(unit: Unit) -> void:
	print("%s (%s) foi destruído" % [unit.type.display_name, unit.owner_player.display_name])
	if unit == selected_unit:
		select_unit(null)
	# Quem está a bordo afunda junto com a Galé
	for passenger in unit.cargo.duplicate():
		print("  %s afundou junto" % passenger.type.display_name)
		if passenger == selected_unit:
			select_unit(null)
		passenger.owner_player.units.erase(passenger)
		passenger.queue_free()
	unit.cargo.clear()
	unit.leave_transport()
	unit.owner_player.units.erase(unit)
	_check_victory()
	if is_watched([unit.cell], unit):
		await unit.play_death()
	else:
		unit.queue_free() # na névoa do humano: some sem animação


## Objetivo da partida: eliminar o adversário. Quem já fundou uma cidade é
## DERROTADO ao perder a última (ocupada ou destruída, ver check_invasion),
## mesmo que ainda tenha unidades, madeireiras ou minas; antes da primeira
## cidade, só ao perder todas as unidades (Player.is_defeated). O derrotado
## sai do jogo (_eliminate) e vence quem for o último vivo.
func _check_victory() -> void:
	for player in players:
		if player.is_defeated() and not player.eliminated:
			_eliminate(player)
	var alive := players.filter(func(player: Player) -> bool: return not player.eliminated)
	if alive.size() != 1:
		return
	game_over = true
	_awaiting_end_turn = false
	hud.show_end_turn_prompt(false)
	hud.show_victory(alive[0])
	print("%s venceu!" % alive[0].display_name)


## Tira do jogo o jogador derrotado: as unidades que restam (inclusive os
## Trabalhadores das madeireiras) e as madeireiras e minas remotas somem, e ele
## não joga mais (TurnManager pula a vez dele).
func _eliminate(player: Player) -> void:
	player.eliminated = true
	print("%s foi derrotado" % player.display_name)
	if player != viewer() and viewer() != null and not viewer().eliminated:
		hud.show_message("%s foi derrotado: perdeu todas as cidades." % player.display_name, Color(1, 0.85, 0.5))
	for mill: LumberMill in player.lumber_mills.duplicate():
		if mill == _selected_mill:
			select_unit(null)
		mill.workers.clear()
		player.lumber_mills.erase(mill)
		mill.queue_free()
	for unit: Unit in player.units.duplicate():
		if unit == selected_unit:
			select_unit(null)
		for passenger in unit.cargo:
			passenger.transport = null
		unit.cargo.clear()
		player.units.erase(unit)
		unit.queue_free()
	_update_vision()


# --- Diplomacia (ver Diplomacy) -------------------------------------------------

## Quadros entre duas buscas de primeiros encontros.
const CONTACT_CHECK_FRAMES := 12


## Se o humano pode agir na diplomacia agora (declarar guerra, propor paz): na
## vez dele, sem nada acontecendo.
func can_act_in_diplomacy() -> bool:
	return not _is_busy and not game_over and not TurnManager.current_player().is_ai


## "Imperador do Jogador 2" (por enquanto todo líder é Imperador; o título vai
## variar com a civilização e o governo).
static func leader_name(player: Player) -> String:
	return player.leader_title()


## Primeiros encontros: dois jogadores se conhecem quando um vê alguma unidade
## ou cidade do outro (pela visão das unidades e cidades). Começam em paz.
func _check_contacts() -> void:
	if diplomacy == null:
		return
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a: Player = players[i]
			var b: Player = players[j]
			if a.eliminated or b.eliminated or diplomacy.have_met(a, b):
				continue
			if _sees(a, b) or _sees(b, a):
				diplomacy.meet(a, b)
				print("Primeiro encontro: %s e %s (paz)" % [a.display_name, b.display_name])
				if not a.is_ai or not b.is_ai:
					_offer_audience(b if not a.is_ai else a)


## Primeiro encontro do humano com [param other]: na hora, o conselheiro avisa
## e pergunta se propõe uma audiência (pedido do usuário, 30/10/2026). "Sim"
## abre o encontro com o líder (na vez da máquina, fica para o começo da vez
## do humano: _pending_audiences).
func _offer_audience(other: Player) -> void:
	_queue_diplomacy_notice("Primeiro encontro",
			"[i]\"Meu senhor, encontramos um emissário %s. Devemos propor uma audiência?\"[/i]\n\nNossos impérios começam em [b]paz[/b]: ninguém ataca o outro nem entra no território dele." % other.of_name(),
			["Sim", "Não"],
			func(choice: int) -> void:
				if choice != 0 or game_over or other.eliminated:
					return
				if can_act_in_diplomacy():
					hud.meeting_dialog.open(self, other)
				elif not _pending_audiences.has(other):
					_pending_audiences.append(other))


## Se [param viewer] vê alguma unidade ou cidade de [param other].
func _sees(viewer: Player, other: Player) -> bool:
	var sources: Array[Vector3i] = []
	for unit in viewer.units:
		sources.append(Vector3i(unit.sight_cell.x, unit.sight_cell.y, unit.type.vision))
	for city in viewer.cities:
		sources.append(Vector3i(city.cell.x, city.cell.y, FogOfWar.CITY_VISION))
	var things: Array[Vector2i] = []
	for unit in other.units:
		if unit.working_mill == null and unit.transport == null:
			things.append(unit.cell)
	for city in other.cities:
		things.append(city.cell)
	for source in sources:
		for thing in things:
			if maxi(absi(thing.x - source.x), absi(thing.y - source.y)) <= source.z:
				return true
	return false


## Declaração de guerra de [param aggressor] a [param target] (ou guerra
## surpresa, com [param surprise]). O humano atacado fica sabendo.
func declare_war(aggressor: Player, target: Player, surprise := false) -> void:
	if not diplomacy.can_declare_war(aggressor, target):
		return
	diplomacy.declare_war(aggressor, target, players, surprise)
	print("%s declarou guerra%s a %s" % [aggressor.display_name, " SURPRESA" if surprise else "", target.display_name])
	if not target.is_ai:
		_queue_diplomacy_notice("Guerra!", "O [b]%s[/b] declarou [color=#%s][b]GUERRA[/b][/color] contra você.\n\nAs unidades dele podem atacar as suas e invadir o seu território (e você, as dele)." % [
				leader_name(aggressor), StoneStyle.NEGATIVE.to_html(false)])
	hud.refresh_diplomacy()


## Tratado de paz entre [param a] e [param b]: trégua, e as unidades de cada um
## no território do outro voltam para fora dele.
func sign_peace(a: Player, b: Player) -> void:
	diplomacy.make_peace(a, b)
	print("Paz entre %s e %s" % [a.display_name, b.display_name])
	_expel_from_closed_borders(a)
	_expel_from_closed_borders(b)
	hud.refresh_diplomacy()


## A máquina [param ai] propõe a paz ao humano [param human] (aviso com Aceitar e Recusar).
func offer_peace_to_human(ai: Player, human: Player) -> void:
	_queue_diplomacy_notice("Proposta de paz",
			"O [b]%s[/b] propõe um tratado de paz.\n\nCom a paz, a guerra acaba e começa uma trégua de %d turnos: ninguém declara guerra nesse tempo. As unidades no território do outro voltam para fora dele." % [
				leader_name(ai), Diplomacy.TRUCE_TURNS],
			["Aceitar a paz", "Recusar"],
			func(choice: int) -> void:
				if choice == 0 and diplomacy.at_war(ai, human):
					sign_peace(ai, human)
					hud.show_message("Paz com o %s." % leader_name(ai), Color(0.75, 1, 0.75))
				elif choice != 0:
					diplomacy.add_trust(ai, human, -5))


## Botão "Propor encontro" da janela de Diplomacia: ele aceita receber o humano
## ou não (AIDiplomacy.accepts_meeting); recusado, só depois de
## Diplomacy.PROPOSAL_INTERVAL turnos. Aceito, abre a tela do encontro.
func request_meeting(target: Player) -> void:
	var human := viewer()
	if human == null or not can_act_in_diplomacy():
		return
	if not diplomacy.can_propose(human, target):
		hud.show_message("O %s não quer recebê-lo tão cedo." % leader_name(target), Color(1, 0.6, 0.4))
		return
	if not AIDiplomacy.accepts_meeting(self, target, human):
		diplomacy.note_proposal(human, target)
		hud.refresh_diplomacy()
		await hud.ask("Encontro recusado", "O [b]%s[/b] se recusa a recebê-lo.\n\nEle está [b]%s[/b] com você. Tente de novo em %d turnos." % [
				leader_name(target), Diplomacy.TRUST_NAMES[diplomacy.trust_level(target, human)].to_lower(), Diplomacy.PROPOSAL_INTERVAL], ["OK"])
		return
	hud.meeting_dialog.open(self, target)


## "Declarar guerra" no encontro: confirma antes; o encontro continua, com a
## resposta dele (brava).
func request_declare_war(target: Player) -> void:
	var human := viewer()
	if human == null or not diplomacy.can_declare_war(human, target):
		return
	var choice: int = await hud.ask("Declarar guerra?",
			"Declarar [color=#%s][b]GUERRA[/b][/color] ao [b]%s[/b]?\n\nA confiança dele em você cai %d. Vocês poderão se atacar e invadir o território um do outro até assinarem a paz." % [
				StoneStyle.NEGATIVE.to_html(false), leader_name(target), -Diplomacy.DECLARE_WAR_TRUST],
			["Declarar guerra", "Cancelar"])
	if choice == 0:
		declare_war(human, target)
		# O encontro continua: ele responde, bravo
		hud.meeting_dialog.show_reply(_leader_line(LEADER_LINES_WAR) +
				"\n[color=#%s][b]Guerra declarada.[/b][/color] Vocês podem se atacar e invadir o território um do outro." % StoneStyle.NEGATIVE.to_html(false),
				Nation.Mood.ANGRY)


## "Propor paz" no encontro: ele responde na própria tela. Recusada, o próximo
## encontro só depois de Diplomacy.PROPOSAL_INTERVAL turnos.
func request_peace(target: Player) -> void:
	var human := viewer()
	if human == null or not diplomacy.at_war(human, target):
		return
	if AIDiplomacy.accepts_peace(self, target, human):
		sign_peace(human, target)
		hud.meeting_dialog.show_reply(_leader_line(LEADER_LINES_PEACE_YES) +
				"\n[color=#%s][b]Ele aceita a paz.[/b][/color] Começa uma trégua de %d turnos: ninguém declara guerra nesse tempo." % [
				StoneStyle.POSITIVE.to_html(false), Diplomacy.TRUCE_TURNS], Nation.Mood.HAPPY)
	else:
		diplomacy.note_proposal(human, target)
		var furious := diplomacy.trust_level(target, human) == Diplomacy.Trust.FURIOUS
		hud.meeting_dialog.show_reply(_leader_line(LEADER_LINES_PEACE_NO_FURIOUS if furious else LEADER_LINES_PEACE_NO) +
				"\n[color=#%s][b]Ele recusa a paz[/b][/color] por enquanto. Você só poderá pedir outro encontro daqui a %d turnos." % [
				StoneStyle.NEGATIVE.to_html(false), Diplomacy.PROPOSAL_INTERVAL], Nation.Mood.ANGRY if furious else Nation.Mood.NEUTRAL)
	hud.refresh_diplomacy()


## Falas do líder no encontro, em resposta às propostas (uma sorteada; desde
## 30/10/2026, pedido do usuário). A expressão do retrato acompanha a resposta
## (MeetingDialog.show_reply).
const LEADER_LINES_WAR := ["Você vai se arrepender!", "Então que os deuses decidam no campo de batalha.",
		"Meus exércitos já marcham. Até breve, estrangeiro.", "Foi um erro. Um erro que vai custar caro ao seu povo."]
const LEADER_LINES_PEACE_YES := ["Que haja paz entre nossos povos.", "Muito bem. Que nossas espadas descansem.",
		"Aceito. Já se derramou sangue demais."]
const LEADER_LINES_PEACE_NO := ["Ainda não é hora de paz.", "Meus generais discordam. A guerra continua.",
		"Volte quando tiver algo melhor a oferecer."]
const LEADER_LINES_PEACE_NO_FURIOUS := ["Paz? Depois do que você fez? Nunca!",
		"Só falaremos de paz sobre as ruínas das suas cidades.", "Saia da minha frente."]


## Uma fala sorteada de [param lines], entre aspas e em itálico.
func _leader_line(lines: Array) -> String:
	return "[i]\"%s\"[/i]" % lines[_rng.randi_range(0, lines.size() - 1)]


## Ataque do humano a uma unidade de quem está em paz com ele: pergunta antes,
## porque é uma GUERRA SURPRESA (traição: a confiança do atacado e de quem te
## conhece cai). Retorna true se o ataque deve seguir.
func _confirm_surprise_attack(victim: Player) -> bool:
	var human := viewer()
	var choice: int = await hud.ask("Guerra surpresa?",
			"Você está em [b]paz[/b] com o [b]%s[/b]. Atacar agora, sem aviso, é uma [color=#%s][b]GUERRA SURPRESA[/b][/color]: uma traição.\n\nA confiança dele em você cai %d, e a de todos os imperadores que te conhecem cai %d." % [
				leader_name(victim), StoneStyle.NEGATIVE.to_html(false), -Diplomacy.SURPRISE_WAR_TRUST, -Diplomacy.SURPRISE_WAR_WITNESS_TRUST],
			["Atacar (guerra surpresa)", "Cancelar"])
	if choice != 0 or not diplomacy.can_declare_war(human, victim):
		return false
	declare_war(human, victim, true)
	return true


## Unidades de [param player] dentro do território de quem está em paz com ele
## (sem fronteiras abertas) vão para a casa livre mais próxima fora dele.
func _expel_from_closed_borders(player: Player) -> void:
	var current := occupants()
	for unit in player.units:
		if unit.working_mill or unit.transport or Movement.territory_open(game_map, player, unit.cell):
			continue
		var cell := _nearest_open_cell(unit, current)
		if cell == Unit.NO_TARGET:
			continue
		current.erase(unit.cell)
		unit.cell = cell
		unit.position = game_map.cell_to_world(cell)
		current[cell] = unit
		print("%s (%s) saiu do território fechado para %s" % [unit.type.display_name, player.display_name, cell])


func _nearest_open_cell(unit: Unit, current: Dictionary) -> Vector2i:
	for radius in range(1, 12):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell := unit.cell + Vector2i(x, y)
				if Movement.can_stand(game_map, unit.type, cell) and not current.has(cell) \
						and Movement.territory_open(game_map, unit.owner_player, cell):
					return cell
	return Unit.NO_TARGET


## Aviso de diplomacia para o humano (um de cada vez, em ordem). Com
## [param callback], ele recebe o botão escolhido.
func _queue_diplomacy_notice(title: String, text: String, buttons: Array = ["OK"], callback := Callable()) -> void:
	_diplomacy_queue.append({"title": title, "text": text, "buttons": buttons, "callback": callback})
	if _diplomacy_queue.size() == 1:
		_show_diplomacy_notices.call_deferred()


func _show_diplomacy_notices() -> void:
	while not _diplomacy_queue.is_empty():
		var notice: Dictionary = _diplomacy_queue[0]
		var choice: int = await hud.ask(notice["title"], notice["text"], notice["buttons"])
		var callback: Callable = notice["callback"]
		if callback.is_valid():
			callback.call(choice)
		if not _diplomacy_queue.is_empty():
			_diplomacy_queue.pop_front()
		hud.refresh_diplomacy()


# --- Salvar e carregar (ver SaveGame) ----------------------------------------

## F5 / L (ou F9): janela dos espaços de save. Salvar só na vez do humano, sem nada
## acontecendo; carregar também na tela de vitória.
## Salvar só na vez do humano, sem nada acontecendo e fora da tela de vitória.
func _can_save() -> bool:
	return not _is_busy and not game_over and not TurnManager.current_player().is_ai and not hud.save_dialog.visible


## Menu do jogo (canto de cima à esquerda): Salvar ou Carregar, como F5 e L.
func _on_game_menu(id: int) -> void:
	if id == Hud.MENU_SAVE and _can_save():
		_open_save_dialog(true)
	elif id == Hud.MENU_LOAD and not _is_busy and not hud.save_dialog.visible:
		_open_save_dialog(false)


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
	return {"turn_manager": TurnManager.to_dict(), "map_name": map_name, "map": game_map.to_dict(), "players": players_data,
			"diplomacy": diplomacy.to_dict(),
			"ruins": ruins_layer.to_dict()}


## Troca a partida atual pela de [param data] (de capture_state, já lida do
## arquivo) e continua a vez de quem estava jogando, sem processar o início do
## turno de novo (as cidades já tinham produzido quando o jogo foi salvo).
## Save de outro mapa (save antigo, sem "map_name": o mapa_teste): a cena é
## recarregada com o mapa dele e o save é carregado no _ready.
func restore_state(data: Dictionary) -> void:
	var saved_map: String = data.get("map_name", "mapa_teste")
	if saved_map != map_name:
		map_name = saved_map
		_pending_load = data
		get_tree().reload_current_scene.call_deferred()
		return
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
	fog.reset()
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
			mill.setup(player, SaveGame.json_to_cell(mill_data["cell"]), game_map, mill_data.get("mine", false))
			mill.progress = int(mill_data["progress"])
			mill.pillaged = mill_data.get("pillaged", false)
			cities_root.add_child(mill)
			player.lumber_mills.append(mill)
			mills.append(mill)
		for unit_data: Dictionary in player_data["units"]:
			var unit := Unit.new()
			var type_path: String = REPLACED_UNIT_TYPES.get(unit_data["type"], unit_data["type"])
			unit.setup(load(type_path), player, SaveGame.json_to_cell(unit_data["cell"]), game_map)
			unit.position = game_map.cell_to_world(unit.cell)
			unit.name = "%s_%s_%d" % [unit.type.display_name, player.id, player.units.size() + 1]
			units_root.add_child(unit)
			player.units.append(unit)
			unit.apply_dict(unit_data)
		# Quem estava embarcado volta para a Galé da mesma casa
		for i in player.units.size():
			if player_data["units"][i].get("aboard", false):
				for boat in player.units:
					if boat.cell == player.units[i].cell and boat.can_carry(player.units[i]):
						boat.board(player.units[i])
						break
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
	# Vila (ou maior) de um save que ainda não ganhou o território grande
	for city in cities():
		if city.has_large_territory() and not city.territory_expanded:
			expand_territory(city)
	TurnManager.restore(players, data["turn_manager"])
	# Save anterior à diplomacia: ninguém se conhece; os encontros acontecem de novo (em paz)
	diplomacy = Diplomacy.from_dict(data.get("diplomacy", {}))
	diplomacy.turn = TurnManager.turn_number
	Movement.diplomacy = diplomacy
	_diplomacy_queue.clear()
	_pending_audiences.clear()
	var current := TurnManager.current_player()
	print("Partida carregada: turno %d, vez do %s" % [TurnManager.turn_number, current.display_name])
	hud.set_turn(TurnManager.turn_number, current)
	if current.is_ai:
		_play_ai_turn(current)
	else:
		_start_human_turn(current, false)


# --- Montagem da partida e HUD ----------------------------------------------

## Unidades do início: todo jogador começa com um Colono na casa inicial do
## mapa ([param starts], na ordem dos jogadores) e um Trabalhador logo abaixo
## (só o Trabalhador faz fazendas, e a cidade de 1 habitante sem fazenda não
## cresce). Com WITH_TROOPS, também um Guerreiro, um Arqueiro e uma Cavalaria
## Leve em volta.
func _spawn_starting_units(starts: Array[Vector2i]) -> void:
	for i in players.size():
		_spawn_unit(SETTLER, players[i], starts[i])
		_spawn_unit(WORKER, players[i], free_cell_near(starts[i] + Vector2i(0, 1), 2))
		if WITH_TROOPS:
			for type in [WARRIOR, ARCHER, LIGHT_CAVALRY]:
				_spawn_unit(type, players[i], free_cell_near(starts[i], 3))


## Nome da próxima cidade de [param player]: o primeiro livre da lista da nação
## dele (Nation.DATA "cities"); acabando (ou sem nação), o primeiro livre de
## City.NAMES.
func _next_city_name(player: Player = null) -> String:
	var used := cities().map(func(city: City) -> String: return city.city_name)
	if player and player.nation >= 0:
		for city_name: String in Nation.DATA[player.nation]["cities"]:
			if not used.has(city_name):
				return city_name
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
	var site_city := territory_owner(unit.cell)
	var site: Dictionary = site_city.sites.get(unit.cell, {}) if site_city else {}
	if unit.type.can_build_farm and Terrain.can_farm(game_map.get_terrain(unit.cell)):
		var error := improvement_error(unit, City.Build.FARM)
		var resume: bool = site.get("build", -1) == City.Build.FARM
		actions.append({"id": "farm", "label": "Continuar fazenda [C]" if resume else "Construir fazenda [C]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"Fazenda de %s: %d turnos (o trabalhador fica na casa). Pronta, o cidadão que trabalha nela tira +%d de alimento (sem fazenda, +%d)." % [
						site_city.city_name, City.BUILDS[City.Build.FARM]["cost"] - site.get("progress", 0),
						site_city.farm_food(unit.cell), site_city.tile_food(unit.cell)]})
	var on_hill := game_map.get_terrain(unit.cell) == Terrain.Type.HILLS
	if unit.type.can_build_lumber_mill and on_hill and ruin_at(unit.cell) < 0 \
			and unit.owner_player.researched.has(Technology.Tech.IRON_WORKING): # destruída: botão Reconstruir
		var error := mine_error(unit)
		var remote := lumber_mill_at(unit.cell)
		actions.append({"id": "mine",
				"label": "Trabalhar na mina [M]" if remote else
					"Continuar mina [M]" if site.get("build", -1) == City.Build.MINE else "Construir mina [M]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"O trabalhador entra na mina e trabalha nela (até %d por mina)." % LumberMill.MAX_WORKERS if remote else
					"Mina de %s: %d turnos (o trabalhador fica na casa). Pronta, até %d cidadãos tiram %d de ferro por turno cada (o ferro não se esgota)." % [
						site_city.city_name, City.BUILDS[City.Build.MINE]["cost"] - site.get("progress", 0), City.MINE_MAX_WORKERS,
						City.IRON_PER_WORKER] if is_city_mill_site(unit) else
					"Mina remota nesta colina (%d de produção, 1 por trabalhador por turno). Pronta, cada trabalhador lá dentro tira %d de ferro por turno; ela não se esgota." % [
						LumberMill.cost(), City.IRON_PER_WORKER]})
	var existing := lumber_mill_at(unit.cell)
	if unit.type.can_build_lumber_mill and not on_hill and not (existing and existing.pillaged): # destruída: botão Reconstruir
		var error := lumber_mill_error(unit)
		var city_mill := is_city_mill_site(unit)
		actions.append({"id": "lumber_mill",
				"label": "Trabalhar na madeireira [M]" if existing else
					"Continuar madeireira [M]" if site.get("build", -1) == City.Build.LUMBER_MILL else "Construir madeireira [M]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"O trabalhador entra na madeireira e trabalha nela (até %d por madeireira)." % LumberMill.MAX_WORKERS if existing else
					"Madeireira de %s: %d turnos (o trabalhador fica na casa). Pronta, até %d cidadãos tiram 1 de madeira por turno cada." % [
						site_city.city_name, City.BUILDS[City.Build.LUMBER_MILL]["cost"] - site.get("progress", 0), LumberMill.MAX_WORKERS] if city_mill else
					"Madeireira remota nesta floresta (%d de produção, 1 por trabalhador por turno). Pronta, cada trabalhador tira 1 de madeira por turno." % LumberMill.cost()})
	if unit.type.can_build_lumber_mill and unit.owner_player.researched.has(Technology.Tech.CIVIL_ENGINEERING) \
			and not game_map.roads.has(unit.cell) and get_city_at(unit.cell) == null:
		var error := road_error(unit)
		actions.append({"id": "road",
				"label": "Continuar estrada [E]" if game_map.road_progress.has(unit.cell) else "Construir estrada [E]",
				"disabled": not error.is_empty(),
				"tooltip": error if not error.is_empty() else
					"Estrada: %d turnos (o trabalhador fica na casa). De estrada para estrada (ou cidade), andar custa meio movimento." % [
						GameMap.ROAD_COST - game_map.road_progress.get(unit.cell, 0)]})
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
					"Destrói a melhoria inimiga (%d movimento). Fazenda: +%d de energia. Madeireira ou mina: +%d de ouro. Quem trabalhava nela é executado." % [
						PILLAGE_COST, PILLAGE_FARM_ENERGY, PILLAGE_MILL_GOLD]})
	if not unit.cargo.is_empty():
		actions.append({"id": "unload", "label": "Desembarcar [U]",
				"tooltip": "Seleciona quem está a bordo (%s): clique numa casa de terra vizinha para desembarcar." %
					", ".join(unit.cargo.map(func(passenger: Unit) -> String: return passenger.type.display_name))})
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
	var title := "%s (%d, %d) - %d/%d trabalhadores" % [mill.display_name(), mill.cell.x, mill.cell.y, mill.workers.size(), LumberMill.MAX_WORKERS]
	hud.set_unit_actions(title, [{"id": "release_worker", "label": "Retirar trabalhador",
			"disabled": mill.workers.is_empty(),
			"tooltip": "Nenhum trabalhador na madeireira." if mill.workers.is_empty() else
				"O trabalhador sai da madeireira, volta ao mapa e fica selecionado."}])


func _spawn_unit(type: UnitType, player: Player, cell: Vector2i) -> void:
	if not Movement.can_stand(game_map, type, cell):
		push_warning("Unidade %s não criada: casa %s não é %s." % [type.display_name, cell, "água" if type.is_naval else "terra"])
		return
	var unit := Unit.new()
	unit.setup(type, player, cell, game_map)
	unit.position = game_map.cell_to_world(cell)
	unit.name = "%s_%s_%d" % [type.display_name, player.id, player.units.size() + 1]
	units_root.add_child(unit)
	player.units.append(unit)


func _show_damage(unit: Unit, amount: int, delay := 0.0) -> void:
	if not fog.is_visible_cell(unit.cell):
		return # combate longe da vista do humano
	var top := unit.position - Vector2(0, GameMap.TILE_SIZE / 2.0)
	FloatingText.spawn(units_root, top, "-%d" % amount, Color(1, 0.35, 0.3), delay)


## Painel inferior: casa sob o mouse e a unidade nela (ou a selecionada).
func _update_info() -> void:
	var lines: Array[String] = []
	var unit: Unit = null
	if game_map.is_in_bounds(_hover_cell) and not fog.is_explored(_hover_cell):
		lines.append("Casa (%d, %d): ainda não explorada" % [_hover_cell.x, _hover_cell.y])
	elif game_map.is_in_bounds(_hover_cell):
		lines.append("Casa (%d, %d): %s" % [_hover_cell.x, _hover_cell.y, _terrain_text(_hover_cell)])
		if not fog.is_visible_cell(_hover_cell):
			lines[-1] += " (fora da vista: o que está lá agora não aparece)"
		var owner_city := territory_owner(_hover_cell)
		if owner_city:
			lines[-1] += " - território de %s (%s)" % [owner_city.city_name, owner_city.owner_player.display_name]
		var city := known_city_at(_hover_cell)
		var mill := lumber_mill_at(_hover_cell)
		if city:
			var mood := city.mood()
			lines.append("Cidade %s (%s, %s) - População %d | Alimentos %d/%d (%+d por turno) | %d felizes, %d contentes, %d infelizes%s" % [
				city.city_name, city.owner_player.display_name, city.rank_text(), city.population,
				city.food_stock, city.food_capacity(), city.food_per_turn(),
				mood["happy"], mood["content"], mood["unhappy"],
				" - DESORDEM CIVIL" if city.is_in_disorder() else " - celebração" if city.is_celebrating() else "",
			])
		elif ruins_layer.cities.has(_hover_cell):
			lines.append("Ruínas de %s (cidade saqueada e destruída)" % ruins_layer.city_name_at(_hover_cell))
		elif ruins_layer.improvements.has(_hover_cell):
			lines.append("%s destruída, sem dono (uma cidade fundada perto fica com ela)" % City.BUILDS[ruins_layer.improvements[_hover_cell]["build"]]["name"])
		elif claiming_city(_hover_cell):
			lines.append(_city_improvement_text(claiming_city(_hover_cell), _hover_cell))
		elif owner_city and owner_city.worked_tiles.has(_hover_cell):
			lines.append("Trabalhada por um cidadão de %s - +%d alimento" % [owner_city.city_name, owner_city.tile_food(_hover_cell)])
		elif mill:
			lines.append("%s%s de %s - %s | %d/%d trabalhadores" % [
				mill.display_name(), " destruída" if mill.pillaged else "", mill.owner_player.display_name,
				("reconstrução %d/%d" if mill.pillaged else "em obra %d/%d") % [mill.progress, mill.cost()] if not mill.is_done() else
					"+%d de ferro por turno" % mill.iron_per_turn() if mill.is_mine else "+%d de madeira por turno" % mill.wood_per_turn(),
				mill.workers.size(), LumberMill.MAX_WORKERS,
			])
		var hovered := visible_unit_at(_hover_cell)
		if hovered and hovered != selected_unit:
			unit = hovered
	if unit:
		var defense_notes: Array[String] = []
		if unit.fortified:
			defense_notes.append("fortificada")
		if unit.terrain_defense_bonus() > 0:
			defense_notes.append("+%d %s" % [unit.terrain_defense_bonus(), Terrain.NAMES[game_map.get_terrain(unit.cell)].to_lower()])
		if unit.walls_defense_bonus() > 0:
			defense_notes.append("+%d muralha" % unit.walls_defense_bonus())
		lines.append("%s (%s) - Ataque %d%s | Defesa %d%s | Movimento %s/%d | Energia %d/%d" % [
			unit.type.display_name, unit.owner_player.display_name,
			unit.attack, " à distância (alcance %d)" % unit.type.attack_range if unit.is_ranged() else "", unit.defense, " (%s)" % ", ".join(defense_notes) if not defense_notes.is_empty() else "",
			unit.moves_text(), unit.movement, unit.energy, unit.max_energy,
		])
		if unit.has_goto():
			lines[-1] += " | Indo para (%d, %d)" % [unit.goto_target.x, unit.goto_target.y]
		if unit.type.cargo_capacity > 0:
			lines[-1] += " | A bordo %d/%d%s" % [unit.cargo.size(), unit.type.cargo_capacity,
					": " + ", ".join(unit.cargo.map(func(passenger: Unit) -> String: return passenger.type.display_name))
					if not unit.cargo.is_empty() else ""]
		if unit.transport:
			lines[-1] += " | Embarcada na Galé"
		if unit.rebuilding:
			var building_city := claiming_city(unit.cell)
			lines[-1] += " | Construindo estrada" if game_map.road_progress.has(unit.cell) else \
					" | Construindo" if building_city and building_city.sites.has(unit.cell) else " | Reconstruindo"
	var preview := ""
	if selected_unit and _attack_targets.has(_hover_cell):
		var defender := get_unit_at(_hover_cell)
		var from_cell: Vector2i = _attack_targets[_hover_cell] # de onde a unidade vai atacar
		var expected := Combat.expected_damage(selected_unit, defender, from_cell)
		var attack_note := ", +%d contra cavalaria" % Combat.anti_cavalry(selected_unit, defender) \
				if Combat.anti_cavalry(selected_unit, defender) > 0 else ""
		var target_notes := []
		if Combat.river_bonus(selected_unit, defender, from_cell) > 0:
			target_notes.append("+%d atrás do rio" % Terrain.RIVER_DEFENSE_BONUS)
		if Combat.anti_cavalry(defender, selected_unit) > 0:
			target_notes.append("+%d contra cavalaria" % Combat.anti_cavalry(defender, selected_unit))
		preview = ("%s: %s (força %.2f%s) x %s (força %.2f%s) - dano estimado: causa ~%d | recebe %s" % [
			"Disparar" if selected_unit.is_ranged() else "Atacar",
			selected_unit.type.display_name, Combat.attack_strength(selected_unit, defender), attack_note,
			defender.type.display_name, Combat.defense_strength(selected_unit, defender, from_cell),
			", " + ", ".join(target_notes) if not target_notes.is_empty() else "",
			roundi(expected["to_defender"]),
			"0" if selected_unit.is_ranged() else "~%d" % roundi(expected["to_attacker"]),
		])
	# Com unidade (ou madeireira) selecionada: o painel dela, e a linha de baixo
	# mostra a prévia do ataque, ou a unidade sob o mouse, ou a casa. Sem
	# seleção: o painel some e a barra de informação mostra a casa sob o mouse.
	if (selected_unit and is_instance_valid(selected_unit)) or _selected_mill:
		var extra := preview if not preview.is_empty() else lines[-1] if not lines.is_empty() else ""
		if selected_unit:
			hud.show_unit_panel(selected_unit, game_map, extra)
		else:
			hud.show_mill_panel(_selected_mill, game_map, extra)
		hud.set_info("")
	else:
		hud.hide_unit_panel()
		hud.set_info("\n".join(lines))


## Nome do terreno com as regras dele (madeira que resta, defesa, movimento).
func _terrain_text(cell: Vector2i) -> String:
	var type := game_map.get_terrain(cell)
	var text: String = Terrain.NAMES[type]
	if Terrain.has_wood(type):
		text += " (madeira %d/%d, defesa +%d, movimento -%d para quem anda mais de 1)" % [
			game_map.wood_left(cell), game_map.wood_total(cell), Terrain.DEFENSE_BONUS[type], Terrain.MOVE_PENALTY[type]]
	elif type == Terrain.Type.HILLS:
		text += " (defesa +%d, movimento -%d para quem anda mais de 1, sem fazenda)" % [
			Terrain.DEFENSE_BONUS[type], Terrain.MOVE_PENALTY[type]]
	elif type == Terrain.Type.MOUNTAINS:
		text += " (intransponível)"
	elif type == Terrain.Type.DESERT or type == Terrain.Type.TUNDRA:
		text += " (1 de alimento, sem fazenda)"
	elif type == Terrain.Type.SNOW:
		text += " (sem alimento, sem fazenda)"
	elif type == Terrain.Type.DEEP_WATER:
		text += " (a Galé afunda se ficar 2 turnos seguidos aqui)"
	if game_map.roads.has(cell):
		text += ", com estrada"
	elif game_map.road_progress.has(cell):
		text += ", estrada em obra %d/%d" % [game_map.road_progress[cell], GameMap.ROAD_COST]
	if game_map.has_iron(cell) and game_map.iron_visible:
		text += ", com FERRO (um Trabalhador pode fazer uma mina [M])"
	if game_map.has_river(cell):
		text += " à beira do rio (+%d de alimento)" % Terrain.RIVER_FOOD
	return text


## Fazenda, madeireira ou obra da cidade na casa.
func _city_improvement_text(city: City, cell: Vector2i) -> String:
	if city.sites.has(cell):
		var site: Dictionary = city.sites[cell]
		return "%s de %s (em obra pelo Trabalhador %d/%d)" % [
			City.BUILDS[site["build"]]["name"], city.city_name, site["progress"], City.BUILDS[site["build"]]["cost"]]
	if city.ruins.has(cell):
		var ruin: Dictionary = city.ruins[cell]
		return "%s destruída de %s - um Trabalhador pode reconstruir (%d/%d)" % [
			City.BUILDS[ruin["build"]]["name"], city.city_name, ruin["progress"], City.BUILDS[ruin["build"]]["cost"]]
	if city.lumber_mills.has(cell):
		return "Madeireira de %s - %d/%d trabalhadores" % [city.city_name, city.lumber_mills[cell], LumberMill.MAX_WORKERS]
	if city.mines.has(cell):
		return "Mina de %s - %d/%d trabalhadores (+%d de ferro por turno)" % [
			city.city_name, city.mines[cell], City.MINE_MAX_WORKERS, city.mines[cell] * City.IRON_PER_WORKER]
	return "Fazenda de %s - %s" % [city.city_name,
			"+%d alimento" % city.farm_food(cell) if city.farms[cell] > 0 else "sem trabalhador"]


## Painéis do topo (jogador humano): arsenal, ouro, madeira e ferro com o saldo
## por turno. O ferro só aparece no mapa depois que ele pesquisa Trabalho em Ferro.
func _update_resources() -> void:
	var player := TurnManager.current_player() if not TurnManager.current_player().is_ai else null
	for other in players:
		if player == null and not other.is_ai:
			player = other
	game_map.iron_visible = player != null and player.researched.has(Technology.Tech.IRON_WORKING)
	if player:
		hud.set_resources(player.gold, player.gold_per_turn(), player.wood, player.wood_per_turn(), player.iron, player.iron_per_turn())
		hud.set_science(player)
		var in_production := {}
		for weapon: Arsenal.Weapon in Arsenal.NAMES:
			in_production[weapon] = player.weapons_in_production(weapon)
		hud.set_arsenal(player.arsenal, in_production)
