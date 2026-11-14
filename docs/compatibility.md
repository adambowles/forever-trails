# Compatibility and verification

Target: WoW: Forever, interface **16001**, Lua 5.1, stock Blizzard world map.

The implementation was checked against the `forever` branch of the client UI source:

- [Map API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
- [Map canvas](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua)
- [Scrolling and scaling](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/MapCanvas_ScrollContainerMixin.lua)
- [Native gamepad focus manager](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_GamepadSharedUtility/FrameControlsManager.lua)
- [Native gamepad binding stack](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_GamepadSharedUtility/InputBindingStack/InputBindingManager.lua)
- [Stock world-map layer ordering](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua)
- [Protected frame methods](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua)

API availability is not the same as verified in-game behaviour. Automated tests
use a strict mock UI/API harness; an actual Forever client was not available in
the development environment. The initial release is a recording prototype pending
these in-game checks.

## In-game checks

1. Enable Lua errors with `/console scriptErrors 1`. Log in with only Forever Trails enabled.
2. Walk a loop with several sharp turns. Open its zone map: the loop should align
   with the terrain. Pan, zoom, resize, close and reopen the map.
   Check both an outdoor zone and a city: trails must remain visible over explored
   terrain, with quest markers and the player arrow above them.
   Keep the map open while moving with a long history: existing trails should stay
   visible as new points arrive, without disappearing or rebuilding progressively.
3. Browse another zone while walking. Return to the player's zone and confirm the
   new trail was recorded there.
4. Stand still for ten minutes. `/ft status` should show only bounded chunk endpoints,
   rather than hundreds of stationary samples. Resume moving and inspect the route.
5. Hearth, use a portal, cross a zone border and enter/leave a mapped interior.
   No line should bridge a loading screen, map or floor change.
6. Take a flight path, die and travel as a ghost. Each movement transition should
   start its own segment. Enter an unmapped instance: recording should report
   unavailable and resume after leaving.
7. Pause, move, resume: no line across the pause. Hide trails while moving: history
   should continue recording. Clear history and cancel once before confirming.
8. `/reload` and relog: history/settings should survive without joining across
   sessions. Another character should show only its own history.
9. Check behaviour in combat and with any usual map addons enabled. Restricted
   or secret position values must produce a gap and resume without a Lua error.
10. Open **Trails → Trail colour** and try each preset. The visible trail should
    change immediately, including when an update is in progress. Reload and switch
    characters to confirm the selection persists. Hide/show the trail and change
    maps while recording to check that an old drawing never appears on the wrong map.
11. Test map setup while combat-locked after a UI reload. The overlay/controls should
    attach automatically after combat, while `/ft status` shows recording continuing.
    Also enter/leave combat with an existing visible trail and preset grid, checking
    outdoor layering, redraws and the native gamepad UI for blocked-action warnings.
12. Attempt to clear history in combat, and enter combat with a confirmation already
    open. Opening/accepting deletion should be refused until out of combat, preserving
    history. A later deletion must still require a new explicit confirmation.
13. Enable the native gamepad UI. With a long history, repeatedly open/close the
    map using the controller, including while a redraw is in progress. With a mouse,
    open Trails, select colours and cancel/accept history confirmation, then close
    the map with the controller again. Check for blocked-action warnings after each.
    Trails controls use mouse input; they deliberately do not take controller focus.

## If a protected-action warning recurs

The addon now prints the blocked function name to chat once per event/function
per UI session. Include that name, addon version, combat state and triggering action
in the report.

The supplied 14 November 2026 log first blocks at **10:19:22.046**, when
`WorldMapFrameCloseButton:Click()` closes the map from a native controller binding.
`HideUIPanel` broadcasts the hide, `FrameControlsManager` removes a binding set,
and `GamepadMainActionBarFrame:UpdateInteractIcons()` calls the protected
`SetPreferredGamepadInteractTarget()`. Later chat-global writes and Blizzard's
blocked-action popup are downstream of that first failure; the trace does not show
Forever Trails calling the protected function or opening its history confirmation.

The log attributes taint to Forever Trails but does not record its original write,
so it does not prove which individual addon integration introduced it. The 0.1.4
mitigation removes addon callbacks from native map lifecycle dispatch, moves
interactive controls outside the map navigation tree, and replaces shared menus
and history popups. This addresses the exposed focus boundaries rather than
adding further combat checks. It requires a fresh reload and in-game verification;
automated tests cannot establish that it resolves the client-side taint.

Related primary reports: [Questie map cursor taint investigation](https://github.com/Questie/Questie/issues/7899)
and [native gamepad UI callback/slash-command report](https://us.forums.blizzard.com/en/wow/t/game-crashes-native-gamepad-ui-empty-addon-triggers-blocked-action-popup-loop/2367777).
Questie's pin-specific workaround does not apply to this addon, which registers no pins.

For a full trace, run `/console taintLog 2`, then `/reload`, reproduce the warning
and inspect `_forever_/Logs/taint.log` after exiting WoW. Disable further logging
with `/console taintLog 0`. Automated tests cover the guards and mutation boundaries,
but do not emulate WoW's full secure execution or native gamepad focus system.

## Known limits

- Coordinates can be unavailable or restricted; gaps are intentional.
- Zone/floor maps and their map-art IDs are kept distinct. No parent-map projection
  or continuity across different maps is attempted in 0.1.
- `C_Map.GetMapWorldSize` supplies yard-scaled distances where available; otherwise
  movement and simplification use conservative map-relative thresholds.
- Loading/events and generous movement-specific speed bounds detect discontinuities.
  An instantaneous move with no event that falls inside plausible travel bounds
  cannot reliably be distinguished from travel between two one-second observations.
- No terrain, height, obstacle or pathfinding inference is performed.
- Memory, frame-time and SavedVariables sizes still need measurement on the client.
  Point and render limits are safeguards, not measured resource guarantees.
