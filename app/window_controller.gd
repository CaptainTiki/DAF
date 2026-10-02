class_name WindowController
extends Node
## Switches the game window between its desktop modes and remembers the last one.

signal mode_changed(mode: Mode)

enum Mode { STRIP, FULLSCREEN, CORNER, TRAY }

const SETTINGS_PATH: String = "user://window.cfg"

@export var strip_height: int = 150
@export var corner_size := Vector2i(480, 270)
@export var corner_margin: int = 16
@export_group("Frame rate caps")
@export var strip_fps: int = 30
@export var fullscreen_fps: int = 60
@export var corner_fps: int = 30
@export var tray_fps: int = 5

var mode: Mode = Mode.STRIP

@onready var _tray: StatusIndicator = $Tray

## Mode to return to when the tray icon is clicked.
var _restore_mode: Mode = Mode.STRIP
var _apply_serial: int = 0


func _ready() -> void:
	_tray.pressed.connect(_on_tray_pressed)


## Applies the mode saved by the previous run, or the strip on first run.
func restore_last_mode() -> void:
	var settings := ConfigFile.new()
	var saved: int = Mode.STRIP
	if settings.load(SETTINGS_PATH) == OK:
		saved = settings.get_value("window", "mode", Mode.STRIP)
	if saved < 0 or saved >= Mode.TRAY:
		saved = Mode.STRIP
	set_mode(saved as Mode)


func set_mode(value: Mode) -> void:
	if value == Mode.TRAY and mode != Mode.TRAY:
		_restore_mode = mode
	mode = value
	_apply()
	if mode != Mode.TRAY:
		_save()
	mode_changed.emit(mode)


func _apply() -> void:
	Engine.max_fps = _fps_cap()
	_tray.visible = mode == Mode.TRAY
	if Engine.is_embedded_in_editor():
		# The editor owns the window when the game is embedded in it.
		push_warning("Window modes need the game in its own window. Turn off 'Embed Game on Next Play' in the editor's Game tab.")
		return
	var window: Window = get_window()
	# The UI keeps its real pixel size in every mode, so buttons are the same
	# size in the strip, the corner and full screen. This overrides the
	# project's stretch setting.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	match mode:
		Mode.TRAY:
			# Godot can't hide its main window, so minimise it; the tray icon brings it back.
			window.mode = Window.MODE_MINIMIZED
		Mode.FULLSCREEN:
			window.always_on_top = false
			window.mode = Window.MODE_FULLSCREEN
		_:
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			window.unresizable = true
			window.always_on_top = true
			_place(window)
			# Leaving fullscreen or minimised takes the OS a frame; place again once it settles.
			_apply_serial += 1
			var serial: int = _apply_serial
			await get_tree().process_frame
			await get_tree().process_frame
			if serial == _apply_serial and (mode == Mode.STRIP or mode == Mode.CORNER):
				_place(window)


func _place(window: Window) -> void:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	if mode == Mode.STRIP:
		window.size = Vector2i(usable.size.x, strip_height)
		window.position = Vector2i(usable.position.x, usable.end.y - strip_height)
	else:
		window.size = corner_size
		window.position = usable.end - corner_size - Vector2i(corner_margin, corner_margin)


func _fps_cap() -> int:
	match mode:
		Mode.FULLSCREEN:
			return fullscreen_fps
		Mode.CORNER:
			return corner_fps
		Mode.TRAY:
			return tray_fps
	return strip_fps


func _on_tray_pressed(_mouse_button: int, _mouse_position: Vector2i) -> void:
	if mode == Mode.TRAY:
		set_mode(_restore_mode)


func _save() -> void:
	var settings := ConfigFile.new()
	settings.set_value("window", "mode", mode)
	settings.save(SETTINGS_PATH)
