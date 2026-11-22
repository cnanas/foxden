-- Page: Home ("For you"), as a grid of tiles. What matters for this character right now:
--   you (level, class, XP) and what's ready at your trainer;
--   the dungeons for your level, as picture cards (quests to pick up, the guild's best time);
--   who in the guild is online, which dungeons people want to run, and your recent runs.
-- Every tile opens its page.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, GAP = 16, 14

local page = { key = "overview", label = "For you", order = 10 }

-- Dungeons whose level range fits you; if that's fewer than three, the next ones up.
local function dungeonsFor(level)
  local fit, next = {}, {}
  for id, d in pairs(ns.Dungeons or {}) do
    if not d.raid and d.levels and #d.levels == 2 then
      d._id = id
      if level >= d.levels[1] and level <= d.levels[2] then d._soon = nil; fit[#fit + 1] = d
      elseif d.levels[1] > level and d.levels[1] <= level + 6 then next[#next + 1] = d end
    end
  end
  local byLevel = function(a, b) if a.levels[1] ~= b.levels[1] then return a.levels[1] < b.levels[1] end return a.name < b.name end
  table.sort(fit, byLevel); table.sort(next, byLevel)
  for _, d in ipairs(next) do if #fit < 6 then d._soon = true; fit[#fit + 1] = d end end
  return fit
end

local function classIcon(class) return UI.ClassIconSpec(class, true) end

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

  -- you: name, level and class, XP to the next level
  self.me = UI.Tile(b)
  self.me.onClick = function() ns.OpenPage("leveling") end
  self.me.bar = CreateFrame("StatusBar", nil, self.me)
  self.me.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  self.me.bar:SetHeight(8)
  self.me.barBg = self.me.bar:CreateTexture(nil, "BACKGROUND"); self.me.barBg:SetAllPoints(); self.me.barBg:SetColorTexture(1, 1, 1, 0.08)
  self.me.rested = self.me.bar:CreateTexture(nil, "BORDER"); self.me.rested:SetColorTexture(0.35, 0.55, 1, 0.35)
  self.me.xp = UI.Text(self.me, 11, C.dim)

  self.trainer = UI.Tile(b)
  self.trainer.onClick = function() ns.OpenPage("trainer") end

  self.dungHead = UI.Text(b, 15); self.dungHead:SetText("Dungeons for your level")
  self.dungAll = UI.Button(b, "All dungeons", 110, 24, function() ns.OpenPage("journal") end)
  self.cards = {}

  self.guild = UI.Tile(b)
  self.guild.onClick = function() ns.OpenPage("roster") end
  self.guild.faces = {}
  for i = 1, 8 do
    local t = self.guild:CreateTexture(nil, "ARTWORK"); t:SetSize(22, 22)
    self.guild.faces[i] = t
  end

  self.lfg = UI.Tile(b)
  self.lfg.onClick = function() ns.OpenPage("journal") end

  self.runs = UI.Tile(b)
  self.runs.onClick = function() ns.OpenPage("facts") end
end

function page:Layout(w, h)
  self.w, self.h = w, h
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 0, 0); self.scroll:SetSize(w, h)
  local inner = w - PAD * 2
  self.body:SetWidth(w)
  local y = -PAD

  -- row 1: you (two thirds), trainer (one third)
  local rowH = 132
  local meW = math.floor((inner - GAP) * 0.62)
  self.me:ClearAllPoints(); self.me:SetPoint("TOPLEFT", PAD, y); self.me:SetSize(meW, rowH)
  self.meW = meW
  self.me.bar:ClearAllPoints(); self.me.bar:SetPoint("BOTTOMLEFT", 16, 30); self.me.bar:SetPoint("BOTTOMRIGHT", -16, 30)
  self.me.xp:ClearAllPoints(); self.me.xp:SetPoint("BOTTOMLEFT", 16, 12)
  self.trainer:ClearAllPoints(); self.trainer:SetPoint("TOPLEFT", PAD + meW + GAP, y); self.trainer:SetSize(inner - meW - GAP, rowH)
  y = y - rowH - GAP - 4

  -- row 2: dungeons for your level, as picture cards
  self.dungHead:ClearAllPoints(); self.dungHead:SetPoint("TOPLEFT", PAD, y - 4)
  self.dungAll:ClearAllPoints(); self.dungAll:SetPoint("TOPRIGHT", self.body, "TOPLEFT", PAD + inner, y)
  y = y - 24 - 10
  self.cardCols = inner >= 760 and 3 or 2
  self.cardW = math.floor((inner - GAP * (self.cardCols - 1)) / self.cardCols)
  self.cardH = math.max(96, math.min(128, math.floor(self.cardW * 0.42)))
  self.cardTop = y
  -- (cards are placed in Refresh: their number depends on your level)
  local cardRows = 2
  y = y - cardRows * (self.cardH + GAP) - 4

  -- row 3: guild, looking for group, recent runs
  local tileW = math.floor((inner - GAP * 2) / 3)
  local tileH = math.max(150, h + y - PAD)
  for i, t in ipairs({ self.guild, self.lfg, self.runs }) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + GAP), y); t:SetSize(tileW, math.min(tileH, 210))
  end
  self.rowsEnd = y - math.min(tileH, 210) - PAD
  self.body:SetHeight(-self.rowsEnd)
end

function page:Refresh()
  local level = UnitLevel("player") or 1
  local _, class = UnitClass("player")

  UI.Guard("Home (you)", function()
    -- you
    local cr, cg, cb = UI.ClassColor(class)
    local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    self.me:Set({ title = "Level " .. level .. " " .. (UI.ClassName and UI.ClassName(class) or ""), big = UnitName("player") or "You",
      bigColor = { cr, cg, cb, 1 }, icon = classIcon(class), iconRound = true })
    local maxed = level >= maxLevel
    self.me.bar:SetShown(not maxed)
    self.me.bar:SetMinMaxValues(0, math.max(1, xpMax)); self.me.bar:SetValue(xp)
    self.me.bar:SetStatusBarColor(cr, cg, cb, 0.9)
    local w = (self.meW or 0) - 32 -- the bar's width from the layout (GetWidth lags a resize by a frame)
    local restW = math.min(w * (1 - xp / math.max(1, xpMax)), w * (rest or 0) / math.max(1, xpMax))
    self.me.rested:ClearAllPoints(); self.me.rested:SetPoint("TOPLEFT", self.me.bar, "TOPLEFT", w * xp / math.max(1, xpMax), 0)
    self.me.rested:SetSize(math.max(0.01, restW), 8); self.me.rested:SetShown(not maxed and (rest or 0) > 0)
    self.me.xp:SetText(maxed and "Max level" or string.format("%s / %s XP  ·  %d%%%s", ns.Commas and ns.Commas(xp) or xp,
      ns.Commas and ns.Commas(xpMax) or xpMax, math.floor(xp / math.max(1, xpMax) * 100), (rest or 0) > 0 and "  ·  rested" or ""))
  end)

  UI.Guard("Home (trainer)", function()
    -- trainer
    local abilities = ns.ClassAbilities and ns.ClassAbilities()
    local tr = { title = "At your trainer", icon = "Interface\\Icons\\INV_Misc_Book_11" }
    if not abilities then
      tr.big, tr.body = "—", "Visit your class trainer once and Foxden keeps the list."
    else
      local ready, cost, soon = 0, 0, nil
      for _, s in ipairs(abilities) do
        if s.status == "ready" then ready = ready + 1; cost = cost + (s.cost or 0)
        elseif s.status == "soon" and not soon then soon = s end
      end
      if ready > 0 then
        tr.big, tr.unit, tr.body = tostring(ready), ready == 1 and "ability ready" or "abilities ready", ns.Money(cost) .. " to learn them all"
      else
        tr.big, tr.unit = "0", "ready"
        tr.body = soon and ("Next: " .. soon.name .. " at level " .. soon.level) or "All caught up."
      end
    end
    self.trainer:Set(tr)
  end)

  UI.Guard("Home (dungeons)", function()
    -- dungeons for your level
    local stats = {}
    for _, s in ipairs(ns.Stats.Dungeons()) do stats[ns.Slug(s.name)] = s end
    local list = dungeonsFor(level)
    local shown = math.min(#list, self.cardCols * 2)
    for i = 1, shown do
      local d = list[i]
      local c = self.cards[i]
      if not c then
        c = UI.ArtCard(self.body)
        c.onClick = function(card) ns.OpenPage("journal", { dungeon = card.dname }) end
        self.cards[i] = c
      end
      c.dname = d.name
      local qp = ns.QuestProgress and ns.QuestProgress(d.name)
      local tag, tagDone
      if qp and qp.total > 0 then
        local open = #qp.missing
        if open > 0 then tag = open .. (open == 1 and " quest to pick up" or " quests to pick up")
        elseif qp.done == qp.total then tag, tagDone = "quests done", true end
      end
      local st = stats[ns.Slug(d.name)]
      local right = st and st.best and (#st.runs .. (#st.runs == 1 and " run · best " or " runs · best ") .. UI.Time(st.best.duration))
        or (d._soon and ("from level " .. d.levels[1])) or "not run yet"
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", PAD + ((i - 1) % self.cardCols) * (self.cardW + GAP), self.cardTop - math.floor((i - 1) / self.cardCols) * (self.cardH + GAP))
      c:SetSize(self.cardW, self.cardH)
      c:Set({ art = ns.DungeonArt and ns.DungeonArt[d._id], title = d.name, tag = tag, tagDone = tagDone,
        bottomLeft = "LV " .. d.levels[1] .. "-" .. d.levels[2], bottomRight = right, dim = d._soon })
      c:Show()
    end
    for i = shown + 1, #self.cards do self.cards[i]:Hide() end
  end)

  UI.Guard("Home (guild)", function()
    -- guild
    local members = ns.db and ns.db.roster and ns.db.roster.members or {}
    local online, near, faces = 0, {}, {}
    for _, m in ipairs(members) do
      if m.online then
        online = online + 1
        if not ns.IsMe(m.name) then
          faces[#faces + 1] = m
          if m.level and math.abs(m.level - level) <= 4 then near[#near + 1] = UI.ShortName(m.name or "") .. " " .. m.level end
        end
      end
    end
    local g = { title = "Guild online" }
    if #members == 0 then
      g.big, g.body = "—", (IsInGuild and IsInGuild()) and "Open the Roster to load who's online." or "Not in a guild on this character."
    else
      g.big, g.unit = tostring(online), "of " .. #members
      g.body = #near > 0 and ("Near your level: " .. table.concat(near, ", ")) or "Nobody near your level right now."
    end
    self.guild:Set(g)
    for i, t in ipairs(self.guild.faces) do
      local m = faces[i]
      local ic = m and classIcon(m.class)
      if ic then
        t:SetTexture(ic[1]); t:SetTexCoord(ic[2], ic[3], ic[4], ic[5])
        t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 26, 14); t:Show()
      else t:Hide() end
    end
  end)

  UI.Guard("Home (looking for group)", function()
    -- looking for group (and the next dungeon night)
    local wanted = {}
    for _, d in pairs(ns.Dungeons or {}) do
      local seekers = ns.LfgFor and ns.LfgFor(ns.Slug(d.name)) or {}
      if #seekers > 0 then wanted[#wanted + 1] = { name = d.name, n = #seekers } end
    end
    table.sort(wanted, function(a, b2) if a.n ~= b2.n then return a.n > b2.n end return a.name < b2.name end)
    local lf = { title = "Looking for group", icon = "Interface\\Icons\\Ability_Warrior_RallyingCry" }
    if #wanted == 0 then
      lf.big, lf.body = "0", "Open a dungeon and click \"I want to run this\"."
    else
      lf.big, lf.unit = tostring(#wanted), #wanted == 1 and "dungeon wanted" or "dungeons wanted"
      local lines = {}
      for i = 1, math.min(3, #wanted) do lines[#lines + 1] = "|cffe6e8ee" .. wanted[i].name .. "|r  " .. wanted[i].n end
      lf.body = table.concat(lines, "\n")
    end
    local site = ns.Site()
    local nextUp
    for _, e in ipairs(site and type(site.events) == "table" and site.events or {}) do
      if (e[2] or 0) > GetServerTime() - 3600 and (not nextUp or e[2] < nextUp[2]) then nextUp = e end
    end
    if nextUp then lf.body = (lf.body or "") .. "\n\n|cffe6e8eeDungeon night:|r " .. nextUp[1] .. ", " .. date("%a %H:%M", nextUp[2]) end
    self.lfg:Set(lf)
  end)

  UI.Guard("Home (this week)", function()
    -- this week: your recap (Modules/Facts.lua), with your runs
    local w = {}
    if ns.Facts then local _, wk2 = ns.Facts(); w = wk2 or {} end
    local weekRuns, wk = 0, ns.FactsWeekKey and ns.FactsWeekKey()
    for _, r in ipairs(ns.GetRuns and ns.GetRuns() or {}) do if wk and r.endTime and ns.FactsWeekKey(r.endTime) == wk then weekRuns = weekRuns + 1 end end
    local kills, best, bestN = 0, nil, 0
    for name, n in pairs(w.kills or {}) do kills = kills + n; if n > bestN then best, bestN = name, n end end
    local bits = {}
    if (w.levels or 0) > 0 then bits[#bits + 1] = w.levels .. (w.levels == 1 and " level" or " levels") end
    if (w.quests or 0) > 0 then bits[#bits + 1] = w.quests .. (w.quests == 1 and " quest" or " quests") end
    if kills > 0 then bits[#bits + 1] = (ns.Commas and ns.Commas(kills) or kills) .. " kills" end
    bits[#bits + 1] = (w.deaths or 0) .. ((w.deaths or 0) == 1 and " death" or " deaths")
    local body = table.concat(bits, "  ·  ")
    if best then body = body .. "\nMost killed: |cffe6e8ee" .. best .. "|r ×" .. bestN end
    self.runs:Set({ title = "This week", big = tostring(weekRuns), unit = weekRuns == 1 and "dungeon run" or "dungeon runs",
      body = body, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" })
  end)
end

ns.RegisterPage(page)
