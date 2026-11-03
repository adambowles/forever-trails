# Forever Trails

**Every adventure leaves a trace.**

Forever Trails records your character's travels in WoW: Forever and draws a green
trail on the world map, inspired by Hero's Path in Breath of the Wild.

## Install

Download `ForeverTrails-<version>-Forever.zip` from
[GitHub Releases](https://github.com/adambowles/forever-trails/releases).
Extract the `ForeverTrails` folder into `_forever_/Interface/AddOns/`, then restart
WoW or enable it in the AddOns list. The resulting path must be
`_forever_/Interface/AddOns/ForeverTrails/ForeverTrails.toc`.

## Use

Recording starts automatically, with a position check **every one second**.
Open a zone map and click **Trails** to show/hide the trail, pause/resume recording,
see retained points and the oldest recording, or clear this character's history
with confirmation. Hiding the overlay does not pause recording.

| Command | Action |
| --- | --- |
| `/ft status` | Version, sampling interval, recording status and storage counts |
| `/ft pause` / `/ft resume` | Pause or resume recording |
| `/ft show` / `/ft hide` | Show or hide trails |
| `/ft clear` | Confirm deletion of this character's history |

`/forevertrails` also works. Each character has its own trail. History is kept
locally in the account-wide `ForeverTrailsDB` SavedVariables; there is no network
service or sharing with other players.

## Current scope

The 0.1 prototype displays the current character's retained route on its original
zone, city or supported interior/floor map. Flight paths and ghost travel are
recorded as separate segments. Loading screens, map/floor or movement changes,
invalid coordinates, long sample gaps and implausible position jumps break the
line. Browsing another map does not affect the recorded player position.

Straight paths are simplified; turns and idle arrival/departure timing are kept.
The history limits are 200,000 points per character and 500,000 across the account.
Oldest complete segments are removed when either limit is reached. These are
point limits, not a promised number of hours of history.

Large overlays are built incrementally with reused line regions. The display
prioritises recent sections and caps visible edges at 4,096; exceeding that cap
does not delete recordings. The Trails panel reports when the display is capped.

Playback, date filters, alt browsing and continent-wide projection are planned
for later versions. The stock Blizzard world map is the initial target; map
replacement addons are not yet verified.

SavedVariables are written by WoW during its normal save lifecycle. A crash can
lose recent recordings. Back up `WTF/Account/<account>/SavedVariables/ForeverTrails.lua`
while the game is closed before modifying or moving history.

## Development and releases

The TOC `## Version` is the sole application-version source. Runtime UI and the
release archive name both derive from it.

```sh
lua5.1 tests/run.lua
python3 scripts/package.py --check
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Feature-branch pushes run tests. Plain pushes to `main` do nothing. After merging,
push a matching tag such as `v0.1.0` on a commit belonging to `main`; the separate
release workflow validates the tag and builds a ZIP plus SHA-256 checksum as
GitHub Release assets. It does not rerun the tests. Tags pointing outside `main`
or disagreeing with the TOC version are rejected.

See [compatibility and in-game checks](docs/compatibility.md) and the
[implementation specification](docs/specification.md).
