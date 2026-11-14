# Forever Trails: 0.1

## Data flow

`C_Timer` (one second) → validated player-map position → discontinuity detection →
movement threshold and bounded streaming simplification → SavedVariables store →
current-zone index → incremental world-map overlay.

`Compat.lua` contains the client API boundary. All recorded numbers must be finite
and non-secret. Neither player-map queries nor recording depend on which map the
user has open. Unsupported schemas are preserved and disable recording rather
than silently replacing saved history.

## Recording

- Poll every one second; do not replay missed timer ticks after a stall.
- Use a two-yard movement threshold and one-yard simplification tolerance when
  map dimensions are available; otherwise 0.0004 and 0.0002 of map size.
- Retain the latest endpoint and corners. Collapse only forward, near-collinear
  points over at most ten seconds, preserving backtracking and idle timing.
- Store positions during ordinary travel, mount travel, swimming, taxis and ghost
  travel. Keep each category in separate segments.
- Split on map/art/distance-space/movement changes, invalid positions, loading,
  pause/resume, death/resurrection, backwards time, gaps over five seconds and
  position jumps exceeding generous travel bounds.
- Bound segments to 512 points or five minutes. Repeat the previous endpoint in
  a new storage chunk to maintain visual continuity within the same coordinate space.

## Schema 1

`ForeverTrailsDB = { schemaVersion, settings, characters[GUID] }`

| Record | Stored fields |
| --- | --- |
| Character | Name, realm, sessions, point count |
| Session | Start/end epoch times, ordered segments |
| Segment | Map/art IDs, distance space and dimensions, movement category, start/end times, break reason, points |
| Point | Compact array `{ normalisedX, normalisedY, secondsSinceSegmentStart }` |

There is no persistent active-session pointer. Each UI load starts fresh segments;
existing segments remain readable. Runtime indexes reference the current character's
segments by map ID. A chronological account queue enforces retention; counts are
reconstructed from actual points at startup.

## Rendering

Attach a data provider and a non-interactive line layer to the stock map canvas.
Read the map's existing frame-level ordering and position only addon-owned frames
one level above `PIN_FRAME_LEVEL_MAP_HIGHLIGHT`. In the stock Forever map this
sits in the debug band below normal foreground markers. Do not insert layer
definitions or re-level Blizzard/other-addon pins. Cache the applied level and
change it only when needed, outside combat lockdown.
Let the existing ScrollFrame clip and transform the layer. Rebuild when data, map,
canvas dimensions or zoom changes; cancel stale jobs when the map changes or closes.

Process at most 300 input points or pooled-line cleanups per rendered frame.
Simplify against a 1.25-pixel tolerance, preserve corners, and emit recent segments
first. Prepare updated geometry in a hidden buffer while keeping the last completed
drawing visible; swap buffer visibility only after all geometry and cleanup finish.
Discard both drawings and pending work when the map changes, trails are hidden,
history is cleared or canvas dimensions change. Ordinary recording/zoom updates
keep the completed drawing until its replacement is ready.

Reuse two pools, each capped at 4,096 line pairs (16,384 Line regions total). Both
buffers share the managed trail level below foreground markers. Display capping
never changes stored history. No overlay work runs while the map is closed or
trails are hidden.

Use a dark border and a preset-coloured centre. The map menu offers Green, Cyan,
Blue, Gold, Red and White. Store the preset ID in `settings.trailColour`, defaulting
older or invalid settings to Green. Recolour used lines in both buffers immediately
without rebuilding geometry; subsequent points use the current setting.

## Protected UI boundaries

Defer the initial map overlay and controls setup during combat lockdown, retrying
on `PLAYER_REGEN_ENABLED`. Reapply any deferred own-frame level then, without
breaking the recording segment. Existing unprotected trail drawing and sampling
can continue during combat.

Recording ticks and render commits update addon-owned status controls only. Native
dropdown selection updates are handled by its normal show/response lifecycle.
Do not open the shared history confirmation popup during combat, and recheck before
accepting deletion; refused deletion is not automatically queued.

Listen for `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN` for Forever Trails
and print the function name once per event/function per UI session. Leave Blizzard's
warning behaviour intact. This helps identify remaining taint paths; mock tests
cannot establish that the client is entirely free of taint.

## Release contract

Branch pushes excluding `main`: Lua 5.1 syntax, behaviour/integration tests, TOC
validation and Python packaging/release-guard tests. No uploaded artifacts.

Version-tag pushes: fetch `main`, verify the checkout matches the tag, verify the
tag matches the TOC version and that its peeled commit belongs to `main`, then
publish the installable ZIP and SHA-256 sidecar. No tests or container images.

All addon work goes through a feature-branch PR. Tagging and merging are separate
reviewer actions. No release tag is created by the implementation PR itself.
