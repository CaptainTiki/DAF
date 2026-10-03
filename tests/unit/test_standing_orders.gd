extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
# Materials here are dirt, stone and iron; iron is mined on sight.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(12, 6))


func _rock(x: int, y: int, material: int) -> void:
	_sim.grid.set_tile(x, y, material, true)


# --- Ore ---

func test_ore_uncovered_by_digging_is_mined_without_being_asked() -> void:
	# A small vein two tiles into the wall, hidden until the first tile is dug.
	_rock(16, 5, SimFactory.IRON)
	_rock(17, 5, SimFactory.IRON)
	_rock(17, 4, SimFactory.IRON)
	_sim.mark_dig(Rect2i(15, 4, 1, 3), true)
	SimFactory.run(_sim, 600)
	assert_true(_sim.grid.is_open(16, 5), "the ore uncovered by the tunnel was mined")
	assert_eq(_sim.items.size(), 4, "three dirt balls and one ore")
	# The rest of the vein is marked, but out of reach from a 1-wide hole.
	assert_true(_sim.grid.is_dig_marked(17, 5))
	assert_true(_sim.grid.is_dig_marked(17, 4))
	assert_false(_sim.grid.is_dig_marked(18, 5), "and the stone beyond is left alone")


func test_ore_inside_a_planned_room_is_left_to_the_room() -> void:
	_rock(16, 5, SimFactory.IRON)
	_sim.place_room(_sim.config.rooms[SimFactory.HALL], Rect2i(16, 6, 3, 1))
	_sim.remove_rooms(Rect2i(16, 6, 1, 1))
	_sim.place_room(_sim.config.rooms[SimFactory.HALL], Rect2i(16, 6, 3, 1))
	assert_true(_sim.grid.is_dig_marked(16, 5), "the room marks it like any other tile")


# --- Quarry ---

func test_quarry_is_dug_only_while_stone_is_short() -> void:
	_sim.set_stock_target(SimFactory.STONE_BALL, 4)
	for y in range(4, 7):
		for x in range(15, 21):
			_rock(x, y, SimFactory.STONE)
	_sim.mark_stockpile(Rect2i(9, 6, 3, 1), true)
	var quarry: Room = _sim.place_room(_sim.config.rooms[SimFactory.QUARRY], Rect2i(15, 6, 6, 1))
	assert_not_null(quarry)
	assert_eq(_sim.board.unclaimed_of(Job.Kind.DIG), 0, "a quarry isn't all marked at once")
	SimFactory.run(_sim, 50)
	assert_eq(_sim.board.unclaimed_of(Job.Kind.DIG) + _dig_claimed(), 3, "a few tiles at a time")
	SimFactory.run(_sim, 3000)
	assert_gte(_sim.storage.totals[SimFactory.STONE_BALL], 4, "quarried until the stock was met")
	var dug: int = 0
	for y in range(4, 7):
		for x in range(15, 21):
			if _sim.grid.is_open(x, y):
				dug += 1
	assert_lt(dug, 18, "and not the whole quarry")

	# Use some up: the quarry starts again.
	_sim.storage.totals[SimFactory.STONE_BALL] = 0
	SimFactory.run(_sim, 50)
	assert_gt(_sim.board.unclaimed_of(Job.Kind.DIG) + _dig_claimed(), 0)


func _dig_claimed() -> int:
	var count: int = 0
	for dwarf: Dwarf in _sim.dwarves:
		if dwarf.job != null and dwarf.job.kind == Job.Kind.DIG:
			count += 1
	return count


# --- Harvest to stock ---

func test_plants_are_only_harvested_while_their_yield_is_short() -> void:
	var shrub := PlantDef.new()
	shrub.id = &"shrub"
	shrub.grow_ticks = 50
	shrub.harvest_ticks = 5
	shrub.yield_item = _sim.config.items[SimFactory.WOOD]
	shrub.yield_count = 1
	_sim.set_stock_target(SimFactory.WOOD, 2)
	_sim.plants.add(shrub, Vector2i(13, 6), 49)
	_sim.mark_stockpile(Rect2i(9, 6, 2, 1), true)
	SimFactory.run(_sim, 400)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 2, "harvested until two were in store")
	var plant: Plant = _sim.plants.plants[0]
	assert_true(plant.is_grown(), "then left standing")
	assert_null(plant.job)
	_sim.storage.totals[SimFactory.WOOD] = 0
	SimFactory.run(_sim, 60)
	assert_eq(_sim.items.size() + _sim.storage.totals[SimFactory.WOOD], 1, "and cut again when short")


func test_plants_without_a_stock_target_are_always_harvested() -> void:
	var shrub := PlantDef.new()
	shrub.id = &"shrub"
	shrub.grow_ticks = 50
	shrub.harvest_ticks = 5
	shrub.yield_item = _sim.config.items[SimFactory.WOOD]
	shrub.yield_count = 1
	_sim.plants.add(shrub, Vector2i(13, 6), 49)
	SimFactory.run(_sim, 300)
	assert_gte(_sim.items.size(), 4)