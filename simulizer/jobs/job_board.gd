class_name JobBoard
extends RefCounted
## Central list of open work. Dwarves claim a job, and either finish it
## (it leaves the board) or release it for someone else.

var _dig_by_tile: Dictionary[Vector2i, Job] = {}
var _build_by_tile: Dictionary[Vector2i, Job] = {}
var _haul_by_item: Dictionary[int, Job] = {}
var _next_id: int = 1
## Unclaimed job count per Job.Kind.
var _unclaimed: Array[int] = [0, 0, 0]


func add_dig(tile: Vector2i) -> Job:
	if _dig_by_tile.has(tile):
		return _dig_by_tile[tile]
	var job := _create(Job.Kind.DIG)
	job.tile = tile
	_dig_by_tile[tile] = job
	return job


func add_build(tile: Vector2i) -> Job:
	if _build_by_tile.has(tile):
		return _build_by_tile[tile]
	var job := _create(Job.Kind.BUILD)
	job.tile = tile
	_build_by_tile[tile] = job
	return job


func add_haul(item: Item) -> Job:
	if _haul_by_item.has(item.id):
		return _haul_by_item[item.id]
	var job := _create(Job.Kind.HAUL)
	job.item = item
	_haul_by_item[item.id] = job
	return job


func dig_job_at(tile: Vector2i) -> Job:
	return _dig_by_tile.get(tile)


func build_job_at(tile: Vector2i) -> Job:
	return _build_by_tile.get(tile)


func haul_job_for(item: Item) -> Job:
	return _haul_by_item.get(item.id)


func dig_jobs() -> Array[Job]:
	var jobs: Array[Job] = []
	jobs.assign(_dig_by_tile.values())
	return jobs


func build_jobs() -> Array[Job]:
	var jobs: Array[Job] = []
	jobs.assign(_build_by_tile.values())
	return jobs


func haul_jobs() -> Array[Job]:
	var jobs: Array[Job] = []
	jobs.assign(_haul_by_item.values())
	return jobs


func unclaimed_count() -> int:
	return _unclaimed[Job.Kind.DIG] + _unclaimed[Job.Kind.HAUL] + _unclaimed[Job.Kind.BUILD]


func unclaimed_haul_count() -> int:
	return _unclaimed[Job.Kind.HAUL]


func claim(job: Job, dwarf_id: int) -> void:
	if not job.on_board or job.claimed_by != Job.UNCLAIMED:
		return
	job.claimed_by = dwarf_id
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
	match job.kind:
		Job.Kind.DIG:
			_dig_by_tile.erase(job.tile)
		Job.Kind.BUILD:
			_build_by_tile.erase(job.tile)
		Job.Kind.HAUL:
			_haul_by_item.erase(job.item.id)


func _create(kind: Job.Kind) -> Job:
	var job := Job.new()
	job.id = _next_id
	_next_id += 1
	job.kind = kind
	job.on_board = true
	_unclaimed[kind] += 1
	return job
