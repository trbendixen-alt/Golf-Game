class_name StreetButton
extends Button
## A chunky Street Golf button: the sunken "pressed" look comes from the theme (see
## ui/theme/street_golf.tres); this adds a quick squash-and-bounce when pressed, plus the
## click-sound and haptic hooks (see UiFeedback).
##
## Set `theme_type_variation` to "BigGreenButton" or "OrangeButton" (or leave it for the
## default green) and give it the theme. Works like any other Button: connect `pressed`.

const PRESS_SCALE := 0.965
const DOWN_SECONDS := 0.05
const UP_SECONDS := 0.16

var _tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE  # No focus frame; it's a touch game.
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	pivot_offset = size / 2.0
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func _on_down() -> void:
	UiFeedback.press()
	_animate_to(Vector2.ONE * PRESS_SCALE, DOWN_SECONDS, Tween.TRANS_QUAD)


func _on_up() -> void:
	_animate_to(Vector2.ONE, UP_SECONDS, Tween.TRANS_BACK)


func _animate_to(target: Vector2, seconds: float, transition: Tween.TransitionType) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", target, seconds).set_trans(transition).set_ease(Tween.EASE_OUT)
