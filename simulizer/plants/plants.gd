class_name Plants
extends RefCounted
## Everything that grows. Plants grow a tick at a time; a full-grown one puts a
## harvest job on the board, and harvesting sets it back to bare.

## Views redraw plants when growth passes one of this many steps.
const GROWTH_STEPS: int = 20

var plants: Array[Plant] = []
## Bumped when any plant visibly changes, so views know to redraw.
var version: int = 0


func add(def: PlantDef, tile: Vector2i, growth: int) -> Plant:
	var plant := Plant.new()
	plant.def = def
	plant.tile = tile
	plant.growth = mini(growth, def.grow_ticks - 1)
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


func tick(board: JobBoard) -> void:
	for plant: Plant in plants:
		if plant.is_grown():
			continue
		var step_before: int = _step(plant)
		plant.growth += 1
		if plant.is_grown():
			plant.job = board.add_harvest(plant)
			version += 1
		elif _step(plant) != step_before:
			version += 1


## Cuts the plant back to bare. The caller drops the yield.
func harvest(plant: Plant, board: JobBoard) -> void:
	plant.growth = 0
	if plant.job != null:
		board.remove(plant.job)
		plant.job = null
	version += 1


func _step(plant: Plant) -> int:
	@warning_ignore("integer_division")
	return plant.growth * GROWTH_STEPS / maxi(plant.def.grow_ticks, 1)
