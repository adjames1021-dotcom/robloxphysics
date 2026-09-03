-- Names of the CollectionService tags used across the game.
return {
	Draggable = "Draggable", -- anything the player can pick up and drag around

	AttachSurface = "AttachSurface", -- a SLOT PAD: holds exactly one item.
	-- Drop an item on it -> the item snaps centered onto the pad and sticks.
	-- Grab the item -> it comes off. Anchor a pad on a counter, or weld an
	-- unanchored pad onto a draggable object (like a cookie sheet) in Studio.

	UncookedCookie = "UncookedCookie", -- raw dough: bakes when inside an Oven

	Oven = "Oven", -- an invisible region part: anything tagged UncookedCookie
	-- that sits inside it for a few seconds turns cooked brown

	KeepUpright = "KeepUpright", -- gently nudges the item back upright, like a
	-- weighted-bottom toy: it can still tip and tumble, it just rights itself
}
