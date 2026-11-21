# UILibs

## XHlib

The xanhub UI library. Drop-in replacement for xanhub 3.x: same API, flags and config files.

```lua
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/PPainez/UILibs/main/XHlib.lua"))()
library:SetTitle("Example") -- shown in the window title and under the splash logo

local section = library:AddTab("Main"):AddColumn():AddSection("Combat")
section:AddToggle({text = "Enabled", tip = "Turns the feature on", callback = function(on) end})
section:AddSlider({text = "Range", min = 0, max = 100, value = 50, suffix = " studs"})
section:AddList({text = "Mode", values = {"Legit", "Rage"}})

library:Init()
```

Controls: `AddToggle`, `AddButton`, `AddSlider`, `AddList` (single or `multiselect`), `AddBox`, `AddColor` (optional `trans`), `AddBind` (`toggle` or `hold`), `AddLabel`, `AddDivider`. Toggles, sliders and lists accept sub-controls (`toggle:AddColor{}`, `toggle:AddBind{}`, ...).

Built in:

- A splash on execute: the logo types out, then flies into the window title as the menu rises. Click, tap, Escape, Enter or Space skips it (clicks still reach the game). `library.intro = false` turns it off. Roblox's Reduced Motion setting, or `library.reducedMotion = true`, gets a plain fade.
- Animations (window, tabs, popups, toggles, notifications) driven by RenderStepped, so they work on executors that reject TweenService. Off switch: `library.animations = false`.
- The mouse stays free and visible while the menu is open, even in first-person games that lock it every frame. Closing the menu gives the game its cursor back.
- UI sounds for hover, click, toggle, open/close, tab and notifications. Change ids in `library.sounds`, volume with `library.soundVolume`, off with `library.soundsEnabled = false`.
- Settings tab with configs, per-place autoload, accent color, background, and the sound/animation switches.
- `library:SendNotification(seconds, text)`, `library:AddCleanup(fn)`, `library:Unload()`.
