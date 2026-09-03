-- Names of the CollectionService tags used across the game.
return {
	Draggable = "Draggable", -- anything the player can pick up and drag around

	AttachSurface = "AttachSurface", -- an ITEM HOLDER: holds up to 6 draggable
	-- items in an invisible 3x2 grid across its top. Drop an item on or near
	-- it -> the item snaps into the nearest empty spot and sticks. Grab the
	-- item -> it comes off. Tag a cookie sheet (also Draggable) or a counter.

	UncookedCookie = "UncookedCookie", -- raw dough: bakes when inside an Oven

	Oven = "Oven", -- an invisible region part: anything tagged UncookedCookie
	-- that sits inside it for a few seconds turns cooked brown

	KeepUpright = "KeepUpright", -- gently nudges the item back upright, like a
	-- weighted-bottom toy: it can still tip and tumble, it just rights itself
}
