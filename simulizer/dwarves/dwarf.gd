class_name Dwarf
extends RefCounted
## State of one dwarf. Behaviour lives in DwarfDriver.

enum Activity { IDLE, WALK, WORK, FALL, SIT }

var id: int
var display_name: String
## Tiles dug so far. Beards grow with experience.
var experience: int = 0
var beard_length: float = 0.0
## Personal tempo, fixed at hiring. think_ticks is the pause before acting on a
## new decision; pace multiplies how long walking and working take.
var think_ticks: int = 0
var pace: float = 1.0

## Feet tile. The head is the tile above.
var pos: Vector2i
## Where the current step started. Views interpolate from here to pos.
var from_pos: Vector2i
var move_ticks_left: int = 0
var move_ticks_total: int = 1
## 1 facing right, -1 facing left.
var facing: int = 1

var activity: Activity = Activity.IDLE
var idle_ticks_left: int = 1
var path: Array[Vector2i] = []
var job: Job
var carrying: Item

var work_tile: Vector2i
var work_progress: int = 0
var work_total: int = 1

## The seat this dwarf is sitting on or walking to, when taking a break.
var seat: RoomSlot
var sit_ticks_left: int = 0


func move_fraction(alpha: float) -> float:
	if move_ticks_left <= 0:
		return 1.0
	return clampf((move_ticks_total - move_ticks_left + alpha) / move_ticks_total, 0.0, 1.0)


## Where the dwarf will be once the current walk is done.
func destination() -> Vector2i:
	return pos if path.is_empty() else path[path.size() - 1]


func work_fraction() -> float:
	return clampf(float(work_progress) / work_total, 0.0, 1.0)
