class_name DwarfDriver
extends RefCounted
## Advances dwarves one tick: gravity, walking, finding work and doing it.
## Stateless. All state lives on the Dwarf and the Simulation passed in.
##
## How a dwarf picks work (staffing by demand):
## 1. A dwarf with a post (the station they last worked at) serves it first:
##    craft if it is ready, fetch its inputs, or clear its output if it is full.
## 2. Otherwise the kinds of work are ranked. A kind with work waiting and
##    nobody on it comes first, the one neglected longest at the front. After
##    that, kinds are ranked by work waiting per dwarf already on it.
## 3. The dwarf takes the nearest job of the first kind that has one in reach.

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
		Dwarf.Activity.WORK:
			_tick_work(sim, dwarf)
		Dwarf.Activity.SIT:
			_tick_sit(sim, dwarf)


# --- Moving ---

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
	if next.x != dwarf.from_pos.x:
		dwarf.facing = signi(next.x - dwarf.from_pos.x)
	dwarf.move_ticks_left = _paced(dwarf, sim.config.walk_ticks)
	dwarf.move_ticks_total = dwarf.move_ticks_left


func _arrive(sim: Simulation, dwarf: Dwarf) -> void:
	var job: Job = dwarf.job
	if job == null:
		if dwarf.seat != null and _begin_sit(sim, dwarf):
			return
		_leave_seat(dwarf)
		_go_idle(dwarf)
		dwarf.idle_ticks_left = sim.config.idle_retry_ticks
		return
	if job.kind != Job.Kind.HAUL:
		_begin_work(sim, dwarf, job)
	elif job.picked_up:
		_deliver(sim, dwarf, job)
	else:
		_pick_up(sim, dwarf, job)


# --- Idle time ---

func _tick_idle(sim: Simulation, dwarf: Dwarf) -> void:
	dwarf.idle_ticks_left -= 1
	if dwarf.idle_ticks_left > 0:
		return
	var config: SimConfig = sim.config
	@warning_ignore("integer_division")
	dwarf.idle_ticks_left = config.idle_retry_ticks + sim.rng.randi_range(0, config.idle_retry_ticks / 2)
	if _try_take_job(sim, dwarf):
		return
	_check_trapped(sim, dwarf)
	# Idle dwarves don't stand inside each other: all but one move along.
	if _shares_tile_with_idler(sim, dwarf) or sim.rng.randf() < config.wander_chance:
		if sim.rng.randf() < config.sit_chance and _try_sit(sim, dwarf):
			return
		_wander(sim, dwarf)


## Every so often an idle dwarf checks they can still walk back to where the
## dwarves arrived. One who can't says so, with a "!" and a line in the
## requests log, until a way out exists again.
func _check_trapped(sim: Simulation, dwarf: Dwarf) -> void:
	if sim.tick_count < dwarf.trapped_check_tick:
		return
	dwarf.trapped_check_tick = sim.tick_count + sim.config.trapped_check_ticks
	var home: Vector2i = sim.spawn_point()
	var trapped: bool = false
	# If the arrival spot itself has been dug away there is no home to measure against.
	if Pathfinder.can_occupy(sim.grid, home.x, home.y):
		trapped = not Pathfinder.flood(sim.grid, dwarf.pos).is_reachable(home.x, home.y)
	dwarf.trapped = trapped
	dwarf.speech = "!" if trapped else ""
	if trapped:
		sim.requests.post(StringName("trapped_%d" % dwarf.id), dwarf.display_name, "I'm trapped! Build stairs to me.", sim.tick_count, sim.config.request_refresh_ticks)


func _wander(sim: Simulation, dwarf: Dwarf) -> void:
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos, sim.config.wander_range)
	if flood_map.reached.size() < 2:
		return
	var index: int = flood_map.reached[sim.rng.randi_range(1, flood_map.reached.size() - 1)]
	@warning_ignore("integer_division")
	dwarf.path = flood_map.path_to(index % flood_map.width, index / flood_map.width)
	dwarf.activity = Dwarf.Activity.WALK


func _try_sit(sim: Simulation, dwarf: Dwarf) -> bool:
	if sim.rooms.rooms.is_empty():
		return false
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos)
	var seat: RoomSlot = sim.rooms.find_seat(flood_map)
	if seat == null:
		return false
	seat.occupant = dwarf.id
	dwarf.seat = seat
	dwarf.path = flood_map.path_to(seat.tile.x, seat.tile.y)
	dwarf.activity = Dwarf.Activity.WALK
	return true


func _begin_sit(sim: Simulation, dwarf: Dwarf) -> bool:
	var seat: RoomSlot = dwarf.seat
	if seat.room.removed or not seat.built or seat.occupant != dwarf.id or dwarf.pos != seat.tile:
		return false
	dwarf.activity = Dwarf.Activity.SIT
	dwarf.sit_ticks_left = sim.rng.randi_range(sim.config.sit_ticks_min, sim.config.sit_ticks_max)
	dwarf.from_pos = dwarf.pos
	return true


## Sitting dwarves still check the board now and then, and get up for work.
func _tick_sit(sim: Simulation, dwarf: Dwarf) -> void:
	dwarf.sit_ticks_left -= 1
	var seat: RoomSlot = dwarf.seat
	if seat == null or seat.room.removed or dwarf.sit_ticks_left <= 0:
		_leave_seat(dwarf)
		_go_idle(dwarf)
		return
	if dwarf.sit_ticks_left % sim.config.idle_retry_ticks == 0:
		_try_take_job(sim, dwarf)


func _leave_seat(dwarf: Dwarf) -> void:
	if dwarf.seat == null:
		return
	if dwarf.seat.occupant == dwarf.id:
		dwarf.seat.occupant = -1
	dwarf.seat = null


# --- Choosing work ---

func _try_take_job(sim: Simulation, dwarf: Dwarf) -> bool:
	if not _has_work(sim):
		return false
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos)
	if _try_post_duties(sim, dwarf, flood_map):
		return true
	for kind: int in _kind_order(sim):
		if _try_kind(sim, dwarf, flood_map, kind as Job.Kind):
			sim.kind_served[kind] = sim.tick_count
			return true
	return false


func _has_work(sim: Simulation) -> bool:
	return sim.board.unclaimed_count() > 0 or sim.logistics.open_count() > 0 or _has_drainable(sim)


## A dwarf with a post looks after it before anything else.
func _try_post_duties(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	var station: Station = sim.rooms.station_of(dwarf.id)
	if station == null:
		return false
	if station.job != null:
		var own_job: Array[Job] = [station.job]
		if _try_work(sim, dwarf, flood_map, own_job, true):
			return true
	if station.request != null and station.request.open_count() > 0:
		if _try_haul_for_requests(sim, dwarf, flood_map, station.request):
			return true
	if station.is_blocked():
		return _try_haul(sim, dwarf, flood_map)
	return false


## Kinds of work with something waiting, most in need of a dwarf first.
func _kind_order(sim: Simulation) -> Array[int]:
	var backlog := PackedInt32Array()
	backlog.resize(Job.KIND_COUNT)
	backlog[Job.Kind.DIG] = sim.board.unclaimed_of(Job.Kind.DIG)
	backlog[Job.Kind.CRAFT] = sim.board.unclaimed_of(Job.Kind.CRAFT)
	backlog[Job.Kind.HARVEST] = sim.board.unclaimed_of(Job.Kind.HARVEST)
	for job: Job in sim.board.jobs_of(Job.Kind.BUILD):
		if job.is_available(sim.tick_count) and job.site.is_ready() and sim.is_site_workable(job.site):
			backlog[Job.Kind.BUILD] += 1
	backlog[Job.Kind.HAUL] = sim.board.unclaimed_of(Job.Kind.HAUL) + sim.logistics.open_count()
	if _has_drainable(sim):
		backlog[Job.Kind.HAUL] += 1

	var workers := PackedInt32Array()
	workers.resize(Job.KIND_COUNT)
	for dwarf: Dwarf in sim.dwarves:
		if dwarf.job != null:
			workers[dwarf.job.kind] += 1

	var kinds: Array[int] = []
	for kind in Job.KIND_COUNT:
		if backlog[kind] > 0:
			kinds.append(kind)
	var served: PackedInt32Array = sim.kind_served
	kinds.sort_custom(func(a: int, b: int) -> bool:
		var a_unstaffed: bool = workers[a] == 0
		var b_unstaffed: bool = workers[b] == 0
		if a_unstaffed != b_unstaffed:
			return a_unstaffed
		if a_unstaffed and served[a] != served[b]:
			return served[a] < served[b]
		# Work waiting per dwarf, counting the one about to join.
		var a_load: int = backlog[a] * (workers[b] + 1)
		var b_load: int = backlog[b] * (workers[a] + 1)
		if a_load != b_load:
			return a_load > b_load
		return a < b
	)
	return kinds


func _try_kind(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap, kind: Job.Kind) -> bool:
	match kind:
		Job.Kind.HAUL:
			return _try_haul(sim, dwarf, flood_map)
		Job.Kind.DIG:
			if _try_work(sim, dwarf, flood_map, sim.board.jobs_of(kind), false):
				return true
			# Nothing in reach. If something marked is just too high, plan a tower for it.
			sim.scaffolds.plan(sim, flood_map)
			return false
	return _try_work(sim, dwarf, flood_map, sim.board.jobs_of(kind), true)


## Takes the best job from the list, if any can be reached.
## With stand_on_tile the dwarf may work standing on the job's tile as well as beside it.
func _try_work(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap, jobs: Array[Job], stand_on_tile: bool) -> bool:
	var best: Job = null
	var best_spot := Pathfinder.NO_SPOT
	var best_score: int = 0
	for job: Job in jobs:
		if not job.is_available(sim.tick_count):
			continue
		if job.kind == Job.Kind.BUILD and not (job.site.is_ready() and sim.is_site_workable(job.site)):
			continue
		if job.kind == Job.Kind.CRAFT and _is_held_for_another(sim, dwarf, job.station):
			continue
		var removing: bool = _must_work_from_beside(job)
		# Nobody takes down what they are standing on.
		var spot: Vector2i = Pathfinder.best_access(flood_map, job.tile.x, job.tile.y, stand_on_tile and not removing, job.kind == Job.Kind.DIG)
		if spot == Pathfinder.NO_SPOT:
			continue
		# Nearest first; among equals take the lowest tile so balls land on the floor.
		# A spot another dwarf is using counts as a few steps further, which spreads
		# the crew along the work face instead of stacking them on one tile.
		var score: int = flood_map.distance_to(spot.x, spot.y) * 1000 - job.tile.y
		score += _dwarves_bound_for(sim, dwarf, spot) * CROWDED_SPOT_PENALTY
		if job.kind == Job.Kind.BUILD and job.site.removing:
			# Taking things down starts at the far end, so the dwarf works back
			# towards the way out and never cuts off the rest of the run.
			score = -score
		if best == null or score < best_score:
			best = job
			best_spot = spot
			best_score = score
	if best == null:
		return false
	_start_job(sim, dwarf, best, flood_map.path_to(best_spot.x, best_spot.y))
	return true


## Stairs and floors hold up whoever stands in or on their tile, so they are
## taken down from the tile beside. Scaffolding holds up the tile above, so a
## dwarf can take it down while standing in it.
func _must_work_from_beside(job: Job) -> bool:
	return job.kind == Job.Kind.BUILD and job.site.removing and job.site.structure != TileGrid.STRUCTURE_SCAFFOLD


## A station's craft job is kept for the dwarf whose post it is, for a while.
## If they don't turn up, anyone may take it and the post changes hands.
func _is_held_for_another(sim: Simulation, dwarf: Dwarf, station: Station) -> bool:
	if station.worker_id == -1 or station.worker_id == dwarf.id:
		return false
	return sim.tick_count - station.ready_tick < sim.config.post_patience_ticks


func _start_job(sim: Simulation, dwarf: Dwarf, job: Job, path: Array[Vector2i]) -> void:
	_leave_seat(dwarf)
	# Check again as soon as this job is done, so the "!" clears promptly once
	# there is a way out, and comes back if there still isn't.
	dwarf.trapped_check_tick = 0
	sim.board.claim(job, dwarf.id)
	dwarf.job = job
	dwarf.path = path
	dwarf.activity = Dwarf.Activity.WALK


# --- Working: dig, build, craft, harvest ---

func _begin_work(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var in_position: bool = Pathfinder.can_reach(dwarf.pos, job.tile)
	if job.kind == Job.Kind.DIG:
		in_position = Pathfinder.can_dig_from(dwarf.pos, job.tile)
	elif not _must_work_from_beside(job):
		in_position = Pathfinder.can_access(dwarf.pos, job.tile)
	if not in_position or not _is_job_valid(sim, job):
		_abandon_job(sim, dwarf, true)
		return
	dwarf.activity = Dwarf.Activity.WORK
	dwarf.work_tile = job.tile
	dwarf.work_progress = 0
	dwarf.work_total = _paced(dwarf, _work_ticks(sim, job))
	if job.tile.x != dwarf.pos.x:
		dwarf.facing = signi(job.tile.x - dwarf.pos.x)
	if job.kind == Job.Kind.CRAFT:
		job.station.worker_id = dwarf.id


func _tick_work(sim: Simulation, dwarf: Dwarf) -> void:
	var job: Job = dwarf.job
	if job == null or not _is_job_valid(sim, job):
		# Cancelled by the player, or someone else got there first.
		_abandon_job(sim, dwarf, false)
		return
	dwarf.work_progress += 1
	if dwarf.work_progress < dwarf.work_total:
		return
	if job.kind == Job.Kind.BUILD and not sim.can_complete_site(job.site, dwarf):
		# Someone is on it, or taking it down would strand this dwarf. Try later.
		_abandon_job(sim, dwarf, true)
		return
	dwarf.job = null
	match job.kind:
		Job.Kind.DIG:
			dwarf.experience += 1
			dwarf.beard_length = minf(dwarf.experience / 200.0, 1.0)
			sim.complete_dig(job.tile)
		Job.Kind.BUILD:
			sim.complete_site(job.site)
		Job.Kind.CRAFT:
			sim.complete_craft(job.station)
		Job.Kind.HARVEST:
			sim.complete_harvest(job.plant)
	_go_idle(dwarf)


func _is_job_valid(sim: Simulation, job: Job) -> bool:
	match job.kind:
		Job.Kind.DIG:
			return sim.grid.in_bounds(job.tile.x, job.tile.y) and sim.grid.is_solid(job.tile.x, job.tile.y) and sim.grid.is_dig_marked(job.tile.x, job.tile.y)
		Job.Kind.BUILD:
			return job.on_board and job.site.is_ready()
	return job.on_board


func _work_ticks(sim: Simulation, job: Job) -> int:
	match job.kind:
		Job.Kind.DIG:
			return sim.material_def(sim.grid.material_at(job.tile.x, job.tile.y)).dig_ticks
		Job.Kind.BUILD:
			return job.site.work_ticks
		Job.Kind.CRAFT:
			return job.station.recipe.work_ticks
		Job.Kind.HARVEST:
			return job.plant.def.harvest_ticks
	return 1


# --- Hauling ---

## Deliveries someone asked for come first, then loose items to the stockpile,
## then clearing output and supply piles into the stockpile.
func _try_haul(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	return _try_haul_for_requests(sim, dwarf, flood_map, null) \
			or _try_haul_loose(sim, dwarf, flood_map) \
			or _try_haul_drain(sim, dwarf, flood_map)


## Finds an item for a request and sets off to fetch it. With only_request the
## search is limited to that one request.
func _try_haul_for_requests(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap, only_request: Request) -> bool:
	var candidates: Array[Request] = sim.logistics.requests
	if only_request != null:
		var single: Array[Request] = [only_request]
		candidates = single
	var loose_jobs: Array[Job] = sim.board.jobs_of(Job.Kind.HAUL)
	var best_request: Request = null
	var best_job: Job = null
	var best_pile: Pile = null
	var best_spot := Pathfinder.NO_SPOT
	var best_dist: int = 0
	var unmet: Request = null
	for request: Request in candidates:
		if request.open_count() <= 0:
			continue
		if Pathfinder.best_access(flood_map, request.tile.x, request.tile.y, true) == Pathfinder.NO_SPOT:
			continue
		var found: bool = false
		for job: Job in loose_jobs:
			var item: Item = job.item
			if item.type != request.item_type or not item.settled or not job.is_available(sim.tick_count):
				continue
			var spot: Vector2i = Pathfinder.best_access(flood_map, item.pos.x, item.pos.y, true)
			if spot == Pathfinder.NO_SPOT:
				continue
			found = true
			var dist: int = flood_map.distance_to(spot.x, spot.y)
			if best_request == null or dist < best_dist:
				best_request = request
				best_job = job
				best_pile = null
				best_spot = spot
				best_dist = dist
		var pile: Pile = sim.storage.find_source(request.item_type, flood_map)
		if pile != null:
			found = true
			var spot: Vector2i = Pathfinder.best_access(flood_map, pile.tile.x, pile.tile.y, true)
			var dist: int = flood_map.distance_to(spot.x, spot.y)
			if best_request == null or dist < best_dist:
				best_request = request
				best_job = null
				best_pile = pile
				best_spot = spot
				best_dist = dist
		if not found and unmet == null:
			unmet = request
	if best_request == null:
		if unmet != null:
			_post_missing_item(sim, dwarf, unmet)
		return false
	var trip: Job = best_job
	if trip == null:
		trip = sim.board.make_haul_trip(best_pile, best_request.item_type)
		sim.storage.reserve_out(best_pile, best_request.item_type)
	trip.dest_request = best_request
	best_request.incoming += 1
	_start_job(sim, dwarf, trip, flood_map.path_to(best_spot.x, best_spot.y))
	return true


## Carries the nearest loose item to the stockpile.
func _try_haul_loose(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	var best: Job = null
	var best_spot := Pathfinder.NO_SPOT
	var best_dist: int = 0
	for job: Job in sim.board.jobs_of(Job.Kind.HAUL):
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
	var pile: Pile = sim.storage.reserve_stock_space(best.item.type, best.item.pos, flood_map)
	if pile == null:
		# Leave the item where it is and tell the player. The cooldown lets the
		# next search consider other items.
		_post_no_storage(sim, dwarf, best.item.type)
		best.retry_tick = sim.tick_count + sim.config.job_retry_ticks
		return false
	best.dest_pile = pile
	_start_job(sim, dwarf, best, flood_map.path_to(best_spot.x, best_spot.y))
	return true


## Moves something nobody is asking for from an output or supply pile into the stockpile.
func _try_haul_drain(sim: Simulation, dwarf: Dwarf, flood_map: FloodMap) -> bool:
	if sim.storage.tile_count() == 0:
		return false
	for pile: Pile in sim.storage.piles:
		if pile.kind == Pile.Kind.STOCKPILE or pile.units_used == 0:
			continue
		var spot: Vector2i = Pathfinder.best_access(flood_map, pile.tile.x, pile.tile.y, true)
		if spot == Pathfinder.NO_SPOT:
			continue
		for type: int in pile.counts:
			if pile.available(type) <= 0 or sim.logistics.open_count_of(type) > 0:
				continue
			var dest: Pile = sim.storage.reserve_stock_space(type, pile.tile, flood_map)
			if dest == null:
				continue
			var trip: Job = sim.board.make_haul_trip(pile, type)
			sim.storage.reserve_out(pile, type)
			trip.dest_pile = dest
			_start_job(sim, dwarf, trip, flood_map.path_to(spot.x, spot.y))
			return true
	return false


func _has_drainable(sim: Simulation) -> bool:
	if sim.storage.tile_count() == 0:
		return false
	for pile: Pile in sim.storage.piles:
		if pile.kind != Pile.Kind.STOCKPILE and pile.units_used > 0:
			return true
	return false


func _pick_up(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var item: Item = job.item
	if job.source_pile != null:
		var pile: Pile = job.source_pile
		if not Pathfinder.can_access(dwarf.pos, pile.tile):
			_abandon_job(sim, dwarf, true)
			return
		job.source_pile = null
		if not sim.storage.take(pile, job.item_type):
			_abandon_job(sim, dwarf, true)
			return
		item = sim.create_carried_item(job.item_type, dwarf.pos)
		job.item = item
		if pile.tile.x != dwarf.pos.x:
			dwarf.facing = signi(pile.tile.x - dwarf.pos.x)
	else:
		if item.state != Item.State.LOOSE or not item.settled or not Pathfinder.can_access(dwarf.pos, item.pos):
			_abandon_job(sim, dwarf, true)
			return
		if item.pos.x != dwarf.pos.x:
			dwarf.facing = signi(item.pos.x - dwarf.pos.x)
		sim.pick_up_item(item)
	dwarf.carrying = item
	job.picked_up = true

	if not _is_destination_alive(job):
		_abandon_job(sim, dwarf, true)
		return
	var target: Vector2i = _destination_tile(job)
	var flood_map: FloodMap = Pathfinder.flood(sim.grid, dwarf.pos)
	var spot: Vector2i = Pathfinder.best_access(flood_map, target.x, target.y, true)
	if spot == Pathfinder.NO_SPOT:
		_abandon_job(sim, dwarf, true)
		return
	dwarf.path = flood_map.path_to(spot.x, spot.y)
	dwarf.activity = Dwarf.Activity.WALK


func _deliver(sim: Simulation, dwarf: Dwarf, job: Job) -> void:
	var target: Vector2i = _destination_tile(job)
	if not _is_destination_alive(job) or not Pathfinder.can_access(dwarf.pos, target):
		_abandon_job(sim, dwarf, true)
		return
	if target.x != dwarf.pos.x:
		dwarf.facing = signi(target.x - dwarf.pos.x)
	if job.dest_request != null:
		job.dest_request.incoming = maxi(job.dest_request.incoming - 1, 0)
		job.dest_request.delivered += 1
		job.dest_request = null
	else:
		sim.storage.deposit(job.dest_pile, job.item_type)
		job.dest_pile = null
	sim.remove_item(dwarf.carrying)
	dwarf.carrying = null
	dwarf.job = null
	_go_idle(dwarf)


func _is_destination_alive(job: Job) -> bool:
	if job.dest_request != null:
		return not job.dest_request.closed
	return job.dest_pile != null and not job.dest_pile.removed


func _destination_tile(job: Job) -> Vector2i:
	if job.dest_request != null:
		return job.dest_request.tile
	return job.dest_pile.tile if job.dest_pile != null else job.tile


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
		if job.dest_request != null:
			job.dest_request.incoming = maxi(job.dest_request.incoming - 1, 0)
			job.dest_request = null
		if job.dest_pile != null:
			sim.storage.release_space(job.dest_pile, job.item_type)
			job.dest_pile = null
		if job.source_pile != null:
			sim.storage.release_out(job.source_pile, job.item_type)
			job.source_pile = null
		job.picked_up = false
		if cooldown:
			job.retry_tick = sim.tick_count + sim.config.job_retry_ticks
		sim.board.release(job)
	_leave_seat(dwarf)
	_go_idle(dwarf)


# --- Helpers ---

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


func _post_no_storage(sim: Simulation, dwarf: Dwarf, type: int) -> void:
	var def: ItemDef = sim.item_def(type)
	var message: String
	if sim.storage.tile_count() == 0:
		message = "nowhere to put %s. Mark a stockpile." % def.display_name.to_lower()
	else:
		message = "stockpile's full, no room for more %s." % def.display_name.to_lower()
	sim.requests.post(StringName("no_storage_%s" % def.id), dwarf.display_name, message, sim.tick_count, sim.config.request_refresh_ticks)


## Reports a request nobody can fill. Things a station can make are left out:
## they are simply still being made.
func _post_missing_item(sim: Simulation, dwarf: Dwarf, request: Request) -> void:
	if sim.is_craftable(request.item_type):
		return
	var def: ItemDef = sim.item_def(request.item_type)
	var message: String = "no %s for %s." % [def.display_name.to_lower(), request.purpose]
	sim.requests.post(StringName("missing_%s" % def.id), dwarf.display_name, message, sim.tick_count, sim.config.request_refresh_ticks)
