extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
# The layer below has feet row 10 and is solid rock until dug.
# FLIGHT runs down to the right from the room floor: a dwarf at (12, 6) steps
# onto (13, 7), then (14, 8), (15, 9), and off onto the lower floor at (16, 10).
const FLIGHT: Array[Vector2i] = [Vector2i(13, 7), Vector2i(14, 8), Vector2i(15, 9)]

var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	_dwarf.pos = Vector2i(10, 6)
	_dwarf.from_pos = _dwarf.pos


func _build_flight() -> void:
	for tile: Vector2i in FLIGHT:
		_sim.grid.add_structure(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)


func test_marking_plans_stairs_in_rock_and_posts_jobs() -> void:
	assert_eq(_sim.mark_stairs(FLIGHT, true), 3)
	assert_true(_sim.grid.is_build_marked(13, 7))
	assert_true(_sim.grid.is_solid(13, 7), "planning doesn't dig")
	assert_eq(_sim.board.jobs_of(Job.Kind.BUILD).size(), 3)
	assert_eq(_sim.mark_stairs(FLIGHT, true), 0, "already planned")


func test_cancelling_removes_the_plan() -> void:
	_sim.mark_stairs(FLIGHT, true)
	assert_eq(_sim.mark_stairs(FLIGHT, false), 3)
	assert_eq(_sim.board.unclaimed_count(), 0)
	SimFactory.run(_sim, 300)
	assert_false(_sim.grid.has_stair(13, 7))


func test_dwarf_builds_the_whole_flight_from_the_top() -> void:
	_sim.mark_stairs(FLIGHT, true)
	SimFactory.run(_sim, 600)
	for tile: Vector2i in FLIGHT:
		assert_true(_sim.grid.has_stair(tile.x, tile.y), "stair at %s" % tile)
		assert_false(_sim.grid.is_build_marked(tile.x, tile.y))
	assert_eq(_sim.board.jobs_of(Job.Kind.BUILD).size(), 0)
	assert_eq(_sim.items.size(), 0, "building drops nothing")


func test_floor_over_a_stair_stays_walkable() -> void:
	_build_flight()
	assert_true(_sim.grid.is_solid(13, 7), "the floor tile is still rock in front")
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 13, 6), "walk across the top of the stairs")
	assert_true(Pathfinder.can_step(_sim.grid, 13, 6, 14, 6))


# --- Built floors ---

func test_dug_out_floor_at_a_stairwell_is_a_hole_until_a_floor_is_built() -> void:
	_build_flight()
	# The stairwell passes through the room's floor (row 7) at columns 13 and 14.
	_sim.grid.set_open(13, 7)
	_sim.grid.set_open(14, 7)
	assert_false(Pathfinder.can_stand(_sim.grid, 14, 6), "nothing underfoot")
	var map := Pathfinder.flood(_sim.grid, Vector2i(10, 6))
	assert_eq(map.distance_to(13, 6), -1, "can't stand over the hole")

	assert_eq(_sim.mark_floors(Rect2i(13, 7, 2, 1), true), 2)
	assert_true(_sim.grid.is_floor_marked(13, 7))
	SimFactory.run(_sim, 600)
	assert_true(_sim.grid.has_floor(13, 7))
	assert_true(_sim.grid.has_floor(14, 7))
	assert_true(_sim.grid.has_stair(13, 7), "the stair shares the tile")
	assert_false(_sim.grid.is_floor_marked(13, 7))
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 13, 6), "straight across")
	assert_true(Pathfinder.can_step(_sim.grid, 13, 6, 14, 6))
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 13, 7), "and the stairs still work")


func test_floor_can_only_be_planned_on_open_tiles() -> void:
	assert_eq(_sim.mark_floors(Rect2i(15, 5, 3, 1), true), 0, "solid rock")
	assert_eq(_sim.mark_floors(Rect2i(9, 1, 3, 1), true), 0, "open sky")
	assert_eq(_sim.mark_floors(Rect2i(9, 5, 3, 1), true), 3, "inside the room")
	assert_eq(_sim.mark_floors(Rect2i(9, 5, 3, 1), true), 0, "already planned")


func test_floor_splits_a_tall_room_into_two_storeys() -> void:
	# Open a shaft below the room: columns 11..12, rows 7..10, floor at row 11.
	SimFactory.carve(_sim, Rect2i(11, 7, 2, 4))
	assert_false(Pathfinder.can_stand(_sim.grid, 11, 6), "the room floor is gone here")
	_sim.mark_floors(Rect2i(11, 7, 2, 1), true)
	SimFactory.run(_sim, 600)
	assert_true(_sim.grid.has_floor(11, 7))
	assert_true(_sim.grid.has_floor(12, 7))
	assert_true(Pathfinder.can_stand(_sim.grid, 11, 6), "upper storey, on the planks")
	assert_true(Pathfinder.can_stand(_sim.grid, 11, 10), "lower storey, under them")
	assert_true(_sim.grid.is_open(11, 7), "the space under the planks stays open")


func test_items_rest_on_a_built_floor() -> void:
	SimFactory.carve(_sim, Rect2i(11, 7, 1, 4))
	_sim.grid.add_structure(11, 7, TileGrid.STRUCTURE_FLOOR)
	var item: Item = _sim.spawn_item(SimFactory.DIRT_BALL, Vector2i(11, 5))
	SimFactory.run(_sim, 30)
	assert_eq(item.pos, Vector2i(11, 6))
	assert_true(item.settled)


func test_floor_costs_wood() -> void:
	var config := SimFactory.make_config()
	config.structure_item = config.items[SimFactory.WOOD]
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	SimFactory.carve(_sim, Rect2i(13, 7, 1, 4))
	_sim.mark_floors(Rect2i(13, 7, 1, 1), true)
	SimFactory.run(_sim, 300)
	assert_false(_sim.grid.has_floor(13, 7), "no wood, no floor")
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, Vector2i(9, 6), Pile.UNLIMITED)
	_sim.storage.put(pile, SimFactory.WOOD)
	SimFactory.run(_sim, 600)
	assert_true(_sim.grid.has_floor(13, 7))
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0)


# --- Taking structures down ---

func test_removing_a_plan_cancels_it_at_once() -> void:
	_sim.mark_stairs(FLIGHT, true)
	_sim.mark_floors(Rect2i(9, 5, 2, 1), true)
	_dwarf.idle_ticks_left = 100000
	assert_eq(_sim.mark_removal(Rect2i(8, 4, 10, 8), true), 5)
	assert_eq(_sim.sites.size(), 0)
	assert_false(_sim.grid.is_build_marked(13, 7))
	assert_false(_sim.grid.is_floor_marked(9, 5))
	assert_false(_sim.grid.is_remove_marked(13, 7), "nothing was built, so nothing to take down")
	assert_eq(_sim.board.jobs_of(Job.Kind.BUILD).size(), 0)


func test_built_structures_are_marked_then_taken_down_by_a_dwarf() -> void:
	var config := SimFactory.make_config()
	config.structure_item = config.items[SimFactory.WOOD]
	_sim = SimFactory.make_sim(config)
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	_build_flight()
	assert_eq(_sim.mark_removal(Rect2i(13, 7, 3, 3), true), 3)
	assert_true(_sim.grid.is_remove_marked(13, 7))
	assert_true(_sim.grid.has_stair(13, 7), "still there until a dwarf does the work")
	assert_eq(_sim.mark_removal(Rect2i(13, 7, 3, 3), true), 0, "already marked")
	SimFactory.run(_sim, 600)
	for tile: Vector2i in FLIGHT:
		assert_false(_sim.grid.has_stair(tile.x, tile.y), "stair at %s" % tile)
		assert_false(_sim.grid.is_remove_marked(tile.x, tile.y))
	assert_eq(_sim.items.size(), 3, "one wood back per tile")
	assert_true(Pathfinder.can_stand(_sim.grid, _dwarf.pos.x, _dwarf.pos.y), "the dwarf ended on solid ground")
	assert_eq(_sim.sites.size(), 0)


func test_removal_mark_can_be_taken_off_again() -> void:
	_build_flight()
	_dwarf.idle_ticks_left = 100000
	_sim.mark_removal(Rect2i(13, 7, 3, 3), true)
	assert_eq(_sim.mark_removal(Rect2i(13, 7, 3, 3), false), 3)
	assert_false(_sim.grid.is_remove_marked(13, 7))
	assert_eq(_sim.board.jobs_of(Job.Kind.BUILD).size(), 0)
	_dwarf.idle_ticks_left = 1
	SimFactory.run(_sim, 300)
	assert_true(_sim.grid.has_stair(13, 7))


func test_a_flight_through_rock_is_taken_down_without_stranding_the_dwarf() -> void:
	# The only way to the room below is this flight. The dwarf starts below.
	_build_flight()
	SimFactory.carve(_sim, Rect2i(16, 8, 3, 3))
	SimFactory.place_dwarf(_dwarf, Vector2i(17, 10))
	_sim.mark_removal(Rect2i(13, 7, 3, 3), true)
	for i in 800:
		_sim.tick()
		assert_true(Pathfinder.is_supported(_sim.grid, _dwarf.pos.x, _dwarf.pos.y), "never left hanging")
	assert_true(Pathfinder.can_stand(_sim.grid, _dwarf.pos.x, _dwarf.pos.y), "ends on real ground, not inside the rock")
	for tile: Vector2i in FLIGHT:
		assert_false(_sim.grid.has_stair(tile.x, tile.y), "stair at %s" % tile)


func test_stair_with_another_dwarf_on_it_waits() -> void:
	_build_flight()
	var other := _sim.hire_dwarf()
	SimFactory.place_dwarf(other, Vector2i(14, 8))
	other.idle_ticks_left = 100000
	_sim.mark_removal(Rect2i(14, 8, 1, 1), true)
	SimFactory.run(_sim, 300)
	assert_true(_sim.grid.has_stair(14, 8), "not while someone is standing on it")
	SimFactory.place_dwarf(other, Vector2i(9, 6))
	SimFactory.run(_sim, 300)
	assert_false(_sim.grid.has_stair(14, 8))


func test_built_floor_is_taken_down_and_what_was_on_it_falls() -> void:
	SimFactory.carve(_sim, Rect2i(11, 7, 1, 4))
	_sim.grid.add_structure(11, 7, TileGrid.STRUCTURE_FLOOR)
	var item: Item = _sim.spawn_item(SimFactory.DIRT_BALL, Vector2i(11, 6))
	_dwarf.idle_ticks_left = 100000
	SimFactory.run(_sim, 10)
	assert_true(item.settled)
	_sim.mark_removal(Rect2i(11, 7, 1, 1), true)
	_dwarf.idle_ticks_left = 1
	SimFactory.run(_sim, 300)
	assert_false(_sim.grid.has_floor(11, 7))
	assert_eq(item.pos, Vector2i(11, 10), "down to the bottom of the shaft")
	assert_ne(_dwarf.pos, Vector2i(11, 10), "the dwarf did not go down with it")

func test_stairs_can_be_walked_through_rock() -> void:
	_build_flight()
	var map := Pathfinder.flood(_sim.grid, Vector2i(10, 6))
	assert_eq(map.distance_to(13, 7), 3, "down onto the first stair")
	assert_eq(map.distance_to(15, 9), 5, "bottom stair, still inside rock")
	assert_true(Pathfinder.can_step(_sim.grid, 15, 9, 14, 8), "and back up")


func test_dwarf_on_a_stair_does_not_fall() -> void:
	_build_flight()
	_dwarf.pos = Vector2i(14, 8)
	_dwarf.from_pos = _dwarf.pos
	SimFactory.run(_sim, 50)
	assert_eq(_dwarf.pos, Vector2i(14, 8))
	assert_ne(_dwarf.activity, Dwarf.Activity.FALL)


func test_lower_layer_can_be_dug_out_from_the_stairs() -> void:
	_build_flight()
	# A room on the layer below, to the right of the foot of the stairs.
	_sim.mark_dig(Rect2i(16, 8, 4, 3), true)
	SimFactory.run(_sim, 2500)
	for y in range(8, 11):
		for x in range(16, 20):
			assert_true(_sim.grid.is_open(x, y), "tile %d,%d" % [x, y])
	assert_true(_sim.grid.is_solid(16, 11), "lower floor intact")
	var map := Pathfinder.flood(_sim.grid, Vector2i(19, 10))
	assert_true(map.is_reachable(10, 6), "and the way back up still works")


func test_digging_beside_stairs_keeps_them() -> void:
	_build_flight()
	_sim.mark_dig(Rect2i(13, 8, 4, 3), true)
	SimFactory.run(_sim, 2500)
	for tile: Vector2i in FLIGHT:
		assert_true(_sim.grid.has_stair(tile.x, tile.y))
	var map := Pathfinder.flood(_sim.grid, Vector2i(10, 6))
	assert_true(map.is_reachable(16, 10))


func test_dwarves_spread_along_the_work_face() -> void:
	var other := _sim.hire_dwarf()
	other.pos = _dwarf.pos
	other.from_pos = other.pos
	# Work on both sides of the room: one dwarf each, not both on one tile.
	_sim.mark_dig(Rect2i(15, 4, 1, 3), true)
	_sim.mark_dig(Rect2i(8, 4, 1, 3), true)
	var together: int = 0
	for i in 60:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.WORK and other.activity == Dwarf.Activity.WORK and _dwarf.pos == other.pos:
			together += 1
	assert_eq(together, 0)


func test_idle_dwarves_do_not_stand_on_one_tile() -> void:
	var other := _sim.hire_dwarf()
	other.pos = _dwarf.pos
	other.from_pos = other.pos
	SimFactory.run(_sim, 200)
	assert_ne(_dwarf.pos, other.pos)

# --- Trapped dwarves ---

func test_dwarf_in_a_pit_says_so_and_is_quiet_again_once_there_is_a_way_out() -> void:
	# A sealed pocket below the room: no way up.
	SimFactory.carve(_sim, Rect2i(16, 8, 3, 3))
	SimFactory.place_dwarf(_dwarf, Vector2i(17, 10))
	SimFactory.run(_sim, 150)
	assert_true(_dwarf.trapped)
	assert_eq(_dwarf.speech, "!")
	assert_eq(_sim.requests.entries.size(), 1)
	assert_string_contains(_sim.requests.entries[0].message, "trapped")
	assert_eq(_sim.requests.entries[0].dwarf_name, _dwarf.display_name)

	_build_flight()
	SimFactory.run(_sim, 150)
	assert_false(_dwarf.trapped)
	assert_eq(_dwarf.speech, "")


func test_dwarf_at_home_is_not_trapped() -> void:
	SimFactory.run(_sim, 300)
	assert_false(_dwarf.trapped)
	assert_eq(_dwarf.speech, "")
	assert_eq(_sim.requests.entries.size(), 0)

# --- Stair layout from a drag ---

func test_diagonal_drag_makes_a_straight_flight() -> void:
	assert_eq(StairLayout.tiles(Vector2i(5, 5), Vector2i(8, 8)), [Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7), Vector2i(8, 8)] as Array[Vector2i])
	assert_eq(StairLayout.tiles(Vector2i(5, 5), Vector2i(3, 7)), [Vector2i(5, 5), Vector2i(4, 6), Vector2i(3, 7)] as Array[Vector2i])
	assert_eq(StairLayout.tiles(Vector2i(5, 5), Vector2i(5, 5)), [Vector2i(5, 5)] as Array[Vector2i])


func test_vertical_drag_makes_a_zig_zag_stairwell_two_wide() -> void:
	var tiles := StairLayout.tiles(Vector2i(5, 5), Vector2i(5, 10))
	assert_eq(tiles, [Vector2i(5, 5), Vector2i(6, 6), Vector2i(5, 7), Vector2i(6, 8), Vector2i(5, 9), Vector2i(6, 10)] as Array[Vector2i])
	# Every step is one tile over and one down, so dwarves can walk it.
	for i in range(1, tiles.size()):
		assert_eq(absi(tiles[i].x - tiles[i - 1].x), 1)
		assert_eq(tiles[i].y - tiles[i - 1].y, 1)
	# Leaning the drag to the left puts the zig-zag on that side.
	assert_eq(StairLayout.tiles(Vector2i(5, 5), Vector2i(4, 8))[1], Vector2i(4, 6))


func test_stairwell_from_a_drag_is_walkable_through_rock() -> void:
	var tiles := StairLayout.tiles(Vector2i(13, 7), Vector2i(13, 11))
	for tile: Vector2i in tiles:
		_sim.grid.add_structure(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)
	var map := Pathfinder.flood(_sim.grid, Vector2i(12, 6))
	assert_true(map.is_reachable(tiles[tiles.size() - 1].x, tiles[tiles.size() - 1].y), "bottom of the well")
