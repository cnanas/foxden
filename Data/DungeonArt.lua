-- Each dungeon and raid's picture, from the game's own files (WoW Forever build 1.60.1): the dungeon
-- journal's "lore" picture for classic ones (JournalInstance.LoreFileDataID, 512x512 with a frame; the classic raids' from retail's table), else
-- Forever's loading screen (LoadingScreens.MainImageFileDataID, letterboxed). Generated: don't edit by hand.
local _, ns = ...
-- [instanceID] = { fileDataID, "lore" | "screen" }
ns.DungeonArt = {
  [389] = { 608250, "lore" }, -- Ragefire Chasm
  [3065] = { 7963781, "screen" }, -- The Hall of Thanes
  [2999] = { 7963782, "screen" }, -- Ruins of Lordaeron
  [36] = { 526404, "lore" }, -- Deadmines
  [43] = { 608313, "lore" }, -- Wailing Caverns
  [33] = { 526410, "lore" }, -- Shadowfang Keep
  [2998] = { 7963777, "screen" }, -- Excavation Site: Wetlands
  [48] = { 608234, "lore" }, -- Blackfathom Deeps
  [34] = { 608262, "lore" }, -- Stormwind Stockade
  [2959] = { 7963775, "screen" }, -- City of Dalaran
  [47] = { 608252, "lore" }, -- Razorfen Kraul
  [90] = { 608241, "lore" }, -- Gnomeregan
  [189] = { 608253, "lore" }, -- Scarlet Monastery
  [2970] = { 7963741, "screen" }, -- The Drowned City
  [129] = { 608251, "lore" }, -- Razorfen Downs
  [3039] = { 7963780, "screen" }, -- Krol'dok Stronghold
  [70] = { 608264, "lore" }, -- Uldaman
  [209] = { 608267, "lore" }, -- Zul'Farrak
  [2994] = { 7963734, "screen" }, -- Alcaz Prison
  [349] = { 608248, "lore" }, -- Maraudon
  [109] = { 608256, "lore" }, -- Sunken Temple
  [230] = { 608235, "lore" }, -- Blackrock Depths
  [429] = { 608239, "lore" }, -- Dire Maul
  [229] = { 608236, "lore" }, -- Blackrock Spire
  [2974] = { 7963784, "screen" }, -- Blackmaw Hold
  [329] = { 608255, "lore" }, -- Stratholme
  [3001] = { 7963783, "screen" }, -- The Shaper's Terrace
  [289] = { 608254, "lore" }, -- Scholomance
  [309] = { 526416, "lore" }, -- Zul'Gurub
  [409] = { 1396505, "lore" }, -- Molten Core
  [249] = { 1396508, "lore" }, -- Onyxia's Lair
  [469] = { 1396499, "lore" }, -- Blackwing Lair
  [509] = { 1396510, "lore" }, -- Ruins of Ahn'Qiraj
  [531] = { 1396512, "lore" }, -- Ahn'Qiraj Temple
  [533] = { 1396506, "lore" }, -- Naxxramas
}
