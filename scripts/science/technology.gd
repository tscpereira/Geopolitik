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
## Era antiga (árvore desenhada pelo usuário em 25/10/2026, techtree.drawio):
##   Escrita -> Literatura -> Direito -> República
##   Escrita + Trabalho em Bronze -> Moeda
##   Construção -> Matemática -> Engenharia Civil -> Pão e Circo
##   Trabalho em Bronze -> Trabalho em Ferro -> Pão e Circo
##   Montaria + Trabalho em Bronze -> Guerra de movimento
##   Misticismo (sem sucessora por enquanto)
##   Guerra a distância (sem sucessora por enquanto; entrou em 25/10/2026)
## O que cada uma libera fica onde é usado: o campo "tech" de City.BUILDS
## (prédios, unidades), has_tech nas regras (Direito, Trabalho em Ferro,
## Engenharia Civil). Para uma tecnologia nova: entre no fim do enum e em DATA.

## Novas tecnologias entram no fim: o save guarda o número de cada uma.
## WRITING era ALPHABET ("Alfabeto") até 25/10/2026: o número é o mesmo.
enum Tech {
	CONSTRUCTION, MYSTICISM, WRITING, BRONZE_WORKING, HORSEBACK_RIDING, LITERATURE, MATHEMATICS,
	IRON_WORKING, CURRENCY, MOBILE_WARFARE, LAW, CIVIL_ENGINEERING, REPUBLIC, BREAD_AND_CIRCUSES,
	RANGED_WARFARE,
}

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
	Tech.WRITING: {
		"name": "Escrita", "cost": 40, "requires": [],
		"description": "Registrar e transmitir o conhecimento. Libera a Escola (+1 de ciência por turno).",
		"image": "res://assets/tech/alfabeto.png",
	},
	Tech.BRONZE_WORKING: {
		"name": "Trabalho em Bronze", "cost": 35, "requires": [],
		"description": "Cobre e estanho fundidos em bronze: armas e armaduras melhores. Libera o Lanceiro, forte contra a cavalaria.",
		"image": "res://assets/tech/bronze.png",
	},
	Tech.HORSEBACK_RIDING: {
		"name": "Montaria", "cost": 35, "requires": [],
		"description": "Domar e montar cavalos. Libera a Cavalaria Leve (Movimento 4; leva 1 Lança).",
		"image": "res://assets/tech/montaria.png",
	},
	Tech.RANGED_WARFARE: {
		"name": "Guerra a distância", "cost": 35, "requires": [],
		"description": "Arcos e flechas: atacar sem chegar perto. Libera o Arqueiro (ataque à distância 2, alcance 1).",
		"image": "res://assets/tech/guerra_a_distancia.png",
	},
	Tech.LITERATURE: {
		"name": "Literatura", "cost": 70, "requires": [Tech.WRITING],
		"description": "Obras escritas e copiadas. Libera a Biblioteca (até 2 cidadãos, +1 de ciência cada).",
		"image": "res://assets/tech/literatura.png",
	},
	Tech.MATHEMATICS: {
		"name": "Matemática", "cost": 60, "requires": [Tech.CONSTRUCTION],
		"description": "Números e geometria aplicados às máquinas. Libera a Catapulta (ataque à distância 4, alcance 2).",
		"image": "res://assets/tech/matematica.png",
	},
	Tech.IRON_WORKING: {
		"name": "Trabalho em Ferro", "cost": 70, "requires": [Tech.BRONZE_WORKING],
		"description": "Fundir e forjar o ferro. Mostra o ferro no mapa, libera a Mina (+1 de ferro por cidadão), a Forja (Espadas Curtas; parada, impostos e bem-estar) e o Guerreiro de Espada Curta (Ataque 2, Defesa 2).",
		"image": "res://assets/tech/trabalho_em_ferro.png",
	},
	Tech.CURRENCY: {
		"name": "Moeda", "cost": 70, "requires": [Tech.WRITING, Tech.BRONZE_WORKING],
		"description": "Moedas de metal cunhadas para o comércio. Libera o Mercado (até 2 cidadãos, +1 de ouro cada).",
		"image": "res://assets/tech/moeda.png",
	},
	Tech.MOBILE_WARFARE: {
		"name": "Guerra de movimento", "cost": 80, "requires": [Tech.HORSEBACK_RIDING, Tech.BRONZE_WORKING],
		"description": "Carros de guerra puxados por cavalos. Libera as Bigas (Ataque 2, Movimento 3; levam 1 Espada Curta).",
		"image": "res://assets/tech/guerra_de_movimento.png",
	},
	Tech.LAW: {
		"name": "Direito", "cost": 100, "requires": [Tech.LITERATURE],
		"description": "Leis escritas e iguais para todos. Todas as cidades ganham +1 cidadão contente de base.",
		"image": "res://assets/tech/direito.png",
	},
	Tech.CIVIL_ENGINEERING: {
		"name": "Engenharia Civil", "cost": 100, "requires": [Tech.MATHEMATICS],
		"description": "Pontes, aquedutos e vias pavimentadas. Os Trabalhadores passam a construir Estradas (andar de estrada para estrada custa meio movimento).",
		"image": "res://assets/tech/engenharia_civil.png",
	},
	Tech.REPUBLIC: {
		"name": "República", "cost": 150, "requires": [Tech.LAW],
		"description": "O povo escolhe os seus representantes. Vai habilitar o governo representativo (os governos ainda não existem no jogo).",
		"image": "res://assets/tech/republica.png",
	},
	Tech.BREAD_AND_CIRCUSES: {
		"name": "Pão e Circo", "cost": 140, "requires": [Tech.CIVIL_ENGINEERING, Tech.IRON_WORKING],
		"description": "Espetáculos para o povo. Libera a Arena, que dobra a alegria das festividades.",
		"image": "res://assets/tech/pao_e_circo.png",
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
