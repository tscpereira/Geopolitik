class_name Trade
extends RefCounted

## Comércio entre jogadores em paz (desde 30/10/2026; diplomacia, fase 3,
## pedido do usuário). Cada lado de uma proposta é um dicionário:
##   {"gold": int, "wood": int, "iron": int, "weapons": {Arsenal.Weapon: int},
##    "map": bool, "techs": [Technology.Tech]}
## Ouro, madeira, ferro e armas saem do tesouro, do estoque e do arsenal de quem
## dá; o MAPA soma o que quem dá já explorou (e as cidades que ele conhece) ao
## de quem recebe; uma TECNOLOGIA só se o outro ainda não tem e já pode
## pesquisar (as exigidas pesquisadas).
## A máquina avalia tudo em ouro (value_of): ouro 1, madeira WOOD_VALUE, ferro
## IRON_VALUE, arma pelo que custa fazer (WEAPON_PRODUCTION_VALUE por ponto de
## produção, mais a madeira e o ferro dela), tecnologia TECH_VALUE por ponto de
## ciência e o mapa MAP_CELL_VALUE por casa nova que ele revela.

const WOOD_VALUE := 2
const IRON_VALUE := 3
const WEAPON_PRODUCTION_VALUE := 3
const TECH_VALUE := 2
const MAP_CELL_VALUE := 0.1
## Troca feita: confiança a mais, dos dois lados.
const TRADE_TRUST := 5


static func empty() -> Dictionary:
	return {"gold": 0, "wood": 0, "iron": 0, "weapons": {}, "map": false, "techs": []}


static func is_empty(side: Dictionary) -> bool:
	return side["gold"] <= 0 and side["wood"] <= 0 and side["iron"] <= 0 and not side["map"] \
			and side["techs"].is_empty() and side["weapons"].values().all(func(n: int) -> bool: return n <= 0)


## Tecnologias que [param giver] pode passar a [param receiver]: tem, o outro
## não tem e já pode pesquisar.
static func techs_to_offer(giver: Player, receiver: Player) -> Array[int]:
	var result: Array[int] = []
	for tech: int in Technology.available(receiver.researched):
		if giver.researched.has(tech):
			result.append(tech)
	return result


## Casas que o mapa de [param giver] revela a [param receiver] (exploradas por um e não pelo outro).
static func map_gain(giver: Player, receiver: Player) -> int:
	var count := 0
	for i in giver.explored.size():
		if giver.explored[i] != 0 and (i >= receiver.explored.size() or receiver.explored[i] == 0):
			count += 1
	return count


## Valor em ouro da arma [param weapon] (o que custa fazer).
static func weapon_value(weapon: int) -> int:
	for build: int in City.BUILDS:
		var info: Dictionary = City.BUILDS[build]
		if info.get("weapon", -1) == weapon:
			return info["cost"] * WEAPON_PRODUCTION_VALUE + info.get("wood", 0) * WOOD_VALUE + info.get("iron", 0) * IRON_VALUE
	return 10


## Valor em ouro de um lado da proposta, dado por [param giver] a [param receiver].
static func value_of(side: Dictionary, giver: Player, receiver: Player) -> float:
	var total: float = side["gold"] + side["wood"] * WOOD_VALUE + side["iron"] * IRON_VALUE
	for weapon: int in side["weapons"]:
		total += side["weapons"][weapon] * weapon_value(weapon)
	for tech: int in side["techs"]:
		total += Technology.cost(tech) * TECH_VALUE
	if side["map"]:
		total += map_gain(giver, receiver) * MAP_CELL_VALUE
	return total


## Se [param giver] tem tudo o que o lado oferece.
static func can_give(side: Dictionary, giver: Player, receiver: Player) -> bool:
	if side["gold"] > giver.gold or side["wood"] > giver.wood or side["iron"] > giver.iron:
		return false
	for weapon: int in side["weapons"]:
		if side["weapons"][weapon] > giver.arsenal.get(weapon, 0):
			return false
	var allowed := techs_to_offer(giver, receiver)
	return side["techs"].all(func(tech: int) -> bool: return allowed.has(tech))


## Passa o lado [param side] de [param giver] para [param receiver].
static func transfer(side: Dictionary, giver: Player, receiver: Player) -> void:
	giver.gold -= side["gold"]
	receiver.gold += side["gold"]
	giver.wood -= side["wood"]
	receiver.wood += side["wood"]
	giver.iron -= side["iron"]
	receiver.iron += side["iron"]
	for weapon: int in side["weapons"]:
		var count: int = side["weapons"][weapon]
		giver.arsenal[weapon] = giver.arsenal.get(weapon, 0) - count
		receiver.arsenal[weapon] = receiver.arsenal.get(weapon, 0) + count
	for tech: int in side["techs"]:
		if not receiver.researched.has(tech):
			receiver.researched.append(tech)
		receiver.research_progress.erase(tech)
		if receiver.research == tech:
			receiver.research = -1 # já tem: escolhe outra
	if side["map"]:
		if receiver.explored.size() < giver.explored.size():
			receiver.explored.resize(giver.explored.size())
		for i in giver.explored.size():
			if giver.explored[i] != 0:
				receiver.explored[i] = 1
		for cell: Vector2i in giver.seen_cities:
			if giver.seen_cities[cell] != receiver.id:
				receiver.seen_cities[cell] = giver.seen_cities[cell]
		for city in giver.cities:
			receiver.seen_cities[city.cell] = giver.id


## Texto curto de um lado da proposta ("100 de ouro, 2 Lanças, o mapa").
static func describe(side: Dictionary) -> String:
	var parts: Array[String] = []
	if side["gold"] > 0:
		parts.append("%d de ouro" % side["gold"])
	if side["wood"] > 0:
		parts.append("%d de madeira" % side["wood"])
	if side["iron"] > 0:
		parts.append("%d de ferro" % side["iron"])
	for weapon: int in side["weapons"]:
		if side["weapons"][weapon] > 0:
			parts.append(Arsenal.amount_text(weapon, side["weapons"][weapon]))
	for tech: int in side["techs"]:
		parts.append(Technology.tech_name(tech))
	if side["map"]:
		parts.append("o mapa")
	return ", ".join(parts) if not parts.is_empty() else "nada"
