class_name ViewCamera
extends Camera3D
## Orthographic side camera. Two ways of framing the world:
## - layer view: shows a fixed number of whole layers and pans sideways only;
## - free view: pan anywhere and zoom.

signal layer_changed(layer: int)

@export var min_view_height: float = 6.0
@export var max_view_height: float = 140.0
@export var wheel_pan_tiles: float = 4.0
@export var zoom_step: float = 1.15
## Empty space shown above the top of the world in free view.
@export var sky_margin: float = 3.0

## When true, dragging with the left button pans. Tools turn this off while active.
var left_drag_pans: bool = true
## Topmost layer on screen in layer view. -1 is the surface.
var layer: int = 0

var _grid: TileGrid
var _free: bool = false
## Zoom level of the free view, in tiles of height. Kept while in layer view.
var _free_view_height: float = 32.0
var _layers_shown: int = 2
var _focus: Vector2
var _dragging: bool = false


func bind(grid: TileGrid) -> void:
	_grid = grid
	_focus = Vector2(grid.width * 0.5, 0.0)
	get_viewport().size_changed.connect(_apply)
	show_layers(_layers_shown)


## Layer view: frame this many whole layers, starting at the current layer.
func show_layers(count: int) -> void:
	_free = false
	_layers_shown = count
	size = count * _grid.layer_height
	_set_layer(layer)


## Free view: pan and zoom at will.
func set_free() -> void:
	_free = true
	size = _free_view_height
	_apply()


func step_layer(direction: int) -> void:
	if not _free:
		_set_layer(layer + direction)


func is_free() -> bool:
	return _free


func screen_to_tile(screen_position: Vector2) -> Vector2i:
	return ViewSpace.world_to_tile(project_ray_origin(screen_position))


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_wheel(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_wheel(1.0)
			MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
			MOUSE_BUTTON_LEFT:
				if left_drag_pans:
					_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var world_per_pixel: float = size / get_viewport().get_visible_rect().size.y
		_focus.x -= motion.relative.x * world_per_pixel
		if _free:
			_focus.y += motion.relative.y * world_per_pixel
		_apply()


func _wheel(direction: float) -> void:
	if _free:
		size = clampf(size * (zoom_step if direction > 0.0 else 1.0 / zoom_step), min_view_height, max_view_height)
		_free_view_height = size
	else:
		_focus.x += direction * wheel_pan_tiles
	_apply()


func _set_layer(value: int) -> void:
	var clamped: int = clampi(value, -1, _grid.layer_count() - _layers_shown)
	var changed: bool = clamped != layer
	layer = clamped
	_focus.y = -(_grid.layer_top_row(layer) + size * 0.5)
	_apply()
	if changed:
		layer_changed.emit(layer)


## Clamps the focus to the world and moves the camera there.
func _apply() -> void:
	if _grid == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var half_width: float = size * view.x / maxf(view.y, 1.0) * 0.5
	if half_width * 2.0 >= _grid.width:
		_focus.x = _grid.width * 0.5
	else:
		_focus.x = clampf(_focus.x, half_width, _grid.width - half_width)
	if _free:
		var half_height: float = size * 0.5
		var top: float = sky_margin
		var bottom: float = -float(_grid.height)
		if half_height * 2.0 >= top - bottom:
			_focus.y = (top + bottom) * 0.5
		else:
			_focus.y = clampf(_focus.y, bottom + half_height, top - half_height)
	position = Vector3(_focus.x, _focus.y, position.z)
