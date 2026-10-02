class_name FloodMap
extends RefCounted
## Result of a Pathfinder flood: step distance and route to every standing spot
## reachable from the start.

var width: int
var start: Vector2i
## Steps from the start per tile index, -1 where unreachable.
var dist: PackedInt32Array
var parent: PackedInt32Array
## Tile indices of every reached spot, nearest first. Entry 0 is the start.
var reached: PackedInt32Array


func distance_to(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0:
		return -1
	var index: int = y * width + x
	if index >= dist.size():
		return -1
	return dist[index]


func is_reachable(x: int, y: int) -> bool:
	return distance_to(x, y) >= 0


## Steps to walk from the start to (x, y), excluding the start itself.
## Empty if the target is the start or unreachable.
func path_to(x: int, y: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if distance_to(x, y) <= 0:
		return path
	var index: int = y * width + x
	var start_index: int = start.y * width + start.x
	while index != start_index and index >= 0:
		@warning_ignore("integer_division")
		path.append(Vector2i(index % width, index / width))
		index = parent[index]
	path.reverse()
	return path
