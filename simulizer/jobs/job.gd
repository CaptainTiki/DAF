class_name Job
extends RefCounted
## One unit of work on the job board. Claimed by at most one dwarf at a time.

enum Kind { DIG, HAUL, BUILD }

const UNCLAIMED: int = -1

var id: int
var kind: Kind
## DIG: the tile to dig. BUILD: the tile to build in.
var tile: Vector2i
## HAUL: the ball to move.
var item: Item
## HAUL: the pallet reserved for the ball while the job is claimed.
var pallet: Pallet
## HAUL: true once the dwarf is carrying the ball.
var picked_up: bool = false
var claimed_by: int = UNCLAIMED
## Nobody takes this job before this tick. Set after a failed attempt.
var retry_tick: int = 0
## False once the job is finished or cancelled.
var on_board: bool = false


func is_available(tick: int) -> bool:
	return on_board and claimed_by == UNCLAIMED and retry_tick <= tick
