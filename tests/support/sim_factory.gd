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

# Furniture indices in config.furniture.
const BENCH: int = 0
const CHAIR_PIECE: int = 1
const TABLE_PIECE: int = 2
const BED_PIECE: int = 3
const SHELF_PIECE: int = 4
const STOVE: int = 5


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
	config.rooms = [make_carpentry(), make_hall(), make_bunk_room(), make_kitchen(), make_storeroom(), make_quarry()]
	config.furniture = [make_bench(wood), make_chair(chair), make_table(table), make_bed(bed), make_shelf(shelf), make_stove(wood)]
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


static func make_carpentry() -> RoomDef:
	return _room(&"carpentry", "Carpentry", 4)


static func make_hall() -> RoomDef:
	return _room(&"hall", "Hall", 3)


static func make_bunk_room() -> RoomDef:
	return _room(&"bunk_room", "Bunk room", 2)


static func make_kitchen() -> RoomDef:
	return _room(&"kitchen", "Kitchen", 4)


## A 3-wide bench (2 wood, built in place) with an output pile to its right.
static func make_bench(wood: ItemDef) -> SlotDef:
	var bench := SlotDef.new()
	bench.id = &"bench"
	bench.display_name = "Bench"
	bench.kind = SlotDef.Kind.STATION
	bench.rooms = [&"carpentry"]
	bench.width = 3
	bench.item = wood
	bench.item_count = 2
	bench.work_ticks = 10
	bench.station_type = &"carpentry"
	bench.output = true
	return bench


## A 3-wide stove (2 wood) with an output pile, for the kitchen.
static func make_stove(wood: ItemDef) -> SlotDef:
	var stove: SlotDef = make_bench(wood)
	stove.id = &"stove"
	stove.display_name = "Stove"
	stove.rooms = [&"kitchen"]
	stove.station_type = &"cooking"
	return stove


## A dining seat, for the hall.
static func make_chair(chair: ItemDef) -> SlotDef:
	var def := SlotDef.new()
	def.id = &"chair"
	def.display_name = "Chair"
	def.rooms = [&"hall"]
	def.item = chair
	def.seat = true
	def.satisfies = &"dining"
	return def


static func make_table(table: ItemDef) -> SlotDef:
	var def := SlotDef.new()
	def.id = &"table"
	def.display_name = "Table"
	def.rooms = [&"hall"]
	def.item = table
	return def


## A bunk, for the bunk room. Bunks satisfy the sleep need.
static func make_bed(bed: ItemDef) -> SlotDef:
	var def := SlotDef.new()
	def.id = &"bed"
	def.display_name = "Bunk"
	def.rooms = [&"bunk_room"]
	def.item = bed
	def.satisfies = &"sleep"
	return def


## A shelf: storage on the wall of a storeroom, one or two tiles up.
static func make_shelf(shelf: ItemDef) -> SlotDef:
	var def := SlotDef.new()
	def.id = &"shelf"
	def.display_name = "Shelf"
	def.rooms = [&"storeroom"]
	def.item = shelf
	def.rise = 1
	def.rise_max = 2
	def.storage = true
	return def


## Places a piece of furniture. Fails the test loudly if it doesn't fit.
static func place(sim: Simulation, piece: int, tile: Vector2i) -> RoomSlot:
	var slot: RoomSlot = sim.place_furniture(sim.config.furniture[piece], tile)
	assert(slot != null, "furniture %d does not fit at %s" % [piece, tile])
	return slot


## Fills a hall the old automatic way: a chair and a table on every tile but
## the ends. Returns the chairs.
static func furnish_hall(sim: Simulation, room: Room) -> Array[RoomSlot]:
	var chairs: Array[RoomSlot] = []
	for x in range(room.rect.position.x + 1, room.rect.end.x - 1):
		chairs.append(place(sim, CHAIR_PIECE, Vector2i(x, room.feet_row)))
		place(sim, TABLE_PIECE, Vector2i(x, room.feet_row))
	return chairs


## A bunk on every tile of a bunk room.
static func furnish_bunks(sim: Simulation, room: Room) -> Array[RoomSlot]:
	var beds: Array[RoomSlot] = []
	for x in range(room.rect.position.x, room.rect.end.x):
		beds.append(place(sim, BED_PIECE, Vector2i(x, room.feet_row)))
	return beds


## A bench (or stove) at the left end of a workshop.
static func furnish_workshop(sim: Simulation, room: Room) -> RoomSlot:
	var piece: int = STOVE if room.def.id == &"kitchen" else BENCH
	return place(sim, piece, Vector2i(room.rect.position.x, room.feet_row))


## Two shelves above every tile of a storeroom.
static func furnish_storeroom(sim: Simulation, room: Room) -> Array[RoomSlot]:
	var shelves: Array[RoomSlot] = []
	for x in range(room.rect.position.x, room.rect.end.x):
		for rise in [1, 2]:
			shelves.append(place(sim, SHELF_PIECE, Vector2i(x, room.feet_row - rise)))
	return shelves


## Finishes every pending site in a room, as if everything had been delivered and built.
static func finish_sites(sim: Simulation, room: Room) -> void:
	for slot: RoomSlot in room.slots.duplicate():
		if slot.site != null:
			sim.complete_site(slot.site)


static func _room(id: StringName, display_name: String, min_width: int) -> RoomDef:
	var def := RoomDef.new()
	def.id = id
	def.display_name = display_name
	def.min_width = min_width
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


## A storeroom: a stockpile spot on every floor tile. Shelves are placed.
static func make_storeroom() -> RoomDef:
	var floor_spot := SlotDef.new()
	floor_spot.kind = SlotDef.Kind.STOCKPILE
	var def: RoomDef = _room(&"storeroom", "Storeroom", 2)
	def.pattern_width = 1
	def.slots = [floor_spot]
	return def


## A quarry: rock dug a few tiles at a time while its stone is short.
static func make_quarry() -> RoomDef:
	var def := RoomDef.new()
	def.id = &"quarry"
	def.display_name = "Quarry"
	def.quarry = true
	def.min_width = 2
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
