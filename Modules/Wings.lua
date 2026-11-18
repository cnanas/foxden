-- Module: Wings. Which wing of a several-in-one dungeon (Scarlet Monastery, Dire Maul,
-- Blackrock Spire, Stratholme) the run is in: run.wing = "Graveyard".
-- From what the game shows on the way in (the group finder name, zone and sub-zone
-- text), and for certain from the first boss killed. Data/Wings.lua has the lists.
-- run.where keeps what the game said, so the word lists can learn from real runs.

local _, ns = ...

local function wingsOf(run) return run and ns.Wings and ns.Wings[run.instanceID] end

-- The run's wing ({ name, final, bosses, match }), or nil.
function ns.RunWing(run)
  for _, w in ipairs(wingsOf(run) or {}) do if w.name == run.wing then return w end end
end

-- "Scarlet Monastery: Graveyard", or just the dungeon.
function ns.RunName(run)
  if not run then return "Dungeon" end
  return (run.dungeon or "Dungeon") .. (run.wing and (": " .. run.wing) or "")
end

-- The dungeon's bosses (Data/Dungeons.lua entries) in this run's wing, or all of them.
function ns.RunDungeonBosses(run)
  local d = run and ns.Dungeons and ns.Dungeons[run.instanceID]
  local all = d and d.bosses or {}
  local w = ns.RunWing(run)
  if not w then return all end
  local keep = {}
  for _, n in ipairs(w.bosses) do keep[n] = true end
  local out = {}
  for _, b in ipairs(all) do if keep[b.name] then out[#out + 1] = b end end
  return out
end

local function wingOfBoss(run, name)
  for _, w in ipairs(wingsOf(run) or {}) do
    for _, n in ipairs(w.bosses) do if n == name then return w end end
  end
end

local function setWing(run, name, how)
  if run.wing == name then if how == "kill" then run.wingBy = how end return end
  run.wing, run.wingBy = name, how
  if ns.CheckRunDone then ns.CheckRunDone() end -- the boss that told us may have been the wing's last
  if ns.RefreshTracker then ns.RefreshTracker() end
  ns.Changed()
end

local function note(run, key, v)
  if v == nil or v == "" or ns.IsSecret(v) then return end
  run.where = run.where or {}
  run.where[key] = v
end

-- what the game says about where you are; picks the wing if a known word is in it
local function detect(run)
  local ws = wingsOf(run)
  if not ws or run.wingBy == "kill" then return end
  local texts = {}
  local okI, name, _, _, _, _, _, _, _, _, lfg = pcall(GetInstanceInfo)
  if okI then
    texts[#texts + 1] = name
    if type(lfg) == "number" and lfg > 0 and not ns.IsSecret(lfg) then
      note(run, "lfg", lfg)
      if GetLFGDungeonInfo then
        local okL, lname = pcall(GetLFGDungeonInfo, lfg)
        if okL and type(lname) == "string" then texts[#texts + 1] = lname; note(run, "lfgName", lname) end
      end
    end
  end
  for key, fn in pairs({ sub = GetSubZoneText, minimap = GetMinimapZoneText }) do
    if fn then
      local ok, t = pcall(fn)
      if ok and type(t) == "string" then texts[#texts + 1] = t; note(run, key, t) end
    end
  end
  for _, t in ipairs(texts) do
    if type(t) == "string" and not ns.IsSecret(t) then
      local low = t:lower()
      for _, w in ipairs(ws) do
        for _, word in ipairs(w.match or { w.name }) do
          if low:find(word:lower(), 1, true) then setWing(run, w.name, "zone"); return end
        end
      end
    end
  end
end

local function detectSoon()
  local run = ns.GetCurrentRun()
  if run and wingsOf(run) then C_Timer.After(0.5, function() if ns.GetCurrentRun() == run then detect(run) end end) end
end

ns.RegisterModule({
  name = "Wings",
  OnRunStart = function(_, run) if wingsOf(run) then C_Timer.After(2, function() if ns.GetCurrentRun() == run then detect(run) end end) end end,
  OnLoad = function(_, db)
    -- runs saved before Foxden knew wings: name the wing from the bosses they killed
    for _, r in ipairs(db and db.runs or {}) do
      if not r.wing and wingsOf(r) then
        for _, k in ipairs(r.bosses or {}) do
          local w = wingOfBoss(r, k.name)
          if w then r.wing, r.wingBy = w.name, "kill"; break end
        end
      end
    end
    C_Timer.After(3, detectSoon)
  end,
  events = {
    ZONE_CHANGED = function() detectSoon() end,
    ZONE_CHANGED_INDOORS = function() detectSoon() end,
    -- a boss kill settles it (and corrects a guess from the zone text)
    ENCOUNTER_END = function(_, run, _, name, _, _, success)
      if not run or success ~= 1 or ns.IsSecret(name) then return end
      local w = wingOfBoss(run, name)
      if w then setWing(run, w.name, "kill") end
    end,
  },
})
