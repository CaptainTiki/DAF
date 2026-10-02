class_name BoxBatch
extends RefCounted
## Draws many coloured boxes through one MultiMesh of unit cubes. Greybox
## shapes (furniture, logs, plants) are a few boxes each.
## Usage: begin(), add_box() as often as needed, then commit().

var _mesh: MultiMesh
var _transforms: Array[Transform3D] = []
var _colors: PackedColorArray


func _init(mesh: MultiMesh) -> void:
	_mesh = mesh


func begin() -> void:
	_transforms.clear()
	_colors.clear()


func add_box(center: Vector3, size: Vector3, color: Color) -> void:
	_transforms.append(Transform3D(Basis.from_scale(size), center))
	_colors.append(color)


func commit() -> void:
	var count: int = _transforms.size()
	if _mesh.instance_count < count:
		_mesh.instance_count = maxi(64, count * 2)
	for i in count:
		_mesh.set_instance_transform(i, _transforms[i])
		_mesh.set_instance_color(i, _colors[i])
	_mesh.visible_instance_count = count
