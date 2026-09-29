class_name ShotController
extends Node
## The three-tap swing meter. It only tracks meter values; it doesn't move the ball.
##
## Tap 1: start swing (power bar begins to fill)
## Tap 2: set power (bar stops; accuracy marker starts sweeping)
## Tap 3: set accuracy (marker stops, shot is fired)
##
## When the third tap happens it emits `shot_fired` and the hole scene launches the ball.

## power: 0.0 to 1.0.  accuracy: -1.0 (far left) to 1.0 (far right), 0.0 = perfect.
signal shot_fired(power: float, accuracy: float)

enum State { IDLE, POWER, ACCURACY, LOCKED }

const POWER_SECONDS := 1.0    # Time for the power bar to fill from 0% to 100%.
const ACCURACY_SECONDS := 0.8 # Time for the marker to cross from far left to far right.
## Half-width of the green "sweet spot" in the centre of the accuracy bar (0..1 scale).
## The swing meter draws this; later milestones will use it for shot quality.
const SWEET_SPOT := 0.1

var state := State.IDLE
var power := 0.0
var accuracy := 0.0

# +1 while a value is rising / moving right, -1 while it is falling / moving left.
var _power_direction := 1.0
var _accuracy_direction := 1.0


## Call this every time the player taps the screen.
func tap() -> void:
	match state:
		State.IDLE:
			state = State.POWER
			power = 0.0
			_power_direction = 1.0
		State.POWER:
			state = State.ACCURACY
			accuracy = -1.0
			_accuracy_direction = 1.0
		State.ACCURACY:
			state = State.LOCKED
			shot_fired.emit(power, accuracy)
		State.LOCKED:
			pass  # Ball is in flight; taps are ignored until reset().


## Get ready for the next swing.
func reset() -> void:
	state = State.IDLE
	power = 0.0
	accuracy = 0.0


func _process(delta: float) -> void:
	match state:
		State.POWER:
			# The bar bounces up and down between 0 and 1 until the player taps.
			power += _power_direction * delta / POWER_SECONDS
			if power >= 1.0:
				power = 1.0
				_power_direction = -1.0
			elif power <= 0.0:
				power = 0.0
				_power_direction = 1.0
		State.ACCURACY:
			# The marker sweeps back and forth between -1 and 1.
			accuracy += _accuracy_direction * 2.0 * delta / ACCURACY_SECONDS
			if accuracy >= 1.0:
				accuracy = 1.0
				_accuracy_direction = -1.0
			elif accuracy <= -1.0:
				accuracy = -1.0
				_accuracy_direction = 1.0
