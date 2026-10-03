class_name StairLayout
extends RefCounted
## Turns a drag into the tiles of a flight of stairs.
##
## A diagonal drag makes a straight flight. A mostly vertical drag makes a
## stairwell: a zig-zag two columns wide that goes down (or up) as far as the
## drag does, so a deep shaft needs one drag instead of a flight per layer.


static func tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var delta: Vector2i = to - from
	var result: Array[Vector2i] = []
	if absi(delta.y) > absi(delta.x) + 1:
		# Zig-zag: each step down swaps between the start column and the next one over.
		var side: int = 1 if delta.x >= 0 else -1
		var down: int = 1 if delta.y >= 0 else -1
		for i in absi(delta.y) + 1:
			result.append(Vector2i(from.x + side * (i % 2), from.y + down * i))
		return result
	var step := Vector2i(1 if delta.x >= 0 else -1, 1 if delta.y >= 0 else -1)
	for i in maxi(absi(delta.x), absi(delta.y)) + 1:
		result.append(from + step * i)
	return result