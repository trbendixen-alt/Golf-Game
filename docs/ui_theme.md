# The Street Golf UI theme

Everything that gives the menus their look is in **one Godot theme**: `golf-game/ui/theme/street_golf.tres`.
The main menu and Settings screen use it today. Mode select, the pause menu, Stats, Clubs and the round
summary still have their old plain look; to restyle one, set `theme = preload("res://ui/theme/street_golf.tres")`
on its root Control and use the variations below. (Setting it as the project theme in Project Settings
would restyle every screen at once.)

## What's in it

| Item | Name | Notes |
|---|---|---|
| Buttons | `Button` (green), `BigGreenButton` (PLAY size), `OrangeButton` | Lilita One, navy outline, glossy 9-slice images with a sunken pressed look |
| Labels | `TitleLabel`, `TaglineLabel`, `VersionLabel` | `TitleLabel` is white on purpose: put `ui/theme/title_gradient.gdshader` in its Material to get the yellow-orange gradient |
| Rich text | `ChipText` | Fredoka Bold. Use BBCode: `[color=#ffd84a]3[/color]` |
| Panels | `ChipPanel`, `PillPanel` | Navy rounded panels (PillPanel has the gold border) |
| Palette and fonts | type `StreetGolf`: colours `navy`, `navy_deep`, `gold`, `yellow`, `green`, `orange`; fonts `title`, `body`, `body_bold` | `theme.get_color("gold", "StreetGolf")` |

Use `StreetButton` (`ui/street_button.gd`) instead of a plain `Button` to get the press squash animation and the
click-sound / haptic hooks (`ui/ui_feedback.gd`). Use `MenuBackdrop` (`ui/menu_backdrop.gd`) for the animated
street background.

## Changing the look

Edit the colours and numbers at the top of `tools/build_ui_theme.gd`, then run its three steps (written in the file's
header): draw the button images, import, build the theme. You can also tweak `street_golf.tres` by hand in Godot.

## Hooks for later

`UiFeedback.sound_hook` and `UiFeedback.haptic_hook` are empty callables until Milestone 8 (audio and haptics).
Set them once and every StreetButton in the game gets sound and buzz, and both already obey the Settings switches.
