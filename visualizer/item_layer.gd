class_name ItemLayer
extends Node3D
## Draws loose resource balls and pallets with their stacks, as MultiMeshes.
## Instances are reused frame to frame; nothing is created or freed per ball.

const BALL_RADIUS: float = 0.2
const PALLET_COLOR := Color(0.5, 0.36, 0.2)
const PALLET_BASE_HEIGHT: float = 0.1
## Balls on a pallet are drawn smaller and stacked as a 4-3-2-1 pyramid.
const STACK_SCALE: float = 0.55
const STACK_ROWS: Array[int] = [4, 3, 2, 1]
const STACK_SIZE: int = 10

@onready var _loose: MultiMeshInstance3D = $LooseBalls
@onready var _pallet_balls: MultiMeshInstance3D = $PalletBalls
@onready var _pallet_bases: MultiMeshInstance3D = $PalletBases

var _sim: Simulation
var _last_items_version: int = -1
var _pallets_dirty: bool = true


func bind(sim: Simulation) -> void:
	_sim = sim
	_sim.storage.changed.connect(_on_storage_changed)


func refresh(alpha: float) -> void:
	if _pallets_dirty:
		_pallets_dirty = false
		_rebuild_pallets()
	if _sim.items_version != _last_items_version or _sim.unsettled_item_count() > 0:
		_last_items_version = _sim.items_version
		_rebuild_loose(alpha)


func _on_storage_changed() -> void:
	_pallets_dirty = true


func _rebuild_loose(alpha: float) -> void:
	var mesh: MultiMesh = _loose.multimesh
	_ensure_capacity(mesh, _sim.items.size())
	var count: int = 0
	for item: Item in _sim.items.values():
		if item.state != Item.State.LOOSE:
			continue
		var tile: Vector2 = Vector2(item.from_pos).lerp(Vector2(item.pos), item.move_fraction(alpha))
		var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, ViewSpace.LANE_ITEM)
		# Spread balls that share a tile into a loose pile.
		origin.x += ((item.id * 37) % 7 - 3) * 0.09
		origin.y += BALL_RADIUS + ((item.id * 13) % 3) * 0.07
		origin.z += (item.id % 5) * 0.03
		mesh.set_instance_transform(count, Transform3D(Basis.IDENTITY, origin))
		mesh.set_instance_color(count, _sim.material_def(item.material).color)
		count += 1
	mesh.visible_instance_count = count


func _rebuild_pallets() -> void:
	var pallets: Array[Pallet] = []
	var ball_total: int = 0
	for pallet: Pallet in _sim.storage.pallets.values():
		if pallet.placed:
			pallets.append(pallet)
			ball_total += pallet.count
	var bases: MultiMesh = _pallet_bases.multimesh
	var balls: MultiMesh = _pallet_balls.multimesh
	_ensure_capacity(bases, pallets.size())
	_ensure_capacity(balls, ball_total)
	var stack_basis: Basis = Basis.from_scale(Vector3.ONE * STACK_SCALE)
	var ball_index: int = 0
	for i in pallets.size():
		var pallet: Pallet = pallets[i]
		var floor_point: Vector3 = ViewSpace.tile_floor(pallet.tile.x, pallet.tile.y, ViewSpace.LANE_PALLET)
		bases.set_instance_transform(i, Transform3D(Basis.IDENTITY, floor_point + Vector3(0.0, PALLET_BASE_HEIGHT * 0.5, 0.0)))
		bases.set_instance_color(i, PALLET_COLOR)
		var color: Color = _sim.material_def(pallet.material).color
		for n in pallet.count:
			balls.set_instance_transform(ball_index, Transform3D(stack_basis, floor_point + _stack_offset(n)))
			balls.set_instance_color(ball_index, color)
			ball_index += 1
	bases.visible_instance_count = pallets.size()
	balls.visible_instance_count = ball_total


## Position of the nth ball in a pallet's stack, relative to the tile floor.
func _stack_offset(n: int) -> Vector3:
	var radius: float = BALL_RADIUS * STACK_SCALE
	var slot: int = n % STACK_SIZE
	@warning_ignore("integer_division")
	var depth: int = n / STACK_SIZE
	var row: int = 0
	while slot >= STACK_ROWS[row]:
		slot -= STACK_ROWS[row]
		row += 1
	var x: float = (slot - (STACK_ROWS[row] - 1) * 0.5) * radius * 2.0
	var y: float = PALLET_BASE_HEIGHT + radius + row * radius * 1.75
	return Vector3(x, y, depth * radius * 2.0)


func _ensure_capacity(mesh: MultiMesh, needed: int) -> void:
	if mesh.instance_count >= needed:
		return
	var capacity: int = maxi(mesh.instance_count, 64)
	while capacity < needed:
		capacity *= 2
	mesh.instance_count = capacity
