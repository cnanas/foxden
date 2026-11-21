-- Module: Journal. Reads the game's own Encounter Journal (dungeons, bosses,
-- abilities, loot, map floors and boss pins) and saves it, so the Journal page
-- and the website can show every dungeon, even ones nobody has run yet.
--
-- Forever's journal may not include everything (abilities and loot in
-- particular); every call is protected and `/fox journaltest` reports what this
-- client actually has.
--
-- FoxdenDB.journal = {
--   build, scannedAt, stats = { dungeons, bosses, sections, loot, pins },
--   dungeons = { { id, name, desc, map, floors = { { map, name } },
--     bosses = { { id, encounterID, name, desc, loot = { itemID, ... }, pins = { { m, x, y } },
--       sections = { { t = title, d = description, depth, flags = "tank,healer,..." } } } } } },
-- }

local _, ns = ...
local MAX_SECTIONS, MAX_TEXT = 60, 700
local FLAG = { [0] = "tank", [1] = "damage", [2] = "healer", [3] = "heroic", [4] = "deadly", [5] = "important",
  [6] = "interruptible", [7] = "magic", [8] = "curse", [9] = "poison", [10] = "disease", [11] = "enrage", [12] = "mythic" }

local scanning = false

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function clip(s) return type(s) == "string" and s:sub(1, MAX_TEXT) or nil end

-- One ability section, whichever form this client has.
local function sectionInfo(id)
  if C_EncounterJournal and C_EncounterJournal.GetSectionInfo then
    local ok, info = pcall(C_EncounterJournal.GetSectionInfo, id)
    if ok and type(info) == "table" then return info.title, info.description, info.firstChildSectionID, info.siblingSectionID end
  end
  local ok, title, desc, _, _, _, sibling, child = call(EJ_GetSectionInfo, id)
  if ok then return title, desc, child, sibling end
end

local function sectionFlags(id)
  if not (C_EncounterJournal and C_EncounterJournal.GetSectionIconFlags) then return nil end
  local ok, flags = pcall(C_EncounterJournal.GetSectionIconFlags, id)
  if not ok or type(flags) ~= "table" then return nil end
  local names = {}
  for _, f in ipairs(flags) do if FLAG[f] then names[#names + 1] = FLAG[f] end end
  return #names > 0 and table.concat(names, ",") or nil
end

-- Depth-first walk of a boss's ability tree.
local function sections(rootID)
  local out = {}
  local function walk(id, depth)
    while id and id > 0 and #out < MAX_SECTIONS do
      local title, desc, child, sibling = sectionInfo(id)
      if not title then return end
      out[#out + 1] = { t = title, d = clip(desc), depth = depth, flags = sectionFlags(id) }
      if child and child > 0 then walk(child, depth + 1) end
      id = sibling
    end
  end
  if rootID and rootID > 0 then walk(rootID, 0) end
  return out
end

local function loot(journalEncounterID)
  local items = {}
  if not call(EJ_SelectEncounter, journalEncounterID) then return items end
  local ok, n = call(EJ_GetNumLoot)
  for i = 1, (ok and tonumber(n) or 0) do
    local id
    if C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
      local okL, info = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
      if okL and type(info) == "table" then id = info.itemID end
    end
    if not id then
      local okL, first = call(EJ_GetLootInfoByIndex, i)
      if okL and type(first) == "number" then id = first elseif okL and type(first) == "table" then id = first.itemID end
    end
    if id then items[#items + 1] = id end
  end
  return items
end

local function floors(uiMapID)
  if not uiMapID or uiMapID == 0 then return {} end
  local list = {}
  local okG, group = call(C_Map and C_Map.GetMapGroupID, uiMapID)
  if okG and group then
    local okM, members = call(C_Map.GetMapGroupMembersInfo, group)
    if okM and type(members) == "table" then
      table.sort(members, function(a, b) return (a.relativeHeightIndex or 0) < (b.relativeHeightIndex or 0) end)
      for _, m in ipairs(members) do list[#list + 1] = { map = m.mapID, name = m.name } end
    end
  end
  if #list == 0 then
    local okI, info = call(C_Map and C_Map.GetMapInfo, uiMapID)
    list[1] = { map = uiMapID, name = okI and info and info.name or nil }
  end
  return list
end

-- A dungeon's floors. Forever has no Encounter Journal, so this is how the Journal's Map tab
-- finds a dungeon's map before anyone has run it:
--   1. the game's map list, by name (one pass over the map IDs, the first time a map is asked for)
--   2. the classic dungeon map pictures that ship with the game client (Interface\WorldMap\<Folder>\<Folder><n>_1..12,
--      a 4 x 3 grid of 256px tiles), for when the map API has no art for the floor.
-- Each floor: { key, map = uiMapID or nil, name, tiles = path prefix or nil }.

-- Game client folder names, floor counts and (where they are fixed) floor names. Keys are ns.Slug(name).
local CLIENT_MAPS = {
  ["ragefire-chasm"] = { "Ragefire", 1 },
  ["wailing-caverns"] = { "WailingCaverns", 1 },
  ["deadmines"] = { "TheDeadmines", 2, { "The Deadmines", "Ironclad Cove" } },
  ["shadowfang-keep"] = { "ShadowfangKeep", 7 },
  ["blackfathom-deeps"] = { "BlackFathomDeeps", 3 },
  ["stormwind-stockade"] = { "TheStockade", 1 },
  ["stockade"] = { "TheStockade", 1 },
  ["gnomeregan"] = { "Gnomeregan", 4 },
  ["razorfen-kraul"] = { "RazorfenKraul", 1 },
  ["scarlet-monastery"] = { "ScarletMonastery", 4, { "Graveyard", "Library", "Armory", "Cathedral" } },
  ["razorfen-downs"] = { "RazorfenDowns", 1 },
  ["uldaman"] = { "Uldaman", 2 },
  ["zul-farrak"] = { "ZulFarrak", 1 },
  ["maraudon"] = { "Maraudon", 2 },
  ["sunken-temple"] = { "TheTempleOfAtalHakkar", 1 },
  ["temple-of-atal-hakkar"] = { "TheTempleOfAtalHakkar", 1 },
  ["blackrock-depths"] = { "BlackrockDepths", 2, { "Detention Block", "Shadowforge City" } },
  ["blackrock-spire"] = { "BlackrockSpire", 7 },
  ["dire-maul"] = { "DireMaul", 6, { "Gordok Commons", "Capital Gardens", "Court of the Highborne", "Prison of Immol'thar", "Warpwood Quarter", "Shrine of Eldretharr" } },
  ["scholomance"] = { { "ScholomanceOLD", "Scholomance" }, 4 },
  ["stratholme"] = { "Stratholme", 2 },
  ["molten-core"] = { "MoltenCore", 1 },
  ["onyxia-s-lair"] = { "OnyxiasLair", 1 },
  ["blackwing-lair"] = { "BlackwingLair", 4 },
  ["zul-gurub"] = { "ZulGurub", 1 },
  ["ruins-of-ahn-qiraj"] = { "RuinsofAhnQiraj", 1 },
  ["ahn-qiraj-temple"] = { "AhnQiraj", 3 },
  ["naxxramas"] = { "Naxxramas", 6 },
}
-- names the game's map list may use instead of ours
local ALIASES = {
  ["deadmines"] = { "the-deadmines" }, ["stormwind-stockade"] = { "the-stockade", "stockade" },
  ["sunken-temple"] = { "temple-of-atal-hakkar" }, ["ahn-qiraj-temple"] = { "ahn-qiraj", "temple-of-ahn-qiraj" },
}

-- Does a texture file exist? SetTexture says so on current clients (older ones return nothing: assume yes).
local probe
local function fileExists(path)
  if not CreateFrame then return true end
  probe = probe or CreateFrame("Frame"):CreateTexture()
  local ok, r = pcall(probe.SetTexture, probe, path)
  if not ok then return false end
  return r ~= false
end
ns.TextureExists = fileExists

local byName, floorCache = nil, {}
local function hasArt(map)
  if not (C_Map and C_Map.GetMapArtLayerTextures) then return false end
  local ok, t = call(C_Map.GetMapArtLayerTextures, map, 1)
  return ok and type(t) == "table" and #t > 0
end
ns.MapHasArt = hasArt

local function scanMaps()
  byName = {}
  if not (C_Map and C_Map.GetMapInfo) then return end
  for id = 1, 5000 do
    local ok, info = call(C_Map.GetMapInfo, id)
    -- anything below a continent (3 zone, 4 dungeon, 5 micro, 6 orphan)
    if ok and info and info.name and (info.mapType or 4) >= 3 then
      local k = ns.Slug(info.name)
      byName[k] = byName[k] or {}
      table.insert(byName[k], { id = id, type = info.mapType })
    end
  end
end

-- The game's maps with this name, dungeon types first.
local function mapIDs(key)
  if not byName then scanMaps() end
  local out = {}
  local keys = { key }
  for _, a in ipairs(ALIASES[key] or {}) do keys[#keys + 1] = a end
  for _, k in ipairs(keys) do
    for _, m in ipairs(byName[k] or {}) do if m.type == 4 or m.type == 5 then out[#out + 1] = m.id end end
  end
  for _, k in ipairs(keys) do
    for _, m in ipairs(byName[k] or {}) do if m.type ~= 4 and m.type ~= 5 then out[#out + 1] = m.id end end
  end
  return out
end

local function clientFloors(key)
  local c = CLIENT_MAPS[key]
  if not c then return {} end
  local folders = type(c[1]) == "table" and c[1] or { c[1] }
  for _, folder in ipairs(folders) do
    local list = {}
    for n = 1, c[2] do
      local prefix = "Interface\\WorldMap\\" .. folder .. "\\" .. folder .. n .. "_"
      if fileExists(prefix .. "1") then
        list[#list + 1] = { key = prefix, fid = folder .. n, tiles = prefix, name = c[3] and c[3][n] or (c[2] > 1 and ("Level " .. n) or nil), n = n }
      end
    end
    if #list > 0 then return list end
  end
  return {}
end

function ns.DungeonFloors(name)
  if not name then return {} end
  local key = ns.Slug(name)
  if floorCache[key] then return floorCache[key] end
  -- 1. the game's map list: the first set of floors that all have art
  local fromApi, firstFound = nil, nil
  for _, id in ipairs(mapIDs(key)) do
    local list = floors(id)
    firstFound = firstFound or list
    local ok = #list > 0
    for _, f in ipairs(list) do if not hasArt(f.map) then ok = false end end
    if ok then fromApi = list; break end
  end
  local best
  if fromApi then
    best = fromApi
    for _, f in ipairs(best) do f.key = f.map end
  else
    -- 2. the client's map pictures; keep the game's map IDs (for boss pins) when the floors line up
    best = clientFloors(key)
    local ids = firstFound or {}
    for i, f in ipairs(best) do
      local api = #ids == #best and ids[i] or (#ids >= f.n and ids[f.n]) or nil
      if api then f.map = api.map; if not (CLIENT_MAPS[key][3]) and api.name and #best > 1 then f.name = api.name end end
    end
    if #best == 0 and firstFound then best = firstFound; for _, f in ipairs(best) do f.key = f.map end end
  end
  for _, f in ipairs(best) do f.fid = f.fid or (f.map and ("m" .. f.map)) end
  floorCache[key] = best
  return best
end

-- /fox maptest (in the Journal's Map tab): what Foxden can find for a dungeon.
function ns.DungeonMapReport(name)
  local key = ns.Slug(name or "")
  local say = function(t) ns.say(t, true) end
  say("Map lookup for " .. tostring(name) .. ":")
  local ids = mapIDs(key)
  local bits = {}
  for _, id in ipairs(ids) do
    local ok, info = call(C_Map.GetMapInfo, id)
    bits[#bits + 1] = id .. " (type " .. tostring(ok and info and info.mapType) .. ", art " .. (hasArt(id) and "yes" or "no") .. ")"
  end
  say("  Game maps with that name: " .. (#bits > 0 and table.concat(bits, ", ") or "none"))
  local cf = clientFloors(key)
  say("  Client map pictures: " .. (CLIENT_MAPS[key] and (#cf .. " of " .. CLIENT_MAPS[key][2] .. " found") or "none known for this dungeon"))
  floorCache[key] = nil
  local fl = ns.DungeonFloors(name)
  say("  Floors shown: " .. #fl)
end

-- Where the game puts each boss on a floor: { [encounterID] = { m, x, y } } (x, y 0..1000).
function ns.EncounterPins(floorList)
  local out = {}
  if not (C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap) then return out end
  for _, f in ipairs(floorList or {}) do
    local ok, list = call(C_EncounterJournal.GetEncountersOnMap, f.map)
    for _, e in ipairs(ok and type(list) == "table" and list or {}) do
      if e.encounterID and type(e.mapX) == "number" and type(e.mapY) == "number" and not out[e.encounterID] then
        out[e.encounterID] = { m = f.map, x = math.floor(e.mapX * 1000 + 0.5), y = math.floor(e.mapY * 1000 + 0.5) }
      end
    end
  end
  return out
end

local function pinsOn(floorList)
  local byEncounter = {}
  for _, f in ipairs(floorList) do
    local ok, encounters = call(C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap, f.map)
    if ok and type(encounters) == "table" then
      for _, e in ipairs(encounters) do
        if e.encounterID and type(e.mapX) == "number" then
          byEncounter[e.encounterID] = byEncounter[e.encounterID] or {}
          table.insert(byEncounter[e.encounterID], { m = f.map, x = math.floor(e.mapX * 1000 + 0.5), y = math.floor(e.mapY * 1000 + 0.5) })
        end
      end
    end
  end
  return byEncounter
end

-- The journal's data only loads with Blizzard's journal module, which the game loads
-- the first time you open the journal window. Load it ourselves before reading.
local function loadJournal()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
  if not loaded and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
  elseif not loaded and LoadAddOn then pcall(LoadAddOn, "Blizzard_EncounterJournal") end
end

-- Every dungeon (not raid) in every tier, as { id, tier } pairs.
local function listDungeons()
  loadJournal()
  local list, seen = {}, {}
  local okT, tiers = call(EJ_GetNumTiers)
  tiers = okT and tonumber(tiers) or 1
  local okC, original = call(EJ_GetCurrentTier)
  for tier = 1, math.max(1, tiers) do
    call(EJ_SelectTier, tier)
    local okN, n = call(EJ_GetNumInstances, false)
    n = okN and tonumber(n) or nil
    for i = 1, n or 200 do
      local ok, id, name = call(EJ_GetInstanceByIndex, i, false)
      if not ok or not id then break end
      if not seen[id] then seen[id] = true; list[#list + 1] = { id = id, name = name, tier = tier } end
    end
  end
  if okC and tonumber(original) then call(EJ_SelectTier, tonumber(original)) end
  return list
end

local function scanDungeon(entry)
  call(EJ_SelectTier, entry.tier)
  call(EJ_SelectInstance, entry.id)
  local ok, name, desc, _, _, _, _, areaMap = call(EJ_GetInstanceInfo, entry.id)
  if not ok then ok, name, desc, _, _, _, _, areaMap = call(EJ_GetInstanceInfo) end
  local d = { id = entry.id, name = (ok and name) or entry.name, desc = clip(ok and desc), map = areaMap, bosses = {} }
  d.floors = floors(areaMap)
  local pins = pinsOn(d.floors)
  for i = 1, 40 do
    local okE, bName, bDesc, journalID, rootSection, _, _, dungeonEncounterID = call(EJ_GetEncounterInfoByIndex, i, entry.id)
    if not okE or not bName then okE, bName, bDesc, journalID, rootSection, _, _, dungeonEncounterID = call(EJ_GetEncounterInfoByIndex, i) end
    if not okE or not bName or not journalID then break end
    d.bosses[#d.bosses + 1] = {
      id = journalID, encounterID = dungeonEncounterID, name = bName, desc = clip(bDesc),
      sections = sections(rootSection), loot = loot(journalID), pins = pins[journalID] or {},
    }
  end
  return d
end

-- Scan one dungeon per tick so the game doesn't stall.
function ns.ScanJournal(onDone)
  if scanning then return end
  loadJournal()
  if not (EJ_GetInstanceByIndex and EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then
    ns.say("This client has no Encounter Journal for addons to read.", true)
    return
  end
  scanning = true
  local list, i = listDungeons(), 0
  local result = { build = select(2, GetBuildInfo()), scannedAt = GetServerTime(), dungeons = {} }
  local function tick()
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then
      C_Timer.After(2, tick) -- don't change what Blizzard's own journal window is showing
      return
    end
    i = i + 1
    local entry = list[i]
    if entry then
      local ok, d = pcall(scanDungeon, entry)
      if ok and d and #d.bosses > 0 then result.dungeons[#result.dungeons + 1] = d end
      C_Timer.After(0.05, tick)
      return
    end
    local s = { dungeons = #result.dungeons, bosses = 0, sections = 0, loot = 0, pins = 0 }
    for _, d in ipairs(result.dungeons) do
      for _, b in ipairs(d.bosses) do
        s.bosses, s.sections, s.loot, s.pins = s.bosses + 1, s.sections + #b.sections, s.loot + #b.loot, s.pins + #b.pins
      end
    end
    result.stats = s
    if ns.db then ns.db.journal = result end
    scanning = false
    ns.Changed()
    if onDone then onDone(result) end
  end
  C_Timer.After(0.05, tick)
end

local function report(j)
  local s = j and j.stats
  if not s then ns.say("No journal scan yet.", true); return end
  ns.say(string.format("Journal: %d dungeons, %d bosses.", s.dungeons, s.bosses), true)
  ns.say("  Abilities: " .. (s.sections > 0 and ("YES, " .. s.sections .. " entries") or "none in this client's journal"), true)
  ns.say("  Loot tables: " .. (s.loot > 0 and ("YES, " .. s.loot .. " items") or "none in this client's journal"), true)
  ns.say("  Boss map pins: " .. (s.pins > 0 and ("YES, " .. s.pins) or "none"), true)
  if s.dungeons == 0 then ns.say("This game client has no journal data for addons; Foxden uses its own dungeon list and your guild's runs instead.", true)
  else ns.say("Open /fox and pick Journal. It goes to the website when you log out.", true) end
end

-- What the game's journal answers, step by step (for /fox journaltest).
local function diagnose()
  loadJournal()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
  local okT, tiers = call(EJ_GetNumTiers)
  local okC, cur = call(EJ_GetCurrentTier)
  ns.say(string.format("  Journal module loaded: %s. Tiers: %s, current %s.", tostring(loaded), tostring(okT and tiers), tostring(okC and cur)), true)
  for tier = 1, math.min(3, tonumber(okT and tiers) or 1) do
    call(EJ_SelectTier, tier)
    local okN, n = call(EJ_GetNumInstances, false)
    local okR, nr = call(EJ_GetNumInstances, true)
    local names = {}
    for i = 1, 4 do
      local ok, id, name = call(EJ_GetInstanceByIndex, i, false)
      if ok and id then names[#names + 1] = tostring(name) .. "#" .. tostring(id) end
    end
    ns.say(string.format("  Tier %d: %s dungeons, %s raids. First: %s", tier, tostring(okN and n), tostring(okR and nr), #names > 0 and table.concat(names, ", ") or "none"), true)
  end
  local okM, map = call(C_Map.GetBestMapForUnit, "player")
  local okJ, here = call(EJ_GetInstanceForMap, okM and map or 0)
  ns.say(string.format("  This map %s is journal instance %s.", tostring(okM and map), tostring(okJ and here)), true)
  if okJ and tonumber(here) and here > 0 then
    call(EJ_SelectInstance, here)
    local ok, bname = call(EJ_GetEncounterInfoByIndex, 1, here)
    ns.say("  Its first boss: " .. tostring(ok and bname), true)
  end
end

function ns.JournalTest()
  ns.say("Reading the game's Encounter Journal…", true)
  pcall(diagnose)
  ns.ScanJournal(report)
end

ns.RegisterModule({
  name = "Journal",
  events = {
    PLAYER_LOGIN = function()
      -- re-scan after a patch, or once a week
      C_Timer.After(25, function()
        local j = ns.db and ns.db.journal
        local build = select(2, GetBuildInfo())
        if not j or j.build ~= build or #(j.dungeons or {}) == 0 or GetServerTime() - (j.scannedAt or 0) > 7 * 86400 then ns.ScanJournal() end
      end)
    end,
  },
})
