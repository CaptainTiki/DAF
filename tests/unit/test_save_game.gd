extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")
const SAVE_PATH := "user://test_save.dat"

# Test world: entry room x 9..14, open rows 4..6, floor row 7. Feet row is 6.
var _sim: Simulation


func before_each() -> void:
	_sim = SimFactory.make_sim()
	for i in 2:
		_sim.hire_dwarf()
	SimFactory.place_dwarf(_sim.dwarves[0], Vector2i(10, 6))
	SimFactory.place_dwarf(_sim.dwarves[1], Vector2i(12, 6))


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _busy_colony() -> void:
	# Wood lying about, a bench being built, a stair planned, and some digging.
	_sim.spill(SimFactory.WOOD, 6, Vector2i(11, 6))
	SimFactory.carve(_sim, Rect2i(15, 4, 4, 3))
	SimFactory.furnish_workshop(_sim, _sim.place_room(_sim.config.rooms[SimFactory.CARPENTRY], Rect2i(15, 6, 4, 1)))
	_sim.mark_stairs([Vector2i(9, 7), Vector2i(9, 8)], true)
	_sim.mark_dig(Rect2i(10, 7, 3, 1), true)
	_sim.mark_stockpile(Rect2i(13, 6, 2, 1), true)
	SimFactory.run(_sim, 150)


func test_round_trip_keeps_the_world() -> void:
	_busy_colony()
	var copy: Simulation = SaveGame.from_data(_sim.config, SaveGame.to_data(_sim))
	assert_eq(copy.tick_count, _sim.tick_count)
	assert_eq(copy.grid.export_arrays(), _sim.grid.export_arrays(), "grid")
	assert_eq(copy.dwarves.size(), 2)
	assert_eq(copy.dwarves[1].display_name, _sim.dwarves[1].display_name)
	assert_eq(copy.dwarves[1].pos, _sim.dwarves[1].pos)
	assert_eq(copy.dwarves[0].activity, Dwarf.Activity.IDLE, "dwarves start over idle")
	assert_eq(copy.rooms.rooms.size(), 1)
	assert_eq(copy.rooms.rooms[0].slots.size(), _sim.rooms.rooms[0].slots.size())
	assert_eq(copy.sites.size(), _sim.sites.size(), "build sites")
	assert_eq(copy.storage.tile_count(), _sim.storage.tile_count(), "stockpile tiles")
	assert_eq(copy.storage.totals, _sim.storage.totals, "stored totals")
	assert_eq(copy.board.jobs_of(Job.Kind.DIG).size(), _sim.board.jobs_of(Job.Kind.DIG).size(), "dig jobs")
	# Loose items plus whatever was in hand, all on the floor now.
	assert_eq(copy.items.size(), _sim.items.size(), "items")
	for item: Item in copy.items.values():
		assert_eq(item.state, Item.State.LOOSE)


func test_a_loaded_colony_carries_on() -> void:
	_busy_colony()
	_sim.mark_dig(Rect2i(10, 8, 3, 1), true)
	var copy: Simulation = SaveGame.from_data(_sim.config, SaveGame.to_data(_sim))
	assert_eq(copy.board.jobs_of(Job.Kind.DIG).size(), 3, "dig marks became jobs again")
	SimFactory.run(copy, 600)
	assert_eq(copy.board.jobs_of(Job.Kind.DIG).size(), 0, "and got dug")
	var bench_built: bool = false
	for slot: RoomSlot in copy.rooms.rooms[0].slots:
		bench_built = bench_built or (slot.def.kind == SlotDef.Kind.STATION and slot.built)
	assert_true(bench_built, "the bench got finished from the saved request")


func test_write_and_read_file() -> void:
	_busy_colony()
	assert_true(SaveGame.write(_sim, SAVE_PATH))
	var copy: Simulation = SaveGame.read(_sim.config, SAVE_PATH)
	assert_not_null(copy)
	assert_eq(copy.tick_count, _sim.tick_count)
	assert_eq(copy.grid.export_arrays(), _sim.grid.export_arrays())
	assert_eq(copy.dwarves.size(), 2)


func test_missing_file_reads_as_null() -> void:
	assert_null(SaveGame.read(_sim.config, SAVE_PATH))
