# Third-party code and techniques

Blinko links one third-party library, [Sparkle](https://sparkle-project.org) (MIT), for updates. Everything else is Blinko's own code. Where a technique was learned from another open-source project, it is credited below.

## Lock-screen windows (v0.5)

`Sources/Blinko/Window/LockScreenSpace.swift` is an independent Swift implementation of the technique in:

- **SkyLightWindow** by Lakr Aream (Lakr233) — MIT License, Copyright (c) 2025 Lakr Aream — https://github.com/Lakr233/SkyLightWindow. Learned from it: the SkyLight call sequence (`SLSMainConnectionID`, `SLSSpaceCreate(cid, 1, nil)`, `SLSSpaceSetAbsoluteLevel` with level 400 = `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, windows, 7)`) and `canBecomeVisibleWithoutLogin`.
- **boring.notch** (TheBoredTeam, MPL-2.0) — https://github.com/TheBoredTeam/boring.notch. Learned from it: taking a window back out of the space with `SLSRemoveWindowsFromSpaces`.
- **Atoll** (Ebullioscopic) — https://github.com/Ebullioscopic/Atoll. Learned from it: `sessionDidBecomeActive` and the `CGSSessionScreenIsLocked` session key as fallbacks for a late `com.apple.screenIsUnlocked`.

No source files were copied. Blinko resolves every symbol with `dlsym` and turns the feature off if one is missing, adds space hiding / destruction, state save and restore, and an on-screen check after unlock.

MIT License (SkyLightWindow):

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
