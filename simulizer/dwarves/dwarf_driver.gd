class_name DwarfDriver
extends RefCounted
## Advances dwarves one tick: gravity, walking, finding work and doing it.
## Stateless. All state lives on the Dwarf and the Simulation passed in.

## Job score added per other dwarf using the same work spot. 1000 equals one step.
const CROWDED_SPOT_PENALTY: int = 4000


func tick(sim: Simulation, dwarf: Dwarf) -> void:
	if dwarf.move_ticks_left > 0:
		dwarf.move_ticks_left -= 1
		if dwarf.move_ticks_left > 0:
			return
	if not Pathfinder.is_supported(sim.grid, dwarf.pos.x, dwarf.pos.y):
		_fall(sim, dwarf)
		return
	match dwarf.activity:
		Dwarf.Activity.FALL:
			_go_idle(dwarf)
		Dwarf.Activity.IDLE:
			_tick_idle(sim, dwarf)
		Dwarf.Activity.WALK:
			_tick_walk(sim, dwarf)
		Dwarf.Activity.DIG, Dwarf.Activity.BUILD:
			_tick_work(sim, dwarf)


func _fall(sim: Simulation, dwarf: Dwarf) -> void:
	if dwarf.activity != Dwarf.Activity.FALL:
		_abandon_job(sim, dwarf, false)
		dwarf.activity = Dwarf.Activity.FALL
	dwarf.from_pos = dwarf.pos
	dwarf.pos.y += 1
	dwarf.move_ticks_left = sim.config.fall_ticks
	dwarf.move_ticks_total = sim.config.fall_ticks


func _go_idle(dwarf: Dwarf) -> void:
	dwarf.activity = Dwarf.Activity.IDLE
	dwarf.idle_ticks_left = 1 + dwarf.think_ticks
	dwarf.from_pos = dwarf.pos
	dwarf.path.clear()


func _tick_idle(sim: Simulation, dwarf: Dwarf) -> void:
	dwarf.idle_ticks_left -= 1
	if dwarf.idle_ticks_left > 0:
		return
	var config: SimConfig = sim.config
	@warning_ignore("integer_division")
	dwarf.idle_ticks_left = config.idle_retry_ticks + sim.rng.randi_range(0, config.idle_retry_ticks / 2)
	if sim.board.unclaimed_count() > 0:
		var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos)
		if _try_take_job(sim, dwarf, flood_map):
			return
	# Idle dwarves don't stand inside each other: all but one move along.
	if _shares_tile_with_idler(sim, dwarf) or sim.rng.randf() < config.wander_chance:
		_wander(sim, dwarf)


func _try_take_job(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	var board: JobBoard = sim.board
	if board.unclaimed_haul_count() > sim.config.haul_priority_threshold:
		return _try_haul(sim, dwarf, flood_map) \
				or _try_tile_job(sim, dwarf, flood_map, board.build_jobs()) \
				or _try_tile_job(sim, dwarf, flood_map, board.dig_jobs())
	return _try_tile_job(sim, dwarf, flood_map, board.build_jobs()) \
			or _try_tile_job(sim, dwarf, flood_map, board.dig_jobs()) \
			or _try_haul(sim, dwarf, flood_map)


## Takes the best dig or build job from the list, if any can be reached.
func _try_tile_job(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap, jobs: Array[Job]) -> bool:
	var best: Job = null
	var best_spot := Pathfinder.NO_SPOT
	var best_score: int = 0
	for job: Job in jobs:
		if not job.is_available(sim.tick_count):
			continue
		var spot: Vector2i = Pathfinder.best_access(flood_map, job.tile.x, job.tile.y, false)
		if spot == Pathfinder.NO_SPOT:
			continue
		# Nearest first; among equals take the lowest tile so balls land on the floor.
		# A spot another dwarf is using counts as a few steps further, which spreads
		# the crew along the work face instead of stacking them on one tile.
		var score: int = flood_map.distance_to(spot.x, spot.y) * 1000 - job.tile.y
		score += _dwarves_bound_for(sim, dwarf, spot) * CROWDED_SPOT_PENALTY
		if best == null or score < best_score:
			best = job
			best_spot = spot
			best_score = score
	if best == null:
		return false
	_start_job(sim, dwarf, best, flood_map.path_to(best_spot.x, best_spot.y))
	return true


func _try_haul(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	var best: Job = null
	var best_spot := Pathfinder.NO_SPOT
	var best_dist: int = 0
	for job: Job in sim.board.haul_jobs():
		if not job.is_available(sim.tick_count) or not job.item.settled:
			continue
		var spot: Vector2i = Pathfinder.best_access(flood_map, job.item.pos.x, job.item.pos.y, true)
		if spot == Pathfinder.NO_SPOT:
			continue
		var dist: int = flood_map.distance_to(spot.x, spot.y)
		if best == null or dist < best_dist:
			best = job
			best_spot = spot
			best_dist = dist
	if best == null:
		return false
	var pallet: Pallet = sim.storage.reserve(best.item.material, best.item.pos, flood_map, sim.config.pallet_capacity)
	if pallet == null:
		# Leave the ball where it is and tell the player. The cooldown lets the
		# next search consider other balls.
		_post_no_storage(sim, dwarf, best.item.material)
		best.retry_tick = sim.tick_count + sim.config.job_retry_ticks
		return false
	best.pallet = pallet
	_start_job(sim, dwarf, best, flood_map.path_to(best_spot.x, best_spot.y))
	return true


func _start_job(sim: Simulation, dwarf: Dwarf, job: Job, path: Array[Vector2i]) -> void:
	sim.board.claim(job, dwarf.id)
	dwarf.job = job
	dwarf.path = path
	dwarf.activity = Dwarf.Activity.WALK


func _wander(sim: Simulation, dwarf: Dwarf) -> void:
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos, sim.config.wander_range)
	if flood_map.reached.size() < 2:
		return
	var index: int = flood_map.reached[sim.rng.randi_range(1, flood_map.reached.size() - 1)]
	@warning_ignore("integer_division")
	dwarf.path = flood_map.path_to(index % flood_map.width, index / flood_map.width)
	dwarf.activity = Dwarf.Activity.WALK


func _tick_walk(sim: Simulation, dwarf: Dwarf) -> void:
	if dwarf.path.is_empty():
		_arrive(sim, dwarf)
		return
	var next: Vector2i = dwarf.path[0]
	if not Pathfinder.can_step(sim.grid, dwarf.pos.x, dwarf.pos.y, next.x, next.y):
		# The tunnel changed since the path was planned.
		_abandon_job(sim, dwarf, false)
		return
	dwarf.path.remove_at(0)
	dwarf.from_pos = dwarf.pos
	dwarf.pos = next
	dwarf.facing = signi(next.x - dwarf.from_pos.x)
	dwarf.move_ticks_left = _paced(dwarf, sim.config.walk_ticks)
	dwarf.move_ticks_total = dwarf.move_ticks_left


func _arrive(sim: Simulation, dwarf: Dwarf) -> void:
	var job: Job = dwarf.job
	if job == null:
		_go_idle(dwarf)
		dwarf.idle_ticks_left = sim.config.idle_retry_ticks
		return
	match job.kind:
		Job.Kind.DIG:
			_begin_dig(sim, dwarf, job)
		Job.Kind.BUILD:
			_begin_build(sim, dwarf, job)
		Job.Kind.HAUL:
			if job.picked_up:
				_deliver(sim, dwarf, job)
			else:
				_pick_up(sim, dwarf, job)


func _begin_dig(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var tile: Vector2i = job.tile
	if not _is_diggable(sim, tile) or not Pathfinder.can_reach(dwarf.pos, tile):
		_abandon_job(sim, dwarf, true)
		return
	dwarf.activity = Dwarf.Activity.DIG
	dwarf.work_tile = tile
	dwarf.work_progress = 0
	dwarf.work_total = _paced(dwarf, sim.material_def(sim.grid.material_at(tile.x, tile.y)).dig_ticks)
	dwarf.facing = signi(tile.x - dwarf.pos.x)


func _begin_build(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var tile: Vector2i = job.tile
	if not sim.grid.is_build_marked(tile.x, tile.y) or not Pathfinder.can_reach(dwarf.pos, tile):
		_abandon_job(sim, dwarf, true)
		return
	dwarf.activity = Dwarf.Activity.BUILD
	dwarf.work_tile = tile
	dwarf.work_progress = 0
	dwarf.work_total = _paced(dwarf, sim.config.stair_build_ticks)
	dwarf.facing = signi(tile.x - dwarf.pos.x)


## Digging or building: chip away until the work is done.
func _tick_work(sim: Simulation, dwarf: Dwarf) -> void:
	var building: bool = dwarf.activity == Dwarf.Activity.BUILD
	var tile: Vector2i = dwarf.work_tile
	var still_wanted: bool = sim.grid.is_build_marked(tile.x, tile.y) if building else _is_diggable(sim, tile)
	if not still_wanted:
		# Unmarked by the player, or someone else got there first.
		_abandon_job(sim, dwarf, false)
		return
	dwarf.work_progress += 1
	if dwarf.work_progress < dwarf.work_total:
		return
	dwarf.job = null
	if building:
		sim.complete_build(tile)
	else:
		dwarf.experience += 1
		dwarf.beard_length = minf(dwarf.experience / 200.0, 1.0)
		sim.complete_dig(tile)
	_go_idle(dwarf)


func _pick_up(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var item: Item = job.item
	if item.state != Item.State.LOOSE or not item.settled or not Pathfinder.can_access(dwarf.pos, item.pos):
		_abandon_job(sim, dwarf, true)
		return
	sim.pick_up_item(item)
	dwarf.carrying = item
	job.picked_up = true
	if item.pos.x != dwarf.pos.x:
		dwarf.facing = signi(item.pos.x - dwarf.pos.x)
	if not sim.storage.is_current(job.pallet):
		_abandon_job(sim, dwarf, true)
		return
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos)
	var spot: Vector2i = Pathfinder.best_access(flood_map, job.pallet.tile.x, job.pallet.tile.y, true)
	if spot == Pathfinder.NO_SPOT:
		_abandon_job(sim, dwarf, true)
		return
	dwarf.path = flood_map.path_to(spot.x, spot.y)
	dwarf.activity = Dwarf.Activity.WALK


func _deliver(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var pallet: Pallet = job.pallet
	if not sim.storage.is_current(pallet) or not Pathfinder.can_access(dwarf.pos, pallet.tile):
		_abandon_job(sim, dwarf, true)
		return
	if pallet.tile.x != dwarf.pos.x:
		dwarf.facing = signi(pallet.tile.x - dwarf.pos.x)
	sim.storage.deposit(pallet)
	job.pallet = null
	sim.remove_item(dwarf.carrying)
	dwarf.carrying = null
	dwarf.job = null
	_go_idle(dwarf)


## Drops whatever the dwarf was doing and frees the job for others.
## With cooldown the job is left alone for a while, so a job that can't be done
## right now doesn't get grabbed again every tick.
func _abandon_job(sim: Simulation, dwarf: Dwarf, cooldown: bool) -> void:
	var job: Job = dwarf.job
	dwarf.job = null
	if dwarf.carrying != null:
		sim.drop_item(dwarf.carrying, dwarf.pos)
		dwarf.carrying = null
	if job != null:
		if job.pallet != null:
			sim.storage.release(job.pallet)
			job.pallet = null
		job.picked_up = false
		if cooldown:
			job.retry_tick = sim.tick_count + sim.config.job_retry_ticks
		sim.board.release(job)
	_go_idle(dwarf)


## A duration adjusted for this dwarf's personal pace.
func _paced(dwarf: Dwarf, ticks: int) -> int:
	return maxi(1, roundi(ticks * dwarf.pace))


## How many other dwarves are at this spot or walking to it.
func _dwarves_bound_for(sim: Simulation, dwarf: Dwarf, spot: Vector2i) -> int:
	var count: int = 0
	for other: Dwarf in sim.dwarves:
		if other != dwarf and other.job != null and other.destination() == spot:
			count += 1
	return count


## True if a dwarf hired earlier is idling on the same tile. The earlier one stays.
func _shares_tile_with_idler(sim: Simulation, dwarf: Dwarf) -> bool:
	for other: Dwarf in sim.dwarves:
		if other.id < dwarf.id and other.pos == dwarf.pos and other.activity == Dwarf.Activity.IDLE:
			return true
	return false


func _is_diggable(sim: Simulation, tile: Vector2i) -> bool:
	return sim.grid.in_bounds(tile.x, tile.y) and sim.grid.is_solid(tile.x, tile.y) and sim.grid.is_dig_marked(tile.x, tile.y)


func _post_no_storage(sim: Simulation, dwarf: Dwarf, material: int) -> void:
	var def: MaterialDef = sim.material_def(material)
	var message: String
	if sim.storage.tile_count() == 0:
		message = "nowhere to put %s. Mark a stockpile." % def.display_name.to_lower()
	else:
		message = "stockpile's full, no room for a new %s pallet." % def.display_name.to_lower()
	sim.requests.post(StringName("no_storage_%s" % def.id), dwarf.display_name, message, sim.tick_count, sim.config.request_refresh_ticks)
