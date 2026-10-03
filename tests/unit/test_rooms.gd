extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world, widened: the first layer is carved open from x 1 to x 22,
# rows 4..6, floor row 7. Feet row is 6.
var _sim: Simulation
var _carpentry: RoomDef
var _hall: RoomDef


func before_each() -> void:
	_sim = SimFactory.make_sim()
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	_carpentry = _sim.config.rooms[0]
	_hall = _sim.config.rooms[1]


func _supply(type: int, count: int, tile: Vector2i) -> Pile:
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, tile, Pile.UNLIMITED)
	for i in count:
		_sim.storage.put(pile, type)
	return pile


func _slots_of(room: Room, item_type: int) -> Array[RoomSlot]:
	var found: Array[RoomSlot] = []
	for slot: RoomSlot in room.slots:
		if slot.def.kind == SlotDef.Kind.FURNITURE and _sim.item_type(slot.def.item) == item_type:
			found.append(slot)
	return found


func _built_count(room: Room) -> int:
	var count: int = 0
	for slot: RoomSlot in room.slots:
		if slot.built:
			count += 1
	return count


# --- Placing ---

func test_room_grows_up_to_its_minimum_height_from_the_dragged_row() -> void:
	# Dragged over just the floor row; the room takes the space above it.
	var room: Room = _sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	assert_not_null(room)
	assert_eq(room.rect, Rect2i(8, 4, 5, 3))
	assert_eq(room.feet_row, 6)
	assert_true(_sim.grid.has_flag(8, 4, TileGrid.FLAG_ROOM))
	assert_eq(_sim.rooms.room_at(Vector2i(10, 5)), room)


func test_room_needs_its_minimum_width() -> void:
	assert_false(_sim.can_place_room(_hall, Rect2i(8, 6, 2, 1)), "hall needs 3")
	assert_false(_sim.can_place_room(_carpentry, Rect2i(8, 6, 3, 1)), "carpentry needs 4")
	assert_true(_sim.can_place_room(_carpentry, Rect2i(8, 6, 4, 1)))


func test_room_cannot_go_in_the_sky_or_over_nothing() -> void:
	assert_false(_sim.can_place_room(_hall, Rect2i(8, 2, 5, 1)), "open sky")
	# A room whose floor row has open space under it has nothing to stand on.
	SimFactory.carve(_sim, Rect2i(8, 8, 5, 3))
	assert_false(_sim.can_place_room(_hall, Rect2i(8, 7, 5, 1)), "the row below is open")
	assert_true(_sim.can_place_room(_hall, Rect2i(8, 10, 5, 1)), "down on the real floor is fine")


# --- Planning in rock ---

func test_room_planned_in_rock_marks_its_digging() -> void:
	var room: Room = _sim.place_room(_hall, Rect2i(8, 12, 5, 2))
	assert_not_null(room)
	assert_eq(room.rect, Rect2i(8, 11, 5, 3), "grown upward to 3 high")
	for y in range(11, 14):
		for x in range(8, 13):
			assert_true(_sim.grid.is_dig_marked(x, y), "tile %d,%d marked" % [x, y])
	assert_eq(_sim.board.unclaimed_of(Job.Kind.DIG), 15)
	assert_true(_sim.grid.is_solid(10, 14), "the floor under it stays")


func test_dig_tool_leaves_rooms_alone() -> void:
	_sim.place_room(_hall, Rect2i(8, 12, 5, 2))
	_sim.mark_dig(Rect2i(8, 11, 5, 3), false)
	assert_true(_sim.grid.is_dig_marked(10, 12), "the room's own digging can't be unmarked with the dig tool")
	assert_eq(_sim.mark_dig(Rect2i(6, 11, 10, 3), true), 15, "only the 5 columns outside the room")
	assert_false(_sim.grid.is_dig_marked(7, 12) and _sim.rooms.room_at(Vector2i(7, 12)) != null)


func test_furniture_waits_until_the_room_is_dug_out() -> void:
	var room: Room = _sim.place_room(_hall, Rect2i(8, 12, 5, 2))
	var chair: RoomSlot = _slots_of(room, SimFactory.CHAIR)[0]
	# Deliver the chair while its tile is still rock: it must not be set up in there.
	chair.site.request.delivered = 1
	SimFactory.run(_sim, 30)
	assert_false(chair.built)
	SimFactory.carve(_sim, room.rect)
	SimFactory.run(_sim, 30)
	assert_true(chair.built, "set up once the tile is open")


func test_removing_a_planned_room_cancels_its_digging() -> void:
	var room: Room = _sim.place_room(_hall, Rect2i(8, 12, 5, 2))
	_sim.remove_rooms(room.rect)
	assert_eq(_sim.board.unclaimed_of(Job.Kind.DIG), 0)
	assert_false(_sim.grid.is_dig_marked(10, 12))


func test_dwarves_dig_out_a_planned_room_and_furnish_it() -> void:
	# A hall planned in the rock beside the carved strip, with wood and a bench to hand.
	# The test world is widened so there is rock to the right of the strip.
	var config := SimFactory.make_config()
	config.world_gen.width = 40
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	for i in 2:
		SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(10 + i, 6))
	_supply(SimFactory.WOOD, 11, Vector2i(7, 6))
	_sim.place_room(_sim.config.rooms[SimFactory.CARPENTRY], Rect2i(1, 6, 4, 1))
	var hall: Room = _sim.place_room(_sim.config.rooms[SimFactory.HALL], Rect2i(23, 6, 5, 1))
	assert_not_null(hall)
	assert_true(_sim.grid.is_solid(24, 5), "in rock to start with")
	SimFactory.run(_sim, 8000)
	for y in range(4, 7):
		for x in range(23, 28):
			assert_true(_sim.grid.is_open(x, y), "tile %d,%d dug" % [x, y])
	assert_eq(_built_count(hall), 6)


func test_planned_room_with_no_way_in_waits_until_a_tunnel_is_marked() -> void:
	# A hall planned in rock two columns clear of the carved strip. Nobody can
	# reach it, so nothing happens until the dig tool marks the gap.
	var config := SimFactory.make_config()
	config.world_gen.width = 40
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(10, 6))
	var hall: Room = _sim.place_room(_sim.config.rooms[SimFactory.HALL], Rect2i(25, 6, 5, 1))
	assert_not_null(hall)
	SimFactory.run(_sim, 1500)
	for y in range(4, 7):
		for x in range(25, 30):
			assert_true(_sim.grid.is_solid(x, y), "tile %d,%d untouched" % [x, y])

	# Mark the two tiles of rock between: now it is reachable and gets dug.
	_sim.mark_dig(Rect2i(23, 4, 2, 3), true)
	SimFactory.run(_sim, 5000)
	for y in range(4, 7):
		for x in range(25, 30):
			assert_true(_sim.grid.is_open(x, y), "tile %d,%d dug" % [x, y])


# --- Storerooms ---

func test_storeroom_floor_is_storage_at_once_and_shelves_once_built() -> void:
	var storeroom: RoomDef = _sim.config.rooms[SimFactory.STOREROOM]
	var room: Room = _sim.place_room(storeroom, Rect2i(8, 6, 3, 1))
	assert_eq(room.slots.size(), 9, "a floor spot and two shelves per tile")
	SimFactory.run(_sim, 25)
	assert_eq(_sim.storage.tile_count(), 3, "the floor spots")
	assert_true(_sim.grid.is_stockpile(9, 6))
	assert_false(_sim.grid.is_stockpile(9, 5), "no shelf yet")
	for slot: RoomSlot in room.slots:
		if slot.def.rise == 1 and slot.tile.x == 9:
			_sim.complete_site(slot.site)
	assert_true(_sim.grid.is_stockpile(9, 5), "the shelf is storage")
	assert_eq(_sim.storage.tile_count(), 4)
	assert_eq(_sim.logistics.open_count_of(SimFactory.SHELF), 5, "the other shelves are still asked for")


func test_goods_are_stored_on_shelves() -> void:
	var dwarf := _sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(12, 6))
	var room: Room = _sim.place_room(_sim.config.rooms[SimFactory.STOREROOM], Rect2i(8, 6, 1, 1))
	# Width 1 is below the minimum; use 2.
	assert_null(room)
	room = _sim.place_room(_sim.config.rooms[SimFactory.STOREROOM], Rect2i(8, 6, 2, 1))
	for slot: RoomSlot in room.slots:
		if slot.site != null:
			_sim.complete_site(slot.site)
	SimFactory.run(_sim, 25)
	assert_eq(_sim.storage.tile_count(), 6)
	for i in 25:
		_sim.spawn_item(SimFactory.STONE_BALL, Vector2i(14, 6))
	SimFactory.run(_sim, 4000)
	assert_eq(_sim.storage.totals[SimFactory.STONE_BALL], 25)
	var on_shelves: int = 0
	for pile: Pile in _sim.storage.piles:
		if pile.kind == Pile.Kind.STOCKPILE and pile.tile.y < 6:
			on_shelves += pile.count_of(SimFactory.STONE_BALL)
	assert_gt(on_shelves, 0, "some went up on the shelves")


func test_removing_a_storeroom_spills_the_shelves() -> void:
	var room: Room = _sim.place_room(_sim.config.rooms[SimFactory.STOREROOM], Rect2i(8, 6, 2, 1))
	for slot: RoomSlot in room.slots:
		if slot.site != null:
			_sim.complete_site(slot.site)
	SimFactory.run(_sim, 25)
	_sim.remove_rooms(room.rect)
	assert_eq(_sim.storage.tile_count(), 0)
	assert_false(_sim.grid.is_stockpile(8, 5))
	assert_eq(_sim.items.size(), 4, "four shelves on the floor")
	_sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	assert_false(_sim.can_place_room(_carpentry, Rect2i(11, 6, 5, 1)), "overlaps a room of another type")
	assert_true(_sim.can_place_room(_carpentry, Rect2i(13, 6, 5, 1)), "next to it is fine")


# --- Joining rooms of the same type ---

func test_touching_halls_become_one_hall() -> void:
	_sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	var joined: Room = _sim.place_room(_hall, Rect2i(13, 6, 5, 1))
	assert_eq(_sim.rooms.rooms.size(), 1)
	assert_eq(joined.rect, Rect2i(8, 4, 10, 3))
	assert_eq(_slots_of(joined, SimFactory.CHAIR).size(), 8, "laid out as one 10-wide hall")
	assert_eq(_sim.logistics.open_count_of(SimFactory.CHAIR), 8)
	assert_eq(_sim.rooms.room_at(Vector2i(9, 5)), joined)
	assert_eq(_sim.rooms.room_at(Vector2i(16, 5)), joined)


func test_drawing_over_a_hall_extends_it() -> void:
	_sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	var joined: Room = _sim.place_room(_hall, Rect2i(10, 6, 8, 1))
	assert_eq(_sim.rooms.rooms.size(), 1)
	assert_eq(joined.rect, Rect2i(8, 4, 10, 3))


func test_halls_with_a_gap_between_stay_separate() -> void:
	_sim.place_room(_hall, Rect2i(3, 6, 4, 1))
	_sim.place_room(_hall, Rect2i(8, 6, 4, 1))
	assert_eq(_sim.rooms.rooms.size(), 2)


func test_a_new_hall_can_bridge_two_others() -> void:
	_sim.place_room(_hall, Rect2i(3, 6, 4, 1))
	_sim.place_room(_hall, Rect2i(10, 6, 4, 1))
	var joined: Room = _sim.place_room(_hall, Rect2i(7, 6, 3, 1))
	assert_eq(_sim.rooms.rooms.size(), 1)
	assert_eq(joined.rect, Rect2i(3, 4, 11, 3))


func test_furniture_stays_in_place_when_a_hall_is_extended() -> void:
	var hall: Room = _sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	var chair: RoomSlot = _slots_of(hall, SimFactory.CHAIR)[1]
	_sim.complete_site(chair.site)
	var joined: Room = _sim.place_room(_hall, Rect2i(13, 6, 5, 1))
	assert_true(chair.built, "still standing")
	assert_eq(chair.room, joined)
	assert_true(joined.slots.has(chair))
	assert_eq(_sim.items.size(), 0, "nothing was dropped")
	assert_eq(_built_count(joined), 1)
	assert_eq(_sim.logistics.open_count_of(SimFactory.CHAIR), 7, "only the missing ones are asked for")
	assert_eq(_sim.sites.size(), 15, "7 chairs and 8 tables still to come")


func test_extending_a_hall_to_the_left_keeps_its_furniture() -> void:
	var hall: Room = _sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	var chair: RoomSlot = _slots_of(hall, SimFactory.CHAIR)[0]
	_sim.complete_site(chair.site)
	var joined: Room = _sim.place_room(_hall, Rect2i(3, 6, 5, 1))
	assert_eq(joined.rect, Rect2i(3, 4, 10, 3))
	assert_true(chair.built)
	assert_eq(chair.tile, Vector2i(9, 6))
	assert_eq(_slots_of(joined, SimFactory.CHAIR).size(), 8)


func test_extending_a_workshop_keeps_its_bench_and_adds_another() -> void:
	var workshop: Room = _sim.place_room(_carpentry, Rect2i(6, 6, 4, 1))
	_sim.complete_site(workshop.slots[0].site)
	var station: Station = _sim.rooms.stations[0]
	_sim.storage.put(station.output, SimFactory.CHAIR)
	# Extended to the left by a width that doesn't line up with the bench spacing.
	var joined: Room = _sim.place_room(_carpentry, Rect2i(1, 6, 5, 1))
	assert_eq(joined.rect, Rect2i(1, 4, 9, 3))
	assert_eq(_sim.rooms.stations.size(), 1)
	assert_eq(_sim.rooms.stations[0], station, "the same bench")
	assert_eq(station.tile, Vector2i(7, 6), "where it was")
	assert_eq(station.output.count_of(SimFactory.CHAIR), 1, "with its output pile")
	assert_eq(_sim.items.size(), 0)
	assert_eq(joined.slots.size(), 4, "and a second bench in the new space")
	assert_eq(joined.slots[0].tile, Vector2i(2, 6), "lined up with the first, leaving the odd tile at the end")


func test_rooms_and_stockpiles_keep_apart() -> void:
	_sim.mark_stockpile(Rect2i(3, 6, 2, 1), true)
	assert_false(_sim.can_place_room(_hall, Rect2i(2, 6, 5, 1)))
	_sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	assert_eq(_sim.mark_stockpile(Rect2i(8, 6, 5, 1), true), 0)


# --- Layout from size ---

func test_five_wide_hall_wants_three_chairs_and_three_tables() -> void:
	var room: Room = _sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	assert_eq(_slots_of(room, SimFactory.CHAIR).size(), 3)
	assert_eq(_slots_of(room, SimFactory.TABLE).size(), 3)
	var chairs := _slots_of(room, SimFactory.CHAIR)
	assert_eq(chairs[0].tile, Vector2i(9, 6), "one tile in from the end")
	assert_eq(chairs[2].tile, Vector2i(11, 6))


func test_ten_wide_hall_wants_eight_of_each() -> void:
	var room: Room = _sim.place_room(_hall, Rect2i(8, 6, 10, 1))
	assert_eq(_slots_of(room, SimFactory.CHAIR).size(), 8)
	assert_eq(_slots_of(room, SimFactory.TABLE).size(), 8)


func test_wider_workshop_gets_more_benches() -> void:
	var small: Room = _sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	var big: Room = _sim.place_room(_carpentry, Rect2i(6, 6, 9, 1))
	assert_eq(small.slots.size(), 2, "one bench and its output pile")
	assert_eq(big.slots.size(), 4, "two benches fit in 9; the odd tile is left over")


func test_each_empty_slot_asks_for_its_item() -> void:
	_sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	assert_eq(_sim.logistics.open_count_of(SimFactory.CHAIR), 3)
	assert_eq(_sim.logistics.open_count_of(SimFactory.TABLE), 3)


# --- Bench, orders, crafting ---

func test_bench_is_built_from_delivered_wood() -> void:
	var dwarf := _sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(10, 6))
	_supply(SimFactory.WOOD, 2, Vector2i(8, 6))
	var room: Room = _sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	assert_eq(_sim.rooms.stations.size(), 0)
	SimFactory.run(_sim, 600)
	assert_eq(_sim.rooms.stations.size(), 1)
	assert_true(room.slots[0].built)
	assert_eq(_sim.rooms.stations[0].tile, Vector2i(2, 6), "the worker stands at the middle of the bench")
	assert_eq(_sim.rooms.stations[0].output, room.slots[1].pile)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0)


func test_no_orders_without_demand() -> void:
	var dwarf := _sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(10, 6))
	_supply(SimFactory.WOOD, 6, Vector2i(8, 6))
	_sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	SimFactory.run(_sim, 1200)
	assert_eq(_sim.rooms.stations.size(), 1)
	assert_null(_sim.rooms.stations[0].recipe, "nothing is asking for furniture")
	assert_eq(_sim.storage.totals[SimFactory.CHAIR], 0)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 4, "only the bench used wood")


func test_hall_is_furnished_end_to_end() -> void:
	for i in 2:
		SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(10 + i, 6))
	# Bench 2 wood, 3 chairs at 1 wood, 3 tables at 2 wood.
	_supply(SimFactory.WOOD, 11, Vector2i(7, 6))
	_sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	var hall: Room = _sim.place_room(_hall, Rect2i(12, 6, 5, 1))
	SimFactory.run(_sim, 6000)
	assert_eq(_built_count(hall), 6, "three chairs and three tables in place")
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0, "exactly the wood needed was used")
	assert_eq(_sim.storage.totals[SimFactory.CHAIR], 0, "nothing extra was made")
	assert_eq(_sim.storage.totals[SimFactory.TABLE], 0)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.logistics.requests.size(), 0)
	assert_eq(_sim.sites.size(), 0)
	assert_null(_sim.rooms.stations[0].recipe)


func test_worker_keeps_the_bench_as_a_post() -> void:
	for i in 2:
		SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(10 + i, 6))
	_supply(SimFactory.WOOD, 11, Vector2i(7, 6))
	_sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	_sim.place_room(_hall, Rect2i(12, 6, 5, 1))
	var crafters: Dictionary[int, int] = {}
	for i in 6000:
		_sim.tick()
		for dwarf: Dwarf in _sim.dwarves:
			if dwarf.activity == Dwarf.Activity.WORK and dwarf.job != null and dwarf.job.kind == Job.Kind.CRAFT:
				crafters[dwarf.id] = crafters.get(dwarf.id, 0) + 1
	assert_eq(crafters.size(), 1, "one dwarf did all the crafting")


func test_full_output_pile_blocks_the_bench_until_cleared() -> void:
	# No hall yet, so nothing pulls chairs away. A request with no reachable
	# destination stands in for demand.
	var config := SimFactory.make_config()
	config.pile_capacity = 3
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	var dwarf := _sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(10, 6))
	_supply(SimFactory.WOOD, 5, Vector2i(8, 6))
	_sim.place_room(_sim.config.rooms[0], Rect2i(1, 6, 4, 1))
	_sim.logistics.add(Vector2i(20, 20), SimFactory.CHAIR, 3, "somewhere out of reach")
	SimFactory.run(_sim, 3000)
	var station: Station = _sim.rooms.stations[0]
	assert_eq(station.output.count_of(SimFactory.CHAIR), 1, "one chair fills the 3-unit pile")
	assert_true(station.is_blocked(), "the next chair's wood is in, but there is nowhere to put it")
	assert_null(station.job)


# --- Removing ---

func test_removing_a_hall_drops_its_furniture() -> void:
	var hall: Room = _sim.place_room(_hall, Rect2i(8, 6, 5, 1))
	_sim.complete_site(_slots_of(hall, SimFactory.CHAIR)[0].site)
	assert_eq(_built_count(hall), 1)
	assert_eq(_sim.remove_rooms(Rect2i(10, 5, 1, 1)), 1)
	assert_eq(_sim.rooms.rooms.size(), 0)
	assert_eq(_sim.sites.size(), 0)
	assert_eq(_sim.logistics.requests.size(), 0)
	assert_eq(_sim.items.size(), 1, "the chair is on the floor")
	assert_false(_sim.grid.has_flag(8, 4, TileGrid.FLAG_ROOM))
	assert_null(_sim.rooms.room_at(Vector2i(10, 5)))


func test_removing_a_workshop_drops_bench_wood_and_output() -> void:
	var room: Room = _sim.place_room(_carpentry, Rect2i(1, 6, 4, 1))
	_sim.complete_site(room.slots[0].site)
	_sim.storage.put(room.slots[1].pile, SimFactory.CHAIR)
	_sim.remove_rooms(Rect2i(1, 6, 1, 1))
	assert_eq(_sim.rooms.stations.size(), 0)
	assert_eq(_sim.storage.piles.size(), 0)
	assert_eq(_sim.items.size(), 3, "two wood from the bench and one chair")


# --- Sitting ---

func test_idle_dwarf_sits_on_a_free_chair_and_gets_up_for_work() -> void:
	var config := SimFactory.make_config()
	config.wander_chance = 1.0
	config.sit_chance = 1.0
	config.sit_ticks_min = 5000
	config.sit_ticks_max = 5000
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	var hall: Room = _sim.place_room(_sim.config.rooms[1], Rect2i(8, 6, 5, 1))
	var chair: RoomSlot = _slots_of(hall, SimFactory.CHAIR)[0]
	_sim.complete_site(chair.site)
	var dwarf := _sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(15, 6))
	SimFactory.run(_sim, 100)
	assert_eq(dwarf.activity, Dwarf.Activity.SIT)
	assert_eq(dwarf.pos, chair.tile)
	assert_eq(chair.occupant, dwarf.id)

	_sim.mark_dig(Rect2i(23, 6, 1, 1), true)
	SimFactory.run(_sim, 10)
	assert_ne(dwarf.activity, Dwarf.Activity.SIT, "work came up")
	assert_eq(chair.occupant, -1)
	SimFactory.run(_sim, 100)
	assert_true(_sim.grid.is_open(23, 6))


func test_two_dwarves_do_not_share_a_chair() -> void:
	var config := SimFactory.make_config()
	config.wander_chance = 1.0
	config.sit_chance = 1.0
	config.sit_ticks_min = 5000
	config.sit_ticks_max = 5000
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	var hall: Room = _sim.place_room(_sim.config.rooms[1], Rect2i(8, 6, 5, 1))
	_sim.complete_site(_slots_of(hall, SimFactory.CHAIR)[0].site)
	var first := _sim.hire_dwarf()
	var second := _sim.hire_dwarf()
	SimFactory.place_dwarf(first, Vector2i(15, 6))
	SimFactory.place_dwarf(second, Vector2i(16, 6))
	SimFactory.run(_sim, 200)
	var sitting: int = 0
	for dwarf: Dwarf in _sim.dwarves:
		if dwarf.activity == Dwarf.Activity.SIT:
			sitting += 1
	assert_eq(sitting, 1)
