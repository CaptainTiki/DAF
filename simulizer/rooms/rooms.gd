class_name Rooms
extends RefCounted
## All rooms, what stands in them, and their stations. A room lays out only
## what is part of the room itself (farm plots, a storeroom's floor); furniture
## and stations are placed by the player, one at a time. Each slot then asks
## for what it needs through a build site.

## Emitted when a room is placed or removed, or a slot gets built.
signal changed

## Rooms are never taller than this, however high the ceiling.
const MAX_HEIGHT: int = 8
## How often slots in planned rooms are checked for having been dug out, in ticks.
const ACTIVATE_INTERVAL: int = 20

var rooms: Array[Room] = []
var stations: Array[Station] = []

var _room_at: Dictionary[Vector2i, Room] = {}
## Placed furniture by every tile it covers and the lane it stands in (see
## _lane); an output pile maps to its station.
var _slot_at: Dictionary[Vector3i, RoomSlot] = {}
var _next_id: int = 1
## Built slots per need id they satisfy. Null when it has to be counted again.
var _provider_counts: Variant = null


func room_at(tile: Vector2i) -> Room:
	return _room_at.get(tile)


## The room a drag would make: the drag itself, at least min_height tall
## (grown upward), widened to take in any room of the same type it touches.
## Rock inside it is fine; it gets dug out. An empty rect means a room can't
## go there: open sky, nothing under its floor, or another room in the way.
func fit(grid: TileGrid, def: RoomDef, rect: Rect2i) -> Rect2i:
	var left: int = maxi(rect.position.x, 0)
	var right: int = mini(rect.end.x, grid.width) - 1
	if right < left:
		return Rect2i()
	var feet: int = rect.end.y - 1
	var height: int = clampi(rect.size.y, def.min_height, MAX_HEIGHT)
	var joined: Array[Room] = _rooms_to_join(def, feet, left, right)
	for room: Room in joined:
		left = mini(left, room.rect.position.x)
		right = maxi(right, room.rect.end.x - 1)
		height = maxi(height, room.rect.size.y)
	var top: int = feet - height + 1
	if top < 0 or not grid.in_bounds(left, feet):
		return Rect2i()
	for x in range(left, right + 1):
		if not grid.is_ground(x, feet + 1):
			return Rect2i()
		var existing: Room = _room_at.get(Vector2i(x, feet))
		if existing != null and not joined.has(existing):
			return Rect2i()
		if existing == null and grid.is_stockpile(x, feet):
			return Rect2i()
		for y in range(top, feet + 1):
			if grid.material_at(x, y) == TileGrid.NO_MATERIAL:
				return Rect2i()
	var width: int = right - left + 1
	if width < def.min_width:
		return Rect2i()
	return Rect2i(left, top, width, height)

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

	# Take over the rooms being joined. What the player placed in them stays;
	# what they laid out themselves is kept where the new layout agrees.
	var joined: Array[Room] = _rooms_to_join(def, room.feet_row, fitted.position.x, fitted.end.x - 1)
	var old_slots: Array[RoomSlot] = []
	var leftmost: Room = null
	for old: Room in joined:
		if leftmost == null or old.rect.position.x < leftmost.rect.position.x:
			# Keep the layout lined up with the leftmost old room, so its plots don't move.
			leftmost = old
			room.anchor_x = old.anchor_x
		for slot: RoomSlot in old.slots:
			if old.def.slots.has(slot.def):
				old_slots.append(slot)
			else:
				slot.room = room
				room.slots.append(slot)
		old.slots.clear()
		old.removed = true
		rooms.erase(old)
		_set_tiles(sim, old.rect, null)

	rooms.append(room)
	_set_tiles(sim, fitted, room)
	# Whatever is still rock inside the room gets dug out first. A quarry is
	# dug bit by bit instead, as stone is needed; see Simulation._tick_quarries.
	if not def.quarry:
		sim.plan_dig(fitted)
	_lay_out(sim, room, old_slots)
	# Whatever no longer has a place in the new layout drops to the floor.
	for slot: RoomSlot in old_slots:
		_clear_slot(sim, slot)
	_provider_counts = null
	changed.emit()
	return room


# --- Furniture ---

## Where a piece would stand if placed at this tile, or an empty rect if it
## can't go there. The tile is where its left end goes; the row says how high
## up the wall it sits. It needs a room of a type that takes it, every tile
## it covers (and its output pile's) inside that room and free, and rock is
## fine: it is dug out first.
func furniture_fit(def: SlotDef, tile: Vector2i) -> Rect2i:
	var room: Room = _room_at.get(tile)
	if room == null or not def.allowed_in(room.def.id):
		return Rect2i()
	var rise: int = room.feet_row - tile.y
	if rise < def.rise or rise > def.highest_rise():
		return Rect2i()
	var span: int = def.width + (1 if def.output else 0)
	var lane: int = _lane(def)
	for dx in span:
		var covered := Vector2i(tile.x + dx, tile.y)
		if _room_at.get(covered) != room or _slot_at.has(Vector3i(covered.x, covered.y, lane)):
			return Rect2i()
	return Rect2i(tile, Vector2i(span, 1))


## Places a piece of furniture or a station. Null if it doesn't fit there.
func place_furniture(sim: Simulation, def: SlotDef, tile: Vector2i) -> RoomSlot:
	var footprint: Rect2i = furniture_fit(def, tile)
	if footprint.size == Vector2i.ZERO:
		return null
	var room: Room = _room_at[tile]
	var slot: RoomSlot = _make_slot(sim, room, def, tile)
	if def.output:
		var output_def := SlotDef.new()
		output_def.kind = SlotDef.Kind.OUTPUT
		slot.output_slot = _make_slot(sim, room, output_def, tile + Vector2i(def.width, 0))
	_cover(slot)
	changed.emit()
	return slot


## The placed pieces covering this tile: at most one at the back (a seat, a
## bed, a shelf, a station) and one in front of it (a table).
func furniture_at(tile: Vector2i) -> Array[RoomSlot]:
	var found: Array[RoomSlot] = []
	for lane in 2:
		var slot: RoomSlot = _slot_at.get(Vector3i(tile.x, tile.y, lane))
		if slot != null:
			found.append(slot)
	return found


## A table stands in front of a chair, so the two can share a tile. Every
## other piece stands at the back of its tile.
static func _lane(def: SlotDef) -> int:
	var is_table: bool = def.kind == SlotDef.Kind.FURNITURE and not def.seat and not def.storage and def.satisfies == &""
	return 1 if is_table else 0


func _cover(slot: RoomSlot) -> void:
	var lane: int = _lane(slot.def)
	for dx in slot.def.width + (1 if slot.def.output else 0):
		_slot_at[Vector3i(slot.tile.x + dx, slot.tile.y, lane)] = slot


## Takes away the furniture in the rect. A plan is simply cancelled; what is
## built is marked, and a dwarf takes it apart into an item that is then
## hauled off to storage. Returns how many pieces were affected.
func remove_furniture(sim: Simulation, rect: Rect2i) -> int:
	var found: Array[RoomSlot] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			for slot: RoomSlot in furniture_at(Vector2i(x, y)):
				if not found.has(slot):
					found.append(slot)
	var changed_count: int = 0
	for slot: RoomSlot in found:
		if not slot.built:
			_remove_slot(sim, slot)
			changed_count += 1
		elif slot.site == null:
			slot.site = sim.add_site(slot.tile, Simulation.NO_ITEM, 0, sim.config.remove_ticks, "", slot)
			slot.site.removing = true
			changed_count += 1
	if changed_count > 0:
		changed.emit()
	return changed_count


## Called when the site that takes a built piece apart is finished.
func slot_removed(sim: Simulation, slot: RoomSlot) -> void:
	slot.site = null
	_remove_slot(sim, slot)
	changed.emit()


func _make_slot(sim: Simulation, room: Room, def: SlotDef, tile: Vector2i) -> RoomSlot:
	var slot := RoomSlot.new()
	slot.room = room
	slot.def = def
	slot.tile = tile
	room.slots.append(slot)
	match def.kind:
		SlotDef.Kind.FURNITURE, SlotDef.Kind.STATION:
			var purpose: String = "the %s" % room.def.display_name.to_lower()
			slot.site = sim.add_site(tile, sim.item_type(def.item), def.item_count, def.work_ticks, purpose, slot)
		SlotDef.Kind.OUTPUT:
			slot.pile = sim.storage.add_pile(Pile.Kind.OUTPUT, tile, sim.config.pile_capacity)
	return slot


## Takes a placed piece (and its output pile) out of its room for good.
func _remove_slot(sim: Simulation, slot: RoomSlot) -> void:
	for key: Vector3i in _slot_at.keys():
		if _slot_at[key] == slot:
			_slot_at.erase(key)
	_clear_slot(sim, slot)
	slot.room.slots.erase(slot)
	if slot.output_slot != null:
		_clear_slot(sim, slot.output_slot)
		slot.room.slots.erase(slot.output_slot)
		slot.output_slot = null
	_provider_counts = null

## Puts a room back from a save, slots as they were. Piles and plants are
## looked up by index in the lists SaveGame has already restored.
func restore_room(sim: Simulation, data: Dictionary, piles: Array[Pile], plants: Array[Plant]) -> Room:
	var room := Room.new()
	room.id = data["id"]
	_next_id = maxi(_next_id, room.id + 1)
	room.def = _room_def(sim, data["def"])
	room.rect = data["rect"]
	room.feet_row = data["feet_row"]
	room.anchor_x = data["anchor_x"]
	rooms.append(room)
	_set_tiles(sim, room.rect, room)
	for slot_data: Dictionary in data["slots"]:
		var slot := RoomSlot.new()
		slot.room = room
		if slot_data["placed"]:
			slot.def = _furniture_def(sim, slot_data["def"])
		else:
			slot.def = room.def.slots[slot_data["def"]]
		slot.tile = slot_data["tile"]
		slot.unit = slot_data["unit"]
		slot.built = slot_data["built"]
		slot.owner = slot_data["owner"]
		if slot_data["pile"] >= 0:
			slot.pile = piles[slot_data["pile"]]
		if slot_data["plant"] >= 0:
			slot.plant = plants[slot_data["plant"]]
		if slot_data.has("site"):
			slot.site = sim.restore_site(slot_data["site"], slot)
		room.slots.append(slot)
		if slot_data.has("station"):
			var station_data: Dictionary = slot_data["station"]
			var station := Station.new()
			station.slot = slot
			station.tile = station_data["tile"]
			station.station_type = slot.def.station_type
			station.worker_id = station_data["worker_id"]
			if station_data["recipe"] >= 0:
				station.recipe = sim.config.recipes[station_data["recipe"]]
				var request: Dictionary = station_data["request"]
				station.request = sim.logistics.add(station.tile, request["type"], request["wanted"], request["purpose"])
				station.request.delivered = request["delivered"]
			slot.station = station
			stations.append(station)
	var slot_index: int = 0
	for slot_data: Dictionary in data["slots"]:
		var slot: RoomSlot = room.slots[slot_index]
		slot_index += 1
		if slot_data["output_slot"] >= 0:
			slot.output_slot = room.slots[slot_data["output_slot"]]
		if slot_data["placed"] and slot.def.kind != SlotDef.Kind.OUTPUT:
			_cover(slot)
		if slot.station != null:
			slot.station.output = _output_pile_for(slot)
	_provider_counts = null
	changed.emit()
	return room


## A placed piece's definition, by id; an output pile has none and gets a
## plain OUTPUT def.
func _furniture_def(sim: Simulation, id: StringName) -> SlotDef:
	for def: SlotDef in sim.config.furniture:
		if def.id == id:
			return def
	var output_def := SlotDef.new()
	output_def.kind = SlotDef.Kind.OUTPUT
	return output_def


func _room_def(sim: Simulation, id: StringName) -> RoomDef:
	for def: RoomDef in sim.config.rooms:
		if def.id == id:
			return def
	push_error("Unknown room type in save: %s" % id)
	return sim.config.rooms[0]


## Takes a room away. Furniture, materials and stored goods are left on the floor.
func remove(sim: Simulation, room: Room) -> void:
	if room.removed:
		return
	room.removed = true
	rooms.erase(room)
	for slot: RoomSlot in room.slots:
		_clear_slot(sim, slot)
	for key: Vector3i in _slot_at.keys():
		if _slot_at[key].room == room:
			_slot_at.erase(key)
	_set_tiles(sim, room.rect, null)
	sim.mark_dig(room.rect, false)
	_provider_counts = null
	changed.emit()


func rooms_in(rect: Rect2i) -> Array[Room]:
	var found: Array[Room] = []
	for room: Room in rooms:
		if room.rect.intersects(rect):
			found.append(room)
	return found


## A slot's tile is ready to be used once it is dug out, with something under
## it if it is on the floor.
func is_slot_ready(grid: TileGrid, slot: RoomSlot) -> bool:
	if not grid.is_open(slot.tile.x, slot.tile.y):
		return false
	var on_the_wall: bool = slot.tile.y < slot.room.feet_row
	return on_the_wall or grid.is_ground(slot.tile.x, slot.tile.y + 1)


## Plants and stockpile spots come into being once their tile is dug out.
func _activate_slots(sim: Simulation) -> void:
	for room: Room in rooms:
		for slot: RoomSlot in room.slots:
			if slot.built or slot.site != null or not is_slot_ready(sim.grid, slot):
				continue
			match slot.def.kind:
				SlotDef.Kind.PLANT:
					slot.plant = sim.plants.add(slot.def.plant, slot.tile, 0, sim.roll_growth_speed(slot.def.plant))
					slot.built = true
				SlotDef.Kind.STOCKPILE:
					sim.add_stockpile_tile(slot.tile)
					slot.built = true
				SlotDef.Kind.OUTPUT:
					slot.built = true


## Called when a slot's build site is finished.
func slot_built(sim: Simulation, slot: RoomSlot) -> void:
	slot.built = true
	slot.site = null
	if slot.def.storage:
		sim.add_stockpile_tile(slot.tile)
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


## Called when a site is finished, whichever way it went.
func site_finished(sim: Simulation, site: BuildSite) -> void:
	if site.removing:
		slot_removed(sim, site.slot)
	else:
		slot_built(sim, site.slot)


## Stations take orders, ask for inputs and offer craft jobs. Slots that need
## their tile dug out first wake up once it is.
func tick(sim: Simulation) -> void:
	if sim.tick_count % ACTIVATE_INTERVAL == 0:
		_activate_slots(sim)
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


## Whether a built station exists that can make this item type.
func can_make(sim: Simulation, type: int) -> bool:
	for recipe: RecipeDef in sim.config.recipes:
		if sim.item_type(recipe.output) != type:
			continue
		for station: Station in stations:
			if station.station_type == recipe.station_type:
				return true
	return false


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


## Somewhere this dwarf can satisfy a need. With `owned`, their own (a bed they
## have used before) if it is free and in reach, otherwise the nearest one
## nobody owns. Without, simply the nearest free one.
func find_provider(provider: StringName, dwarf_id: int, flood_map: FloodMap, owned: bool) -> RoomSlot:
	var best: RoomSlot = null
	var best_dist: int = 0
	for room: Room in rooms:
		for slot: RoomSlot in room.slots:
			if slot.def.satisfies != provider or not slot.built or slot.occupant != -1:
				continue
			if owned and slot.owner != -1 and slot.owner != dwarf_id:
				continue
			var dist: int = flood_map.distance_to(slot.tile.x, slot.tile.y)
			if dist < 0:
				continue
			if owned and slot.owner == dwarf_id:
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
			var tile := Vector2i(base_x + slot_def.offset, room.feet_row - slot_def.rise)
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
				# Plants and stockpile spots wait for their tile to be dug out; see _activate_slots.
		base_x += pattern_width
		unit += 1
	for slot: RoomSlot in room.slots:
		if slot.def.kind == SlotDef.Kind.STATION and slot.output_slot == null:
			for other: RoomSlot in room.slots:
				if other.unit == slot.unit and other.def.kind == SlotDef.Kind.OUTPUT and def.slots.has(other.def):
					slot.output_slot = other
		if slot.station != null:
			slot.station.output = _output_pile_for(slot)


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
	if slot.built and (slot.def.storage or slot.def.kind == SlotDef.Kind.STOCKPILE):
		sim.remove_stockpile_tile(slot.tile)
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
	if station_slot.output_slot == null:
		return null
	return station_slot.output_slot.pile


## An open tile with ground under it, underground.
static func _is_floor_spot(grid: TileGrid, x: int, y: int) -> bool:
	return _is_indoors(grid, x, y) and grid.is_solid(x, y + 1)


## Open and dug out of something, as opposed to open sky.
static func _is_indoors(grid: TileGrid, x: int, y: int) -> bool:
	return grid.is_open(x, y) and grid.material_at(x, y) != TileGrid.NO_MATERIAL
