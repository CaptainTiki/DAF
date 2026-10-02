extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
var _grid: TileGrid


func before_each() -> void:
	_grid = SimFactory.make_sim().grid


func test_can_stand_on_room_floor() -> void:
	assert_true(Pathfinder.can_stand(_grid, 9, 6))
	assert_false(Pathfinder.can_stand(_grid, 9, 5), "no ground under feet")
	assert_false(Pathfinder.can_stand(_grid, 8, 6), "inside rock")


func test_standing_needs_two_tiles_of_headroom() -> void:
	_grid.set_open(15, 6)
	assert_false(Pathfinder.can_stand(_grid, 15, 6), "one open tile is not enough")
	_grid.set_open(15, 5)
	assert_true(Pathfinder.can_stand(_grid, 15, 6))


func test_walks_sideways_but_not_two_columns() -> void:
	assert_true(Pathfinder.can_step(_grid, 9, 6, 10, 6))
	assert_false(Pathfinder.can_step(_grid, 9, 6, 11, 6))
	assert_false(Pathfinder.can_step(_grid, 9, 6, 8, 6), "rock")


func test_steps_down_and_back_up_a_one_tile_step() -> void:
	# Dig the floor at column 15 one tile down, with room for the body.
	_grid.set_open(15, 7)
	_grid.set_open(15, 6)
	_grid.set_open(15, 5)
	assert_true(Pathfinder.can_step(_grid, 14, 6, 15, 7), "down")
	assert_true(Pathfinder.can_step(_grid, 15, 7, 14, 6), "back up")


func test_step_needs_headroom_at_the_low_end() -> void:
	_grid.set_open(15, 7)
	_grid.set_open(15, 6)
	assert_false(Pathfinder.can_step(_grid, 14, 6, 15, 7), "ceiling too low over the lower tile")
	assert_false(Pathfinder.can_step(_grid, 15, 7, 14, 6))


func test_cannot_step_two_tiles_down() -> void:
	for y in range(4, 9):
		_grid.set_open(15, y)
	assert_false(Pathfinder.can_step(_grid, 14, 6, 15, 8))
	assert_false(Pathfinder.can_step(_grid, 14, 6, 15, 6), "nothing to stand on")


func test_reach_is_the_four_tiles_in_the_next_column() -> void:
	var from := Vector2i(10, 6)
	assert_true(Pathfinder.can_reach(from, Vector2i(11, 7)), "below feet")
	assert_true(Pathfinder.can_reach(from, Vector2i(11, 6)), "feet")
	assert_true(Pathfinder.can_reach(from, Vector2i(11, 5)), "head")
	assert_true(Pathfinder.can_reach(from, Vector2i(9, 4)), "above head")
	assert_false(Pathfinder.can_reach(from, Vector2i(11, 3)), "too high")
	assert_false(Pathfinder.can_reach(from, Vector2i(11, 8)), "too low")
	assert_false(Pathfinder.can_reach(from, Vector2i(10, 7)), "own column")
	assert_false(Pathfinder.can_reach(from, Vector2i(12, 6)), "two columns away")


func test_flood_covers_the_room_and_gives_distances() -> void:
	var map := Pathfinder.flood(_grid, Vector2i(9, 6))
	assert_eq(map.distance_to(9, 6), 0)
	assert_eq(map.distance_to(14, 6), 5)
	assert_eq(map.distance_to(15, 6), -1, "rock")
	assert_eq(map.reached.size(), 6)


func test_flood_respects_max_distance() -> void:
	var map := Pathfinder.flood(_grid, Vector2i(9, 6), 2)
	assert_eq(map.distance_to(11, 6), 2)
	assert_eq(map.distance_to(12, 6), -1)


func test_path_lists_steps_after_the_start() -> void:
	var map := Pathfinder.flood(_grid, Vector2i(9, 6))
	var path := map.path_to(12, 6)
	assert_eq(path, [Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6)] as Array[Vector2i])
	assert_eq(map.path_to(9, 6).size(), 0)
	assert_eq(map.path_to(20, 6).size(), 0)


func test_best_access_picks_the_nearest_spot_beside_the_tile() -> void:
	var map := Pathfinder.flood(_grid, Vector2i(9, 6))
	assert_eq(Pathfinder.best_access(map, 15, 5, false), Vector2i(14, 6), "wall tile beside the room")
	assert_eq(Pathfinder.best_access(map, 18, 5, false), Pathfinder.NO_SPOT, "buried tile")
	assert_eq(Pathfinder.best_access(map, 12, 6, false), Vector2i(11, 6), "nearer side of a floor tile")
	assert_eq(Pathfinder.best_access(map, 9, 6, true), Vector2i(9, 6), "standing on it counts")
