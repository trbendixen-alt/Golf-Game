extends Node3D
## One hole of a round: flat ground, a tee, a cup, and one ball.
##
## The hole's layout (name, par, tee, cup) comes from a data file, loaded by
## RoundManager. This script builds the scene in code (ground, flag, camera, light,
## UI) so you can read everything in one place.
##
## Flow: tap -> tap -> tap (swing meter) -> ball flies/bounces/rolls -> ball stops
## (swing again) or drops in the cup. Holing out (or hitting the stroke cap) shows the
## score term, then RoundManager loads the next hole or the round summary.

# How long the score term stays on screen before the next hole loads (tap to skip).
const RESULT_SECONDS := 3.0

# --- Shot tuning (speed and launch angle now come from the selected club) ---
const MAX_MISS_ANGLE_DEG := 15.0 # Sideways aim error when the accuracy tap is at the far edge.
const MAX_DISTANCE_LOSS := 0.15  # Fraction of speed lost by a totally off-centre accuracy tap.

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

# This hole's wind: a unit direction the wind blows toward, and a speed in MPH.
var wind_direction := Vector3.RIGHT
var wind_speed_mph := 0.0

var ball: BallPhysics
var shot: ShotController
var camera: Camera3D
var hud: HoleHud
var pause_menu: PauseMenu
var wind_trails: WindTrails

# Clubs: the list, which one is selected, and the power we suggest for the next shot.
var clubs: Array[Dictionary] = []
var club_index := 0
var club: Dictionary = {}
var suggested_power := 0.0
var cup_out_of_range := false

# The flat direction (unit vector) the ball is aimed in: always toward the cup.
var aim_direction := Vector3(0, 0, -1)
var hole_complete := false
var _advance_countdown := 0.0
var _advancing := false


func _ready() -> void:
	var hole := RoundManager.current_hole()
	tee_position = hole["tee"]
	cup_position = hole["cup"]
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

	# Ground: one big flat green plane at y = 0. The ball physics treats y = 0 as the ground.
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(600, 600)
	_add_mesh(ground_mesh, Color(0.30, 0.58, 0.22), midpoint)

	# A lighter fairway strip from behind the tee to past the cup.
	var fairway_mesh := BoxMesh.new()
	fairway_mesh.size = Vector3(12, 0.01, hole_length + 20.0)
	_add_mesh(fairway_mesh, Color(0.40, 0.70, 0.30), midpoint + Vector3(0, 0.005, 0), facing)

	# White stripes every 10 m along the hole. A totally flat field gives no sense of
	# distance, so these help you see how far the ball has travelled.
	for i in range(1, int(hole_length / 10.0) + 1):
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(12, 0.02, 0.25)
		_add_mesh(stripe_mesh, Color(1, 1, 1), tee_position + direction * 10.0 * i + Vector3(0, 0.01, 0), facing)

	# Tee marker.
	var tee_mesh := CylinderMesh.new()
	tee_mesh.top_radius = 0.7
	tee_mesh.bottom_radius = 0.7
	tee_mesh.height = 0.04
	_add_mesh(tee_mesh, Color(0.95, 0.95, 0.95), tee_position + Vector3(0, 0.02, 0))

	# The cup: a dark disc lying on the ground.
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = BallPhysics.CUP_RADIUS
	cup_mesh.bottom_radius = BallPhysics.CUP_RADIUS
	cup_mesh.height = 0.02
	_add_mesh(cup_mesh, Color(0.05, 0.05, 0.05), cup_position + Vector3(0, 0.015, 0))

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
	add_child(ball)

	shot = ShotController.new()
	shot.shot_fired.connect(_on_shot_fired)
	add_child(shot)


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

	pause_menu = PauseMenu.new()
	add_child(pause_menu)


func pause_menu_open() -> void:
	pause_menu.open()


# ---------------------------------------------------------------------------
# Input: every tap (mouse click, touch, or Space/Enter) goes here
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var tapped := false
	# On a phone, Godot turns touches into mouse clicks for us, so this covers both.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		tapped = true  # Space / Enter, handy when testing on a computer.
	if tapped:
		_on_tap()


func _on_tap() -> void:
	if hole_complete:
		_go_to_next_hole()    # After the hole ends, a tap skips the wait.
	elif not ball.is_moving:
		shot.tap()            # Otherwise the tap advances the swing meter.


# ---------------------------------------------------------------------------
# Game events
# ---------------------------------------------------------------------------

## Third tap happened: turn the meter's power + accuracy into a real ball launch.
func _on_shot_fired(power: float, accuracy: float) -> void:
	RoundManager.add_stroke()
	_update_hud()
	# Power decides speed (as a fraction of the club's max). A bad accuracy tap also
	# costs a little distance.
	var speed: float = club["max_speed"] * power * (1.0 - MAX_DISTANCE_LOSS * absf(accuracy))

	# Accuracy turns the aim left/right. Positive = right (+X when facing -Z),
	# and rotating around UP by a negative angle turns clockwise, i.e. to the right.
	var yaw := deg_to_rad(-accuracy * MAX_MISS_ANGLE_DEG)
	var flat_direction := aim_direction.rotated(Vector3.UP, yaw)

	# Tilt the flat direction upward by the launch angle to get the 3D direction.
	var pitch := deg_to_rad(club["launch_angle"])
	var direction := flat_direction * cos(pitch) + Vector3.UP * sin(pitch)
	ball.roll_decel = club["roll_decel"]  # Each club rolls differently.
	ball.launch(direction * speed)
	hud.set_message("")


func _on_ball_came_to_rest() -> void:
	# Stroke cap reached and the ball still isn't in? The player picks up.
	if RoundManager.is_at_stroke_cap():
		_finish_hole("PICK UP")
		return
	_aim_at_cup()
	_update_suggestion()
	shot.reset()  # Ready for the next swing from wherever the ball stopped.


func _on_ball_holed() -> void:
	_finish_hole("IN THE HOLE!")


## The hole is over (holed out or picked up): save the score, show the golf term.
func _finish_hole(headline: String) -> void:
	hole_complete = true
	_advance_countdown = RESULT_SECONDS
	var par: int = RoundManager.current_hole()["par"]
	var term := RoundManager.score_term(RoundManager.strokes, par)
	RoundManager.record_hole()
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
	_update_suggestion()


## Work out how hard to hit with the current club to reach the cup (no wind included).
func _update_suggestion() -> void:
	var distance := _flat_distance_to_cup()
	suggested_power = ClubSystem.suggest_power(club, distance)
	cup_out_of_range = distance > club["max_distance"]
	hud.set_suggested_power(suggested_power)


func _flat_distance_to_cup() -> float:
	return Vector2(ball.position.x - cup_position.x, ball.position.z - cup_position.z).length()


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

	# Glide toward a spot behind and above the ball, looking down the aim line.
	var target := ball.position - aim_direction * CAMERA_BACK + Vector3.UP * CAMERA_HEIGHT
	camera.position = camera.position.lerp(target, 1.0 - exp(-4.0 * delta))
	_point_camera()

	# Feed the HUD. Club arrows only work between shots.
	hud.update_map(ball.position, cup_position, aim_direction, suggested_power, cup_out_of_range)
	hud.set_club_buttons_enabled(shot.state == ShotController.State.IDLE and not hole_complete)

	# Keep the wind streaks in front of the ball.
	wind_trails.follow_position = ball.position + aim_direction * TRAIL_LEAD


## Jump the camera straight to its spot (no gliding). Used when the ball is reset.
func _snap_camera() -> void:
	camera.position = ball.position - aim_direction * CAMERA_BACK + Vector3.UP * CAMERA_HEIGHT
	_point_camera()


func _point_camera() -> void:
	var look_target := ball.position + aim_direction * CAMERA_LOOK_AHEAD + Vector3(0, 0.5, 0)
	camera.look_at(look_target, Vector3.UP)
