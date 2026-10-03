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
const IRON: int = 2

# Item type indices.
const DIRT_BALL: int = 0
const STONE_BALL: int = 1
const WOOD: int = 2
const CHAIR: int = 3
const TABLE: int = 4
const BED: int = 5
const MUSHROOM: int = 6
const MEAL: int = 7
const SHELF: int = 8
const IRON_ORE: int = 9

# Room type indices in config.rooms.
const CARPENTRY: int = 0
const HALL: int = 1
const BUNK_ROOM: int = 2
const KITCHEN: int = 3
const STOREROOM: int = 4
const QUARRY: int = 5

# Need indices.
const SLEEP: int = 0
const FOOD: int = 1


static func make_config() -> SimConfig:
	var dirt_ball := _item(&"dirt", "Dirt", 1, ItemDef.Shape.BALL)
	var stone_ball := _item(&"stone", "Stone", 1, ItemDef.Shape.BALL)
	var wood := _item(&"wood", "Wood", 1, ItemDef.Shape.LOG)
	var chair := _item(&"chair", "Chair", 3, ItemDef.Shape.CHAIR)
	var table := _item(&"table", "Table", 5, ItemDef.Shape.TABLE)
	var bed := _item(&"bed", "Bunk", 5, ItemDef.Shape.BED)
	var mushroom := _item(&"mushroom", "Mushroom", 1, ItemDef.Shape.BALL)
	var meal := _item(&"meal", "Meal", 1, ItemDef.Shape.BALL)
	meal.quality = 1
	var shelf := _item(&"shelf", "Shelf", 2, ItemDef.Shape.SHELF)
	var iron_ore := _item(&"iron_ore", "Iron ore", 1, ItemDef.Shape.BALL)

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

	var iron := MaterialDef.new()
	iron.id = &"iron"
	iron.display_name = "Iron"
	iron.dig_ticks = 8
	iron.drop = iron_ore
	iron.auto_mine = true

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
	config.materials = [dirt, stone, iron]
	config.items = [dirt_ball, stone_ball, wood, chair, table, bed, mushroom, meal, shelf, iron_ore]
	config.recipes = [_recipe(wood, 1, chair, 10), _recipe(wood, 2, table, 10), _recipe(wood, 2, bed, 10), _recipe(mushroom, 2, meal, 10, &"cooking"), _recipe(wood, 1, shelf, 10)]
	config.rooms = [make_carpentry(wood), make_hall(chair, table), make_bunk_room(bed), make_kitchen(wood), make_storeroom(shelf), make_quarry()]
	config.needs = [make_sleep_need(), make_food_need(meal, mushroom)]
	config.world_gen = world
	config.starting_item = null
	config.structure_item = null
	config.stair_build_ticks = 10
	config.floor_build_ticks = 10
	config.remove_ticks = 10
	config.scaffold_build_ticks = 10
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
	chair_slot.satisfies = &"dining"
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


## A bunk on every tile. Bunks satisfy the sleep need.
static func make_bunk_room(bed: ItemDef) -> RoomDef:
	var bed_slot := SlotDef.new()
	bed_slot.item = bed
	bed_slot.satisfies = &"sleep"
	var def := RoomDef.new()
	def.id = &"bunk_room"
	def.display_name = "Bunk room"
	def.min_width = 2
	def.pattern_width = 1
	def.slots = [bed_slot]
	return def


## Needs in the test world run down so slowly they never matter unless a test
## calls hurry_needs(). Then sleep runs out in 200 ticks and food in 300.
const SLOW: int = 100000000


static func hurry_needs(config: SimConfig) -> void:
	config.needs[SLEEP].decay_ticks = 200
	config.needs[FOOD].decay_ticks = 300


## Sleep: restored in 50 ticks, sought below 35%.
static func make_sleep_need() -> NeedDef:
	var need := NeedDef.new()
	need.id = &"sleep"
	need.display_name = "Sleep"
	need.decay_ticks = SLOW
	need.restore_ticks = 50
	need.seek_below = 0.35
	need.provider = &"sleep"
	need.owned = true
	return need


## Food: eaten in 20 ticks, sought below 40%. Satisfied by fetching a meal (or,
## failing that, a raw mushroom) to a dining seat. One meal is kept in stock.
static func make_food_need(meal: ItemDef, mushroom: ItemDef) -> NeedDef:
	var need := NeedDef.new()
	need.id = &"food"
	need.display_name = "Food"
	need.decay_ticks = SLOW
	need.restore_ticks = 20
	need.seek_below = 0.4
	need.provider = &"dining"
	need.consumes = [meal, mushroom]
	need.stock_target = 1
	need.using_speech = "nom"
	need.unmet_speech = "hungry!"
	need.no_item_message = "nothing to eat."
	need.no_provider_message = "nowhere to eat. Eating on the floor."
	return need


## A storeroom: a stockpile spot on every floor tile, with two shelves above
## it that become storage once a carpenter-made shelf is set in place.
static func make_storeroom(shelf: ItemDef) -> RoomDef:
	var floor_spot := SlotDef.new()
	floor_spot.kind = SlotDef.Kind.STOCKPILE
	var slots: Array[SlotDef] = [floor_spot]
	for rise in [1, 2]:
		var shelf_slot := SlotDef.new()
		shelf_slot.item = shelf
		shelf_slot.rise = rise
		shelf_slot.storage = true
		slots.append(shelf_slot)
	var def := RoomDef.new()
	def.id = &"storeroom"
	def.display_name = "Storeroom"
	def.min_width = 2
	def.pattern_width = 1
	def.slots = slots
	return def


## A quarry: rock dug a few tiles at a time while its stone is short.
static func make_quarry() -> RoomDef:
	var def := RoomDef.new()
	def.id = &"quarry"
	def.display_name = "Quarry"
	def.quarry = true
	def.min_width = 2
	return def


## A kitchen: a 3-wide stove (2 wood, built in place) and an output pile.
static func make_kitchen(wood: ItemDef) -> RoomDef:
	var def: RoomDef = make_carpentry(wood)
	def.id = &"kitchen"
	def.display_name = "Kitchen"
	(def.slots[0] as SlotDef).station_type = &"cooking"
	return def


static func _item(id: StringName, display_name: String, size: int, shape: ItemDef.Shape) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.display_name = display_name
	item.size = size
	item.shape = shape
	return item


static func _recipe(input: ItemDef, input_count: int, output: ItemDef, work_ticks: int, station_type: StringName = &"carpentry") -> RecipeDef:
	var recipe := RecipeDef.new()
	recipe.station_type = station_type
	recipe.input = input
	recipe.input_count = input_count
	recipe.output = output
	recipe.work_ticks = work_ticks
	return recipe
