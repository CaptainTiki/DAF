class_name MaterialDef
extends Resource
## Definition of one tile material and what it yields when dug.

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
## Sim ticks a dwarf needs to dig one tile of this material.
@export_range(1, 2000) var dig_ticks: int = 30
## Material of the resource ball dropped when dug. Null drops this same material.
@export var drop: MaterialDef
