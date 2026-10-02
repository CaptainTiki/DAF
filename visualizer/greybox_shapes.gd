class_name GreyboxShapes
extends RefCounted
## Placeholder shapes built from boxes, until real models exist.
## Every shape is placed by its base: the middle of the bottom edge of the
## tile it stands on. `scale` shrinks a shape for stacking in a pile.


## Adds a non-ball item. Balls are drawn as spheres by the item layer.
static func add_item(batch: BoxBatch, shape: ItemDef.Shape, base: Vector3, color: Color, scale: float = 1.0) -> void:
	match shape:
		ItemDef.Shape.LOG:
			_box(batch, base, Vector3(0.0, 0.13, 0.0), Vector3(0.7, 0.24, 0.24), color, scale)
			_box(batch, base, Vector3(0.36, 0.13, 0.0), Vector3(0.03, 0.2, 0.2), color.lightened(0.35), scale)
		ItemDef.Shape.CHAIR:
			_box(batch, base, Vector3(0.0, 0.42, 0.0), Vector3(0.56, 0.1, 0.4), color, scale)
			_box(batch, base, Vector3(0.0, 0.85, -0.17), Vector3(0.56, 0.8, 0.07), color.darkened(0.15), scale)
			_box(batch, base, Vector3(-0.23, 0.2, 0.0), Vector3(0.08, 0.4, 0.36), color.darkened(0.3), scale)
			_box(batch, base, Vector3(0.23, 0.2, 0.0), Vector3(0.08, 0.4, 0.36), color.darkened(0.3), scale)
		ItemDef.Shape.TABLE:
			_box(batch, base, Vector3(0.0, 0.7, 0.0), Vector3(1.0, 0.12, 0.3), color, scale)
			_box(batch, base, Vector3(-0.4, 0.32, 0.0), Vector3(0.1, 0.64, 0.26), color.darkened(0.3), scale)
			_box(batch, base, Vector3(0.4, 0.32, 0.0), Vector3(0.1, 0.64, 0.26), color.darkened(0.3), scale)
		_:
			_box(batch, base, Vector3(0.0, 0.2, 0.0), Vector3(0.4, 0.4, 0.4), color, scale)


## A work bench, `width` tiles wide. `left_base` is the base of its leftmost tile.
static func add_bench(batch: BoxBatch, left_base: Vector3, width: int, color: Color) -> void:
	var middle: Vector3 = left_base + Vector3((width - 1) * 0.5, 0.0, 0.0)
	var span: float = width - 0.3
	_box(batch, middle, Vector3(0.0, 0.8, 0.0), Vector3(span, 0.16, 0.5), color, 1.0)
	_box(batch, middle, Vector3(-span * 0.5 + 0.12, 0.36, 0.0), Vector3(0.16, 0.72, 0.44), color.darkened(0.3), 1.0)
	_box(batch, middle, Vector3(span * 0.5 - 0.12, 0.36, 0.0), Vector3(0.16, 0.72, 0.44), color.darkened(0.3), 1.0)
	_box(batch, middle, Vector3(0.0, 0.3, -0.1), Vector3(span - 0.3, 0.08, 0.3), color.darkened(0.2), 1.0)
	# A vice on the end, so it reads as a work bench and not a long table.
	_box(batch, middle, Vector3(span * 0.5 - 0.35, 1.0, 0.1), Vector3(0.3, 0.24, 0.2), Color(0.5, 0.52, 0.56, color.a), 1.0)


## A pallet for a pile to sit on.
static func add_pallet(batch: BoxBatch, base: Vector3, color: Color) -> void:
	_box(batch, base, Vector3(0.0, 0.05, 0.0), Vector3(0.92, 0.1, 0.6), color, 1.0)


## A plant at a given stage of growth (0..1): a stem with a cap or canopy on top.
static func add_plant(batch: BoxBatch, def: PlantDef, growth: float, base: Vector3, alpha: float = 1.0) -> void:
	var grown: float = lerpf(0.15, 1.0, growth)
	var cap: Vector2 = def.cap_size * grown
	var stem_height: float = maxf(def.height * grown - cap.y * 0.5, 0.1)
	var stem_color := Color(def.stem_color, alpha)
	var cap_color := Color(def.cap_color, alpha)
	_box(batch, base, Vector3(0.0, stem_height * 0.5, 0.0), Vector3(0.22 * maxf(grown, 0.5), stem_height, 0.22), stem_color, 1.0)
	var cap_centre := Vector3(0.0, stem_height + cap.y * 0.25, 0.0)
	_box(batch, base, cap_centre, Vector3(cap.x, cap.y, 0.5), cap_color, 1.0)
	if growth < 1.0:
		return
	# Ready for harvest: tufts break the square outline, so a ripe plant can be
	# told from a nearly grown one at a glance.
	var tuft_color: Color = cap_color.lightened(0.25)
	var tuft := Vector3(cap.x * 0.3, cap.y * 0.4, 0.5)
	var reach: float = cap.x * 0.5 + tuft.x * 0.3
	_box(batch, base, cap_centre + Vector3(-reach, cap.y * 0.15, 0.05), tuft, tuft_color, 1.0)
	_box(batch, base, cap_centre + Vector3(reach, -cap.y * 0.12, 0.05), tuft, tuft_color, 1.0)
	_box(batch, base, cap_centre + Vector3(cap.x * 0.12, cap.y * 0.5 + tuft.y * 0.3, 0.05), Vector3(cap.x * 0.4, tuft.y, 0.5), tuft_color, 1.0)


static func _box(batch: BoxBatch, base: Vector3, offset: Vector3, size: Vector3, color: Color, scale: float) -> void:
	batch.add_box(base + offset * scale, size * scale, color)
