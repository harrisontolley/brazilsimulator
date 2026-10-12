extends Control
## The emote wheel: eight slices round the middle of the screen while the key is held, the
## mouse pushing a pointer toward one of them, and whatever it is on when the key comes up is
## what the body does. Scrolling turns to the other page.
##
## Each slice shows its emote as a stick figure worked out from the emote's own pose, so the
## picture is never out of date; the one under the pointer dances.

const UI := preload("res://scenes/ui/ui_kit.gd")
const Emotes := preload("res://scenes/characters/emotes.gd")

## Pixels on a 900-high screen: where the slices start and end, how far the pointer can be
## pushed, and how far it has to go before it is choosing anything.
const INNER := 92.0
const OUTER := 262.0
const THROW := 150.0
const DEAD := 40.0
## Pixels to a metre of stick figure.
const FIGURE := 36.0

var open := false
var page := 0

var _at := Vector2.ZERO
var _t := 0.0
var _in := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


static func pages() -> int:
	return ceili(float(Emotes.COUNT) / Emotes.PAGE)


## Which slice a pointer pushed to `v` (screen axes, from the middle) is on, 0 at the top and
## on round clockwise, or -1 while it is still in the middle.
static func slot_of(v: Vector2) -> int:
	if v.length() < DEAD:
		return -1
	return int(fposmod(atan2(v.x, -v.y) + PI / Emotes.PAGE, TAU) / (TAU / Emotes.PAGE)) % Emotes.PAGE


func open_up() -> void:
	open = true
	visible = true
	_at = Vector2.ZERO
	_in = 0.0
	_t = 0.0


## Puts the wheel away. The emote that was chosen, or -1 for none.
func close() -> int:
	var got := picked()
	open = false
	visible = false
	return got


## The emote under the pointer, or -1.
func picked() -> int:
	var slot := slot_of(_at)
	var id := page * Emotes.PAGE + slot
	return id if open and slot >= 0 and Emotes.has(id) else -1


## The mouse moved by `rel`.
func push(rel: Vector2) -> void:
	point(_at + rel)


## Puts the pointer at `v` from the middle.
func point(v: Vector2) -> void:
	_at = v.limit_length(THROW)


func turn_page(by: int) -> void:
	page = posmod(page + by, pages())


func _process(delta: float) -> void:
	if not open:
		return
	_t += delta
	_in = minf(1.0, _in + delta / 0.12)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var s := size.y / 900.0 * lerpf(0.86, 1.0, _in * (2.0 - _in))
	var hot := slot_of(_at)
	var fade := _in
	var wedge := TAU / Emotes.PAGE
	draw_circle(c, (OUTER + 26.0) * s, Color(0, 0, 0, 0.28 * fade))
	for k in Emotes.PAGE:
		var id := page * Emotes.PAGE + k
		var lit := k == hot and Emotes.has(id)
		var mid := k * wedge - PI / 2.0
		var grow := 10.0 if lit else 0.0
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(c + Vector2.from_angle(mid - wedge * 0.5 + 0.022 + (wedge - 0.044) * i / 12.0) * (OUTER + grow) * s)
		for i in 13:
			pts.append(c + Vector2.from_angle(mid + wedge * 0.5 - 0.06 - (wedge - 0.12) * i / 12.0) * INNER * s)
		var fill := UI.ASPHALT_LIT if lit else UI.ASPHALT
		draw_colored_polygon(pts, Color(fill.r, fill.g, fill.b, (0.96 if lit else 0.86) * fade))
		if lit:
			pts.append(pts[0])
			draw_polyline(pts, UI.CANARY, 3.0 * s, true)
		if not Emotes.has(id):
			continue
		var e: Dictionary = Emotes.LIST[id]
		var ink := UI.CANARY if lit else UI.SAND
		ink.a = fade
		var mid_at := c + Vector2.from_angle(mid) * (INNER + OUTER + grow) * 0.5 * s
		# The one being pointed at dances; the rest hold the moment that says what they are.
		_figure(id, fposmod(_t, e.len) if lit else e.len * e.get("show", 0.4), mid_at - Vector2(0, 12.0 * s), FIGURE * s * (1.12 if lit else 1.0), ink)
		var font := UI.font(true)
		var px := int(15.0 * s)
		draw_string(font, mid_at + Vector2(-70.0 * s, 46.0 * s), e.name, HORIZONTAL_ALIGNMENT_CENTER, 140.0 * s, px, ink)

	# The middle: what letting go now would do.
	draw_circle(c, (INNER - 10.0) * s, Color(UI.ASPHALT.r, UI.ASPHALT.g, UI.ASPHALT.b, 0.9 * fade))
	var got := picked()
	var font := UI.font(true)
	var title: String = Emotes.LIST[got].name if got >= 0 else "EMOTES"
	draw_string(font, c + Vector2(-INNER * s, 2.0 * s), title, HORIZONTAL_ALIGNMENT_CENTER, INNER * 2.0 * s, int(22.0 * s), UI.CANARY if got >= 0 else UI.SAND)
	draw_string(UI.font(false), c + Vector2(-INNER * s, 24.0 * s), "let go to play" if got >= 0 else "scroll: more", HORIZONTAL_ALIGNMENT_CENTER, INNER * 2.0 * s, int(13.0 * s), UI.DIM)
	for k in pages():
		draw_circle(c + Vector2((k - (pages() - 1) * 0.5) * 16.0 * s, 44.0 * s), 4.0 * s, UI.CANARY if k == page else UI.DIM)
	if _at.length() > 4.0:
		draw_line(c, c + _at * (INNER - 14.0) / THROW * s, Color(UI.CANARY.r, UI.CANARY.g, UI.CANARY.b, 0.8), 3.0 * s, true)


## Emote `id` at time `t` as a stick figure standing on `at`'s middle.
func _figure(id: int, t: float, at: Vector2, scale_by: float, ink: Color) -> void:
	var j := Emotes.stick(id, t)
	var lines := PackedVector2Array()
	for b in Emotes.BONES:
		lines.append(at + Vector2(j[b].x, 0.9 - j[b].y) * scale_by)
	draw_multiline(lines, ink, maxf(2.0, scale_by * 0.075))
	draw_circle(at + Vector2(j[Emotes.J_HEAD].x, 0.9 - j[Emotes.J_HEAD].y) * scale_by, scale_by * 0.17, ink)
