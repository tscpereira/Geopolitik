class_name MapCamera
extends Camera2D

## Câmera do mapa: setas/WASD movem, roda do mouse dá zoom (na direção do
## cursor) e arrastar com o botão esquerdo ou do meio move o mapa.
## Com o botão esquerdo, só vira arraste depois de DRAG_THRESHOLD pixels;
## antes disso é um clique normal (selecionar, mover, abrir cidade).

## Velocidade em pixels de tela por segundo.
const PAN_SPEED := 900.0
const ZOOM_FACTOR := 1.15
## Com casas de 40px o mapa pequeno tem 4800x3000; 0.25 permite vê-lo quase inteiro.
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0
## Pixels que o mouse precisa andar com o botão esquerdo apertado para virar
## arraste do mapa (abaixo disso, conta como clique).
const DRAG_THRESHOLD := 8.0

## Travada (janela da cidade ou pergunta do nome abertas): teclas, roda do
## mouse e arraste não mexem no mapa por trás da janela.
var locked := false:
	set(value):
		locked = value
		_dragging = false

var _bounds := Rect2()
var _left_press_position := Vector2.ZERO
var _dragging := false


## Limita a câmera à área do mapa (em pixels).
func set_bounds(size: Vector2) -> void:
	_bounds = Rect2(Vector2.ZERO, size)
	_clamp_position()


func center_on(world_position: Vector2) -> void:
	position = _clamped(world_position)


## Desliza a câmera suavemente até centralizar [param world_position].
func pan_to(world_position: Vector2, duration := 0.25) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", _clamped(world_position), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _process(delta: float) -> void:
	if locked:
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		direction.y += 1
	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / zoom.x
		_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_FACTOR, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_FACTOR, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_press_position = event.position
				_dragging = false
			elif _dragging:
				# Foi um arraste, não um clique: o jogo não recebe o "soltar"
				_dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if not _dragging and event.position.distance_to(_left_press_position) > DRAG_THRESHOLD:
				_dragging = true
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			if _dragging:
				_drag(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_drag(event.relative)


## Move o mapa junto com o mouse (o ponto agarrado fica sob o cursor).
func _drag(relative: Vector2) -> void:
	position -= relative / zoom.x
	_clamp_position()


## Aplica o zoom mantendo fixo o ponto do mapa que está sob o cursor.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	var offset_from_center := screen_point - get_viewport_rect().size / 2.0
	var world_point := position + offset_from_center / zoom.x
	zoom = Vector2(new_zoom, new_zoom)
	position = world_point - offset_from_center / new_zoom
	_clamp_position()


func _clamp_position() -> void:
	position = _clamped(position)


## Posição mais próxima que mantém a visão dentro do mapa; se o mapa couber
## inteiro na tela, centraliza.
func _clamped(target: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return target
	var half_view := get_viewport_rect().size / 2.0 / zoom.x
	var clamped := target
	for axis in 2:
		var low := _bounds.position[axis] + half_view[axis]
		var high := _bounds.end[axis] - half_view[axis]
		clamped[axis] = (low + high) / 2.0 if low > high else clampf(clamped[axis], low, high)
	return clamped
