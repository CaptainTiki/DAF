extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world, widened: the first layer is carved open from x 1 to x 22,
# rows 4..6, floor row 7. Feet row is 6.
# Sleep in the test config runs out in 200 ticks, is restored in 50, and a
# dwarf goes to bed once it drops below 35%.
var _sim: Simulation
var _dwarf: Dwarf
var _bunks: RoomDef


func before_each() -> void:
	_start(SimFactory.make_config())


func _start(config: SimConfig) -> void:
	SimFactory.hurry_needs(config)
	# Only sleep is under test here; food is kept out of the way.
	config.needs[SimFactory.FOOD].decay_ticks = SimFactory.SLOW
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	_bunks = _sim.config.rooms[SimFactory.BUNK_ROOM]
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))


## Places a bunk room with a bunk on every tile, in place without any crafting.
func _bunk_room(rect: Rect2i) -> Room:
	var room: Room = _sim.place_room(_bunks, rect)
	SimFactory.furnish_bunks(_sim, room)
	SimFactory.finish_sites(_sim, room)
	return room


func test_each_placed_bunk_asks_for_one() -> void:
	var room: Room = _sim.place_room(_bunks, Rect2i(3, 6, 4, 1))
	SimFactory.furnish_bunks(_sim, room)
	assert_eq(room.slots.size(), 4)
	assert_eq(_sim.logistics.open_count_of(SimFactory.BED), 4)
	assert_eq(room.slots[0].tile, Vector2i(3, 6))


func test_without_a_bunk_a_dwarf_sleeps_on_the_floor_and_is_unhappy() -> void:
	# Food is left out of it: a meal is on hand to keep that need neutral.
	_sim.storage.put(_sim.storage.add_pile(Pile.Kind.SUPPLY, Vector2i(2, 6), Pile.UNLIMITED), SimFactory.MEAL)
	assert_eq(_dwarf.mood, Dwarf.Mood.OK)
	var slept_at: Vector2i = Vector2i(-1, -1)
	for i in 300:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.REST and _dwarf.restoring == SimFactory.SLEEP:
			slept_at = _dwarf.pos
			assert_eq(_dwarf.speech, "Zzz")
			break
	assert_ne(slept_at, Vector2i(-1, -1), "slept")
	assert_null(_dwarf.seat, "on the floor, right where they were")
	for i in 100:
		_sim.tick()
		if _dwarf.activity != Dwarf.Activity.REST:
			break
	assert_gt(_dwarf.needs[SimFactory.SLEEP], 0.9, "rested all the same")
	assert_eq(_dwarf.need_quality[SimFactory.SLEEP], -1)
	assert_eq(_dwarf.mood, Dwarf.Mood.BAD, "but in a bad mood about it")
	var reported: bool = false
	for entry: RequestEntry in _sim.requests.entries:
		reported = reported or entry.message.contains("Sleeping on the floor")
	assert_true(reported)


func test_tired_dwarf_goes_to_bed_sleeps_and_gets_up() -> void:
	var room := _bunk_room(Rect2i(3, 6, 2, 1))
	var slept: bool = false
	var lowest: float = 1.0
	for i in 260:
		_sim.tick()
		lowest = minf(lowest, _dwarf.needs[SimFactory.SLEEP])
		if _dwarf.activity == Dwarf.Activity.REST:
			slept = true
			assert_eq(_dwarf.speech, "Zzz")
			assert_eq(_dwarf.pos.y, 6)
			assert_true(room.rect.has_point(_dwarf.pos))
	assert_true(slept)
	assert_lt(lowest, 0.35, "ran down before bed")
	assert_gt(lowest, 0.0, "but never ran out")
	assert_ne(_dwarf.activity, Dwarf.Activity.REST, "up again")
	assert_gt(_dwarf.needs[SimFactory.SLEEP], 0.5, "and rested")
	assert_eq(_dwarf.speech, "")
	assert_null(_dwarf.seat)


func test_dwarf_keeps_the_same_bunk() -> void:
	var room := _bunk_room(Rect2i(3, 6, 3, 1))
	var beds_used: Dictionary[Vector2i, bool] = {}
	for i in 1200:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.REST:
			beds_used[_dwarf.pos] = true
	assert_eq(beds_used.size(), 1, "slept several times, always in the same bunk")
	var owned: int = 0
	for slot: RoomSlot in room.slots:
		if slot.owner == _dwarf.id:
			owned += 1
	assert_eq(owned, 1)


func test_resting_dwarf_finishes_sleeping_before_taking_work() -> void:
	_bunk_room(Rect2i(3, 6, 2, 1))
	for i in 400:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.REST:
			break
	assert_eq(_dwarf.activity, Dwarf.Activity.REST)
	_sim.mark_dig(Rect2i(23, 6, 1, 1), true)
	SimFactory.run(_sim, 5)
	assert_eq(_dwarf.activity, Dwarf.Activity.REST, "still asleep")
	SimFactory.run(_sim, 200)
	assert_true(_sim.grid.is_open(23, 6), "dug once awake")


func test_mood_is_good_when_rested_and_bad_when_sleep_runs_out() -> void:
	# One bunk, two dwarves: the first to use it keeps it.
	_bunk_room(Rect2i(3, 6, 2, 1))
	_sim.rooms.rooms[0].slots[1].built = false
	_sim.rooms.changed.emit()
	var other := _sim.hire_dwarf()
	SimFactory.place_dwarf(other, Vector2i(12, 6))
	SimFactory.run(_sim, 30)
	assert_eq(_dwarf.mood, Dwarf.Mood.OK, "nothing has gone well or badly yet")

	SimFactory.run(_sim, 600)
	var moods: Array[int] = [_dwarf.mood, other.mood]
	moods.sort()
	assert_eq(moods, [Dwarf.Mood.BAD, Dwarf.Mood.GOOD] as Array[int], "one slept in the bunk, the other on the floor")
	var winner: Dwarf = _dwarf if _dwarf.mood == Dwarf.Mood.GOOD else other
	var loser: Dwarf = other if winner == _dwarf else _dwarf
	assert_eq(winner.need_quality[SimFactory.SLEEP], 1)
	assert_eq(loser.need_quality[SimFactory.SLEEP], -1)
	assert_gt(loser.needs[SimFactory.SLEEP], 0.0, "they still got some sleep")


func test_mood_changes_how_fast_a_dwarf_walks() -> void:
	var config := SimFactory.make_config()
	config.walk_ticks = 10
	_start(config)
	_bunk_room(Rect2i(3, 6, 2, 1))
	var step_ticks: Dictionary[int, int] = {}
	for mood: int in [Dwarf.Mood.BAD, Dwarf.Mood.OK, Dwarf.Mood.GOOD]:
		# Hold the need at a level that gives this mood, then send the dwarf walking.
		var level: float = [0.0, 0.45, 1.0][mood]
		_dwarf.needs[SimFactory.SLEEP] = level
		_dwarf.need_quality[SimFactory.SLEEP] = 1 if mood == Dwarf.Mood.GOOD else 0
		# Mood is worked out at the end of each tick, so let one pass first.
		_dwarf.activity = Dwarf.Activity.IDLE
		_dwarf.idle_ticks_left = 100
		_sim.tick()
		_dwarf.needs[SimFactory.SLEEP] = level
		_dwarf.needs[SimFactory.FOOD] = 1.0
		_dwarf.path = [_dwarf.pos + Vector2i(1, 0)] as Array[Vector2i]
		_dwarf.activity = Dwarf.Activity.WALK
		_dwarf.move_ticks_left = 0
		_sim.tick()
		assert_eq(_dwarf.mood, mood)
		step_ticks[mood] = _dwarf.move_ticks_total
	assert_eq(step_ticks[Dwarf.Mood.OK], 10)
	assert_eq(step_ticks[Dwarf.Mood.BAD], 13, "30% slower")
	assert_eq(step_ticks[Dwarf.Mood.GOOD], 9, "15% quicker")


func test_bunks_are_made_by_the_carpenter_and_set_in_place() -> void:
	SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(11, 6))
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, Vector2i(7, 6), Pile.UNLIMITED)
	# Bench 2 wood, two bunks at 2 wood each.
	for i in 6:
		_sim.storage.put(pile, SimFactory.WOOD)
	SimFactory.furnish_workshop(_sim, _sim.place_room(_sim.config.rooms[SimFactory.CARPENTRY], Rect2i(1, 6, 4, 1)))
	var room: Room = _sim.place_room(_bunks, Rect2i(14, 6, 2, 1))
	SimFactory.furnish_bunks(_sim, room)
	SimFactory.run(_sim, 4000)
	assert_true(room.slots[0].built)
	assert_true(room.slots[1].built)
	assert_eq(_sim.storage.totals[SimFactory.WOOD], 0)
	assert_eq(_sim.rooms.provider_count(&"sleep"), 2)


func test_removing_the_bunk_room_wakes_the_sleeper() -> void:
	var room := _bunk_room(Rect2i(3, 6, 2, 1))
	for i in 400:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.REST:
			break
	assert_eq(_dwarf.activity, Dwarf.Activity.REST)
	_sim.remove_rooms(room.rect)
	SimFactory.run(_sim, 5)
	assert_null(_dwarf.seat, "out of the bunk; if still tired they carry on on the floor")
	assert_eq(_sim.rooms.provider_count(&"sleep"), 0)
