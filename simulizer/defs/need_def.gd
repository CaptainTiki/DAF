class_name NeedDef
extends Resource
## Something a dwarf needs from time to time: sleep, and later food, drink, fun.
##
## A need is asleep until the hold has somewhere to satisfy it (a room slot
## whose `satisfies` matches `provider`) and, if it consumes something, a way
## to make that. Until then it never runs down, so nobody suffers for
## something the player has no way to provide yet.

@export var id: StringName
@export var display_name: String
## Ticks for the need to run from fully met down to empty.
@export var decay_ticks: int = 9600
## Ticks to go from empty back to fully met while it is being satisfied.
@export var restore_ticks: int = 1200
## A dwarf goes to satisfy the need once it drops below this (0..1).
@export_range(0.0, 1.0) var seek_below: float = 0.35
## Room slots with this in `satisfies` are where the need is seen to. A bunk
## for sleep, a dining seat for food and drink.
@export var provider: StringName
## The first dwarf to use a provider keeps it (a bunk). Otherwise anyone may use any.
@export var owned: bool = false
## Something the dwarf has to fetch and use up at the provider: a meal, a drink.
## Null for needs that only take time there, like sleep.
@export var consumes: ItemDef
## How many of the consumed item the hold tries to keep ready beyond what is
## being asked for right now.
@export var stock_target: int = 2
## What the dwarf reports when the item can't be found anywhere.
@export var no_item_message: String = "nothing to eat."
## Shown over the dwarf while the need is being satisfied.
@export var using_speech: String = "Zzz"
## Shown over the dwarf when the need has run out.
@export var unmet_speech: String = "tired!"
## What the dwarf reports in the requests log when there is nowhere to go.
@export var no_provider_message: String = "no free bed. Build more bunks."
