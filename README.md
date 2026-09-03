# Draggable Items (Physics Carry)

Click and hold any tagged item to carry it on a springy physics leash in front
of your camera — crosshair in first person, mouse cursor in third person —
while keeping full camera and movement control. Items collide with the world
and players, swing naturally, and drop when you release.

## Project layout

```
default.project.json        Rojo project file (maps folders to Roblox services)
src/server/                  -> ServerScriptService
  Draggables.server.lua       RemoteEvents, anti-cheat checks, network
                              ownership handoff, CanCollide enforcement
src/shared/                  -> ReplicatedStorage
  Tags.lua                    shared list of CollectionService tag names
src/client/                  -> StarterPlayer.StarterPlayerScripts
  DragController.client.lua   the carry itself: raycast grab, AlignPosition
                              leash, per-frame target in front of the camera
```

## Setting up an item in Studio

1. Make a Part or Model. Leave it **unanchored** (Anchored = false).
   For a Model: weld its parts together and set a PrimaryPart.
2. Tag it `Draggable` (Properties > Tags, or Model tab > Tag Editor).

## Slot pads (tag: `AttachSurface`)

A slot pad holds exactly **one** item. Drop a draggable item on a pad and it
snaps centered onto it and sticks (invisible weld); grab it to take it off.

- **On a counter:** anchor the pad where items should be placeable.
- **On a draggable object:** make the pad unanchored, weld it to the object
  (e.g. a cookie sheet) with a Studio WeldConstraint - carrying the sheet
  then carries every slotted item along.

## Keep-upright items (tag: `KeepUpright`)

Tag an item `KeepUpright` and it gets a gentle self-righting nudge - like a
weighted-bottom toy. It can still tip, tumble, and wobble (nothing is
locked); it just prefers to end up standing. Good for the milk carton and
flour bag. Strength knobs (`UPRIGHT_TORQUE_PER_MASS`, `UPRIGHT_RESPONSIVENESS`)
are at the top of `Draggables.server.lua`.

## Oven & raw dough

- Tag raw dough items `UncookedCookie` (plus `Draggable` so they can be
  carried). Any shape/color works.
- Make an invisible part filling the inside of your oven: Anchored = true,
  CanCollide = false, Transparency = 1, tagged `Oven`.
- Dough that sits inside the oven region for ~6 seconds turns cooked brown
  (and stops being `UncookedCookie`). Pulling it out early resets progress.
  Bake time and the cooked color are constants at the top of
  `Draggables.server.lua`.

Press Play, then click-hold an item and walk/look around while carrying it.
Tuning knobs (hold distance, pull strength, grab range) are constants at the
top of `DragController.client.lua`.
