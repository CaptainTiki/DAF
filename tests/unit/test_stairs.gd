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
		_sim.grid.set_structure(tile.x, tile.y, TileGrid.STRUCTURE_STAIR)


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
