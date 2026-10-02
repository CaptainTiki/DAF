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
## Dwarves stand anywhere within this fraction of a tile, so a group sharing a
## tile reads as a group.
const STAND_SPREAD: float = 0.6
const GOLDEN_RATIO: float = 0.618034
const STAIR_LANE: float = ViewSpace.LANE_STRUCTURE + 0.5
## How far a sitting dwarf is lifted onto the chair.
const SEAT_HEIGHT: float = 0.22
## Turns the rig, which faces +X, towards the camera.
const FACING_CAMERA := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))

@onready var _rig: Node3D = $Rig
@onready var _body: MeshInstance3D = $Rig/Body
@onready var _beard: MeshInstance3D = $Rig/Beard
@onready var _pick: Node3D = $Rig/PickPivot
@onready var _carried_ball: MeshInstance3D = $Rig/CarriedBall
@onready var _carried_box: MeshInstance3D = $Rig/CarriedBox
@onready var _progress: MeshInstance3D = $Progress
@onready var _speech: Label3D = $Speech

var _dwarf: Dwarf
var _carried_material := StandardMaterial3D.new()
var _carried_type: int = -1
var _shown_speech: String = ""
## The activity the dwarf was last posed for while standing still, or -1.
var _resting_as: int = -1
## Sideways standing position within the tile, in tiles.
var _stand_offset: float = 0.0
## Where in the swing this dwarf starts, 0..1.
var _swing_phase: float = 0.0


func bind(dwarf: Dwarf) -> void:
	_dwarf = dwarf
	# Golden-ratio steps keep consecutive dwarves well apart from each other.
	_stand_offset = (fposmod(dwarf.id * GOLDEN_RATIO, 1.0) - 0.5) * STAND_SPREAD
	_swing_phase = fposmod(dwarf.id * GOLDEN_RATIO * 3.0, 1.0)
	_body.material_override = _flat_material(TUNIC_COLORS[dwarf.id % TUNIC_COLORS.size()])
	_beard.material_override = _flat_material(BEARD_COLORS[(dwarf.id * 7 + 3) % BEARD_COLORS.size()])
	_carried_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_carried_ball.material_override = _carried_material
	_carried_box.material_override = _carried_material
	_resting_as = -1


func refresh(sim: Simulation, alpha: float) -> void:
	if _dwarf.speech != _shown_speech:
		_shown_speech = _dwarf.speech
		_speech.text = _shown_speech
		_speech.visible = not _shown_speech.is_empty()
	var moving: bool = _dwarf.move_ticks_left > 0
	var working: bool = _dwarf.activity == Dwarf.Activity.WORK
	var sitting: bool = _dwarf.activity == Dwarf.Activity.SIT
	# A dwarf standing or sitting still doesn't change, so leave the scene
	# untouched and let the renderer skip the frame.
	if not moving and not working and _dwarf.carrying == null:
		if _resting_as == _dwarf.activity:
			return
		_resting_as = _dwarf.activity
	else:
		_resting_as = -1

	var fraction: float = _dwarf.move_fraction(alpha)
	var tile: Vector2 = Vector2(_dwarf.from_pos).lerp(Vector2(_dwarf.pos), fraction)
	# On stairs a dwarf is in the back lane, behind any rock or floor in front.
	var grid: TileGrid = sim.grid
	var on_stairs: bool = grid.has_stair(_dwarf.pos.x, _dwarf.pos.y) or grid.has_stair(_dwarf.from_pos.x, _dwarf.from_pos.y)
	var lane: float = STAIR_LANE if on_stairs else ViewSpace.LANE_DWARF
	if sitting:
		lane = ViewSpace.LANE_SEATED
	var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, lane + (_dwarf.id % 8) * 0.01)
	if sitting:
		origin.y += SEAT_HEIGHT
		_rig.basis = FACING_CAMERA
	else:
		# Dwarves working from the same tile stand side by side, not inside each other.
		origin.x += _stand_offset
		_rig.basis = Basis.from_scale(Vector3(_dwarf.facing, 1.0, 1.0))
	if moving and _dwarf.activity == Dwarf.Activity.WALK:
		origin.y += absf(sin(fraction * PI)) * BOB_HEIGHT
	position = origin

	if working:
		var swing_ticks: float = SWING_TICKS * _dwarf.pace
		var swing: float = fmod(_dwarf.work_progress + alpha + _swing_phase * swing_ticks, swing_ticks) / swing_ticks
		_pick.rotation.z = lerpf(0.7, -1.3, swing * swing)
		_progress.visible = true
		_progress.global_position = ViewSpace.tile_center(_dwarf.work_tile.x, _dwarf.work_tile.y, ViewSpace.LANE_OVERLAY + 0.1) + Vector3(0.0, 0.3, 0.0)
		_progress.scale = Vector3(maxf(_dwarf.work_fraction(), 0.02), 1.0, 1.0)
	else:
		_pick.rotation.z = PICK_REST_ANGLE
		_progress.visible = false

	var item: Item = _dwarf.carrying
	_pick.visible = item == null and not sitting
	if item == null:
		_carried_ball.visible = false
		_carried_box.visible = false
		return
	var def: ItemDef = sim.item_def(item.type)
	var is_ball: bool = def.shape == ItemDef.Shape.BALL
	_carried_ball.visible = is_ball
	_carried_box.visible = not is_ball
	if item.type != _carried_type:
		_carried_type = item.type
		_carried_material.albedo_color = def.color
		_carried_box.scale = _carried_size(def.shape)


## Rough size of a carried non-ball item, held in front of the dwarf.
func _carried_size(shape: ItemDef.Shape) -> Vector3:
	match shape:
		ItemDef.Shape.LOG:
			return Vector3(0.7, 0.24, 0.24)
		ItemDef.Shape.TABLE:
			return Vector3(0.9, 0.5, 0.3)
	return Vector3(0.5, 0.7, 0.3)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
