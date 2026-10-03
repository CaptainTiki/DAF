class_name SlotDef
extends Resource
## One thing a room wants at a position in its repeating layout.

enum Kind {
	## A piece of furniture, made elsewhere and carried in.
	FURNITURE,
	## A work station, built in place from materials.
	STATION,
	## A small pile next to a station, where finished goods wait.
	OUTPUT,
	## A plot where a plant grows.
	PLANT,
	## A spot on the floor where goods are stored.
	STOCKPILE,
}

@export var kind: Kind = Kind.FURNITURE
## Tiles from the left edge of the layout unit.
@export var offset: int = 0
## Floor tiles this takes up.
@export var width: int = 1
## Tiles above the floor. 0 is on the floor; a shelf is 1 or 2 up.
@export var rise: int = 0
## FURNITURE: once built, goods can be stored on it (a shelf).
@export var storage: bool = false
## FURNITURE: the item to install. STATION: the material it is built from.
@export var item: ItemDef
@export var item_count: int = 1
## STATION: ticks to build it once the materials are there.
@export var work_ticks: int = 0
## STATION: which recipes it can make.
@export var station_type: StringName
## FURNITURE: idle dwarves may sit here.
@export var seat: bool = false
## FURNITURE: the NeedDef id a dwarf satisfies by using this, such as &"sleep"
## for a bed. Empty if it satisfies nothing.
@export var satisfies: StringName
## PLANT: what grows here.
@export var plant: PlantDef
