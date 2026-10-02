class_name RecipeDef
extends Resource
## Something a station can make: inputs in, one output out.

## Kind of station that makes this, matched against SlotDef.station_type.
@export var station_type: StringName
@export var input: ItemDef
@export var input_count: int = 1
@export var output: ItemDef
@export var work_ticks: int = 120
