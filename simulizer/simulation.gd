class_name Simulation
extends RefCounted
## Root of the simulation. Owns all sim state and advances it one fixed tick at a time.
## Plain data and logic: nothing here touches the scene tree, so it can run headless,
## faster than real time, or (later) for save/load and offline catch-up.

signal tile_changed(x: int, y: int)
signal marks_changed(rect: Rect2i)
signal dwarf_hired(dwarf: Dwarf)

var config: SimConfig
var rng := RandomNumberGenerator.new()
var grid: TileGrid
var board := JobBoard.new()
var storage: Storage
var requests := RequestLog.new()
var dwarves: Array[Dwarf] = []
var items: Dictionary[int, Item] = {}
var tick_count: int = 0
## Bumped whenever a ball appears, disappears, is picked up, dropped or comes to rest,
## so views can skip rebuilding when nothing changed.
var items_version: int = 0

var _driver := DwarfDriver.new()
var _unsettled: Array[Item] = []
var _next_item_id: int = 1
var _name_order: PackedInt32Array


func _init(p_config: SimConfig, world_seed: int) -> void:
	config = p_config
	rng.seed = world_seed
	grid = WorldGenerator.generate(config.world_gen, config.materials, rng)
	storage = Storage.new(config.materials.size())
	_name_order = _shuffled_indices(config.dwarf_names.size())


func tick() -> void:
	tick_count += 1
	_tick_items()
	for dwarf: Dwarf in dwarves:
		_driver.tick(self, dwarf)


func material_def(material: int) -> MaterialDef:
	return config.materials[material]


func unsettled_item_count() -> int:
	return _unsettled.size()


# --- Player commands ---

func hire_dwarf() -> Dwarf:
	var room: Rect2i = WorldGenerator.entry_room_rect(config.world_gen)
	var dwarf := Dwarf.new()
	dwarf.id = dwarves.size()
	dwarf.display_name = _next_name()
	dwarf.pos = Vector2i(rng.randi_range(room.position.x, room.end.x - 1), room.end.y - 1)
	dwarf.from_pos = dwarf.pos
	dwarf.facing = 1 if rng.randf() < 0.5 else -1
	dwarf.think_ticks = rng.randi_range(0, config.think_ticks_max)
	dwarf.pace = 1.0 + rng.randf_range(-config.pace_variation, config.pace_variation)
	dwarves.append(dwarf)
	dwarf_hired.emit(dwarf)
	return dwarf


## Marks or unmarks every solid tile in the rect for digging. Returns how many changed.
func mark_dig(rect: Rect2i, marked: bool) -> int:
	var changed: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not grid.in_bounds(x, y) or not grid.is_solid(x, y) or grid.is_dig_marked(x, y) == marked:
				continue
			grid.set_flag(x, y, TileGrid.FLAG_DIG_MARK, marked)
			var tile := Vector2i(x, y)
			if marked:
				board.add_dig(tile)
			else:
				var job: Job = board.dig_job_at(tile)
				if job != null:
					board.remove(job)
			changed += 1
	if changed > 0:
		marks_changed.emit(rect)
	return changed


## Marks or unmarks floor spots in the rect as stockpile. A floor spot is an open
## tile with solid ground under it; dragging over the ground itself marks the
## spot on top of it. Returns how many changed.
func mark_stockpile(rect: Rect2i, marked: bool) -> int:
	var changed: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var spot_y: int = y
			if grid.is_solid(x, y) and grid.is_open(x, y - 1):
				spot_y = y - 1
			if not grid.is_open(x, spot_y) or not grid.is_solid(x, spot_y + 1):
				continue
			if grid.is_stockpile(x, spot_y) == marked:
				continue
			var tile := Vector2i(x, spot_y)
			if marked:
				grid.set_flag(x, spot_y, TileGrid.FLAG_STOCKPILE, true)
				storage.add_tile(tile)
			else:
				_remove_stockpile_tile(tile)
			changed += 1
	if changed > 0:
		marks_changed.emit(rect.grow(1))
	return changed


## Plans or cancels stairs on the given tiles. Stairs are built in the back lane,
## so the tile can be rock, floor or open room. Cancelling only removes plans;
## built stairs stay. Returns how many changed.
func mark_stairs(tiles: Array[Vector2i], marked: bool) -> int:
	var changed: int = 0
	var bounds := Rect2i()
	for tile: Vector2i in tiles:
		if not grid.in_bounds(tile.x, tile.y) or grid.material_at(tile.x, tile.y) == TileGrid.NO_MATERIAL:
			continue
		if grid.has_stair(tile.x, tile.y) or grid.is_build_marked(tile.x, tile.y) == marked:
			continue
		grid.set_flag(tile.x, tile.y, TileGrid.FLAG_BUILD_MARK, marked)
		if marked:
			board.add_build(tile)
		else:
			var job: Job = board.build_job_at(tile)
			if job != null:
				board.remove(job)
		bounds = Rect2i(tile, Vector2i.ONE) if changed == 0 else bounds.expand(tile).expand(tile + Vector2i.ONE)
		changed += 1
	if changed > 0:
		marks_changed.emit(bounds.grow(1))
	return changed


# --- Used by DwarfDriver ---

## Turns a planned stair tile into a built one.
func complete_build(tile: Vector2i) -> void:
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_BUILD_MARK, false)
	grid.set_structure(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)
	var job: Job = board.build_job_at(tile)
	if job != null:
		board.remove(job)
	tile_changed.emit(tile.x, tile.y)


## Opens a dug tile and drops its resource ball.
func complete_dig(tile: Vector2i) -> void:
	var material: int = grid.material_at(tile.x, tile.y)
	grid.set_open(tile.x, tile.y)
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_DIG_MARK, false)
	var job: Job = board.dig_job_at(tile)
	if job != null:
		board.remove(job)
	# Anything resting on this tile loses its footing.
	for item: Item in items.values():
		if item.state == Item.State.LOOSE and item.settled and item.pos.x == tile.x and item.pos.y == tile.y - 1:
			_unsettle(item)
	if grid.is_stockpile(tile.x, tile.y - 1):
		_remove_stockpile_tile(Vector2i(tile.x, tile.y - 1))
	var def: MaterialDef = material_def(material)
	var drop: int = material if def.drop == null else config.materials.find(def.drop)
	spawn_item(drop, tile)
	tile_changed.emit(tile.x, tile.y)


func spawn_item(material: int, pos: Vector2i) -> Item:
	var item := Item.new()
	item.id = _next_item_id
	_next_item_id += 1
	item.material = material
	item.pos = pos
	item.from_pos = pos
	items[item.id] = item
	_unsettled.append(item)
	board.add_haul(item)
	items_version += 1
	return item


func pick_up_item(item: Item) -> void:
	item.state = Item.State.CARRIED
	item.settled = false
	items_version += 1


func drop_item(item: Item, pos: Vector2i) -> void:
	item.state = Item.State.LOOSE
	item.pos = pos
	item.from_pos = pos
	item.move_ticks_left = 0
	_unsettle(item)
	items_version += 1


## Removes a ball for good, once it has gone into a pallet.
func remove_item(item: Item) -> void:
	var job: Job = board.haul_job_for(item)
	if job != null:
		board.remove(job)
	items.erase(item.id)
	items_version += 1


# --- Internals ---

func _tick_items() -> void:
	for i in range(_unsettled.size() - 1, -1, -1):
		var item: Item = _unsettled[i]
		if item.state != Item.State.LOOSE or not items.has(item.id):
			_unsettled.remove_at(i)
			continue
		if item.move_ticks_left > 0:
			item.move_ticks_left -= 1
			if item.move_ticks_left > 0:
				continue
		if grid.is_open(item.pos.x, item.pos.y + 1):
			item.from_pos = item.pos
			item.pos.y += 1
			item.move_ticks_left = config.fall_ticks
			item.move_ticks_total = config.fall_ticks
		else:
			item.from_pos = item.pos
			item.settled = true
			_unsettled.remove_at(i)
			items_version += 1


func _unsettle(item: Item) -> void:
	item.settled = false
	if not _unsettled.has(item):
		_unsettled.append(item)


func _remove_stockpile_tile(tile: Vector2i) -> void:
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_STOCKPILE, false)
	var pallet: Pallet = storage.remove_tile(tile)
	if pallet != null and pallet.placed:
		for n in pallet.count:
			spawn_item(pallet.material, tile)
	marks_changed.emit(Rect2i(tile, Vector2i.ONE))


func _next_name() -> String:
	if _name_order.is_empty():
		return "Dwarf %d" % (dwarves.size() + 1)
	var base: String = config.dwarf_names[_name_order[dwarves.size() % _name_order.size()]]
	@warning_ignore("integer_division")
	var round_number: int = dwarves.size() / _name_order.size()
	return base if round_number == 0 else "%s %d" % [base, round_number + 1]


func _shuffled_indices(count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	for i in count:
		order.append(i)
	for i in range(count - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	return order
