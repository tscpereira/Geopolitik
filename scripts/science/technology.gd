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

## Novas tecnologias entram no fim: o save guarda o número de cada uma.
enum Tech { CONSTRUCTION, MYSTICISM, ALPHABET, BRONZE_WORKING }

##   name      nome mostrado
##   cost      pontos de ciência para pesquisar
##   requires  tecnologias que precisam estar pesquisadas antes
##   description  texto do tooltip e da janela de tecnologia descoberta
##   image     ilustração da janela de tecnologia descoberta (TechDialog);
##             qualquer tamanho, ela é recortada para caber
const DATA := {
	Tech.CONSTRUCTION: {
		"name": "Construção", "cost": 30, "requires": [],
		"description": "Técnicas de construção com pedra e madeira. Libera a Muralha, que dá +2 de defesa às unidades dentro da cidade.",
		"image": "res://assets/tech/construcao.png",
	},
	Tech.MYSTICISM: {
		"name": "Misticismo", "cost": 20, "requires": [],
		"description": "Crenças e rituais que unem o povo. Libera o Templo, que acalma os cidadãos infelizes.",
		"image": "res://assets/tech/misticismo.png",
	},
	Tech.ALPHABET: {
		"name": "Alfabeto", "cost": 40, "requires": [],
		"description": "A escrita: base para registrar e transmitir o conhecimento.",
		"image": "res://assets/tech/alfabeto.png",
	},
	Tech.BRONZE_WORKING: {
		"name": "Trabalho em Bronze", "cost": 35, "requires": [],
		"description": "Cobre e estanho fundidos em bronze: armas e armaduras melhores. Libera o Lanceiro, forte contra a cavalaria.",
		"image": "res://assets/tech/bronze.png",
	},
}


## Ilustração da tecnologia, ou null se não houver (ou o arquivo não existir).
static func image(tech: int) -> Texture2D:
	var path: String = DATA[tech].get("image", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)


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
