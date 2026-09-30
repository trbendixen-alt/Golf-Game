extends Node3D
## One hole of a round: the ground (fairway, rough, hazards...), a tee, a cup, and one ball.
##
## The hole's layout (name, par, tee, cup, surfaces) comes from a data file, loaded by
## RoundManager. This script builds the scene in code (ground, flag, camera, light,
## UI) so you can read everything in one place.
##
## Flow: drag to aim -> tap -> tap -> tap (swing meter) -> ball flies/bounces/rolls ->
## ball stops (swing again) or drops in the cup. Holing out (or hitting the stroke cap) shows the
## score term, then RoundManager loads the next hole or the round summary.

# How long the score term stays on screen before the next hole loads (tap to skip).
const RESULT_SECONDS := 3.0

# --- Shot tuning (speed and launch angle now come from the selected club) ---
const START_MISS_ANGLE_DEG := 4.0 # A far-edge accuracy tap starts the ball this far off line
                                  # (sidespin then curves it further; see BallPhysics).
const MAX_DISTANCE_LOSS := 0.15  # Fraction of speed lost by a totally off-centre accuracy tap.

# --- Aiming ---
const AIM_DEGREES_PER_PIXEL := 0.08    # How far the aim turns per pixel of sideways drag.
const DRAG_THRESHOLD := 20.0           # Pixels a press must move before it counts as a drag.
const AIM_KEY_DEGREES_PER_SECOND := 40.0  # Left/right arrow keys aim too (for desktop testing).
const QUALITY_SECONDS := 1.2           # How long "PERFECT!" etc. stays on screen.
const HAZARD_SECONDS := 1.2            # Pause on "SPLASH!" / "OUT OF BOUNDS" before the drop.

const MPH_TO_MS := 0.44704       # Wind speeds are shown in MPH but physics uses m/s.
const TRAIL_LEAD := 15.0         # Wind streaks are kept this far ahead of the ball.

# --- Camera tuning ---
const CAMERA_BACK := 8.0         # Metres behind the ball.
const CAMERA_HEIGHT := 4.5       # Metres above the ground.
const CAMERA_LOOK_AHEAD := 3.0   # The camera looks at a point this far ahead of the ball. A short
                                 # distance tilts the view down so the ball sits above the bottom controls.

# Layout of this hole, read from the data file in _ready().
var tee_position := Vector3.ZERO
var cup_position := Vector3.ZERO
## Which surface is where on this hole.
var surfaces: SurfaceMap

# This hole's wind: a unit direction the wind blows toward, and a speed in MPH.
var wind_direction := Vector3.RIGHT
var wind_speed_mph := 0.0

var ball: BallPhysics
var shot: ShotController
var camera: Camera3D
var hud: HoleHud
var pause_menu: PauseMenu
var wind_trails: WindTrails
var aim_preview: AimPreview

# Clubs: the list, which one is selected, and the power we suggest for the next shot.
var clubs: Array[Dictionary] = []
var club_index := 0
var club: Dictionary = {}
## The selected club as it plays from the ball's current lie (see ClubSystem.adjust_for_lie).
## Use this, not `club`, for anything about the next shot.
var shot_club: Dictionary = {}
## The surface the ball is sitting on.
var lie: Dictionary = {}
var suggested_power := 0.0
var cup_out_of_range := false
# Where the aim preview's 100% power shot stops (drawn on the mini map).
var _preview_end := Vector3.ZERO
# Set while dragging; the arc is redrawn once per frame, not on every finger movement.
var _preview_dirty := false

# The flat direction (unit vector) the ball is aimed in: always toward the cup.
var aim_direction := Vector3(0, 0, -1)
var hole_complete := false
var _advance_countdown := 0.0
var _advancing := false

# Where the last shot was hit from (out of bounds replays from here), where the ball
# goes after a penalty, and the timer for the short pause before it's moved there.
var _shot_start := Vector3.ZERO
var _penalty_spot := Vector3.ZERO
var _penalty_timer: Timer

# A press before the swing starts can be a tap (start swing) or a drag (aim). We
# only know which once the finger moves or lifts, so remember where it went down.
var _pressing := false
var _dragging := false
var _press_position := Vector2.ZERO


func _ready() -> void:
	var hole := RoundManager.current_hole()
	tee_position = hole["tee"]
	cup_position = hole["cup"]
	surfaces = SurfaceMap.new(hole["surfaces"], hole["bounds"], hole["ground"], hole["obstacles"])
	_roll_wind(hole)
	_build_world()
	_build_ball()
	_build_wind_trails()
	_build_ui()
	clubs = ClubSystem.get_clubs()
	_reset_ball_to_tee()
	_select_club(0)  # Start every hole with the Driver.
	_update_hud()


## Pick this hole's wind: a random direction and a random speed within the hole's range.
func _roll_wind(hole: Dictionary) -> void:
	wind_speed_mph = randf_range(hole["wind_min"], hole["wind_max"])
	var angle := randf() * TAU
	# angle 0 blows toward -Z (the way the first hole faces), and it goes around from there.
	wind_direction = Vector3(sin(angle), 0.0, -cos(angle))


# ---------------------------------------------------------------------------
# Building the scene
# ---------------------------------------------------------------------------

func _build_world() -> void:
	# Sky colour and soft ambient light.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.53, 0.75, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	# The sun.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	# Camera (positioned every frame in _process).
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 400.0
	add_child(camera)

	# Work out the line from tee to cup. The fairway and stripes follow this line.
	var to_cup := cup_position - tee_position
	to_cup.y = 0.0
	var hole_length := to_cup.length()
	var direction := to_cup / hole_length
	var midpoint := (tee_position + cup_position) / 2.0
	# A rotation that makes a mesh's long (Z) axis line up with the hole.
	var facing := Basis.looking_at(direction, Vector3.UP)

	# The ground: flat at y = 0 (the ball physics treats y = 0 as the ground), with
	# the hole's fairway, green, hazards and out-of-bounds stakes drawn on it.
	var ground := HoleGround.new()
	ground.surfaces = surfaces
	ground.centre = midpoint
	add_child(ground)

	# White stripes every 10 m along the hole. A totally flat field gives no sense of
	# distance, so these help you see how far the ball has travelled.
	for i in range(1, int(hole_length / 10.0) + 1):
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(12, 0.02, 0.25)
		_add_mesh(stripe_mesh, Color(1, 1, 1),
				tee_position + direction * 10.0 * i + Vector3(0, ground.top_height, 0), facing)

	# Tee marker.
	var tee_mesh := CylinderMesh.new()
	tee_mesh.top_radius = 0.7
	tee_mesh.bottom_radius = 0.7
	tee_mesh.height = 0.04
	_add_mesh(tee_mesh, Color(0.95, 0.95, 0.95), tee_position + Vector3(0, ground.top_height, 0))

	# The cup: a dark disc lying on the ground.
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = BallPhysics.CUP_RADIUS
	cup_mesh.bottom_radius = BallPhysics.CUP_RADIUS
	cup_mesh.height = 0.02
	_add_mesh(cup_mesh, Color(0.05, 0.05, 0.05), cup_position + Vector3(0, ground.top_height, 0))

	# Flag: a tall pole with a red flag so you can spot the cup from far away.
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.04
	pole_mesh.height = 4.0
	_add_mesh(pole_mesh, Color(0.9, 0.9, 0.9), cup_position + Vector3(0, 2.0, 0))
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.9, 0.55, 0.03)
	_add_mesh(flag_mesh, Color(0.9, 0.1, 0.1), cup_position + Vector3(0.45, 3.7, 0))


## Small helper: create a coloured mesh, put it at `at`, and add it to the scene.
func _add_mesh(mesh: Mesh, color: Color, at: Vector3, orientation := Basis.IDENTITY) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(orientation, at)
	add_child(instance)


func _build_ball() -> void:
	ball = BallPhysics.new()
	ball.cup_position = cup_position
	ball.wind_velocity = wind_direction * wind_speed_mph * MPH_TO_MS
	ball.came_to_rest.connect(_on_ball_came_to_rest)
	ball.holed.connect(_on_ball_holed)
	ball.hazard.connect(_on_ball_hazard)
	ball.surfaces = surfaces
	add_child(ball)

	_penalty_timer = Timer.new()
	_penalty_timer.one_shot = true
	_penalty_timer.timeout.connect(_on_penalty_timer_timeout)
	add_child(_penalty_timer)

	shot = ShotController.new()
	shot.shot_fired.connect(_on_shot_fired)
	add_child(shot)

	aim_preview = AimPreview.new()
	add_child(aim_preview)


func _build_wind_trails() -> void:
	wind_trails = WindTrails.new()
	wind_trails.wind_direction = wind_direction
	wind_trails.wind_speed = wind_speed_mph * MPH_TO_MS
	wind_trails.follow_position = tee_position
	wind_trails.visible = wind_speed_mph >= 0.5  # No streaks in dead calm.
	add_child(wind_trails)


func _build_ui() -> void:
	hud = HoleHud.new()
	hud.shot = shot  # The swing meter reads this.
	hud.pause_pressed.connect(pause_menu_open)
	hud.previous_club_pressed.connect(_select_club_offset.bind(-1))
	hud.next_club_pressed.connect(_select_club_offset.bind(1))
	add_child(hud)

	hud.set_map_surfaces(surfaces)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)


func pause_menu_open() -> void:
	pause_menu.open()


# ---------------------------------------------------------------------------
# Input: every tap (mouse click, touch, or Space/Enter) goes here
# ---------------------------------------------------------------------------

## Before the swing starts, a press is either a tap (start the swing, on release) or a
## sideways drag (aim). Once the swing has started, every press is a meter tap and
## fires the instant the finger goes down, so timing feels exact.
func _unhandled_input(event: InputEvent) -> void:
	# On a phone, Godot turns touches into mouse events for us, so this covers both.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		elif _pressing:
			_pressing = false
			if not _dragging and _can_aim():
				shot.tap()  # A press that didn't move: start the swing.
	elif event is InputEventMouseMotion and _pressing:
		if not _dragging and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging and _can_aim():
			# Drag right = aim right. Turning around UP by a negative angle turns right.
			_turn_aim(-event.relative.x * AIM_DEGREES_PER_PIXEL)
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		# Space / Enter, handy when testing on a computer.
		if hole_complete:
			_go_to_next_hole()
		elif not ball.is_moving:
			shot.tap()


func _on_press(at: Vector2) -> void:
	if hole_complete:
		_go_to_next_hole()    # After the hole ends, a tap skips the wait.
	elif _can_aim():
		_pressing = true      # Tap or drag? Decided on move / release.
		_dragging = false
		_press_position = at
	elif not ball.is_moving:
		shot.tap()            # Mid-swing: set power / accuracy right now.


## Aiming (and switching clubs) is only allowed before the swing starts.
func _can_aim() -> bool:
	return shot.state == ShotController.State.IDLE and not ball.is_moving and not hole_complete


## Turn the aim by some degrees: positive turns left, negative turns right.
func _turn_aim(degrees: float) -> void:
	aim_direction = aim_direction.rotated(Vector3.UP, deg_to_rad(degrees)).normalized()
	_update_wind_arrow()
	_preview_dirty = true


# ---------------------------------------------------------------------------
# Game events
# ---------------------------------------------------------------------------

## Third tap happened: turn the meter's power + accuracy into a real ball launch.
func _on_shot_fired(power: float, accuracy: float) -> void:
	RoundManager.add_stroke()
	_update_hud()
	# Grade the swing (Perfect / Good / Average / Poor) and tell the player.
	var quality := ShotQuality.rate(power, accuracy, suggested_power, shot_club["sweet_spot"],
			not shot_club["two_tap"])
	RoundManager.record_shot(quality)
	hud.flash_quality(ShotQuality.TIER_NAMES[quality["tier"]], QUALITY_SECONDS)

	# Power decides speed (as a fraction of the club's max). A bad accuracy tap also
	# costs a little distance.
	# (shot_club already has any power lost to a bad lie taken off.)
	var speed: float = shot_club["max_speed"] * power * (1.0 - MAX_DISTANCE_LOSS * absf(accuracy))

	# An off-centre accuracy tap starts the ball slightly off line, then sidespin
	# curves it further: positive = right (a slice), negative = left (a hook).
	# Rotating around UP by a negative angle turns clockwise, i.e. to the right.
	var yaw := deg_to_rad(-accuracy * START_MISS_ANGLE_DEG)
	var flat_direction := aim_direction.rotated(Vector3.UP, yaw)
	ball.sidespin = accuracy
	ball.roll_decel = shot_club["roll_decel"]  # Each club rolls and spins differently.
	ball.backspin = shot_club["backspin"]
	_shot_start = ball.position
	ball.launch(ClubSystem.launch_velocity(shot_club, flat_direction, speed))
	aim_preview.visible = false
	hud.set_message("")


func _on_ball_came_to_rest() -> void:
	RoundManager.record_shot_distance(club["name"], _flat_distance(_shot_start, ball.position), false)
	_get_ready_for_next_shot()


## Water: +1 and drop near where the ball went in. Out of bounds: +1 and replay from
## where the shot was hit. Show the news for a moment, then move the ball.
func _on_ball_hazard(kind: String, drop_position: Vector3) -> void:
	RoundManager.add_stroke()  # The penalty stroke.
	if kind == "water":
		_penalty_spot = drop_position
		hud.set_message("SPLASH!\n+1 STROKE")
	else:
		_penalty_spot = _shot_start
		hud.set_message("OUT OF BOUNDS\n+1 STROKE")
	_update_hud()
	_penalty_timer.start(HAZARD_SECONDS)


func _on_penalty_timer_timeout() -> void:
	hud.set_message("")
	ball.place_at(_penalty_spot)
	_get_ready_for_next_shot()
	_snap_camera()  # A quick cut to the new spot, not a long glide.


## The ball has stopped somewhere playable: check the stroke cap, then set up the
## next swing from where it lies.
func _get_ready_for_next_shot() -> void:
	# Stroke cap reached and the ball still isn't in? The player picks up.
	if RoundManager.is_at_stroke_cap():
		_finish_hole("PICK UP")
		return
	_update_lie()
	_aim_at_cup()
	_update_suggestion()
	shot.reset()  # Ready for the next swing from wherever the ball stopped.


func _on_ball_holed() -> void:
	RoundManager.record_shot_distance(club["name"], _flat_distance(_shot_start, cup_position), true)
	_finish_hole("IN THE HOLE!")


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## The hole is over (holed out or picked up): save the score, show the golf term.
func _finish_hole(headline: String) -> void:
	hole_complete = true
	_advance_countdown = RESULT_SECONDS
	RoundManager.record_hole()  # First, so the stroke cap is applied to what we show.
	var par: int = RoundManager.current_hole()["par"]
	var term := RoundManager.score_term(RoundManager.strokes, par)
	var vs_par := RoundManager.format_vs_par(RoundManager.strokes - par)
	hud.set_message("%s\n%s (%s)" % [headline, term.to_upper(), vs_par])
	_update_hud()


func _go_to_next_hole() -> void:
	if _advancing:
		return  # Guard so a tap and the timer can't both trigger it.
	_advancing = true
	RoundManager.next_hole()


func _reset_ball_to_tee() -> void:
	hole_complete = false
	hud.set_message("")
	ball.place_at(tee_position)
	shot.reset()
	_aim_at_cup()
	_snap_camera()


## Point the aim direction from the ball toward the cup (ignoring height).
func _aim_at_cup() -> void:
	var to_cup := cup_position - ball.position
	to_cup.y = 0.0
	if to_cup.length() > 0.5:  # Don't flip around if we're standing right on the cup.
		aim_direction = to_cup.normalized()
	_update_wind_arrow()
	_update_aim_preview()


## Redraw the dotted arc: a 100% power shot with this club along the aim line.
func _update_aim_preview() -> void:
	if shot_club.is_empty():
		return  # No club picked yet (still setting up the hole).
	var path := ClubSystem.simulate_path(ball.position, aim_direction, shot_club["max_speed"],
			shot_club, surfaces)
	aim_preview.show_path(path)
	aim_preview.visible = true
	_preview_dirty = false
	_preview_end = path[path.size() - 1]


## The wind arrow is drawn relative to the shot: "up" = wind blowing the way you hit.
func _update_wind_arrow() -> void:
	# signed_angle_to is counter-clockwise when seen from above; the screen turns clockwise.
	var angle := -aim_direction.signed_angle_to(wind_direction, Vector3.UP)
	hud.set_wind(wind_speed_mph, angle)


# ---------------------------------------------------------------------------
# Clubs
# ---------------------------------------------------------------------------

func _select_club_offset(offset: int) -> void:
	_select_club(club_index + offset)


## Switch to a club by its index in the list (wraps around at both ends).
func _select_club(index: int) -> void:
	club_index = wrapi(index, 0, clubs.size())
	club = clubs[club_index]
	hud.set_club(club)
	_update_lie()
	_update_suggestion()
	_update_aim_preview()


## Look at what the ball is sitting on and work out how the selected club plays from it.
func _update_lie() -> void:
	if club.is_empty():
		return  # No club picked yet (still setting up the hole).
	lie = surfaces.support_at(ball.position)["surface"]  # The ground, or e.g. a car roof.
	shot_club = ClubSystem.adjust_for_lie(club, lie)
	shot.sweet_spot = shot_club["sweet_spot"]
	shot.two_tap = shot_club["two_tap"]
	var power_lost := roundi((1.0 - shot_club["max_speed"] / club["max_speed"]) * 100.0)
	hud.set_lie(lie["label"], power_lost)


## Work out how hard to hit with the current club to reach the cup, rolling over the
## real ground between here and there (no wind included).
func _update_suggestion() -> void:
	var to_cup := cup_position - ball.position
	to_cup.y = 0.0
	suggested_power = ClubSystem.suggest_power(shot_club, to_cup.length(), ball.position,
			to_cup.normalized(), surfaces)
	cup_out_of_range = suggested_power >= 1.0
	hud.set_suggested_power(suggested_power)


# ---------------------------------------------------------------------------
# Camera + HUD, updated every frame
# ---------------------------------------------------------------------------

## Refresh the hole / stroke / score text at the top of the screen.
func _update_hud() -> void:
	var hole := RoundManager.current_hole()
	hud.set_info("Hole %d of %d  -  Par %d" % [
			RoundManager.current_index + 1, RoundManager.hole_count(), hole["par"]])
	hud.set_strokes("Strokes %d  -  Round %s" % [
			RoundManager.strokes, RoundManager.format_vs_par(RoundManager.round_vs_par())])


func _process(delta: float) -> void:
	# After the hole ends, count down and then move on automatically.
	if hole_complete:
		_advance_countdown -= delta
		if _advance_countdown <= 0.0:
			_go_to_next_hole()

	# Arrow keys aim too, for testing on a computer.
	var turn := Input.get_axis("ui_left", "ui_right")
	if turn != 0.0 and _can_aim():
		_turn_aim(-turn * AIM_KEY_DEGREES_PER_SECOND * delta)
	if _preview_dirty and _can_aim():
		_update_aim_preview()

	# Glide toward a spot behind and above the ball, looking down the aim line.
	var target := ball.position - aim_direction * CAMERA_BACK + Vector3.UP * CAMERA_HEIGHT
	camera.position = camera.position.lerp(target, 1.0 - exp(-4.0 * delta))
	_point_camera()

	# Feed the HUD. Club arrows only work between shots.
	hud.update_map(ball.position, cup_position, aim_direction, _preview_end,
			suggested_power, cup_out_of_range)
	hud.set_club_buttons_enabled(_can_aim())

	# Keep the wind streaks in front of the ball.
	wind_trails.follow_position = ball.position + aim_direction * TRAIL_LEAD


## Jump the camera straight to its spot (no gliding). Used when the ball is reset.
func _snap_camera() -> void:
	camera.position = ball.position - aim_direction * CAMERA_BACK + Vector3.UP * CAMERA_HEIGHT
	_point_camera()


func _point_camera() -> void:
	var look_target := ball.position + aim_direction * CAMERA_LOOK_AHEAD + Vector3(0, 0.5, 0)
	camera.look_at(look_target, Vector3.UP)
