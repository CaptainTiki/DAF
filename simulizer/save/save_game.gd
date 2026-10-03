class_name SaveGame
extends RefCounted
## Turns a Simulation into plain data and back. Only what lasts is saved: the
## world, what is in it, and what the dwarves have been told to do. Work in
## progress (claims, reservations, who is walking where, what is in hand) is
## not: on loading, every dwarf starts idle where they stood and picks the work
## up again from the board, and anything carried is dropped at their feet.

const VERSION: int = 1


static func write(sim: Simulation, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_var(to_data(sim))
	return true


## Null if there is no save there, or it can't be read.
static func read(config: SimConfig, path: String) -> Simulation:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = file.get_var()
	if data is not Dictionary or data.get("version", 0) != VERSION:
		push_error("Save at %s is from another version" % path)
		return null
	return from_data(config, data)


static func to_data(sim: Simulation) -> Dictionary:
	var grid: TileGrid = sim.grid
	var piles: Array[Pile] = sim.storage.piles
	var plants: Array[Plant] = sim.plants.plants
	var data: Dictionary = {
		"version": VERSION,
		"tick": sim.tick_count,
		"rng_seed": sim.rng.seed,
		"rng_state": sim.rng.state,
		"dumped": sim.dumped,
		"kind_served": sim.kind_served,
		"stock_targets": sim.stock_targets,
		"name_order": sim.name_order(),
		"next_item_id": sim.next_item_id(),
		"grid_width": grid.width,
		"grid_height": grid.height,
		"first_layer_row": grid.first_layer_row,
		"layer_height": grid.layer_height,
		"grid": grid.export_arrays(),
		"structure_items": sim.structure_items(),
		"scaffold_tiles": sim.scaffolds.own_tiles.keys(),
		"piles": [],
		"items": [],
		"plants": [],
		"sites": [],
		"rooms": [],
		"dwarves": [],
		"log": [],
	}
	for pile: Pile in piles:
		data["piles"].append({"kind": pile.kind, "tile": pile.tile, "capacity": pile.capacity, "only_type": pile.only_type, "counts": pile.counts})
	for item: Item in sim.items.values():
		var pos: Vector2i = item.pos
		if item.state == Item.State.CARRIED:
			pos = _carrier_pos(sim, item)
		data["items"].append({"type": item.type, "pos": pos})
	for plant: Plant in plants:
		data["plants"].append({"def": plant.def.id, "tile": plant.tile, "speed": plant.speed, "grow_ticks": plant.grow_ticks, "growth": plant.growth})
	for site: BuildSite in sim.structure_sites():
		data["sites"].append(_site_data(site))
	for room: Room in sim.rooms.rooms:
		var slots: Array = []
		for slot: RoomSlot in room.slots:
			var placed: bool = not room.def.slots.has(slot.def)
			var slot_data: Dictionary = {
				"placed": placed,
				"def": slot.def.id if placed else room.def.slots.find(slot.def),
				"output_slot": room.slots.find(slot.output_slot) if slot.output_slot != null else -1,
				"tile": slot.tile,
				"unit": slot.unit,
				"built": slot.built,
				"owner": slot.owner,
				"pile": piles.find(slot.pile) if slot.pile != null else -1,
				"plant": plants.find(slot.plant) if slot.plant != null else -1,
			}
			if slot.site != null:
				slot_data["site"] = _site_data(slot.site)
			if slot.station != null:
				var station: Station = slot.station
				var station_data: Dictionary = {"tile": station.tile, "worker_id": station.worker_id, "recipe": -1}
				if station.recipe != null:
					station_data["recipe"] = sim.config.recipes.find(station.recipe)
					station_data["request"] = _request_data(station.request)
				slot_data["station"] = station_data
			slots.append(slot_data)
		data["rooms"].append({"id": room.id, "def": room.def.id, "rect": room.rect, "feet_row": room.feet_row, "anchor_x": room.anchor_x, "slots": slots})
	for dwarf: Dwarf in sim.dwarves:
		data["dwarves"].append({
			"id": dwarf.id,
			"name": dwarf.display_name,
			"experience": dwarf.experience,
			"beard": dwarf.beard_length,
			"think_ticks": dwarf.think_ticks,
			"pace": dwarf.pace,
			"pos": dwarf.pos,
			"facing": dwarf.facing,
			"needs": dwarf.needs,
			"need_quality": dwarf.need_quality,
		})
	for entry: RequestEntry in sim.requests.entries:
		data["log"].append({"key": entry.key, "dwarf": entry.dwarf_name, "message": entry.message, "first": entry.first_tick, "last": entry.last_tick, "count": entry.count})
	return data


static func from_data(config: SimConfig, data: Dictionary) -> Simulation:
	var sim := Simulation.new(config, data["rng_seed"], false)
	sim.restore(data)
	var piles: Array[Pile] = []
	for pile_data: Dictionary in data["piles"]:
		piles.append(sim.restore_pile(pile_data))
	var plants: Array[Plant] = []
	var plant_defs: Dictionary[StringName, PlantDef] = _plant_defs(config)
	for plant_data: Dictionary in data["plants"]:
		var plant: Plant = sim.plants.add(plant_defs[plant_data["def"]], plant_data["tile"], 0, plant_data["speed"])
		plant.grow_ticks = plant_data["grow_ticks"]
		plant.growth = plant_data["growth"]
		plants.append(plant)
	for item_data: Dictionary in data["items"]:
		sim.restore_item(item_data)
	for site_data: Dictionary in data["sites"]:
		sim.restore_site(site_data, null)
	for room_data: Dictionary in data["rooms"]:
		sim.rooms.restore_room(sim, room_data, piles, plants)
	for tile: Vector2i in data["scaffold_tiles"]:
		sim.scaffolds.own_tiles[tile] = true
	sim.restore_dig_jobs()
	for dwarf_data: Dictionary in data["dwarves"]:
		sim.restore_dwarf(dwarf_data)
	for entry_data: Dictionary in data["log"]:
		var entry := RequestEntry.new()
		entry.key = entry_data["key"]
		entry.dwarf_name = entry_data["dwarf"]
		entry.message = entry_data["message"]
		entry.first_tick = entry_data["first"]
		entry.last_tick = entry_data["last"]
		entry.count = entry_data["count"]
		sim.requests.restore(entry)
	return sim


static func _site_data(site: BuildSite) -> Dictionary:
	var site_data: Dictionary = {"tile": site.tile, "work_ticks": site.work_ticks, "structure": site.structure, "removing": site.removing}
	if site.request != null:
		site_data["request"] = _request_data(site.request)
	return site_data


static func _request_data(request: Request) -> Dictionary:
	return {"type": request.item_type, "wanted": request.wanted, "delivered": request.delivered, "purpose": request.purpose}


## Where a carried item lands when the save forgets who was carrying it.
static func _carrier_pos(sim: Simulation, item: Item) -> Vector2i:
	for dwarf: Dwarf in sim.dwarves:
		if dwarf.carrying == item:
			return dwarf.pos
	return item.pos


## Every plant type the config can grow, by id: the surface tree and whatever
## room slots plant.
static func _plant_defs(config: SimConfig) -> Dictionary[StringName, PlantDef]:
	var defs: Dictionary[StringName, PlantDef] = {}
	if config.world_gen != null and config.world_gen.tree != null:
		defs[config.world_gen.tree.id] = config.world_gen.tree
	for room: RoomDef in config.rooms:
		for slot: SlotDef in room.slots:
			if slot.plant != null:
				defs[slot.plant.id] = slot.plant
	return defs
