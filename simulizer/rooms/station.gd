class_name Station
extends RefCounted
## A built work station. It takes one order at a time: asks for the inputs,
## then offers a craft job, and puts the result on its output pile.

var slot: RoomSlot
## Where the worker stands.
var tile: Vector2i
var station_type: StringName
## The order being worked on, or null when idle.
var recipe: RecipeDef
## Inputs for the current order.
var request: Request
## The craft job on the board, once the inputs are in and there is room for the output.
var job: Job
## Tick at which the current craft job was offered.
var ready_tick: int = 0
## Where finished goods go. Null drops them on the floor.
var output: Pile
## The dwarf who last worked here. They treat the station as their post.
var worker_id: int = -1
var removed: bool = false


## Inputs are in but the output pile is full, so nothing can be made.
func is_blocked() -> bool:
	return recipe != null and request != null and request.is_satisfied() and job == null
