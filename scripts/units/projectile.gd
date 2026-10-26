class_name Projectile
extends Node2D

## Projétil do ataque à distância (Unit.play_shot): voa em arco da unidade até
## o alvo e some. A flecha aponta para onde vai; a pedra da Catapulta sobe mais.

enum Kind { ARROW, STONE }

const ARROW_TIME := 0.35
const STONE_TIME := 0.55
## Altura do arco, em fração da distância até o alvo.
const ARROW_ARC := 0.2
const STONE_ARC := 0.5
const ARROW_LENGTH := GameMap.TILE_SIZE * 0.45
const STONE_RADIUS := GameMap.TILE_SIZE * 0.13

var _kind := Kind.ARROW
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _arc := 0.0
## Progresso do voo, de 0 (saindo) a 1 (no alvo).
var _t := 0.0:
	set(value):
		_t = value
		var previous := position
		position = _point(value)
		if _kind == Kind.ARROW and position != previous:
			rotation = (position - previous).angle()


## Lança o projétil de [param from] até [param to] (posições em [param parent])
## e espera ele chegar.
static func fire(parent: Node, kind: Kind, from: Vector2, to: Vector2) -> void:
	var projectile := Projectile.new()
	projectile._kind = kind
	projectile._from = from
	projectile._to = to
	projectile._arc = from.distance_to(to) * (STONE_ARC if kind == Kind.STONE else ARROW_ARC)
	projectile.z_index = 10
	projectile.position = from
	projectile.rotation = (to - from).angle()
	parent.add_child(projectile)
	var tween := projectile.create_tween()
	tween.tween_property(projectile, "_t", 1.0, STONE_TIME if kind == Kind.STONE else ARROW_TIME)
	await tween.finished
	projectile.queue_free()


## Ponto do arco: a reta entre as duas casas, levantada por uma parábola.
func _point(t: float) -> Vector2:
	return _from.lerp(_to, t) - Vector2(0, _arc * 4.0 * t * (1.0 - t))


func _draw() -> void:
	if _kind == Kind.STONE:
		draw_circle(Vector2.ZERO, STONE_RADIUS + 1.5, Color.BLACK)
		draw_circle(Vector2.ZERO, STONE_RADIUS, Color8(120, 112, 100))
		draw_circle(Vector2(-STONE_RADIUS, -STONE_RADIUS) * 0.35, STONE_RADIUS * 0.4, Color8(165, 157, 145))
		return
	# Flecha deitada no eixo x, ponta para a direita
	var half := ARROW_LENGTH / 2.0
	draw_line(Vector2(-half, 0), Vector2(half, 0), Color.BLACK, 4.0)
	draw_line(Vector2(-half, 0), Vector2(half, 0), Color8(140, 95, 50), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(half + 7, 0), Vector2(half - 2, -4), Vector2(half - 2, 4)]),
			Color8(70, 70, 75))
	for side in [-1.0, 1.0]:
		draw_line(Vector2(-half, 0), Vector2(-half - 5, 5 * side), Color.WHITE, 2.0)
		draw_line(Vector2(-half + 4, 0), Vector2(-half - 1, 5 * side), Color.WHITE, 2.0)
