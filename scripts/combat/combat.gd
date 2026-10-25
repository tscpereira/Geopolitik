class_name Combat
extends RefCounted

## Batalha por desgaste de energia (inspirada no Civilization V/VI):
## cada ataque tira energia dos dois lados e a unidade é destruída ao chegar a 0.
##
##   força de ataque = (Ataque + anticavalaria) × fator de energia × bônus de ataque
##   força de defesa = (Defesa + rio + anticavalaria) × fator de energia × bônus de defesa
## Anticavalaria: unidade com anti_cavalry_bonus (Lanceiro: +1) ganha o bônus no
## ataque e na defesa quando o adversário é cavalaria (is_mounted: Cavaleiro).
## Rio: o defensor ganha +1 se o ataque vem do outro lado de um rio
## (Unit.river_defense_bonus). Por isso as funções recebem a casa de onde o
## atacante ataca ([param from_cell]); sem ela, vale a casa em que ele está.
##   razão           = força de ataque / força de defesa
##   dano ao defensor = BASE_DAMAGE × √razão × sorte
##   dano ao atacante = BASE_DAMAGE ÷ √razão × sorte

## Dano trocado entre duas unidades de mesma força.
const BASE_DAMAGE := 30.0
## Variação aleatória do dano: 0.1 = ±10%.
const LUCK := 0.10
## Fração da força com que a unidade luta quando está com energia 0
## (com energia cheia, luta com 100%).
const MIN_ENERGY_FACTOR := 0.5
## Evita divisão por zero com unidades de força 0.
const MIN_STRENGTH := 0.01


class Result:
	var damage_to_defender := 0
	var damage_to_attacker := 0
	var defender_destroyed := false
	var attacker_destroyed := false


static func energy_factor(unit: Unit) -> float:
	var ratio := float(unit.energy) / unit.max_energy
	return MIN_ENERGY_FACTOR + (1.0 - MIN_ENERGY_FACTOR) * ratio


## Multiplicador de ataque (terreno, etc.). Ainda sem bônus.
static func attack_bonus(_attacker: Unit, _defender: Unit) -> float:
	return 1.0


## Multiplicador de defesa (montanha, fortificação, etc.). Ainda sem bônus.
static func defense_bonus(_attacker: Unit, _defender: Unit) -> float:
	return 1.0


static func attack_strength(attacker: Unit, defender: Unit) -> float:
	return (attacker.attack + anti_cavalry(attacker, defender)) * energy_factor(attacker) * attack_bonus(attacker, defender)


static func defense_strength(attacker: Unit, defender: Unit, from_cell := Unit.NO_TARGET) -> float:
	var origin := attacker.cell if from_cell == Unit.NO_TARGET else from_cell
	return (defender.defense + defender.river_defense_bonus(origin) + anti_cavalry(defender, attacker)) \
			* energy_factor(defender) * defense_bonus(attacker, defender)


## Bônus de [param unit] por lutar contra [param enemy] de cavalaria
## (UnitType.anti_cavalry_bonus; 0 se o inimigo não for cavalaria).
static func anti_cavalry(unit: Unit, enemy: Unit) -> int:
	return unit.type.anti_cavalry_bonus if enemy.type.is_mounted else 0


## Dano médio esperado, sem a sorte: {"to_defender": float, "to_attacker": float}.
static func expected_damage(attacker: Unit, defender: Unit, from_cell := Unit.NO_TARGET) -> Dictionary:
	var ratio := sqrt(maxf(attack_strength(attacker, defender), MIN_STRENGTH)
			/ maxf(defense_strength(attacker, defender, from_cell), MIN_STRENGTH))
	return {
		"to_defender": BASE_DAMAGE * ratio,
		"to_attacker": BASE_DAMAGE / ratio,
	}


## Resolve um ataque e aplica o dano às duas unidades (o atacante já está na
## casa de onde ataca).
static func resolve(attacker: Unit, defender: Unit, rng: RandomNumberGenerator) -> Result:
	var expected := expected_damage(attacker, defender)
	var result := Result.new()
	result.damage_to_defender = _roll(expected["to_defender"], rng)
	result.damage_to_attacker = _roll(expected["to_attacker"], rng)

	var attacker_energy_before := attacker.energy
	defender.energy -= result.damage_to_defender
	attacker.energy -= result.damage_to_attacker

	result.defender_destroyed = defender.energy <= 0
	if result.defender_destroyed and attacker.energy <= 0:
		# Os dois cairiam: o defensor cai primeiro e o atacante resiste com 1.
		attacker.energy = 1
		result.damage_to_attacker = attacker_energy_before - 1
	result.attacker_destroyed = attacker.energy <= 0
	return result


static func _roll(value: float, rng: RandomNumberGenerator) -> int:
	return maxi(1, roundi(value * rng.randf_range(1.0 - LUCK, 1.0 + LUCK)))
