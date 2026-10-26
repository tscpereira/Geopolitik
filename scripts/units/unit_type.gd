class_name UnitType
extends Resource

## Definição de um tipo de unidade (ex.: Guerreiro).
## Cada tipo é um arquivo .tres em data/units/.

@export var display_name := ""
## Desenho da unidade (TILE_SIZE x TILE_SIZE, fundo transparente).
## Pixels magenta (#FF00FF) viram a cor do jogador.
@export var sprite: Texture2D
## Letra desenhada no lugar do sprite, se ele não estiver definido.
@export var symbol := ""
@export_range(0, 99) var attack := 1
@export_range(0, 99) var defense := 1
## Quantas casas a unidade anda por turno.
@export_range(0, 99) var movement := 1
## Energia com que a unidade começa; ao chegar a 0 ela é destruída.
@export_range(1, 999) var max_energy := 100
## Cavalaria (Cavalaria Leve, Bigas): é contra ela que vale o anti_cavalry_bonus.
@export var is_mounted := false
## Bônus de ataque E de defesa quando luta contra cavalaria (Lanceiro: +1).
@export_range(0, 9) var anti_cavalry_bonus := 0
## Alcance do ataque à distância, em casas (Arqueiro: 1, só a vizinha;
## Catapulta: 2). 0 = ataca corpo a corpo. Quem ataca à distância usa o Ataque
## como força do disparo, não leva dano de volta, não avança para a casa do
## alvo e não invade cidades (ver Combat e Movement.attack_targets).
@export_range(0, 9) var attack_range := 0
## Disparo por cima do terreno: floresta, colinas e montanhas entre a unidade e
## o alvo não bloqueiam o tiro (ver Movement.has_line_of_fire). Ninguém tem
## ainda; fica para os canhões das próximas eras.
@export var indirect_fire := false
## Desenho do projétil no ataque à distância: 0 = flecha, 1 = pedra.
@export_enum("Flecha", "Pedra") var projectile := 0
## Pode construir uma nova cidade (tecla B), sendo consumida no processo.
@export var can_found_city := false
## Pode construir madeireiras (tecla M): no território de uma cidade sua, a
## madeireira é da cidade; fora dele, remota, e a unidade trabalha nela.
@export var can_build_lumber_mill := false
## Pode construir fazendas no território de uma cidade sua (tecla C).
@export var can_build_farm := false
## Pode reconstruir fazendas e madeireiras pilhadas (tecla R).
@export var can_rebuild := false
## Pode migrar para uma cidade (tecla J): vira 1 de população dela.
@export var can_join_city := false
