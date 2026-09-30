class_name MenuBackdrop
extends Control
## The animated background for the menu screens: the pre-rendered Main Street picture with
## a slow camera drift and a gentle shimmer around the sun, and a dark fade at the bottom
## so buttons stay readable. It costs one picture and two small gradients, so it's
## light on a phone.
##
## Add it first (behind everything else). The picture is made by
## tools/render_menu_background.gd.

const PICTURE := preload("res://ui/menu/menu_bg.jpg")
## Where the sun sits in the picture (0..1), for the shimmer.
const SUN_AT := Vector2(0.427, 0.475)
const DRIFT_SECONDS := 26.0      # One full slow drift cycle.
const DRIFT_ZOOM := 0.035        # How much the picture slowly zooms (3.5%).
const DRIFT_PAN := 14.0          # Sideways drift, in picture pixels.

## 0 = the picture as is; up to 1 = nearly black. Content screens use ~0.6 so text reads well.
var darkness := 0.0

var _scene: Control       # Holds the picture and the glow; moved and scaled as a unit.
var _glow: TextureRect
# Shared by every backdrop, so the slow drift carries on from one screen to the next
# instead of restarting each time you open a menu.
static var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	_scene = Control.new()
	_scene.size = PICTURE.get_size()
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene)
	var picture := TextureRect.new()
	picture.texture = PICTURE
	picture.size = PICTURE.get_size()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(picture)

	# The sun shimmer: a soft radial glow, added on top of the picture's own sun.
	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1.0, 0.86, 0.55, 0.9))
	glow_gradient.set_color(1, Color(1.0, 0.7, 0.35, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	glow_texture.width = 256
	glow_texture.height = 256
	_glow = TextureRect.new()
	_glow.texture = glow_texture
	_glow.size = Vector2(760, 760)
	_glow.position = PICTURE.get_size() * SUN_AT - _glow.size / 2.0
	_glow.pivot_offset = _glow.size / 2.0
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = additive
	_scene.add_child(_glow)

	# Dark fade up from the bottom (and a light one at the very top).
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(0.02, 0.05, 0.16, 0.25), Color(0.02, 0.05, 0.16, 0.0),
			Color(0.02, 0.04, 0.14, 0.42), Color(0.02, 0.03, 0.10, 0.85)])
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = fade
	fade_texture.fill_from = Vector2(0.5, 0.0)
	fade_texture.fill_to = Vector2(0.5, 1.0)
	fade_texture.width = 4
	fade_texture.height = 256
	var fade_rect := TextureRect.new()
	fade_rect.texture = fade_texture
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade_rect.stretch_mode = TextureRect.STRETCH_SCALE
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

	if darkness > 0.0:
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.05, 0.16, darkness)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)

	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_time += delta
	_layout()
	# Shimmer: the glow slowly breathes.
	var breath := 0.5 + 0.5 * sin(_time * 1.3)
	_glow.modulate.a = lerpf(0.35, 0.75, breath)
	_glow.scale = Vector2.ONE * lerpf(0.92, 1.08, breath)


## Fit the picture so it covers the screen (cropping the sides on wider screens), then
## apply the drift.
func _layout() -> void:
	if _scene == null:
		return
	var picture_size: Vector2 = PICTURE.get_size()
	var phase := sin(_time * TAU / DRIFT_SECONDS)
	var zoom := maxf(size.x / picture_size.x, size.y / picture_size.y) * (1.0 + DRIFT_ZOOM * (0.5 + 0.5 * phase))
	_scene.scale = Vector2.ONE * zoom
	# Keep the horizon area centred; pan a little sideways.
	var pan := Vector2(DRIFT_PAN * phase * zoom, 0.0)
	_scene.position = (size - picture_size * zoom) / 2.0 + pan
