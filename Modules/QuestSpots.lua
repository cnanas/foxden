-- Module: QuestSpots. Where quests start and end, learned while you play: when you
-- accept or turn in a quest, Foxden notes the NPC and where you're standing (outdoors
-- only; the game hides positions inside dungeons). Shared with the guild through the
-- website, so dungeon quests that no database knows yet gain map pins.
-- It also learns quest chains: a quest you accept within two minutes of turning in another at
-- the same NPC is that quest's next step. With its title, level, objective and your faction, so
-- Forever's new quests (no database has them yet) get chains on the map and in the journal.
--
-- FoxdenDB.questSpots[questID] = { s = { n = npc, m = mapID, x, y }, e = { ... },
--   p = questID before it, t = title, l = level, o = objective, f = "A"/"H" }   (x, y in 0-100)

local _, ns = ...
local db

local function here()
  if IsInInstance and IsInInstance() then return nil end
  local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not okM or type(map) ~= "number" or ns.IsSecret(map) then return nil end
  local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not okP or not pos then return nil end
  local x, y = pos:GetXY()
  if type(x) ~= "number" or ns.IsSecret(x) or x <= 0 then return nil end
  return map, math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100
end

local function npcName()
  for _, unit in ipairs({ "npc", "questnpc" }) do
    if UnitExists and UnitExists(unit) then
      local n = UnitName(unit)
      if type(n) == "string" and not ns.IsSecret(n) then return n end
    end
  end
end

local function note(questID, kind)
  if type(questID) ~= "number" or ns.IsSecret(questID) or not db then return end
  local map, x, y = here()
  if not map then return end
  db.questSpots = db.questSpots or {}
  local q = db.questSpots[questID] or {}
  q[kind] = { n = npcName() or "", m = map, x = x, y = y }
  db.questSpots[questID] = q
  ns.Changed()
end

-- What the quest log says about a quest: title, level and objectives.
local function logInfo(questID)
  local title, level, obj
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID); if ok and type(t) == "string" then title = t end
  end
  local index
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, questID); if ok then index = i end
  elseif GetQuestLogIndexByID then
    local ok, i = pcall(GetQuestLogIndexByID, questID); if ok and i and i > 0 then index = i end
  end
  if index then
    if C_QuestLog and C_QuestLog.GetInfo then
      local ok, info = pcall(C_QuestLog.GetInfo, index)
      if ok and type(info) == "table" then title = title or info.title; level = info.level end
    elseif GetQuestLogTitle then
      local ok, t, l = pcall(GetQuestLogTitle, index)
      if ok then title = title or t; level = l end
    end
  end
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(list) == "table" then
      local parts = {}
      for _, o in ipairs(list) do
        -- "0/8 Defias Pillager slain" -> "Defias Pillager slain: 8"
        local t = type(o) == "table" and type(o.text) == "string" and o.text or nil
        if t and not ns.IsSecret(t) then
          local have, need, what = t:match("^(%d+)/(%d+)%s+(.+)$")
          parts[#parts + 1] = need and (what .. ": " .. need) or t
        end
      end
      if #parts > 0 then obj = table.concat(parts, "; ") end
    end
  end
  if title and ns.IsSecret(title) then title = nil end
  return title, type(level) == "number" and level or nil, obj
end

local lastTurnIn -- { id, at, npc }
local function learn(questID)
  if type(questID) ~= "number" or ns.IsSecret(questID) or not db then return end
  db.questSpots = db.questSpots or {}
  local q = db.questSpots[questID] or {}
  db.questSpots[questID] = q
  local now = GetTime and GetTime() or 0
  if lastTurnIn and lastTurnIn.id ~= questID and now - lastTurnIn.at < 120 then
    local npc = npcName()
    if not lastTurnIn.npc or not npc or lastTurnIn.npc == npc then q.p = lastTurnIn.id end
  end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  q.f = mine == "Alliance" and "A" or mine == "Horde" and "H" or q.f
  -- the quest log fills in a moment after the quest is accepted
  C_Timer.After(1, function()
    local t, l, o = logInfo(questID)
    q.t, q.l, q.o = t or q.t, l or q.l, o or q.o
    ns.Changed()
  end)
end

ns.RegisterModule({
  name = "QuestSpots",
  OnLoad = function(_, saved) db = saved end,
  events = {
    QUEST_ACCEPTED = function(_, _, a, b) -- (questID) or (index, questID) on older clients
      local id = type(b) == "number" and b or a
      note(id, "s"); learn(id)
    end,
    QUEST_TURNED_IN = function(_, _, questID)
      note(questID, "e")
      if type(questID) == "number" and not ns.IsSecret(questID) then lastTurnIn = { id = questID, at = GetTime and GetTime() or 0, npc = npcName() } end
    end,
  },
})
