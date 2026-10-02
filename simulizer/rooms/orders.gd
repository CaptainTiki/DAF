class_name Orders
extends RefCounted
## Works out what needs making. Nobody queues orders by hand: whenever places
## are asking for more of an item than exists or is already being made, the
## difference becomes pending orders for stations to pick up.

var _pending: Dictionary[RecipeDef, int] = {}


func update(sim: Simulation) -> void:
	for recipe: RecipeDef in sim.config.recipes:
		var type: int = sim.item_type(recipe.output)
		var wanted: int = sim.logistics.open_count_of(type) + sim.needs.demand_for(sim, type)
		var on_hand: int = sim.storage.available_total(type) + sim.loose_unassigned_count(type)
		_pending[recipe] = maxi(wanted - on_hand - sim.rooms.in_production(recipe), 0)


## Hands one pending order to a station of this type, or null if there is none.
func take(station_type: StringName) -> RecipeDef:
	for recipe: RecipeDef in _pending:
		if recipe.station_type == station_type and _pending[recipe] > 0:
			_pending[recipe] -= 1
			return recipe
	return null


func pending_count() -> int:
	var total: int = 0
	for recipe: RecipeDef in _pending:
		total += _pending[recipe]
	return total
