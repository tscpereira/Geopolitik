class_name Technology
extends RefCounted

## Árvore de conhecimentos (tecnologias). Cada tecnologia custa pontos de
## ciência e pode exigir outras já pesquisadas ("requires"); quando todas as
## exigidas estão prontas, ela fica disponível para pesquisa (como no
## Civilization e no Age of Empires).
##
## A ciência vem das Prefeituras (City.science_per_turn) e é gasta, a cada
## turno, na pesquisa escolhida (Player.research). Os pontos não se acumulam:
## sem pesquisa escolhida, eles se perdem.
##
## Para uma tecnologia nova: entre no enum e em DATA. O que cada uma libera no
## jogo ainda vai ser definido ("unlocks" fica só como texto por enquanto).

enum Tech { CONSTRUCTION, MYSTICISM, ALPHABET }

##   name      nome mostrado
##   cost      pontos de ciência para pesquisar
##   requires  tecnologias que precisam estar pesquisadas antes
##   description  texto do tooltip
const DATA := {
	Tech.CONSTRUCTION: {
		"name": "Construção", "cost": 30, "requires": [],
		"description": "Técnicas de construção com pedra e madeira.",
	},
	Tech.MYSTICISM: {
		"name": "Misticismo", "cost": 20, "requires": [],
		"description": "Crenças e rituais que unem o povo.",
	},
	Tech.ALPHABET: {
		"name": "Alfabeto", "cost": 40, "requires": [],
		"description": "A escrita: base para registrar e transmitir o conhecimento.",
	},
}


static func tech_name(tech: int) -> String:
	return DATA[tech]["name"]


static func cost(tech: int) -> int:
	return DATA[tech]["cost"]


## Tecnologias que [param researched] permite pesquisar agora: ainda não
## pesquisadas e com todas as exigidas prontas. Na ordem do enum.
static func available(researched: Array) -> Array[int]:
	var result: Array[int] = []
	for tech: int in DATA:
		if researched.has(tech):
			continue
		var ready := true
		for required: int in DATA[tech]["requires"]:
			if not researched.has(required):
				ready = false
		if ready:
			result.append(tech)
	return result
