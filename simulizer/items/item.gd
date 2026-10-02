class_name Item
extends RefCounted
## A resource ball: dropped by digging, carried by haulers, absorbed into a pallet.

enum State { LOOSE, CARRIED }

var id: int
var material: int
var pos: Vector2i
## Where the current fall step started. Views interpolate from here to pos.
var from_pos: Vector2i
var move_ticks_left: int = 0
var move_ticks_total: int = 1
var state: State = State.LOOSE
## True once the ball has come to rest and can be hauled.
var settled: bool = false


func move_fraction(alpha: float) -> float:
	if move_ticks_left <= 0:
		return 1.0
	return clampf((move_ticks_total - move_ticks_left + alpha) / move_ticks_total, 0.0, 1.0)
