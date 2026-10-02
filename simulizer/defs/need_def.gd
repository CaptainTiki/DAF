class_name NeedDef
extends Resource
## Something a dwarf needs from time to time: sleep, and later food, drink, fun.
##
## Needs are always in play. What the hold provides decides how well they are
## met: a bunk or the floor, a meal at a table or a raw mushroom on the floor,
## or nothing at all. That is what moves mood.

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
## Things the dwarf fetches and uses up to satisfy the need, best first: a meal,
## then a raw mushroom. Empty for needs that only take time, like sleep.
## Stations are asked to make the first one.
@export var consumes: Array[ItemDef] = []
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
@export var no_provider_message: String = "no free bunk. Sleeping on the floor."
