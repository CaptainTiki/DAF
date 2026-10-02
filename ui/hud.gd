class_name Hud
extends Control
## Tools bar, window buttons, requests log and debug panel.
## Shows sim state and reports what the player asked for through its own signals;
## it never changes the sim or the window itself.

signal tool_selected(tool: ToolController.Tool)
## The player picked a type of room to place.
signal room_tool_selected(def: RoomDef)
signal hire_requested
signal speed_selected(multiplier: float)
signal reveal_toggled(enabled: bool)
signal window_mode_requested(mode: WindowController.Mode)
signal layer_step_requested(direction: int)

@onready var _dig_button: Button = $Bar/DigButton
@onready var _stockpile_button: Button = $Bar/StockpileButton
@onready var _stairs_button: Button = $Bar/StairsButton
@onready var _room_button: Button = $Bar/RoomButton
@onready var _room_panel: PanelContainer = $RoomPanel
@onready var _room_row: HBoxContainer = $RoomPanel/Row
@onready var _requests_button: Button = $Bar/RequestsButton
@onready var _debug_button: Button = $Bar/DebugButton
@onready var _totals: Label = $Bar/Totals
@onready var _layer_up: Button = $Bar/LayerUpButton
@onready var _layer_label: Label = $Bar/LayerLabel
@onready var _layer_down: Button = $Bar/LayerDownButton
@onready var _strip_button: Button = $Bar/StripButton
@onready var _full_button: Button = $Bar/FullButton
@onready var _corner_button: Button = $Bar/CornerButton
@onready var _tray_button: Button = $Bar/TrayButton
@onready var _requests_panel: PanelContainer = $RequestsPanel
@onready var _requests_list: RichTextLabel = $RequestsPanel/Rows/List
@onready var _clear_button: Button = $RequestsPanel/Rows/Header/ClearButton
@onready var _debug_panel: PanelContainer = $DebugPanel
@onready var _hire_button: Button = $DebugPanel/Row/HireButton
@onready var _dwarf_count: Label = $DebugPanel/Row/DwarfCount
@onready var _reveal_check: CheckButton = $DebugPanel/Row/RevealCheck

const SPEEDS: Array[float] = [1.0, 4.0, 16.0]

var _sim: Simulation
var _tool_buttons: Dictionary[ToolController.Tool, Button] = {}
## One button per entry in SPEEDS.
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	_speed_buttons.assign([$DebugPanel/Row/Speed1, $DebugPanel/Row/Speed4, $DebugPanel/Row/Speed16])
	_tool_buttons = {
		ToolController.Tool.DIG: _dig_button,
		ToolController.Tool.STOCKPILE: _stockpile_button,
		ToolController.Tool.STAIRS: _stairs_button,
	}
	for tool: ToolController.Tool in _tool_buttons:
		_tool_buttons[tool].toggled.connect(_on_tool_toggled.bind(tool))
	_room_button.toggled.connect(_on_room_toggled)
	_requests_button.toggled.connect(_on_panel_toggled.bind(_requests_panel, _debug_button))
	_debug_button.toggled.connect(_on_panel_toggled.bind(_debug_panel, _requests_button))
	_layer_up.pressed.connect(func() -> void: layer_step_requested.emit(-1))
	_layer_down.pressed.connect(func() -> void: layer_step_requested.emit(1))
	_strip_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.STRIP))
	_full_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.FULLSCREEN))
	_corner_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.CORNER))
	_tray_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.TRAY))
	_hire_button.pressed.connect(func() -> void: hire_requested.emit())
	_reveal_check.toggled.connect(func(enabled: bool) -> void: reveal_toggled.emit(enabled))
	for i in _speed_buttons.size():
		_speed_buttons[i].pressed.connect(_on_speed_pressed.bind(i))
	_on_speed_pressed(0)


func bind(sim: Simulation) -> void:
	_sim = sim
	sim.storage.changed.connect(_refresh_totals)
	sim.requests.changed.connect(_refresh_requests)
	sim.dwarf_hired.connect(func(_dwarf: Dwarf) -> void: _refresh_dwarf_count())
	_clear_button.pressed.connect(sim.requests.clear)
	for def: RoomDef in sim.config.rooms:
		var button := Button.new()
		button.text = def.display_name
		button.tooltip_text = "At least %d wide and %d high. Drag over dug floor. Right-drag removes a room." % [def.min_width, def.min_height]
		button.pressed.connect(_on_room_type_pressed.bind(def))
		_room_row.add_child(button)
	_refresh_totals()
	_refresh_requests()
	_refresh_dwarf_count()


func set_layer(layer: int) -> void:
	_layer_label.text = "Surface" if layer < 0 else "Layer %d" % (layer + 1)


func set_window_mode(mode: WindowController.Mode) -> void:
	var layered: bool = mode != WindowController.Mode.FULLSCREEN
	_layer_up.visible = layered
	_layer_label.visible = layered
	_layer_down.visible = layered
	_strip_button.disabled = mode == WindowController.Mode.STRIP
	_full_button.disabled = mode == WindowController.Mode.FULLSCREEN
	_corner_button.disabled = mode == WindowController.Mode.CORNER
	# The corner window is too narrow for the readout.
	_totals.visible = mode != WindowController.Mode.CORNER


func set_reveal(enabled: bool) -> void:
	_reveal_check.set_pressed_no_signal(enabled)


func _on_tool_toggled(pressed: bool, tool: ToolController.Tool) -> void:
	if pressed:
		for other: ToolController.Tool in _tool_buttons:
			if other != tool:
				_tool_buttons[other].set_pressed_no_signal(false)
		_room_button.set_pressed_no_signal(false)
		_close_room_picker()
		tool_selected.emit(tool)
	else:
		tool_selected.emit(ToolController.Tool.NONE)


func _on_panel_toggled(pressed: bool, panel: PanelContainer, other_button: Button) -> void:
	if pressed:
		other_button.button_pressed = false
		_room_panel.visible = false
	panel.visible = pressed


## The Room button opens the picker; the tool only becomes active once a type is chosen.
func _on_room_toggled(pressed: bool) -> void:
	for tool: ToolController.Tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(false)
	tool_selected.emit(ToolController.Tool.NONE)
	_close_room_picker()
	if pressed:
		_requests_button.button_pressed = false
		_debug_button.button_pressed = false
		_room_panel.visible = true


func _on_room_type_pressed(def: RoomDef) -> void:
	_room_panel.visible = false
	_room_button.text = "Room: %s" % def.display_name
	room_tool_selected.emit(def)


func _close_room_picker() -> void:
	_room_panel.visible = false
	_room_button.text = "Room"


func _on_speed_pressed(index: int) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].disabled = i == index
	speed_selected.emit(SPEEDS[index])


func _refresh_totals() -> void:
	var parts := PackedStringArray()
	for type in _sim.storage.totals.size():
		var count: int = _sim.storage.totals[type]
		if count > 0:
			parts.append("%s %d" % [_sim.item_def(type).display_name, count])
	_totals.text = "Stored: nothing yet" if parts.is_empty() else "Stored: " + "  ".join(parts)


func _refresh_requests() -> void:
	var entries: Array[RequestEntry] = _sim.requests.entries
	_requests_button.text = "Requests" if entries.is_empty() else "Requests (%d)" % entries.size()
	if entries.is_empty():
		_requests_list.text = "[color=#999999]No requests. The dwarves are content.[/color]"
		return
	var lines := PackedStringArray()
	# Most recently raised first.
	for i in range(entries.size() - 1, -1, -1):
		var entry: RequestEntry = entries[i]
		var line: String = "[color=#999999]%s[/color]  [b]%s:[/b] %s" % [_clock_text(entry.last_tick), entry.dwarf_name, entry.message]
		if entry.count > 1:
			line += "  [color=#e0b040]x%d[/color]" % entry.count
		lines.append(line)
	_requests_list.text = "\n".join(lines)


func _refresh_dwarf_count() -> void:
	_dwarf_count.text = "Dwarves: %d" % _sim.dwarves.size()


## Sim time as minutes:seconds.
func _clock_text(tick: int) -> String:
	@warning_ignore("integer_division")
	var seconds: int = tick / _sim.config.ticks_per_second
	@warning_ignore("integer_division")
	return "%d:%02d" % [seconds / 60, seconds % 60]
