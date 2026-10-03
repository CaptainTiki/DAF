extends Node
## Composition root. Creates the simulation, hands it to the view and UI, and
## wires their signals together. All cross-system wiring lives here, so there is
## no autoload and no global signal bus.

@export var config: SimConfig
## 0 picks a random seed each run.
@export var world_seed: int = 0
@export var starting_dwarves: int = 3
@export var strip_layers: int = 2
@export var corner_layers: int = 3

@onready var _world_view: WorldView = $WorldView
@onready var _hud: Hud = $UiLayer/Hud
@onready var _tools: ToolController = $ToolController
@onready var _window: WindowController = $WindowController

## How often the HUD's colony readout is brought up to date.
const COLONY_REFRESH_SECONDS: float = 0.5
const SAVE_PATH: String = "user://save.dat"
const AUTOSAVE_SECONDS: float = 120.0

var _sim: Simulation
var _colony_refresh_left: float = 0.0
var _autosave_left: float = AUTOSAVE_SECONDS
var _clock: SimClock


func _ready() -> void:
	# The last save is picked up where it left off; otherwise a new world.
	_sim = SaveGame.read(config, SAVE_PATH)
	var loaded: bool = _sim != null
	if not loaded:
		var seed_value: int = world_seed if world_seed != 0 else randi()
		print("World seed: %d" % seed_value)
		_sim = Simulation.new(config, seed_value)
	_clock = SimClock.new(config.ticks_per_second)

	_world_view.set_reveal_all(false)
	# The dwarves arrive on the surface, so that is where the view starts.
	_world_view.camera.layer = -1
	_world_view.bind(_sim)
	_hud.bind(_sim)
	_tools.bind(_sim, _world_view)

	_hud.tool_selected.connect(_tools.set_tool)
	_hud.room_tool_selected.connect(_tools.set_room_tool)
	_hud.build_material_selected.connect(_tools.set_build_material)
	_hud.stock_target_changed.connect(_sim.set_stock_target)
	_hud.save_requested.connect(_save)
	_hud.load_requested.connect(_reload)
	_hud.new_game_requested.connect(_new_game)
	_hud.hire_requested.connect(_sim.hire_dwarf)
	_hud.speed_selected.connect(func(multiplier: float) -> void: _clock.speed = multiplier)
	_hud.reveal_toggled.connect(_world_view.set_reveal_all)
	_hud.room_overlay_toggled.connect(_world_view.set_room_overlay)
	_hud.planned_furniture_toggled.connect(_world_view.set_planned_furniture_visible)
	_hud.layer_step_requested.connect(_world_view.camera.step_layer)
	_hud.window_mode_requested.connect(_window.set_mode)
	_world_view.camera.layer_changed.connect(_hud.set_layer)
	_window.mode_changed.connect(_on_window_mode_changed)

	_hud.set_reveal(false)
	_hud.set_layer(_world_view.camera.layer)
	if not loaded:
		for i in starting_dwarves:
			_sim.hire_dwarf()
	_window.restore_last_mode()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _sim != null:
		_save()


func _save() -> void:
	_autosave_left = AUTOSAVE_SECONDS
	SaveGame.write(_sim, SAVE_PATH)


## Starts the scene over; _ready picks up the save (or the lack of one).
func _reload() -> void:
	get_tree().reload_current_scene()


func _new_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_reload()


func _process(delta: float) -> void:
	for i in _clock.advance(delta):
		_sim.tick()
	_world_view.refresh(_clock.alpha, delta)
	_colony_refresh_left -= delta
	if _colony_refresh_left <= 0.0:
		_colony_refresh_left = COLONY_REFRESH_SECONDS
		_hud.refresh_colony()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_save()


func _on_window_mode_changed(mode: WindowController.Mode) -> void:
	match mode:
		WindowController.Mode.STRIP:
			_world_view.camera.show_layers(strip_layers)
		WindowController.Mode.CORNER:
			_world_view.camera.show_layers(corner_layers)
		WindowController.Mode.FULLSCREEN:
			_world_view.camera.set_free()
	_hud.set_window_mode(mode)
