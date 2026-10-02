extends RefCounted
## Builds small hand-made worlds for sim tests.
## The test world is solid dirt with one entry room, no veins, and no idle wandering,
## so dwarves only move when a test gives them work.

const DIRT: int = 0
const STONE: int = 1


static func make_config() -> SimConfig:
	var dirt := MaterialDef.new()
	dirt.id = &"dirt"
	dirt.display_name = "Dirt"
	dirt.dig_ticks = 4
	var stone := MaterialDef.new()
	stone.id = &"stone"
	stone.display_name = "Stone"
	stone.dig_ticks = 8

	var band := DepthBand.new()
	band.base_material = dirt

	var world := WorldGenConfig.new()
	world.width = 24
	world.layer_count = 3
	world.entry_room_width = 6
	world.band_jitter = 0.0
	world.bands = [band]

	var config := SimConfig.new()
	config.materials = [dirt, stone]
	config.world_gen = world
	config.walk_ticks = 2
	config.idle_retry_ticks = 2
	config.wander_chance = 0.0
	config.think_ticks_max = 0
	config.pace_variation = 0.0
	config.job_retry_ticks = 10
	config.pallet_capacity = 3
	config.haul_priority_threshold = 0
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
