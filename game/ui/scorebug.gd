extends Control
class_name Scorebug
## NBC/Peacock-style scorebug (bottom-right). Polls the Python live service for
## the current game and updates labels. Pure data display — no game logic.
## Expects child labels: %Away, %Home, %AwayScore, %HomeScore, %Clock.

@export var service_url: String = "http://127.0.0.1:8777/scores"
@export var poll_seconds: float = 3.0

@onready var _http: HTTPRequest = HTTPRequest.new()
var _timer: float = 0.0

func _ready() -> void:
	add_child(_http)
	_http.request_completed.connect(_on_scores)
	_request()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= poll_seconds:
		_timer = 0.0
		_request()

func _request() -> void:
	if _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http.request(service_url)

func _on_scores(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var games: Array = data.get("games", [])
	if games.is_empty():
		return
	var g: Dictionary = games[0]
	_set_label("%Away", g.get("away", "AWY"))
	_set_label("%Home", g.get("home", "HOM"))
	_set_label("%AwayScore", str(g.get("away_score", 0)))
	_set_label("%HomeScore", str(g.get("home_score", 0)))
	_set_label("%Clock", g.get("status", ""))

func _set_label(path: String, text: String) -> void:
	var n := get_node_or_null(path)
	if n is Label:
		(n as Label).text = text
