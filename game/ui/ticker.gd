extends Control
class_name NewsTicker
## Horizontal news ticker (top-left): pops in, scrolls one headline across, then
## slides out and re-fires. Headlines come from the Python live service. Mirrors
## the locked sandbox behaviour (pop-in + 9s scroll + dismiss, re-fire ~12s).
## Expects: %Track (Label inside a clipping container), self starts hidden.

@export var service_url: String = "http://127.0.0.1:8777/news"
@export var scroll_seconds: float = 9.0
@export var refire_seconds: float = 12.0
@export var scroll_width: float = 520.0

@onready var _http: HTTPRequest = HTTPRequest.new()
@onready var _track: Label = get_node_or_null("%Track")
var _headlines: Array = []
var _idx: int = 0
var _refire: float = 0.0

func _ready() -> void:
	add_child(_http)
	_http.request_completed.connect(_on_news)
	modulate.a = 0.0
	_http.request(service_url)
	_refire = refire_seconds

func _process(delta: float) -> void:
	_refire += delta
	if _refire >= refire_seconds and not _headlines.is_empty():
		_refire = 0.0
		_pop_next()

func _on_news(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) == TYPE_DICTIONARY:
		_headlines = data.get("headlines", [])

func _pop_next() -> void:
	if _track == null or _headlines.is_empty():
		return
	_track.text = String(_headlines[_idx % _headlines.size()])
	_idx += 1
	var tw := create_tween()
	# pop in
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	# scroll the track from right edge to fully off the left
	_track.position.x = scroll_width
	var t2 := create_tween()
	t2.tween_property(_track, "position:x", -scroll_width, scroll_seconds)
	# slide out after the scroll
	var t3 := create_tween()
	t3.tween_interval(scroll_seconds)
	t3.tween_property(self, "modulate:a", 0.0, 0.35)
