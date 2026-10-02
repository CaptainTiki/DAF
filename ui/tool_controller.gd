class_name ToolController
extends Node
## Turns mouse drags on the world into player commands for the active tool.
## Left drag marks; right drag (or Shift + drag) unmarks or removes.

enum Tool { NONE, DIG, STOCKPILE, STAIRS, FLOOR, REMOVE_STRUCTURE, ROOM, REMOVE_ROOM }

const DIG_COLOR := Color(1.0, 0.82, 0.2, 0.3)
const STAIRS_COLOR := Color(0.4, 1.0, 0.5, 0.4)
const FLOOR_COLOR := Color(1.0, 0.6, 0.25, 0.4)
const STOCKPILE_COLOR := Color(0.3, 0.65, 1.0, 0.3)
const UNMARK_COLOR := Color(1.0, 0.3, 0.25, 0.3)
## Taking a removal mark off again.
const KEEP_COLOR := Color(0.9, 0.9, 0.9, 0.3)
const INVALID_COLOR := Color(1.0, 0.15, 0.1, 0.45)
const ROOM_PREVIEW_ALPHA: float = 0.4

var tool: Tool = Tool.NONE: set = set_tool
## The type of room the ROOM tool places.
var room_def: RoomDef
## What the STAIRS and FLOOR tools build from. Null uses the sim's default.
var build_material: ItemDef

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


func set_build_material(def: ItemDef) -> void:
	build_material = def


## Switches to the ROOM tool for one type of room.
func set_room_tool(def: RoomDef) -> void:
	room_def = def
	set_tool(Tool.ROOM)


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
			if _unmark:
				_sim.mark_removal(_drag_rect(), true)
			else:
				_sim.mark_stairs(_drag_diagonal(), true, build_material)
		Tool.FLOOR:
			if _unmark:
				_sim.mark_removal(_drag_rect(), true)
			else:
				_sim.mark_floors(_drag_rect(), true, build_material)
		Tool.REMOVE_STRUCTURE:
			# Left drag marks for removal; right drag takes the mark off again.
			_sim.mark_removal(_drag_rect(), not _unmark)
		Tool.ROOM:
			if _unmark:
				_sim.remove_rooms(_drag_rect())
			elif room_def != null:
				_sim.place_room(room_def, _drag_rect())
		Tool.REMOVE_ROOM:
			_sim.remove_rooms(_drag_rect())


func _show_preview() -> void:
	match tool:
		Tool.STAIRS:
			if _unmark:
				_view.show_selection(_drag_rect(), UNMARK_COLOR)
			else:
				_view.show_tile_selection(_drag_diagonal(), STAIRS_COLOR)
		Tool.FLOOR:
			_view.show_selection(_drag_rect(), UNMARK_COLOR if _unmark else FLOOR_COLOR)
		Tool.REMOVE_STRUCTURE:
			_view.show_selection(_drag_rect(), KEEP_COLOR if _unmark else UNMARK_COLOR)
		Tool.REMOVE_ROOM:
			_view.show_selection(_drag_rect(), UNMARK_COLOR)
		Tool.ROOM:
			_show_room_preview()
		Tool.DIG:
			_view.show_selection(_drag_rect(), UNMARK_COLOR if _unmark else DIG_COLOR)
		Tool.STOCKPILE:
			_view.show_selection(_drag_rect(), UNMARK_COLOR if _unmark else STOCKPILE_COLOR)


## Shows the space the room would actually take, or the raw drag in red if it
## doesn't fit there.
func _show_room_preview() -> void:
	if _unmark or room_def == null:
		_view.show_selection(_drag_rect(), UNMARK_COLOR)
		return
	var fitted: Rect2i = _sim.room_fit(room_def, _drag_rect())
	if fitted.size == Vector2i.ZERO:
		_view.show_selection(_drag_rect(), INVALID_COLOR)
	else:
		_view.show_selection(fitted, Color(room_def.color, ROOM_PREVIEW_ALPHA))


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
