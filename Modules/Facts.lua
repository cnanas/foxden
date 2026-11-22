-- Module: Facts. Your personal stats and fun facts, this week and all time, per character.
-- The modern client keeps the combat log from addons, so these come from what it does tell us:
--   kills      "<mob> dies, you gain N experience." (mobs that gave you XP)
--   deaths     PLAYER_DEAD: where, and the enemy you were fighting (your target) at the time
--   quests     QUEST_TURNED_IN (with its XP and gold)
--   gold/items "You loot ..." lines
--   casts      your own successful spell casts (favourite ability, hearthstones)
--   zones      time spent in each zone, XP gained, levels gained
-- Dungeon runs, bosses and wipes come from the run log (ns.GetRuns), not from here.
--
-- FoxdenDB.facts[charKey] = { all = counters, weeks = { ["2026-47"] = counters } }   (last 12 weeks kept)
-- counters = { kills = { [name] = n }, deaths = n, deathZones = { [zone] = n }, diedTo = { [name] = n },
--   quests = n, questXP = n, questGold = n, gold = copper looted, items = n, casts = { [spellID] = n },
--   hearths = n, zones = { [zone] = seconds }, xp = n, levels = n }

local _, ns = ...
local db
local HEARTH = { [8690] = true } -- Hearthstone

local function weekKey(t) return date("%Y-%W", t or time()) end
ns.FactsWeekKey = weekKey

local function blank()
  return { kills = {}, deaths = 0, deathZones = {}, diedTo = {}, quests = 0, questXP = 0, questGold = 0, gold = 0, items = 0,
    casts = {}, hearths = 0, zones = {}, xp = 0, levels = 0 }
end

local function mine()
  if not db then return nil end
  db.facts = db.facts or {}
  local k = ns.CharKey()
  local f = db.facts[k]
  if not f then f = { all = blank(), weeks = {} }; db.facts[k] = f end
  local wk = weekKey()
  if not f.weeks[wk] then
    f.weeks[wk] = blank()
    -- keep the last 12 weeks
    local keys = {}
    for key in pairs(f.weeks) do keys[#keys + 1] = key end
    table.sort(keys)
    for i = 1, #keys - 12 do f.weeks[keys[i]] = nil end
  end
  return f, f.weeks[wk]
end

-- Add to a counter in both all-time and this week. field: "deaths" (number) or "kills", "Name" (map)
local function bump(field, key, by)
  local f, w = mine()
  if not f then return end
  by = by or 1
  for _, c in ipairs({ f.all, w }) do
    if key ~= nil then
      c[field] = c[field] or {}
      c[field][key] = (c[field][key] or 0) + by
    else
      c[field] = (c[field] or 0) + by
    end
  end
end

-- All-time numbers the game keeps itself, for history from before Foxden counted:
--   quests  every quest this character has completed (the game's completed-quest list)
--   levels  current level - 1
--   the achievement Statistics, when this client has them (deaths, creatures killed, gold
--   looted, quests, hearthstone uses). Each is nil when the game can't say.
local STAT = { deaths = 60, kills = 1197, gold = 328, quests = 98, hearths = 1149 }
function ns.FactsHistory()
  local h = {}
  local ok, list = false, nil
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs) end
  if ok and type(list) == "table" then h.quests = #list
  elseif GetQuestsCompleted then
    local t = {}
    if pcall(GetQuestsCompleted, t) then local n = 0; for _ in pairs(t) do n = n + 1 end; h.quests = n > 0 and n or nil end
  end
  h.levels = math.max(0, (UnitLevel("player") or 1) - 1)
  if GetStatistic then
    for k, id in pairs(STAT) do
      local okS, v = pcall(GetStatistic, id)
      if okS and v and not ns.IsSecret(v) then
        local text = tostring(v)
        if k == "gold" then
          -- money text: numbers before coin icons (UI-GoldIcon ...) or g / s / c
          local function part(icon, letter)
            return tonumber(text:match("(%d+)%s*|T[^|]*" .. icon) or text:match("(%d+)%s*" .. letter .. "%f[%A]") or "0") or 0
          end
          local copper = part("GoldIcon", "g") * 10000 + part("SilverIcon", "s") * 100 + part("CopperIcon", "c")
          if copper > 0 then h.gold = copper end
        else
          local n = tonumber(text:match("^%s*([%d,]+)%s*$") and (text:gsub("[^%d]", "")) or nil)
          if n and n > 0 then h[k] = n end
        end
      end
    end
  end
  return h
end

-- Is this cast an ability worth calling a favourite (not a mount, not the hearthstone)?
function ns.FactsIsAbility(spellID)
  if HEARTH[spellID] then return false end
  if C_MountJournal and C_MountJournal.GetMountFromSpell then
    local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
    if ok and mountID then return false end
  end
  return true
end

-- This character's counters: (all-time, this week)
function ns.Facts(charKey)
  local f = db and db.facts and db.facts[charKey or ns.CharKey()]
  if not f then return blank(), blank() end
  return f.all, f.weeks[weekKey()] or blank()
end

-- ---- reading chat lines ---------------------------------------------------------------------
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
  fmt = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return "^" .. fmt:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
end
local xpPatterns
local function killedName(text)
  if not xpPatterns then
    xpPatterns = {}
    -- the game's own wording for "<mob> dies, you gain N experience." (with and without rested bonus)
    for _, g in ipairs({ "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION4",
      "COMBATLOG_XPGAIN_EXHAUSTION5", "COMBATLOG_XPGAIN_FIRSTPERSON" }) do
      local p = toPattern(_G[g])
      if p then xpPatterns[#xpPatterns + 1] = p end
    end
    if #xpPatterns == 0 then xpPatterns[1] = "^(.+) dies, you gain (%d+) experience" end
  end
  for _, p in ipairs(xpPatterns) do
    local name = text:match(p)
    if name then return name end
  end
end

-- copper from "You loot 1 Gold, 2 Silver, 3 Copper" (any order or subset, the game's words)
local function copperOf(text)
  local total = 0
  local function amount(fmt, mult)
    local word = type(fmt) == "string" and fmt:gsub("%%d", ""):gsub("^%s+", ""):gsub("%s+$", "") or nil
    if word and word ~= "" then
      local n = text:match("(%d+)%s*" .. word:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
      if n then total = total + tonumber(n) * mult end
    end
  end
  amount(GOLD_AMOUNT or "%d Gold", 10000); amount(SILVER_AMOUNT or "%d Silver", 100); amount(COPPER_AMOUNT or "%d Copper", 1)
  return total
end

-- ---- zones and XP -------------------------------------------------------------------------------
local zone, zoneSince
local function zoneTick()
  local now = GetTime()
  if zone and zoneSince then bump("zones", zone, math.floor(now - zoneSince + 0.5)) end
  local z = GetRealZoneText and GetRealZoneText() or nil
  if ns.IsSecret(z) then z = nil end
  zone, zoneSince = (z ~= "" and z) or nil, now
end
local lastXP, lastMax

ns.RegisterModule({
  name = "Facts",
  OnLoad = function(_, saved) db = saved end,
  events = {
    PLAYER_LOGIN = function()
      lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
      zoneTick()
      C_Timer.NewTicker(60, zoneTick) -- time per zone, a minute at a time
    end,
    ZONE_CHANGED_NEW_AREA = function() zoneTick() end,
    PLAYER_LOGOUT = function() zoneTick() end,
    CHAT_MSG_COMBAT_XP_GAIN = function(_, _, text)
      if type(text) ~= "string" or ns.IsSecret(text) then return end
      local name = killedName(text)
      if name then bump("kills", name) end
    end,
    PLAYER_XP_UPDATE = function()
      local xp, mx = UnitXP("player"), UnitXPMax("player")
      if ns.IsSecret(xp) or not lastXP then lastXP, lastMax = xp, mx; return end
      local gained = xp >= lastXP and (xp - lastXP) or ((lastMax or 0) - lastXP + xp) -- rolled over a level
      if gained > 0 and gained < 10000000 then bump("xp", nil, gained) end
      lastXP, lastMax = xp, mx
    end,
    PLAYER_LEVEL_UP = function() bump("levels") end,
    PLAYER_DEAD = function()
      bump("deaths")
      local z = GetRealZoneText and GetRealZoneText()
      if z and z ~= "" and not ns.IsSecret(z) then bump("deathZones", z) end
      -- the enemy you were fighting: your target, if it's hostile
      if UnitExists("target") and UnitCanAttack("player", "target") then
        local n = UnitName("target")
        if n and not ns.IsSecret(n) then bump("diedTo", n) end
      end
    end,
    QUEST_TURNED_IN = function(_, _, _, xp, money)
      bump("quests")
      if type(xp) == "number" and not ns.IsSecret(xp) and xp > 0 then bump("questXP", nil, xp) end
      if type(money) == "number" and not ns.IsSecret(money) and money > 0 then bump("questGold", nil, money) end
    end,
    CHAT_MSG_MONEY = function(_, _, text)
      if type(text) ~= "string" or ns.IsSecret(text) then return end
      local c = copperOf(text)
      if c > 0 then bump("gold", nil, c) end
    end,
    CHAT_MSG_LOOT = function(_, _, text, _, _, _, player)
      if type(text) ~= "string" or ns.IsSecret(text) then return end
      -- only your own loot: "You receive loot: ..." (the game's wording)
      local mineFmt = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(.-)%%") or "You receive loot:"
      if mineFmt ~= "" and text:sub(1, #mineFmt) == mineFmt then bump("items") end
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(_, _, unit, _, spellID)
      if unit ~= "player" or type(spellID) ~= "number" or ns.IsSecret(spellID) then return end
      bump("casts", spellID)
      if HEARTH[spellID] then bump("hearths") end
    end,
  },
})
