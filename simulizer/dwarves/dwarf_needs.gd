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


## A need is in play once something in the hold can satisfy it.
func is_active(sim: Simulation, need: NeedDef) -> bool:
	return sim.rooms.provider_count(need.id) > 0


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
