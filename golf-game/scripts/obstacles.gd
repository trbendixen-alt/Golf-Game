class_name Obstacles
extends RefCounted
## The solid things on a hole (cars, walls, fences, hay bales, cones, buildings) and
## the maths for the ball bumping into them.
##
## Every obstacle is made of simple "parts": upright boxes (turned by an angle) or
## upright cylinders, standing on the ground (y = 0) up to their height. Simple
## shapes keep the collision maths cheap and exactly the same on every phone.
##
## Obstacles in a hole file (positions are [x, z] on the ground, in metres):
##   { "type": "car", "at": [x, z], "angle": 30 }
##   { "type": "wall", "at": [x, z], "size": [0.4, 12, 1.5] }       (override the size)
##   { "type": "hay_bale", "at": [x, z], "radius": 1.0 }
## "angle" turns clockwise seen from above, like SurfaceMap rects.
##
## What each type is like (size, bounciness, what landing on top is like) lives in
## data/obstacles.json.

const OBSTACLES_FILE := "res://data/obstacles.json"
const CYLINDER_SIDES := 16  # For drawing a cylinder's footprint on the mini map.
## A ball resting exactly on a top or against a side isn't "overlapping". This small
## allowance stops rounding errors counting it as a hit every tick.
const CONTACT_SLOP := 0.001

static var _types: Dictionary = {}

## Every part: { type, shape ("box"/"cylinder"), centre (Vector2 x/z), half (Vector2,
## boxes), radius (cylinders), height, angle (radians), color, taper, reach }.
## `reach` is how far the part extends from its centre, for a quick "too far" check.
var parts: Array[Dictionary] = []


func _init(hole_obstacles: Array = []) -> void:
	for entry in hole_obstacles:
		if not obstacle_types().has(entry["type"]):
			push_error("Unknown obstacle type in hole file: " + str(entry["type"]))
			continue
		_add_obstacle(entry, get_type(entry["type"]))


## Is there nothing solid on this hole?
func is_empty() -> bool:
	return parts.is_empty()


# ---------------------------------------------------------------------------
# Questions the ball physics asks
# ---------------------------------------------------------------------------

## The highest obstacle top under (x, z) that the ball (centre at height y) is above.
## Returns { height, type }: height 0 and type "" means plain ground.
func support_at(x: float, z: float, y: float) -> Dictionary:
	var best := {"height": 0.0, "type": ""}
	for part in parts:
		if part["height"] <= y and part["height"] > best["height"] and _covers(part, Vector2(x, z)):
			best = {"height": part["height"], "type": part["type"]}
	return best


## Could a ball at `position` touch any part within `margin` metres? A cheap check
## so the physics only does careful work near obstacles.
func is_near(position: Vector3, margin: float) -> bool:
	var flat := Vector2(position.x, position.z)
	for part in parts:
		if position.y - margin <= part["height"] \
				and flat.distance_to(part["centre"]) <= part["reach"] + margin:
			return true
	return false


## Is any obstacle standing on this spot?
func covers(x: float, z: float) -> bool:
	for part in parts:
		if _covers(part, Vector2(x, z)):
			return true
	return false


## Every part a ball of `radius` at `position` is overlapping. Each contact is
## { normal (Vector3, pointing away from the obstacle), depth (metres of overlap), type }.
func contacts(position: Vector3, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var flat := Vector2(position.x, position.z)
	for part in parts:
		# Quick check first: skip anything clearly too far away or too low.
		if flat.distance_to(part["centre"]) > part["reach"] + radius:
			continue
		if position.y - radius > part["height"]:
			continue
		var contact := _box_contact(part, position, radius) if part["shape"] == "box" \
				else _cylinder_contact(part, position, radius)
		if not contact.is_empty():
			found.append(contact)
	return found


## The part's outline on the ground (for drawing on the mini map).
static func footprint(part: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	if part["shape"] == "box":
		var half: Vector2 = part["half"]
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			points.append(part["centre"] + corner.rotated(part["angle"]))
	else:
		for i in CYLINDER_SIDES:
			var angle := TAU * i / CYLINDER_SIDES
			points.append(part["centre"] + Vector2(cos(angle), sin(angle)) * part["radius"])
	return points


# ---------------------------------------------------------------------------
# Obstacle types (shared by every hole)
# ---------------------------------------------------------------------------

static func obstacle_types() -> Dictionary:
	if _types.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(OBSTACLES_FILE))
		for type_name in data["obstacles"]:
			var entry: Dictionary = data["obstacles"][type_name]
			var type := entry.duplicate()
			# Landing on top works like a surface, so give it the same fields SurfaceMap uses.
			type["name"] = type_name
			type["label"] = entry.get("label", type_name.capitalize())
			type["color"] = Color(entry.get("color", "#888888"))
			type["roll"] = float(entry.get("roll", 1.0))
			type["bounce"] = float(entry.get("bounce", 1.0))
			type["lie_power"] = float(entry.get("lie_power", 1.0))
			type["lie_sweet_spot"] = float(entry.get("lie_sweet_spot", 1.0))
			type["penalty"] = ""
			type["restitution"] = float(entry.get("restitution", 0.4))
			type["grip"] = float(entry.get("grip", 0.8))
			_types[type_name] = type
	return _types


static func get_type(type_name: String) -> Dictionary:
	return obstacle_types()[type_name]


# ---------------------------------------------------------------------------
# Building parts from a hole file entry
# ---------------------------------------------------------------------------

func _add_obstacle(entry: Dictionary, type: Dictionary) -> void:
	var centre := Vector2(float(entry["at"][0]), float(entry["at"][1]))
	var angle := deg_to_rad(float(entry.get("angle", 0.0)))
	var color: Color = type["color"]
	if type["shape"] == "cylinder":
		var radius := float(entry.get("radius", type["radius"]))
		parts.append({
			"type": type["name"], "shape": "cylinder", "centre": centre, "radius": radius,
			"height": float(entry.get("height", type["height"])), "angle": 0.0,
			"color": color, "taper": bool(type.get("taper", false)), "reach": radius,
		})
		return
	var size: Array = entry.get("size", type["size"])
	var full := Vector3(float(size[0]), float(size[1]), float(size[2]))
	# One box unless the type lists several parts (e.g. a car's body and cabin).
	for piece in type.get("parts", [{"size": [1, 1, 1]}]):
		var fraction: Array = piece["size"]
		var half := Vector2(full.x * fraction[0], full.y * fraction[1]) / 2.0
		var offset: Array = piece.get("offset", [0, 0])
		# Offset "along" is toward the front, which is -Z before turning.
		var shift := Vector2(full.x * offset[0], -full.y * offset[1]).rotated(angle)
		parts.append({
			"type": type["name"], "shape": "box", "centre": centre + shift, "half": half,
			"height": full.z * fraction[2], "angle": angle,
			"color": Color(piece["color"]) if piece.has("color") else color,
			"taper": false, "reach": half.length(),
		})


# ---------------------------------------------------------------------------
# Collision maths
# ---------------------------------------------------------------------------

## Is (x, z) inside this part's footprint?
func _covers(part: Dictionary, spot: Vector2) -> bool:
	if part["shape"] == "box":
		var local: Vector2 = (spot - part["centre"]).rotated(-part["angle"])
		return absf(local.x) <= part["half"].x and absf(local.y) <= part["half"].y
	return spot.distance_to(part["centre"]) <= part["radius"]


## Ball vs an upright box. Works in the box's own frame (unturned), where the
## closest point on the box is just the ball's position clamped to its edges.
func _box_contact(part: Dictionary, position: Vector3, radius: float) -> Dictionary:
	var half: Vector2 = part["half"]
	var height: float = part["height"]
	var local: Vector2 = (Vector2(position.x, position.z) - part["centre"]).rotated(-part["angle"])
	var closest := Vector3(clampf(local.x, -half.x, half.x), clampf(position.y, 0.0, height),
			clampf(local.y, -half.y, half.y))
	var gap := Vector3(local.x, position.y, local.y) - closest
	var distance := gap.length()
	if distance >= radius - CONTACT_SLOP:
		return {}
	var normal: Vector3
	var depth: float
	if distance > 0.0001:
		normal = gap / distance
		depth = radius - distance
	else:
		# The ball's centre got inside the box: push it out through the nearest face.
		var to_side := half.x - absf(local.x)
		var to_end := half.y - absf(local.y)
		var to_top := height - position.y
		if to_top <= to_side and to_top <= to_end:
			normal = Vector3.UP
			depth = to_top + radius
		elif to_side <= to_end:
			normal = Vector3(signf(local.x), 0, 0)
			depth = to_side + radius
		else:
			normal = Vector3(0, 0, signf(local.y))
			depth = to_end + radius
	# Turn the normal back into the world's frame.
	var flat_normal := Vector2(normal.x, normal.z).rotated(part["angle"])
	return {"normal": Vector3(flat_normal.x, normal.y, flat_normal.y), "depth": depth,
			"type": part["type"]}


## Ball vs an upright cylinder.
func _cylinder_contact(part: Dictionary, position: Vector3, radius: float) -> Dictionary:
	var offset: Vector2 = Vector2(position.x, position.z) - part["centre"]
	var out := offset.length()
	var height: float = part["height"]
	var closest_flat: Vector2 = offset if out <= part["radius"] else offset / out * part["radius"]
	var closest := Vector3(closest_flat.x, clampf(position.y, 0.0, height), closest_flat.y)
	var gap := Vector3(offset.x, position.y, offset.y) - closest
	var distance := gap.length()
	if distance >= radius - CONTACT_SLOP:
		return {}
	if distance > 0.0001:
		return {"normal": gap / distance, "depth": radius - distance, "type": part["type"]}
	# Centre inside: out through the top or the side, whichever is nearer.
	var to_top := height - position.y
	var to_side: float = part["radius"] - out
	if to_top <= to_side or out < 0.0001:
		return {"normal": Vector3.UP, "depth": to_top + radius, "type": part["type"]}
	var side := offset / out
	return {"normal": Vector3(side.x, 0, side.y), "depth": to_side + radius, "type": part["type"]}
