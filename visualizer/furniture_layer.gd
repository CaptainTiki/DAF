class_name FurnitureLayer
extends Node3D
## Draws what rooms contain (furniture, benches, the faint outline of what is
## still to come) and everything that grows. Rebuilt only when something changes.

const BENCH_COLOR := Color(0.6, 0.44, 0.26)
const GHOST_ALPHA: float = 0.28

@onready var _solid: MultiMeshInstance3D = $Solid
@onready var _ghost: MultiMeshInstance3D = $Ghost

var _sim: Simulation
var _solid_batch: BoxBatch
var _ghost_batch: BoxBatch
var _dirty: bool = true
var _last_plants_version: int = -1


func bind(sim: Simulation) -> void:
	_sim = sim
	_solid_batch = BoxBatch.new(_solid.multimesh)
	_ghost_batch = BoxBatch.new(_ghost.multimesh)
	sim.rooms.changed.connect(func() -> void: _dirty = true)


## Shows or hides what is planned but not built yet.
func set_planned_visible(enabled: bool) -> void:
	_ghost.visible = enabled


func refresh() -> void:
	if not _dirty and _sim.plants.version == _last_plants_version:
		return
	_dirty = false
	_last_plants_version = _sim.plants.version
	_solid_batch.begin()
	_ghost_batch.begin()
	for room: Room in _sim.rooms.rooms:
		for slot: RoomSlot in room.slots:
			_add_slot(slot)
	for plant: Plant in _sim.plants.plants:
		var base: Vector3 = ViewSpace.tile_floor(plant.tile.x, plant.tile.y, ViewSpace.LANE_STRUCTURE)
		GreyboxShapes.add_plant(_solid_batch, plant.def, plant.growth_fraction(), base)
	_solid_batch.commit()
	_ghost_batch.commit()


func _add_slot(slot: RoomSlot) -> void:
	var batch: BoxBatch = _solid_batch if slot.built else _ghost_batch
	var alpha: float = 1.0 if slot.built else GHOST_ALPHA
	match slot.def.kind:
		SlotDef.Kind.FURNITURE:
			var def: ItemDef = slot.def.item
			var lane: float = ViewSpace.LANE_SEAT if slot.def.seat else ViewSpace.LANE_TABLE
			var base: Vector3 = ViewSpace.tile_floor(slot.tile.x, slot.tile.y, lane)
			GreyboxShapes.add_item(batch, def.shape, base, Color(def.color, alpha))
		SlotDef.Kind.STATION:
			var base: Vector3 = ViewSpace.tile_floor(slot.tile.x, slot.tile.y, ViewSpace.LANE_SEAT)
			GreyboxShapes.add_bench(batch, base, slot.def.width, Color(BENCH_COLOR, alpha))
		SlotDef.Kind.OUTPUT:
			var base: Vector3 = ViewSpace.tile_floor(slot.tile.x, slot.tile.y, ViewSpace.LANE_PALLET)
			GreyboxShapes.add_pallet(_ghost_batch, base, Color(ItemLayer.PALLET_COLOR, GHOST_ALPHA))
