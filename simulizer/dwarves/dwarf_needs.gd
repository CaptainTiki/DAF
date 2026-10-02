class_name DwarfNeeds
extends RefCounted
## Runs dwarves' needs down, works out mood from them, and decides what a
## dwarf is saying. Stateless: the values live on the Dwarf.
##
## Mood has three levels. Bad: some need has run out. Good: at least one need
## is in play and every one of them is comfortably met. Ok: anything else,
## including a hold where no need is in play yet.

## A need at or above this counts as comfortably met.
const COMFORTABLE: float = 0.5


## Call once per tick per dwarf.
func tick(sim: Simulation, dwarf: Dwarf) -> void:
	var needs: Array[NeedDef] = sim.config.needs
	var any_active: bool = false
	var all_comfortable: bool = true
	var unmet: NeedDef = null
	for i in needs.size():
		var need: NeedDef = needs[i]
		if not is_active(sim, need):
			continue
		any_active = true
		var resting: bool = dwarf.activity == Dwarf.Activity.REST and dwarf.restoring == i
		if not resting:
			dwarf.needs[i] = maxf(dwarf.needs[i] - 1.0 / need.decay_ticks, 0.0)
		if dwarf.needs[i] <= 0.0 and unmet == null:
			unmet = need
		if dwarf.needs[i] < COMFORTABLE:
			all_comfortable = false

	if unmet != null:
		dwarf.mood = Dwarf.Mood.BAD
	elif any_active and all_comfortable:
		dwarf.mood = Dwarf.Mood.GOOD
	else:
		dwarf.mood = Dwarf.Mood.OK

	if dwarf.trapped:
		dwarf.speech = "!"
	elif dwarf.activity == Dwarf.Activity.REST and dwarf.restoring >= 0:
		dwarf.speech = needs[dwarf.restoring].using_speech
	elif unmet != null:
		dwarf.speech = unmet.unmet_speech
	else:
		dwarf.speech = ""


## A need is in play once the hold has somewhere to see to it and, if it
## consumes something, a way to make that or some already to hand.
func is_active(sim: Simulation, need: NeedDef) -> bool:
	if sim.rooms.provider_count(need.provider) == 0:
		return false
	if need.consumes == null:
		return true
	var type: int = sim.item_type(need.consumes)
	return sim.rooms.can_make(sim, type) or sim.storage.available_total(type) > 0 or sim.loose_unassigned_count(type) > 0


## How many of an item type dwarves are about to want for a need: those who
## need it and haven't set off for one yet, plus the stock kept ready.
func demand_for(sim: Simulation, type: int) -> int:
	var total: int = 0
	var needs: Array[NeedDef] = sim.config.needs
	for i in needs.size():
		var need: NeedDef = needs[i]
		if need.consumes == null or sim.item_type(need.consumes) != type or not is_active(sim, need):
			continue
		total += need.stock_target
		for dwarf: Dwarf in sim.dwarves:
			if dwarf.needs[i] < need.seek_below and dwarf.restoring != i:
				total += 1
	return total


## Index of the need this dwarf should go and see to now, or -1.
## The lowest one below its seek level wins.
func most_pressing(sim: Simulation, dwarf: Dwarf) -> int:
	var needs: Array[NeedDef] = sim.config.needs
	var best: int = -1
	for i in needs.size():
		if not is_active(sim, needs[i]) or dwarf.needs[i] >= needs[i].seek_below:
			continue
		if best < 0 or dwarf.needs[i] < dwarf.needs[best]:
			best = i
	return best


## How much longer or shorter this dwarf's walking and working take, from mood.
func pace_factor(sim: Simulation, dwarf: Dwarf) -> float:
	match dwarf.mood:
		Dwarf.Mood.BAD:
			return sim.config.bad_mood_pace
		Dwarf.Mood.GOOD:
			return sim.config.good_mood_pace
	return 1.0
