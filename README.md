# Draggable Items (Physics)

One script: anything tagged `Draggable` can be grabbed and dragged around with
real physics — it has weight, collides with things, and falls when you let go.

## Project layout

```
default.project.json       Rojo project file (maps folders to Roblox services)
src/server/                 -> ServerScriptService
  Draggables.server.lua      gives every tagged item a physics DragDetector
src/shared/                 -> ReplicatedStorage
  Tags.lua                   shared list of CollectionService tag names
src/client/                 -> StarterPlayer.StarterPlayerScripts (empty for now)
```

## Setting up an item in Studio

1. Make a Part or Model. Leave it **unanchored** (Anchored = false).
2. Tag it `Draggable` (Properties > Tags, or Model tab > Tag Editor).

Press Play, then click-hold and drag it. Works on PC and mobile automatically.
