extends SceneTree
## Developer tool: builds the shared "Street Golf" look.
##   Step 1 (draws the glossy button images):
##     godot --headless --path . --script res://tools/build_ui_theme.gd -- textures
##   Step 2 (lets Godot import the new images):
##     godot --headless --path . --import --quit
##   Step 3 (builds the theme file that uses them):
##     godot --headless --path . --script res://tools/build_ui_theme.gd -- theme
##
## Output: ui/theme/btn_*.png and ui/theme/street_golf.tres. Commit both. Nothing here
## runs in the game; the game only loads the finished theme.
##
## To change the look: edit the colours and numbers below and run the three steps again.
## (The theme file can also be tweaked by hand in Godot's editor once it exists.)

const OUT := "res://ui/theme/"
const TEX_W := 256
const TEX_H := 176
const MARGIN_X := 70   # 9-slice: how much of each side stays un-stretched
const MARGIN_TOP := 60
const MARGIN_BOTTOM := 64

# --- The palette (also stored in the theme under the "StreetGolf" type) ---
const NAVY := Color("#16235a")
const NAVY_DEEP := Color("#0c1538")
const GOLD := Color("#e8c14a")
const YELLOW := Color("#ffd84a")
const GREEN := {"top": Color("#a4f36e"), "mid": Color("#48d03e"), "bottom": Color("#25a52c"), "lip": Color("#157425")}
const ORANGE := {"top": Color("#ffc862"), "mid": Color("#ff9626"), "bottom": Color("#f2701a"), "lip": Color("#b04a0b")}

const LILITA := "res://fonts/lilita_one/LilitaOne-Regular.ttf"
const FREDOKA := "res://fonts/fredoka/Fredoka-Variable.ttf"


func _init() -> void:
	var step := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "textures"
	if step == "textures":
		for name in ["green", "orange"]:
			var colors: Dictionary = GREEN if name == "green" else ORANGE
			_button_image(colors, false).save_png(ProjectSettings.globalize_path(OUT + "btn_%s.png" % name))
			_button_image(colors, true).save_png(ProjectSettings.globalize_path(OUT + "btn_%s_pressed.png" % name))
		print("button images written; now run the import step")
	else:
		_build_theme()
	quit()


# ---------------------------------------------------------------------------
# Button images (drawn with signed distance maths so the edges are smooth)
# ---------------------------------------------------------------------------

## Distance from point `p` to a rounded rectangle: negative inside, positive outside.
func _round_rect(p: Vector2, top_left: Vector2, bottom_right: Vector2, radius: float) -> float:
	var centre := (top_left + bottom_right) / 2.0
	var half := (bottom_right - top_left) / 2.0 - Vector2(radius, radius)
	var q := (p - centre).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


func _over(under: Color, over: Color) -> Color:
	var alpha := over.a + under.a * (1.0 - over.a)
	if alpha <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (over.srgb_to_linear() * over.a + under.srgb_to_linear() * under.a * (1.0 - over.a)) / alpha
	var out := Color(rgb.r, rgb.g, rgb.b, alpha).linear_to_srgb()
	out.a = alpha
	return out


func _button_image(colors: Dictionary, pressed: bool) -> Image:
	var image := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var drop := 10.0 if pressed else 0.0  # Pressed: the whole top sinks toward the base.
	var border_top := 8.0 + drop
	var border_bottom := TEX_H - 28.0
	var border := 9.0
	var lip_height := 6.0 if pressed else 24.0
	var inner_top := border_top + border
	var inner_bottom := border_bottom - border
	var body_bottom := inner_bottom - lip_height
	for y in TEX_H:
		for x in TEX_W:
			var p := Vector2(x + 0.5, y + 0.5)
			var pixel := Color(0, 0, 0, 0)
			# 1. Soft drop shadow under the button.
			var shadow_distance := _round_rect(p, Vector2(10, border_top + 10), Vector2(TEX_W - 10, border_bottom + 12), 46.0)
			pixel = _over(pixel, Color(0, 0, 0, 0.38 * clampf(1.0 - shadow_distance / 12.0, 0.0, 1.0)))
			# 2. Dark navy outline.
			var outline := _round_rect(p, Vector2(8, border_top), Vector2(TEX_W - 8, border_bottom), 46.0)
			pixel = _over(pixel, Color(NAVY.r, NAVY.g, NAVY.b, clampf(0.5 - outline, 0.0, 1.0)))
			# 3. The darker "side" of the 3D button (shows below the face when not pressed).
			var lip := _round_rect(p, Vector2(8 + border, inner_top), Vector2(TEX_W - 8 - border, inner_bottom), 39.0)
			var lip_color: Color = colors["lip"]
			pixel = _over(pixel, Color(lip_color.r, lip_color.g, lip_color.b, clampf(0.5 - lip, 0.0, 1.0)))
			# 4. The face: a vertical gradient, light on top, richer below.
			var face := _round_rect(p, Vector2(8 + border, inner_top), Vector2(TEX_W - 8 - border, body_bottom), 36.0)
			var t := clampf((p.y - inner_top) / maxf(body_bottom - inner_top, 1.0), 0.0, 1.0)
			var face_color: Color = colors["top"].lerp(colors["mid"], clampf(t * 2.0, 0.0, 1.0))
			face_color = face_color.lerp(colors["bottom"], clampf(t * 2.0 - 1.0, 0.0, 1.0))
			pixel = _over(pixel, Color(face_color.r, face_color.g, face_color.b, clampf(0.5 - face, 0.0, 1.0)))
			# 5. Gloss: a soft white highlight across the top half of the face.
			var gloss_bottom := inner_top + (body_bottom - inner_top) * 0.46
			var gloss := _round_rect(p, Vector2(8 + border + 12, inner_top + 8), Vector2(TEX_W - 8 - border - 12, gloss_bottom), 24.0)
			var gloss_t := clampf((p.y - inner_top) / maxf(gloss_bottom - inner_top, 1.0), 0.0, 1.0)
			pixel = _over(pixel, Color(1, 1, 1, clampf(0.5 - gloss, 0.0, 1.0) * lerpf(0.6, 0.1, gloss_t) * (0.5 if pressed else 1.0)))
			image.set_pixel(x, y, pixel)
	return image


# ---------------------------------------------------------------------------
# The theme
# ---------------------------------------------------------------------------

func _texture_box(file: String, pressed: bool) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(OUT + file)
	box.texture_margin_left = MARGIN_X
	box.texture_margin_right = MARGIN_X
	box.texture_margin_top = MARGIN_TOP
	box.texture_margin_bottom = MARGIN_BOTTOM
	# Where the label sits. Pressed pushes it 10 px down, matching the sunken face.
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.content_margin_top = 28 if pressed else 6
	box.content_margin_bottom = 50
	return box


func _flat_panel(fill: Color, border_color: Color, radius: int, margins: Vector4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_color
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	return box


func _button_type(theme: Theme, type_name: String, base: String, file: String, font: Font, size: int) -> void:
	if type_name != "Button":
		theme.set_type_variation(type_name, "Button")
	var normal := _texture_box("btn_%s.png" % file, false)
	var pressed := _texture_box("btn_%s_pressed.png" % file, true)
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, normal)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("hover_pressed", type_name, pressed)
	theme.set_stylebox("disabled", type_name, normal)
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, Color(1, 1, 1, 0.5))
	theme.set_color("font_outline_color", type_name, NAVY)
	theme.set_constant("outline_size", type_name, int(size * 0.065))
	theme.set_color("font_shadow_color", type_name, Color(0, 0.05, 0.2, 0.5))
	theme.set_constant("shadow_offset_x", type_name, 0)
	theme.set_constant("shadow_offset_y", type_name, int(size * 0.05))


func _build_theme() -> void:
	var lilita: Font = load(LILITA)
	var fredoka_medium := FontVariation.new()
	fredoka_medium.base_font = load(FREDOKA)
	fredoka_medium.variation_opentype = {"weight": 500}  # Note: the key is "weight", not "wght" (that does nothing).
	var fredoka_bold := FontVariation.new()
	fredoka_bold.base_font = load(FREDOKA)
	fredoka_bold.variation_opentype = {"weight": 700}
	var fredoka_tracked := FontVariation.new()  # Wide-spaced capitals for the tagline.
	fredoka_tracked.base_font = load(FREDOKA)
	fredoka_tracked.variation_opentype = {"weight": 700}
	fredoka_tracked.spacing_glyph = 7

	var theme := Theme.new()
	theme.default_font = fredoka_medium
	theme.default_font_size = 44

	# The palette and fonts, so other screens can ask the theme for them by name.
	var palette := {"navy": NAVY, "navy_deep": NAVY_DEEP, "gold": GOLD, "yellow": YELLOW,
			"green": GREEN["mid"], "orange": ORANGE["mid"]}
	for color_name in palette:
		theme.set_color(color_name, "StreetGolf", palette[color_name])
	theme.set_font("title", "StreetGolf", lilita)
	theme.set_font("body", "StreetGolf", fredoka_medium)
	theme.set_font("body_bold", "StreetGolf", fredoka_bold)

	# Buttons. Plain "Button" = green; variations: BigGreenButton (PLAY), OrangeButton.
	_button_type(theme, "Button", "", "green", lilita, 76)
	_button_type(theme, "BigGreenButton", "Button", "green", lilita, 156)
	_button_type(theme, "OrangeButton", "Button", "orange", lilita, 80)

	# Labels.
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", lilita)
	theme.set_font_size("font_size", "TitleLabel", 230)
	theme.set_color("font_color", "TitleLabel", Color.WHITE)  # The gradient shader recolours this.
	theme.set_color("font_outline_color", "TitleLabel", NAVY_DEEP)
	theme.set_constant("outline_size", "TitleLabel", 38)
	theme.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 16)
	theme.set_type_variation("TaglineLabel", "Label")
	theme.set_font("font", "TaglineLabel", fredoka_tracked)
	theme.set_font_size("font_size", "TaglineLabel", 42)
	theme.set_color("font_color", "TaglineLabel", Color.WHITE)
	theme.set_type_variation("VersionLabel", "Label")
	theme.set_font_size("font_size", "VersionLabel", 34)
	theme.set_color("font_color", "VersionLabel", Color(1, 1, 1, 0.6))
	theme.set_type_variation("ChipText", "RichTextLabel")
	theme.set_font("normal_font", "ChipText", fredoka_bold)
	theme.set_font("bold_font", "ChipText", fredoka_bold)
	theme.set_font_size("normal_font_size", "ChipText", 44)
	theme.set_font_size("bold_font_size", "ChipText", 44)
	theme.set_color("default_color", "ChipText", Color.WHITE)

	# Panels.
	theme.set_type_variation("ChipPanel", "PanelContainer")
	theme.set_stylebox("panel", "ChipPanel", _flat_panel(Color(NAVY.r, NAVY.g, NAVY.b, 0.9), Color(0.27, 0.36, 0.72), 44, Vector4(32, 14, 32, 14)))
	theme.set_type_variation("PillPanel", "PanelContainer")
	theme.set_stylebox("panel", "PillPanel", _flat_panel(Color(NAVY.r, NAVY.g, NAVY.b, 0.92), GOLD, 60, Vector4(44, 16, 44, 16)))

	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _flat_panel(Color(NAVY.r, NAVY.g, NAVY.b, 0.82), Color(0.27, 0.36, 0.72), 36, Vector4(30, 26, 30, 26)))

	ResourceSaver.save(theme, OUT + "street_golf.tres")
	print("theme written: ", OUT, "street_golf.tres")
