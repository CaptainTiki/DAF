class_name DwarfView
extends Node3D
## Greybox dwarf. Reads one Dwarf from the sim each frame and poses itself.

const TUNIC_COLORS: Array[Color] = [
	Color(0.72, 0.22, 0.2), Color(0.2, 0.45, 0.72), Color(0.25, 0.6, 0.32),
	Color(0.75, 0.55, 0.15), Color(0.55, 0.3, 0.65), Color(0.2, 0.62, 0.62),
]
const BEARD_COLORS: Array[Color] = [
	Color(0.8, 0.42, 0.12), Color(0.35, 0.22, 0.12), Color(0.85, 0.82, 0.75), Color(0.15, 0.13, 0.12),
]
const PICK_REST_ANGLE: float = -0.5
const SWING_TICKS: float = 10.0
const BOB_HEIGHT: float = 0.07
const SHARED_TILE_SPREAD: float = 0.16
const STAIR_LANE: float = ViewSpace.LANE_STRUCTURE + 0.5

@onready var _rig: Node3D = $Rig
@onready var _body: MeshInstance3D = $Rig/Body
@onready var _beard: MeshInstance3D = $Rig/Beard
@onready var _pick: Node3D = $Rig/PickPivot
@onready var _carried: MeshInstance3D = $Rig/Carried
@onready var _progress: MeshInstance3D = $Progress

var _dwarf: Dwarf
var _carried_material := StandardMaterial3D.new()
var _carried_item_material: int = -1
var _at_rest: bool = false


func bind(dwarf: Dwarf) -> void:
	_dwarf = dwarf
	_body.material_override = _flat_material(TUNIC_COLORS[dwarf.id % TUNIC_COLORS.size()])
	_beard.material_override = _flat_material(BEARD_COLORS[(dwarf.id * 7 + 3) % BEARD_COLORS.size()])
	_carried_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_carried.material_override = _carried_material
	_at_rest = false


func refresh(sim: Simulation, alpha: float) -> void:
	var moving: bool = _dwarf.move_ticks_left > 0
	var digging: bool = _dwarf.activity == Dwarf.Activity.DIG or _dwarf.activity == Dwarf.Activity.BUILD
	# A dwarf standing idle doesn't change, so leave the scene untouched and let
	# the renderer skip the frame.
	if not moving and not digging and _dwarf.carrying == null:
		if _at_rest:
			return
		_at_rest = true
	else:
		_at_rest = false

	var fraction: float = _dwarf.move_fraction(alpha)
	var tile: Vector2 = Vector2(_dwarf.from_pos).lerp(Vector2(_dwarf.pos), fraction)
	# On stairs a dwarf is in the back lane, behind any rock or floor in front.
	var grid: TileGrid = sim.grid
	var on_stairs: bool = grid.has_stair(_dwarf.pos.x, _dwarf.pos.y) or grid.has_stair(_dwarf.from_pos.x, _dwarf.from_pos.y)
	var lane: float = STAIR_LANE if on_stairs else ViewSpace.LANE_DWARF
	var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, lane + (_dwarf.id % 8) * 0.01)
	# Dwarves working from the same tile stand side by side, not inside each other.
	origin.x += (_dwarf.id % 3 - 1) * SHARED_TILE_SPREAD
	if moving and _dwarf.activity == Dwarf.Activity.WALK:
		origin.y += absf(sin(fraction * PI)) * BOB_HEIGHT
	position = origin
	_rig.basis = Basis.from_scale(Vector3(_dwarf.facing, 1.0, 1.0))

	if digging:
		var swing: float = fmod(_dwarf.work_progress + alpha, SWING_TICKS) / SWING_TICKS
		_pick.rotation.z = lerpf(0.7, -1.3, swing * swing)
		_progress.visible = true
		_progress.global_position = ViewSpace.tile_center(_dwarf.work_tile.x, _dwarf.work_tile.y, ViewSpace.LANE_OVERLAY + 0.1) + Vector3(0.0, 0.3, 0.0)
		_progress.scale = Vector3(maxf(_dwarf.work_fraction(), 0.02), 1.0, 1.0)
	else:
		_pick.rotation.z = PICK_REST_ANGLE
		_progress.visible = false

	var item: Item = _dwarf.carrying
	_pick.visible = item == null
	_carried.visible = item != null
	if item != null and item.material != _carried_item_material:
		_carried_item_material = item.material
		_carried_material.albedo_color = sim.material_def(item.material).color


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
