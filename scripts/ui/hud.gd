class_name Hud
extends CanvasLayer

## Interface da partida: turno e jogador da vez (canto superior esquerdo),
## arsenal (armas estocadas), tesouro e recursos estratégicos (canto superior
## direito: ouro e madeira, com o saldo por turno), pedido de confirmação de fim
## de turno, informações da casa sob o mouse, botões de ação da unidade
## selecionada (canto inferior direito), mensagens rápidas (topo), a janela da
## cidade e a pergunta do nome da nova cidade.

## Botão de ação da unidade clicado; [param action_id] vem de set_unit_actions.
signal action_pressed(action_id: String)
## Clique no painel de Ciência: abrir a escolha da pesquisa.
signal research_pressed
## Botão "Árvore [T]" do painel de Ciência: abrir a árvore de tecnologias.
signal tech_tree_pressed

## Cores do HUD (fundo escuro sobre o mapa; as janelas de pedra têm as delas).
const WARNING_COLOR := Color(1, 0.6, 0.4)
const MUTED_COLOR := Color(0.75, 0.75, 0.75)
const POSITIVE_COLOR := Color(0.45, 1, 0.45)
const NEGATIVE_COLOR := Color(1, 0.4, 0.35)

## Tempo que uma mensagem fica na tela antes de sumir.
const MESSAGE_TIME := 3.0

@onready var _turn_label: Label = $TurnPanel/VBox/TurnRow/TurnLabel
@onready var _end_turn_label: Label = $TurnPanel/VBox/TurnRow/EndTurnLabel
@onready var _player_label: Label = $TurnPanel/VBox/PlayerLabel
@onready var _info_label: Label = $InfoPanel/VBox/InfoLabel
@onready var _victory_screen: Control = $VictoryScreen
@onready var _victory_label: Label = $VictoryScreen/Center/VBox/VictoryLabel
@onready var _action_panel: PanelContainer = $ActionPanel
@onready var _action_title: Label = $ActionPanel/VBox/ActionTitle
@onready var _action_buttons: HBoxContainer = $ActionPanel/VBox/ActionButtons
@onready var _message_label: Label = $MessageLabel
@onready var _weapons_box: VBoxContainer = $TopRight/ArsenalPanel/VBox/Weapons
@onready var _gold_icon: TextureRect = $TopRight/ResourcePanel/VBox/GoldRow/GoldIcon
@onready var _gold_label: RichTextLabel = $TopRight/ResourcePanel/VBox/GoldRow/GoldLabel
@onready var _wood_icon: Control = $TopRight/ResourcePanel/VBox/WoodRow/WoodIcon
@onready var _wood_label: RichTextLabel = $TopRight/ResourcePanel/VBox/WoodRow/WoodLabel
@onready var _iron_icon: Control = $TopRight/ResourcePanel/VBox/IronRow/IronIcon
@onready var _iron_label: RichTextLabel = $TopRight/ResourcePanel/VBox/IronRow/IronLabel
@onready var city_window: CityWindow = $CityWindow
@onready var city_name_dialog: CityNameDialog = $CityNameDialog
@onready var notice_dialog: NoticeDialog = $NoticeDialog
@onready var save_dialog: SaveDialog = $SaveDialog
@onready var invasion_dialog: InvasionDialog = $InvasionDialog
@onready var research_dialog: ResearchDialog = $ResearchDialog
@onready var tech_dialog: TechDialog = $TechDialog
## Árvore de tecnologias (criada pelo código, por cima das outras janelas).
var tech_tree_dialog: TechTreeDialog
## Ações da unidade selecionada (as mesmas dos botões), para o painel da unidade.
var last_actions: Array[Dictionary] = []
## Minimapa (canto esquerdo, abaixo do painel do turno; o Game chama setup).
var minimap: Minimap
var _minimap_panel: PanelContainer
## Painel da unidade selecionada (canto inferior esquerdo; no lugar das barras
## de informação e de ações desde 28/10/2026).
var unit_panel: UnitPanel

var _prompt_tween: Tween
var _message_tween: Tween
## Animação de "piscar" de cada número do painel de recursos: {Label: Tween}.
var _flash_tweens := {}
## Últimos valores mostrados (-1 = nenhum), para piscar quando mudam.
var _shown_gold := -1
var _shown_gold_rate := 0
var _shown_wood := -1
var _shown_wood_rate := 0
var _shown_iron := -1
var _shown_iron_rate := 0
## Linha de cada arma no painel Arsenal: {Arsenal.Weapon: RichTextLabel}.
var _weapon_labels := {}
var _shown_arsenal := {}
## Painel Ciência (ver _build_science_panel).
var _science_label: RichTextLabel
var _research_label: Label
var _research_bar: ProgressBar
var _shown_science := []


func _ready() -> void:
	_build_minimap()
	_build_unit_panel()
	tech_tree_dialog = TechTreeDialog.new()
	tech_tree_dialog.name = "TechTreeDialog"
	add_child(tech_tree_dialog)
	_gold_icon.texture = Icons.gold_coin(22)
	_gold_icon.tooltip_text = "Ouro do tesouro: compra unidades e prédios na hora. Vem dos impostos das Marcenarias sem armas na fila."
	_wood_icon.draw.connect(func() -> void:
		LumberMill.draw_icon(_wood_icon, Rect2(Vector2.ZERO, _wood_icon.size)))
	_wood_icon.tooltip_text = "Madeira: vem das madeireiras na floresta (1 por trabalhador por turno)."
	_iron_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_iron_icon.draw.connect(func() -> void:
		Icons.draw_iron(_iron_icon, Rect2(Vector2.ZERO, _iron_icon.size)))
	_iron_icon.tooltip_text = "Ferro: vem das minas nas colinas com ferro (1 por trabalhador por turno; a mina não se esgota)."
	_build_arsenal_rows()
	_build_science_panel()


## Painel da unidade, preso ao canto inferior esquerdo. A barra de ações antiga
## fica sempre escondida; a de informação só aparece sem unidade selecionada
## (a casa e a cidade sob o mouse), sem a linha de atalhos (as teclas estão
## nos botões).
func _build_unit_panel() -> void:
	unit_panel = UnitPanel.new()
	unit_panel.name = "UnitPanel"
	add_child(unit_panel)
	move_child(unit_panel, $InfoPanel.get_index() + 1)
	unit_panel.action_pressed.connect(func(id: String) -> void: action_pressed.emit(id))
	$ActionPanel.hide()
	$InfoPanel/VBox/HintLabel.hide()
	var place := func() -> void:
		unit_panel.position = Vector2(4.0, get_viewport().get_visible_rect().size.y - unit_panel.size.y - 4.0)
	get_viewport().size_changed.connect(place)
	place.call()


func show_unit_panel(unit: Unit, map: GameMap, extra: String) -> void:
	unit_panel.show_unit(unit, map, extra)
	$InfoPanel.hide()


func show_mill_panel(mill: LumberMill, map: GameMap, extra: String) -> void:
	unit_panel.show_mill(mill, map, extra)
	$InfoPanel.hide()


func hide_unit_panel() -> void:
	unit_panel.hide()


## Painel do minimapa, logo abaixo do painel do turno (acompanha a altura dele).
func _build_minimap() -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.name = "MinimapPanel"
	var style: StyleBoxFlat = $TurnPanel.get_theme_stylebox("panel").duplicate()
	style.set_content_margin_all(5)
	_minimap_panel.add_theme_stylebox_override("panel", style)
	add_child(_minimap_panel)
	move_child(_minimap_panel, $TurnPanel.get_index() + 1)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	_minimap_panel.add_child(minimap)
	var place := func() -> void:
		_minimap_panel.position = Vector2($TurnPanel.position.x, $TurnPanel.position.y + $TurnPanel.size.y + 8.0)
	$TurnPanel.resized.connect(place)
	place.call()


## Uma linha por arma no painel Arsenal: ícone + "Lanças N".
func _build_arsenal_rows() -> void:
	for weapon: Arsenal.Weapon in Arsenal.NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_weapons_box.add_child(row)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.draw.connect(func() -> void: Icons.draw_weapon(icon, weapon, Rect2(Vector2.ZERO, icon.size)))
		var maker := ""
		for build: int in City.BUILDS:
			if City.BUILDS[build].get("weapon", -1) == weapon:
				maker = City.BUILDS[City.BUILDS[build]["requires"]]["name"]
		icon.tooltip_text = "%s: feitas na %s; usadas para treinar tropas." % [Arsenal.PLURAL_NAMES[weapon], maker]
		row.add_child(icon)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 170
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.add_theme_font_size_override("normal_font_size", 18)
		row.add_child(label)
		_weapon_labels[weapon] = label


## Painel Ciência (à esquerda do Arsenal): ciência por turno e a pesquisa em
## andamento com a barra de progresso. Clicar nele abre a escolha da pesquisa.
func _build_science_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SciencePanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", $TopRight/ArsenalPanel.get_theme_stylebox("panel"))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = "Ciência: as Prefeituras geram pontos que vão para a pesquisa escolhida (não se acumulam). Clique para escolher ou trocar a pesquisa."
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			research_pressed.emit())
	$TopRight.add_child(panel)
	$TopRight.move_child(panel, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_row)
	var title := Label.new()
	title.text = "Ciência"
	title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	# Botão da árvore de tecnologias (o resto do painel abre a escolha da pesquisa)
	var tree_button := Button.new()
	tree_button.text = "Árvore [T]"
	tree_button.focus_mode = Control.FOCUS_NONE
	tree_button.add_theme_font_size_override("font_size", 12)
	tree_button.tooltip_text = "Árvore de tecnologias: o que já foi pesquisado e o que ainda falta."
	tree_button.pressed.connect(func() -> void: tech_tree_pressed.emit())
	title_row.add_child(tree_button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: Icons.draw_science(icon, Rect2(Vector2.ZERO, icon.size)))
	row.add_child(icon)
	_science_label = RichTextLabel.new()
	_science_label.bbcode_enabled = true
	_science_label.fit_content = true
	_science_label.scroll_active = false
	_science_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_science_label.custom_minimum_size.x = 200
	_science_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_science_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_science_label.add_theme_font_size_override("normal_font_size", 18)
	row.add_child(_science_label)
	_research_label = Label.new()
	_research_label.add_theme_font_size_override("font_size", 13)
	_research_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_research_label)
	_research_bar = ProgressBar.new()
	_research_bar.show_percentage = false
	_research_bar.custom_minimum_size = Vector2(0, 8)
	_research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.3, 0.3, 0.33)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Icons.SCIENCE_COLOR
	_research_bar.add_theme_stylebox_override("background", background)
	_research_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_research_bar)


## Painel Ciência: "+N por turno" e a pesquisa (nome, progresso/custo, turnos e
## barra). Sem pesquisa, avisa em laranja que os pontos estão se perdendo.
func set_science(player: Player) -> void:
	var per_turn := player.science_per_turn()
	var key := [per_turn, player.research, player.research_progress.get(player.research, 0)]
	if key == _shown_science:
		return
	_shown_science = key
	_science_label.text = "[color=#%s]%+d[/color] por turno" % [_rate_color(per_turn).to_html(false), per_turn]
	if player.research < 0:
		_research_label.text = "Sem pesquisa: clique para escolher"
		_research_label.add_theme_color_override("font_color", WARNING_COLOR)
		_research_bar.visible = false
		return
	var done: int = player.research_progress.get(player.research, 0)
	var turns := player.research_turns()
	_research_label.text = "%s  %d/%d%s" % [Technology.tech_name(player.research), done, Technology.cost(player.research),
			"  (%d t)" % turns if turns > 0 else ""]
	_research_label.add_theme_color_override("font_color", Color.WHITE)
	_research_bar.visible = true
	_research_bar.max_value = Technology.cost(player.research)
	_research_bar.value = done


## Painel Arsenal: armas estocadas e quantas estão em produção. Pisca quando
## o estoque muda.
func set_arsenal(arsenal: Dictionary, in_production: Dictionary) -> void:
	for weapon: Arsenal.Weapon in _weapon_labels:
		var amount: int = arsenal.get(weapon, 0)
		var making: int = in_production.get(weapon, 0)
		var key := Vector2i(amount, making)
		if _shown_arsenal.get(weapon) == key:
			continue
		var label: RichTextLabel = _weapon_labels[weapon]
		label.text = "%s [b]%d[/b]%s" % [Arsenal.PLURAL_NAMES[weapon], amount,
				"   [color=#%s](+%d em produção)[/color]" % [MUTED_COLOR.to_html(false), making] if making > 0 else ""]
		label.tooltip_text = "Estoque de %s no arsenal e quantas estão na fila das Marcenarias." % Arsenal.PLURAL_NAMES[weapon].to_lower()
		if _shown_arsenal.has(weapon) and _shown_arsenal[weapon].x != amount:
			_flash(label, amount > _shown_arsenal[weapon].x)
		_shown_arsenal[weapon] = key


## Painel do canto superior direito: tesouro (ouro) e recursos estratégicos
## (madeira e ferro), com quanto entra por turno. Quando um número muda, ele
## pisca (verde se subiu, vermelho se caiu).
func set_resources(gold: int, gold_per_turn: int, wood: int, wood_per_turn: int, iron: int, iron_per_turn: int) -> void:
	if gold != _shown_gold or gold_per_turn != _shown_gold_rate:
		_gold_label.text = "Ouro [b][color=#%s]%d[/color][/b]   [color=#%s]%+d por turno[/color]" % [
			Icons.GOLD_COLOR.to_html(false), gold, _rate_color(gold_per_turn).to_html(false), gold_per_turn]
		_gold_label.tooltip_text = "Tesouro do jogador e quanto entra no início do seu próximo turno."
		if _shown_gold >= 0 and gold != _shown_gold:
			_flash(_gold_label, gold > _shown_gold)
		_shown_gold = gold
		_shown_gold_rate = gold_per_turn
	if wood != _shown_wood or wood_per_turn != _shown_wood_rate:
		_wood_label.text = "Madeira [b]%d[/b]   [color=#%s]%+d por turno[/color]" % [wood, _rate_color(wood_per_turn).to_html(false), wood_per_turn]
		_wood_label.tooltip_text = "Estoque de madeira e quanto entra no início do seu próximo turno."
		if _shown_wood >= 0 and wood != _shown_wood:
			_flash(_wood_label, wood > _shown_wood)
		_shown_wood = wood
		_shown_wood_rate = wood_per_turn
	if iron != _shown_iron or iron_per_turn != _shown_iron_rate:
		_iron_label.text = "Ferro [b]%d[/b]   [color=#%s]%+d por turno[/color]" % [iron, _rate_color(iron_per_turn).to_html(false), iron_per_turn]
		_iron_label.tooltip_text = "Estoque de ferro e quanto entra no início do seu próximo turno."
		if _shown_iron >= 0 and iron != _shown_iron:
			_flash(_iron_label, iron > _shown_iron)
		_shown_iron = iron
		_shown_iron_rate = iron_per_turn


func _rate_color(rate: int) -> Color:
	return POSITIVE_COLOR if rate > 0 else NEGATIVE_COLOR if rate < 0 else MUTED_COLOR


## O número pisca em verde (subiu) ou vermelho (caiu) e volta ao normal.
func _flash(label: Control, increased: bool) -> void:
	if _flash_tweens.has(label):
		_flash_tweens[label].kill()
	label.modulate = POSITIVE_COLOR if increased else NEGATIVE_COLOR
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 1.2)
	_flash_tweens[label] = tween


func set_turn(turn_number: int, player: Player) -> void:
	_turn_label.text = "Turno %d" % turn_number
	_player_label.text = "Vez do %s%s" % [player.display_name, " (máquina)" if player.is_ai else ""]
	_player_label.add_theme_color_override("font_color", player.color)
	show_end_turn_prompt(false)


## Mostra/esconde o "Finalizar turno?" ao lado do turno, piscando suavemente.
func show_end_turn_prompt(visible_prompt: bool) -> void:
	if _prompt_tween:
		_prompt_tween.kill()
		_prompt_tween = null
	_end_turn_label.visible = visible_prompt
	_end_turn_label.modulate.a = 1.0
	if visible_prompt:
		_prompt_tween = create_tween().set_loops()
		_prompt_tween.tween_property(_end_turn_label, "modulate:a", 0.4, 0.6)
		_prompt_tween.tween_property(_end_turn_label, "modulate:a", 1.0, 0.6)


## Tela de fim de jogo por cima de tudo, com o nome do vencedor na cor dele.
func show_victory(winner: Player) -> void:
	_victory_label.text = "%s venceu!" % winner.display_name
	_victory_label.add_theme_color_override("font_color", winner.color)
	_victory_screen.modulate.a = 0.0
	_victory_screen.show()
	create_tween().tween_property(_victory_screen, "modulate:a", 1.0, 0.5)


## Esconde a tela de fim de jogo (ao carregar uma partida salva).
func hide_victory() -> void:
	_victory_screen.hide()


func set_info(text: String) -> void:
	_info_label.text = text
	_info_label.visible = not text.is_empty()
	$InfoPanel.visible = not text.is_empty()


## Mostra os botões de ação da unidade selecionada. Cada ação é um dicionário
## {"id", "label", "disabled" (opcional), "tooltip" (opcional)}. Lista vazia esconde.
func set_unit_actions(title: String, actions: Array[Dictionary]) -> void:
	last_actions = actions
	for child in _action_buttons.get_children():
		_action_buttons.remove_child(child)
		child.queue_free()
	_action_panel.visible = false # substituída pelos botões do painel da unidade
	unit_panel.set_actions(actions)
	_action_title.text = title
	for action in actions:
		var button := Button.new()
		button.text = action["label"]
		button.disabled = action.get("disabled", false)
		button.tooltip_text = action.get("tooltip", "")
		# Sem foco: Espaço/Enter continuam indo para o jogo, não para o botão
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(action_pressed.emit.bind(action["id"]))
		_action_buttons.add_child(button)
	# Volta ao tamanho mínimo, crescendo a partir do canto inferior direito
	_action_panel.offset_left = _action_panel.offset_right
	_action_panel.offset_top = _action_panel.offset_bottom


## Mensagem rápida no topo da tela, que some sozinha (ex.: "Aurora cresceu").
func show_message(text: String, color := Color.WHITE) -> void:
	if _message_tween:
		_message_tween.kill()
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)
	_message_label.offset_bottom = _message_label.offset_top
	_message_label.modulate.a = 1.0
	_message_label.show()
	_message_tween = create_tween()
	_message_tween.tween_interval(MESSAGE_TIME)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.6)
	_message_tween.tween_callback(_message_label.hide)
