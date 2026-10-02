class_name Plant
extends RefCounted
## One growing thing on a tile: a surface tree, a farmed mushroom.

var def: PlantDef
## Tile at its base, where a dwarf's feet would be.
var tile: Vector2i
## This plant's own growth speed, rolled when planted. 1.1 grows 10% faster.
var speed: float = 1.0
## Ticks this plant takes from bare to ready, after its speed.
var grow_ticks: int = 1
## Ticks grown so far, up to grow_ticks.
var growth: int = 0
## The harvest job on the board while it is full grown.
var job: Job
var removed: bool = false


func growth_fraction() -> float:
	return clampf(float(growth) / grow_ticks, 0.0, 1.0)


func is_grown() -> bool:
	return growth >= grow_ticks
