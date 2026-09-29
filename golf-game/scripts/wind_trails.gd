class_name WindTrails
extends MultiMeshInstance3D
## Tiny white streaks that drift through the air in the wind's direction, so you can
## SEE which way the wind blows. They're cheap on purpose:
##   - a fixed "pool" of TRAIL_COUNT streaks that are recycled forever (nothing is
##     created or deleted while playing),
##   - drawn with a single MultiMesh, which is one draw call for all of them.
## Each streak fades in and out by growing and shrinking, so it never pops.

const TRAIL_COUNT := 40
const AREA_SIZE := 22.0     # Streaks appear within this many metres either side of the follow point.
const MAX_HEIGHT := 7.0     # ...and up to this high above the ground.
const LIFETIME := 3.0       # Seconds a streak lives before being recycled.

## Unit vector the wind blows toward, and its speed in m/s. Set these before adding.
var wind_direction := Vector3.RIGHT
var wind_speed := 0.0
## Streaks are recycled near this point. The hole scene keeps it ahead of the ball.
var follow_position := Vector3.ZERO

var _positions := PackedVector3Array()
var _ages := PackedFloat32Array()
var _basis := Basis.IDENTITY


func _ready() -> void:
	# One thin box, long along its Z axis, drawn TRAIL_COUNT times.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material

	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.mesh = mesh
	pool.instance_count = TRAIL_COUNT
	# The streaks move around a lot; tell Godot to always draw them (no clever culling).
	pool.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 200, 4000))
	multimesh = pool

	_basis = Basis.looking_at(wind_direction, Vector3.UP)
	# Start with the streaks spread out, at random points in their life.
	_positions.resize(TRAIL_COUNT)
	_ages.resize(TRAIL_COUNT)
	for i in TRAIL_COUNT:
		_respawn(i)
		_ages[i] = randf() * LIFETIME


func _process(delta: float) -> void:
	# Streaks drift a little even in light wind, and faster in strong wind.
	var drift := maxf(0.8, wind_speed * 0.6)
	# Stronger wind = longer streaks.
	var length := 0.8 + wind_speed * 0.25
	for i in TRAIL_COUNT:
		_ages[i] += delta
		if _ages[i] >= LIFETIME:
			_respawn(i)
		_positions[i] += wind_direction * drift * delta
		# 0 -> 1 -> 0 over the streak's life: it grows in, then shrinks away.
		var fade := sin(PI * _ages[i] / LIFETIME)
		var streak_basis := _basis * Basis.from_scale(Vector3(fade, fade, length * fade))
		multimesh.set_instance_transform(i, Transform3D(streak_basis, _positions[i]))


## Move streak `i` back to a random spot near the follow point and restart its life.
func _respawn(i: int) -> void:
	_ages[i] = 0.0
	_positions[i] = follow_position + Vector3(
			randf_range(-AREA_SIZE, AREA_SIZE),
			randf_range(0.3, MAX_HEIGHT),
			randf_range(-AREA_SIZE, AREA_SIZE))
