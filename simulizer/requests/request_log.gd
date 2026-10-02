class_name RequestLog
extends RefCounted
## Problems dwarves report to the player. Deduped by key and refreshed, not spammed.

signal changed

var entries: Array[RequestEntry] = []

var _by_key: Dictionary[StringName, RequestEntry] = {}


## Adds a request, or refreshes the existing one with the same key.
## A repeat inside refresh_ticks of the last one is ignored.
func post(key: StringName, dwarf_name: String, message: String, tick: int, refresh_ticks: int) -> void:
	var entry: RequestEntry = _by_key.get(key)
	if entry == null:
		entry = RequestEntry.new()
		entry.key = key
		entry.first_tick = tick
		_by_key[key] = entry
		entries.append(entry)
	elif tick - entry.last_tick < refresh_ticks:
		return
	else:
		entry.count += 1
	entry.dwarf_name = dwarf_name
	entry.message = message
	entry.last_tick = tick
	changed.emit()


func clear() -> void:
	entries.clear()
	_by_key.clear()
	changed.emit()
