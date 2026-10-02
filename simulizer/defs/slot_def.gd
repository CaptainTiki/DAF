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
}

@export var kind: Kind = Kind.FURNITURE
## Tiles from the left edge of the layout unit.
@export var offset: int = 0
## Floor tiles this takes up.
@export var width: int = 1
## FURNITURE: the item to install. STATION: the material it is built from.
@export var item: ItemDef
@export var item_count: int = 1
## STATION: ticks to build it once the materials are there.
@export var work_ticks: int = 0
## STATION: which recipes it can make.
@export var station_type: StringName
## FURNITURE: idle dwarves may sit here.
@export var seat: bool = false
## PLANT: what grows here.
@export var plant: PlantDef
