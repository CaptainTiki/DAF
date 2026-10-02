class_name RequestEntry
extends RefCounted
## One line in the requests log. Repeats of the same problem bump count instead of adding lines.

var key: StringName
var dwarf_name: String
var message: String
var first_tick: int
var last_tick: int
var count: int = 1
