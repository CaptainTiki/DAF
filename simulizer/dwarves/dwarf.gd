class_name Dwarf
extends RefCounted
## State of one dwarf. Behaviour lives in DwarfDriver.

enum Activity { IDLE, WALK, WORK, FALL, SIT, REST }
enum Mood { BAD, OK, GOOD }

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

## What the dwarf is saying right now, shown in a bubble over their head.
## Empty when they have nothing to say. For now the only thing said is "!".
var speech: String = ""
## Cut off from where the dwarves arrived, with no way to walk back.
var trapped: bool = false
var trapped_check_tick: int = 0

## How well each need is met, 0..1, one per entry in SimConfig.needs.
var needs: PackedFloat32Array
## Bad slows the dwarf down, good speeds them up.
var mood: Mood = Mood.OK
## How well each need was last met: -1 poorly (the floor), 0 plainly, 1 well.
## Together with needs that have run out, this is what mood is made of.
var need_quality: PackedInt32Array
## Index of the need being seen to, while walking to or using something for it. -1 if none.
var restoring: int = -1
## How well the need being seen to will have been met, once it is.
var restoring_quality: int = 0

## The seat or bed this dwarf is using or walking to.
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
