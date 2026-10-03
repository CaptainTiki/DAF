class_name Simulation
extends RefCounted
## Root of the simulation. Owns all sim state and advances it one fixed tick at a time.
## Plain data and logic: nothing here touches the scene tree, so it can run headless,
## faster than real time, or (later) for save/load and offline catch-up.

signal tile_changed(x: int, y: int)
signal marks_changed(rect: Rect2i)
signal dwarf_hired(dwarf: Dwarf)

## How often pending orders are recalculated, in ticks.
const ORDER_INTERVAL: int = 10
## How often scaffolding that is no longer needed is looked for, in ticks.
const SCAFFOLD_INTERVAL: int = 40
## How many tiles of a quarry are marked at a time.
const QUARRY_BATCH: int = 3
## How often quarries and harvests are checked against the stock, in ticks.
const STOCK_INTERVAL: int = 40
const ALL_STRUCTURES: int = TileGrid.STRUCTURE_STAIR | TileGrid.STRUCTURE_FLOOR | TileGrid.STRUCTURE_SCAFFOLD
const NO_ITEM: int = -1

var config: SimConfig
var rng := RandomNumberGenerator.new()
var grid: TileGrid
var board := JobBoard.new()
var storage: Storage
var logistics := Logistics.new()
var rooms := Rooms.new()
var plants := Plants.new()
var orders := Orders.new()
var scaffolds := Scaffolder.new()
var needs := DwarfNeeds.new()
var requests := RequestLog.new()
var dwarves: Array[Dwarf] = []
var items: Dictionary[int, Item] = {}
## Things waiting to be built: planned stairs and unfinished room slots.
var sites: Array[BuildSite] = []
var tick_count: int = 0
## Bumped whenever an item appears, disappears, is picked up, dropped or comes to rest,
## so views can skip rebuilding when nothing changed.
var items_version: int = 0
## Where waste is tipped. Null if no item type is waste.
var dump_pile: Pile
## How many items have been tipped on the spoil heap.
var dumped: int = 0
## Standing orders: how many of each item type to keep in storage, per item
## type index. Starts from ItemDef.stock_target; the player can change it.
var stock_targets: PackedInt32Array
## Tick at which each Job.Kind was last taken up by a dwarf.
var kind_served: PackedInt32Array

var _driver := DwarfDriver.new()
var _unsettled: Array[Item] = []
## Structures being taken down, keyed the same way as _structure_sites.
var _removal_sites: Dictionary[Vector3i, BuildSite] = {}
## What each built structure is made of (item type), keyed like _structure_sites.
var _structure_items: Dictionary[Vector3i, int] = {}
## Planned structures, keyed by (x, y, STRUCTURE_ bit).
var _structure_sites: Dictionary[Vector3i, BuildSite] = {}
var _next_item_id: int = 1
var _name_order: PackedInt32Array
## Item type dropped per material index.
var _drop_type: PackedInt32Array


## With `generate` off the world is left empty, for SaveGame to fill in.
func _init(p_config: SimConfig, world_seed: int, generate: bool = true) -> void:
	config = p_config
	rng.seed = world_seed
	storage = Storage.new(config.items, config.pile_capacity)
	kind_served.resize(Job.KIND_COUNT)
	for item: ItemDef in config.items:
		stock_targets.append(item.stock_target)
	for material: MaterialDef in config.materials:
		_drop_type.append(item_type(material.drop))
	if not generate:
		return
	grid = WorldGenerator.generate(config.world_gen, config.materials, rng)
	_name_order = _shuffled_indices(config.dwarf_names.size())
	_plant_trees()
	_place_supplies()
	_place_dump()


func tick() -> void:
	tick_count += 1
	_tick_items()
	plants.tick(self)
	if tick_count % STOCK_INTERVAL == 0:
		_tick_quarries()
	if tick_count % ORDER_INTERVAL == 0:
		orders.update(self)
	if tick_count % SCAFFOLD_INTERVAL == 0:
		scaffolds.clean_up(self)
	rooms.tick(self)
	_tick_sites()
	for dwarf: Dwarf in dwarves:
		_driver.tick(self, dwarf)


func material_def(material: int) -> MaterialDef:
	return config.materials[material]


func item_def(type: int) -> ItemDef:
	return config.items[type]


## Index of an item definition, or NO_ITEM for null or unknown.
func item_type(def: ItemDef) -> int:
	if def == null:
		return NO_ITEM
	return config.items.find(def)


## A growth speed for a new plant: 1.0 give or take the plant type's variation.
func roll_growth_speed(def: PlantDef) -> float:
	return 1.0 + rng.randf_range(-def.growth_variation, def.growth_variation)


func is_craftable(type: int) -> bool:
	for recipe: RecipeDef in config.recipes:
		if item_type(recipe.output) == type:
			return true
	return false


func unsettled_item_count() -> int:
	return _unsettled.size()


## Loose items of a type that nobody is already carrying off to a request.
func loose_unassigned_count(type: int) -> int:
	var count: int = 0
	for item: Item in items.values():
		if item.type != type or item.state != Item.State.LOOSE:
			continue
		var job: Job = board.haul_job_for(item)
		if job == null or job.dest_request == null:
			count += 1
	return count


## Where new dwarves arrive: the entry room if the world has one, otherwise
## the middle of the surface.
func spawn_point() -> Vector2i:
	var world: WorldGenConfig = config.world_gen
	if world.entry_room_width > 0:
		var room: Rect2i = WorldGenerator.entry_room_rect(world)
		@warning_ignore("integer_division")
		return Vector2i(room.position.x + room.size.x / 2, room.end.y - 1)
	@warning_ignore("integer_division")
	return Vector2i(world.width / 2, world.surface_feet_row())


# --- Player commands ---

func hire_dwarf() -> Dwarf:
	var dwarf := Dwarf.new()
	dwarf.id = dwarves.size()
	dwarf.display_name = _next_name()
	dwarf.pos = _arrival_spot()
	dwarf.from_pos = dwarf.pos
	dwarf.facing = 1 if rng.randf() < 0.5 else -1
	dwarf.think_ticks = rng.randi_range(0, config.think_ticks_max)
	dwarf.pace = 1.0 + rng.randf_range(-config.pace_variation, config.pace_variation)
	dwarf.needs.resize(config.needs.size())
	dwarf.needs.fill(1.0)
	dwarf.need_quality.resize(config.needs.size())
	dwarves.append(dwarf)
	dwarf_hired.emit(dwarf)
	return dwarf


## Marks or unmarks every solid tile in the rect for digging. Tiles inside a
## room are left to the room: it plans its own digging. Returns how many changed.
func mark_dig(rect: Rect2i, marked: bool) -> int:
	return _mark_dig(rect, marked, false)


## The room tool's own digging: marks the rock inside a room's rect.
func plan_dig(rect: Rect2i) -> int:
	return _mark_dig(rect, true, true)


func _mark_dig(rect: Rect2i, marked: bool, inside_rooms: bool) -> int:
	var changed: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not grid.in_bounds(x, y) or not grid.is_solid(x, y) or grid.is_dig_marked(x, y) == marked:
				continue
			if not inside_rooms and grid.has_flag(x, y, TileGrid.FLAG_ROOM):
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
## spot on top of it. Spots inside a room are skipped. Returns how many changed.
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
				if rooms.room_at(tile) != null:
					continue
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
## see remove_structures for what is already built. Returns how many changed.
## `material` is what to build them from; null uses the default.
func mark_stairs(tiles: Array[Vector2i], marked: bool, material: ItemDef = null) -> int:
	return _mark_structure(TileGrid.STRUCTURE_STAIR, tiles, marked, material)


## Plans or cancels built floors on the open tiles in the rect. A floor is a
## platform along the top of its tile: it is walked on from the tile above.
## Returns how many changed.
func mark_floors(rect: Rect2i, marked: bool, material: ItemDef = null) -> int:
	var tiles: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			tiles.append(Vector2i(x, y))
	return _mark_structure(TileGrid.STRUCTURE_FLOOR, tiles, marked, material)


## The item type a built structure is made of. Anything not on record is taken
## to be made of the default material, which is NO_ITEM when structures are free.
func structure_item_type(tile: Vector2i, structure: int) -> int:
	return _structure_items.get(Vector3i(tile.x, tile.y, structure), item_type(config.structure_item))


## Plans or cancels scaffolding on the given open tiles. Dwarves normally do
## this themselves through the Scaffolder. Returns how many changed.
func mark_scaffolds(tiles: Array[Vector2i], marked: bool) -> int:
	return _mark_structure(TileGrid.STRUCTURE_SCAFFOLD, tiles, marked, null)


## Marks the structures in the rect to be taken down, or takes that mark off
## again. A plan that isn't built yet is simply cancelled; what is built is
## taken down by a dwarf, and its wood drops on the spot. `kinds` limits it to
## some STRUCTURE_ bits. Returns how many changed.
func mark_removal(rect: Rect2i, marked: bool, kinds: int = ALL_STRUCTURES) -> int:
	var changed: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not grid.in_bounds(x, y):
				continue
			var tile := Vector2i(x, y)
			for structure: int in [TileGrid.STRUCTURE_STAIR, TileGrid.STRUCTURE_FLOOR, TileGrid.STRUCTURE_SCAFFOLD]:
				if kinds & structure == 0:
					continue
				var key := Vector3i(x, y, structure)
				if not marked:
					if _removal_sites.has(key):
						cancel_site(_removal_sites[key])
						_removal_sites.erase(key)
						changed += 1
				elif _structure_sites.has(key):
					grid.set_flag(x, y, _mark_flag(structure), false)
					cancel_site(_structure_sites[key])
					_structure_sites.erase(key)
					changed += 1
				elif grid.structure_at(x, y) & structure != 0 and not _removal_sites.has(key):
					var site: BuildSite = add_site(tile, NO_ITEM, 0, config.remove_ticks, "", null)
					site.structure = structure
					site.removing = true
					_removal_sites[key] = site
					changed += 1
			grid.set_flag(x, y, TileGrid.FLAG_REMOVE_MARK, _has_removal_site(tile))
	if changed > 0:
		marks_changed.emit(rect.grow(1))
	return changed


## Whether this dwarf may finish the site right now. Taking something down
## waits while another dwarf is on it, and is refused if it would leave the
## worker with no way back to solid ground.
func can_complete_site(site: BuildSite, worker: Dwarf) -> bool:
	if not site.removing:
		return true
	if _is_structure_in_use(site.tile, site.structure, worker):
		return false
	# A tower comes down from the top.
	if site.structure == TileGrid.STRUCTURE_SCAFFOLD and grid.has_scaffold(site.tile.x, site.tile.y - 1):
		return false
	grid.remove_structure(site.tile.x, site.tile.y, site.structure)
	var safe: bool = _can_get_to_ground(worker.pos)
	grid.add_structure(site.tile.x, site.tile.y, site.structure)
	return safe


## Whether work on a site could start now, materials aside. Scaffolding goes up
## from the bottom: each tile needs something under it first.
func is_site_workable(site: BuildSite) -> bool:
	if site.structure == TileGrid.STRUCTURE_SCAFFOLD and not site.removing:
		return grid.is_ground(site.tile.x, site.tile.y + 1)
	if site.slot != null:
		# A room planned in rock: its furniture waits until the tile is dug out.
		return rooms.is_slot_ready(grid, site.slot)
	return true


func can_place_room(def: RoomDef, rect: Rect2i) -> bool:
	return rooms.fit(grid, def, rect).size != Vector2i.ZERO


## The space a room dragged over this rect would take, or an empty rect if it can't go there.
func room_fit(def: RoomDef, rect: Rect2i) -> Rect2i:
	return rooms.fit(grid, def, rect)


## Gives a stretch of dug floor a purpose. Null if the room doesn't fit there.
func place_room(def: RoomDef, rect: Rect2i) -> Room:
	var room: Room = rooms.place(self, def, rect)
	if room != null:
		# Grown upward as well, in case a joined room had a higher ceiling.
		marks_changed.emit(room.rect.grow_individual(0, Rooms.MAX_HEIGHT, 0, 0))
	return room


## Removes every room touching the rect. Returns how many were removed.
func remove_rooms(rect: Rect2i) -> int:
	var found: Array[Room] = rooms.rooms_in(rect)
	for room: Room in found:
		rooms.remove(self, room)
		marks_changed.emit(room.rect)
	return found.size()


# --- Build sites ---

## Registers something to be built in place. Pass NO_ITEM for a site that needs
## no materials.
func add_site(tile: Vector2i, type: int, count: int, work_ticks: int, purpose: String, slot: RoomSlot) -> BuildSite:
	var site := BuildSite.new()
	site.tile = tile
	site.work_ticks = work_ticks
	site.slot = slot
	if type != NO_ITEM and count > 0:
		site.request = logistics.add(tile, type, count, purpose)
	if work_ticks > 0:
		site.job = board.add_build(site)
	sites.append(site)
	return site


## Abandons a site. Materials already delivered drop to the floor.
func cancel_site(site: BuildSite) -> void:
	if site.done:
		return
	site.done = true
	sites.erase(site)
	if site.job != null:
		board.remove(site.job)
		site.job = null
	if site.request != null:
		spill(site.request.item_type, site.request.delivered, site.tile)
		logistics.close(site.request)


func complete_site(site: BuildSite) -> void:
	if site.done:
		return
	site.done = true
	sites.erase(site)
	if site.job != null:
		board.remove(site.job)
		site.job = null
	if site.request != null:
		logistics.close(site.request)
	if site.slot != null:
		rooms.slot_built(self, site.slot)
		return
	if site.removing:
		_take_down(site)
		return
	var key := Vector3i(site.tile.x, site.tile.y, site.structure)
	grid.set_flag(site.tile.x, site.tile.y, _mark_flag(site.structure), false)
	grid.add_structure(site.tile.x, site.tile.y, site.structure)
	_structure_sites.erase(key)
	if site.request != null:
		_structure_items[key] = site.request.item_type
	tile_changed.emit(site.tile.x, site.tile.y)


# --- Used by DwarfDriver ---

## Opens a dug tile and drops its item.
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
	if _drop_type[material] != NO_ITEM:
		spawn_item(_drop_type[material], tile)
	_mark_uncovered_ore(tile)
	tile_changed.emit(tile.x, tile.y)


## Finishes the station's current order and puts the result on its output pile.
func complete_craft(station: Station) -> void:
	var output: int = item_type(station.recipe.output)
	logistics.close(station.request)
	station.request = null
	station.recipe = null
	if station.job != null:
		board.remove(station.job)
		station.job = null
	if station.output == null or not storage.put(station.output, output):
		spawn_item(output, station.tile)


func complete_harvest(plant: Plant) -> void:
	plants.harvest(plant, board)
	spill(item_type(plant.def.yield_item), plant.def.yield_count, plant.tile)


func spawn_item(type: int, pos: Vector2i) -> Item:
	var item := _create_item(type, pos)
	_unsettled.append(item)
	board.add_haul(item)
	return item


## Makes an item that is already in a dwarf's hands, taken from a pile.
func create_carried_item(type: int, pos: Vector2i) -> Item:
	var item := _create_item(type, pos)
	item.state = Item.State.CARRIED
	return item


## Drops a number of loose items of one type on a tile.
func spill(type: int, count: int, pos: Vector2i) -> void:
	if type == NO_ITEM:
		return
	for n in count:
		spawn_item(type, pos)


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
	board.add_haul(item)
	items_version += 1


## Removes an item for good, once it has gone into a pile or been used up.
func remove_item(item: Item) -> void:
	var job: Job = board.haul_job_for(item)
	if job != null:
		board.remove(job)
	items.erase(item.id)
	items_version += 1


# --- Used by SaveGame ---

func structure_sites() -> Array[BuildSite]:
	var found: Array[BuildSite] = []
	found.assign(_structure_sites.values())
	found.append_array(_removal_sites.values())
	return found


func structure_items() -> Dictionary[Vector3i, int]:
	return _structure_items


func name_order() -> PackedInt32Array:
	return _name_order


func next_item_id() -> int:
	return _next_item_id


## Puts the bare world back from a save: the grid and the counters. Everything
## that lives on it is restored piece by piece by SaveGame afterwards.
func restore(data: Dictionary) -> void:
	tick_count = data["tick"]
	rng.state = data["rng_state"]
	dumped = data["dumped"]
	kind_served = data["kind_served"]
	stock_targets = data["stock_targets"]
	_name_order = data["name_order"]
	_next_item_id = data["next_item_id"]
	grid = TileGrid.new(data["grid_width"], data["grid_height"], data["first_layer_row"], data["layer_height"])
	grid.import_arrays(data["grid"])
	var structure_items_data: Dictionary = data["structure_items"]
	for key: Vector3i in structure_items_data:
		_structure_items[key] = structure_items_data[key]
	for y in grid.height:
		for x in grid.width:
			if grid.is_stockpile(x, y):
				storage.add_tile(Vector2i(x, y))


## Puts a pile back. The dump is recognised by its kind.
func restore_pile(data: Dictionary) -> Pile:
	var pile: Pile = storage.restore_pile(data["kind"], data["tile"], data["capacity"], data["only_type"], data["counts"])
	if pile.kind == Pile.Kind.DUMP:
		dump_pile = pile
	return pile


## Puts a loose item back on the floor. Whatever was carried is dropped.
func restore_item(data: Dictionary) -> Item:
	return spawn_item(data["type"], data["pos"])


## Puts a build site back, for a structure or (with `slot`) a room slot.
func restore_site(data: Dictionary, slot: RoomSlot) -> BuildSite:
	var request: Dictionary = data.get("request", {})
	var site: BuildSite = add_site(data["tile"], request.get("type", NO_ITEM), request.get("wanted", 0), data["work_ticks"], request.get("purpose", ""), slot)
	if site.request != null:
		site.request.delivered = request["delivered"]
	site.structure = data["structure"]
	site.removing = data["removing"]
	if slot == null:
		var key := Vector3i(site.tile.x, site.tile.y, site.structure)
		if site.removing:
			_removal_sites[key] = site
		else:
			_structure_sites[key] = site
	return site


## Dig marks in the grid become dig jobs again.
func restore_dig_jobs() -> void:
	for y in grid.height:
		for x in grid.width:
			if grid.is_dig_marked(x, y) and grid.is_solid(x, y):
				board.add_dig(Vector2i(x, y))


## Puts a dwarf back where they stood, idle: whatever they were doing, they
## pick up afresh from the job board.
func restore_dwarf(data: Dictionary) -> Dwarf:
	var dwarf := Dwarf.new()
	dwarf.id = data["id"]
	dwarf.display_name = data["name"]
	dwarf.experience = data["experience"]
	dwarf.beard_length = data["beard"]
	dwarf.think_ticks = data["think_ticks"]
	dwarf.pace = data["pace"]
	dwarf.pos = data["pos"]
	dwarf.from_pos = dwarf.pos
	dwarf.facing = data["facing"]
	dwarf.needs = data["needs"]
	dwarf.need_quality = data["need_quality"]
	dwarves.append(dwarf)
	dwarf_hired.emit(dwarf)
	return dwarf


# --- Internals ---

func _mark_structure(structure: int, tiles: Array[Vector2i], marked: bool, material: ItemDef) -> int:
	var material_type: int = item_type(material if material != null else config.structure_item)
	var flag: int = _mark_flag(structure)
	# Floors and scaffolding span open space; stairs can go through anything.
	var needs_open: bool = structure != TileGrid.STRUCTURE_STAIR
	var changed: int = 0
	var bounds := Rect2i()
	for tile: Vector2i in tiles:
		if not grid.in_bounds(tile.x, tile.y) or grid.material_at(tile.x, tile.y) == TileGrid.NO_MATERIAL:
			continue
		if needs_open and marked and not grid.is_open(tile.x, tile.y):
			continue
		if grid.structure_at(tile.x, tile.y) & structure != 0 or grid.has_flag(tile.x, tile.y, flag) == marked:
			continue
		grid.set_flag(tile.x, tile.y, flag, marked)
		var key := Vector3i(tile.x, tile.y, structure)
		if marked:
			var work_ticks: int = config.stair_build_ticks
			var purpose: String = "the stairs"
			match structure:
				TileGrid.STRUCTURE_FLOOR:
					work_ticks = config.floor_build_ticks
					purpose = "the floor"
				TileGrid.STRUCTURE_SCAFFOLD:
					work_ticks = config.scaffold_build_ticks
					purpose = "the scaffolding"
			var site: BuildSite = add_site(tile, material_type, config.structure_item_count, work_ticks, purpose, null)
			site.structure = structure
			_structure_sites[key] = site
		else:
			cancel_site(_structure_sites[key])
			_structure_sites.erase(key)
		bounds = Rect2i(tile, Vector2i.ONE) if changed == 0 else bounds.expand(tile).expand(tile + Vector2i.ONE)
		changed += 1
	if changed > 0:
		marks_changed.emit(bounds.grow(1))
	return changed


## Removes a built structure and drops the wood that was in it.
func _take_down(site: BuildSite) -> void:
	var tile: Vector2i = site.tile
	var key := Vector3i(tile.x, tile.y, site.structure)
	_removal_sites.erase(key)
	grid.remove_structure(tile.x, tile.y, site.structure)
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_REMOVE_MARK, _has_removal_site(tile))
	# What it was made of comes back.
	spill(structure_item_type(tile, site.structure), config.structure_item_count, tile)
	_structure_items.erase(key)
	if site.structure != TileGrid.STRUCTURE_STAIR:
		_drop_what_stood_on(tile)
	tile_changed.emit(tile.x, tile.y)


func _has_removal_site(tile: Vector2i) -> bool:
	return _removal_sites.has(Vector3i(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)) \
			or _removal_sites.has(Vector3i(tile.x, tile.y, TileGrid.STRUCTURE_FLOOR)) \
			or _removal_sites.has(Vector3i(tile.x, tile.y, TileGrid.STRUCTURE_SCAFFOLD))


## True if a dwarf at this spot is held up and can walk to somewhere with real
## ground underfoot (or is standing on it already).
func _can_get_to_ground(from: Vector2i) -> bool:
	if not Pathfinder.is_supported(grid, from.x, from.y):
		return false
	var flood_map: FloodMap = Pathfinder.flood(grid, from, 64)
	for index: int in flood_map.reached:
		var x: int = index % grid.width
		@warning_ignore("integer_division")
		var y: int = index / grid.width
		if Pathfinder.can_stand(grid, x, y):
			return true
	return false


func _mark_flag(structure: int) -> int:
	return TileGrid.FLAG_FLOOR_MARK if structure == TileGrid.STRUCTURE_FLOOR else TileGrid.FLAG_BUILD_MARK


## A dwarf other than the worker is on this stair, or standing on this floor,
## or still stepping off it.
func _is_structure_in_use(tile: Vector2i, structure: int, worker: Dwarf) -> bool:
	# A stair is used by standing in its tile; floors and scaffolding by standing on top.
	var spot: Vector2i = tile if structure == TileGrid.STRUCTURE_STAIR else tile + Vector2i.UP
	for dwarf: Dwarf in dwarves:
		if dwarf == worker:
			continue
		if dwarf.pos == spot or (dwarf.move_ticks_left > 0 and dwarf.from_pos == spot):
			return true
	return false


## After a floor is taken away: loose items on it fall, and a stockpile spot on it goes.
func _drop_what_stood_on(tile: Vector2i) -> void:
	if grid.is_solid(tile.x, tile.y):
		return
	var above: Vector2i = tile + Vector2i.UP
	for item: Item in items.values():
		if item.state == Item.State.LOOSE and item.settled and item.pos == above:
			_unsettle(item)
	if grid.is_stockpile(above.x, above.y):
		_remove_stockpile_tile(above)

func _create_item(type: int, pos: Vector2i) -> Item:
	var item := Item.new()
	item.id = _next_item_id
	_next_item_id += 1
	item.type = type
	item.pos = pos
	item.from_pos = pos
	items[item.id] = item
	items_version += 1
	return item


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
		if not grid.is_ground(item.pos.x, item.pos.y + 1):
			item.from_pos = item.pos
			item.pos.y += 1
			item.move_ticks_left = config.fall_ticks
			item.move_ticks_total = config.fall_ticks
		else:
			item.from_pos = item.pos
			item.settled = true
			_unsettled.remove_at(i)
			items_version += 1


## Standing order: ore showing in the walls of a freshly dug tile gets marked
## for mining, so a vein is followed as it is uncovered.
func _mark_uncovered_ore(tile: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = tile.x + dx
			var y: int = tile.y + dy
			if not grid.is_solid(x, y) or not grid.in_bounds(x, y) or grid.is_dig_marked(x, y):
				continue
			if grid.has_flag(x, y, TileGrid.FLAG_ROOM):
				continue
			if material_def(grid.material_at(x, y)).auto_mine:
				_mark_dig(Rect2i(x, y, 1, 1), true, false)


## Standing order: a quarry is dug a few tiles at a time while what its rock
## yields is short in storage. Tiles beside open space go first.
func _tick_quarries() -> void:
	for room: Room in rooms.rooms:
		if not room.def.quarry:
			continue
		var marked: int = 0
		var candidates: Array[Vector2i] = []
		for y in range(room.rect.position.y, room.rect.end.y):
			for x in range(room.rect.position.x, room.rect.end.x):
				if not grid.is_solid(x, y):
					continue
				if grid.is_dig_marked(x, y):
					marked += 1
				elif is_short(_drop_type[grid.material_at(x, y)]) and _touches_open(x, y):
					candidates.append(Vector2i(x, y))
		for tile: Vector2i in candidates:
			if marked >= QUARRY_BATCH:
				break
			_mark_dig(Rect2i(tile, Vector2i.ONE), true, true)
			marked += 1


func set_stock_target(type: int, target: int) -> void:
	stock_targets[type] = maxi(target, 0)


## Fewer of this item in storage than the standing order asks for. Items with
## no target are never short: they are only ever gathered on purpose.
func is_short(type: int) -> bool:
	if type == NO_ITEM:
		return false
	var target: int = stock_targets[type]
	return target > 0 and storage.totals[type] < target


func _touches_open(x: int, y: int) -> bool:
	return grid.is_open(x - 1, y) or grid.is_open(x + 1, y) or grid.is_open(x, y - 1) or grid.is_open(x, y + 1)


## Sites that need no work are done the moment their materials arrive.
func _tick_sites() -> void:
	for i in range(sites.size() - 1, -1, -1):
		var site: BuildSite = sites[i]
		if site.work_ticks == 0 and site.is_ready() and is_site_workable(site):
			complete_site(site)


func _unsettle(item: Item) -> void:
	item.settled = false
	if not _unsettled.has(item):
		_unsettled.append(item)


## Makes a tile a storage spot. Used by storerooms; the Stockpile tool uses mark_stockpile.
func add_stockpile_tile(tile: Vector2i) -> void:
	if grid.is_stockpile(tile.x, tile.y):
		return
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_STOCKPILE, true)
	storage.add_tile(tile)
	marks_changed.emit(Rect2i(tile, Vector2i.ONE))


func remove_stockpile_tile(tile: Vector2i) -> void:
	if not grid.is_stockpile(tile.x, tile.y):
		return
	_remove_stockpile_tile(tile)


func _remove_stockpile_tile(tile: Vector2i) -> void:
	grid.set_flag(tile.x, tile.y, TileGrid.FLAG_STOCKPILE, false)
	var pile: Pile = storage.remove_tile(tile)
	if pile != null:
		for type: int in pile.counts:
			spill(type, pile.counts[type], tile)
	marks_changed.emit(Rect2i(tile, Vector2i.ONE))


func _plant_trees() -> void:
	var world: WorldGenConfig = config.world_gen
	if world.tree == null or world.tree_count <= 0:
		return
	var feet: int = world.surface_feet_row()
	@warning_ignore("integer_division")
	var centre: int = world.width / 2
	var columns: Array[int] = []
	for attempt in world.tree_count * 20:
		if columns.size() >= world.tree_count:
			break
		var x: int = rng.randi_range(2, world.width - 3)
		if absi(x - centre) < world.tree_clearing:
			continue
		var crowded: bool = false
		for other: int in columns:
			if absi(x - other) < 3:
				crowded = true
		if crowded:
			continue
		columns.append(x)
		@warning_ignore("integer_division")
		plants.add(world.tree, Vector2i(x, feet), rng.randi_range(world.tree.grow_ticks / 2, world.tree.grow_ticks), roll_growth_speed(world.tree))


func _place_supplies() -> void:
	var type: int = item_type(config.starting_item)
	if type == NO_ITEM or config.starting_item_count <= 0:
		return
	var pile: Pile = storage.add_pile(Pile.Kind.SUPPLY, spawn_point(), Pile.UNLIMITED)
	for n in config.starting_item_count:
		storage.put(pile, type)


## Sets up the spoil heap on the surface, if any item type is waste.
func _place_dump() -> void:
	var has_waste: bool = false
	for item: ItemDef in config.items:
		has_waste = has_waste or item.dump
	if not has_waste:
		return
	# Always on the surface, whatever level the dwarves arrive on.
	var x: int = clampi(spawn_point().x + config.dump_offset, 0, grid.width - 1)
	var tile := Vector2i(x, config.world_gen.surface_feet_row())
	dump_pile = storage.add_pile(Pile.Kind.DUMP, tile, Pile.UNLIMITED)


func _arrival_spot() -> Vector2i:
	var world: WorldGenConfig = config.world_gen
	if world.entry_room_width > 0:
		var room: Rect2i = WorldGenerator.entry_room_rect(world)
		return Vector2i(rng.randi_range(room.position.x, room.end.x - 1), room.end.y - 1)
	return spawn_point() + Vector2i(rng.randi_range(-2, 2), 0)


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
