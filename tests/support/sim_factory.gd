extends RefCounted
## Builds small hand-made worlds for sim tests.
## The test world is solid dirt with one pre-dug entry room, no veins, no trees,
## no starting supplies, free stairs, and no idle wandering or personal tempo,
## so dwarves only move when a test gives them work.
##
## Layout: 3 sky rows, topsoil at row 3. Entry room x 9..14, open rows 4..6,
## floor row 7. A dwarf's feet are on row 6.

# Material indices.
const DIRT: int = 0
const STONE: int = 1

# Item type indices.
const DIRT_BALL: int = 0
const STONE_BALL: int = 1
const WOOD: int = 2
const CHAIR: int = 3
const TABLE: int = 4


static func make_config() -> SimConfig:
	var dirt_ball := _item(&"dirt", "Dirt", 1, ItemDef.Shape.BALL)
	var stone_ball := _item(&"stone", "Stone", 1, ItemDef.Shape.BALL)
	var wood := _item(&"wood", "Wood", 1, ItemDef.Shape.LOG)
	var chair := _item(&"chair", "Chair", 3, ItemDef.Shape.CHAIR)
	var table := _item(&"table", "Table", 5, ItemDef.Shape.TABLE)

	var dirt := MaterialDef.new()
	dirt.id = &"dirt"
	dirt.display_name = "Dirt"
	dirt.dig_ticks = 4
	dirt.drop = dirt_ball
	var stone := MaterialDef.new()
	stone.id = &"stone"
	stone.display_name = "Stone"
	stone.dig_ticks = 8
	stone.drop = stone_ball

	var band := DepthBand.new()
	band.base_material = dirt

	var world := WorldGenConfig.new()
	world.width = 24
	world.layer_count = 3
	world.sky_rows = 3
	world.entry_room_width = 6
	world.band_jitter = 0.0
	world.bands = [band]
	world.tree_count = 0

	var config := SimConfig.new()
	config.materials = [dirt, stone]
	config.items = [dirt_ball, stone_ball, wood, chair, table]
	config.recipes = [_recipe(wood, 1, chair, 10), _recipe(wood, 2, table, 10)]
	config.rooms = [make_carpentry(wood), make_hall(chair, table)]
	config.world_gen = world
	config.starting_item = null
	config.structure_item = null
	config.stair_build_ticks = 10
	config.floor_build_ticks = 10
	config.walk_ticks = 2
	config.idle_retry_ticks = 2
	config.wander_chance = 0.0
	config.sit_chance = 0.0
	config.think_ticks_max = 0
	config.pace_variation = 0.0
	config.job_retry_ticks = 10
	config.pile_capacity = 10
	config.request_refresh_ticks = 50
	config.dwarf_names = PackedStringArray(["Brokk", "Dagna"])
	return config


static func make_sim(config: SimConfig = null) -> Simulation:
	return Simulation.new(config if config != null else make_config(), 1234)


static func run(sim: Simulation, ticks: int) -> void:
	for i in ticks:
		sim.tick()


## The entry room in the test world: x 9..14, open rows 4..6, floor row 7.
static func room(sim: Simulation) -> Rect2i:
	return WorldGenerator.entry_room_rect(sim.config.world_gen)


## Opens a rectangle of tiles directly, without any digging.
static func carve(sim: Simulation, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			sim.grid.set_open(x, y)


static func place_dwarf(dwarf: Dwarf, tile: Vector2i) -> void:
	dwarf.pos = tile
	dwarf.from_pos = tile


## A workshop with a 3-wide bench (2 wood, built in place) and an output pile, every 4 tiles.
static func make_carpentry(wood: ItemDef) -> RoomDef:
	var bench := SlotDef.new()
	bench.kind = SlotDef.Kind.STATION
	bench.width = 3
	bench.item = wood
	bench.item_count = 2
	bench.work_ticks = 10
	bench.station_type = &"carpentry"
	var output := SlotDef.new()
	output.kind = SlotDef.Kind.OUTPUT
	output.offset = 3
	var def := RoomDef.new()
	def.id = &"carpentry"
	def.display_name = "Carpentry"
	def.min_width = 4
	def.pattern_width = 4
	def.slots = [bench, output]
	return def


## A hall with a chair and a table on every tile except one at each end.
static func make_hall(chair: ItemDef, table: ItemDef) -> RoomDef:
	var chair_slot := SlotDef.new()
	chair_slot.item = chair
	chair_slot.seat = true
	var table_slot := SlotDef.new()
	table_slot.item = table
	var def := RoomDef.new()
	def.id = &"hall"
	def.display_name = "Hall"
	def.min_width = 3
	def.margin = 1
	def.pattern_width = 1
	def.slots = [chair_slot, table_slot]
	return def


static func _item(id: StringName, display_name: String, size: int, shape: ItemDef.Shape) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.display_name = display_name
	item.size = size
	item.shape = shape
	return item


static func _recipe(input: ItemDef, input_count: int, output: ItemDef, work_ticks: int) -> RecipeDef:
	var recipe := RecipeDef.new()
	recipe.station_type = &"carpentry"
	recipe.input = input
	recipe.input_count = input_count
	recipe.output = output
	recipe.work_ticks = work_ticks
	return recipe
