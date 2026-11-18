-- Foxden: where the quest helper's quest data comes from.
--   With the QuestieDB addon installed (it comes with Questie), Foxden reads its database in
--   game: the full, current WoW Forever data, Forever's own zones and quests included (the
--   copy on GitHub that Data/Quests.lua is made from has only the older part of it).
--   Without it, Data/Quests.lua (shipped with Foxden) is used.
-- The rows built here have exactly the Data/Quests.lua layout, so nothing else needs to know.
-- Built in small batches after you log in, so the game doesn't stall.

local _, ns = ...
local BATCH = 200
local ALLY, HORDE = 1 + 4 + 8 + 64 + 1024, 2 + 16 + 32 + 128 + 256 + 512
local HOLIDAY = { [-22] = true, [-284] = true, [-364] = true, [-366] = true, [-369] = true, [-370] = true, [-374] = true,
  [-375] = true, [-376] = true, [-1001] = true, [-1002] = true, [-1003] = true, [-1005] = true, [-41] = true }

ns.QuestSource = { name = "Foxden's own quest data", count = 0, building = false }

local function band(a, b)
  if bit and bit.band then return bit.band(a, b) end
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

local function countOf(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

-- QuestieDB's area ID -> the game's map ID (its own table, plus its overrides).
local function zoneMaps(L)
  local out = {}
  local ok, zdb = pcall(L.Support.Get, "ZoneDB")
  local p = ok and type(zdb) == "table" and zdb.private
  if type(p) ~= "table" then return out end
  for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
    local src = p[key]
    local t = src
    if type(src) == "string" and loadstring then
      local fn = loadstring(src)
      local okT, res = pcall(fn or function() end)
      t = okT and res or nil
    end
    if type(t) == "table" then for area, map in pairs(t) do out[area] = map end end
  end
  return out
end

local function numbers(v)
  local out = {}
  if type(v) ~= "table" then return nil end
  for _, x in ipairs(v) do
    if type(x) == "number" then out[#out + 1] = x
    elseif type(x) == "table" then for _, y in ipairs(x) do if type(y) == "number" then out[#out + 1] = y end end end
  end
  return #out > 0 and out or nil
end

local function build(L, done)
  local Quest, Npc, Object = L.Quest, L.Npc, L.Object
  local maps = zoneMaps(L)
  local function spot(name, spawns)
    if type(spawns) ~= "table" then return nil end
    for zone, coords in pairs(spawns) do
      local map = maps[zone]
      local c = type(coords) == "table" and coords[1]
      if map and map > 0 and type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 and c[2] >= 0 then
        return name or "", map, math.floor(c[1] * 100 + 0.5) / 100, math.floor(c[2] * 100 + 0.5) / 100
      end
    end
  end
  -- startedBy / finishedBy: { {npcs}, {objects}, {items} }
  local function where(v)
    if type(v) ~= "table" then return nil end
    for _, id in ipairs(type(v[1]) == "table" and v[1] or {}) do
      local n, m, x, y = spot(Npc.Get(id, 1), Npc.Get(id, 7))
      if n then return n, m, x, y end
    end
    if Object then
      for _, id in ipairs(type(v[2]) == "table" and v[2] or {}) do
        local n, m, x, y = spot(Object.Get(id, 1), Object.Get(id, 4))
        if n then return n, m, x, y end
      end
    end
  end
  local function row(id)
    local name = Quest.Get(id, 1)
    if type(name) ~= "string" then return nil end
    local gN, gM, gX, gY = where(Quest.Get(id, 2))
    local eN, eM, eX, eY = where(Quest.Get(id, 3))
    local mask = tonumber(Quest.Get(id, 6)) or 0
    local low, hi = mask % 4294967296, math.floor(mask / 4294967296)
    local a = band(low, ALLY) ~= 0 or hi % 2 == 1
    local h = band(low, HORDE) ~= 0 or math.floor(hi / 2) % 2 == 1
    local special = tonumber(Quest.Get(id, 24)) or 0
    local skill, ranks = Quest.Get(id, 18), Quest.Get(id, 35)
    local hidden = band(special, 2) ~= 0 or HOLIDAY[tonumber(Quest.Get(id, 17)) or 0] == true
      or (tonumber(Quest.Get(id, 30)) or 0) > 0
      or (tonumber(Quest.Get(id, 31)) or 0) > 0 or (type(ranks) == "table" and next(ranks) ~= nil)
    local obj = Quest.Get(id, 8)
    obj = type(obj) == "table" and type(obj[1]) == "string" and obj[1]:sub(1, 300) or ""
    return { name, tonumber(Quest.Get(id, 4)) or 0, tonumber(Quest.Get(id, 5)) or 0, (a == h) and "B" or a and "A" or "H",
      band(low, ALLY + HORDE), tonumber(Quest.Get(id, 7)) or 0,
      numbers(Quest.Get(id, 12)), numbers(Quest.Get(id, 13)), numbers(Quest.Get(id, 16)),
      tonumber(Quest.Get(id, 22)) or 0, tonumber(Quest.Get(id, 25)) or 0, tonumber(Quest.Get(id, 32)) or 0,
      band(special, 1) ~= 0, hidden,
      gN or "", gM or 0, gX or 0, gY or 0, eN or "", eM or 0, eX or 0, eY or 0, obj,
      type(Quest.Get(id, 26)) == "table" and Quest.Get(id, 26) or nil, -- 24: reputation { {factionID, value}, ... }
      type(skill) == "table" and skill[1] and skill or nil } -- 25: profession needed { skillLineID, level }
  end

  local ids = Quest.GetAllIds()
  if type(ids) ~= "table" or #ids == 0 then return false end
  local out, i, failed = {}, 1, 0
  ns.QuestSource.building = true
  local function step()
    local stop = math.min(#ids, i + BATCH - 1)
    for k = i, stop do
      local ok, r = pcall(row, ids[k])
      if ok and r then out[ids[k]] = r
      elseif not ok then
        failed = failed + 1
        if failed == 1 and ns.Quests then ns.Quests.Try("QuestieDB quest " .. ids[k], error, r) end
      end
    end
    i = stop + 1
    if i <= #ids then C_Timer.After(0, step); return end
    ns.QuestSource.building = false
    if countOf(out) < 500 then return done(false) end -- something's off: keep Foxden's own data
    local ver = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("QuestieDB", "Version")
    ns.QuestDB = out
    ns.QuestSource.name = "QuestieDB" .. (ver and (" " .. ver) or "")
    ns.QuestSource.count = countOf(out)
    ns.QuestSource.failed = failed
    done(true)
  end
  step()
  return true
end

-- QuestieDB installed but switched off? (Questie can stay off; Foxden only needs QuestieDB.)
function ns.QuestieDBState()
  if _G.LibQuestieDB then return "on" end
  local info = C_AddOns and C_AddOns.GetAddOnInfo
  if not info then return "missing" end
  local ok, name = pcall(info, "QuestieDB")
  if not ok or not name then return "missing" end
  return "off"
end
function ns.EnableQuestieDB()
  if not (C_AddOns and C_AddOns.EnableAddOn) then return end
  pcall(C_AddOns.EnableAddOn, "QuestieDB", UnitName("player"))
  ReloadUI()
end

-- Dungeon entrances from QuestieDB's dungeon list: { { name, slug, map, x, y (0-100) }, ... },
-- one per entrance (a dungeon can have more than one). Built once QuestieDB has them.
-- QuestieDB names a few dungeons differently from Foxden's list.
local ENTRANCE_ALIAS = {
  ["stockade"] = "stormwind-stockade", ["stockades"] = "stormwind-stockade",
  ["temple-of-atalhakkar"] = "sunken-temple", ["sunken-temple-of-atalhakkar"] = "sunken-temple",
  ["lower-blackrock-spire"] = "blackrock-spire", ["upper-blackrock-spire"] = "blackrock-spire",
  ["dire-maul-east"] = "dire-maul", ["dire-maul-west"] = "dire-maul", ["dire-maul-north"] = "dire-maul",
}
local entrances
function ns.DungeonEntrances()
  if entrances then return entrances end
  local L = _G.LibQuestieDB
  if not (L and L.Support and L.Support.Get) then return {} end
  local ok, zdb = pcall(L.Support.Get, "ZoneDB")
  local list = ok and type(zdb) == "table" and type(zdb.private) == "table" and zdb.private.dungeons
  if type(list) ~= "table" then return {} end
  local maps, out = zoneMaps(L), {}
  for _, d in pairs(list) do
    if type(d) == "table" and type(d[1]) == "string" and type(d[4]) == "table" then
      local slug = ns.Slug(d[1])
      slug = ENTRANCE_ALIAS[slug] or slug
      for _, loc in ipairs(d[4]) do
        local map = type(loc) == "table" and maps[loc[1]]
        if map and map > 0 and type(loc[2]) == "number" and type(loc[3]) == "number" then
          out[#out + 1] = { name = d[1], slug = slug, map = map, x = loc[2], y = loc[3] }
        end
      end
    end
  end
  entrances = out -- the list is static once QuestieDB has it, so build it once
  return out
end

-- Where a dungeon's entrance is: map ID, x, y (0-100), or nil.
function ns.DungeonEntrance(name)
  local want = ns.Slug(name)
  for _, e in ipairs(ns.DungeonEntrances()) do
    if e.slug == want then return e.map, e.x, e.y end
  end
end

-- QuestieDB may still be getting ready right after login: try again a few times.
local tries = 0
local function start()
  if ns.QuestSource.building or ns.QuestSource.name:find("QuestieDB", 1, true) then return end
  tries = tries + 1
  ns.QuestSource.count = countOf(ns.QuestDB)
  local L = _G.LibQuestieDB
  local function again(why)
    ns.QuestSource.note = why
    if tries < 8 then C_Timer.After(3, start) end
  end
  if not L then
    if ns.QuestieDBState() == "off" then
      ns.QuestSource.note = "the QuestieDB addon is turned off: turn it on for Forever's new zones (Questie itself can stay off)"
      if tries == 1 and ns.say then
        C_Timer.After(4, function() ns.say("Quest marks for Forever's new zones need the QuestieDB addon, which is turned off. Turn it on in AddOns, or click \"Turn on QuestieDB\" on Foxden's Quests page. Questie itself can stay off.", true) end)
      end
      return
    end
    return again("the QuestieDB addon isn't installed (it comes with Questie)")
  end
  if not (L.Quest and L.Quest.GetAllIds and L.Quest.Get and L.Npc and L.Npc.Get and L.Support and L.Support.Get) then
    return again("QuestieDB is a version Foxden can't read")
  end
  if L.RequireContract then
    local ok, fine = pcall(L.RequireContract, 1)
    if not ok or fine == false then return again("QuestieDB is a version Foxden can't read") end
  end
  local ok, started = pcall(build, L, function(used)
    if used then
      ns.QuestSource.note = nil
      if ns.Quests then ns.Quests.Dirty(); ns.Quests.Changed() end
    else again("QuestieDB returned too few quests") end
  end)
  if not ok then
    ns.QuestSource.building = false
    if ns.Quests then ns.Quests.Try("QuestieDB", error, started) end
    again("reading QuestieDB failed: " .. tostring(started))
  elseif not started then
    again("QuestieDB had no quests yet")
  end
end

ns.RegisterModule({
  name = "QuestSource",
  events = { PLAYER_LOGIN = function() C_Timer.After(1, start) end },
})
