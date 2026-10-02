class_name Pathfinder
extends RefCounted
## Movement and reach rules for a dwarf (1 wide, 2 tall), plus a breadth-first
## flood over standing spots. A position is always the dwarf's feet tile.

const NO_SPOT := Vector2i(-1, -1)


## Feet and head tiles open, ground underneath.
static func can_stand(grid: TileGrid, x: int, y: int) -> bool:
	return grid.is_open(x, y) and grid.is_open(x, y - 1) and grid.is_ground(x, y + 1)


## A dwarf can be here: standing on the ground, or on a stair in the back lane.
static func can_occupy(grid: TileGrid, x: int, y: int) -> bool:
	return grid.has_stair(x, y) or can_stand(grid, x, y)


## Something holds a dwarf up here: ground underfoot, or a stair.
static func is_supported(grid: TileGrid, x: int, y: int) -> bool:
	return grid.is_ground(x, y + 1) or grid.has_stair(x, y)


## One move: sideways, or sideways and one tile up or down.
## Stepping needs clear headroom above whichever end of the step is lower,
## except on stairs, which run behind the rock and have their own space.
## The other move is a climb: straight up or down one tile, through scaffolding.
static func can_step(grid: TileGrid, x: int, y: int, to_x: int, to_y: int) -> bool:
	if to_x == x:
		# The lower of the two tiles is the scaffolding being climbed.
		return absi(to_y - y) == 1 and grid.has_scaffold(x, maxi(y, to_y)) and can_occupy(grid, to_x, to_y)
	if absi(to_x - x) != 1 or absi(to_y - y) > 1:
		return false
	if not can_occupy(grid, to_x, to_y):
		return false
	if grid.has_stair(x, y) or grid.has_stair(to_x, to_y):
		return true
	if to_y < y:
		return grid.is_open(x, y - 2)
	if to_y > y:
		return grid.is_open(to_x, to_y - 2)
	return true


## A dwarf reaches the four tiles in the column beside them:
## below feet, feet, head and above head.
static func can_reach(from: Vector2i, tile: Vector2i) -> bool:
	if absi(tile.x - from.x) != 1:
		return false
	var dy: int = tile.y - from.y
	return dy >= -2 and dy <= 1


## Digging reach: the column beside, plus the tile directly above the dwarf's
## head. Digging overhead never takes away the dwarf's own footing.
static func can_dig_from(from: Vector2i, tile: Vector2i) -> bool:
	return can_reach(from, tile) or (tile.x == from.x and tile.y == from.y - 2)


## Reach, or standing right on the tile. Used for picking up and putting down.
static func can_access(from: Vector2i, tile: Vector2i) -> bool:
	return from == tile or can_reach(from, tile)


static func flood(grid: TileGrid, start: Vector2i, max_dist: int = -1) -> FloodMap:
	var width: int = grid.width
	var height: int = grid.height
	var map := FloodMap.new()
	map.width = width
	map.start = start
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(width * height)
	parent.fill(-1)
	var queue := PackedInt32Array()
	if grid.in_bounds(start.x, start.y):
		var start_index: int = start.y * width + start.x
		dist[start_index] = 0
		queue.append(start_index)
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var d: int = dist[current]
		if max_dist >= 0 and d >= max_dist:
			continue
		var cx: int = current % width
		@warning_ignore("integer_division")
		var cy: int = current / width
		for side in 2:
			var nx: int = cx + side * 2 - 1
			if nx < 0 or nx >= width:
				continue
			for rise in 3:
				var ny: int = cy + rise - 1
				if ny < 0 or ny >= height:
					continue
				var next: int = ny * width + nx
				if dist[next] != -1:
					continue
				if not can_step(grid, cx, cy, nx, ny):
					continue
				dist[next] = d + 1
				parent[next] = current
				queue.append(next)
		# Climbing straight up or down scaffolding.
		for rise in 2:
			var ny: int = cy + rise * 2 - 1
			if ny < 0 or ny >= height:
				continue
			var next: int = ny * width + cx
			if dist[next] != -1 or not can_step(grid, cx, cy, cx, ny):
				continue
			dist[next] = d + 1
			parent[next] = current
			queue.append(next)
	map.dist = dist
	map.parent = parent
	map.reached = queue
	return map


## Nearest reachable spot from which a dwarf can work on a tile, or NO_SPOT.
## With include_self the tile itself counts if it can be stood on.
## With from_below, standing directly under the tile counts too (for digging overhead).
static func best_access(flood_map: FloodMap, tile_x: int, tile_y: int, include_self: bool, from_below: bool = false) -> Vector2i:
	var best := NO_SPOT
	var best_dist: int = -1
	if include_self:
		best_dist = flood_map.distance_to(tile_x, tile_y)
		if best_dist >= 0:
			best = Vector2i(tile_x, tile_y)
	if from_below:
		var under: int = flood_map.distance_to(tile_x, tile_y + 2)
		if under >= 0 and (best_dist < 0 or under < best_dist):
			best_dist = under
			best = Vector2i(tile_x, tile_y + 2)
	for side in 2:
		var sx: int = tile_x + side * 2 - 1
		for offset in 4:
			var sy: int = tile_y - 1 + offset
			var d: int = flood_map.distance_to(sx, sy)
			if d >= 0 and (best_dist < 0 or d < best_dist):
				best_dist = d
				best = Vector2i(sx, sy)
	return best
