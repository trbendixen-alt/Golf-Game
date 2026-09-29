class_name BallPhysics
extends Node3D
## The golf ball and its physics.
##
## We do NOT use Godot's built-in rigid bodies. Instead we move the ball by hand
## every physics tick (60 times per second, fixed timestep). That keeps the result
## predictable and identical on every phone, which a golf game needs.
##
## Units: 1 unit = 1 metre. Y is up. The ground is the flat plane at y = 0.
## Godot's "forward" direction is -Z, so the hole is down the negative Z axis.
##
## NOTE: this node's parent must sit at the world origin, because we use
## `position` (local) as if it were the world position.

## Emitted when the ball has stopped moving.
signal came_to_rest
## Emitted when the ball drops into the cup.
signal holed
## Emitted when the ball touches down in water or out of bounds. `kind` is the
## surface's penalty ("water" or "oob"). `drop_position` is the last playable spot the
## ball passed over, i.e. roughly where it went in: that's where a water drop goes.
signal hazard(kind: String, drop_position: Vector3)

# --- Tunable numbers (tweak these to change how the ball feels) ---
const BALL_RADIUS := 0.2          # Bigger than a real ball so it's visible on a phone.
const GRAVITY := 9.8              # Metres per second^2, pulls the ball down.
const AIR_DRAG := 0.004           # Air slows the ball a bit (faster = more drag).
const BOUNCE_ENERGY := 0.55       # Fraction of vertical speed kept after a bounce.
const BOUNCE_GRIP := 0.8          # Fraction of sideways speed kept after a bounce.
const MIN_BOUNCE_SPEED := 1.5     # Slower landings than this don't bounce; the ball rolls.
const DEFAULT_ROLL_DECEL := 3.0   # How quickly rolling slows the ball (m/s^2). Clubs override this.
const WIND_PUSH := 0.08           # Wind acceleration in the air, per m/s of wind speed.
const ROLL_WIND_FACTOR := 0.1     # Wind matters this much less once the ball is on the ground.
const CURVE_TURN_RATE := 0.08     # Radians per second the flight path bends with full sidespin (hook/slice).
const STOP_SPEED := 0.2           # Rolling slower than this counts as stopped.
const GROUND_TOLERANCE := 0.001   # Position is stored as a 32-bit float, so "on the ground" needs a tiny margin.
const CUP_RADIUS := 0.5           # How close to the cup centre counts as "over the hole".
const CUP_CAPTURE_SPEED := 5.0    # Faster than this and the ball skips over the cup.
const DROP_STEP_BACK := 1.0       # A water drop goes this far back from the edge, onto dry land.

## World position of the cup. The hole scene sets this.
var cup_position := Vector3.ZERO
## Current velocity in metres per second.
var velocity := Vector3.ZERO
## True while the ball is flying, bouncing or rolling.
var is_moving := false
## How quickly rolling slows the ball. The hole scene sets this from the club used.
var roll_decel := DEFAULT_ROLL_DECEL
## The wind as a velocity (direction * speed, in m/s). Zero = calm.
var wind_velocity := Vector3.ZERO
## Hook/slice spin from the accuracy tap: -1 curves hard left, 1 curves hard right, 0 = straight.
var sidespin := 0.0
## Backspin (wedges): 0 = none, 1 = the first landing kills all forward speed.
var backspin := 0.0
## The hole's ground (fairway, rough, water...). null = fairway everywhere, which is
## what the practice balls in ClubSystem use to measure a club's distance.
var surfaces: SurfaceMap = null
## false = water / OOB play like fairway. Used by practice balls that work out the
## suggested power, so a pond in the way doesn't confuse the maths.
var hazards_enabled := true

var _has_landed := false
var _last_safe_position := Vector3.ZERO

var _shadow: MeshInstance3D


func _ready() -> void:
	# Build the ball's look in code so this script works with no extra setup.
	var mesh := SphereMesh.new()
	mesh.radius = BALL_RADIUS
	mesh.height = BALL_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	mesh.material = material
	var ball_visual := MeshInstance3D.new()
	ball_visual.mesh = mesh
	add_child(ball_visual)

	# A dark blob on the ground under the ball, so you can judge its height.
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = BALL_RADIUS
	shadow_mesh.bottom_radius = BALL_RADIUS
	shadow_mesh.height = 0.01
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0, 0, 0, 0.4)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mesh.material = shadow_material
	_shadow = MeshInstance3D.new()
	_shadow.mesh = shadow_mesh
	_shadow.top_level = true  # Don't follow the ball up into the air; we place it ourselves.
	add_child(_shadow)


## Put the ball on the ground at `spot` (e.g. the tee) and make it stand still.
func place_at(spot: Vector3) -> void:
	position = Vector3(spot.x, BALL_RADIUS, spot.z)
	velocity = Vector3.ZERO
	is_moving = false
	visible = true
	_has_landed = false
	_last_safe_position = position


## Hit the ball! `launch_velocity` is direction * speed, in metres per second.
func launch(launch_velocity: Vector3) -> void:
	velocity = launch_velocity
	is_moving = true
	_has_landed = false


func _process(_delta: float) -> void:
	# Keep the shadow glued to the ground below the ball. It shrinks as the ball rises.
	var shrink := clampf(1.0 - position.y / 15.0, 0.4, 1.0)
	_shadow.global_position = Vector3(position.x, 0.03, position.z)
	_shadow.scale = Vector3(shrink, 1.0, shrink)


func _physics_process(delta: float) -> void:
	step(delta)


## Advance the ball by one small time step. This is public (and not just inside
## _physics_process) so ClubSystem can run a "practice ball" off-screen to work out
## how far a shot will go.
func step(delta: float) -> void:
	if not is_moving:
		return

	# 1. Airborne: gravity and air drag act on the ball.
	# (Also counts as airborne while moving upward, e.g. right after being hit.)
	var airborne := position.y > BALL_RADIUS + GROUND_TOLERANCE or velocity.y > 0.0
	if airborne:
		velocity.y -= GRAVITY * delta
		# Wind pushes the ball the whole time it is in the air. A high arc stays in
		# the air longer, so it gets pushed more than a low punch shot.
		velocity += wind_velocity * WIND_PUSH * delta
		velocity -= velocity * velocity.length() * AIR_DRAG * delta
		# Sidespin bends the flight path left or right a little more every moment,
		# so a slice starts nearly straight and then peels away.
		if sidespin != 0.0:
			var turned := Vector3(velocity.x, 0.0, velocity.z).rotated(
					Vector3.UP, -sidespin * CURVE_TURN_RATE * delta)
			velocity = Vector3(turned.x, velocity.y, turned.z)

	# 2. Move the ball.
	position += velocity * delta

	# 3. What's underneath? Remember the last playable spot for water drops.
	var surface := _surface_here()
	var is_hazard: bool = surface["penalty"] != ""
	if not is_hazard:
		_last_safe_position = Vector3(position.x, BALL_RADIUS, position.z)

	# 4. Hit the ground?
	if position.y <= BALL_RADIUS + GROUND_TOLERANCE and velocity.y <= 0.0:
		position.y = BALL_RADIUS
		if is_hazard:
			_stop_in_hazard(surface["penalty"])
			return
		# Backspin bites on the first landing, taking off some forward speed.
		if not _has_landed:
			_has_landed = true
			velocity.x *= 1.0 - backspin
			velocity.z *= 1.0 - backspin
		if velocity.y < -MIN_BOUNCE_SPEED:
			# A real landing: bounce back up, losing some energy. Soft ground
			# (rough, mud, potholes) soaks up more of it.
			velocity.y = -velocity.y * BOUNCE_ENERGY * surface["bounce"]
			velocity.x *= BOUNCE_GRIP * surface["bounce"]
			velocity.z *= BOUNCE_GRIP * surface["bounce"]
		else:
			# A soft landing: stop bouncing and start rolling.
			velocity.y = 0.0
			_roll(delta, surface)

	# 5. Did we drop into the cup?
	_check_cup()


## The surface under the ball right now.
func _surface_here() -> Dictionary:
	if surfaces == null:
		return SurfaceMap.get_type("fairway")
	var surface := surfaces.surface_at(position)
	if not hazards_enabled and surface["penalty"] != "":
		return SurfaceMap.get_type("fairway")
	return surface


## The ball touched down in water or out of bounds: stop it and report where to drop.
func _stop_in_hazard(kind: String) -> void:
	# Step back a little from the edge (the way the ball came) so the drop is
	# clearly on dry land, unless that spot is itself a hazard.
	var drop := _last_safe_position
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.01 and surfaces != null:
		var stepped_back := drop - flat.normalized() * DROP_STEP_BACK
		if surfaces.surface_at(stepped_back)["penalty"] == "":
			drop = stepped_back
	velocity = Vector3.ZERO
	is_moving = false
	hazard.emit(kind, drop)


## Rolling: friction gradually slows the ball along the ground (more on rough, mud...).
func _roll(delta: float, surface: Dictionary) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat += wind_velocity * WIND_PUSH * ROLL_WIND_FACTOR * delta  # Only a small effect on roll.
	var speed := maxf(flat.length() - roll_decel * surface["roll"] * delta, 0.0)
	velocity = flat.normalized() * speed
	if speed < STOP_SPEED:
		velocity = Vector3.ZERO
		is_moving = false
		came_to_rest.emit()


## The ball goes in if it is over the cup, low to the ground, and slow enough.
func _check_cup() -> void:
	if not is_moving:
		return
	var offset := Vector2(position.x - cup_position.x, position.z - cup_position.z)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_low := position.y < BALL_RADIUS + 0.3
	if offset.length() < CUP_RADIUS and is_low and flat_speed < CUP_CAPTURE_SPEED:
		velocity = Vector3.ZERO
		is_moving = false
		visible = false  # The ball "disappears" into the hole.
		holed.emit()
