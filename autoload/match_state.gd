extends Node
## Match clock and seed. Server drives it; clients run the clock locally and get corrected.

var seed_value := 0
var time := 0.0
var duration := 900.0
var ended := false
var running := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duration="):
			duration = float(a.trim_prefix("--duration="))


func _process(delta: float) -> void:
	if running and not ended:
		time += delta


func time_left() -> float:
	return maxf(0.0, duration - time)
