class_name BuildSite
extends RefCounted
## Something waiting to be built in place: a stair tile, or a room slot
## (a bench, a chair's spot). It may need materials delivered first, then work.

var tile: Vector2i
## Materials needed before work can start. Null if it is free.
var request: Request
## Work once the materials are there. 0 means it is done the moment they arrive.
var work_ticks: int = 0
## The room slot this fills. Null for a structure.
var slot: RoomSlot
## The TileGrid.STRUCTURE_ bit this builds, when it is not a room slot.
var structure: int = 0
## True when the work is to take the structure down, not put it up.
var removing: bool = false
## The job on the board for the work part. Null if work_ticks is 0.
var job: Job
var done: bool = false


func is_ready() -> bool:
	return not done and (request == null or request.is_satisfied())
