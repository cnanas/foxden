-- Foxden: the quest engine behind the world map and minimap marks and the quest tracker.
--   ns.Quests.Log()       your quest log, grouped by zone header: { { header, quests = { q, ... } }, ... }
--                         q = { id, title, level, complete, failed, group, index, objectives = { { text, done } } }
--   ns.Quests.Givers()    quest givers to mark: { [key] = { npc, map, x, y, quests = { entry, ... } } }
--                         entry = { id, title, min, level, kind = "new"/"turnin", objective }
--   ns.Quests.Available(id) / ns.Quests.Done(id) / ns.Quests.InLog(id)
-- Quest data: Data/Quests.lua (QuestieDB, GPLv3). Which quests you've done: the game.
-- Available = your faction, race and class, your level (up to 3 above, not grey), what it needs
-- first is done, nothing that rules it out is done or in your log, and it isn't in your log or done.

local _, ns = ...
local Q = {}
ns.Quests = Q
-- how many levels above you to show (Quests page), and whether grey quests show too
local function ahead() local v = ns.settings and tonumber(ns.settings.questAhead); return v or 3 end
local function showGrey() return ns.settings and ns.settings.questShowGrey == true end
Q.Ahead = ahead

local done, inLog, log = {}, {}, {}
local giversCache
local me = {}

local function band(a, b)
  if bit and bit.band then return bit.band(a, b) end
  -- plain Lua fallback (tests): both numbers are below 2^32
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

local function whoAmI()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  me.fac = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
  -- (not "UnitRace and UnitRace()": "and" keeps only the first of the three values)
  local raceID, classID
  if UnitRace then raceID = select(3, UnitRace("player")) end
  if UnitClass then classID = select(3, UnitClass("player")) end
  me.raceBit = type(raceID) == "number" and raceID >= 1 and raceID <= 11 and 2 ^ (raceID - 1) or nil
  me.classBit = type(classID) == "number" and classID >= 1 and classID <= 11 and 2 ^ (classID - 1) or nil
  me.level = UnitLevel and UnitLevel("player") or 1
  me.profs = Q.Professions and Q.Professions() or {}
end

-- Grey quests (next to no XP): the game's own range when it has one.
local function greyBelow()
  local ok, range = false, nil
  if GetQuestGreenRange then ok, range = pcall(GetQuestGreenRange, "player") end
  return ok and type(range) == "number" and range > 0 and range or 8
end
Q.GreyBelow = greyBelow

-- ---- what you've done and what's in your log ----------------------------------------
function Q.ScanCompleted()
  wipe(done)
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(list) == "table" then for _, id in ipairs(list) do done[id] = true end end
  elseif GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted, {})
    if ok and type(t) == "table" then for id in pairs(t) do done[id] = true end end
  end
  giversCache = nil
end

local function objectivesOf(questID, index)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(list) == "table" then
      for _, o in ipairs(list) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then out[#out + 1] = { text = o.text, done = o.finished == true } end
      end
      return out
    end
  end
  if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and index then
    local ok, n = pcall(GetNumQuestLeaderBoards, index)
    for j = 1, ok and n or 0 do
      local okL, text, _, finished = pcall(GetQuestLogLeaderBoard, j, index)
      if okL and type(text) == "string" then out[#out + 1] = { text = text, done = finished and true or false } end
    end
  end
  return out
end

function Q.ScanLog()
  wipe(inLog); wipe(log)
  local group
  local function add(id, title, level, complete, failed, sgroup, index)
    if not group then group = { header = "Other", quests = {} }; log[#log + 1] = group end
    local q = { id = id, title = title, level = level, complete = complete, failed = failed, group = sgroup, index = index }
    q.objectives = objectivesOf(id, index)
    group.quests[#group.quests + 1] = q
    inLog[id] = q
  end
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    for i = 1, okN and n or 0 do
      local ok, info = pcall(C_QuestLog.GetInfo, i)
      if ok and type(info) == "table" then
        if info.isHeader then group = { header = info.title or "Other", quests = {} }; log[#log + 1] = group
        elseif info.questID and info.questID > 0 and not info.isHidden then
          local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
          local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(info.questID) or false
          add(info.questID, info.title, info.level, complete and true or false, failed and true or false, info.suggestedGroup, i)
        end
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    local n = GetNumQuestLogEntries()
    for i = 1, n or 0 do
      local title, level, sgroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
      if isHeader then group = { header = title or "Other", quests = {} }; log[#log + 1] = group
      elseif questID and questID > 0 then add(questID, title, level, isComplete == 1 or isComplete == true, isComplete == -1, sgroup, i) end
    end
  end
  -- drop empty headers (collapsed in the quest log)
  for i = #log, 1, -1 do if #log[i].quests == 0 then table.remove(log, i) end end
  giversCache = nil
end

function Q.Log() return log end
function Q.Done(id) return done[id] == true or (ns.QuestState and ns.QuestState(id) == "done") end
function Q.InLog(id) return inLog[id] end
function Q.Dirty() giversCache = nil end

-- ---- can you pick it up? ---------------------------------------------------------------
local function allDone(list) for _, id in ipairs(list or {}) do if not done[id] then return false end end; return true end
local function anyDone(list) if not list or #list == 0 then return true end; for _, id in ipairs(list) do if done[id] then return true end end; return false end
local function anyTaken(list) for _, id in ipairs(list or {}) do if done[id] or inLog[id] then return true end end; return false end

function Q.Available(id, r)
  r = r or (ns.QuestDB and ns.QuestDB[id])
  if not r or r[14] then return false end -- unknown, or an event/holiday/profession quest
  if inLog[id] or (done[id] and not r[13]) then return false end
  if r[4] ~= "B" and me.fac and r[4] ~= me.fac then return false end
  if r[5] ~= 0 and me.raceBit and band(r[5], me.raceBit) == 0 then return false end
  if r[6] ~= 0 and me.classBit and band(r[6], me.classBit) == 0 then return false end
  local lvl = me.level or 1
  if (r[2] or 0) > lvl + ahead() then return false end
  if (r[12] or 0) > 0 and lvl > r[12] then return false end
  if not showGrey() and (r[3] or 0) > 0 and lvl - r[3] > greyBelow() then return false end
  if not allDone(r[7]) or not anyDone(r[8]) or anyTaken(r[9]) then return false end
  if (r[10] or 0) > 0 and (done[r[10]] or inLog[r[10]]) then return false end
  if (r[11] or 0) > 0 and not inLog[r[11]] then return false end
  -- profession quests: only with that profession, at that level
  if type(r[25]) == "table" and r[25][1] then
    local have = me.profs and me.profs[r[25][1]]
    if not have or have < (r[25][2] or 0) then return false end
  end
  return true
end

-- ---- quest givers and turn-ins to mark ----------------------------------------------------
local function keyOf(map, x, y) return map .. ":" .. math.floor(x * 2 + 0.5) .. ":" .. math.floor(y * 2 + 0.5) end
Q.KeyOf = keyOf

function Q.Givers()
  if giversCache then return giversCache end
  whoAmI()
  local out = {}
  local function at(npc, map, x, y)
    local k = keyOf(map, x, y)
    local g = out[k]
    if not g then g = { npc = npc, map = map, x = x, y = y, quests = {}, byId = {} }; out[k] = g end
    if (g.npc == nil or g.npc == "") and npc and npc ~= "" then g.npc = npc end
    return g
  end
  for id, r in pairs(ns.QuestDB or {}) do
    if (r[16] or 0) > 0 and Q.Available(id, r) then
      local g = at(r[15], r[16], r[17], r[18])
      local e = { id = id, title = r[1], min = r[2], level = r[3], kind = "new", objective = r[23] }
      g.quests[#g.quests + 1] = e; g.byId[id] = e
    end
  end
  -- finished quests in your log: where to turn them in (QuestieDB, else the guild's learned spots)
  local site = ns.Site and ns.Site()
  local spots = ns.db and ns.db.questSpots or {}
  for id, q in pairs(inLog) do
    if q.complete then
      local r = ns.QuestDB and ns.QuestDB[id]
      local npc, map, x, y
      if r and (r[20] or 0) > 0 then npc, map, x, y = r[19], r[20], r[21], r[22]
      elseif spots[id] and spots[id].e then npc, map, x, y = spots[id].e.n, spots[id].e.m, spots[id].e.x, spots[id].e.y end
      if not map and site and type(site.quests) == "table" then
        for _, rows in pairs(site.quests) do
          for _, d in ipairs(type(rows) == "table" and rows or {}) do
            if d[1] == id and (d[20] or 0) > 0 then npc, map, x, y = d[11] ~= "" and d[11] or d[6], d[20], d[21], d[22] end
          end
        end
      end
      if map and map > 0 then
        local g = at(npc, map, x, y)
        local e = { id = id, title = q.title, level = q.level, kind = "turnin" }
        g.quests[#g.quests + 1] = e; g.byId[id] = e
      end
    end
  end
  for _, g in pairs(out) do
    table.sort(g.quests, function(a, b)
      if a.kind ~= b.kind then return a.kind == "turnin" end
      return (a.level or 0) < (b.level or 0)
    end)
  end
  giversCache = out
  return out
end

-- ---- dungeon quests: fill gaps from QuestieDB ----------------------------------------------
-- The website's dungeon quest rows (Blizzard's API + the older QuestieDB on GitHub + what the
-- guild learned) miss Forever's new dungeons. The QuestieDB addon has them: where they start
-- and end, levels, objective, and what each needs first. Rows keep the website's layout.
local nextOf, nextFor
local function chainNext()
  if nextFor == ns.QuestDB and nextOf then return nextOf end
  nextOf, nextFor = {}, ns.QuestDB
  local count = {}
  for id, r in pairs(ns.QuestDB or {}) do
    for _, pre in ipairs(r[8] or r[7] or {}) do count[pre] = (count[pre] or 0) + 1; nextOf[pre] = id end
  end
  for pre, n in pairs(count) do if n > 1 then nextOf[pre] = nil end end -- several follow-ups: not one chain
  for id, r in pairs(ns.QuestDB or {}) do if (r[10] or 0) > 0 and ns.QuestDB[r[10]] then nextOf[id] = r[10] end end
  return nextOf
end
-- The whole chain around a quest, from QuestieDB: { {id, title, giver, map, x, y, min, faction, level}, ... }
function Q.ChainFromDB(id)
  local db = ns.QuestDB or {}
  if not db[id] then return nil end
  local nxt, seen, back, fwd = chainNext(), { [id] = true }, {}, {}
  local cur = id
  while #back < 30 do
    local r = db[cur]
    local pre = r and ((r[8] and r[8][1]) or (r[7] and r[7][1]))
    if not pre or seen[pre] or not db[pre] then break end
    seen[pre] = true; table.insert(back, 1, pre); cur = pre
  end
  cur = id
  while #fwd < 30 do
    local n = nxt[cur]
    if not n or seen[n] then break end
    seen[n] = true; fwd[#fwd + 1] = n; cur = n
  end
  if #back + #fwd == 0 then return nil end
  local out = {}
  local function step(qid) local r = db[qid]; out[#out + 1] = { qid, r[1], r[15], r[16], r[17], r[18], r[2], r[4], r[3] } end
  for _, q in ipairs(back) do step(q) end
  step(id)
  for _, q in ipairs(fwd) do step(q) end
  return out
end

local zoneNames = {}
local function zoneOf(map)
  if not map or map == 0 then return "" end
  if zoneNames[map] == nil then
    local ok, info = false, nil
    if C_Map and C_Map.GetMapInfo then ok, info = pcall(C_Map.GetMapInfo, map) end
    zoneNames[map] = ok and type(info) == "table" and info.name or ""
  end
  return zoneNames[map]
end

-- Your professions: { [skillLineID] = level }. Profession quests only count when you have it.
local PROF_NAMES = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism", [186] = "Mining",
  [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [393] = "Skinning", [129] = "First Aid", [185] = "Cooking",
  [356] = "Fishing", [755] = "Jewelcrafting", [773] = "Inscription" }
Q.PROF_NAMES = PROF_NAMES
function Q.Professions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      local ok, _, _, level, _, _, _, line = false
      if type(idx) == "number" then ok, _, _, level, _, _, _, line = pcall(GetProfessionInfo, idx) end
      if ok and line then out[line] = level or 0 end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then -- older clients: by name
    local byName = {}
    for id, n in pairs(PROF_NAMES) do byName[n] = id end
    for i = 1, tonumber(GetNumSkillLines()) or 0 do
      local name, header, _, rank = GetSkillLineInfo(i)
      if name and not header and byName[name] then out[byName[name]] = rank or 0 end
    end
  end
  return out
end
-- Why you can't take a quest, or nil: "Needs Alchemy (150)", "Unavailable to Undead"
function Q.Locked(id)
  local r = ns.QuestDB and ns.QuestDB[id]
  if not r then return nil end
  if type(r[25]) == "table" and r[25][1] then
    local have = Q.Professions()[r[25][1]]
    if not have or have < (r[25][2] or 0) then
      return "Needs " .. (PROF_NAMES[r[25][1]] or "a profession") .. ((r[25][2] or 0) > 0 and (" (" .. r[25][2] .. ")") or ""), "profession"
    end
  end
  whoAmI()
  if r[5] and r[5] ~= 0 and me.raceBit and band(r[5], me.raceBit) == 0 and (r[4] == "B" or r[4] == me.fac) then
    return "Unavailable to " .. ((UnitRace and UnitRace("player")) or "your race"), "race"
  end
end

-- A website dungeon quest row with its gaps filled from QuestieDB (a copy; the original is untouched).
function Q.Enrich(q)
  local r = ns.QuestDB and ns.QuestDB[q[1]]
  if not r then return q end
  local x = {}
  for k, v in pairs(q) do x[k] = v end
  if (x[4] or 0) == 0 then x[4], x[5] = r[3], r[2] end
  if (x[3] or "") == "" then x[3] = r[4] end
  if ((x[8] or 0) == 0) and (r[16] or 0) > 0 then
    x[6], x[8], x[9], x[10] = (x[6] ~= "" and x[6]) or r[15], r[16], r[17], r[18]
    if (x[7] or "") == "" then x[7] = zoneOf(r[16]) end
  end
  if ((x[20] or 0) == 0) and (r[20] or 0) > 0 then
    x[20], x[21], x[22] = r[20], r[21], r[22]
    if (x[11] or "") == "" and r[19] ~= x[6] then x[11] = r[19] end
  end
  if (x[12] or "") == "" and (r[23] or "") ~= "" then x[12] = r[23] end
  if type(x[23]) ~= "table" or #x[23] < 2 then x[23] = Q.ChainFromDB(q[1]) or x[23] end
  return x
end

-- ---- when something goes wrong: keep it, say it once ------------------------------------
-- WoW hides script errors by default, so a broken mark builder would just show nothing.
-- Errors go to FoxdenDB.questErrors (the last 10) and one line in chat per session.
local warned = false
function Q.Try(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return true end
  if ns.db then
    ns.db.questErrors = ns.db.questErrors or {}
    table.insert(ns.db.questErrors, 1, { at = time and time() or 0, where = where, err = tostring(err) })
    while #ns.db.questErrors > 10 do table.remove(ns.db.questErrors) end
  end
  if not warned then
    warned = true
    if ns.say then ns.say("Couldn't draw quest marks (" .. where .. "). Type /fox quests for details.", true) end
  end
  return false
end

-- /fox quests: what the quest helper knows and draws right now.
function ns.QuestReport()
  local say = function(t) if ns.say then ns.say(t, true) else print(t) end end
  local n = 0
  for _ in pairs(ns.QuestDB or {}) do n = n + 1 end
  whoAmI()
  local avail, givers, turnins = 0, 0, 0
  for _, g in pairs(Q.Givers()) do
    givers = givers + 1
    for _, e in ipairs(g.quests) do if e.kind == "turnin" then turnins = turnins + 1 else avail = avail + 1 end end
  end
  local logged = 0
  for _ in pairs(inLog) do logged = logged + 1 end
  local src = ns.QuestSource and ((ns.QuestSource.building and "reading QuestieDB..." or ns.QuestSource.name)
    .. (ns.QuestSource.note and ("; " .. ns.QuestSource.note) or "")) or "?"
  say(string.format("Quest data: %d quests (%s). You (level %s, %s): %d you can pick up at %d spots, %d to turn in, %d in your log.",
    n, src, tostring(me.level), me.fac == "A" and "Alliance" or me.fac == "H" and "Horde" or "faction unknown", avail, givers, turnins, logged))
  if ns.QuestMapStatus then say(ns.QuestMapStatus()) end
  local s = ns.settings or {}
  say(string.format("Settings: map %s, dungeon quests %s, minimap %s, tracker %s, up to %d levels above you%s.",
    s.questPinsAll ~= false and "on" or "off", s.questPins ~= false and "on" or "off", s.questMinimap ~= false and "on" or "off",
    s.questTracker ~= false and "on" or "off", ahead(), showGrey() and ", grey quests shown" or ""))
  local errs = ns.db and ns.db.questErrors
  if errs and errs[1] then say("Last error (" .. errs[1].where .. "): " .. errs[1].err) else say("No errors.") end
end

-- ---- XP: what a quest gives you -------------------------------------------------------
-- In your log the game says exactly. Otherwise: the quest's base XP (QuestieDB's figures for
-- Forever, else the website's from Blizzard's API) at your level: full up to 5 levels above
-- the quest, then 20% less per level down to a tenth, rounded the way the game rounds, and
-- nothing at max level.
local xpDB
local function baseXP(id)
  if not xpDB then -- (not cached when missing: QuestieDB may turn up later)
    local L = _G.LibQuestieDB
    if L and L.Support and L.Support.Get then
      local ok, sup = pcall(L.Support.Get, "QuestXP")
      if ok and type(sup) == "table" and type(sup.db) == "table" then xpDB = sup.db end
    end
  end
  local row = type(xpDB) == "table" and xpDB[id]
  if type(row) == "table" and row[2] then return row[2], row[1] end
  local site = ns.Site and ns.Site()
  for _, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, d in ipairs(type(rows) == "table" and rows or {}) do
      if d[1] == id and (d[14] or 0) > 0 then return d[14], d[4] end
    end
  end
end
local function roundXP(xp)
  if xp <= 100 then return 5 * math.floor((xp + 2) / 5)
  elseif xp <= 500 then return 10 * math.floor((xp + 5) / 10)
  elseif xp <= 1000 then return 25 * math.floor((xp + 12) / 25) end
  return 50 * math.floor((xp + 25) / 50)
end
function Q.XP(id, questLevel)
  local lvl = UnitLevel and UnitLevel("player") or 1
  local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
  if type(maxLevel) == "number" and lvl >= maxLevel then return 0 end
  if inLog[id] and GetQuestLogRewardXP then
    local ok, xp = pcall(GetQuestLogRewardXP, id)
    if ok and type(xp) == "number" and xp > 0 then return xp end
  end
  local xp, qlvl = baseXP(id)
  if not xp then return nil end
  qlvl = (qlvl and qlvl > 0) and qlvl or questLevel or lvl
  local mult = math.max(1, math.min(10, 2 * (qlvl - lvl) + 20))
  return roundXP(xp * mult / 10)
end

-- How a quest's level reads to you: the game's difficulty colours.
function Q.Color(level)
  if GetQuestDifficultyColor and level and level > 0 then
    local ok, c = pcall(GetQuestDifficultyColor, level)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
  end
  return 1, 0.82, 0
end

-- Anything that shows quests (tracker, world map, minimap) refreshes after the log settles.
local listeners, pending = {}, false
function Q.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    whoAmI(); Q.ScanLog()
    for _, fn in ipairs(listeners) do pcall(fn) end
  end)
end
Q.Changed = changed

local function rescan() changed() end
ns.RegisterModule({
  name = "Quests",
  events = {
    PLAYER_LOGIN = function() whoAmI(); Q.ScanCompleted(); changed() end,
    PLAYER_LEVEL_UP = function() C_Timer.After(1, changed) end,
    QUEST_LOG_UPDATE = rescan,
    QUEST_WATCH_UPDATE = rescan,
    QUEST_ACCEPTED = rescan,
    QUEST_REMOVED = rescan,
    UNIT_QUEST_LOG_CHANGED = function(_, _, unit) if unit == "player" then changed() end end,
    QUEST_TURNED_IN = function(_, _, questID)
      if type(questID) == "number" and not ns.IsSecret(questID) then done[questID] = true end
      changed()
    end,
  },
})
