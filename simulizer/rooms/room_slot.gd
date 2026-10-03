class_name RoomSlot
extends RefCounted
## One position in a room's layout and what currently stands there.

var room: Room
var def: SlotDef
## Leftmost floor tile of the slot.
var tile: Vector2i
## Which repeat of the room's layout this belongs to. A bench and its output
## pile share a unit.
var unit: int
## True once the furniture is in place or the station is built.
var built: bool = false
## The pending build, until it is done.
var site: BuildSite
var station: Station
## STATION: the OUTPUT slot beside it, where its goods go.
var output_slot: RoomSlot
var pile: Pile
var plant: Plant
## Id of the dwarf this belongs to, or -1. A bed is kept by the first dwarf to use it.
var owner: int = -1
## Id of the dwarf using this or on the way to it, or -1.
var occupant: int = -1
