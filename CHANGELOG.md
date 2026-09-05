# Changelog

Newest changes first. Dates are when the change was pushed to this repo.

## 2026-09-05 — Cookie sheet reliability pass
- Fixed cookies hovering in the air after snapping: the server now takes
  physics control of the item during the snap, so the previous carrier's
  machine can't overwrite the teleport with stale positions.
- Grabbing any welded piece of a cookie (e.g. a chocolate chip) now frees
  the whole cookie from the sheet instead of fighting the weld.
- Moving one cookie no longer disturbs the sheet or the other cookies on
  it (the welded-group search stops at the holder).
- Grid spots free themselves automatically if their item is unwelded or
  destroyed by other means.
- Added this changelog.

## 2026-09-05 — Welded multi-part items & tidier snapping
- Items built from several welded objects (cookie disc + chips) teleport
  as one unit when snapping onto a holder (previously only the tagged part
  moved and physics launched the rest skyward).
- Snapped items are laid flat, aligned with the sheet, resting on their
  true lowest point.
- Holder grid is inset away from the tray lip; snap range reduced to
  2.5 studs; faster settle check.
- Baking skips parts with "chip" in their name so chocolate chips stay
  chocolate-colored.

## 2026-09-05 — 6-item holders + cookie sheet model
- Replaced the one-pad-per-item slot system: a single part tagged
  `AttachSurface` now holds up to 6 draggable items in an invisible 3x2
  grid across its top.
- Added a simple lipped metal cookie sheet mesh (`assets/cookie_sheet/`).

## 2026-09-05 — Baking & self-righting
- New tags: `UncookedCookie` (raw dough) and `Oven` (invisible baking
  region). Dough inside an oven for ~6 seconds turns cooked brown;
  pulling it early resets progress.
- New `KeepUpright` tag: gently nudges items back to standing like a
  weighted-bottom toy, without locking their rotation.

## 2026-09-05 — Attach surfaces
- Dropped items stick to tagged surfaces (cookie sheets, counters) via
  invisible welds; grabbing takes them back off. Later superseded by the
  6-item holder grid.

## 2026-09-05 — Physics carry system
- Replaced DragDetector dragging (which froze the camera in first person)
  with a custom carry: click-hold carries the item on a springy physics
  leash in front of the camera, full camera/movement control, real
  collisions, server-validated via RemoteEvents, lag-free through
  network ownership handoff.

## 2026-09-05 — Ingredient models
- Low-poly ingredient set with printed-label textures: paper flour bag,
  butter stick, milk carton, egg, chocolate chip bag (`assets/`).
- Textures later upgraded with real typography, corrected proportions,
  paper grain, and per-item folders.

## 2026-09-05 — Project setup
- Rojo project structure (`default.project.json`, `src/server`,
  `src/shared`, `src/client`) with tag-driven draggable physics items.
