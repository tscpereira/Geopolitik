class_name Nation
extends RefCounted

## Nações que se pode escolher na tela de início (desde 30/10/2026, pedido do
## usuário). Cada uma tem o nome (plural, "Romanos"), o artigo ("os"), a cor
## padrão, os nomes das cidades (na ordem em que são fundadas; acabando, o
## jogo usa City.NAMES) e o estilo da máquina quando ela não é do humano
## (AIPersonality). O líder é sempre o Imperador por enquanto (o título vai
## variar com a civilização e o governo; sem nomes próprios, decisão do
## usuário). Nações novas entram no fim: o save guarda o número.

enum Id { ROMANS, GREEKS, PHOENICIANS, EGYPTIANS, AMERICANS, ENGLISH }

const DATA := {
	Id.ROMANS: {
		"name": "Romanos", "color": Color8(200, 40, 40), "personality": "expansionist",
		"description": "Construtores de estradas e conquistadores.",
		"cities": ["Roma", "Óstia", "Cápua", "Pompeia", "Ravena", "Verona", "Mediolano", "Neápolis",
				"Aquileia", "Tarento", "Arímino", "Pisa"],
	},
	Id.GREEKS: {
		"name": "Gregos", "color": Color8(40, 96, 220), "personality": "balanced",
		"description": "Filósofos, navegantes e cidades-estado.",
		"cities": ["Atenas", "Esparta", "Corinto", "Tebas", "Argos", "Delfos", "Olímpia", "Mégara",
				"Siracusa", "Mileto", "Rodes", "Éfeso"],
	},
	Id.PHOENICIANS: {
		"name": "Fenícios", "color": Color8(160, 80, 220), "personality": "economist",
		"description": "Mercadores do mar e da púrpura.",
		"cities": ["Tiro", "Sídon", "Biblos", "Cartago", "Útica", "Gades", "Arados", "Léptis",
				"Hipona", "Motia", "Berito", "Panormo"],
	},
	Id.EGYPTIANS: {
		"name": "Egípcios", "color": Color8(250, 210, 40), "personality": "defensive",
		"description": "Os reinos do Nilo e das pirâmides.",
		"cities": ["Mênfis", "Tebas do Nilo", "Heliópolis", "Alexandria", "Abidos", "Tânis", "Elefantina",
				"Assuã", "Sais", "Bubástis", "Hermópolis", "Edfu"],
	},
	Id.AMERICANS: {
		"name": "Americanos", "color": Color8(40, 160, 80), "personality": "expansionist",
		"description": "Pioneiros de uma terra nova.",
		"cities": ["Washington", "Nova York", "Filadélfia", "Boston", "Chicago", "Atlanta",
				"São Francisco", "Nova Orleans", "Seattle", "Denver", "Dallas", "Baltimore"],
	},
	Id.ENGLISH: {
		"name": "Ingleses", "color": Color8(240, 140, 40), "personality": "balanced",
		"description": "Um povo de ilha, de reis e de marinheiros.",
		"cities": ["Londres", "York", "Cantuária", "Bristol", "Oxford", "Nottingham", "Liverpool",
				"Manchester", "Plymouth", "Dover", "Cambridge", "Norwich"],
	},
}

## Cores que se pode escolher (as das nações e mais algumas). Cada jogador tem
## uma cor diferente.
const COLORS: Array[Color] = [
	Color8(200, 40, 40), Color8(40, 96, 220), Color8(160, 80, 220), Color8(250, 210, 40),
	Color8(40, 160, 80), Color8(240, 140, 40), Color8(40, 190, 200), Color8(230, 90, 160),
]


static func name_of(nation: int) -> String:
	return DATA[nation]["name"]


## "Imperador dos Romanos".
static func leader(nation: int) -> String:
	return "Imperador dos %s" % name_of(nation)


## Personalidade da máquina para a nação.
static func personality(nation: int) -> AIPersonality:
	match DATA[nation]["personality"]:
		"expansionist":
			return AIPersonality.expansionist()
		"economist":
			return AIPersonality.economist()
		"defensive":
			return AIPersonality.defensive()
	return AIPersonality.balanced()
