class_name MaterialDef
extends Resource
## Definition of one tile material and what it yields when dug.

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
## Sim ticks a dwarf needs to dig one tile of this material.
@export_range(1, 2000) var dig_ticks: int = 30
## Standing order: dwarves mine this wherever they uncover it (ore).
@export var auto_mine: bool = false
## Item dropped when a tile of this material is dug.
@export var drop: ItemDef
