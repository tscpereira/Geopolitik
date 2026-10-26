class_name Arsenal
extends RefCounted

## Armas que o império estoca no arsenal (Player.arsenal: {Weapon: quantidade}).
## Armas são produzidas em prédios (Lança, Arco, a máquina da Catapulta e o casco da Galé na
## Marcenaria; Espada Curta na Forja) e gastas para treinar tropas no Quartel
## General (ex.: o Lanceiro leva 1 Lança; a Catapulta, 1 máquina). Para uma arma nova: entre no
## enum, nos nomes abaixo, em City.BUILDS (com "weapon") e no ícone
## (Icons.draw_weapon).

## Novas armas entram no fim: o save guarda o número de cada uma.
enum Weapon { SPEAR, SHORT_SWORD, BOW, CATAPULT, GALLEY }

const NAMES := {
	Weapon.SPEAR: "Lança",
	Weapon.SHORT_SWORD: "Espada Curta",
	Weapon.BOW: "Arco",
	Weapon.CATAPULT: "Catapulta",
	Weapon.GALLEY: "Galé",
}

const PLURAL_NAMES := {
	Weapon.SPEAR: "Lanças",
	Weapon.SHORT_SWORD: "Espadas Curtas",
	Weapon.BOW: "Arcos",
	Weapon.CATAPULT: "Catapultas",
	Weapon.GALLEY: "Galés",
}


## Arsenal vazio: {Weapon: 0} para todas as armas.
static func empty() -> Dictionary:
	var stock := {}
	for weapon: Weapon in NAMES:
		stock[weapon] = 0
	return stock


## "1 Lança", "3 Lanças".
static func amount_text(weapon: Weapon, amount: int) -> String:
	return "%d %s" % [amount, NAMES[weapon] if amount == 1 else PLURAL_NAMES[weapon]]
