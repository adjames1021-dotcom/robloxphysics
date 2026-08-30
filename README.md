# Bakery Game — Drag & Drop System

Drag ingredients and tools (pots, pans) around the kitchen and snap them into
place: burners, mixing spots, counter slots.

## Project layout

```
default.project.json       Rojo project file (maps folders to Roblox services)
src/server/                 -> ServerScriptService
  DragAndDrop.server.lua     the whole drag & snap system
src/shared/                 -> ReplicatedStorage
  Tags.lua                   shared list of CollectionService tag names
src/client/                 -> StarterPlayer.StarterPlayerScripts (empty for now)
```

## Setting up items in Studio

**Draggable items** (flour, eggs, pots, pans...):
1. Build a Part or Model, set **Anchored = true**.
2. Tag it `Draggable` (Model tab → Tag Editor, or Properties → Tags).
3. Optional: add a String attribute `ItemType`, e.g. `Flour`, `Egg`, `Pot`.

**Drop zones** (where items snap to):
1. Make a thin flat Part where the item should land. Transparency ~0.5 looks good.
2. Tag it `DropZone`.
3. Optional: add a String attribute `Accepts` — a comma list of ItemTypes it
   takes (`Flour,Egg`, or just `Pot`). No attribute = accepts anything.

## What players experience

- Click/touch and drag any tagged item — works on PC and mobile automatically
  (Roblox's built-in DragDetector handles the input).
- While dragging, every free zone that accepts the item glows green.
- Release near a glowing zone → the item snaps neatly on top of it.
- Release anywhere else → the item returns to where it was picked up.
- One item per zone; picking an item back up frees its zone.
