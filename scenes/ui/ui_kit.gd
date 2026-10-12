extends RefCounted
## How the interface looks, in one place: the colours, the lettering, the theme every panel
## and button wears, and the few things that are drawn rather than laid out.
##
## The look is the street's own: asphalt-dark panels, lettering the colour of sand, the yellow
## of the national shirt for what matters, sea green for what you hold and guaraná red for
## what hurts. The one flourish is the black and white wave of the Copacabana pavement, which
## runs along the top of the two panels at the foot of the screen and nowhere else.

const ASPHALT := Color(0.078, 0.094, 0.122)
const ASPHALT_LIT := Color(0.15, 0.175, 0.215)
const SAND := Color(0.965, 0.914, 0.784)
const CANARY := Color(1.0, 0.824, 0.118)
const SEA := Color(0.098, 0.71, 0.647)
const GUARANA := Color(0.898, 0.204, 0.227)
const DIM := Color(0.965, 0.914, 0.784, 0.6)
## How far in from the edge of the screen anything sits.
const EDGE := 24.0

static var _fonts := {}
static var _theme: Theme


## The lettering: `bold` for numbers and headings, the lighter cut for everything else.
static func font(bold := false) -> Font:
	if not _fonts.has(bold):
		var path := "res://assets/fonts/BarlowCondensed-%s.ttf" % ("Bold" if bold else "SemiBold")
		_fonts[bold] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[bold]


static func box(bg: Color, radius := 4, margin := 8.0, border := Color(0, 0, 0, 0), width := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.border_color = border
	s.set_border_width_all(width)
	return s


## A panel standing on the screen over the game: dark enough to read on, not so dark it hides it.
static func plate(alpha := 0.82) -> StyleBoxFlat:
	return box(Color(ASPHALT.r, ASPHALT.g, ASPHALT.b, alpha), 3, 10.0)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 20
	t.set_color("font_color", "Label", SAND)
	# Panels: the menu, the shop, the scoreboard.
	var panel := box(Color(ASPHALT.r, ASPHALT.g, ASPHALT.b, 0.95), 4, 16.0, CANARY, 0)
	panel.border_width_top = 4
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupMenu", box(ASPHALT, 4, 6.0, ASPHALT_LIT, 1))
	t.set_stylebox("panel", "PopupPanel", box(ASPHALT, 4, 6.0, ASPHALT_LIT, 1))
	t.set_color("font_color", "PopupMenu", SAND)
	t.set_color("font_hover_color", "PopupMenu", CANARY)
	# Buttons: quiet until the mouse is on them, yellow when it is.
	for kind in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		var plain: bool = kind.begins_with("Check")
		t.set_stylebox("normal", kind, box(Color(0, 0, 0, 0) if plain else ASPHALT_LIT, 3, 9.0))
		t.set_stylebox("hover", kind, box(ASPHALT_LIT.lightened(0.08), 3, 9.0, CANARY, 0 if plain else 2))
		t.set_stylebox("pressed", kind, box(Color(0, 0, 0, 0) if plain else CANARY, 3, 9.0))
		t.set_stylebox("hover_pressed", kind, box(Color(0, 0, 0, 0) if plain else CANARY, 3, 9.0))
		t.set_stylebox("disabled", kind, box(Color(ASPHALT_LIT.r, ASPHALT_LIT.g, ASPHALT_LIT.b, 0.4), 3, 9.0))
		t.set_stylebox("focus", kind, box(Color(0, 0, 0, 0), 3, 9.0, SEA, 2))
		t.set_color("font_color", kind, SAND)
		t.set_color("font_hover_color", kind, CANARY)
		t.set_color("font_pressed_color", kind, SAND if plain else ASPHALT)
		t.set_color("font_hover_pressed_color", kind, CANARY if plain else ASPHALT)
		t.set_color("font_focus_color", kind, SAND)
		t.set_color("font_disabled_color", kind, DIM)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 3, 9.0, ASPHALT_LIT, 2))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.35), 3, 9.0, SEA, 2))
	t.set_color("font_color", "LineEdit", SAND)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", CANARY)
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), 2, 0.0))
	t.set_stylebox("fill", "ProgressBar", box(SEA, 2, 0.0))
	var groove := box(Color(0, 0, 0, 0.5), 3, 0.0)
	groove.content_margin_top = 3.0
	groove.content_margin_bottom = 3.0
	t.set_stylebox("slider", "HSlider", groove)
	var run := box(SEA, 3, 0.0)
	run.content_margin_top = 3.0
	run.content_margin_bottom = 3.0
	t.set_stylebox("grabber_area", "HSlider", run)
	t.set_stylebox("grabber_area_highlight", "HSlider", run)
	_theme = t
	return t


## A line of lettering, sized and coloured, with a dark edge so it reads over sand and sky.
static func label(size: int, color := SAND, bold := false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


## The biggest size up to `size` at which the widest line of `text` fits in `width`, and no
## smaller than `least`: below that it is left to wrap.
static func fit_size(text: String, size: int, width: float, bold := true, least := 20) -> int:
	var f := font(bold)
	var widest := ""
	for line in text.split("\n"):
		if line.length() > widest.length():
			widest = line
	while size > least and f.get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 2
	return size


## The pavement of Copacabana, as a strip: black, with the white wave running through it.
class Wave extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.03, 0.04))
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w + 2.0:
			pts.append(Vector2(x, h * 0.5 + sin(x * 0.19) * h * 0.24))
			x += 2.0
		if pts.size() > 1:
			draw_polyline(pts, Color(0.97, 0.97, 0.95), h * 0.34, true)


## A bar that empties: health. What has just been lost lingers pale for a moment before it
## goes, and when there is little left the whole thing pulses.
class Meter extends Control:
	var value := 1.0
	var color := GUARANA
	var _lag := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(250, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_lag = maxf(value, move_toward(_lag, value, delta * 0.45))
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, 0, w * clampf(_lag, 0.0, 1.0), h), Color(1, 1, 1, 0.85))
		var c := color
		if value < 0.3:
			c = c.lerp(Color(1, 1, 1), 0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))
		draw_rect(Rect2(0, 0, w * clampf(value, 0.0, 1.0), h), c)
		# Quarters, so a glance says how many more of those you can take.
		for k in range(1, 4):
			draw_rect(Rect2(w * k * 0.25 - 1.0, 0, 2.0, h), Color(0, 0, 0, 0.45))


## The middle of the screen: the crosshair, which opens up when the gun is unsteady, and the
## flick across it when something has been hit.
class Reticle extends Control:
	## How wide the gun would scatter right now, as a fraction of the screen's height.
	var spread := 0.0
	var show_cross := true
	var _open := 0.0
	var _hit_t := 9.0
	var _hit_len := 0.2
	var _hit_color := Color.WHITE
	var _hit_big := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(head: bool, kill: bool) -> void:
		_hit_t = 0.0
		_hit_len = 0.42 if kill else (0.3 if head else 0.2)
		_hit_color = GUARANA if kill else (CANARY if head else Color.WHITE)
		_hit_big = kill or head
		_open += 6.0

	func _process(delta: float) -> void:
		_open = lerpf(_open, spread * size.y, minf(1.0, 14.0 * delta))
		_hit_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		if show_cross:
			var gap := 5.0 + _open
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * gap, c + d * (gap + 8.0), Color(0, 0, 0, 0.7), 4.0)
				draw_line(c + d * gap, c + d * (gap + 8.0), Color(1, 1, 1, 0.95), 2.0)
			draw_circle(c, 2.2, Color(0, 0, 0, 0.7))
			draw_circle(c, 1.2, Color(1, 1, 1, 0.95))
		if _hit_t < _hit_len:
			# Four ticks on the diagonals that jump out and fade.
			var u := _hit_t / _hit_len
			var inner := (9.0 if _hit_big else 7.0) + u * 5.0
			var outer := inner + (13.0 if _hit_big else 9.0)
			var col := _hit_color
			col.a = 1.0 - u * u
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var n: Vector2 = d.normalized()
				draw_line(c + n * inner, c + n * outer, Color(0, 0, 0, col.a * 0.7), 5.0)
				draw_line(c + n * inner, c + n * outer, col, 3.0 if _hit_big else 2.0)
