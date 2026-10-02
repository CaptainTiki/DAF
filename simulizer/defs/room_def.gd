class_name RoomDef
extends Resource
## A type of room. The player only chooses the type and where it goes; what the
## room contains is worked out from its width using the layout below.

@export var id: StringName
@export var display_name: String
## For grouping in the room picker.
@export var category: StringName = &"general"
@export var color: Color = Color(0.6, 0.5, 0.8)
@export var min_width: int = 3
## Open tiles from floor to ceiling.
@export var min_height: int = 3

@export_group("Layout")
## Floor tiles left empty at each end of the room.
@export var margin: int = 0
## The slots below repeat every this many tiles along the floor.
@export var pattern_width: int = 1
@export var slots: Array[SlotDef] = []
