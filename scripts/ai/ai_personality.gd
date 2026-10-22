class_name AIPersonality
extends RefCounted

## Personalidade do jogador máquina: os números que guiam as decisões do
## AIController (economia, expansão e guerra). Trocar a personalidade muda o
## estilo de jogo sem mudar as regras: todas usam as mesmas ações do humano.
##
## Presets: balanced (Equilibrada, a de hoje), expansionist (Expansionista),
## economist (Econômica) e defensive (Defensiva). Futuramente: ciência,
## cultura, diplomacia.

var display_name := ""

# --- Crescimento -------------------------------------------------------------
## Saldo de alimento por turno que a cidade tenta manter (faz fazendas e põe
## cidadãos nelas até chegar nisso).
var food_surplus := 2

# --- Expansão ----------------------------------------------------------------
## População mínima para a cidade fazer um Colono.
var settler_population := 4
## Máximo de cidades que o jogador tenta ter.
var max_cities := 4
## Distância (em casas) que o Colono anda procurando um bom lugar.
var settler_search_radius := 8

# --- Economia ----------------------------------------------------------------
## Madeira que o jogador tenta ter por turno (madeireiras e Trabalhadores).
var wood_per_turn_goal := 2
## Trabalhadores (unidades) por cidade sem floresta na área.
var workers_per_city := 1
## Põe cidadãos sobrando na Marcenaria parada, para render impostos.
var collect_taxes := true
## Cidadãos reservados para os impostos da Marcenaria parada, mesmo com obras
## para fazer (só em cidades de 4+ de população); 0 = só quem sobrar.
var tax_workers := 0

# --- Militar -----------------------------------------------------------------
## Guerreiros fortificados dentro de cada cidade.
var garrison_per_city := 1
## Lanças que o jogador tenta ter no arsenal por cidade.
var spears_per_city := 2
## Guerreiros fora das cidades necessários para partir para o ataque
## (0 = nunca ataca; só se defende).
var army_to_attack := 3
## Compra um Guerreiro com ouro quando há inimigo perto de uma cidade sem defesa.
var buy_defense := true
## Distância (em casas) em que um inimigo é considerado uma ameaça à cidade.
var threat_radius := 3


## Todos os números da personalidade, para o save.
func to_dict() -> Dictionary:
	var data := {}
	for property in get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data[property["name"]] = get(property["name"])
	return data


## Personalidade de um save. Campos que não existem mais são ignorados; os que
## faltam (save antigo) ficam com o valor da Equilibrada.
static func from_dict(data: Dictionary) -> AIPersonality:
	var p := balanced()
	for key: String in data:
		if key in p:
			p.set(key, type_convert(data[key], typeof(p.get(key))))
	return p


## Equilibrada: cresce, junta madeira, monta uma defesa e um pequeno exército.
static func balanced() -> AIPersonality:
	var p := AIPersonality.new()
	p.display_name = "Equilibrada"
	return p


## Expansionista: funda muitas cidades cedo; pouca tropa.
static func expansionist() -> AIPersonality:
	var p := balanced()
	p.display_name = "Expansionista"
	p.settler_population = 3
	p.max_cities = 8
	p.spears_per_city = 1
	p.army_to_attack = 5
	return p


## Econômica: cresce bastante, cobra impostos e quase não ataca.
static func economist() -> AIPersonality:
	var p := balanced()
	p.display_name = "Econômica"
	p.food_surplus = 3
	p.settler_population = 5
	p.wood_per_turn_goal = 3
	p.tax_workers = 2
	p.spears_per_city = 1
	p.army_to_attack = 0
	return p


## Defensiva: guarnição forte nas cidades e nunca sai para atacar.
static func defensive() -> AIPersonality:
	var p := balanced()
	p.display_name = "Defensiva"
	p.garrison_per_city = 2
	p.spears_per_city = 3
	p.army_to_attack = 0
	return p
