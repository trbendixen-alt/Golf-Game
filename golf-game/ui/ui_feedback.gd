class_name UiFeedback
extends RefCounted
## One place for "the player pressed something" feedback: a click sound and a haptic
## buzz. Every StreetButton calls press().
##
## There is no audio system yet (Milestone 8), so the sound is a HOOK: when an
## AudioManager exists, it sets `sound_hook` to a function that plays a sound by name:
##     UiFeedback.sound_hook = func(sound_name: StringName) -> void: AudioManager.play(sound_name)
## The haptic works already on phones (a short vibration) and can be replaced the same way.
## Both respect the Sound and Haptics switches in Settings.

## Called with the sound's name, e.g. &"ui_click". Empty = silent for now.
static var sound_hook := Callable()
## Called with the strength, e.g. &"light". Empty = use the phone's built-in short buzz.
static var haptic_hook := Callable()

const DEFAULT_BUZZ_MS := 12


static func press() -> void:
	if GameSettings.sound_on and sound_hook.is_valid():
		sound_hook.call(&"ui_click")
	if GameSettings.haptics_on:
		if haptic_hook.is_valid():
			haptic_hook.call(&"light")
		elif OS.has_feature("mobile"):
			Input.vibrate_handheld(DEFAULT_BUZZ_MS)
