extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	_dwarf.pos = Vector2i(10, 6)
	_dwarf.from_pos = _dwarf.pos


func test_hired_dwarf_stands_in_the_entry_room() -> void:
	var dwarf := _sim.hire_dwarf()
	assert_true(SimFactory.room(_sim).has_point(dwarf.pos))
	assert_true(Pathfinder.can_stand(_sim.grid, dwarf.pos.x, dwarf.pos.y))
	assert_ne(dwarf.display_name, "")
	assert_ne(dwarf.display_name, _dwarf.display_name)


func test_idle_dwarf_stays_put_without_work() -> void:
	SimFactory.run(_sim, 100)
	assert_eq(_dwarf.pos, Vector2i(10, 6))
	assert_eq(_dwarf.activity, Dwarf.Activity.IDLE)


func test_marking_only_affects_solid_tiles() -> void:
	var changed: int = _sim.mark_dig(Rect2i(13, 5, 4, 2), true)
	assert_eq(changed, 4, "two columns of rock, two rows; the room tiles are skipped")
	assert_true(_sim.grid.is_dig_marked(15, 5))
	assert_false(_sim.grid.is_dig_marked(14, 5))
	assert_eq(_sim.board.unclaimed_count(), 4)


func test_unmarking_cancels_the_jobs() -> void:
	_sim.mark_dig(Rect2i(15, 4, 2, 3), true)
	_sim.mark_dig(Rect2i(15, 4, 2, 3), false)
	assert_eq(_sim.board.unclaimed_count(), 0)
	SimFactory.run(_sim, 100)
	assert_true(_sim.grid.is_solid(15, 6))


func test_dwarf_walks_over_digs_and_drops_a_ball() -> void:
	_sim.mark_dig(Rect2i(15, 6, 1, 1), true)
	SimFactory.run(_sim, 60)
	assert_true(_sim.grid.is_open(15, 6))
	assert_false(_sim.grid.is_dig_marked(15, 6))
	assert_eq(_sim.board.dig_jobs().size(), 0)
	assert_eq(_sim.items.size(), 1)
	var item: Item = _sim.items.values()[0]
	assert_eq(item.pos, Vector2i(15, 6))
	assert_eq(item.material, SimFactory.DIRT)
	assert_true(item.settled)
	assert_eq(_dwarf.experience, 1)


func test_dwarf_digs_from_beside_the_tile() -> void:
	_sim.mark_dig(Rect2i(15, 4, 1, 3), true)
	var dug_from: Array[Vector2i] = []
	for i in 200:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.DIG:
			assert_true(Pathfinder.can_reach(_dwarf.pos, _dwarf.work_tile), "tile is in reach")
			assert_ne(_dwarf.pos.x, _dwarf.work_tile.x, "never digs own column")
			if not dug_from.has(_dwarf.pos):
				dug_from.append(_dwarf.pos)
	assert_eq(dug_from, [Vector2i(14, 6)] as Array[Vector2i], "the whole 3-tall column from one spot")
	for y in range(4, 7):
		assert_true(_sim.grid.is_open(15, y))


func test_dwarf_tunnels_through_a_marked_room() -> void:
	_sim.mark_dig(Rect2i(15, 4, 4, 3), true)
	SimFactory.run(_sim, 1500)
	for y in range(4, 7):
		for x in range(15, 19):
			assert_true(_sim.grid.is_open(x, y), "tile %d,%d" % [x, y])
	assert_eq(_sim.items.size(), 12)


func test_buried_tiles_wait_until_reachable() -> void:
	_sim.mark_dig(Rect2i(18, 5, 1, 1), true)
	SimFactory.run(_sim, 200)
	assert_true(_sim.grid.is_solid(18, 5))
	assert_eq(_dwarf.pos, Vector2i(10, 6), "nothing to walk to")


func test_hand_dug_steps_can_be_walked_down_and_up() -> void:
	# Mark a staircase going down to the right: each column one tile lower.
	_sim.mark_dig(Rect2i(15, 5, 1, 3), true)
	_sim.mark_dig(Rect2i(16, 6, 1, 3), true)
	_sim.mark_dig(Rect2i(17, 7, 1, 3), true)
	var lowest: int = _dwarf.pos.y
	for i in 1500:
		_sim.tick()
		assert_ne(_dwarf.activity, Dwarf.Activity.FALL, "never digs out own footing")
		lowest = maxi(lowest, _dwarf.pos.y)
	assert_true(_sim.grid.is_open(17, 9))
	assert_true(Pathfinder.can_stand(_sim.grid, 17, 9))
	var map := Pathfinder.flood(_sim.grid, Vector2i(17, 9))
	assert_true(map.is_reachable(10, 6), "can climb back to the room")
	assert_gt(lowest, 6, "the dwarf went down the steps")


func test_ball_falls_when_the_tile_under_it_is_dug() -> void:
	_sim.mark_dig(Rect2i(15, 5, 1, 1), true)
	SimFactory.run(_sim, 80)
	var item: Item = _sim.items.values()[0]
	assert_eq(item.pos, Vector2i(15, 5), "rests on the undug tile below")
	_sim.mark_dig(Rect2i(15, 6, 1, 1), true)
	SimFactory.run(_sim, 80)
	assert_eq(item.pos, Vector2i(15, 6))
	assert_true(item.settled)


func test_dwarf_falls_when_the_floor_goes() -> void:
	_sim.grid.set_open(10, 7)
	_sim.grid.set_open(10, 8)
	SimFactory.run(_sim, 20)
	assert_eq(_dwarf.pos, Vector2i(10, 8))
	assert_eq(_dwarf.activity, Dwarf.Activity.IDLE)


func test_two_dwarves_never_share_a_dig_job() -> void:
	var other := _sim.hire_dwarf()
	_sim.mark_dig(Rect2i(15, 4, 3, 3), true)
	for i in 1200:
		_sim.tick()
		if _dwarf.job != null and other.job != null:
			assert_ne(_dwarf.job, other.job)
	assert_eq(_sim.items.size(), 9)
