class_name SurfaceMap
extends RefCounted
## One hole's ground: which surface (fairway, rough, water, pothole...) is where.
##
## A hole file lists its surface zones in DRAW ORDER: later zones sit on top of
## earlier ones, so a green listed after the fairway wins where they overlap. Any spot
## not covered by a zone is the hole's "ground" (rough unless the hole says otherwise).
## If the hole has "bounds", everything outside them is out of bounds.
##
## Zone shapes in a hole file (all positions are [x, z] on the ground, in metres):
##   { "type": "green", "circle": [x, z], "radius": 8 }
##   { "type": "fairway", "rect": [x, z], "size": [width, length], "angle": 30 }
##   { "type": "water", "polygon": [[x, z], [x, z], [x, z], ...] }
## "angle" turns a rectangle clockwise (seen from above) in degrees; "size" is
## [across, along] before turning, where "along" runs down the -Z direction.
##
## What each surface DOES (roll, bounce, lie, penalty) lives in data/surfaces.json.
##
## The map also holds the hole's solid obstacles (see Obstacles), because the top of a
## car or a building is somewhere the ball can land too: support_at() answers "what is
## the ball resting on, and how high is it?" for both.

const SURFACES_FILE := "res://data/surfaces.json"
const CIRCLE_POINTS := 24  # Circles become polygons with this many corners.

# Every surface type from surfaces.json: name -> { name, label, color, roll, bounce,
# lie_power, lie_sweet_spot, penalty }. Loaded once, then shared.
static var _types: Dictionary = {}
static var _default_type := "rough"

## Zones in draw order: each is { type: String, points: PackedVector2Array }.
var zones: Array[Dictionary] = []
## The playable area. Empty = no boundary (nothing is out of bounds except "oob" zones).
var bounds := PackedVector2Array()
## The surface anywhere no zone covers.
var ground := "rough"
## Cars, walls, hay bales... that the ball bounces off (and can land on).
var obstacles: Obstacles


## Build a hole's map from its data file entries ("surfaces", "bounds", "ground",
## "obstacles").
func _init(hole_zones: Array = [], hole_bounds = null, hole_ground := "",
		hole_obstacles: Array = []) -> void:
	obstacles = Obstacles.new(hole_obstacles)
	ground = hole_ground if hole_ground != "" else default_type()
	for zone in hole_zones:
		if not surface_types().has(zone["type"]):
			push_error("Unknown surface type in hole file: " + str(zone["type"]))
			continue
		zones.append({"type": zone["type"], "points": shape_points(zone)})
	if hole_bounds != null:
		bounds = shape_points(hole_bounds)


## Which surface is at this spot? Returns its name, e.g. "rough".
func type_at(x: float, z: float) -> String:
	var spot := Vector2(x, z)
	if not bounds.is_empty() and not Geometry2D.is_point_in_polygon(spot, bounds):
		return "oob"
	# Check the top zone first: later zones are drawn over earlier ones.
	for i in range(zones.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(spot, zones[i]["points"]):
			return zones[i]["type"]
	return ground


## The ground surface's full description at a 3D position (height and obstacles are
## ignored: this is what's painted on the ground).
func surface_at(position: Vector3) -> Dictionary:
	return get_type(type_at(position.x, position.z))


## What a ball at `position` would rest on: the top of an obstacle it's above, or the
## ground. Returns { height (of the surface, in metres), surface (a surface description) }.
func support_at(position: Vector3) -> Dictionary:
	var top := obstacles.support_at(position.x, position.z, position.y)
	if top["type"] != "":
		return {"height": top["height"], "surface": Obstacles.get_type(top["type"])}
	return {"height": 0.0, "surface": surface_at(position)}


# ---------------------------------------------------------------------------
# Surface types (shared by every hole)
# ---------------------------------------------------------------------------

static func surface_types() -> Dictionary:
	if _types.is_empty():
		_load_types()
	return _types


static func get_type(type_name: String) -> Dictionary:
	return surface_types()[type_name]


static func default_type() -> String:
	surface_types()
	return _default_type


static func _load_types() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SURFACES_FILE))
	_default_type = data.get("default", "rough")
	for type_name in data["surfaces"]:
		var entry: Dictionary = data["surfaces"][type_name]
		_types[type_name] = {
			"name": type_name,
			"label": entry.get("label", type_name.capitalize()),
			"color": Color(entry.get("color", "#ffffff")),
			"roll": float(entry.get("roll", 1.0)),
			"bounce": float(entry.get("bounce", 1.0)),
			"lie_power": float(entry.get("lie_power", 1.0)),
			"lie_sweet_spot": float(entry.get("lie_sweet_spot", 1.0)),
			"penalty": entry.get("penalty", ""),  # "", "water" or "oob".
		}


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

## Turn a zone's shape (circle / rect / polygon) into polygon corners on the ground.
static func shape_points(shape: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape.has("circle"):
		var centre := _vec2(shape["circle"])
		var radius := float(shape["radius"])
		for i in CIRCLE_POINTS:
			var angle := TAU * i / CIRCLE_POINTS
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	elif shape.has("rect"):
		var centre := _vec2(shape["rect"])
		var half := _vec2(shape["size"]) / 2.0
		# Seen from above with -Z pointing up the screen, turning clockwise means
		# rotating the (x, z) coordinates by +angle.
		var angle := deg_to_rad(float(shape.get("angle", 0.0)))
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			points.append(centre + corner.rotated(angle))
	elif shape.has("polygon"):
		for point in shape["polygon"]:
			points.append(_vec2(point))
	else:
		push_error("Surface zone needs a circle, rect or polygon: " + str(shape))
	return points


static func _vec2(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))
