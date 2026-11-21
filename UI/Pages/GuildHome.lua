-- Page: Guild overview. Tiles for who's online, the next dungeon night, rares the guild has
-- spotted and your leveling pace, then a small tile for each guildmate online (class, level,
-- zone). Every tile opens its page.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, GAP = 16, 14

local page = { key = "guildoverview", label = "Overview", order = 85 }

local function classIcon(class) return UI.ClassIconSpec(class, true) end
local function dur(s)
  s = math.floor(s or 0)
  if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min" end
  return math.floor(s / 3600) .. " h " .. math.floor((s % 3600) / 60) .. " min"
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
  self.online = UI.Tile(b); self.online.onClick = function() ns.OpenPage("roster") end
  self.night = UI.Tile(b); self.night.onClick = function() ns.OpenPage("journal") end
  self.rares = UI.Tile(b); self.rares.onClick = function() ns.OpenPage("rares") end
  self.level = UI.Tile(b); self.level.onClick = function() ns.OpenPage("leveling") end
  self.head = UI.Text(b, 15); self.head:SetText("Online now")
  self.empty = UI.Text(b, 12, C.dim); self.empty:SetWordWrap(true)
  self.people = {}
end

function page:Layout(w, h)
  self.w, self.h = w, h
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 0, 0); self.scroll:SetSize(w, h)
  self.body:SetWidth(w)
  local inner = w - PAD * 2
  local cols = inner >= 760 and 4 or 2
  local tw = math.floor((inner - GAP * (cols - 1)) / cols)
  for i, t in ipairs({ self.online, self.night, self.rares, self.level }) do
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD + ((i - 1) % cols) * (tw + GAP), -PAD - math.floor((i - 1) / cols) * (118 + GAP))
    t:SetSize(tw, 118)
  end
  local y = -PAD - math.ceil(4 / cols) * (118 + GAP) - 4
  self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", PAD, y - 4)
  self.peopleTop = y - 24 - 10
  self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT", PAD, self.peopleTop); self.empty:SetWidth(inner)
  self.pcols = inner >= 760 and 4 or (inner >= 480 and 3 or 2)
  self.pw = math.floor((inner - GAP * (self.pcols - 1)) / self.pcols)
end

function page:Refresh()
  if ns.RequestRoster then ns.RequestRoster() end
  local roster = ns.db and ns.db.roster
  local members = roster and roster.members or {}
  local online = {}
  for _, m in ipairs(members) do if m.online and not ns.IsMe(m.name) then online[#online + 1] = m end end
  table.sort(online, function(a, b) return (a.level or 0) > (b.level or 0) end)
  local all = 0
  for _, m in ipairs(members) do if m.online then all = all + 1 end end
  local exact = ns.GuildLocations and ns.GuildLocations() or {}
  local sharing = 0
  for _ in pairs(exact) do sharing = sharing + 1 end
  self.online:Set({ title = roster and roster.guild or "Guild", big = tostring(all), unit = "of " .. #members .. " online",
    body = sharing > 0 and (sharing .. " sharing their location on the map") or "Open the world map to see where everyone is.",
    icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" })

  -- the next dungeon night (planned on the website)
  local site = ns.Site and ns.Site()
  local nextUp
  for _, e in ipairs(site and type(site.events) == "table" and site.events or {}) do
    if (e[2] or 0) > GetServerTime() - 3600 and (not nextUp or e[2] < nextUp[2]) then nextUp = e end
  end
  if nextUp then
    self.night:Set({ title = "Next dungeon night", big = date("%a", nextUp[2]), unit = date("%H:%M", nextUp[2]),
      body = nextUp[1] .. "  ·  " .. (nextUp[3] or 0) .. " signed up", icon = "Interface\\Icons\\INV_Misc_PocketWatch_02" })
  else
    self.night:Set({ title = "Next dungeon night", big = "—", body = "None planned. Officers plan them on the guild website.",
      icon = "Interface\\Icons\\INV_Misc_PocketWatch_02" })
  end

  -- rares seen this week (yours and the guild's sightings)
  local seen, now = {}, GetServerTime()
  for _, s in ipairs(ns.db and ns.db.rareSightings or {}) do if (s.at or 0) > now - 7 * 86400 then seen[s.i] = true end end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  self.rares:Set({ title = "Rares spotted", big = tostring(n), unit = "this week",
    body = "Where they spawn and when they may be up again.", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" })

  -- your leveling pace
  local level = UnitLevel("player") or 1
  local hist = ns.LevelHistory and ns.LevelHistory()
  local last = hist and hist.history and hist.history[level]
  if last and last.seconds then
    self.level:Set({ title = "Level " .. level, big = dur(last.seconds):match("^(%S+)"), unit = dur(last.seconds):match("^%S+%s+(.+)$"),
      body = "How long reaching level " .. level .. " took.", icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight" })
  else
    self.level:Set({ title = "Leveling", big = tostring(level), unit = "level",
      body = "Foxden times each level from your next level-up.", icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight" })
  end

  -- a small tile per guildmate online
  for i, m in ipairs(online) do
    local t = self.people[i]
    if not t then
      t = UI.Tile(self.body)
      t.big:SetFont(UI.Font(), 15, "")
      t.onClick = function() ns.OpenPage("roster") end
      self.people[i] = t
    end
    local r, g, bl = UI.ClassColor(m.class)
    t:Set({ title = (m.level and ("Level " .. m.level) or "") , big = UI.ShortName(m.name or ""), bigColor = { r, g, bl, 1 },
      body = (m.zone or "") .. (exact[ns.SenderKey(m.name)] and "  ·  on the map" or ""), icon = classIcon(m.class), iconRound = true })
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD + ((i - 1) % self.pcols) * (self.pw + GAP), self.peopleTop - math.floor((i - 1) / self.pcols) * (84 + GAP))
    t:SetSize(self.pw, 84)
    t:Show()
  end
  for i = #online + 1, #self.people do self.people[i]:Hide() end
  self.empty:SetShown(#online == 0)
  self.empty:SetText(#members == 0 and "Loading the guild roster…" or "Nobody else is online right now.")
  local rows = math.max(1, math.ceil(#online / self.pcols))
  self.body:SetHeight(-self.peopleTop + rows * (84 + GAP) + PAD)
end

ns.RegisterPage(page)
