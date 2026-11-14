# Changelog

## 0.1.2

- Fix trail flashing when new points are recorded: keep the completed trail visible
  while preparing its replacement, then swap drawings within one frame.
- Add Green, Cyan, Blue, Gold, Red and White presets to the Trails map menu, with
  immediate colour changes and a saved account-wide selection.
- Reuse two bounded line pools and discard stale drawings when changing maps,
  hiding trails or clearing history.

## 0.1.1

- Fix outdoor trails being hidden beneath explored-terrain textures by using a
  managed map layer above terrain, fog and map highlights, below foreground markers.
- Keep existing map pins and the trail layer aligned with managed frame levels.
- Add regression coverage for outdoor layering, existing markers and map refreshes.

## 0.1.0

- Record character travel at one-second intervals, with simplified straight paths
  and explicit breaks around loading screens, map changes and unavailable positions.
- Draw retained zone trails in green using pooled lines and incremental rendering.
- Add map controls and slash commands for visibility, recording, status and confirmed deletion.
- Persist character-separated history with bounded account and character retention.
- Add Lua behaviour tests and independent branch-test and tagged-release workflows.
