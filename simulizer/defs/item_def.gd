class_name ItemDef
extends Resource
## One type of thing that can be carried and stored: a resource ball, a log,
## a piece of furniture.

enum Shape { BALL, LOG, CHAIR, TABLE, BED }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
## Storage units one of these takes up. A pile holds a fixed number of units.
@export_range(1, 100) var size: int = 1
## How the view draws it.
@export var shape: Shape = Shape.BALL
