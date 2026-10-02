class_name ToolController
extends Node
## Turns mouse drags on the world into player commands for the active tool.
## Left drag marks; right drag (or Shift + drag) unmarks.

enum Tool { NONE, DIG, STOCKPILE, STAIRS }

const DIG_COLOR := Color(1.0, 0.82, 0.2, 0.3)
const STAIRS_COLOR := Color(0.4, 1.0, 0.5, 0.4)
const STOCKPILE_COLOR := Color(0.3, 0.65, 1.0, 0.3)
const UNMARK_COLOR := Color(1.0, 0.3, 0.25, 0.3)

var tool: Tool = Tool.NONE: set = set_tool

var _sim: Simulation
var _view: WorldView
var _dragging: bool = false
var _unmark: bool = false
var _drag_start: Vector2i
var _drag_end: Vector2i


func bind(sim: Simulation, view: WorldView) -> void:
	_sim = sim
	_view = view
	set_tool(tool)


func set_tool(value: Tool) -> void:
	tool = value
	if _view == null:
		return
	_cancel_drag()
	_view.camera.left_drag_pans = tool == Tool.NONE


func _unhandled_input(event: InputEvent) -> void:
	if tool == Tool.NONE or _view == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
			return
		if button.pressed and not _dragging:
			_dragging = true
			_unmark = button.button_index == MOUSE_BUTTON_RIGHT or button.shift_pressed
			_drag_start = _view.camera.screen_to_tile(button.position)
			_drag_end = _drag_start
			_show_preview()
		elif not button.pressed and _dragging:
			_drag_end = _view.camera.screen_to_tile(button.position)
			_apply()
			_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag_end = _view.camera.screen_to_tile((event as InputEventMouseMotion).position)
		_show_preview()
	elif event.is_action_pressed(&"ui_cancel") and _dragging:
		_cancel_drag()


func _apply() -> void:
	match tool:
		Tool.DIG:
			_sim.mark_dig(_drag_rect(), not _unmark)
		Tool.STOCKPILE:
			_sim.mark_stockpile(_drag_rect(), not _unmark)
		Tool.STAIRS:
			_sim.mark_stairs(_drag_diagonal(), not _unmark)


func _show_preview() -> void:
	var color: Color = UNMARK_COLOR
	if not _unmark:
		match tool:
			Tool.DIG:
				color = DIG_COLOR
			Tool.STOCKPILE:
				color = STOCKPILE_COLOR
			Tool.STAIRS:
				color = STAIRS_COLOR
	if tool == Tool.STAIRS:
		_view.show_tile_selection(_drag_diagonal(), color)
	else:
		_view.show_selection(_drag_rect(), color)


func _cancel_drag() -> void:
	_dragging = false
	_view.hide_selection()


## The drag snapped to a 45 degree line from where it started: one tile over,
## one tile down (or up) per step, which is the slope dwarves can walk.
func _drag_diagonal() -> Array[Vector2i]:
	var delta: Vector2i = _drag_end - _drag_start
	var step := Vector2i(1 if delta.x >= 0 else -1, 1 if delta.y >= 0 else -1)
	var tiles: Array[Vector2i] = []
	for i in maxi(absi(delta.x), absi(delta.y)) + 1:
		tiles.append(_drag_start + step * i)
	return tiles


func _drag_rect() -> Rect2i:
	var top_left := Vector2i(mini(_drag_start.x, _drag_end.x), mini(_drag_start.y, _drag_end.y))
	var bottom_right := Vector2i(maxi(_drag_start.x, _drag_end.x), maxi(_drag_start.y, _drag_end.y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)
