# Compatibility and verification

Target: WoW: Forever, interface **16001**, Lua 5.1, stock Blizzard world map.

The implementation was checked against the `forever` branch of the client UI source:

- [Map API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
- [Map canvas](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua)
- [Data provider hooks](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/MapCanvas_DataProviderBase.lua)
- [Scrolling and scaling](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/MapCanvas_ScrollContainerMixin.lua)

API availability is not the same as verified in-game behaviour. Automated tests
use a strict mock UI/API harness; an actual Forever client was not available in
the development environment. The initial release is a recording prototype pending
these in-game checks.

## In-game checks

1. Enable Lua errors with `/console scriptErrors 1`. Log in with only Forever Trails enabled.
2. Walk a loop with several sharp turns. Open its zone map: the loop should align
   with the terrain. Pan, zoom, resize, close and reopen the map.
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
