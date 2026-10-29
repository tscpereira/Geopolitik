class_name CityWindow
extends Control

## Janela da cidade, aberta ao clicar numa cidade.
##   esquerda: mapa da área de trabalho (CityMapView). Clicar numa fazenda põe
##             ou tira o cidadão dela; as setas da madeireira põem ou tiram
##             cidadãos (até 2);
##   direita : resumo (população, alimentos, produção), botão "Construir",
##             prédios da cidade (com as unidades que cada um produz e os
##             trabalhadores dele), obras em andamento (prédios, com barra de
##             progresso + trabalhadores), melhorias em obra (as que os
##             Trabalhadores estão fazendo e as ruínas) e unidades na
##             cidade. Fazendas e madeireiras prontas aparecem só no mapa.
## "Construir" abre uma lista (modal) com o que a cidade pode construir,
## dividida em Unidades, Armas e Prédios. O botão da moeda compra na hora com
## ouro. Prédios prontos somem da lista. Unidades entram na fila do prédio que
## as produz; prédios entram nas obras. Fazendas e madeireiras não estão na
## lista: quem as faz é o Trabalhador, no mapa.
## Esc fecha a lista ou a janela, nessa ordem.
## A cidade de outro jogador abre só para observar: nenhum botão de ordem funciona.

signal closed

## Cores das janelas de pedra (desde 28/10/2026: mármore claro, texto escuro;
## ver StoneStyle). O HUD do mapa, escuro, tem as suas (Hud).
const SECTION_COLOR := StoneStyle.BRONZE
const MUTED_COLOR := StoneStyle.INK_MUTED
const WARNING_COLOR := StoneStyle.WARNING
const POSITIVE_COLOR := StoneStyle.POSITIVE
const NEGATIVE_COLOR := StoneStyle.NEGATIVE
## Obra parada por falta de mão de obra: explicação (a vala da barra fica avermelhada).
const NEEDS_WORKERS_TIP := "Ninguém está trabalhando nesta obra, então ela não avança. Use + para alocar cidadãos livres; se não houver, tire alguns das fazendas e madeireiras (clique no mapa da cidade) ou dos impostos (botão -)."
const RIGHT_COLUMN_WIDTH := 620
## Largura do controle "- N trab. +" (para alinhar o X das linhas sem ele).
const WORKER_CONTROLS_WIDTH := 124
## Altura da lista de construções (o resto aparece rolando).
const BUILD_LIST_HEIGHT := 380
## Tamanho da moeda de ouro nos botões de compra.
const COIN_SIZE := 20
const BUY_BUTTON_WIDTH := 80
## Coluna do custo na lista "Construir" (textos maiores quebram a linha).
const COST_COLUMN_WIDTH := 310
## Ícones das construções (Icons.build_icon): na lista "Construir" e o recuo
## das unidades embaixo do prédio, na janela da cidade.
const BUILD_LIST_ICON_SIZE := 28
const UNIT_INDENT := 18
## Letras por linha nos tooltips (as descrições cabem em até 3 linhas).
const TOOLTIP_WIDTH := 50

var _city: City
var _game: Game
## Cidade de outro jogador: só observação.
var _read_only := false
var _refresh_queued := false

var _title: Label
var _summary: RichTextLabel
var _food_bar: ProgressBar
var _food_bar_label: Label
var _hint: Label
var _map_view: CityMapView
var _build_box: VBoxContainer
var _mood_box: VBoxContainer
var _constructions_box: VBoxContainer
var _farms_box: VBoxContainer
var _buildings_box: VBoxContainer
var _units_box: VBoxContainer
var _build_modal: Control
var _build_list: VBoxContainer
var _treasury_label: Label


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	_build_modal_layout()


func open(city: City, game: Game, read_only := false) -> void:
	_city = city
	_game = game
	_read_only = read_only
	_build_modal.hide()
	_city.changed.connect(_queue_refresh)
	_map_view.editable = not read_only
	_map_view.setup(city, game)
	_refresh()
	show()


func close() -> void:
	if _city and _city.changed.is_connected(_queue_refresh):
		_city.changed.disconnect(_queue_refresh)
	_city = null
	_build_modal.hide()
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _build_modal.visible:
			_build_modal.hide()
		else:
			close()
		get_viewport().set_input_as_handled()


## Clique numa fazenda ou nas setas de uma madeireira ou mina do mapa da cidade: põe
## ([param delta] = +1) ou tira (-1) um cidadão. Sem ninguém livre para pôr, avisa.
func _on_workers_requested(cell: Vector2i, delta: int) -> void:
	if _read_only:
		return
	if delta > 0 and _city.free_citizens() <= 0:
		_game.hud.show_message("Nenhum cidadão livre em %s: tire alguém de outra fazenda, madeireira, mina, obra ou dos impostos." % _city.city_name,
				WARNING_COLOR)
		return
	if _city.farms.has(cell):
		_city.set_farm_worked(cell, delta > 0)
	elif _city.lumber_mills.has(cell):
		_city.set_mill_workers(cell, _city.lumber_mills[cell] + delta)
	elif _city.mines.has(cell):
		_city.set_mine_workers(cell, _city.mines[cell] + delta)
	else:
		_city.set_tile_worked(cell, delta > 0)


## Clique numa casa vermelha do mapa da cidade: ela passa de outra cidade do
## jogador para esta (Game.transfer_cell), com a melhoria.
func _on_cell_claimed(cell: Vector2i) -> void:
	if _read_only:
		return
	var previous: City = _game.transfer_cell(_city, cell)
	_game.hud.show_message("Casa (%d, %d) passou de %s para %s." % [cell.x, cell.y, previous.city_name, _city.city_name],
			Color(0.75, 1, 0.75))
	_queue_refresh()


## Se alguma casa do raio de ação é de outra cidade do jogador (vermelha).
func _has_transferable() -> bool:
	if _read_only:
		return false
	for offset in City.territory_offsets(_city.is_capital):
		if _game.transfer_error(_city, _city.cell + offset).is_empty():
			return true
	return false


## Fundo dos painéis das janelas: mármore com chanfro de lápide (StonePanelBox).
## Usado por todas as janelas, que também recebem o tema de pedra (StoneStyle.theme).
static func make_panel_style() -> StyleBox:
	return StonePanelBox.new()


# --- Montagem da janela -----------------------------------------------------

func _build_layout() -> void:
	var root := _add_centered_panel(self)

	# Cabeçalho: nome da cidade e botão de fechar
	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_make_button("Fechar [Esc]", close))
	root.add_child(StoneStyle.separator())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)

	# Esquerda: mapa da cidade
	var left := VBoxContainer.new()
	body.add_child(left)
	left.add_child(_make_section("Mapa da cidade"))
	_map_view = CityMapView.new()
	_map_view.cell_claimed.connect(_on_cell_claimed)
	_map_view.workers_requested.connect(_on_workers_requested)
	left.add_child(_map_view)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = CityMapView.CELL_SIZE * 5
	_hint.add_theme_color_override("font_color", MUTED_COLOR)
	_hint.add_theme_font_size_override("font_size", 13)
	left.add_child(_hint)

	# Direita: resumo, construir, obras e produção da cidade (com rolagem)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH, CityMapView.CELL_SIZE * 5 + 60)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	scroll.add_child(right)

	right.add_child(_make_section("Resumo"))
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	right.add_child(_summary)
	# Barra do estoque de alimentos: quando enche, a cidade cresce
	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 8)
	right.add_child(food_row)
	var food_title := Label.new()
	food_title.text = "Estoque"
	food_row.add_child(food_title)
	_food_bar = ProgressBar.new()
	_food_bar.show_percentage = false
	_food_bar.custom_minimum_size = Vector2(0, 18)
	_food_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_food_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	StoneStyle.style_progress(_food_bar, City.FOOD_BAR_COLOR)
	food_row.add_child(_food_bar)
	_food_bar_label = Label.new()
	_food_bar_label.custom_minimum_size.x = 70
	food_row.add_child(_food_bar_label)
	_add_carved_section(right, "Bem-estar social")
	_mood_box = VBoxContainer.new()
	right.add_child(_mood_box)
	_build_box = VBoxContainer.new()
	right.add_child(_build_box)
	_add_carved_section(right, "Prédios da cidade")
	_buildings_box = VBoxContainer.new()
	right.add_child(_buildings_box)
	_add_carved_section(right, "Obras em andamento")
	_constructions_box = VBoxContainer.new()
	right.add_child(_constructions_box)
	_add_carved_section(right, "Melhorias em obra")
	_farms_box = VBoxContainer.new()
	right.add_child(_farms_box)
	_add_carved_section(right, "Unidades na cidade")
	_units_box = VBoxContainer.new()
	right.add_child(_units_box)


## Lista de construções, por cima da janela da cidade.
func _build_modal_layout() -> void:
	_build_modal = Control.new()
	_build_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_modal.hide()
	add_child(_build_modal)

	var root := _add_centered_panel(_build_modal)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Construir"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", SECTION_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# Tesouro do jogador, para comparar com os preços em ouro
	header.add_theme_constant_override("separation", 12)
	var coin := TextureRect.new()
	coin.texture = Icons.gold_coin(COIN_SIZE)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	header.add_child(coin)
	_treasury_label = Label.new()
	_treasury_label.add_theme_color_override("font_color", Icons.GOLD_COLOR)
	header.add_child(_treasury_label)
	header.add_child(_make_button("Cancelar [Esc]", _build_modal.hide))
	root.add_child(StoneStyle.separator())
	# Com rolagem, para quando a lista crescer além da tela
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, BUILD_LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_build_list = VBoxContainer.new()
	_build_list.add_theme_constant_override("separation", 12)
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_build_list)


## Fundo escurecido + painel centralizado; retorna a coluna de conteúdo.
func _add_centered_panel(parent: Control) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_panel_style())
	panel.theme = StoneStyle.theme()
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	return root


# --- Atualização ------------------------------------------------------------

## Atualiza no fim do quadro: os botões da janela são recriados, e um botão não
## pode ser removido no meio do próprio clique.
func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	if _city == null:
		return
	_title.text = "%s  (%s, %s)%s" % [_city.city_name, _city.owner_player.display_name, _city.rank_text(),
			"  - observando" if _read_only else ""]
	_title.add_theme_color_override("font_color", _city.owner_player.color)
	_summary.text = _summary_text()
	_food_bar.max_value = _city.food_capacity()
	_food_bar.value = _city.food_stock
	_food_bar_label.text = "%d/%d" % [_city.food_stock, _city.food_capacity()]
	_food_bar.tooltip_text = "Estoque de alimentos. Cheio, a cidade ganha 1 de população. Tamanho = (população + 1) x %d." % City.FOOD_BOX_PER_SIZE
	_rebuild_units()
	_hint.text = ("Cidade de outro jogador: você pode observar, mas não dar ordens. Passe o mouse sobre uma casa para ver detalhes."
			if _read_only else
			"Clique numa casa do território para pôr ou tirar o cidadão (sem melhoria: +2 de alimento na pradaria, +1 nas outras; a fazenda soma +1); nas madeireiras e minas, use as setas. Os números brancos indicam os cidadãos trabalhando ali. Fazendas, madeireiras e minas novas são feitas por Trabalhadores, no mapa."
			+ (" Casas em vermelho são de outra cidade sua: clique para trazê-las." if _has_transferable() else ""))
	_rebuild_mood()
	_rebuild_build_button()
	_rebuild_constructions()
	_rebuild_farms()
	_rebuild_buildings()
	if _build_modal.visible:
		_rebuild_build_list()
	_map_view.queue_redraw()


func _summary_text() -> String:
	var lines: Array[String] = []
	lines.append("População: %d   (livres: %d)" % [_city.population, _city.free_citizens()])
	var food := _city.food_per_turn()
	var growth := _city.turns_to_grow()
	# Saldo de alimento colorido: verde sobrando, vermelho faltando
	var food_color := POSITIVE_COLOR if food > 0 else NEGATIVE_COLOR if food < 0 else StoneStyle.INK
	lines.append("Estoque de alimentos: %d/%d   [color=#%s]%+d[/color] por turno%s" % [
		_city.food_stock, _city.food_capacity(), food_color.to_html(false), food,
		("   (cresce em %d %s)" % [growth, "turno" if growth == 1 else "turnos"]) if growth > 0 else "",
	])
	if not _city.lumber_mills.is_empty():
		lines.append("Madeira: [color=#%s]+%d[/color] por turno   (%d em madeireiras)" % [
			LumberMill.WOOD_BAR_COLOR.to_html(false), _city.wood_per_turn(), _city.mill_workers(),
		])
	if not _city.mines.is_empty():
		lines.append("Ferro: [color=#%s]+%d[/color] por turno   (%d em minas)" % [
			Icons.IRON_COLOR.to_html(false), _city.iron_per_turn(), _city.mine_workers(),
		])
	if _city.gold_per_turn() > 0:
		lines.append("Ouro: [color=#%s]+%d[/color] por turno   (impostos e comércio)" % [
			Icons.GOLD_COLOR.to_html(false), _city.gold_per_turn(),
		])
	if _city.science_per_turn() > 0:
		lines.append("Ciência: [color=#%s]+%d[/color] por turno   (Prefeitura, Escola e Biblioteca)" % [
			StoneStyle.SCIENCE.to_html(false), _city.science_per_turn(),
		])
	lines.append("Produção (força de trabalho): %d por turno   (%d em obras e prédios)" % [
		_city.production, _city.construction_workers(),
	])
	if food < 0:
		lines.append("[color=#%s]Atenção: a cidade está consumindo mais alimento do que produz![/color]" % NEGATIVE_COLOR.to_html(false))
	var stalled := _city.stalled_count()
	if stalled > 0:
		lines.append("[color=#%s]%d %s sem mão de obra: aloque cidadãos com + (veja as linhas em vermelho).[/color]" % [
			NEGATIVE_COLOR.to_html(false), stalled, "obra parada" if stalled == 1 else "obras paradas"])
	if _city.population <= 0:
		lines.append("[color=#%s]Cidade vazia: não produz nem cresce. Um Trabalhador de outra cidade pode migrar para ela (tecla J).[/color]" % NEGATIVE_COLOR.to_html(false))
	if not _city.ruins.is_empty():
		lines.append("[color=#%s]%d %s pela pilhagem: um Trabalhador pode reconstruir (tecla R).[/color]" % [
			WARNING_COLOR.to_html(false), _city.ruins.size(), "melhoria destruída" if _city.ruins.size() == 1 else "melhorias destruídas"])
	return "\n".join(lines)


## Seção "Bem-estar social": um rosto por cidadão (felizes, contentes e
## infelizes), a situação (desordem civil, celebração ou em ordem), de onde
## vem cada coisa e a linha das festividades (cidadãos que geram alegria).
func _rebuild_mood() -> void:
	_clear(_mood_box)
	if _city.population <= 0:
		_mood_box.add_child(_make_muted("Cidade vazia."))
		return
	var mood := _city.mood()
	var faces_row := HBoxContainer.new()
	faces_row.add_theme_constant_override("separation", 10)
	_mood_box.add_child(faces_row)
	var faces := Control.new()
	# Rostos menores numa cidade grande, para caberem na coluna
	var face_size := clampf(340.0 / _city.population - 4.0, 8.0, 22.0)
	faces.custom_minimum_size = Vector2(face_size * _city.population + 4 * (_city.population - 1), face_size)
	faces.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	faces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var order: Array = []
	for i in mood["happy"]:
		order.append(City.Mood.HAPPY)
	for i in mood["content"]:
		order.append(City.Mood.CONTENT)
	for i in mood["unhappy"]:
		order.append(City.Mood.UNHAPPY)
	faces.draw.connect(func() -> void:
		for i in order.size():
			Icons.draw_face(faces, Vector2(face_size / 2.0 + i * (face_size + 4), face_size / 2.0), face_size / 2.0 - 2.0, order[i]))
	faces_row.add_child(faces)
	var counts := RichTextLabel.new()
	counts.bbcode_enabled = true
	counts.fit_content = true
	counts.scroll_active = false
	counts.autowrap_mode = TextServer.AUTOWRAP_OFF
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.text = "[color=#%s]%d felizes[/color]  [color=#%s]%d contentes[/color]  [color=#%s]%d infelizes[/color]" % [
		StoneStyle.BRONZE.to_html(false), mood["happy"], StoneStyle.INK.to_html(false), mood["content"],
		NEGATIVE_COLOR.to_html(false), mood["unhappy"]]
	faces_row.add_child(counts)

	var status := RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.scroll_active = false
	if _city.is_in_disorder():
		status.text = "[color=#%s]DESORDEM CIVIL: a maioria da cidade está infeliz. A cidade não avança obras nem rende ouro ou ciência. Ponha cidadãos nas festividades, fortifique soldados na cidade ou construa um Templo.[/color]" % NEGATIVE_COLOR.to_html(false)
	elif _city.is_celebrating():
		status.text = "[color=#%s]CELEBRAÇÃO: nenhum infeliz e pelo menos metade feliz. +%d de alimento por turno (+%d por feliz).[/color]" % [
			StoneStyle.BRONZE.to_html(false), _city.celebration_food(), City.CELEBRATION_FOOD_PER_HAPPY]
	else:
		var margin := _city.unrest_margin()
		status.text = "[color=#%s]Em ordem.[/color] %s Desordem: mais da metade infeliz (cada feliz compensa um infeliz). Celebração: nenhum infeliz e metade feliz (%d+ de população)." % [
			POSITIVE_COLOR.to_html(false),
			"[color=#%s]No limite: mais um infeliz e a cidade entra em desordem.[/color]" % NEGATIVE_COLOR.to_html(false) if margin == 0
				else "Aguenta mais %d infeliz%s." % [margin, "es" if margin > 1 else ""],
			City.CELEBRATION_MIN_POPULATION]
	_mood_box.add_child(status)
	var details := _make_muted("    " + "\n    ".join(_city.mood_details()))
	details.add_theme_font_size_override("font_size", 13)
	_mood_box.add_child(details)

	# Festividades: cada cidadão gera FESTIVAL_JOY pontos de alegria
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = wrap_tooltip("Cidadãos que organizam festas e jogos: cada um gera +%d de alegria. Cada ponto de alegria torna um infeliz contente ou, sem infelizes, um contente feliz." % City.FESTIVAL_JOY)
	_mood_box.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * Icons.ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: Icons.draw_face(icon, icon.size / 2.0, icon.size.x / 2.0 - 2.0, City.Mood.HAPPY))
	row.add_child(icon)
	var label := Label.new()
	label.text = "Festividades"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var joy := Label.new()
	joy.text = "+%d alegria" % _city.festival_joy()
	joy.custom_minimum_size.x = 120
	joy.add_theme_color_override("font_color", StoneStyle.BRONZE if _city.festival_workers > 0 else MUTED_COLOR)
	row.add_child(joy)
	_add_worker_controls(row, _city.festival_workers, _city.festival_workers + _city.free_citizens(), _city.set_festival_workers)
	var x_space := Control.new()
	x_space.custom_minimum_size.x = 30 # alinha com o X das outras linhas
	row.add_child(x_space)


## Botão "Construir".
func _rebuild_build_button() -> void:
	_clear(_build_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_build_box.add_child(row)
	var button := _make_button("Construir...", _open_build_modal)
	button.custom_minimum_size.x = 160
	button.disabled = _read_only
	row.add_child(button)


func _open_build_modal() -> void:
	_rebuild_build_list()
	_build_modal.show()


## Lista dividida em classes (Unidades, Armas, Prédios). Cada linha: nome,
## custo em produção, "Escolher" (vai para as obras) e o botão da moeda
## (compra na hora com ouro). A descrição aparece no tooltip.
func _rebuild_build_list() -> void:
	_clear(_build_list)
	_treasury_label.text = "Tesouro: %d" % _city.owner_player.gold
	for category: int in City.CATEGORY_NAMES:
		# Melhorias de terreno são feitas pelo Trabalhador: a classe nem aparece
		if City.BUILDS.values().all(func(info: Dictionary) -> bool: return info["category"] != category or info["on_tile"]):
			continue
		_build_list.add_child(_make_section(City.CATEGORY_NAMES[category]))
		# Prédios prontos (e os que toda cidade já tem) somem da lista, e o que
		# depende de uma tecnologia ainda não pesquisada nem aparece
		var builds := City.BUILDS.keys().filter(func(build: int) -> bool:
			return (City.BUILDS[build]["category"] == category and not City.BUILDS[build]["on_tile"]
					and not City.BUILDS[build].get("native", false) and not _city.has_building(build)
					and _city.has_tech_for(build)))
		if builds.is_empty():
			_build_list.add_child(_make_muted("Nenhum disponível ainda."))
		for build: int in builds:
			_build_list.add_child(_make_build_row(build))


func _make_build_row(build: int) -> HBoxContainer:
	var info: Dictionary = City.BUILDS[build]
	var description := wrap_tooltip(info["description"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	# Tooltip com a descrição ao passar o mouse em qualquer parte da linha
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = description

	row.add_child(Icons.build_icon(build, _city.owner_player.color, BUILD_LIST_ICON_SIZE))
	var name_label := Label.new()
	name_label.text = info["name"]
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.custom_minimum_size.x = 160
	row.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d de produção" % info["cost"]
	if info.get("population", 0) > 0:
		cost.text += " + %d pop." % info["population"]
	if info.get("wood", 0) > 0:
		cost.text += " + %d madeira" % info["wood"]
	if info.get("iron", 0) > 0:
		cost.text += " + %d ferro" % info["iron"]
	var weapons: Dictionary = info.get("weapons", {})
	for weapon: Arsenal.Weapon in weapons:
		cost.text += " + %s" % Arsenal.amount_text(weapon, weapons[weapon])
	cost.add_theme_color_override("font_color", MUTED_COLOR)
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.custom_minimum_size.x = COST_COLUMN_WIDTH
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(cost)

	var choose := _make_button("Escolher", _choose_build.bind(build))
	choose.custom_minimum_size.x = 100
	choose.tooltip_text = description
	var reason := _city.build_error(build)
	if not reason.is_empty():
		choose.disabled = true
		choose.tooltip_text = wrap_tooltip(reason)
		cost.text = reason
		cost.add_theme_color_override("font_color", WARNING_COLOR)
	row.add_child(choose)

	var buy := _make_button(str(info["gold"]), _buy_build.bind(build))
	buy.icon = Icons.gold_coin(COIN_SIZE)
	buy.custom_minimum_size.x = BUY_BUTTON_WIDTH
	buy.add_theme_color_override("font_color", Icons.GOLD_COLOR)
	var error: String = _game.buy_error(_city, build)
	buy.disabled = _read_only or not error.is_empty()
	buy.tooltip_text = wrap_tooltip(error if not error.is_empty() else
			"Comprar agora por %d de ouro: fica pronto na hora." % info["gold"])
	row.add_child(buy)
	return row


## Quebra o texto do tooltip em linhas de até [param width] letras, para não
## ficar uma linha só muito comprida (as descrições cabem em 3 linhas).
static func wrap_tooltip(text: String, width := TOOLTIP_WIDTH) -> String:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		if not line.is_empty() and line.length() + 1 + word.length() > width:
			lines.append(line)
			line = word
		else:
			line = word if line.is_empty() else line + " " + word
	if not line.is_empty():
		lines.append(line)
	return "\n".join(lines)


## Unidade, arma ou prédio: entra direto nas obras.
func _choose_build(build: int) -> void:
	_build_modal.hide()
	_warn_if_needs_workers(_city.order_build(build))


## Obra recém-pedida que ficou sem ninguém trabalhando: aviso em vermelho no
## topo da tela (a linha dela também fica vermelha).
func _warn_if_needs_workers(construction: City.Construction) -> void:
	if _city.needs_workers(construction):
		_game.hud.show_message("%s sem mão de obra: aloque cidadãos (botão +) para %s avançar." % [
			construction.display_name(), {"a": "ela", "o": "ele", "as": "elas", "os": "eles"}[City.BUILDS[construction.build]["article"]]], NEGATIVE_COLOR)


## Botão da moeda: compra na hora com ouro (ver Game.buy_build).
func _buy_build(build: int) -> void:
	var error: String = _game.buy_error(_city, build)
	if not error.is_empty():
		_game.hud.show_message(error, WARNING_COLOR)
		return
	_game.buy_build(_city, build)
	_build_modal.hide()
	_game.hud.show_message("%s comprad%s por %d de ouro." % [City.BUILDS[build]["name"], City.BUILDS[build]["article"], City.BUILDS[build]["gold"]],
			Icons.GOLD_COLOR)
	_queue_refresh()


## Seção "Obras em andamento": melhorias de terreno e prédios em construção.
## (As unidades ficam na seção "Prédios da cidade", no prédio que as produz.)
func _rebuild_constructions() -> void:
	_clear(_constructions_box)
	var works := _city.constructions.filter(func(c: City.Construction) -> bool: return not c.is_produced())
	if works.is_empty():
		_constructions_box.add_child(_make_muted("Nenhuma obra. Clique em \"Construir...\"."))
		return
	for construction: City.Construction in works:
		_add_construction_row(_constructions_box, construction, true)


## Seção "Prédios da cidade": cada prédio pronto e, embaixo, as unidades ou
## armas que ele está produzindo. A primeira avança e tem o "- N trab. +"
## (os trabalhadores são do prédio); as outras esperam "na fila". Quando uma
## fica pronta, os trabalhadores passam para a próxima. A Marcenaria sem armas
## na fila mostra a linha de impostos (ouro por trabalhador).
func _rebuild_buildings() -> void:
	_clear(_buildings_box)
	for building in _city.buildings:
		var info: Dictionary = City.BUILDS[building]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = wrap_tooltip(info["description"])
		_buildings_box.add_child(row)
		row.add_child(Icons.build_icon(building, _city.owner_player.color))
		var name_label := Label.new()
		name_label.text = info["name"]
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var active := _city.active_unit(building)
		var queue := _city.unit_queue(building)
		if active == null and info.get("idle_gold", 0) > 0:
			_add_idle_gold_row(building)
		elif active == null and info.get("idle_science", 0) > 0:
			_add_idle_science_row(building)
		elif info.get("science", 0) > 0 and not _produces_something(building):
			_add_science_row(building)
		elif queue.is_empty() and _produces_something(building):
			var empty := _make_muted("          Nada em produção.")
			empty.add_theme_font_size_override("font_size", 13)
			_buildings_box.add_child(empty)
		for construction in queue:
			# Só a da frente da fila tem os trabalhadores (que são do prédio)
			_add_construction_row(_buildings_box, construction, construction == active)


## Se o prédio faz unidades ou armas (Prefeitura, Quartel, Marcenaria, Forja).
## Os outros (Escola, Templo, Muralha...) não mostram "Nada em produção.".
func _produces_something(building: int) -> bool:
	return City.BUILDS.values().any(func(other: Dictionary) -> bool: return other.get("requires", -1) == building)


## Prédio que só gera ciência sozinho (Escola): o ícone da ciência e quanto
## ele gera por turno, como a linha da Prefeitura, sem cidadãos.
func _add_science_row(building: int) -> void:
	var info: Dictionary = City.BUILDS[building]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = wrap_tooltip("%s %s gera +%d de ciência por turno sozinha, sem cidadãos." % [
		info["article"].capitalize(), String(info["name"]).to_lower(), info["science"]])
	_buildings_box.add_child(row)
	var indent := Control.new()
	indent.custom_minimum_size.x = UNIT_INDENT
	row.add_child(indent)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * Icons.ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: Icons.draw_science(icon, Rect2(Vector2.ZERO, icon.size)))
	row.add_child(icon)
	var label := Label.new()
	label.text = "Ciência"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var status := Label.new()
	status.text = "+%d ciência" % info["science"]
	status.custom_minimum_size.x = 120
	status.add_theme_color_override("font_color", StoneStyle.SCIENCE)
	row.add_child(status)
	var controls_space := Control.new()
	controls_space.custom_minimum_size.x = WORKER_CONTROLS_WIDTH + 30 # alinha com as outras linhas
	row.add_child(controls_space)


## Prédio que rende ouro parado (Marcenaria e Forja sem armas na fila,
## Mercado): os trabalhadores dele recolhem impostos ou comerciam, +idle_gold de
## ouro cada por turno (até idle_max_workers, se houver limite).
func _add_idle_gold_row(building: int) -> void:
	var gold_each: int = City.BUILDS[building]["idle_gold"]
	var workers: int = _city.building_workers.get(building, 0)
	var limit := City.idle_max_workers(building)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var goods_every: int = City.BUILDS[building].get("idle_goods", 0)
	var produces := City.BUILDS.values().any(func(other: Dictionary) -> bool: return other.get("requires", -1) == building)
	row.tooltip_text = wrap_tooltip(("Sem nada na fila: " if produces else "") + "os trabalhadores rendem +%d de ouro cada por turno" % gold_each
			+ (" (até %d)" % limit if limit >= 0 else "") + "."
			+ (" A cada %d trabalhador%s, +1 de alegria (bem-estar social)." % [goods_every, "es" if goods_every > 1 else ""] if goods_every > 0 else ""))
	_buildings_box.add_child(row)
	var indent := Control.new()
	indent.custom_minimum_size.x = UNIT_INDENT
	row.add_child(indent)
	var coin := TextureRect.new()
	coin.texture = Icons.gold_coin(Icons.ICON_SIZE)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)
	var label := Label.new()
	label.text = City.BUILDS[building].get("idle_label", "Impostos")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var status := Label.new()
	status.text = "+%d ouro" % (workers * gold_each)
	if goods_every > 0 and workers >= goods_every:
		status.text += " +%d alegria" % (workers / goods_every)
	status.custom_minimum_size.x = 120
	status.add_theme_color_override("font_color", Icons.GOLD_COLOR if workers > 0 else MUTED_COLOR)
	row.add_child(status)
	var most := workers + _city.free_citizens()
	_add_worker_controls(row, workers, most if limit < 0 else mini(limit, most),
			func(value: int) -> void: _city.set_building_workers(building, value))
	var x_space := Control.new()
	x_space.custom_minimum_size.x = 30 # alinha com o X das outras linhas
	row.add_child(x_space)


## Prédio que gera ciência parado (Prefeitura sem unidades na fila, Biblioteca):
## até idle_max_workers cidadãos, +idle_science de ciência cada por turno, além
## da ciência que o prédio gera sozinho.
func _add_idle_science_row(building: int) -> void:
	var info: Dictionary = City.BUILDS[building]
	var workers: int = _city.building_workers.get(building, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var produces := City.BUILDS.values().any(func(other: Dictionary) -> bool: return other.get("requires", -1) == building)
	row.tooltip_text = wrap_tooltip(("Sem unidades na fila: até" if produces else "Até") + " %d cidadãos estudam e pesquisam (+%d de ciência cada por turno)." % [
		City.idle_max_workers(building), info["idle_science"]]
		+ (" %s %s já gera +%d sozinha." % [info["article"].capitalize(), String(info["name"]).to_lower(), info["science"]] if info.get("science", 0) > 0 else ""))
	_buildings_box.add_child(row)
	var indent := Control.new()
	indent.custom_minimum_size.x = UNIT_INDENT
	row.add_child(indent)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * Icons.ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: Icons.draw_science(icon, Rect2(Vector2.ZERO, icon.size)))
	row.add_child(icon)
	var label := Label.new()
	label.text = info.get("idle_label", "Pesquisa")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var status := Label.new()
	status.text = "+%d ciência" % (info.get("science", 0) + workers * info["idle_science"])
	status.custom_minimum_size.x = 120
	status.add_theme_color_override("font_color", StoneStyle.SCIENCE)
	row.add_child(status)
	_add_worker_controls(row, workers, mini(City.idle_max_workers(building), workers + _city.free_citizens()),
			func(value: int) -> void: _city.set_building_workers(building, value))
	var x_space := Control.new()
	x_space.custom_minimum_size.x = 30 # alinha com o X das outras linhas
	row.add_child(x_space)


## Linha de uma obra: nome, barra de progresso, "progresso/custo (N t)",
## trabalhadores (se [param with_workers]) e o X para cancelar. Unidades
## aparecem recuadas, embaixo do prédio que as produz.
func _add_construction_row(box: VBoxContainer, construction: City.Construction, with_workers: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	# Unidades ficam recuadas, embaixo do prédio que as produz
	if construction.is_produced():
		var indent := Control.new()
		indent.custom_minimum_size.x = UNIT_INDENT
		row.add_child(indent)
	row.add_child(Icons.build_icon(construction.build, _city.owner_player.color))
	var name_label := Label.new()
	name_label.text = construction.display_name()
	name_label.custom_minimum_size.x = 130 - (UNIT_INDENT + 6 if construction.is_produced() else 0)
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.max_value = construction.cost()
	bar.value = construction.progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL # empurra trabalhadores e X para a direita
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	StoneStyle.style_progress(bar, Color(0.3, 0.75, 1.0))
	row.add_child(bar)

	var turns := _city.turns_to_finish(construction)
	var status := Label.new()
	status.text = "%d/%d %s" % [construction.progress, construction.cost(),
			"(parada)" if turns < 0 else "(%d t)" % turns]
	status.custom_minimum_size.x = 120
	status.tooltip_text = "Progresso / custo. (N t) = turnos para terminar."
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	if construction.is_done():
		# Unidade pronta esperando população para sair da cidade
		status.text = "pronto"
		status.tooltip_text = "Pronto. Sai da cidade quando a população chegar a %d." % (construction.population_cost() + 1)
		status.add_theme_color_override("font_color", WARNING_COLOR)
	elif construction.is_produced() and _city.active_unit(construction.producer()) != construction:
		status.text = "na fila"
		status.tooltip_text = "Espera a unidade da frente ficar pronta; os trabalhadores do prédio passam para ela."
		status.add_theme_color_override("font_color", MUTED_COLOR)
	elif _city.needs_workers(construction):
		# Parada: ninguém trabalhando nela. Vermelho até o jogador alocar cidadãos
		status.text = "%d/%d sem mão de obra" % [construction.progress, construction.cost()]
		status.tooltip_text = NEEDS_WORKERS_TIP
		status.add_theme_color_override("font_color", NEGATIVE_COLOR)
		name_label.add_theme_color_override("font_color", NEGATIVE_COLOR)
		bar.set_meta("stone_alert", true) # vala avermelhada: obra parada
		bar.tooltip_text = NEEDS_WORKERS_TIP
	row.add_child(status)

	if with_workers:
		var workers := _city.workers_on(construction)
		var max_workers := 0 if construction.is_done() else workers + _city.free_citizens()
		_add_worker_controls(row, workers, max_workers,
				func(value: int) -> void: _city.set_construction_workers(construction, value))
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = WORKER_CONTROLS_WIDTH
		row.add_child(spacer)
	var cancel := _make_button("X", _city.cancel_construction.bind(construction))
	cancel.tooltip_text = "Cancelar a obra (o progresso é perdido)."
	if construction.wood_paid > 0:
		cancel.tooltip_text += "\nOs %d de madeira voltam para o estoque." % construction.wood_paid
	if construction.iron_paid > 0:
		cancel.tooltip_text += "\nOs %d de ferro voltam para o estoque." % construction.iron_paid
	cancel.disabled = _read_only
	row.add_child(cancel)


## Seção "Melhorias em obra": as ruínas (melhorias pilhadas) e as melhorias que
## os Trabalhadores estão fazendo. As fazendas e madeireiras prontas ficam só no
## mapa da cidade, onde os cidadãos são alocados.
func _rebuild_farms() -> void:
	_clear(_farms_box)
	if _city.ruins.is_empty() and _city.sites.is_empty():
		_farms_box.add_child(_make_muted("Nenhuma. Um Trabalhador no território faz fazendas (C) e madeireiras (M)."))
		return
	# Melhorias pilhadas: não produzem até um Trabalhador reconstruir
	for ruin_cell: Vector2i in _city.ruins:
		var ruin: Dictionary = _city.ruins[ruin_cell]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_farms_box.add_child(row)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2.ONE * Icons.ICON_SIZE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.draw.connect(func() -> void: City.draw_ruin(icon, ruin["build"], Rect2(Vector2.ZERO, icon.size), ruin_cell))
		row.add_child(icon)
		var name_label := Label.new()
		name_label.text = "%s (%d, %d)" % [City.BUILDS[ruin["build"]]["name"], ruin_cell.x, ruin_cell.y]
		name_label.custom_minimum_size.x = 130
		row.add_child(name_label)
		var status := Label.new()
		status.text = "destruída - reconstrução %d/%d" % [ruin["progress"], City.BUILDS[ruin["build"]]["cost"]]
		status.add_theme_color_override("font_color", WARNING_COLOR)
		status.tooltip_text = "Pilhada por um inimigo. Um Trabalhador na casa reconstrói (tecla R), 1 ponto por turno."
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(status)
	# Melhorias que os Trabalhadores estão fazendo (ou que ficaram paradas)
	for site_cell: Vector2i in _city.sites:
		var site: Dictionary = _city.sites[site_cell]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_farms_box.add_child(row)
		row.add_child(Icons.build_icon(site["build"], _city.owner_player.color))
		var name_label := Label.new()
		name_label.text = "%s (%d, %d)" % [City.BUILDS[site["build"]]["name"], site_cell.x, site_cell.y]
		name_label.custom_minimum_size.x = 130
		row.add_child(name_label)
		var worker := _game.get_unit_at(site_cell)
		var working: bool = worker != null and worker.rebuilding and worker.owner_player == _city.owner_player
		var status := Label.new()
		status.text = "em obra - %d/%d%s" % [site["progress"], City.BUILDS[site["build"]]["cost"],
				" (Trabalhador na casa)" if working else " (parada: sem Trabalhador)"]
		if not working:
			status.add_theme_color_override("font_color", WARNING_COLOR)
		status.tooltip_text = "Um Trabalhador na casa faz 1 ponto por turno. Se ele sair, a obra para e guarda o progresso."
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(status)


## Seção "Unidades na cidade": a unidade que está na casa da cidade (só cabe
## uma por casa). Fortificada, ela fica escondida no mapa; "Ativar" a tira da
## fortificação e a seleciona.
func _rebuild_units() -> void:
	_clear(_units_box)
	var unit := _game.get_unit_at(_city.cell)
	if unit == null:
		_units_box.add_child(_make_muted("Nenhuma unidade na cidade."))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_units_box.add_child(row)
	var label := Label.new()
	label.text = "%s  -  %s  |  Defesa %d  |  Energia %d/%d" % [
		unit.type.display_name, "fortificada" if unit.fortified else "no mapa",
		unit.defense, unit.energy, unit.max_energy,
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := _make_button("Ativar" if unit.fortified else "Selecionar", _game.activate_unit.bind(unit))
	button.disabled = _read_only
	button.tooltip_text = "Tira a unidade da fortificação e a seleciona no mapa." if unit.fortified else ""
	row.add_child(button)


## Controle "− N +" de trabalhadores, limitado entre 0 e [param max_value].
func _add_worker_controls(row: HBoxContainer, value: int, max_value: int, on_change: Callable) -> void:
	var minus := _make_button("-", on_change.bind(value - 1))
	minus.disabled = _read_only or value <= 0
	minus.custom_minimum_size.x = 28
	row.add_child(minus)
	var count := Label.new()
	count.text = "%d trab." % value
	count.custom_minimum_size.x = 56
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	var plus := _make_button("+", on_change.bind(value + 1))
	plus.disabled = _read_only or value >= max_value
	plus.custom_minimum_size.x = 28
	plus.tooltip_text = "Nenhum cidadão livre." if not _read_only and value >= max_value else ""
	row.add_child(plus)


# --- Auxiliares -------------------------------------------------------------

func _make_section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SECTION_COLOR)
	label.add_theme_font_size_override("font_size", 18)
	return label


## Título de seção com um sulco entalhado acima (o sulco some junto se o
## título for escondido).
func _add_carved_section(parent: Container, text: String) -> Label:
	var groove := StoneStyle.separator(14.0)
	parent.add_child(groove)
	var label := _make_section(text)
	label.visibility_changed.connect(func() -> void: groove.visible = label.visible)
	parent.add_child(label)
	return label


func _make_muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label



func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	style_button(button)
	return button


## Botões de pedra em relevo (StoneStyle). Usado por todas as janelas.
static func style_button(button: Button) -> void:
	StoneStyle.style_button(button)


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
