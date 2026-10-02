class_name Scaffolder
extends RefCounted
## Puts scaffolding up where dwarves need it and takes it down when they don't.
##
## Nobody asks for scaffolding. When a tile marked for digging is too high to
## reach, a tower is planned straight up from the floor beside it, just tall
## enough to stand on and reach the tile. From the top of a tower a dwarf digs
## the column on each side and the tile straight overhead, so one tower serves
## three columns of ceiling. Once nothing in reach of a tower is
## marked for digging any more, the tower is marked to be taken down.

## Tiles of scaffolding this class planned, built or not. Player-built
## scaffolding (none yet) would not be in here and would be left alone.
var _own_tiles: Dictionary[Vector2i, bool] = {}


## Plans one tower for a marked tile that can't be reached, if there is one
## that a tower would help. `flood_map` says where the asking dwarf can walk.
## Returns true if anything was planned.
func plan(sim: Simulation, flood_map: FloodMap) -> bool:
	for job: Job in sim.board.jobs_of(Job.Kind.DIG):
		if not job.is_available(sim.tick_count):
			continue
		if Pathfinder.best_access(flood_map, job.tile.x, job.tile.y, false, true) != Pathfinder.NO_SPOT:
			continue
		var tower: Array[Vector2i] = _best_tower(sim, flood_map, job.tile)
		if tower.is_empty():
			continue
		var missing: Array[Vector2i] = []
		for tile: Vector2i in tower:
			if not sim.grid.has_scaffold(tile.x, tile.y) and not sim.grid.is_build_marked(tile.x, tile.y):
				missing.append(tile)
		if missing.is_empty():
			# Already on its way up; look at the next tile.
			continue
		for tile: Vector2i in missing:
			_own_tiles[tile] = true
		sim.mark_scaffolds(missing, true)
		return true
	return false


## Marks towers nobody needs any more to be taken down, and cancels ones that
## were planned but are no longer wanted.
func clean_up(sim: Simulation) -> void:
	if _own_tiles.is_empty():
		return
	var grid: TileGrid = sim.grid
	# Topmost and lowest row of our scaffolding per column.
	var top_row: Dictionary[int, int] = {}
	var bottom_row: Dictionary[int, int] = {}
	for tile: Vector2i in _own_tiles.keys():
		if not grid.has_scaffold(tile.x, tile.y) and not grid.is_build_marked(tile.x, tile.y):
			_own_tiles.erase(tile)
			continue
		top_row[tile.x] = mini(top_row.get(tile.x, tile.y), tile.y)
		bottom_row[tile.x] = maxi(bottom_row.get(tile.x, tile.y), tile.y)
	for tile: Vector2i in _own_tiles:
		if _is_column_needed(grid, tile.x, top_row[tile.x], bottom_row[tile.x]):
			continue
		if not grid.is_remove_marked(tile.x, tile.y):
			sim.mark_removal(Rect2i(tile, Vector2i.ONE), true, TileGrid.STRUCTURE_SCAFFOLD)


## The best tower for reaching `target`: the tiles to scaffold, bottom first.
## Empty if no tower would do it.
func _best_tower(sim: Simulation, flood_map: FloodMap, target: Vector2i) -> Array[Vector2i]:
	var grid: TileGrid = sim.grid
	var best: Array[Vector2i] = []
	var best_reach: int = 0
	# A tower can stand beside the tile, or directly under it.
	for offset: int in [-1, 1, 0]:
		var x: int = target.x + offset
		# Standing lower needs less scaffolding, so try the lowest stance first:
		# the target is then above the dwarf's head. From directly underneath
		# that is the only stance that reaches.
		var highest_stance: int = target.y - 1 if offset != 0 else target.y + 2
		for stance in range(target.y + 2, highest_stance - 1, -1):
			if not grid.is_open(x, stance) or not grid.is_open(x, stance - 1):
				continue
			# Find the floor under the stance. Everything between must be open.
			var base: int = stance
			while grid.in_bounds(x, base + 1) and grid.is_open(x, base + 1) and not grid.is_ground(x, base + 1):
				base += 1
			var height: int = base - stance
			if height < 1 or height > sim.config.scaffold_max_height:
				continue
			if not flood_map.is_reachable(x, base):
				continue
			# Prefer the tower that brings the most marked tiles into reach, so
			# one tower does for as much as it can; then the shorter one.
			var reach: int = _marked_in_reach(grid, Vector2i(x, stance))
			if best.is_empty() or reach > best_reach or (reach == best_reach and height < best.size()):
				best_reach = reach
				best.clear()
				for row in range(base, stance, -1):
					best.append(Vector2i(x, row))
			break
	return best


## A tower is still needed while a tile beside it, within reach of somewhere on
## it, is marked for digging.
func _is_column_needed(grid: TileGrid, x: int, top: int, bottom: int) -> bool:
	# Standing on the top platform puts feet at top - 1, reaching up to top - 3.
	# Standing on the floor at the bottom reaches down to bottom + 1.
	for side in 2:
		var beside: int = x + side * 2 - 1
		for y in range(top - 3, bottom + 2):
			if grid.is_solid(beside, y) and grid.is_dig_marked(beside, y):
				return true
	# And the tile straight above the top platform.
	return grid.is_solid(x, top - 3) and grid.is_dig_marked(x, top - 3)


## How many tiles marked for digging a dwarf standing here could reach.
func _marked_in_reach(grid: TileGrid, stance: Vector2i) -> int:
	var count: int = 0
	for side in 2:
		var beside: int = stance.x + side * 2 - 1
		for y in range(stance.y - 2, stance.y + 2):
			if grid.is_solid(beside, y) and grid.is_dig_marked(beside, y):
				count += 1
	if grid.is_solid(stance.x, stance.y - 2) and grid.is_dig_marked(stance.x, stance.y - 2):
		count += 1
	return count