extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
# Pallets hold 3 balls in the test config.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	_dwarf.pos = Vector2i(12, 6)
	_dwarf.from_pos = _dwarf.pos


func _drop_balls(count: int, material: int = SimFactory.DIRT) -> void:
	for i in count:
		_sim.spawn_item(material, Vector2i(14, 6))


func test_stockpile_marks_floor_spots_only() -> void:
	var changed: int = _sim.mark_stockpile(Rect2i(9, 4, 3, 3), true)
	assert_eq(changed, 3, "one spot per column, on the floor")
	assert_true(_sim.grid.is_stockpile(9, 6))
	assert_false(_sim.grid.is_stockpile(9, 5))
	assert_eq(_sim.storage.tile_count(), 3)


func test_dragging_over_the_ground_marks_the_spot_above() -> void:
	_sim.mark_stockpile(Rect2i(9, 7, 2, 1), true)
	assert_true(_sim.grid.is_stockpile(9, 6))
	assert_true(_sim.grid.is_stockpile(10, 6))
	assert_false(_sim.grid.is_stockpile(9, 7))


func test_ball_is_hauled_to_a_new_pallet() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 2, 1), true)
	_drop_balls(1)
	SimFactory.run(_sim, 100)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.storage.pallets.size(), 1)
	var pallet: Pallet = _sim.storage.pallets.values()[0]
	assert_true(pallet.placed)
	assert_eq(pallet.count, 1)
	assert_eq(pallet.reserved, 0)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 1)
	assert_eq(_sim.board.unclaimed_count(), 0)
	assert_null(_dwarf.carrying)


func test_ball_is_visibly_carried_on_the_way() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), true)
	_drop_balls(1)
	var carried: bool = false
	for i in 100:
		_sim.tick()
		if _dwarf.carrying != null:
			carried = true
			assert_eq(_dwarf.carrying.state, Item.State.CARRIED)
	assert_true(carried)


func test_full_pallet_starts_a_new_one() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 2, 1), true)
	_drop_balls(4)
	SimFactory.run(_sim, 600)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.storage.pallets.size(), 2)
	var counts: Array[int] = []
	for pallet: Pallet in _sim.storage.pallets.values():
		counts.append(pallet.count)
	counts.sort()
	assert_eq(counts, [1, 3] as Array[int])


func test_each_pallet_holds_one_material() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 2, 1), true)
	_drop_balls(1, SimFactory.DIRT)
	_drop_balls(1, SimFactory.STONE)
	SimFactory.run(_sim, 400)
	assert_eq(_sim.storage.pallets.size(), 2)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 1)
	assert_eq(_sim.storage.totals[SimFactory.STONE], 1)


func test_full_stockpile_posts_one_request_and_leaves_the_ball() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), true)
	_drop_balls(5)
	SimFactory.run(_sim, 1000)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 3)
	assert_eq(_sim.items.size(), 2, "the rest stay on the floor")
	assert_eq(_sim.requests.entries.size(), 1, "deduped")
	var entry: RequestEntry = _sim.requests.entries[0]
	assert_eq(entry.dwarf_name, _dwarf.display_name)
	assert_string_contains(entry.message, "no room")
	assert_gt(entry.count, 1, "refreshed while the problem lasts")
	assert_lt(entry.count, 25, "but not every tick")
	assert_null(_dwarf.carrying)


func test_no_stockpile_posts_a_request() -> void:
	_drop_balls(1)
	SimFactory.run(_sim, 100)
	assert_eq(_sim.items.size(), 1)
	assert_eq(_sim.requests.entries.size(), 1)
	assert_string_contains(_sim.requests.entries[0].message, "Mark a stockpile")


func test_more_storage_clears_the_backlog() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), true)
	_drop_balls(5)
	SimFactory.run(_sim, 600)
	_sim.mark_stockpile(Rect2i(10, 6, 1, 1), true)
	SimFactory.run(_sim, 600)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 5)


func test_unmarking_a_stockpile_spills_its_pallet() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), true)
	_drop_balls(2)
	SimFactory.run(_sim, 400)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 2)
	_sim.mark_stockpile(Rect2i(9, 6, 1, 1), false)
	assert_eq(_sim.storage.pallets.size(), 0)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 0)
	assert_eq(_sim.items.size(), 2)


func test_dig_then_haul_end_to_end() -> void:
	_sim.mark_stockpile(Rect2i(9, 6, 3, 1), true)
	_sim.mark_dig(Rect2i(15, 4, 2, 3), true)
	SimFactory.run(_sim, 3000)
	assert_eq(_sim.items.size(), 0)
	assert_eq(_sim.storage.totals[SimFactory.DIRT], 6)
	assert_eq(_sim.storage.pallets.size(), 2)


func test_sim_is_deterministic() -> void:
	var a := SimFactory.make_sim()
	var b := SimFactory.make_sim()
	for sim: Simulation in [a, b]:
		sim.hire_dwarf()
		sim.hire_dwarf()
		sim.mark_stockpile(Rect2i(9, 6, 2, 1), true)
		sim.mark_dig(Rect2i(15, 4, 3, 3), true)
		SimFactory.run(sim, 700)
	assert_eq(a.dwarves[0].pos, b.dwarves[0].pos)
	assert_eq(a.dwarves[1].pos, b.dwarves[1].pos)
	assert_eq(a.items.size(), b.items.size())
	assert_eq(a.storage.totals, b.storage.totals)
