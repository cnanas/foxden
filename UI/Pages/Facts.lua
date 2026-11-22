-- Page: Your stats. Personal stats and fun facts for this character, this week or all time:
-- tiles for the big numbers (kills, deaths, quests, gold, levels, runs) and fact cards for the
-- fun ones (most killed, died fighting, most dangerous zone, favourite ability, favourite zone,
-- dungeon nemesis, fastest run). Data: Modules/Facts.lua and the run log.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, GAP = 16, 14

local page = { key = "facts", label = "Your stats", order = 15 }
local span = "week" -- or "all"

local function top(map, n)
  local list = {}
  for k, v in pairs(map or {}) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return tostring(a[1]) < tostring(b[1]) end)
  local out = {}
  for i = 1, math.min(n or 5, #list) do out[i] = list[i] end
  return out
end
local function commas(n) return ns.Commas and ns.Commas(n) or tostring(n) end
local function hours(s)
  s = math.floor(s or 0)
  if s >= 3600 then return string.format("%dh %dm", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
  return math.floor(s / 60) .. "m"
end
local function spellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, i = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(i) == "table" then return i.name, i.iconID end
  end
  if GetSpellInfo then local n, _, icon = GetSpellInfo(id); return n, icon end
end

-- Dungeon numbers from the run log, this week or all time.
local function runFacts(weekOnly)
  local wk = ns.FactsWeekKey and ns.FactsWeekKey()
  local out = { runs = 0, bosses = 0, wipes = 0, nemesis = {}, fastest = nil, gold = 0 }
  for _, r in ipairs(ns.GetRuns and ns.GetRuns() or {}) do
    if not weekOnly or (r.endTime and ns.FactsWeekKey(r.endTime) == wk) then
      out.runs = out.runs + 1
      out.bosses = out.bosses + #(r.bosses or {})
      out.wipes = out.wipes + (r.wipes or 0)
      out.gold = out.gold + (r.gold or 0)
      for _, s in ipairs(r.segments or {}) do
        if s.kind == "boss" and s.kill == false and s.label then out.nemesis[s.label] = (out.nemesis[s.label] or 0) + 1 end
      end
      local d = ns.RunDuration and ns.RunDuration({ run = r })
      if d and d > 0 and #(r.bosses or {}) > 0 and (not out.fastest or d < out.fastest.d) then out.fastest = { d = d, name = r.dungeon } end
    end
  end
  return out
end

function page:Build(f)
  self.scroll = CreateFrame("ScrollFrame", nil, f)
  self.scroll:EnableMouseWheel(true)
  self.body = CreateFrame("Frame", nil, self.scroll)
  self.scroll:SetScrollChild(self.body)
  self.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (self.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  local b = self.body
  self.spans = {}
  for i, s in ipairs({ { "week", "This week" }, { "all", "All time" } }) do
    local btn = UI.Button(b, s[2], 100, 26, function() span = s[1]; self:Refresh() end)
    btn.span = s[1]
    btn:SetPoint("TOPLEFT", PAD + (i - 1) * 104, -PAD)
    self.spans[i] = btn
  end
  self.note = UI.Text(b, 11, C.faint); self.note:SetPoint("LEFT", self.spans[2], "RIGHT", 14, 0)
  self.tiles = {}
  for i = 1, 6 do self.tiles[i] = UI.Tile(b) end
  self.factHead = UI.Text(b, 15); self.factHead:SetText("Fun facts")
  self.facts = {}
  for i = 1, 6 do self.facts[i] = UI.Tile(b); self.facts[i].big:SetFont(UI.Font(), 18, "") end
end

function page:Layout(w, h)
  self.w = w
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 0, 0); self.scroll:SetSize(w, h)
  self.body:SetWidth(w)
  local inner = w - PAD * 2
  local cols = inner >= 760 and 3 or 2
  local tw = math.floor((inner - GAP * (cols - 1)) / cols)
  local y = -PAD - 26 - GAP
  for i, t in ipairs(self.tiles) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + ((i - 1) % cols) * (tw + GAP), y - math.floor((i - 1) / cols) * (104 + GAP)); t:SetSize(tw, 104)
  end
  y = y - math.ceil(#self.tiles / cols) * (104 + GAP) - 4
  self.factHead:ClearAllPoints(); self.factHead:SetPoint("TOPLEFT", PAD, y - 4)
  y = y - 24 - 10
  for i, t in ipairs(self.facts) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + ((i - 1) % cols) * (tw + GAP), y - math.floor((i - 1) / cols) * (112 + GAP)); t:SetSize(tw, 112)
  end
  self.body:SetHeight(-y + math.ceil(#self.facts / cols) * (112 + GAP) + PAD)
end

function page:Refresh()
  local all, week = ns.Facts()
  local c = span == "week" and week or all
  -- all time: the game's own history where it has one (more than Foxden has counted so far)
  local hist = span == "all" and ns.FactsHistory and ns.FactsHistory() or {}
  local function best(field, counted) local h = hist[field]; return (h and h > (counted or 0)) and h or (counted or 0), h ~= nil and h > (counted or 0) end
  local runs = runFacts(span == "week")
  for _, b in ipairs(self.spans) do
    if b.span == span then b.label:SetTextColor(UI.Accent()) else b.label:SetTextColor(unpack(C.text)) end
  end
  self.note:SetText(span == "week" and "Since Monday. Foxden started counting in 2.3.11."
    or "All time: quests and levels from the game's own records" .. ((ns.FactsHistory and ns.FactsHistory().deaths) and ", plus its Statistics." or "; the rest since 2.3.11."))

  local kills = 0
  for _, n in pairs(c.kills or {}) do kills = kills + n end
  local deaths, questsN, gold, levels, hearths
  kills = best("kills", kills)
  deaths = best("deaths", c.deaths)
  questsN = best("quests", c.quests)
  gold = best("gold", c.gold)
  levels = best("levels", c.levels)
  hearths = best("hearths", c.hearths)
  local tiles = {
    { title = "Kills", big = commas(kills), unit = span == "all" and hist.kills and "creatures" or "for XP", icon = "Interface\\Icons\\Ability_DualWield" },
    { title = "Deaths", big = commas(deaths), body = deaths == 0 and "Not a scratch." or nil, icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" },
    { title = "Quests turned in", big = commas(questsN), body = (c.questXP or 0) > 0 and (commas(c.questXP) .. " XP from quests" .. (span == "all" and " since Foxden counted" or "")) or nil, icon = "Interface\\GossipFrame\\ActiveQuestIcon" },
    { title = "Gold looted", big = commas(math.floor(gold / 10000)), unit = "g", body = (c.items or 0) > 0 and (commas(c.items) .. " items looted") or nil, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    { title = "Levels", big = commas(levels), unit = "gained", body = (span == "all" and "from level 1") or ((c.xp or 0) > 0 and (commas(c.xp) .. " XP") or nil), icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight" },
    { title = "Dungeon runs", big = commas(runs.runs), body = runs.bosses .. (runs.bosses == 1 and " boss" or " bosses") .. ", " .. runs.wipes .. (runs.wipes == 1 and " wipe" or " wipes"), icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
  }
  for i, t in ipairs(self.tiles) do t:Set(tiles[i]) end

  -- fun facts
  local function fact(i, title, big, body, icon) self.facts[i]:Set({ title = title, big = big or "—", body = body, icon = icon }) end
  local mk = top(c.kills, 3)
  fact(1, "Most killed", mk[1] and mk[1][1] or nil,
    mk[1] and ("×" .. commas(mk[1][2]) .. (mk[2] and ("   then " .. mk[2][1] .. " ×" .. commas(mk[2][2])) or "")) or "Nothing yet.",
    "Interface\\Icons\\INV_Sword_04")
  local dt = top(c.diedTo, 1)
  fact(2, "Died fighting most", dt[1] and dt[1][1] or nil,
    dt[1] and ("×" .. dt[1][2] .. ((dt[1][2] > 2) and "  · a rivalry" or "")) or ((c.deaths or 0) > 0 and "Nobody in particular." or "No deaths. Nice."),
    "Interface\\Icons\\Spell_Shadow_DeathScream")
  local dz = top(c.deathZones, 1)
  fact(3, "Most dangerous zone", dz[1] and dz[1][1] or nil,
    dz[1] and (dz[1][2] .. (dz[1][2] == 1 and " death there" or " deaths there")) or "Stay safe out there.",
    "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
  -- favourite ability: no mounts, no hearthstone
  local abilities = {}
  for id, n in pairs(c.casts or {}) do if not ns.FactsIsAbility or ns.FactsIsAbility(id) then abilities[id] = n end end
  local fa = top(abilities, 1)
  local spellName, spellIcon
  if fa[1] then spellName, spellIcon = spellInfo(fa[1][1]) end
  local castText = fa[1] and ("cast " .. commas(fa[1][2]) .. (fa[1][2] == 1 and " time" or " times")) or nil
  local hearthText = hearths > 0 and ("hearthed " .. commas(hearths) .. (hearths == 1 and " time" or " times")) or nil
  fact(4, "Favourite ability", spellName,
    (castText and hearthText and (castText .. "  ·  " .. hearthText)) or castText or hearthText or "Go press some buttons.",
    spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
  local fz = top(c.zones, 1)
  fact(5, "Favourite zone", fz[1] and fz[1][1] or nil, fz[1] and (hours(fz[1][2]) .. " there") or "Out exploring soon?",
    "Interface\\Icons\\INV_Misc_Map_01")
  local nm = top(runs.nemesis, 1)
  if nm[1] then
    fact(6, "Dungeon nemesis", nm[1][1], nm[1][2] .. (nm[1][2] == 1 and " wipe" or " wipes") .. (runs.fastest and ("  · fastest clear " .. UI.Time(runs.fastest.d) .. " " .. runs.fastest.name) or ""),
      "Interface\\Icons\\Spell_Shadow_ShadowWordPain")
  else
    fact(6, "Fastest clear", runs.fastest and UI.Time(runs.fastest.d) or nil, runs.fastest and runs.fastest.name or "No full clears yet.",
      "Interface\\Icons\\INV_Misc_PocketWatch_01")
  end
end

ns.RegisterPage(page)
