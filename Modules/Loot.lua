-- Module: Loot. What each boss dropped, so the guild's journal can list boss loot
-- (Forever's in-game journal is empty). When a boss fight starts Foxden notes the
-- boss's NPC ID; anything green or better looted from that boss's corpse is recorded.
--
-- run.loot = { { e = encounterID, b = bossName, i = itemID, q = quality }, ... }
--
-- Also everything you and your group looted during the run, from the game's "receives
-- loot" chat lines and its boss-loot event (for the run summary and the Loot tab):
-- run.got = { { i = itemID, q = quality, n = count, w = who, b = bossName }, ... }

local _, ns = ...

local function npcID(guid)
  if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function call(fn, ...) if type(fn) ~= "function" then return end return select(2, pcall(fn, ...)) end
-- loot sources come as pairs: guid, count, guid, count, ...
local function sources(slot)
  if type(GetLootSourceInfo) ~= "function" then return {} end
  local r = { pcall(GetLootSourceInfo, slot) }
  if not r[1] then return {} end
  local out = {}
  for k = 2, select("#", unpack(r)), 2 do out[#out + 1] = r[k] end
  return out
end

local function noteBoss(run, encounterID, name)
  for i = 1, 5 do
    local unit = "boss" .. i
    if UnitExists and UnitExists(unit) then
      local id = UnitGUID and npcID(UnitGUID(unit))
      if id then
        run._bossNpc = run._bossNpc or {}
        run._bossNpc[id] = { e = encounterID, b = name }
        if i == 1 and ns.db then -- remembered so the Journal can show this boss's model
          ns.db.bossNpc = ns.db.bossNpc or {}
          ns.db.bossNpc[encounterID] = id
        end
      end
    end
  end
end

local function onLoot(run)
  if not run or not run._bossNpc then return end
  run.loot = run.loot or {}
  run._lootSeen = run._lootSeen or {}
  for slot = 1, (call(GetNumLootItems) or 0) do
    local link = call(GetLootSlotLink, slot)
    local itemID = type(link) == "string" and not ns.IsSecret(link) and tonumber(link:match("item:(%d+)"))
    local okI, _, _, _, _, quality = false
    if type(GetLootSlotInfo) == "function" then okI, _, _, _, _, quality = pcall(GetLootSlotInfo, slot) end
    if not okI or ns.IsSecret(quality) then quality = nil end
    if itemID and ns.WishKind and ns.WishKind(itemID) and not (run._wishSaid and run._wishSaid[itemID]) then
      run._wishSaid = run._wishSaid or {}; run._wishSaid[itemID] = true
      ns.say("It dropped! " .. link .. " is on your wishlist (" .. ns.WISH_LABEL[ns.WishKind(itemID)]:lower() .. ").")
      if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    end
    if itemID and (type(quality) ~= "number" or quality >= 2) then
      for _, guid in ipairs(sources(slot)) do
        local id = npcID(guid)
        local boss = id and run._bossNpc[id]
        local seenKey = tostring(guid) .. ":" .. itemID
        if boss and not run._lootSeen[seenKey] then
          run._lootSeen[seenKey] = true
          run.loot[#run.loot + 1] = { e = boss.e, b = boss.b, i = itemID, q = type(quality) == "number" and quality or nil }
          ns.Changed()
        end
      end
    end
  end
end

-- ---- what everyone looted ---------------------------------------------------------

-- a GlobalStrings format ("%s receives loot: %sx%d.") as a Lua pattern
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
  fmt = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return "^" .. fmt:gsub("\001", "(.+)"):gsub("\002", "(%%d+)") .. "$"
end
local PATTERNS -- { pattern, isSelf, hasCount }, most specific first
local function patterns()
  if PATTERNS then return PATTERNS end
  PATTERNS = {}
  local function add(fmt, isSelf, hasCount) local p = toPattern(fmt); if p then PATTERNS[#PATTERNS + 1] = { p, isSelf, hasCount } end end
  add(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", true, true)
  add(LOOT_ITEM_SELF or "You receive loot: %s.", true, false)
  add(LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d.", false, true)
  add(LOOT_ITEM or "%s receives loot: %s.", false, false)
  return PATTERNS
end

local function shortName(name)
  if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return nil end
  return name:match("^[^%s%-]+") or name
end

local function qualityOf(link, itemID)
  if C_Item and C_Item.GetItemInfo then
    local ok, _, _, q = pcall(C_Item.GetItemInfo, link or itemID)
    if ok and type(q) == "number" then return q end
  end
  if C_Item and C_Item.GetItemQualityByID then
    local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
    if ok and type(q) == "number" then return q end
  end
end

-- the boss an item came from, if Foxden saw it on a boss's corpse
local function bossFor(run, itemID)
  for i = #(run.loot or {}), 1, -1 do
    local l = run.loot[i]
    if l.i == itemID then return l.b end
  end
end

-- One item someone got. from: "chat" or "boss" (the two can report the same item: merged).
local function addGot(run, itemID, link, count, who, boss, from)
  run.got = run.got or {}
  for i = #run.got, math.max(1, #run.got - 20), -1 do
    local g = run.got[i]
    if g.i == itemID and g.w == who and not g[from] and (g.chat or g.boss) then
      g[from] = true
      g.b = g.b or boss
      return
    end
  end
  run.got[#run.got + 1] = { i = itemID, q = qualityOf(link, itemID), n = count, w = who, b = boss or bossFor(run, itemID), [from] = true }
  ns.Changed()
end

local function onLootChat(run, text, player)
  if not run or type(text) ~= "string" or ns.IsSecret(text) then return end
  for _, p in ipairs(patterns()) do
    local a, b, c = text:match(p[1])
    if a then
      local who, link, count
      if p[2] then who, link, count = UnitName("player"), a, b else who, link, count = a, b, c end
      local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if not itemID then return end
      addGot(run, itemID, link, tonumber(count) or 1, shortName(who) or shortName(player) or "?", nil, "chat")
      return
    end
  end
end
ns.LootPatternFor = toPattern -- for tests

-- The run's loot, best first: { { i, q, n, w, b }, ... } and how many are grey.
function ns.RunLootList(run)
  local list, grey = {}, 0
  for idx, g in ipairs(run and run.got or {}) do
    local q = g.q
    if not q and ns.UI and ns.UI.ItemLook then q = select(3, ns.UI.ItemLook(g.i)) end
    list[#list + 1] = { i = g.i, q = q, n = g.n or 1, w = g.w, b = g.b, at = idx }
    if q == 0 then grey = grey + 1 end
  end
  table.sort(list, function(x, y)
    local qx, qy = x.q or 1, y.q or 1
    if qx ~= qy then return qx > qy end
    return x.at < y.at
  end)
  return list, grey
end

ns.RegisterModule({
  name = "Loot",
  -- the merge marks aren't worth saving
  OnRunFinish = function(_, run) for _, g in ipairs(run.got or {}) do g.chat, g.boss = nil, nil end end,
  events = {
    ENCOUNTER_START = function(_, run, encounterID, name)
      if not run or ns.IsSecret(encounterID) then return end
      noteBoss(run, encounterID, name)
      C_Timer.After(1, function() if ns.GetCurrentRun() == run then noteBoss(run, encounterID, name) end end)
    end,
    LOOT_OPENED = function(_, run) onLoot(run) end,
    CHAT_MSG_LOOT = function(_, run, text, player) onLootChat(run, text, player) end,
    -- a boss item someone in the group got (newer clients)
    ENCOUNTER_LOOT_RECEIVED = function(_, run, _, itemID, link, quantity, player)
      if not run or ns.IsSecret(itemID) or type(itemID) ~= "number" then return end
      local boss = bossFor(run, itemID)
      if not boss then
        local log = run._encounterLog
        boss = log and log[#log] and log[#log].name
      end
      addGot(run, itemID, link, tonumber(quantity) or 1, shortName(player) or "?", boss, "boss")
    end,
    -- once a wished item is in your bags, it comes off the list
    BAG_UPDATE_DELAYED = function()
      if not (ns.Wishlist and C_Item and C_Item.GetItemCount) then return end
      for _, w in ipairs(ns.Wishlist()) do
        local ok, n = pcall(C_Item.GetItemCount, w.i, true)
        if ok and type(n) == "number" and n > 0 then
          ns.say("You got " .. (w.n or "your wishlist item") .. "! It's off your wishlist.")
          ns.SetWish(w.i, nil)
          if ns.RefreshUI then ns.RefreshUI() end
          return
        end
      end
    end,
  },
})
