class_name Pallet
extends RefCounted
## A stack of one resource type on a stockpile tile.

var tile: Vector2i
var material: int
var count: int = 0
## Balls on their way here. Counts against capacity so haulers don't overfill.
var reserved: int = 0
## False until the first ball arrives; until then only the spot is claimed.
var placed: bool = false
