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
## Built slots per need id they satisfy. Null when it has to be counted again.
var _provider_counts: Variant = null


func room_at(tile: Vector2i) -> Room:
	return _room_at.get(tile)


## The room a drag would make: the rect snapped to the floor it touches and
## the open space above it, widened to take in any room of the same type that
## it touches or overlaps. An empty rect means a room can't go there.
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
	var joined: Array[Room] = _rooms_to_join(def, feet, left, right)
	for room: Room in joined:
		left = mini(left, room.rect.position.x)
		right = maxi(right, room.rect.end.x - 1)
	var height: int = MAX_HEIGHT
	for x in range(left, right + 1):
		if not _is_floor_spot(grid, x, feet) or grid.is_stockpile(x, feet):
			return Rect2i()
		var existing: Room = _room_at.get(Vector2i(x, feet))
		if existing != null and not joined.has(existing):
			return Rect2i()
		var open: int = 0
		while open < height and _is_indoors(grid, x, feet - open):
			open += 1
		height = open
	var width: int = right - left + 1
	if width < def.min_width or height < def.min_height:
		return Rect2i()
	return Rect2i(left, feet - height + 1, width, height)


## Makes a room, or extends the rooms of the same type that the drag touches
## into one. What is already in place stays where it is.
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
	room.anchor_x = fitted.position.x + def.margin

	# Take over the rooms being joined: their slots are kept to be reused.
	var joined: Array[Room] = _rooms_to_join(def, room.feet_row, fitted.position.x, fitted.end.x - 1)
	var old_slots: Array[RoomSlot] = []
	var leftmost: Room = null
	for old: Room in joined:
		if leftmost == null or old.rect.position.x < leftmost.rect.position.x:
			# Keep the layout lined up with the leftmost old room, so its benches don't move.
			leftmost = old
			room.anchor_x = old.anchor_x
		old_slots.append_array(old.slots)
		old.slots.clear()
		old.removed = true
		rooms.erase(old)
		_set_tiles(sim, old.rect, null)

	rooms.append(room)
	_set_tiles(sim, fitted, room)
	_lay_out(sim, room, old_slots)
	# Whatever no longer has a place in the new layout drops to the floor.
	for slot: RoomSlot in old_slots:
		_clear_slot(sim, slot)
	for slot: RoomSlot in room.slots:
		if slot.station != null:
			slot.station.output = _output_pile_for(slot)
	_provider_counts = null
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
	_set_tiles(sim, room.rect, null)
	_provider_counts = null
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
	_provider_counts = null
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


## How many built slots can satisfy a need.
func provider_count(need_id: StringName) -> int:
	if _provider_counts == null:
		var counts: Dictionary[StringName, int] = {}
		for room: Room in rooms:
			for slot: RoomSlot in room.slots:
				if slot.built and slot.def.satisfies != &"":
					counts[slot.def.satisfies] = counts.get(slot.def.satisfies, 0) + 1
		_provider_counts = counts
	return _provider_counts.get(need_id, 0)


## Somewhere this dwarf can satisfy a need: their own (a bed they have used
## before) if it is free and in reach, otherwise the nearest one nobody owns.
func find_provider(need_id: StringName, dwarf_id: int, flood_map: FloodMap) -> RoomSlot:
	var best: RoomSlot = null
	var best_dist: int = 0
	for room: Room in rooms:
		for slot: RoomSlot in room.slots:
			if slot.def.satisfies != need_id or not slot.built or slot.occupant != -1:
				continue
			if slot.owner != -1 and slot.owner != dwarf_id:
				continue
			var dist: int = flood_map.distance_to(slot.tile.x, slot.tile.y)
			if dist < 0:
				continue
			if slot.owner == dwarf_id:
				return slot
			if best == null or dist < best_dist:
				best = slot
				best_dist = dist
	return best


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


## Fills the room with slots: the layout repeats every pattern_width tiles,
## lined up on the room's anchor and kept clear of the margins. A slot from
## `reusable` that sits where a new one would go is kept as it is, and taken
## out of that list.
func _lay_out(sim: Simulation, room: Room, reusable: Array[RoomSlot]) -> void:
	var def: RoomDef = room.def
	var pattern_width: int = maxi(def.pattern_width, 1)
	var first_x: int = room.rect.position.x + def.margin
	var last_x: int = room.rect.end.x - def.margin - pattern_width
	# Leftmost unit position on the anchor's grid that is still inside the room.
	var base_x: int = room.anchor_x + ceili(float(first_x - room.anchor_x) / pattern_width) * pattern_width
	var unit: int = 0
	while base_x <= last_x:
		for slot_def: SlotDef in def.slots:
			var tile := Vector2i(base_x + slot_def.offset, room.feet_row)
			var kept: RoomSlot = _take_matching(reusable, slot_def, tile)
			if kept != null:
				kept.room = room
				kept.unit = unit
				room.slots.append(kept)
				continue
			var slot := RoomSlot.new()
			slot.room = room
			slot.def = slot_def
			slot.unit = unit
			slot.tile = tile
			room.slots.append(slot)
			match slot_def.kind:
				SlotDef.Kind.FURNITURE, SlotDef.Kind.STATION:
					var purpose: String = "the %s" % def.display_name.to_lower()
					slot.site = sim.add_site(slot.tile, sim.item_type(slot_def.item), slot_def.item_count, slot_def.work_ticks, purpose, slot)
				SlotDef.Kind.OUTPUT:
					slot.pile = sim.storage.add_pile(Pile.Kind.OUTPUT, slot.tile, sim.config.pile_capacity)
				SlotDef.Kind.PLANT:
					slot.plant = sim.plants.add(slot_def.plant, slot.tile, 0, sim.roll_growth_speed(slot_def.plant))
		base_x += pattern_width
		unit += 1


func _take_matching(slots: Array[RoomSlot], def: SlotDef, tile: Vector2i) -> RoomSlot:
	for i in slots.size():
		if slots[i].def == def and slots[i].tile == tile:
			var slot: RoomSlot = slots[i]
			slots.remove_at(i)
			return slot
	return null


## Rooms of this type on this floor that touch or overlap the span of columns.
## Joining one can bring the span up against another, so it repeats until settled.
func _rooms_to_join(def: RoomDef, feet: int, left: int, right: int) -> Array[Room]:
	var joined: Array[Room] = []
	var grew: bool = true
	while grew:
		grew = false
		for room: Room in rooms:
			if room.def != def or room.feet_row != feet or joined.has(room):
				continue
			if room.rect.position.x > right + 1 or room.rect.end.x < left:
				continue
			joined.append(room)
			left = mini(left, room.rect.position.x)
			right = maxi(right, room.rect.end.x - 1)
			grew = true
	return joined


## Marks every tile of a rect as belonging to a room, or to none.
func _set_tiles(sim: Simulation, rect: Rect2i, room: Room) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if room == null:
				_room_at.erase(Vector2i(x, y))
			else:
				_room_at[Vector2i(x, y)] = room
			sim.grid.set_flag(x, y, TileGrid.FLAG_ROOM, room != null)


func _clear_slot(sim: Simulation, slot: RoomSlot) -> void:
	slot.occupant = -1
	slot.owner = -1
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
