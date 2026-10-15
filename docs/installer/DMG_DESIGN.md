# DMG design

The installer is a 600×400 Finder window with a dark CastSprint background, the app at x=160, an Applications alias at x=440, and a clear left-to-right install cue. The source artwork is:

- `assets/dmg/installer-background.png`
- `assets/dmg/installer-background@2x.png`

The packaging script creates a writable image, applies Finder layout where GUI scripting is available, then converts it to compressed UDZO. Headless packaging retains a functional DMG even if Finder layout scripting is unavailable.

