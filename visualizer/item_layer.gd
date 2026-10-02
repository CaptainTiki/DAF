class_name ItemLayer
extends Node3D
## Draws loose items and piles with their contents, as MultiMeshes.
## Instances are reused frame to frame; nothing is created or freed per item.

const BALL_RADIUS: float = 0.2
const PALLET_COLOR := Color(0.5, 0.36, 0.2)
const PALLET_HEIGHT: float = 0.1
## Things on a pile are drawn smaller. Balls stack as a 4-3-2-1 pyramid.
const STACK_SCALE: float = 0.55
const STACK_ROWS: Array[int] = [4, 3, 2, 1]
const STACK_SIZE: int = 10
## Other shapes on a pile sit three to a row.
const SHAPE_STACK_SCALE: float = 0.42
const SHAPES_PER_ROW: int = 3
const HEAP_COLOR := Color(0.42, 0.3, 0.19)
const HEAP_WIDTH: float = 3.0
const HEAP_MIN_HEIGHT: float = 0.2
const HEAP_MAX_HEIGHT: float = 2.2
## Height the heap gains per item tipped on it.
const HEAP_GROWTH: float = 0.006

@onready var _loose_balls: MultiMeshInstance3D = $LooseBalls
@onready var _pile_balls: MultiMeshInstance3D = $PileBalls
@onready var _loose_shapes: MultiMeshInstance3D = $LooseShapes
@onready var _pile_shapes: MultiMeshInstance3D = $PileShapes

var _sim: Simulation
var _loose_batch: BoxBatch
var _pile_batch: BoxBatch
var _last_items_version: int = -1
var _piles_dirty: bool = true
var _last_dumped: int = -1


func bind(sim: Simulation) -> void:
	_sim = sim
	_loose_batch = BoxBatch.new(_loose_shapes.multimesh)
	_pile_batch = BoxBatch.new(_pile_shapes.multimesh)
	_sim.storage.changed.connect(_on_storage_changed)


func refresh(alpha: float) -> void:
	if _piles_dirty or _sim.dumped != _last_dumped:
		_piles_dirty = false
		_last_dumped = _sim.dumped
		_rebuild_piles()
	if _sim.items_version != _last_items_version or _sim.unsettled_item_count() > 0:
		_last_items_version = _sim.items_version
		_rebuild_loose(alpha)


func _on_storage_changed() -> void:
	_piles_dirty = true


func _rebuild_loose(alpha: float) -> void:
	var balls: MultiMesh = _loose_balls.multimesh
	_ensure_capacity(balls, _sim.items.size())
	_loose_batch.begin()
	var ball_count: int = 0
	for item: Item in _sim.items.values():
		if item.state != Item.State.LOOSE:
			continue
		var def: ItemDef = _sim.item_def(item.type)
		var tile: Vector2 = Vector2(item.from_pos).lerp(Vector2(item.pos), item.move_fraction(alpha))
		var base: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, ViewSpace.LANE_ITEM)
		# Spread items that share a tile into a loose heap.
		base.x += ((item.id * 37) % 7 - 3) * 0.09
		base.z += (item.id % 5) * 0.03
		if def.shape == ItemDef.Shape.BALL:
			base.y += BALL_RADIUS + ((item.id * 13) % 3) * 0.07
			balls.set_instance_transform(ball_count, Transform3D(Basis.IDENTITY, base))
			balls.set_instance_color(ball_count, def.color)
			ball_count += 1
		else:
			GreyboxShapes.add_item(_loose_batch, def.shape, base, def.color, 0.8)
	balls.visible_instance_count = ball_count
	_loose_batch.commit()


func _rebuild_piles() -> void:
	var ball_total: int = 0
	for pile: Pile in _sim.storage.piles:
		for type: int in pile.counts:
			if _sim.item_def(type).shape == ItemDef.Shape.BALL:
				ball_total += pile.counts[type]
	var balls: MultiMesh = _pile_balls.multimesh
	_ensure_capacity(balls, ball_total)
	_pile_batch.begin()
	var stack_basis: Basis = Basis.from_scale(Vector3.ONE * STACK_SCALE)
	var ball_index: int = 0
	for pile: Pile in _sim.storage.piles:
		if pile.units_used == 0:
			continue
		var base: Vector3 = ViewSpace.tile_floor(pile.tile.x, pile.tile.y, ViewSpace.LANE_PALLET)
		GreyboxShapes.add_pallet(_pile_batch, base, PALLET_COLOR)
		var ball_slot: int = 0
		var shape_slot: int = 0
		for type: int in pile.counts:
			var def: ItemDef = _sim.item_def(type)
			for n in pile.counts[type]:
				if def.shape == ItemDef.Shape.BALL:
					balls.set_instance_transform(ball_index, Transform3D(stack_basis, base + _ball_offset(ball_slot)))
					balls.set_instance_color(ball_index, def.color)
					ball_index += 1
					ball_slot += 1
				else:
					GreyboxShapes.add_item(_pile_batch, def.shape, base + _shape_offset(shape_slot), def.color, SHAPE_STACK_SCALE)
					shape_slot += 1
	_add_spoil_heap()
	balls.visible_instance_count = ball_index
	_pile_batch.commit()


## The spoil heap grows with what has been tipped on it, up to a limit.
func _add_spoil_heap() -> void:
	var heap: Pile = _sim.dump_pile
	if heap == null or _sim.dumped == 0:
		return
	var base: Vector3 = ViewSpace.tile_floor(heap.tile.x, heap.tile.y, ViewSpace.LANE_STRUCTURE)
	var height: float = minf(HEAP_MIN_HEIGHT + _sim.dumped * HEAP_GROWTH, HEAP_MAX_HEIGHT)
	var step: float = height / 3.0
	for tier in 3:
		var width: float = HEAP_WIDTH * (1.0 - tier * 0.3)
		_pile_batch.add_box(base + Vector3(0.0, step * (tier + 0.5), 0.0), Vector3(width, step, 0.5), HEAP_COLOR.darkened(tier * 0.08))


## Position of the nth ball on a pile, relative to the tile floor.
func _ball_offset(n: int) -> Vector3:
	var radius: float = BALL_RADIUS * STACK_SCALE
	var slot: int = n % STACK_SIZE
	@warning_ignore("integer_division")
	var depth: int = n / STACK_SIZE
	var row: int = 0
	while slot >= STACK_ROWS[row]:
		slot -= STACK_ROWS[row]
		row += 1
	var x: float = (slot - (STACK_ROWS[row] - 1) * 0.5) * radius * 2.0
	var y: float = PALLET_HEIGHT + radius + row * radius * 1.75
	return Vector3(x, y, depth * radius * 2.0)


## Position of the nth non-ball item on a pile, relative to the tile floor.
func _shape_offset(n: int) -> Vector3:
	@warning_ignore("integer_division")
	var row: int = n / SHAPES_PER_ROW
	var column: int = n % SHAPES_PER_ROW
	return Vector3((column - 1) * 0.3, PALLET_HEIGHT + row * 0.3, 0.0)


func _ensure_capacity(mesh: MultiMesh, needed: int) -> void:
	if mesh.instance_count >= needed:
		return
	var capacity: int = maxi(mesh.instance_count, 64)
	while capacity < needed:
		capacity *= 2
	mesh.instance_count = capacity
