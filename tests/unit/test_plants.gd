extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
var _sim: Simulation
var _dwarf: Dwarf
var _shrub: PlantDef


func before_each() -> void:
	_sim = SimFactory.make_sim()
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))
	_shrub = PlantDef.new()
	_shrub.id = &"shrub"
	_shrub.grow_ticks = 50
	_shrub.harvest_ticks = 5
	_shrub.yield_item = _sim.config.items[SimFactory.WOOD]
	_shrub.yield_count = 2


func test_plant_grows_then_offers_a_harvest_job() -> void:
	var plant: Plant = _sim.plants.add(_shrub, Vector2i(13, 6), 0)
	_dwarf.idle_ticks_left = 100000
	SimFactory.run(_sim, 49)
	assert_false(plant.is_grown())
	assert_eq(_sim.board.unclaimed_of(Job.Kind.HARVEST), 0)
	SimFactory.run(_sim, 1)
	assert_true(plant.is_grown())
	assert_eq(_sim.board.unclaimed_of(Job.Kind.HARVEST), 1)


func test_harvest_drops_the_yield_and_the_plant_regrows() -> void:
	var plant: Plant = _sim.plants.add(_shrub, Vector2i(13, 6), 49)
	SimFactory.run(_sim, 40)
	assert_eq(_sim.items.size(), 2, "two wood on the ground")
	assert_false(plant.is_grown(), "cut back")
	assert_lt(plant.growth, 49)
	assert_eq(_sim.board.jobs_of(Job.Kind.HARVEST).size(), 0)
	SimFactory.run(_sim, 60)
	assert_eq(_sim.items.size(), 4, "and harvested again once regrown")


func test_each_plant_grows_at_its_own_speed() -> void:
	var fast: Plant = _sim.plants.add(_shrub, Vector2i(11, 6), 0, 1.1)
	var slow: Plant = _sim.plants.add(_shrub, Vector2i(13, 6), 0, 0.9)
	assert_eq(fast.grow_ticks, 45)
	assert_eq(slow.grow_ticks, 56)
	_dwarf.idle_ticks_left = 100000
	SimFactory.run(_sim, 50)
	assert_true(fast.is_grown())
	assert_false(slow.is_grown())


func test_rolled_growth_speed_stays_within_ten_percent() -> void:
	var seen_fast: bool = false
	var seen_slow: bool = false
	for i in 200:
		var speed: float = _sim.roll_growth_speed(_shrub)
		assert_between(speed, 0.9, 1.1)
		seen_fast = seen_fast or speed > 1.03
		seen_slow = seen_slow or speed < 0.97
	assert_true(seen_fast and seen_slow, "some quick, some slow")


func test_farm_room_grows_plants_and_loses_them_when_removed() -> void:
	var plot := SlotDef.new()
	plot.kind = SlotDef.Kind.PLANT
	plot.plant = _shrub
	var farm := RoomDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.min_width = 2
	farm.pattern_width = 2
	farm.slots = [plot]
	var room: Room = _sim.place_room(farm, Rect2i(9, 6, 6, 1))
	assert_eq(_sim.plants.plants.size(), 3, "a plot every 2 tiles")
	assert_eq(room.slots[1].plant.tile, Vector2i(11, 6))
	_sim.remove_rooms(room.rect)
	assert_eq(_sim.plants.plants.size(), 0)


# --- The real start ---

func test_real_game_starts_on_the_surface_with_wood_and_trees() -> void:
	var config: SimConfig = load("res://data/sim_config.tres")
	var sim := Simulation.new(config, 77)
	var wood: int = sim.item_type(config.starting_item)
	assert_eq(sim.spawn_point(), Vector2i(80, 7))
	assert_eq(sim.storage.totals[wood], 10)
	assert_eq(sim.storage.piles.size(), 1)
	assert_eq(sim.storage.piles[0].kind, Pile.Kind.SUPPLY)
	assert_eq(sim.plants.plants.size(), 8)
	for plant: Plant in sim.plants.plants:
		assert_eq(plant.tile.y, 7, "on the surface")
		assert_gt(absi(plant.tile.x - 80), 4, "clear of where the dwarves arrive")
	var dwarf := sim.hire_dwarf()
	assert_true(Pathfinder.can_stand(sim.grid, dwarf.pos.x, dwarf.pos.y))
	assert_eq(dwarf.pos.y, 7)


func test_real_game_opening_stairs_down_then_a_room() -> void:
	# The intended first minutes: stairs from the surface, dig a room, mark a
	# stockpile. Surface is feet row 7, topsoil row 8, first layer feet row 11.
	var config: SimConfig = load("res://data/sim_config.tres")
	var sim := Simulation.new(config, 77)
	for i in 3:
		sim.hire_dwarf()
	var flight: Array[Vector2i] = [Vector2i(83, 8), Vector2i(84, 9), Vector2i(85, 10)]
	sim.mark_stairs(flight, true)
	sim.mark_dig(Rect2i(86, 9, 10, 3), true)
	SimFactory.run(sim, 6000)
	for tile: Vector2i in flight:
		assert_true(sim.grid.has_stair(tile.x, tile.y), "stair at %s" % tile)
	assert_true(sim.grid.is_open(95, 11), "the room is dug out")
	var map := Pathfinder.flood(sim.grid, Vector2i(90, 11))
	assert_true(map.is_reachable(80, 7), "and connected to the surface")
	assert_eq(sim.storage.totals[sim.item_type(config.stair_item)] + sim.loose_unassigned_count(sim.item_type(config.stair_item)) >= 7, true, "three wood went into the stairs; trees may have added more")
