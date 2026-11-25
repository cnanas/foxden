-- Module: RecipeSources. Where recipes come from, for the leveling planner and recipe list.
--   * Notes how you learn each new recipe: at a trainer, by turning in a quest (which one), from
--     an NPC you were talking to, or by using a recipe item, with the place. Forever has recipes
--     that no trainer lists ("hidden until known"), and the game's data doesn't say where they
--     come from; once one guild member learns one, everyone's Foxden can say where.
--     The companion uploads these; the website shares them back (site.recipeSrc).
--   * ns.ItemSources(itemID): where to get a recipe item (plans, patterns, formulas), from the
--     QuestieDB addon: who sells it, what drops it, which quest gives it.
--
-- FoxdenDB.recipeSources = { [recipe name] = { how = "trainer"|"quest"|"npc"|"item"|"other",
--   quest = questID, npc = name, map = uiMapID, x, y (0-100), at = time } }

local _, ns = ...
local db
local trainerOpen, merchantOpen, lastQuest, lastItemUse

local function pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  return "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end
local LEARN = { pattern(_G.ERR_LEARN_RECIPE_S), pattern(_G.ERR_LEARN_SPELL_S) }

local function where()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not okM or not map then return nil end
  local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not okP or not pos then return map end
  local x, y = pos:GetXY()
  return map, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

-- only recipes (the website's list), not class spells
local recipeNames
local function isRecipe(name)
  if not recipeNames then
    local site = ns.Site and ns.Site()
    if not (site and site.costs) then return false end
    recipeNames = {}
    for _, c in ipairs(site.costs) do if c[3] then recipeNames[c[3]] = true end end
  end
  return recipeNames[name] == true
end

local function learned(name)
  if not db or not name or ns.IsSecret(name) or not isRecipe(name) then return end
  local now = GetTime()
  local e = { at = GetServerTime() }
  local npc = UnitExists("npc") and UnitName("npc") or nil
  if trainerOpen then e.how, e.npc = "trainer", npc
  elseif lastQuest and now - lastQuest.t < 6 then e.how, e.quest, e.npc = "quest", lastQuest.id, npc
  elseif npc and not merchantOpen then e.how, e.npc = "npc", npc
  elseif lastItemUse and now - lastItemUse < 6 then e.how = "item"
  else e.how = "other" end
  e.map, e.x, e.y = where()
  db.recipeSources = db.recipeSources or {}
  -- a trainer is the least interesting answer: keep a better one learned elsewhere
  local old = db.recipeSources[name]
  if old and old.how ~= "trainer" and e.how == "trainer" then return end
  db.recipeSources[name] = e
end

-- ---- recipe items: where to get them (QuestieDB) ------------------------------------------

local function zoneName(L, spawns)
  if type(spawns) ~= "table" then return nil end
  local ok, zdb = pcall(L.Support.Get, "ZoneDB")
  local p = ok and type(zdb) == "table" and zdb.private
  for area in pairs(spawns) do
    local map = p and type(p.areaIdToUiMapId) == "table" and p.areaIdToUiMapId[area]
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if info and info.name then return info.name end
  end
end

local function npcText(L, ids, max)
  local out = {}
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    local okN, n = pcall(L.Npc.Get, id, 1)
    if okN and type(n) == "string" then
      local okS, spawns = pcall(L.Npc.Get, id, 7)
      local z = okS and zoneName(L, spawns)
      out[#out + 1] = z and (n .. " (" .. z .. ")") or n
      if #out >= max then break end
    end
  end
  local more = type(ids) == "table" and #ids > #out and (" and " .. (#ids - #out) .. " more") or ""
  return #out > 0 and (table.concat(out, ", ") .. more) or nil
end

local itemCache = {}
-- { "Sold by ...", "Drops from ...", "Quest: ..." } or nil
function ns.ItemSources(itemID)
  if not itemID or itemID <= 0 then return nil end
  if itemCache[itemID] ~= nil then return itemCache[itemID] or nil end
  local L = _G.LibQuestieDB
  if not (L and L.Item and L.Item.Get and L.Npc and L.Npc.Get and L.Support) then return nil end
  local out = {}
  local function get(k) local ok, v = pcall(L.Item.Get, itemID, k); return ok and v or nil end
  local sold = npcText(L, get(14), 2)
  if sold then out[#out + 1] = "Sold by " .. sold end
  local drops = npcText(L, get(2), 3)
  if drops then out[#out + 1] = "Drops from " .. drops end
  local objs = get(3)
  if type(objs) == "table" and #objs > 0 and L.Object then
    local ok, n = pcall(L.Object.Get, objs[1], 1)
    if ok and type(n) == "string" then out[#out + 1] = "Found in " .. n end
  end
  local quests = get(6)
  if type(quests) == "table" and quests[1] then
    local ok, n = pcall(L.Quest.Get, quests[1], 1)
    if ok and type(n) == "string" then out[#out + 1] = "Quest reward: " .. n end
  end
  itemCache[itemID] = #out > 0 and out or false
  return #out > 0 and out or nil
end

-- How a recipe is learned, as one line for the planner, or nil when nothing is known.
-- src: this character's record, else the guild's (from the website).
function ns.RecipeSource(name)
  local mine = db and db.recipeSources and db.recipeSources[name]
  local site = ns.Site and ns.Site()
  local g = site and type(site.recipeSrc) == "table" and site.recipeSrc[name]
  if not mine and type(g) == "table" then
    mine = { how = g[1], quest = (g[2] or 0) > 0 and g[2] or nil, npc = g[3] ~= "" and g[3] or nil, map = g[4], x = g[5], y = g[6] }
  end
  if not mine then return nil end
  local zone = mine.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mine.map)
  local at = zone and zone.name and (" in " .. zone.name .. (mine.x and string.format(" (%.0f, %.0f)", mine.x, mine.y) or "")) or ""
  if mine.how == "quest" then
    local title = mine.quest and ((ns.QuestDB and ns.QuestDB[mine.quest] and ns.QuestDB[mine.quest][1])
      or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(mine.quest)))
    return "Quest reward: " .. (title or ("quest " .. tostring(mine.quest))) .. (mine.npc and (", from " .. mine.npc) or "") .. at
  elseif mine.how == "trainer" then return "Trainer" .. (mine.npc and (": " .. mine.npc) or "") .. at
  elseif mine.how == "npc" then return "Taught by " .. (mine.npc or "an NPC") .. at
  elseif mine.how == "item" then return "From a recipe item" .. at end
  return "Learned" .. at .. " (guild member's note)"
end

ns.RegisterModule({
  name = "RecipeSources",
  OnLoad = function(_, saved) db = saved end,
  events = {
    TRAINER_SHOW = function() trainerOpen = true end,
    TRAINER_CLOSED = function() trainerOpen = false end,
    MERCHANT_SHOW = function() merchantOpen = true end,
    MERCHANT_CLOSED = function() merchantOpen = false end,
    QUEST_TURNED_IN = function(_, _, questID) lastQuest = { id = questID, t = GetTime() } end,
    UNIT_SPELLCAST_SUCCEEDED = function(_, _, unit) if unit == "player" then lastItemUse = GetTime() end end,
    CHAT_MSG_SYSTEM = function(_, _, msg)
      if type(msg) ~= "string" or ns.IsSecret(msg) then return end
      for _, p in ipairs(LEARN) do
        local name = p and msg:match(p)
        if name then
          name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
          pcall(learned, name)
          return
        end
      end
    end,
  },
})
