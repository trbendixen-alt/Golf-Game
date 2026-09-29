class_name GameSettings
extends RefCounted
## Player settings. For now these are just placeholders that the pause menu can
## flip on and off; nothing listens to them yet (there's no audio or haptics until
## a later milestone). They also aren't saved yet.

static var sound_on := true
static var haptics_on := true
