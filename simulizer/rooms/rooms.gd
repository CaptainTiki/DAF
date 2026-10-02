class_name Rooms
extends RefCounted
## All rooms and their stations. Placing a room lays out its slots from the
## room type; each slot then asks for what it needs through build sites.

## Emitted when a room is placed or removed, or a slot gets built.
signal changed

## Rooms are never taller than this, however high the ceiling.
const MAX_HEIGHT: int = 8

var rooms: Array[Room] = []
var stations: Array[Station] = []

var _room_at: Dictionary[Vector2i, Room] = {}
var _next_id: int = 1


func room_at(tile: Vector2i) -> Room:
	return _room_at.get(tile)


## The room a drag would make: the rect snapped to the floor it touches and
## the open space above it. An empty rect means a room can't go there.
func fit(grid: TileGrid, def: RoomDef, rect: Rect2i) -> Rect2i:
	var left: int = maxi(rect.position.x, 0)
	var right: int = mini(rect.end.x, grid.width) - 1
	if right < left:
		return Rect2i()
	var feet: int = -1
	for row in range(rect.end.y - 1, rect.position.y - 2, -1):
		if _is_floor_spot(grid, left, row):
			feet = row
			break
	if feet < 0:
		return Rect2i()
	var height: int = MAX_HEIGHT
	for x in range(left, right + 1):
		if not _is_floor_spot(grid, x, feet) or _room_at.has(Vector2i(x, feet)) or grid.is_stockpile(x, feet):
			return Rect2i()
		var open: int = 0
		while open < height and _is_indoors(grid, x, feet - open):
			open += 1
		height = open
	var width: int = right - left + 1
	if width < def.min_width or height < def.min_height:
		return Rect2i()
	return Rect2i(left, feet - height + 1, width, height)


func place(sim: Simulation, def: RoomDef, rect: Rect2i) -> Room:
	var fitted: Rect2i = fit(sim.grid, def, rect)
	if fitted.size == Vector2i.ZERO:
		return null
	var room := Room.new()
	room.id = _next_id
	_next_id += 1
	room.def = def
	room.rect = fitted
	room.feet_row = fitted.end.y - 1
	rooms.append(room)
	for y in range(fitted.position.y, fitted.end.y):
		for x in range(fitted.position.x, fitted.end.x):
			_room_at[Vector2i(x, y)] = room
			sim.grid.set_flag(x, y, TileGrid.FLAG_ROOM, true)
	_lay_out(sim, room)
	changed.emit()
	return room


## Takes a room away. Furniture, materials and stored goods are left on the floor.
func remove(sim: Simulation, room: Room) -> void:
	if room.removed:
		return
	room.removed = true
	rooms.erase(room)
	for slot: RoomSlot in room.slots:
		_clear_slot(sim, slot)
	for y in range(room.rect.position.y, room.rect.end.y):
		for x in range(room.rect.position.x, room.rect.end.x):
			_room_at.erase(Vector2i(x, y))
			sim.grid.set_flag(x, y, TileGrid.FLAG_ROOM, false)
	changed.emit()


func rooms_in(rect: Rect2i) -> Array[Room]:
	var found: Array[Room] = []
	for room: Room in rooms:
		if room.rect.intersects(rect):
			found.append(room)
	return found


## Called when a slot's build site is finished.
func slot_built(sim: Simulation, slot: RoomSlot) -> void:
	slot.built = true
	slot.site = null
	if slot.def.kind == SlotDef.Kind.STATION:
		var station := Station.new()
		station.slot = slot
		@warning_ignore("integer_division")
		station.tile = slot.tile + Vector2i(slot.def.width / 2, 0)
		station.station_type = slot.def.station_type
		station.output = _output_pile_for(slot)
		slot.station = station
		stations.append(station)
	changed.emit()


## Stations take orders, ask for inputs and offer craft jobs.
func tick(sim: Simulation) -> void:
	for station: Station in stations:
		if station.recipe == null:
			var recipe: RecipeDef = sim.orders.take(station.station_type)
			if recipe == null:
				continue
			station.recipe = recipe
			station.request = sim.logistics.add(station.tile, sim.item_type(recipe.input), recipe.input_count, "the %s" % station.slot.room.def.display_name.to_lower())
		elif station.job == null and station.request.is_satisfied():
			var size: int = recipe_output_size(sim, station.recipe)
			if station.output == null or station.output.free_units() >= size:
				station.job = sim.board.add_craft(station)
				station.ready_tick = sim.tick_count


func recipe_output_size(sim: Simulation, recipe: RecipeDef) -> int:
	return sim.storage.size_of(sim.item_type(recipe.output))


## The station this dwarf treats as their post, or null.
func station_of(dwarf_id: int) -> Station:
	for station: Station in stations:
		if station.worker_id == dwarf_id:
			return station
	return null


## How many stations are currently working on this recipe.
func in_production(recipe: RecipeDef) -> int:
	var count: int = 0
	for station: Station in stations:
		if station.recipe == recipe:
			count += 1
	return count


## Nearest free seat the dwarf can walk to, or null.
func find_seat(flood_map: FloodMap) -> RoomSlot:
	var best: RoomSlot = null
	var best_dist: int = 0
	for room: Room in rooms:
		for slot: RoomSlot in room.slots:
			if not slot.def.seat or not slot.built or slot.occupant != -1:
				continue
			var dist: int = flood_map.distance_to(slot.tile.x, slot.tile.y)
			if dist >= 0 and (best == null or dist < best_dist):
				best = slot
				best_dist = dist
	return best


func _lay_out(sim: Simulation, room: Room) -> void:
	var def: RoomDef = room.def
	var pattern_width: int = maxi(def.pattern_width, 1)
	@warning_ignore("integer_division")
	var units: int = (room.rect.size.x - def.margin * 2) / pattern_width
	for unit in units:
		var base_x: int = room.rect.position.x + def.margin + unit * pattern_width
		for slot_def: SlotDef in def.slots:
			var slot := RoomSlot.new()
			slot.room = room
			slot.def = slot_def
			slot.unit = unit
			slot.tile = Vector2i(base_x + slot_def.offset, room.feet_row)
			room.slots.append(slot)
			match slot_def.kind:
				SlotDef.Kind.FURNITURE, SlotDef.Kind.STATION:
					var purpose: String = "the %s" % def.display_name.to_lower()
					slot.site = sim.add_site(slot.tile, sim.item_type(slot_def.item), slot_def.item_count, slot_def.work_ticks, purpose, slot)
				SlotDef.Kind.OUTPUT:
					slot.pile = sim.storage.add_pile(Pile.Kind.OUTPUT, slot.tile, sim.config.pile_capacity)
				SlotDef.Kind.PLANT:
					slot.plant = sim.plants.add(slot_def.plant, slot.tile, 0)


func _clear_slot(sim: Simulation, slot: RoomSlot) -> void:
	slot.occupant = -1
	if slot.site != null:
		sim.cancel_site(slot.site)
		slot.site = null
	elif slot.built and slot.def.item != null:
		# The furniture, or the materials the station was made of, drop to the floor.
		sim.spill(sim.item_type(slot.def.item), slot.def.item_count, slot.tile)
	if slot.station != null:
		var station: Station = slot.station
		station.removed = true
		stations.erase(station)
		if station.request != null:
			sim.spill(station.request.item_type, station.request.delivered, station.tile)
			sim.logistics.close(station.request)
		if station.job != null:
			sim.board.remove(station.job)
		slot.station = null
	if slot.pile != null:
		sim.storage.remove_pile(slot.pile)
		for type: int in slot.pile.counts:
			sim.spill(type, slot.pile.counts[type], slot.tile)
		slot.pile = null
	if slot.plant != null:
		sim.plants.remove(slot.plant, sim.board)
		slot.plant = null
	slot.built = false


func _output_pile_for(station_slot: RoomSlot) -> Pile:
	for slot: RoomSlot in station_slot.room.slots:
		if slot.unit == station_slot.unit and slot.def.kind == SlotDef.Kind.OUTPUT:
			return slot.pile
	return null


## An open tile with ground under it, underground.
static func _is_floor_spot(grid: TileGrid, x: int, y: int) -> bool:
	return _is_indoors(grid, x, y) and grid.is_solid(x, y + 1)


## Open and dug out of something, as opposed to open sky.
static func _is_indoors(grid: TileGrid, x: int, y: int) -> bool:
	return grid.is_open(x, y) and grid.material_at(x, y) != TileGrid.NO_MATERIAL
