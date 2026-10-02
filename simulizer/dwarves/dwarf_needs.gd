class_name DwarfNeeds
extends RefCounted
## Runs dwarves' needs down, works out mood from them, and decides what a
## dwarf is saying. Stateless: the values live on the Dwarf.
##
## Mood is a sum over needs. Each need counts how well it was last met: -1 for
## the floor, 0 for plain fare, 1 for a bunk or a proper meal at a table. A
## need that has run out counts -2 instead, so going without is worse than
## making do. Below zero is a bad mood, above zero good, zero is ok.

## What a need that has run out adds to the mood sum.
const RAN_OUT: int = -2


## Call once per tick per dwarf.
func tick(sim: Simulation, dwarf: Dwarf) -> void:
	var needs: Array[NeedDef] = sim.config.needs
	var score: int = 0
	var unmet: NeedDef = null
	for i in needs.size():
		var need: NeedDef = needs[i]
		var resting: bool = dwarf.activity == Dwarf.Activity.REST and dwarf.restoring == i
		if not resting:
			dwarf.needs[i] = maxf(dwarf.needs[i] - 1.0 / need.decay_ticks, 0.0)
		if dwarf.needs[i] <= 0.0:
			score += RAN_OUT
			if unmet == null:
				unmet = need
		else:
			score += dwarf.need_quality[i]

	if score < 0:
		dwarf.mood = Dwarf.Mood.BAD
	elif score > 0:
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


## How many of an item type dwarves are about to want for a need: those who
## need it and haven't set off for one yet, plus the stock kept ready. Only
## the best thing for a need is asked for; the rest are what dwarves make do with.
func demand_for(sim: Simulation, type: int) -> int:
	var total: int = 0
	var needs: Array[NeedDef] = sim.config.needs
	for i in needs.size():
		var need: NeedDef = needs[i]
		if need.consumes.is_empty() or sim.item_type(need.consumes[0]) != type:
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
		if dwarf.needs[i] >= needs[i].seek_below:
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
