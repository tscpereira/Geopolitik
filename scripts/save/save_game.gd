class_name SaveGame
extends RefCounted

## Arquivos de save da partida: JSON em user://saves/ (no Windows,
## %APPDATA%\Godot\app_userdata\ProjetoGame\saves\). Cada espaço ("slot") é um
## arquivo. O espaço 0 é o salvamento automático, feito no início de cada vez
## do jogador humano; os espaços 1 a SLOTS são do jogador (F5 salva, F9 carrega).
##
## O conteúdo é montado por Game.capture_state() e devolvido ao jogo por
## Game.restore_state(), usando o to_dict() / from_dict() de cada classe
## (GameMap, Player, City, Unit, LumberMill, TurnManager...). Aqui ficam só os
## arquivos, a versão e as conversões para JSON.
##
## VERSION sobe quando o formato muda; migrate() atualiza saves antigos para o
## formato atual, para eles continuarem abrindo.

## Versão do formato do arquivo. Histórico:
##   1  primeira versão (22/10/2026).
const VERSION := 1
## Espaço do salvamento automático.
const AUTOSAVE_SLOT := 0
## Espaços do jogador: 1 a SLOTS.
const SLOTS := 5

## Pasta dos saves. Os testes automáticos trocam por uma pasta temporária, para
## não apagar os saves de verdade.
static var directory := "user://saves"


static func slot_path(slot: int) -> String:
	return "%s/%s.json" % [directory, "autosave" if slot == AUTOSAVE_SLOT else "slot_%d" % slot]


static func slot_name(slot: int) -> String:
	return "Automático" if slot == AUTOSAVE_SLOT else "Espaço %d" % slot


static func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Grava [param data] (de Game.capture_state) no espaço. Acrescenta a versão
## e a data. Retorna OK ou o erro.
static func write(slot: int, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(directory)
	data["version"] = VERSION
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## Lê o espaço e atualiza o formato, se for de uma versão antiga. Retorna {}
## se o arquivo não existir, estiver estragado ou for de uma versão mais nova.
static func read(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if not parsed is Dictionary:
		push_warning("Save %s ilegível." % slot_path(slot))
		return {}
	return migrate(parsed)


## Atualiza um save antigo para o formato atual (VERSION). Quando o formato
## mudar, acrescente aqui um passo por versão (ex.: if version < 2: ...).
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > VERSION:
		push_warning("Save de uma versão mais nova do jogo (%d; esta lê até %d)." % [version, VERSION])
		return {}
	data["version"] = VERSION
	return data


## Uma linha para a janela de salvar/carregar: "Turno 12, vez do Jogador 1 -
## 22/10/2026 14:30", ou "vazio".
static func summary(slot: int) -> String:
	var data := read(slot)
	if data.is_empty():
		return "vazio" if not has_save(slot) else "arquivo ilegível"
	var players: Array = data.get("players", [])
	var index := int(data["turn_manager"]["current_index"])
	var player_name: String = players[index]["name"] if index < players.size() else "?"
	return "Turno %d, vez do %s - %s" % [int(data["turn_manager"]["turn_number"]), player_name,
			_date_text(data.get("saved_at", ""))]


## "2026-10-22 14:30:05" -> "22/10/2026 14:30".
static func _date_text(saved_at: String) -> String:
	if saved_at.length() < 16:
		return saved_at
	return "%s/%s/%s %s" % [saved_at.substr(8, 2), saved_at.substr(5, 2), saved_at.substr(0, 4), saved_at.substr(11, 5)]


# --- Conversões para JSON ----------------------------------------------------
# O JSON não tem Vector2i nem chaves numéricas, e os números voltam como float.

static func cell_to_json(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


static func json_to_cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


## {casa: número} -> [[x, y, número], ...]
static func cell_map_to_json(cells: Dictionary) -> Array:
	var result := []
	for cell: Vector2i in cells:
		result.append([cell.x, cell.y, cells[cell]])
	return result


static func json_to_cell_map(value: Array) -> Dictionary:
	var result := {}
	for entry: Array in value:
		result[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	return result


## {número: número} (ex.: arsenal, trabalhadores dos prédios) -> [[chave, valor], ...]
static func int_map_to_json(values: Dictionary) -> Array:
	var result := []
	for key: int in values:
		result.append([key, values[key]])
	return result


static func json_to_int_map(value: Array) -> Dictionary:
	var result := {}
	for entry: Array in value:
		result[int(entry[0])] = int(entry[1])
	return result


static func cells_to_json(cells: Array[Vector2i]) -> Array:
	var result := []
	for cell in cells:
		result.append([cell.x, cell.y])
	return result


static func json_to_cells(value: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Array in value:
		result.append(json_to_cell(entry))
	return result
