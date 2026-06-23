extends RefCounted
class_name Attributes
## The 13 HoopClone attributes. This list and ordering MUST stay in lockstep
## with tools/data/schema.py (ATTRIBUTES) so exported roster JSON maps 1:1.

const NAMES: Array[String] = [
	"shooting", "three_pt", "finishing", "dunking", "passing", "handles",
	"steals", "hustle", "hops", "rebounding", "perim_d", "inside_d", "speed",
]

var values: Dictionary = {}

func _init(initial: Dictionary = {}) -> void:
	for n in NAMES:
		values[n] = int(initial.get(n, 50))

func get_attr(name: String) -> int:
	return int(values.get(name, 50))

## 0-99 attribute -> 0.0-1.0 normalised modifier, handy for physics scaling.
func mod(name: String) -> float:
	return clampf(get_attr(name) / 99.0, 0.0, 1.0)

func overall() -> int:
	var total := 0
	for n in NAMES:
		total += get_attr(n)
	return clampi(roundi(float(total) / NAMES.size()), 0, 99)

## Build from a player entry in exported roster JSON.
static func from_json(entry: Dictionary) -> Attributes:
	return Attributes.new(entry.get("attributes", {}))
