class_name Pile
extends RefCounted
## Items stored on one tile. Capacity is in storage units; each item takes
## ItemDef.size units, so a pile holds ten balls but only three chairs.

enum Kind {
	## On a stockpile tile marked by the player. Holds a single item type.
	STOCKPILE,
	## Beside a station, where finished goods wait to be collected. Mixed types.
	OUTPUT,
	## Starting supplies. Mixed types, no limit.
	SUPPLY,
	## The spoil heap. Waste carried here is gone for good; it never holds anything.
	DUMP,
}

const UNLIMITED: int = 0
const ANY_TYPE: int = -1

var kind: Kind
var tile: Vector2i
## Units this pile can hold, or UNLIMITED.
var capacity: int = UNLIMITED
## STOCKPILE: the one item type it holds. Otherwise ANY_TYPE.
var only_type: int = ANY_TYPE
## Item count per item type.
var counts: Dictionary[int, int] = {}
var units_used: int = 0
## Units claimed by items on their way here.
var units_reserved: int = 0
## Items promised to haulers who are on their way to collect them, per type.
var reserved_out: Dictionary[int, int] = {}
## True once the pile has been taken out of storage.
var removed: bool = false


func count_of(type: int) -> int:
	return counts.get(type, 0)


## How many of a type can still be promised to a hauler.
func available(type: int) -> int:
	return count_of(type) - reserved_out.get(type, 0)


func free_units() -> int:
	if capacity == UNLIMITED:
		return 1 << 30
	return capacity - units_used - units_reserved


func accepts(type: int) -> bool:
	return only_type == ANY_TYPE or only_type == type


func is_empty() -> bool:
	return units_used == 0 and units_reserved == 0
