extends GutTest

const SimFactory := preload("res://tests/support/sim_factory.gd")

# Test world, widened: the first layer is carved open from x 1 to x 22,
# rows 4..6, floor row 7. Feet row is 6.
# Food in the test config runs out in 300 ticks, takes 20 to eat, and a dwarf
# goes for a meal below 40%. A meal is 2 mushrooms at the kitchen.
var _sim: Simulation
var _dwarf: Dwarf


func before_each() -> void:
	var config := SimFactory.make_config()
	SimFactory.hurry_needs(config)
	# Only food is under test here; sleep is kept out of the way.
	config.needs[SimFactory.SLEEP].decay_ticks = SimFactory.SLOW
	_sim = SimFactory.make_sim(config)
	SimFactory.carve(_sim, Rect2i(1, 4, 22, 3))
	_dwarf = _sim.hire_dwarf()
	SimFactory.place_dwarf(_dwarf, Vector2i(10, 6))


## A hall with its chairs and tables in place, no crafting needed.
func _hall(rect: Rect2i) -> Room:
	var room: Room = _sim.place_room(_sim.config.rooms[SimFactory.HALL], rect)
	SimFactory.furnish_hall(_sim, room)
	SimFactory.finish_sites(_sim, room)
	return room


## A kitchen with its stove built.
func _kitchen(rect: Rect2i) -> Room:
	var room: Room = _sim.place_room(_sim.config.rooms[SimFactory.KITCHEN], rect)
	_sim.complete_site(SimFactory.furnish_workshop(_sim, room).site)
	return room


func _supply(type: int, count: int, tile: Vector2i) -> Pile:
	var pile: Pile = _sim.storage.add_pile(Pile.Kind.SUPPLY, tile, Pile.UNLIMITED)
	for i in count:
		_sim.storage.put(pile, type)
	return pile


func test_raw_mushroom_at_a_table_leaves_the_dwarf_neutral() -> void:
	_hall(Rect2i(14, 6, 5, 1))
	_supply(SimFactory.MUSHROOM, 2, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	assert_ne(_run_until_eating(400), Vector2i(-1, -1), "ate a raw mushroom, there being no meal")
	assert_eq(_dwarf.need_quality[SimFactory.FOOD], 0)
	_run_until_up(100)
	assert_eq(_dwarf.mood, Dwarf.Mood.OK)


func test_eating_on_the_floor_is_worse_than_at_a_table() -> void:
	# No hall. A meal is eaten where it is picked up.
	_supply(SimFactory.MEAL, 2, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	var ate_at: Vector2i = _run_until_eating(400)
	assert_ne(ate_at, Vector2i(-1, -1))
	assert_lte(absi(ate_at.x - 8), 1, "by the pile")
	assert_null(_dwarf.seat)
	assert_eq(_dwarf.need_quality[SimFactory.FOOD], 0, "a good meal on the floor is only plain")
	_run_until_up(100)
	assert_gt(_dwarf.needs[SimFactory.FOOD], 0.9, "fed all the same")

	# A raw mushroom on the floor is the worst of both.
	_supply(SimFactory.MUSHROOM, 2, Vector2i(12, 6))
	_sim.storage.remove_pile(_sim.storage.piles[0])
	_dwarf.needs[SimFactory.FOOD] = 0.3
	assert_ne(_run_until_eating(400), Vector2i(-1, -1))
	assert_eq(_dwarf.need_quality[SimFactory.FOOD], -1)
	_run_until_up(100)
	assert_eq(_dwarf.mood, Dwarf.Mood.BAD)


func test_a_proper_meal_at_a_table_is_what_makes_a_dwarf_happy() -> void:
	_hall(Rect2i(14, 6, 5, 1))
	_supply(SimFactory.MEAL, 1, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	assert_ne(_run_until_eating(400), Vector2i(-1, -1))
	assert_eq(_dwarf.need_quality[SimFactory.FOOD], 1)
	_run_until_up(100)
	assert_eq(_dwarf.mood, Dwarf.Mood.GOOD)


func test_going_hungry_is_worse_than_making_do() -> void:
	# Nothing to eat at all: hunger runs out and outweighs a bunk slept in.
	_dwarf.need_quality[SimFactory.SLEEP] = 1
	_dwarf.needs[SimFactory.FOOD] = 0.05
	_dwarf.needs[SimFactory.SLEEP] = 1.0
	SimFactory.run(_sim, 40)
	assert_eq(_dwarf.needs[SimFactory.FOOD], 0.0)
	assert_eq(_dwarf.mood, Dwarf.Mood.BAD)
	assert_eq(_dwarf.speech, "hungry!")


func test_kitchen_cooks_to_keep_a_meal_in_stock() -> void:
	_hall(Rect2i(14, 6, 5, 1))
	_kitchen(Rect2i(1, 6, 4, 1))
	_supply(SimFactory.MUSHROOM, 6, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 1.0
	SimFactory.run(_sim, 150)
	var meals: int = _sim.storage.available_total(SimFactory.MEAL) + _sim.loose_unassigned_count(SimFactory.MEAL)
	assert_eq(meals, 1, "one in stock, as the need asks for, and no more")


func test_hungry_dwarf_fetches_a_meal_to_a_seat_and_eats_it() -> void:
	var hall := _hall(Rect2i(14, 6, 5, 1))
	_kitchen(Rect2i(1, 6, 4, 1))
	_supply(SimFactory.MEAL, 2, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	var ate_at: Vector2i = _run_until_eating(400)
	assert_ne(ate_at, Vector2i(-1, -1), "ate")
	assert_eq(_dwarf.speech, "nom")
	assert_null(_dwarf.carrying, "the meal is gone once eating starts")
	assert_true(hall.rect.has_point(ate_at), "at the hall")
	assert_true(hall.slots.any(func(slot: RoomSlot) -> bool: return slot.def.seat and slot.tile == ate_at), "on a chair")
	assert_eq(_sim.storage.totals[SimFactory.MEAL], 1, "one meal used up")
	_run_until_up(100)
	assert_gt(_dwarf.needs[SimFactory.FOOD], 0.9, "fed")
	assert_eq(_own_requests(), 0, "nothing left asking for the dwarf")
	assert_null(_dwarf.seat)
	for slot: RoomSlot in hall.slots:
		assert_eq(slot.occupant, -1)


## Ticks until the dwarf is eating. Returns where, or (-1, -1) if they never did.
func _run_until_eating(limit: int) -> Vector2i:
	for i in limit:
		_sim.tick()
		if _dwarf.activity == Dwarf.Activity.REST and _dwarf.restoring == SimFactory.FOOD:
			return _dwarf.pos
	return Vector2i(-1, -1)


func _run_until_up(limit: int) -> void:
	for i in limit:
		_sim.tick()
		if _dwarf.activity != Dwarf.Activity.REST:
			return


## Requests dwarves made for their own meals.
func _own_requests() -> int:
	var count: int = 0
	for request: Request in _sim.logistics.requests:
		if request.owner_dwarf_id != -1:
			count += 1
	return count


func test_meal_is_fetched_from_the_kitchen_output_pile() -> void:
	_hall(Rect2i(14, 6, 5, 1))
	var kitchen := _kitchen(Rect2i(1, 6, 4, 1))
	_sim.storage.put(kitchen.slots[1].pile, SimFactory.MEAL)
	_dwarf.needs[SimFactory.FOOD] = 0.3
	assert_ne(_run_until_eating(400), Vector2i(-1, -1), "ate")
	_run_until_up(100)
	assert_gt(_dwarf.needs[SimFactory.FOOD], 0.9)
	assert_eq(kitchen.slots[1].pile.count_of(SimFactory.MEAL), 0)


func test_no_meal_anywhere_means_hungry_and_a_request() -> void:
	_hall(Rect2i(14, 6, 5, 1))
	_kitchen(Rect2i(1, 6, 4, 1))
	SimFactory.run(_sim, 900)
	assert_eq(_dwarf.needs[SimFactory.FOOD], 0.0)
	assert_eq(_dwarf.mood, Dwarf.Mood.BAD)
	assert_eq(_dwarf.speech, "hungry!")
	var reported: bool = false
	for entry: RequestEntry in _sim.requests.entries:
		reported = reported or entry.message.contains("nothing to eat")
	assert_true(reported)


func test_mushrooms_to_meals_to_dwarf_end_to_end() -> void:
	SimFactory.place_dwarf(_sim.hire_dwarf(), Vector2i(11, 6))
	_hall(Rect2i(14, 6, 5, 1))
	_kitchen(Rect2i(1, 6, 4, 1))
	_supply(SimFactory.MUSHROOM, 10, Vector2i(8, 6))
	for dwarf: Dwarf in _sim.dwarves:
		dwarf.needs[SimFactory.FOOD] = 0.3
	var fed: Dictionary[int, bool] = {}
	for i in 1500:
		_sim.tick()
		for dwarf: Dwarf in _sim.dwarves:
			if dwarf.activity == Dwarf.Activity.REST and dwarf.restoring == SimFactory.FOOD:
				fed[dwarf.id] = true
	assert_eq(fed.size(), 2, "both got fed")
	assert_lt(_sim.storage.totals[SimFactory.MUSHROOM], 10, "mushrooms were cooked")


func test_nobody_else_fetches_a_dwarfs_own_meal() -> void:
	var other := _sim.hire_dwarf()
	SimFactory.place_dwarf(other, Vector2i(11, 6))
	_hall(Rect2i(14, 6, 5, 1))
	_kitchen(Rect2i(1, 6, 4, 1))
	_supply(SimFactory.MEAL, 3, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	other.needs[SimFactory.FOOD] = 1.0
	var carried_a_meal: bool = false
	for i in 120:
		_sim.tick()
		if other.carrying != null and other.carrying.type == SimFactory.MEAL:
			carried_a_meal = true
	assert_false(carried_a_meal, "the other dwarf, not hungry, never carries a meal")
	assert_gt(_dwarf.needs[SimFactory.FOOD], 0.3, "while the hungry one got theirs")

func test_a_need_that_cannot_be_met_does_not_stop_the_next_one() -> void:
	# Thirsty with nothing to drink anywhere, and hungry with meals on hand.
	var drink := NeedDef.new()
	drink.id = &"drink"
	drink.display_name = "Drink"
	drink.decay_ticks = SimFactory.SLOW
	drink.seek_below = 0.4
	drink.provider = &"dining"
	drink.consumes = [_sim.config.items[SimFactory.STONE_BALL]]
	drink.no_item_message = "nothing to drink."
	_sim.config.needs.append(drink)
	_dwarf.needs.append(0.05)
	_dwarf.need_quality.append(0)
	_hall(Rect2i(14, 6, 5, 1))
	_supply(SimFactory.MEAL, 2, Vector2i(8, 6))
	_dwarf.needs[SimFactory.FOOD] = 0.3
	assert_ne(_run_until_eating(400), Vector2i(-1, -1), "still goes and eats")
