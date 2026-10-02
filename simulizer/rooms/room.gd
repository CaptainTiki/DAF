class_name Room
extends RefCounted
## A stretch of dug floor that the player has given a purpose.

var id: int
var def: RoomDef
## The open space the room covers, in tiles.
var rect: Rect2i
## Row a dwarf's feet are on when standing in the room.
var feet_row: int
var slots: Array[RoomSlot] = []
var removed: bool = false
