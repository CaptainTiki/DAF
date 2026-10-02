class_name Request
extends RefCounted
## A place asking for items: wood at a bench, a chair at a hall slot, wood at
## a planned stair. Haulers bring items to it from wherever they can be found.

var tile: Vector2i
var item_type: int
var wanted: int
var delivered: int = 0
## Items a hauler has claimed for this request and is bringing.
var incoming: int = 0
## What the items are for, as it reads in the requests log ("the stairs").
var purpose: String
var closed: bool = false


## How many more need a hauler assigned.
func open_count() -> int:
	if closed:
		return 0
	return maxi(wanted - delivered - incoming, 0)


func is_satisfied() -> bool:
	return delivered >= wanted
