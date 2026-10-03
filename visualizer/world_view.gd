class_name WorldView
extends Node3D
## Everything that draws the simulation. Reads sim state; never changes it.

@export var dwarf_scene: PackedScene

@onready var camera: ViewCamera = $Camera
@onready var _tiles: TileLayer = $Tiles
@onready var _marks: MarkLayer = $Marks
@onready var _items: ItemLayer = $Items
@onready var _furniture: FurnitureLayer = $Furniture
@onready var _dwarf_root: Node3D = $Dwarves
@onready var _structures: StructureLayer = $Structures
@onready var _selection: MeshInstance3D = $Selection
@onready var _tile_selection: MultiMeshInstance3D = $TileSelection

var _sim: Simulation
## One view per dwarf, indexed by dwarf id. Views are kept and reused, never freed.
var _dwarf_views: Array[DwarfView] = []
var _selection_material: StandardMaterial3D
## Tiles drawn shrunk last frame because someone was digging them.
var _digging: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	_selection_material = _selection.mesh.surface_get_material(0)


func bind(sim: Simulation) -> void:
	_sim = sim
	_tiles.bind(sim)
	_marks.bind(sim)
	_items.bind(sim)
	_furniture.bind(sim)
	_structures.bind(sim)
	camera.bind(sim.grid)
	sim.tile_changed.connect(_on_tile_changed)
	sim.marks_changed.connect(_marks.refresh_rect)
	sim.dwarf_hired.connect(_add_dwarf_view)
	for dwarf: Dwarf in sim.dwarves:
		_add_dwarf_view(dwarf)


## Call once per frame after the sim has ticked. alpha is the fraction of the
## way into the next tick, for smooth movement between ticks.
func refresh(alpha: float) -> void:
	_items.refresh(alpha)
	_furniture.refresh()
	for view: DwarfView in _dwarf_views:
		view.refresh(_sim, alpha)
	_show_digging()


## Tiles being dug shrink as the work goes on. Any tile that was shrinking
## last frame but isn't being worked on now is drawn whole again.
func _show_digging() -> void:
	var now: Dictionary[Vector2i, bool] = {}
	for dwarf: Dwarf in _sim.dwarves:
		if dwarf.activity != Dwarf.Activity.WORK or dwarf.job == null or dwarf.job.kind != Job.Kind.DIG:
			continue
		var tile: Vector2i = dwarf.work_tile
		if not _sim.grid.is_solid(tile.x, tile.y):
			continue
		now[tile] = true
		_tiles.show_dig_progress(tile.x, tile.y, dwarf.work_fraction())
	for tile: Vector2i in _digging:
		if not now.has(tile) and _sim.grid.in_bounds(tile.x, tile.y):
			_tiles.refresh_tile(tile.x, tile.y)
	_digging = now


func set_reveal_all(enabled: bool) -> void:
	_tiles.reveal_all = enabled


func set_room_overlay(enabled: bool) -> void:
	_marks.show_rooms = enabled


## Shows or hides the faint outlines of furniture that isn't built yet.
func set_planned_furniture_visible(enabled: bool) -> void:
	_furniture.set_planned_visible(enabled)


## Shows the drag rectangle for a tool, in tiles.
func show_selection(rect: Rect2i, color: Color) -> void:
	_tile_selection.visible = false
	_selection_material.albedo_color = color
	_selection.position = Vector3(rect.position.x + rect.size.x * 0.5, -(rect.position.y + rect.size.y * 0.5), ViewSpace.LANE_OVERLAY + 0.2)
	_selection.scale = Vector3(rect.size.x, rect.size.y, 1.0)
	_selection.visible = true


## Shows a tool preview on individual tiles, for shapes that aren't a rectangle.
func show_tile_selection(tiles: Array[Vector2i], color: Color) -> void:
	_selection.visible = false
	var mesh: MultiMesh = _tile_selection.multimesh
	if mesh.instance_count < tiles.size():
		mesh.instance_count = maxi(64, tiles.size() * 2)
	for i in tiles.size():
		mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, ViewSpace.tile_center(tiles[i].x, tiles[i].y, ViewSpace.LANE_OVERLAY + 0.2)))
		mesh.set_instance_color(i, color)
	mesh.visible_instance_count = tiles.size()
	_tile_selection.visible = true


func hide_selection() -> void:
	_selection.visible = false
	_tile_selection.visible = false


func _on_tile_changed(x: int, y: int) -> void:
	_tiles.refresh_around(x, y)
	_marks.refresh_tile(x, y)
	_structures.refresh_tile(x, y)


func _add_dwarf_view(dwarf: Dwarf) -> void:
	var view: DwarfView = dwarf_scene.instantiate()
	_dwarf_root.add_child(view)
	view.bind(dwarf)
	_dwarf_views.append(view)
