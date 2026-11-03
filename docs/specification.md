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
Let the existing ScrollFrame clip and transform the layer. Rebuild when data, map,
canvas dimensions or zoom changes; cancel stale jobs when the map changes or closes.

Process at most 300 input points per rendered frame. Simplify against a 1.25-pixel
tolerance, preserve corners, and emit recent segments first. Reuse at most 4,096
line pairs with a dark border and green centre. Display capping never changes
stored history. No overlay work runs while the map is closed or trails are hidden.

## Release contract

Branch pushes excluding `main`: Lua 5.1 syntax, behaviour/integration tests, TOC
validation and Python packaging/release-guard tests. No uploaded artifacts.

Version-tag pushes: fetch `main`, verify the checkout matches the tag, verify the
tag matches the TOC version and that its peeled commit belongs to `main`, then
publish the installable ZIP and SHA-256 sidecar. No tests or container images.

All addon work goes through a feature-branch PR. Tagging and merging are separate
reviewer actions. No release tag is created by the implementation PR itself.
