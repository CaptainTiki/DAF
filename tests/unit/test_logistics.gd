extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(12, 6))


## A supply pile of one item type on a tile.
func _supply(type: int, count: int, tile: Vector2i) -> Pile:
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, tile, Pile.UNLIMITED)
	for i in count:
		_sim.storage.put(pile, type)
	return pile


func test_request_is_filled_from_a_pile() -> void:
	var pile := _supply(SimFactory.WOOD, 5, Vector2i(9, 6))
	var request: Request = _sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 2, "a test")
	SimFactory.run(_sim, 200)
	assert_true(request.is_satisfied())
	assert_eq(request.delivered, 2)
	assert_eq(request.incoming, 0)
	assert_eq(pile.count_of(SimFactory.WOOD), 3)
	assert_eq(_sim.items.size(), 0, "delivered items are used up")
	assert_null(_dwarf.carrying)


func test_request_is_filled_from_loose_items() -> void:
	_sim.spawn_item(SimFactory.WOOD, Vector2i(9, 6))
	var request: Request = _sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 1, "a test")
	SimFactory.run(_sim, 200)
	assert_true(request.is_satisfied())
	assert_eq(_sim.items.size(), 0)


func test_requests_come_before_the_stockpile() -> void:
	_sim.mark_stockpile(Rect2i(10, 6, 1, 1), true)
	_sim.spawn_item(SimFactory.WOOD, Vector2i(9, 6))
	var request: Request = _sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 1, "a test")
	SimFactory.run(_sim, 200)
	assert_true(request.is_satisfied())
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0, "it went to the request, not into storage")


func test_no_more_haulers_than_the_request_needs() -> void:
	_sim.hire_dwarf()
	_sim.hire_dwarf()
	var pile := _supply(SimFactory.WOOD, 5, Vector2i(9, 6))
	var request: Request = _sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 1, "a test")
	SimFactory.run(_sim, 200)
	assert_eq(request.delivered, 1)
	assert_eq(pile.count_of(SimFactory.WOOD), 4, "only one was taken")
	assert_eq(_sim.items.size(), 0)


func test_closed_request_makes_the_hauler_drop_the_item() -> void:
	_supply(SimFactory.WOOD, 1, Vector2i(9, 6))
	var request: Request = _sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 1, "a test")
	for i in 200:
		_sim.tick()
		if _dwarf.carrying != null:
			break
	assert_not_null(_dwarf.carrying)
	_sim.logistics.close(request)
	SimFactory.run(_sim, 100)
	assert_null(_dwarf.carrying)
	assert_eq(_sim.items.size(), 1, "the wood is on the floor again")
	assert_eq(request.delivered, 0)


func test_missing_item_is_reported_once() -> void:
	_sim.logistics.add(Vector2i(14, 6), SimFactory.WOOD, 1, "the stairs")
	SimFactory.run(_sim, 300)
	assert_eq(_sim.requests.entries.size(), 1)
	assert_string_contains(_sim.requests.entries[0].message, "no wood for the stairs")


func test_item_being_made_is_not_reported_missing() -> void:
	_sim.logistics.add(Vector2i(14, 6), SimFactory.CHAIR, 1, "the hall")
	SimFactory.run(_sim, 300)
	assert_eq(_sim.requests.entries.size(), 0, "chairs come from a bench; nothing to complain about")


func test_supply_pile_is_cleared_into_the_stockpile() -> void:
	var pile := _supply(SimFactory.WOOD, 3, Vector2i(9, 6))
	_sim.mark_stockpile(Rect2i(13, 6, 2, 1), true)
	SimFactory.run(_sim, 600)
	assert_eq(pile.count_of(SimFactory.WOOD), 0)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 3)
	assert_eq(_sim.items.size(), 0)


func test_stairs_wait_for_their_wood() -> void:
	var config := SimFactory.make_config()
	config.structure_item = config.items[SimFactory.WOOD]
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	var flight: Array[Vector2i] = [Vector2i(13, 7), Vector2i(14, 8)]
	_sim.mark_stairs(flight, true)
	SimFactory.run(_sim, 300)
	assert_false(_sim.grid.has_stair(13, 7), "no wood, no stairs")
	assert_eq(_dwarf.pos, Vector2i(10, 6), "and nobody tries")

	_supply(SimFactory.WOOD, 2, Vector2i(9, 6))
	SimFactory.run(_sim, 600)
	assert_true(_sim.grid.has_stair(13, 7))
	assert_true(_sim.grid.has_stair(14, 8))
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0, "one wood per stair tile")
	assert_eq(_sim.sites.size(), 0)
	assert_eq(_sim.logistics.requests.size(), 0)


func test_cancelled_stairs_give_their_wood_back() -> void:
	var config := SimFactory.make_config()
	config.structure_item = config.items[SimFactory.WOOD]
	config.stair_build_ticks = 5000
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	_supply(SimFactory.WOOD, 1, Vector2i(9, 6))
	var flight: Array[Vector2i] = [Vector2i(13, 7)]
	_sim.mark_stairs(flight, true)
	SimFactory.run(_sim, 200)
	assert_eq(_sim.items.size(), 0, "wood delivered to the site")
	_sim.mark_stairs(flight, false)
	assert_eq(_sim.items.size(), 1, "and spilled when the plan is cancelled")
	assert_false(_sim.grid.is_build_marked(13, 7))


# --- Staffing ---

func test_lone_dwarf_alternates_between_digging_and_hauling() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 3, 1), true)
	_sim.mark_dig(Rect2i(15, 4, 3, 3), true)
	var kinds: Array[int] = []
	for i in 2500:
		_sim.tick()
		if _dwarf.job != null and (kinds.is_empty() or kinds[kinds.size() - 1] != _dwarf.job.kind):
			kinds.append(_dwarf.job.kind)
	var switches_to_haul: int = kinds.count(Job.Kind.HAUL)
	assert_gt(switches_to_haul, 3, "hauling is interleaved with digging, not left to the end")
	assert_eq(_sim.storage.totals[SimFactory.DIRT_BALL], 9)


func test_crew_keeps_digging_while_one_hauls() -> void:
	_sim.hire_dwarf()
	_sim.hire_dwarf()
	_sim.mark_stockpile(Rect2i(9, 6, 3, 1), true)
	_sim.mark_dig(Rect2i(15, 4, 8, 3), true)
	var ticks_with_work: int = 0
	var ticks_all_hauling: int = 0
	for i in 600:
		_sim.tick()
		if _sim.board.unclaimed_of(Job.Kind.DIG) == 0:
			# Digging is finished or fully taken; hauling is all that's left.
			continue
		var digging: int = 0
		var hauling: int = 0
		for dwarf: Dwarf in _sim.dwarves:
			if dwarf.job != null and dwarf.job.kind == Job.Kind.DIG:
				digging += 1
			elif dwarf.job != null and dwarf.job.kind == Job.Kind.HAUL:
				hauling += 1
		if digging + hauling == 3:
			ticks_with_work += 1
			if hauling == 3:
				ticks_all_hauling += 1
	assert_gt(ticks_with_work, 20)
	assert_eq(ticks_all_hauling, 0, "the whole crew never drops digging to haul")

# --- Waste ---

## A world where dirt is waste, with a way up from the room to the surface.
## Surface feet row is 2; the spoil heap is 7 tiles left of the room's middle, at (5, 2).
func _start_with_waste() -> void:
	var config := SimFactory.make_config()
	config.items[SimFactory.DIRT_BALL].dump = true
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(12, 6))
	for tile: Vector2i in [Vector2i(9, 5), Vector2i(8, 4), Vector2i(7, 3)]:
		_sim.grid.add_structure(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)


func test_waste_is_carried_to_the_spoil_heap_and_is_gone() -> void:
	_start_with_waste()
	assert_not_null(_sim.dump_pile)
	assert_eq(_sim.dump_pile.tile, Vector2i(5, 2))
	_sim.mark_stockpile(Rect2i(13, 6, 2, 1), true)
	for i in 3:
		_sim.spawn_item(SimFactory.DIRT_BALL, Vector2i(14, 6))
	SimFactory.run(_sim, 1500)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.dumped, 3)
	assert_eq(_sim.storage.totals[SimFactory.DIRT_BALL], 0, "never stored, even with a stockpile free")
	assert_eq(_sim.dump_pile.units_used, 0)
	assert_eq(_sim.requests.entries.size(), 0)


func test_waste_waits_quietly_when_there_is_no_way_to_the_heap() -> void:
	var config := SimFactory.make_config()
	config.items[SimFactory.DIRT_BALL].dump = true
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(12, 6))
	_sim.spawn_item(SimFactory.DIRT_BALL, Vector2i(14, 6))
	_sim.spawn_item(SimFactory.STONE_BALL, Vector2i(14, 6))
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), true)
	SimFactory.run(_sim, 600)
	assert_eq(_sim.dumped, 0)
	assert_eq(_sim.items.size(), 1, "the dirt stays where it fell")
	assert_eq(_sim.storage.totals[SimFactory.STONE_BALL], 1, "other things are still stored")
	for entry: RequestEntry in _sim.requests.entries:
		assert_false(entry.message.contains("dirt"), "and nobody complains about dirt")


func test_stairs_and_floors_can_be_built_from_stone() -> void:
	var config := SimFactory.make_config()
	config.structure_item = config.items[SimFactory.WOOD]
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	var stone: ItemDef = config.items[SimFactory.STONE_BALL]
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, Vector2i(9, 6), Pile.UNLIMITED)
	_sim.storage.put(pile, SimFactory.STONE_BALL)
	_sim.storage.put(pile, SimFactory.WOOD)
	var stone_stair: Array[Vector2i] = [Vector2i(13, 7)]
	var wood_stair: Array[Vector2i] = [Vector2i(11, 7)]
	_sim.mark_stairs(stone_stair, true, stone)
	_sim.mark_stairs(wood_stair, true)
	SimFactory.run(_sim, 800)
	assert_true(_sim.grid.has_stair(13, 7))
	assert_true(_sim.grid.has_stair(11, 7))
	assert_eq(_sim.structure_item_type(Vector2i(13, 7), TileGrid.STRUCTURE_STAIR), SimFactory.STONE_BALL)
	assert_eq(_sim.structure_item_type(Vector2i(11, 7), TileGrid.STRUCTURE_STAIR), SimFactory.WOOD)
	assert_eq(_sim.storage.totals[SimFactory.STONE_BALL], 0)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0)

	# Taking the stone stair down gives stone back, not wood.
	_sim.mark_removal(Rect2i(13, 7, 1, 1), true)
	SimFactory.run(_sim, 600)
	assert_false(_sim.grid.has_stair(13, 7))
	var stone_back: int = _sim.storage.totals[SimFactory.STONE_BALL] + _sim.loose_unassigned_count(SimFactory.STONE_BALL)
	assert_eq(stone_back, 1)
