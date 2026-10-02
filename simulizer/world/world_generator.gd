class_name WorldGenerator
extends RefCounted
## Builds a TileGrid from a WorldGenConfig: depth bands, clumped veins, entry room.
## Deterministic for a given rng state.


static func generate(config: WorldGenConfig, materials: Array[MaterialDef], rng: RandomNumberGenerator) -> TileGrid:
	var grid := TileGrid.new(config.width, config.height(), config.first_layer_row(), config.layer_height)
	_fill_bands(grid, config, materials, rng)
	_seed_veins(grid, config, materials, rng)
	_carve_entry_room(grid, config)
	return grid


## The pre-dug room on the first layer where dwarves arrive.
static func entry_room_rect(config: WorldGenConfig) -> Rect2i:
	var room_width: int = mini(config.entry_room_width, config.width - 2)
	@warning_ignore("integer_division")
	var left: int = (config.width - room_width) / 2
	return Rect2i(left, config.first_layer_row(), room_width, config.layer_height - 1)


static func _fill_bands(grid: TileGrid, config: WorldGenConfig, materials: Array[MaterialDef], rng: RandomNumberGenerator) -> void:
	var base_index := PackedInt32Array()
	for band: DepthBand in config.bands:
		base_index.append(_index_of(materials, band.base_material))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi() & 0x7FFFFFFF
	noise.frequency = 0.06
	var ground_rows: float = grid.height - config.sky_rows
	for y in range(config.sky_rows, grid.height):
		for x in grid.width:
			var depth: float = (y - config.sky_rows) / ground_rows + noise.get_noise_2d(x, y) * config.band_jitter
			grid.set_tile(x, y, base_index[_band_at(config, depth)], true)


static func _seed_veins(grid: TileGrid, config: WorldGenConfig, materials: Array[MaterialDef], rng: RandomNumberGenerator) -> void:
	var ground_rows: int = grid.height - config.sky_rows
	for i in config.bands.size():
		var band: DepthBand = config.bands[i]
		var end_depth: float = config.bands[i + 1].start_depth if i + 1 < config.bands.size() else 1.0
		var row_from: int = config.sky_rows + int(band.start_depth * ground_rows)
		var row_to: int = mini(config.sky_rows + int(end_depth * ground_rows), grid.height) - 1
		if row_to < row_from:
			continue
		var area: int = (row_to - row_from + 1) * grid.width
		for vein: VeinDef in band.veins:
			var material: int = _index_of(materials, vein.material)
			var count: int = roundi(vein.veins_per_thousand_tiles * area / 1000.0)
			for n in count:
				var x: int = rng.randi_range(0, grid.width - 1)
				var y: int = rng.randi_range(row_from, row_to)
				var size: int = rng.randi_range(vein.min_size, vein.max_size)
				_grow_vein(grid, rng, material, x, y, size, config.sky_rows)


## Random walk that paints a clump of one material.
static func _grow_vein(grid: TileGrid, rng: RandomNumberGenerator, material: int, x: int, y: int, size: int, min_row: int) -> void:
	var placed: int = 0
	var attempts: int = size * 4
	while placed < size and attempts > 0:
		attempts -= 1
		if grid.material_at(x, y) != material:
			grid.set_tile(x, y, material, true)
			placed += 1
		match rng.randi_range(0, 3):
			0: x += 1
			1: x -= 1
			2: y += 1
			3: y -= 1
		x = clampi(x, 0, grid.width - 1)
		y = clampi(y, min_row, grid.height - 1)


static func _carve_entry_room(grid: TileGrid, config: WorldGenConfig) -> void:
	var room: Rect2i = entry_room_rect(config)
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			grid.set_open(x, y)


static func _band_at(config: WorldGenConfig, depth: float) -> int:
	var result: int = 0
	for i in config.bands.size():
		if config.bands[i].start_depth <= depth:
			result = i
	return result


static func _index_of(materials: Array[MaterialDef], material: MaterialDef) -> int:
	var index: int = materials.find(material)
	assert(index >= 0, "World gen uses a material that is missing from SimConfig.materials")
	return index
