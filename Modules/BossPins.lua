-- Module: BossPins. Where each boss stands on a dungeon's map, for the Journal's Map tab.
-- Forever's game data doesn't say, so pins come from:
--   1. pins you or a guildmate placed (Map tab > Place bosses), saved in FoxdenDB.bossPins
--   2. Blizzard's own boss positions that Foxden ships (below), for the dungeons Forever kept
-- A placed pin names its floor by floor id (ns.DungeonFloors: "RazorfenDowns1" for a client map
-- picture, "m300" for a game map); a shipped one by floor number, "#2". Coordinates are 0..1000
-- across the picture.
--
-- Messages (prefix "Foxden", GUILD): "BP <dungeon slug> <boss> <floor id> <x> <y>" when you place
-- a pin; x = -1 removes it. Only after the welcome popup, like everything else Foxden sends.

local _, ns = ...
local PREFIX = "Foxden"

-- [dungeon name] = { [boss] = { floor number, x, y } }: Blizzard's own boss positions (the JournalEncounter
-- table, Mists of Pandaria Classic build 5.5.4), for dungeons whose bosses and maps Forever kept. Left out:
-- the ones Blizzard rebuilt later (Ragefire, Deadmines, Shadowfang, Scarlet Monastery, Scholomance, Zul'Gurub)
-- and Blackrock Spire (its floors don't line up), plus Forever's new dungeons. Those need placing in game.
local SEEDS_BY_NAME = {
  ["Wailing Caverns"] = {
    ["Lady Anacondra"] = { 1, 306, 430 },
    ["Lord Cobrahn"] = { 1, 167, 568 },
    ["Kresh"] = { 1, 385, 361 },
    ["Lord Pythas"] = { 1, 191, 395 },
    ["Skum"] = { 1, 623, 744 },
    ["Lord Serpentis"] = { 1, 616, 539 },
    ["Verdan the Everliving"] = { 1, 555, 465 },
    ["Mutanus the Devourer"] = { 1, 346, 137 },
  },
  ["Blackfathom Deeps"] = {
    ["Ghamoo-ra"] = { 1, 333, 607 },
    ["Lady Sarevess"] = { 1, 112, 390 },
    ["Old Serra'kis"] = { 3, 587, 309 },
    ["Twilight Lord Kelris"] = { 2, 524, 808 },
    ["Aku'mai"] = { 2, 855, 864 },
  },
  ["Razorfen Kraul"] = {
    ["Aggem Thorncurse"] = { 1, 802, 516 },
    ["Death Speaker Jargba"] = { 1, 873, 422 },
    ["Overlord Ramtusk"] = { 1, 571, 305 },
    ["Agathelos the Raging"] = { 1, 81, 689 },
    ["Charlga Razorflank"] = { 1, 217, 314 },
  },
  ["Gnomeregan"] = {
    ["Grubbis"] = { 1, 779, 670 },
    ["Viscous Fallout"] = { 2, 760, 465 },
    ["Electrocutioner 6000"] = { 2, 243, 684 },
    ["Crowd Pummeler 9-60"] = { 3, 432, 883 },
    ["Mekgineer Thermaplugg"] = { 4, 311, 303 },
  },
  ["Razorfen Downs"] = {
    ["Tuten'kash"] = { 1, 594, 340 },
    ["Mordresh Fire Eye"] = { 1, 861, 467 },
    ["Glutton"] = { 1, 343, 668 },
    ["Amnennar the Coldbringer"] = { 1, 445, 605 },
  },
  ["Uldaman"] = {
    ["Revelosh"] = { 1, 534, 725 },
    ["The Lost Dwarves"] = { 1, 585, 920 },
    ["Ironaya"] = { 1, 373, 740 },
    ["Obsidian Sentinel"] = { 1, 289, 597 },
    ["Ancient Stone Keeper"] = { 1, 475, 441 },
    ["Galgann Firehammer"] = { 1, 268, 328 },
    ["Grimlok"] = { 1, 220, 256 },
    ["Archaedas"] = { 2, 553, 504 },
  },
  ["Zul'Farrak"] = {
    ["Hydromancer Velratha"] = { 1, 336, 448 },
    ["Gahz'rilla"] = { 1, 281, 383 },
    ["Antu'sul"] = { 1, 646, 277 },
    ["Theka the Martyr"] = { 1, 531, 262 },
    ["Witch Doctor Zum'rah"] = { 1, 443, 176 },
    ["Chief Ukorz Sandscalp"] = { 1, 422, 330 },
  },
  ["Maraudon"] = {
    ["Noxxion"] = { 1, 362, 98 },
    ["Razorlash"] = { 1, 167, 344 },
    ["Tinkerer Gizlock"] = { 1, 510, 531 },
    ["Lord Vyletongue"] = { 1, 378, 705 },
    ["Celebras the Cursed"] = { 2, 246, 143 },
    ["Landslide"] = { 2, 408, 488 },
    ["Rotgrip"] = { 2, 414, 818 },
    ["Princess Theradras"] = { 2, 258, 789 },
  },
  ["Sunken Temple"] = {
    ["Avatar of Hakkar"] = { 1, 243, 459 },
    ["Jammal'an the Prophet"] = { 1, 761, 459 },
    ["Shade of Eranikus"] = { 1, 671, 877 },
  },
  ["Blackrock Depths"] = {
    ["High Interrogator Gerstahn"] = { 1, 474, 922 },
    ["Lord Roccor"] = { 1, 556, 670 },
    ["Houndmaster Grebmar"] = { 1, 535, 573 },
    ["Ring of Law"] = { 1, 498, 646 },
    ["Pyromancer Loregrain"] = { 2, 549, 949 },
    ["Lord Incendius"] = { 1, 564, 311 },
    ["Warder Stilgiss"] = { 2, 602, 660 },
    ["Fineous Darkvire"] = { 1, 635, 211 },
    ["Bael'Gar"] = { 1, 251, 535 },
    ["General Angerforge"] = { 2, 363, 824 },
    ["Golem Lord Argelmach"] = { 2, 365, 652 },
    ["Hurley Blackbreath"] = { 2, 506, 705 },
    ["Phalanx"] = { 2, 458, 565 },
    ["Ribbly Screwspigot"] = { 2, 525, 625 },
    ["Plugger Spazzring"] = { 2, 477, 657 },
    ["Ambassador Flamelash"] = { 2, 538, 486 },
    ["The Seven"] = { 2, 538, 248 },
    ["Magmus"] = { 2, 796, 119 },
    ["Emperor Dagran Thaurissan"] = { 2, 910, 119 },
  },
  ["Dire Maul"] = {
    ["Zevrim Thornhoof"] = { 6, 575, 744 },
    ["Hydrospawn"] = { 6, 537, 715 },
    ["Lethtendris"] = { 5, 439, 482 },
    ["Alzzin the Wildshaper"] = { 6, 567, 289 },
    ["Tendris Warpwood"] = { 2, 336, 537 },
    ["Illyanna Ravenoak"] = { 2, 204, 777 },
    ["Magister Kalendris"] = { 3, 339, 451 },
    ["Immol'thar"] = { 4, 350, 576 },
    ["Prince Tortheldrin"] = { 4, 623, 232 },
    ["Guard Mol'dar"] = { 1, 695, 760 },
    ["Stomper Kreeg"] = { 1, 612, 693 },
    ["Guard Fengus"] = { 1, 495, 781 },
    ["Guard Slip'kik"] = { 1, 266, 572 },
    ["Captain Kromcrush"] = { 1, 318, 506 },
    ["Cho'Rush the Observer"] = { 1, 320, 304 },
    ["King Gordok"] = { 1, 320, 229 },
  },
  ["Stratholme"] = {
    ["Hearthsinger Forresten"] = { 1, 605, 314 },
    ["Timmy the Cruel"] = { 1, 500, 178 },
    ["Balnazzar"] = { 1, 205, 822 },
    ["The Unforgiven"] = { 1, 735, 205 },
    ["Baroness Anastari"] = { 2, 746, 469 },
    ["Nerub'enkan"] = { 2, 572, 461 },
    ["Maleki the Pallid"] = { 2, 675, 227 },
    ["Magistrate Barthilas"] = { 2, 567, 162 },
    ["Ramstein the Gorger"] = { 2, 456, 199 },
  },
}
local SEEDS -- by ns.Slug(dungeon), built on first use
local function seeds()
  if not SEEDS then
    SEEDS = {}
    for name, list in pairs(SEEDS_BY_NAME) do SEEDS[ns.Slug(name)] = list end
  end
  return SEEDS
end

local function store()
  ns.db.bossPins = ns.db.bossPins or {}
  return ns.db.bossPins
end

-- floor id (or "#n", floor number n), x, y of a boss's pin, or nil
-- Is a pin's floor this floor (the n-th in the dungeon's floor list)?
function ns.PinOnFloor(f, floor, n)
  return f ~= nil and floor ~= nil and (f == floor.fid or f == "#" .. tostring(n))
end

function ns.BossPin(dungeon, boss)
  local slug = ns.Slug(dungeon)
  local mine = ns.db and ns.db.bossPins and ns.db.bossPins[slug] and ns.db.bossPins[slug][boss]
  if mine then
    if (mine.x or -1) < 0 then return nil end
    return mine.f, mine.x, mine.y
  end
  local s = seeds()[slug] and seeds()[slug][boss]
  if s then return "#" .. s[1], s[2], s[3] end
  if ns.SeedBossPin then return ns.SeedBossPin(dungeon, boss) end
end

local function save(slug, boss, f, x, y, by)
  local d = store()
  d[slug] = d[slug] or {}
  d[slug][boss] = { f = f or "", x = x, y = y, by = by, at = time() }
end

local function canSend() return ns.settings.welcomed and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage end

-- x = nil removes the pin
function ns.SetBossPin(dungeon, boss, f, x, y)
  local slug = ns.Slug(dungeon)
  save(slug, boss, f, x or -1, y or -1, UnitName("player"))
  if canSend() then ns.Send(table.concat({ "BP", slug, boss, f or "", x or -1, y or -1 }, "\t"), "GUILD") end
end

local function onMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not ns.settings.welcomed then return end
  if ns.IsSecret and (ns.IsSecret(text) or ns.IsSecret(sender)) then return end
  local kind, slug, boss, f, x, y = strsplit("\t", text)
  if kind ~= "BP" or not (slug and boss and f) then return end
  local short = Ambiguate and Ambiguate(sender or "", "short") or sender
  if short == UnitName("player") then return end
  x, y = tonumber(x), tonumber(y)
  if not (x and y) or x > 1000 or y > 1000 then return end
  save(slug, boss, f, x, y, short)
  if ns.RefreshUI then ns.RefreshUI() end
end

ns.RegisterModule({
  name = "BossPins",
  events = {
    CHAT_MSG_ADDON = function(_, _, prefix, text, channel, sender) onMessage(prefix, text, channel, sender) end,
  },
})
