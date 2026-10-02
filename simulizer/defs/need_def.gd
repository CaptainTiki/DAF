class_name NeedDef
extends Resource
## Something a dwarf needs from time to time: sleep, and later food, drink, fun.
##
## A need is asleep until the hold has something that can satisfy it (a room
## slot whose `satisfies` matches this id). Until then it never runs down, so
## nobody suffers for something the player has no way to provide yet.

@export var id: StringName
@export var display_name: String
## Ticks for the need to run from fully met down to empty.
@export var decay_ticks: int = 9600
## Ticks to go from empty back to fully met while it is being satisfied.
@export var restore_ticks: int = 1200
## A dwarf goes to satisfy the need once it drops below this (0..1).
@export_range(0.0, 1.0) var seek_below: float = 0.35
## Shown over the dwarf while the need is being satisfied.
@export var using_speech: String = "Zzz"
## Shown over the dwarf when the need has run out.
@export var unmet_speech: String = "tired!"
## What the dwarf reports in the requests log when there is nowhere to go.
@export var no_provider_message: String = "no free bed. Build more bunks."
