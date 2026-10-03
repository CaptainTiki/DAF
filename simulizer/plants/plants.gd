class_name Plants
extends RefCounted
## Everything that grows. Plants grow a tick at a time; a full-grown one puts a
## harvest job on the board, and harvesting sets it back to bare.

## Views redraw plants when growth passes one of this many steps.
const GROWTH_STEPS: int = 20

var plants: Array[Plant] = []
## Bumped when any plant visibly changes, so views know to redraw.
var version: int = 0


## Plants something. `growth` is the head start in ticks; `speed` is this
## plant's own growth speed (see Simulation.roll_growth_speed).
func add(def: PlantDef, tile: Vector2i, growth: int, speed: float = 1.0) -> Plant:
	var plant := Plant.new()
	plant.def = def
	plant.tile = tile
	plant.speed = speed
	plant.grow_ticks = maxi(roundi(def.grow_ticks / speed), 1)
	plant.growth = clampi(growth, 0, plant.grow_ticks - 1)
	plants.append(plant)
	version += 1
	return plant


func remove(plant: Plant, board: JobBoard) -> void:
	plant.removed = true
	plants.erase(plant)
	if plant.job != null:
		board.remove(plant.job)
		plant.job = null
	version += 1


## Grows every plant a tick. A full-grown plant offers a harvest job while its
## yield is wanted: always, or only while storage is short of it if the yield
## item has a stock target. A job no longer wanted is withdrawn until it is.
func tick(sim: Simulation) -> void:
	var board: JobBoard = sim.board
	for plant: Plant in plants:
		if plant.is_grown():
			if sim.tick_count % Simulation.STOCK_INTERVAL != 0:
				continue
			var wanted: bool = _is_wanted(sim, plant)
			if wanted and plant.job == null:
				plant.job = board.add_harvest(plant)
			elif not wanted and plant.job != null and plant.job.claimed_by == Job.UNCLAIMED:
				board.remove(plant.job)
				plant.job = null
			continue
		var step_before: int = _step(plant)
		plant.growth += 1
		if plant.is_grown():
			if _is_wanted(sim, plant):
				plant.job = board.add_harvest(plant)
			version += 1
		elif _step(plant) != step_before:
			version += 1


func _is_wanted(sim: Simulation, plant: Plant) -> bool:
	var type: int = sim.item_type(plant.def.yield_item)
	if type == Simulation.NO_ITEM:
		return false
	var target: int = sim.item_def(type).stock_target
	return target == 0 or sim.storage.totals[type] < target


## Cuts the plant back to bare. The caller drops the yield.
func harvest(plant: Plant, board: JobBoard) -> void:
	plant.growth = 0
	if plant.job != null:
		board.remove(plant.job)
		plant.job = null
	version += 1


func _step(plant: Plant) -> int:
	@warning_ignore("integer_division")
	return plant.growth * GROWTH_STEPS / plant.grow_ticks
