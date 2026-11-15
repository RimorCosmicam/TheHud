# TheHud

A HUD for the Xreal Air, driven by an iPhone. Native Swift and Metal throughout.

The glasses are a display, not a computer: over USB-C they take DisplayPort and show a 1920x1080
image. iOS has no desktop mode and no way to host another app inside this one, so everything on
the glasses is drawn by this app — the surface, the panels and the browser alike.

Requires an iPhone 15 or later with a USB-C port that carries DisplayPort (the 16e and the
iPhone Air do not), and a cable that carries video — the one in the phone's box does not.

## Seeing it without a device

`hudshot` renders the real surfaces to PNG on a Mac. The halftone goes through the same Metal
renderer the app uses and the chrome through the same SwiftUI views, so these are the app's
output at a different size rather than a mockup of it.

```
swift run hudshot --out out
```

It needs only the Command Line Tools: Metal compiles the shader at runtime, so no `metal` CLI and
no Xcode are involved. CI runs the same command on every push and attaches the images to the run.

## Checking the engine

```
swift run hudtests
```

The input engine takes abstract touch frames rather than `UITouch`, so the whole state machine —
pointer filtering, acceleration, tap, drag, two-finger scroll, momentum, the rail — runs here with
no device and no simulator. `glasses-pointer.png` goes further and drives a real swipe through the
real recogniser into the real cursor, so if the pointer in that image is misplaced, the engine is
wrong.

These are a plain executable rather than a `.testTarget` because XCTest and swift-testing both
ship with Xcode, and this runs with the Command Line Tools alone.

## The app

`App/TheHud` is the iOS app: a UIKit app lifecycle with two scenes. The phone scene owns the
surface and the input; the glasses arrive as a second scene in the non-interactive external
display role and only draw. Unplugging the cable tears down a scene, not the session.

The project is generated rather than committed:

```
brew install xcodegen && xcodegen
```

This machine has no Xcode, so CI is the first place the app is compiled at all. See the note in
`Scenes.swift` about the scene-accessory registration iOS 27 may require.

## Where the data comes from

| Panel | Source | Needs |
|---|---|---|
| Clock | Foundation | nothing |
| Next event | EventKit | one permission prompt |
| Weather | Open-Meteo | network |
| Minimap ground | MKMapSnapshotter | network, location |
| Position, heading, speed | CoreLocation | one permission prompt |
| Browser | WKWebView | network |

Each panel degrades on its own. No calendar access drops one line, no location leaves the map
blank, a failed weather fetch keeps the last reading — none of them can take the HUD down.

**Weather is Open-Meteo, not WeatherKit, and that is a trade.** WeatherKit is the native option
but needs a paid Apple Developer account, an App ID with the capability, an entitlement and
display attribution; none of which a free account or an unsigned CI build has. Open-Meteo needs no
account and no key, so the HUD works today and the preview tool can fetch the same data on a Mac.
The cost is privacy: WeatherKit keeps the request inside Apple's privacy policy, Open-Meteo means
the device's coordinates go to a third party. Fine for a personal build; swap to WeatherKit before
this reaches anyone else. The provider is behind `WeatherProviding` so that is one type.

The preview renders real weather and a real map with `--live`:

```
swift run hudshot --live
```

It uses a fixed Lisbon coordinate rather than CoreLocation — a command line tool has no good way
to ask for location permission, and sending a real location to a third party to make a preview
would be a poor trade. Without `--live` nothing leaves the machine, which is what keeps CI
deterministic.

## Layout

The surface is exactly half the display and pinned to the bottom edge. Icons and settings sit
above it; the system keyboard rises from the lower edge and pushes everything up, which spends the
settings area rather than the surface.

Nothing tappable belongs below the toolbar — everything under it is swept blind by a thumb.

## What came from MiniMate

The surface is MiniMate's default halftone scene with the Mustard palette, ported 1:1: the AGSL
scene body, the shared header and footer, the touch warp, the ACES tone curve, the grain and
vignette, and the radial chromatic aberration as a second pass. The edge controls — the scroll
rail and the right-click corner, CRYSTAL material, mirrored as a pair — carry over with their
measurements intact, as does the Mont panel material and the typeface.

The input engine comes over whole: the 1 euro filter, the acceleration curve with its sub-pixel
accumulator, tap-to-click, double-tap drag, two-finger scroll and right click, momentum, and the
rail's scroll maths. MiniMate's own unit tests came with it.

Where MiniMate speaks Bluetooth HID to a Mac, this drives a cursor inside the app's own glasses
canvas, so there is no pairing and no companion.

Mont is a commercial typeface. It is here because it is already licensed for MiniMate; check the
licence covers this before shipping.
