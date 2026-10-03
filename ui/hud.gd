class_name Hud
extends Control
## Tools bar, window buttons, requests log and debug panel.
## Shows sim state and reports what the player asked for through its own signals;
## it never changes the sim or the window itself.

signal tool_selected(tool: ToolController.Tool)
## The player picked a type of room to place.
signal room_tool_selected(def: RoomDef)
signal furniture_tool_selected(def: SlotDef)
## The player chose what stairs and floors are built from.
signal build_material_selected(def: ItemDef)
signal hire_requested
signal speed_selected(multiplier: float)
signal reveal_toggled(enabled: bool)
signal room_overlay_toggled(enabled: bool)
## Whether furniture that is planned but not built yet should be drawn.
signal planned_furniture_toggled(enabled: bool)
signal window_mode_requested(mode: WindowController.Mode)
signal layer_step_requested(direction: int)
## The player changed how many of an item type to keep in store.
signal stock_target_changed(type: int, target: int)
signal save_requested
signal load_requested
signal new_game_requested

@onready var _bar: HBoxContainer = $Bar
@onready var _view_column: VBoxContainer = $ViewColumn
@onready var _window_column: VBoxContainer = $WindowColumn
@onready var _dig_button: Button = $Bar/DigButton
@onready var _stockpile_button: Button = $Bar/StockpileButton
@onready var _build_button: Button = $Bar/BuildButton
@onready var _build_panel: PanelContainer = $BuildPanel
@onready var _material_button: Button = $BuildPanel/Row/MaterialButton
@onready var _room_button: Button = $Bar/RoomButton
@onready var _room_panel: PanelContainer = $RoomPanel
@onready var _room_row: HBoxContainer = $RoomPanel/Row
@onready var _furniture_button: Button = $Bar/FurnitureButton
@onready var _furniture_panel: PanelContainer = $FurniturePanel
@onready var _furniture_row: HBoxContainer = $FurniturePanel/Row
@onready var _requests_button: Button = $Bar/RequestsButton
@onready var _orders_button: Button = $Bar/OrdersButton
@onready var _orders_panel: PanelContainer = $OrdersPanel
@onready var _orders_grid: GridContainer = $OrdersPanel/Rows/Grid
@onready var _mood_label: Label = $Bar/Mood
@onready var _debug_button: Button = $Bar/DebugButton
@onready var _totals: Label = $Bar/Totals
@onready var _layer_up: Button = $Bar/LayerUpButton
@onready var _layer_label: Label = $Bar/LayerLabel
@onready var _layer_down: Button = $Bar/LayerDownButton
@onready var _strip_button: Button = $WindowColumn/StripButton
@onready var _full_button: Button = $WindowColumn/FullButton
@onready var _corner_button: Button = $WindowColumn/CornerButton
@onready var _tray_button: Button = $WindowColumn/TrayButton
@onready var _room_overlay_button: Button = $ViewColumn/RoomOverlayButton
@onready var _planned_button: Button = $ViewColumn/PlannedButton
@onready var _requests_panel: PanelContainer = $RequestsPanel
@onready var _requests_list: RichTextLabel = $RequestsPanel/Rows/List
@onready var _clear_button: Button = $RequestsPanel/Rows/Header/ClearButton
@onready var _debug_panel: PanelContainer = $DebugPanel
@onready var _hire_button: Button = $DebugPanel/Row/HireButton
@onready var _dwarf_count: Label = $DebugPanel/Row/DwarfCount
@onready var _reveal_check: CheckButton = $DebugPanel/Row/RevealCheck
@onready var _save_button: Button = $DebugPanel/Row/SaveButton
@onready var _load_button: Button = $DebugPanel/Row/LoadButton
@onready var _new_button: Button = $DebugPanel/Row/NewButton

const SPEEDS: Array[float] = [1.0, 2.0, 3.0, 4.0, 16.0]
const BAR_MARGIN: float = 4.0
const BAR_HEIGHT: float = 26.0
const SMALL_PANEL_HEIGHT: float = 34.0
const REQUESTS_PANEL_HEIGHT: float = 112.0
const COLUMN_MARGIN: float = 2.0
## Height of one icon button when the columns don't fill the window's height.
const ICON_BUTTON_HEIGHT: float = 34.0

var _sim: Simulation
var _tool_buttons: Dictionary[ToolController.Tool, Button] = {}
## Plain panels and the buttons that open them.
var _panels: Dictionary[Button, PanelContainer] = {}
## Buttons that open a picker panel, and the panel each one opens.
var _pickers: Dictionary[Button, PanelContainer] = {}
## What each picker button says when nothing is chosen.
var _picker_titles: Dictionary[Button, String] = {}
## Which of SimConfig.build_materials is selected.
var _material_index: int = 0
## One button per entry in SPEEDS.
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	_speed_buttons.assign([$ViewColumn/Speed1, $ViewColumn/Speed2, $ViewColumn/Speed3, $DebugPanel/Row/Speed4, $DebugPanel/Row/Speed16])
	_tool_buttons = {
		ToolController.Tool.DIG: _dig_button,
		ToolController.Tool.STOCKPILE: _stockpile_button,
	}
	for tool: ToolController.Tool in _tool_buttons:
		_tool_buttons[tool].toggled.connect(_on_tool_toggled.bind(tool))
	_pickers = {_build_button: _build_panel, _room_button: _room_panel, _furniture_button: _furniture_panel}
	_picker_titles = {_build_button: "Build", _room_button: "Room", _furniture_button: "Furniture"}
	for button: Button in _pickers:
		button.toggled.connect(_on_picker_toggled.bind(button))
	$BuildPanel/Row/StairsOption.pressed.connect(_on_option_pressed.bind(_build_button, "Stairs", ToolController.Tool.STAIRS))
	$BuildPanel/Row/FloorOption.pressed.connect(_on_option_pressed.bind(_build_button, "Floor", ToolController.Tool.FLOOR))
	$BuildPanel/Row/RemoveOption.pressed.connect(_on_option_pressed.bind(_build_button, "Remove", ToolController.Tool.REMOVE_STRUCTURE))
	_panels = {_requests_button: _requests_panel, _orders_button: _orders_panel, _debug_button: _debug_panel}
	for button: Button in _panels:
		button.toggled.connect(_on_panel_toggled.bind(button))
	_layer_up.pressed.connect(func() -> void: layer_step_requested.emit(-1))
	_layer_down.pressed.connect(func() -> void: layer_step_requested.emit(1))
	_strip_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.STRIP))
	_full_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.FULLSCREEN))
	_corner_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.CORNER))
	_tray_button.pressed.connect(func() -> void: window_mode_requested.emit(WindowController.Mode.TRAY))
	_hire_button.pressed.connect(func() -> void: hire_requested.emit())
	_reveal_check.toggled.connect(func(enabled: bool) -> void: reveal_toggled.emit(enabled))
	_save_button.pressed.connect(func() -> void: save_requested.emit())
	_load_button.pressed.connect(func() -> void: load_requested.emit())
	_new_button.pressed.connect(func() -> void: new_game_requested.emit())
	_room_overlay_button.toggled.connect(func(enabled: bool) -> void: room_overlay_toggled.emit(enabled))
	_planned_button.toggled.connect(func(enabled: bool) -> void: planned_furniture_toggled.emit(enabled))
	for i in _speed_buttons.size():
		_speed_buttons[i].pressed.connect(_on_speed_pressed.bind(i))
	_on_speed_pressed(0)


func bind(sim: Simulation) -> void:
	_sim = sim
	sim.storage.changed.connect(_refresh_totals)
	sim.requests.changed.connect(_refresh_requests)
	sim.dwarf_hired.connect(func(_dwarf: Dwarf) -> void: _refresh_dwarf_count())
	_clear_button.pressed.connect(sim.requests.clear)
	_material_button.visible = sim.config.build_materials.size() > 1
	_material_button.pressed.connect(_on_material_pressed)
	_show_material()
	for def: RoomDef in sim.config.rooms:
		var button := Button.new()
		button.text = def.display_name
		button.tooltip_text = "At least %d wide and %d high. Drag over dug floor. Touching a room of the same type extends it." % [def.min_width, def.min_height]
		button.pressed.connect(_on_room_type_pressed.bind(def))
		_room_row.add_child(button)
	var remove := Button.new()
	remove.text = "Remove"
	remove.tooltip_text = "Drag over rooms to take them away. Furniture and goods are left on the floor."
	remove.pressed.connect(_on_option_pressed.bind(_room_button, "Remove", ToolController.Tool.REMOVE_ROOM))
	_room_row.add_child(remove)
	# Furniture is wood only for now; the material is shown, not chosen.
	var wood := Button.new()
	wood.text = sim.config.structure_item.display_name if sim.config.structure_item != null else "Wood"
	wood.disabled = true
	_furniture_row.add_child(wood)
	for def: SlotDef in sim.config.furniture:
		var button := Button.new()
		button.text = def.display_name
		button.tooltip_text = _furniture_tooltip(sim, def)
		button.pressed.connect(_on_furniture_pressed.bind(def))
		_furniture_row.add_child(button)
	var remove_furniture := Button.new()
	remove_furniture.text = "Remove"
	remove_furniture.tooltip_text = "Click or drag over furniture. Plans go at once; what is built is taken apart and carried to storage."
	remove_furniture.pressed.connect(_on_option_pressed.bind(_furniture_button, "Remove", ToolController.Tool.REMOVE_FURNITURE))
	_furniture_row.add_child(remove_furniture)
	for type in sim.config.items.size():
		if sim.stock_targets[type] <= 0:
			continue
		var name_label := Label.new()
		name_label.text = sim.item_def(type).display_name
		_orders_grid.add_child(name_label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 200
		spin.step = 5
		spin.value = sim.stock_targets[type]
		spin.value_changed.connect(func(value: float) -> void: stock_target_changed.emit(type, int(value)))
		_orders_grid.add_child(spin)
	_refresh_totals()
	_refresh_requests()
	_refresh_dwarf_count()
	refresh_colony()


## Updates the mood readout. Called now and then, not every frame.
func refresh_colony() -> void:
	var good: int = 0
	var bad: int = 0
	for dwarf: Dwarf in _sim.dwarves:
		if dwarf.mood == Dwarf.Mood.GOOD:
			good += 1
		elif dwarf.mood == Dwarf.Mood.BAD:
			bad += 1
	var total: int = _sim.dwarves.size()
	if total == 0:
		_mood_label.text = "Mood: -"
	elif bad == 0 and good == total:
		_mood_label.text = "Mood: all good"
	elif bad == 0 and good == 0:
		_mood_label.text = "Mood: ok"
	else:
		_mood_label.text = "Mood: %d good, %d bad" % [good, bad]


func set_layer(layer: int) -> void:
	_layer_label.text = "Surface" if layer < 0 else "Layer %d" % (layer + 1)


func set_window_mode(mode: WindowController.Mode) -> void:
	var layered: bool = mode != WindowController.Mode.FULLSCREEN
	_dock(not layered)
	_layer_up.visible = layered
	_layer_label.visible = layered
	_layer_down.visible = layered
	_strip_button.disabled = mode == WindowController.Mode.STRIP
	_full_button.disabled = mode == WindowController.Mode.FULLSCREEN
	_corner_button.disabled = mode == WindowController.Mode.CORNER
	# The corner window is too narrow for the readout.
	_totals.visible = mode != WindowController.Mode.CORNER
	_mood_label.visible = mode != WindowController.Mode.CORNER


## Arranges the HUD for the window. In the strip and corner the toolbar runs
## along the bottom and the icon columns fill the right edge. In full screen
## everything keeps the same size and sits at the top: tools top left, icons
## top right.
func _dock(at_top: bool) -> void:
	_pin(_bar, at_top, BAR_MARGIN, BAR_HEIGHT)
	var panel_gap: float = BAR_MARGIN + BAR_HEIGHT + BAR_MARGIN
	_pin(_room_panel, at_top, panel_gap, SMALL_PANEL_HEIGHT)
	_pin(_furniture_panel, at_top, panel_gap, SMALL_PANEL_HEIGHT)
	_pin(_build_panel, at_top, panel_gap, SMALL_PANEL_HEIGHT)
	_pin(_debug_panel, at_top, panel_gap, SMALL_PANEL_HEIGHT)
	_pin(_requests_panel, at_top, panel_gap, REQUESTS_PANEL_HEIGHT)
	_pin(_orders_panel, at_top, panel_gap, REQUESTS_PANEL_HEIGHT)
	for column: VBoxContainer in [_view_column, _window_column]:
		column.anchor_bottom = 0.0 if at_top else 1.0
		column.offset_top = COLUMN_MARGIN
		column.offset_bottom = COLUMN_MARGIN + column.get_child_count() * ICON_BUTTON_HEIGHT if at_top else -COLUMN_MARGIN


## Fixes a control's height and places it a gap from the top or bottom edge.
func _pin(control: Control, at_top: bool, gap: float, height: float) -> void:
	var edge: float = 0.0 if at_top else 1.0
	control.anchor_top = edge
	control.anchor_bottom = edge
	control.offset_top = gap if at_top else -gap - height
	control.offset_bottom = gap + height if at_top else -gap


func set_reveal(enabled: bool) -> void:
	_reveal_check.set_pressed_no_signal(enabled)


func _on_tool_toggled(pressed: bool, tool: ToolController.Tool) -> void:
	if pressed:
		for other: ToolController.Tool in _tool_buttons:
			if other != tool:
				_tool_buttons[other].set_pressed_no_signal(false)
		_reset_pickers(null)
		tool_selected.emit(tool)
	else:
		tool_selected.emit(ToolController.Tool.NONE)


## The plain panels (requests, orders, debug) open one at a time.
func _on_panel_toggled(pressed: bool, button: Button) -> void:
	if pressed:
		for other: Button in _panels:
			if other != button:
				other.button_pressed = false
		for picker_panel: PanelContainer in _pickers.values():
			picker_panel.visible = false
	_panels[button].visible = pressed


## A picker button (Build, Room) opens its panel of choices. The tool only
## becomes active once a choice is made.
func _on_picker_toggled(pressed: bool, button: Button) -> void:
	for tool: ToolController.Tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(false)
	_reset_pickers(button)
	button.text = _picker_titles[button]
	tool_selected.emit(ToolController.Tool.NONE)
	if pressed:
		for panel_button: Button in _panels:
			panel_button.button_pressed = false
	_pickers[button].visible = pressed


## One of a picker's plain choices: it stands for a tool.
func _on_option_pressed(button: Button, label: String, tool: ToolController.Tool) -> void:
	_pickers[button].visible = false
	button.text = "%s: %s" % [_picker_titles[button], label]
	tool_selected.emit(tool)


## Steps to the next building material.
func _on_material_pressed() -> void:
	_material_index = (_material_index + 1) % _sim.config.build_materials.size()
	_show_material()
	build_material_selected.emit(_sim.config.build_materials[_material_index])


func _show_material() -> void:
	if _sim.config.build_materials.is_empty():
		return
	_material_button.text = _sim.config.build_materials[_material_index].display_name


func _on_furniture_pressed(def: SlotDef) -> void:
	_furniture_panel.visible = false
	_furniture_button.text = "Furniture: %s" % def.display_name
	furniture_tool_selected.emit(def)


func _furniture_tooltip(sim: Simulation, def: SlotDef) -> String:
	var where := PackedStringArray()
	for room: RoomDef in sim.config.rooms:
		if def.allowed_in(room.id):
			where.append(room.display_name.to_lower())
	var text: String = "Goes in: %s." % ", ".join(where)
	if def.kind == SlotDef.Kind.STATION:
		text += " Built in place from %d %s." % [def.item_count, def.item.display_name.to_lower()]
	else:
		text += " Made by the carpenter and carried in."
	if def.highest_rise() > 0:
		text += " Click the row on the wall it goes on."
	return text + " Click to place, right-click to remove."


func _on_room_type_pressed(def: RoomDef) -> void:
	_room_panel.visible = false
	_room_button.text = "Room: %s" % def.display_name
	room_tool_selected.emit(def)


## Closes every picker and unpresses its button, except the one given.
func _reset_pickers(except: Button) -> void:
	for button: Button in _pickers:
		if button == except:
			continue
		button.set_pressed_no_signal(false)
		button.text = _picker_titles[button]
		_pickers[button].visible = false

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
