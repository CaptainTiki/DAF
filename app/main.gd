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

var _sim: Simulation
var _clock: SimClock


func _ready() -> void:
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
	_hud.hire_requested.connect(_sim.hire_dwarf)
	_hud.speed_selected.connect(func(multiplier: float) -> void: _clock.speed = multiplier)
	_hud.reveal_toggled.connect(_world_view.set_reveal_all)
	_hud.layer_step_requested.connect(_world_view.camera.step_layer)
	_hud.window_mode_requested.connect(_window.set_mode)
	_world_view.camera.layer_changed.connect(_hud.set_layer)
	_window.mode_changed.connect(_on_window_mode_changed)

	_hud.set_reveal(false)
	_hud.set_layer(_world_view.camera.layer)
	for i in starting_dwarves:
		_sim.hire_dwarf()
	_window.restore_last_mode()


func _process(delta: float) -> void:
	for i in _clock.advance(delta):
		_sim.tick()
	_world_view.refresh(_clock.alpha)


func _on_window_mode_changed(mode: WindowController.Mode) -> void:
	match mode:
		WindowController.Mode.STRIP:
			_world_view.camera.show_layers(strip_layers)
		WindowController.Mode.CORNER:
			_world_view.camera.show_layers(corner_layers)
		WindowController.Mode.FULLSCREEN:
			_world_view.camera.set_free()
	_hud.set_window_mode(mode)
