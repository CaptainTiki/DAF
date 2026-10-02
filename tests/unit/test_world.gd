extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

var _real_config: SimConfig = preload("res://data/sim_config.tres")


func _generate(world_seed: int) -> TileGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	return WorldGenerator.generate(_real_config.world_gen, _real_config.materials, rng)


func _count_materials(grid: TileGrid, row_from: int, row_to: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(_real_config.materials.size())
	for y in range(row_from, row_to):
		for x in grid.width:
			var material: int = grid.material_at(x, y)
			if material != TileGrid.NO_MATERIAL:
				counts[material] += 1
	return counts


func _index(id: StringName) -> int:
	for i in _real_config.materials.size():
		if _real_config.materials[i].id == id:
			return i
	return -1


func test_grid_size_matches_config() -> void:
	var grid := _generate(1)
	assert_eq(grid.width, 160)
	assert_eq(grid.height, 124)
	assert_eq(grid.layer_count(), 30)


func test_same_seed_gives_same_world() -> void:
	var a := _generate(42)
	var b := _generate(42)
	var differences: int = 0
	for y in a.height:
		for x in a.width:
			if a.material_at(x, y) != b.material_at(x, y) or a.is_solid(x, y) != b.is_solid(x, y):
				differences += 1
	assert_eq(differences, 0)


func test_sky_is_open_and_ground_is_solid() -> void:
	var grid := _generate(7)
	assert_true(grid.is_open(0, 0))
	assert_true(grid.is_open(80, 2))
	assert_true(grid.is_solid(0, 3))
	assert_true(grid.is_solid(80, 123))


func test_out_of_bounds_reads_as_solid() -> void:
	var grid := _generate(7)
	assert_true(grid.is_solid(-1, 10))
	assert_true(grid.is_solid(10, grid.height))
	assert_false(grid.is_open(grid.width, 10))


func test_entry_room_is_open_with_a_floor() -> void:
	var grid := _generate(7)
	var room: Rect2i = WorldGenerator.entry_room_rect(_real_config.world_gen)
	assert_eq(room.size, Vector2i(12, 3))
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			assert_true(grid.is_open(x, y), "room tile %d,%d" % [x, y])
	for x in range(room.position.x, room.end.x):
		assert_true(grid.is_solid(x, room.end.y), "floor under %d" % x)
		assert_true(grid.is_solid(x, room.position.y - 1), "ceiling over %d" % x)


func test_materials_follow_depth() -> void:
	var grid := _generate(99)
	var top := _count_materials(grid, 3, 14)
	var bottom := _count_materials(grid, 100, 124)
	var all := _count_materials(grid, 0, 124)
	assert_gt(top[_index(&"dirt")], top[_index(&"stone")], "dirt dominates near the surface")
	assert_eq(top[_index(&"gem")], 0, "no gems near the surface")
	assert_gt(bottom[_index(&"gem")], 0, "gems at the bottom")
	assert_gt(all[_index(&"iron")], all[_index(&"gold")] * 3, "iron far more common than gold")


func test_veins_are_clumped() -> void:
	var grid := _generate(99)
	var iron: int = _index(&"iron")
	var total: int = 0
	var with_neighbour: int = 0
	for y in grid.height:
		for x in grid.width:
			if grid.material_at(x, y) != iron:
				continue
			total += 1
			if grid.material_at(x + 1, y) == iron or grid.material_at(x - 1, y) == iron \
					or grid.material_at(x, y + 1) == iron or grid.material_at(x, y - 1) == iron:
				with_neighbour += 1
	assert_gt(total, 0)
	assert_gt(float(with_neighbour) / total, 0.9, "ore tiles touch other ore tiles")


func test_layer_rows() -> void:
	var grid := SimFactory.make_sim().grid
	assert_eq(grid.layer_top_row(0), 4)
	assert_eq(grid.layer_floor_row(0), 7)
	assert_eq(grid.layer_of_row(4), 0)
	assert_eq(grid.layer_of_row(7), 0)
	assert_eq(grid.layer_of_row(8), 1)
	assert_eq(grid.layer_of_row(2), -1)
