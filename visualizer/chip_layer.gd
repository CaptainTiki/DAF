class_name ChipLayer
extends MultiMeshInstance3D
## Flecks that fly off a tile while it is being dug. Pure decoration: nothing
## in the sim knows about them, and they use their own random numbers.

const MAX_CHIPS: int = 256
const CHIP_SIZE: float = 0.12
const GRAVITY: float = 9.0
const LIFE: float = 0.7
## Chips per second from one dwarf digging.
const RATE: float = 10.0

var _positions: PackedVector3Array
var _velocities: PackedVector3Array
var _ages: PackedFloat32Array
var _colors: PackedColorArray
var _rng := RandomNumberGenerator.new()
var _spawn_debt: float = 0.0


func _ready() -> void:
	multimesh.instance_count = MAX_CHIPS
	multimesh.visible_instance_count = 0


## Call once per frame. `sources` are (world position, colour) pairs of tiles
## being dug this frame.
func refresh(delta: float, sources: Array[Array]) -> void:
	_spawn_debt += delta * RATE * sources.size()
	while _spawn_debt >= 1.0 and not sources.is_empty() and _positions.size() < MAX_CHIPS:
		_spawn_debt -= 1.0
		var source: Array = sources[_rng.randi_range(0, sources.size() - 1)]
		_positions.append((source[0] as Vector3) + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4), 0.3))
		_velocities.append(Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(1.5, 4.0), 0.0))
		_ages.append(0.0)
		_colors.append(source[1])
	if sources.is_empty():
		_spawn_debt = 0.0
	var i: int = 0
	while i < _positions.size():
		_ages[i] += delta
		if _ages[i] >= LIFE:
			_positions.remove_at(i)
			_velocities.remove_at(i)
			_ages.remove_at(i)
			_colors.remove_at(i)
			continue
		_velocities[i] += Vector3(0.0, -GRAVITY * delta, 0.0)
		_positions[i] += _velocities[i] * delta
		i += 1
	var basis: Basis = Basis.from_scale(Vector3.ONE * CHIP_SIZE)
	for n in _positions.size():
		multimesh.set_instance_transform(n, Transform3D(basis, _positions[n]))
		multimesh.set_instance_color(n, _colors[n])
	multimesh.visible_instance_count = _positions.size()