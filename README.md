# MyGame — Simple Obby

A basic obstacle-course (obby) game built with Rojo:

- **Checkpoints** — touch a tagged part to save your progress and respawn there instead of the start.
- **Kill bricks** — touch one and you die instantly (respawns you at your last checkpoint).
- **Coins** — collectible parts that add to a `Coins` stat shown on the leaderboard.
- **Stage counter** — a `Stage` stat on the leaderboard, plus an on-screen "Checkpoint reached!" popup.

## Project layout

```
default.project.json      Rojo project file (maps folders to Roblox services)
src/server/                -> ServerScriptService
  PlayerSetup.server.lua    creates leaderstats (Stage, Coins) per player
  Checkpoints.server.lua    checkpoint touch + respawn logic
  KillBricks.server.lua     instant-death parts
  Coins.server.lua          coin pickup logic
src/shared/                -> ReplicatedStorage
  Tags.lua                  shared list of CollectionService tag names
src/client/                -> StarterPlayer.StarterPlayerScripts
  StageNotifier.client.lua  on-screen "Checkpoint reached!" popup
```

## Building the obby in Studio

The code only reacts to parts that are **tagged** — you still build the actual
course (platforms, ramps, etc.) yourself in Studio, then tag the special parts:

1. Open the **Model** tab in Studio, or use **View > Tag Editor** if you don't see it.
2. Select a part and add one of these tags:
   - `Checkpoint` — also add a Number **attribute** named `Order` (1, 2, 3, ... in the order players should reach them). Add one near the very start with `Order = 1`.
   - `KillPart` — lava, spikes, anything that should kill on touch.
   - `Coin` — collectible parts (works best with `CanCollide` off).

That's it — the scripts find tagged parts automatically, including ones you add later while the game is running.

See the setup walkthrough in the chat/PR description for cloning this repo, running `rojo serve`, and connecting Studio.
