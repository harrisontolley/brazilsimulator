extends Node
## Server-side event bus for things police and other players can notice.

signal noise(pos: Vector3, radius: float, pid: int)
## severity: 1 robbery, 2 assault, 3 gunfire / killing
signal crime(pos: Vector3, pid: int, severity: int)


func report_noise(pos: Vector3, radius: float, pid: int) -> void:
	noise.emit(pos, radius, pid)


func report_crime(pos: Vector3, pid: int, severity: int) -> void:
	crime.emit(pos, pid, severity)
