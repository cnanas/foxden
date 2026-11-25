-- Module: QuestLinks. Hands the website what the QuestieDB addon knows about how quests chain
-- together, so its journal shows the same chains as the game. QuestieDB's data for Forever's
-- newer zones (Riverglades and the rest) only exists in game; the website can't get it itself.
-- Written at logout, only when the QuestieDB version changes; the companion uploads it once.
--
-- FoxdenDB.questLinks = { ver = "QuestieDB 1.2.3", at = time, links = {
--   [questID] = "needs-all ids|needs-one ids|next quest|faction" } }   (ids space-separated)
-- Only quests that need another quest or lead to one are listed.

local _, ns = ...

local function ids(list)
  local out = {}
  for _, v in ipairs(type(list) == "table" and list or {}) do if type(v) == "number" then out[#out + 1] = v end end
  return table.concat(out, " ")
end

local function save(db)
  local src = ns.QuestSource
  if not (ns.QuestDB and src and type(src.name) == "string" and src.name:find("^QuestieDB")) then return end
  if db.questLinks and db.questLinks.ver == src.name then return end -- already handed over
  local links, n = {}, 0
  for id, r in pairs(ns.QuestDB) do
    local all, one, nxt = ids(r[7]), ids(r[8]), tonumber(r[10]) or 0
    if all ~= "" or one ~= "" or nxt > 0 then
      links[id] = all .. "|" .. one .. "|" .. nxt .. "|" .. (r[4] or "")
      n = n + 1
    end
  end
  if n > 0 then db.questLinks = { ver = src.name, at = GetServerTime(), links = links } end
end

local saved
ns.RegisterModule({
  name = "QuestLinks",
  OnLoad = function(_, db) saved = db end,
  events = { PLAYER_LOGOUT = function() if saved then pcall(save, saved) end end },
})
