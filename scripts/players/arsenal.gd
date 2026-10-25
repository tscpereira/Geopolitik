class_name Arsenal
extends RefCounted

## Armas que o império estoca no arsenal (Player.arsenal: {Weapon: quantidade}).
## Armas são produzidas em prédios (ex.: Lança na Marcenaria) e gastas para
## treinar tropas (ex.: o Lanceiro leva 1 Lança). Para uma arma nova: entre no
## enum, nos nomes abaixo, em City.BUILDS (com "weapon") e no ícone
## (Icons.draw_weapon).

enum Weapon { SPEAR }

const NAMES := {
	Weapon.SPEAR: "Lança",
}

const PLURAL_NAMES := {
	Weapon.SPEAR: "Lanças",
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
