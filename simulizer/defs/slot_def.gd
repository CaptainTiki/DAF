class_name SlotDef
extends Resource
## One thing that can stand in a room: a piece of furniture or a station the
## player places (SimConfig.furniture), or something a room lays out by itself
## in its repeating pattern (RoomDef.slots: farm plots, storeroom floor).

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

@export var id: StringName
## As it reads in the furniture picker.
@export var display_name: String
@export var kind: Kind = Kind.FURNITURE
## Placed: room types it may go in, by RoomDef.id. Empty means any room.
@export var rooms: Array[StringName] = []
## Laid out by a room: tiles from the left edge of the layout unit.
@export var offset: int = 0
## Floor tiles this takes up.
@export var width: int = 1
## Tiles above the floor. 0 is on the floor; a shelf is 1 or 2 up.
@export var rise: int = 0
## Placed: the highest it may go. A shelf with rise 1 and rise_max 2 can be
## put on either row. Below rise means the same as rise.
@export var rise_max: int = 0
## FURNITURE: once built, goods can be stored on it (a shelf).
@export var storage: bool = false
## FURNITURE: the item to install. STATION: the material it is built from.
@export var item: ItemDef
@export var item_count: int = 1
## STATION: ticks to build it once the materials are there.
@export var work_ticks: int = 0
## STATION: which recipes it can make.
@export var station_type: StringName
## STATION: finished goods go on a pile on the tile to its right.
@export var output: bool = false
## FURNITURE: idle dwarves may sit here.
@export var seat: bool = false
## FURNITURE: the NeedDef id a dwarf satisfies by using this, such as &"sleep"
## for a bed. Empty if it satisfies nothing.
@export var satisfies: StringName
## PLANT: what grows here.
@export var plant: PlantDef


func highest_rise() -> int:
	return maxi(rise, rise_max)


## Whether this may stand in a room of the given type.
func allowed_in(room_id: StringName) -> bool:
	return rooms.is_empty() or rooms.has(room_id)
