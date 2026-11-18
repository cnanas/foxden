-- Foxden: trash drops. Which items a dungeon's trash mobs drop, worked out from the QuestieDB
-- addon's data in game: the NPCs that live in each dungeon, then the items dropped only by
-- NPCs of that one dungeon (so world drops that drop anywhere are left out) and not by its
-- bosses (that's boss loot). Quest items are left out too.
-- Built once per session, in small batches the first time it's asked for (about two seconds).
--   ns.Trash.For(dungeonName) -> { { id, mobs = { name, ... } }, ... } or nil while building
--   ns.Trash.State() -> "ready" | "building" | "missing" (no QuestieDB)

local _, ns = ...
local T = {}
ns.Trash = T
local BATCH = 400
local state, bySlug, listeners = nil, nil, {}

function T.State()
  if state then return state end
  return _G.LibQuestieDB and "idle" or "missing"
end
function T.OnReady(fn) listeners[#listeners + 1] = fn end

local function build()
  local L = _G.LibQuestieDB
  if not (L and L.Npc and L.Npc.GetAllIds and L.Item and L.Item.GetAllIds and L.Support) then state = "missing"; return end
  local ok, zdb = pcall(L.Support.Get, "ZoneDB")
  local dungeons = ok and type(zdb) == "table" and type(zdb.private) == "table" and zdb.private.dungeons
  if type(dungeons) ~= "table" then state = "missing"; return end
  state = "building"
  -- area ID -> dungeon slug (each dungeon's main area and its alternatives)
  local areaSlug = {}
  for area, d in pairs(dungeons) do
    if type(d) == "table" and type(d[1]) == "string" then
      local slug = ns.Slug(d[1])
      areaSlug[area] = slug
      for _, alt in ipairs(type(d[2]) == "table" and d[2] or {}) do areaSlug[alt] = slug end
    end
  end
  -- boss names per dungeon (Data/Dungeons.lua), to leave boss loot out
  local bossNames = {}
  for _, d in pairs(ns.Dungeons or {}) do
    local set = {}
    for _, b in ipairs(d.bosses or {}) do set[b.name] = true end
    bossNames[ns.Slug(d.name)] = set
  end
  local npcSlug, npcName = {}, {}
  local npcs, items = L.Npc.GetAllIds(), L.Item.GetAllIds()
  local out = {}
  local i, phase = 1, 1
  local step
  local function work()
    if phase == 1 then
      for k = i, math.min(#npcs, i + BATCH - 1) do
        local id = npcs[k]
        local okZ, z = pcall(L.Npc.Get, id, 9)
        local slug = okZ and areaSlug[z]
        if slug then npcSlug[id] = slug; npcName[id] = L.Npc.Get(id, 1) end
      end
      i = i + BATCH
      if i > #npcs then phase, i = 2, 1 end
    else
      for k = i, math.min(#items, i + BATCH - 1) do
        local id = items[k]
        local okD, drops = pcall(L.Item.Get, id, 2)
        if okD and type(drops) == "table" and #drops > 0 then
          local slug, only = nil, true
          for _, npc in ipairs(drops) do
            local s = npcSlug[npc]
            if not s or (slug and s ~= slug) then only = false; break end
            slug = s
          end
          if only and slug and L.Item.Get(id, 12) ~= 12 then -- 12: quest items
            local bosses, mobs, seen, boss = bossNames[slug] or {}, {}, {}, false
            for _, npc in ipairs(drops) do
              local n = npcName[npc]
              if n and bosses[n] then boss = true end
              if n and not seen[n] then seen[n] = true; mobs[#mobs + 1] = n end
            end
            if not boss then
              out[slug] = out[slug] or {}
              out[slug][#out[slug] + 1] = { id = id, mobs = mobs }
            end
          end
        end
      end
      i = i + BATCH
      if i > #items then
        bySlug, state = out, "ready"
        for _, fn in ipairs(listeners) do pcall(fn) end
        return true
      end
    end
  end
  step = function()
    local ok, finished = pcall(work)
    if not ok then
      state = "missing"
      if ns.Quests then ns.Quests.Try("trash drops", error, finished) end
      return
    end
    if not finished then C_Timer.After(0, step) end
  end
  step()
end

function T.For(name)
  if state == "ready" then return bySlug[ns.Slug(name)] or {} end
  if not state then
    local ok = pcall(build)
    if not ok then state = "missing" end
  end
  return nil
end
