class_name SimClock
extends RefCounted
## Turns frame time into fixed sim ticks, with a speed multiplier.

## Upper bound on ticks per frame, so a hitch can't snowball.
const MAX_TICKS_PER_FRAME: int = 64

var speed: float = 1.0
## How far the sim is into the next tick (0..1). Views use it to interpolate.
var alpha: float = 0.0

var _ticks_per_second: int


func _init(ticks_per_second: int) -> void:
	_ticks_per_second = ticks_per_second


## Returns how many ticks to run for this frame.
func advance(delta: float) -> int:
	alpha += delta * speed * _ticks_per_second
	var ticks: int = mini(int(alpha), MAX_TICKS_PER_FRAME)
	alpha = minf(alpha - ticks, 1.0)
	return ticks
