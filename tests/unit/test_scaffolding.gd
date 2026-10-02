extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world, made deeper for these tests: the entry room is x 9..14, open rows
# 4..6, floor row 7. Further down there is a tall chamber, carved by hand:
# x 9..14, open rows 14..19 (6 high), floor row 20. Feet row there is 19, and
# a dwarf on its floor reaches rows 17..20 of the next column.
# Structures are free here unless a test says otherwise.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_start(_deep_config())


func _deep_config() -> SimConfig:
	var config := SimFactory.make_config()
	config.world_gen.layer_count = 6
	return config


## A fresh world with the tall chamber and one dwarf standing in it.
func _start(config: SimConfig) -> void:
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(9, 14, 6, 6))
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 19))


## Makes the room taller by opening rows above it, without any digging.
func _raise_ceiling(rows: int) -> void:
	SimFactory.carve(_sim, Rect2i(9, 4 - rows, 6, rows))


func _scaffold_count() -> int:
	var count: int = 0
	for y in _sim.grid.height:
		for x in _sim.grid.width:
			if _sim.grid.has_scaffold(x, y):
				count += 1
	return count


# --- Climbing ---

func test_scaffolding_is_a_platform_that_can_be_climbed() -> void:
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	_raise_ceiling(3)
	_sim.grid.add_structure(12, 6, TileGrid.STRUCTURE_SCAFFOLD)
	_sim.grid.add_structure(12, 5, TileGrid.STRUCTURE_SCAFFOLD)
	assert_true(Pathfinder.can_stand(_sim.grid, 12, 5), "on the first platform")
	assert_true(Pathfinder.can_stand(_sim.grid, 12, 4), "on the second")
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 12, 5), "climb up")
	assert_true(Pathfinder.can_step(_sim.grid, 12, 5, 12, 4))
	assert_true(Pathfinder.can_step(_sim.grid, 12, 4, 12, 5), "and down")
	assert_false(Pathfinder.can_step(_sim.grid, 11, 6, 11, 5), "no climbing without it")
	var map := Pathfinder.flood(_sim.grid, Vector2i(12, 6))
	assert_eq(map.distance_to(12, 4), 2, "straight up from the foot of the tower")
	assert_eq(map.path_to(12, 4), [Vector2i(12, 5), Vector2i(12, 4)] as Array[Vector2i])


func test_walking_past_the_foot_of_a_tower_is_not_blocked() -> void:
	_raise_ceiling(2)
	_sim.grid.add_structure(12, 6, TileGrid.STRUCTURE_SCAFFOLD)
	assert_true(Pathfinder.can_step(_sim.grid, 11, 6, 12, 6))
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 13, 6))


func test_climbing_needs_headroom() -> void:
	_sim.grid.add_structure(12, 6, TileGrid.STRUCTURE_SCAFFOLD)
	# The room is 3 high: standing on the platform puts the head at row 4, fine.
	assert_true(Pathfinder.can_step(_sim.grid, 12, 6, 12, 5))
	_sim.grid.add_structure(12, 5, TileGrid.STRUCTURE_SCAFFOLD)
	assert_false(Pathfinder.can_step(_sim.grid, 12, 5, 12, 4), "head would be in the ceiling")


# --- Dwarves putting it up by themselves ---

func test_no_scaffolding_for_tiles_already_in_reach() -> void:
	_sim.mark_dig(Rect2i(15, 17, 1, 3), true)
	SimFactory.run(_sim, 300)
	assert_eq(_scaffold_count(), 0)
	assert_eq(_sim.sites.size(), 0)
	assert_true(_sim.grid.is_open(15, 17))


func test_dwarf_scaffolds_up_to_a_tile_too_high_to_reach() -> void:
	# The wall tile at row 15 is above reach: from the floor a dwarf reaches rows 17..20.
	_sim.mark_dig(Rect2i(15, 15, 1, 1), true)
	var built: int = 0
	var stood_at: Vector2i = Vector2i.ZERO
	for i in 600:
		_sim.tick()
		built = maxi(built, _scaffold_count())
		if _dwarf.activity == Dwarf.Activity.WORK and _dwarf.job != null and _dwarf.job.kind == Job.Kind.DIG:
			stood_at = _dwarf.pos
	assert_true(_sim.grid.is_open(15, 15), "the high tile was dug")
	assert_eq(built, 2, "two tiles of scaffolding: just enough to bring row 15 into reach")
	assert_eq(stood_at, Vector2i(14, 17), "dug from the top of the tower, beside the tile")


func test_tower_comes_down_when_the_digging_is_done() -> void:
	_sim.mark_dig(Rect2i(15, 15, 1, 1), true)
	SimFactory.run(_sim, 1500)
	assert_true(_sim.grid.is_open(15, 15))
	assert_eq(_scaffold_count(), 0, "taken down again")
	assert_eq(_sim.sites.size(), 0)
	assert_true(Pathfinder.can_stand(_sim.grid, _dwarf.pos.x, _dwarf.pos.y), "and the dwarf is back on the floor")
	assert_false(_sim.grid.is_remove_marked(14, 19))


func test_tower_stays_while_more_high_tiles_are_marked() -> void:
	_sim.mark_dig(Rect2i(15, 14, 1, 2), true)
	var towers_built: int = 0
	var had_scaffold: bool = false
	for i in 1500:
		_sim.tick()
		var has_now: bool = _scaffold_count() > 0
		if has_now and not had_scaffold:
			towers_built += 1
		had_scaffold = has_now
	assert_true(_sim.grid.is_open(15, 14))
	assert_true(_sim.grid.is_open(15, 15))
	assert_eq(towers_built, 1, "one tower served both tiles; it wasn't taken down in between")
	assert_eq(_scaffold_count(), 0)


func test_scaffolding_costs_wood_and_gives_it_back() -> void:
	var config := _deep_config()
	config.structure_item = config.items[SimFactory.WOOD]
	_start(config)
	_sim.mark_dig(Rect2i(15, 15, 1, 1), true)
	SimFactory.run(_sim, 400)
	assert_true(_sim.grid.is_solid(15, 15), "no wood, no tower, no digging")
	assert_eq(_scaffold_count(), 0)
	var found: bool = false
	for entry: RequestEntry in _sim.requests.entries:
		found = found or entry.message.contains("no wood for the scaffolding")
	assert_true(found, "and a dwarf says why")

	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, Vector2i(9, 19), Pile.UNLIMITED)
	for i in 2:
		_sim.storage.put(pile, SimFactory.WOOD)
	SimFactory.run(_sim, 2000)
	assert_true(_sim.grid.is_open(15, 15))
	assert_eq(_scaffold_count(), 0)
	var wood: int = _sim.storage.totals[SimFactory.WOOD] + _sim.loose_unassigned_count(SimFactory.WOOD)
	assert_eq(wood, 2, "both pieces of wood came back")


func test_no_tower_taller_than_the_limit() -> void:
	var config := _deep_config()
	config.scaffold_max_height = 1
	_start(config)
	_sim.mark_dig(Rect2i(15, 15, 1, 1), true)
	SimFactory.run(_sim, 400)
	assert_true(_sim.grid.is_solid(15, 15), "it would take a 2-tile tower")
	assert_eq(_scaffold_count(), 0)


func test_tall_room_is_dug_out_with_scaffolding_end_to_end() -> void:
	# Mark a block 3 wide and 6 high beside the chamber: rows 14..19. The top
	# three rows are out of reach from any floor.
	_sim.mark_dig(Rect2i(15, 14, 3, 6), true)
	SimFactory.run(_sim, 6000)
	for y in range(14, 20):
		for x in range(15, 18):
			assert_true(_sim.grid.is_open(x, y), "tile %d,%d" % [x, y])
	assert_eq(_scaffold_count(), 0, "all towers taken down")
	assert_true(Pathfinder.can_stand(_sim.grid, _dwarf.pos.x, _dwarf.pos.y))

# --- Digging overhead ---

func test_low_ceiling_is_dug_from_one_tile_of_scaffolding_underneath() -> void:
	# The entry room's ceiling is row 3: three above the feet at row 6, one too
	# high for the floor. One tile of scaffolding under it is enough.
	var sim := SimFactory.make_sim()
	var dwarf := sim.hire_dwarf()
	SimFactory.place_dwarf(dwarf, Vector2i(11, 6))
	sim.mark_dig(Rect2i(11, 3, 1, 1), true)
	var most: int = 0
	for i in 400:
		sim.tick()
		var count: int = 0
		for x in range(9, 15):
			if sim.grid.has_scaffold(x, 6):
				count += 1
		most = maxi(most, count)
	assert_true(sim.grid.is_open(11, 3))
	assert_eq(most, 1)

func test_one_tower_serves_three_columns_of_ceiling() -> void:
	# Raise the chamber ceiling (row 13) over three columns, x 10..12.
	_sim.mark_dig(Rect2i(10, 13, 3, 1), true)
	var columns_used: Dictionary[int, bool] = {}
	for i in 2500:
		_sim.tick()
		for y in _sim.grid.height:
			for x in range(9, 15):
				if _sim.grid.has_scaffold(x, y):
					columns_used[x] = true
	for x in range(10, 13):
		assert_true(_sim.grid.is_open(x, 13), "ceiling tile %d" % x)
	assert_eq(columns_used.size(), 1, "one tower: left, straight up and right from its top")
	assert_eq(_scaffold_count(), 0)
