extends Node

## Janela do jogo (autoload global "WindowSettings"):
##   F11 alterna entre a janela maximizada e a janela normal, em qualquer tela.
##   A escolha fica gravada em CONFIG_PATH e vale na próxima vez que o jogo abrir.
## O jogo não estica a imagem (display/window/stretch/mode = "disabled"): uma
## janela maior mostra mais casas do mapa, e o HUD fica preso nos cantos.

const CONFIG_PATH := "user://configuracoes.cfg"

var maximized := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		maximized = config.get_value("janela", "maximizada", false)
	if maximized:
		_apply.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_maximized(not maximized)
		get_viewport().set_input_as_handled()


## Maximiza (ou volta à janela normal) e grava a escolha.
func set_maximized(value: bool) -> void:
	maximized = value
	_apply()
	var config := ConfigFile.new()
	config.load(CONFIG_PATH) # mantém outras configurações, se houver
	config.set_value("janela", "maximizada", maximized)
	config.save(CONFIG_PATH)


func _apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if maximized else DisplayServer.WINDOW_MODE_WINDOWED)
