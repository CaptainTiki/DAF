class_name JobBoard
extends RefCounted
## Central list of open work. Dwarves claim a job, and either finish it
## (it leaves the board) or release it for someone else.

## Jobs per Job.Kind, keyed by job id.
var _by_kind: Array[Dictionary] = []
var _dig_by_tile: Dictionary[Vector2i, Job] = {}
var _haul_by_item: Dictionary[int, Job] = {}
var _next_id: int = 1
## Unclaimed job count per Job.Kind.
var _unclaimed: PackedInt32Array


func _init() -> void:
	_unclaimed.resize(Job.KIND_COUNT)
	for kind in Job.KIND_COUNT:
		_by_kind.append({})


func add_dig(tile: Vector2i) -> Job:
	if _dig_by_tile.has(tile):
		return _dig_by_tile[tile]
	var job := _create(Job.Kind.DIG, tile)
	_dig_by_tile[tile] = job
	return job


## One job per loose item, so it gets carried somewhere.
func add_haul(item: Item) -> Job:
	if _haul_by_item.has(item.id):
		return _haul_by_item[item.id]
	var job := _create(Job.Kind.HAUL, item.pos)
	job.item = item
	job.item_type = item.type
	_haul_by_item[item.id] = job
	return job


func add_build(site: BuildSite) -> Job:
	var job := _create(Job.Kind.BUILD, site.tile)
	job.site = site
	return job


func add_craft(station: Station) -> Job:
	var job := _create(Job.Kind.CRAFT, station.tile)
	job.station = station
	return job


func add_harvest(plant: Plant) -> Job:
	var job := _create(Job.Kind.HARVEST, plant.tile)
	job.plant = plant
	return job


## A haul trip from a pile, made up on the spot for the dwarf who takes it.
## It is never listed, so nobody else can claim it.
func make_haul_trip(source: Pile, item_type: int) -> Job:
	var job := Job.new()
	job.id = _next_id
	_next_id += 1
	job.kind = Job.Kind.HAUL
	job.tile = source.tile
	job.source_pile = source
	job.item_type = item_type
	return job


func dig_job_at(tile: Vector2i) -> Job:
	return _dig_by_tile.get(tile)


func haul_job_for(item: Item) -> Job:
	return _haul_by_item.get(item.id)


func jobs_of(kind: Job.Kind) -> Array[Job]:
	var jobs: Array[Job] = []
	jobs.assign(_by_kind[kind].values())
	return jobs


func unclaimed_count() -> int:
	var total: int = 0
	for count: int in _unclaimed:
		total += count
	return total


func unclaimed_of(kind: Job.Kind) -> int:
	return _unclaimed[kind]


func claim(job: Job, dwarf_id: int) -> void:
	if job.claimed_by != Job.UNCLAIMED:
		return
	job.claimed_by = dwarf_id
	if job.on_board:
		_unclaimed[job.kind] -= 1


## Puts a claimed job back up for grabs. Safe to call on a job that has left the board.
func release(job: Job) -> void:
	if job.claimed_by == Job.UNCLAIMED:
		return
	job.claimed_by = Job.UNCLAIMED
	if job.on_board:
		_unclaimed[job.kind] += 1


## Takes a job off the board, whether finished or cancelled.
func remove(job: Job) -> void:
	if not job.on_board:
		return
	job.on_board = false
	if job.claimed_by == Job.UNCLAIMED:
		_unclaimed[job.kind] -= 1
	_by_kind[job.kind].erase(job.id)
	match job.kind:
		Job.Kind.DIG:
			_dig_by_tile.erase(job.tile)
		Job.Kind.HAUL:
			_haul_by_item.erase(job.item.id)


func _create(kind: Job.Kind, tile: Vector2i) -> Job:
	var job := Job.new()
	job.id = _next_id
	_next_id += 1
	job.kind = kind
	job.tile = tile
	job.on_board = true
	_by_kind[kind][job.id] = job
	_unclaimed[kind] += 1
	return job
