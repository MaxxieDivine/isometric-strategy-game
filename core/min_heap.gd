class_name MinHeap
extends RefCounted
## Binary min-heap of int items keyed by float priority.

var _items := PackedInt32Array()
var _priorities := PackedFloat64Array()


func is_empty() -> bool:
	return _items.is_empty()


func push(item: int, priority: float) -> void:
	_items.append(item)
	_priorities.append(priority)
	var i := _items.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _priorities[parent] <= _priorities[i]:
			break
		_swap(i, parent)
		i = parent


func pop() -> int:
	var top := _items[0]
	var last := _items.size() - 1
	_swap(0, last)
	_items.resize(last)
	_priorities.resize(last)
	var i := 0
	while true:
		var smallest := i
		var left := 2 * i + 1
		var right := left + 1
		if left < last and _priorities[left] < _priorities[smallest]:
			smallest = left
		if right < last and _priorities[right] < _priorities[smallest]:
			smallest = right
		if smallest == i:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var item := _items[a]
	_items[a] = _items[b]
	_items[b] = item
	var priority := _priorities[a]
	_priorities[a] = _priorities[b]
	_priorities[b] = priority
