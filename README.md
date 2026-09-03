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

## Attach surfaces (cookie sheets, trays, counters)

Tag a part `AttachSurface` and any draggable item dropped on top of it
sticks in place (an invisible weld). Grab a stuck item to take it back off.

- Tag a part with **both** `Draggable` and `AttachSurface` for a carryable
  tray: carry the cookie sheet and everything stuck to it rides along.
- An **anchored** part tagged `AttachSurface` (a counter, a shelf) holds
  items exactly where you set them down.

Press Play, then click-hold an item and walk/look around while carrying it.
Tuning knobs (hold distance, pull strength, grab range) are constants at the
top of `DragController.client.lua`.
