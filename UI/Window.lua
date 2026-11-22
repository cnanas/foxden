-- Foxden: the dashboard window (/fox). Resizable. Four places in the sidebar (Home,
-- Dungeons, Crafting, Guild), each with a few tabs across the top; a search box in the
-- header finds dungeons, bosses, quests, loot and recipes. Pages live in UI/Pages/*.lua
-- and register with ns.RegisterPage; the run detail tabs (Overview, Fights, Map) are
-- views in Views/*.lua registered with ns.RegisterView and shown on the runs page.

local ADDON, ns = ...
local UI = ns.UI
local C = UI.C

local HEADER_H, SIDE_W, PAD, TABS_H = 50, 200, 16, 40
-- Narrower than this, the sidebar becomes a slim icon rail and the page tabs come back on top.
local RAIL_W, COMPACT_AT, CHAR_H = 60, 900, 186
local MIN_W, MIN_H, MAX_W, MAX_H = 720, 520, 1700, 1100

-- ---- registries --------------------------------------------------------------

ns.views = {}
function ns.RegisterView(view)
  ns.views[#ns.views + 1] = view
  table.sort(ns.views, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- A page: { key, label, section = "log"|"craft", order, Build(self, frame), Layout(self, w, h), Refresh(self, arg) }
ns.pages = {}
function ns.RegisterPage(page)
  ns.pages[#ns.pages + 1] = page
  table.sort(ns.pages, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- The sidebar: four places, each a set of pages shown as tabs.
local NAV = {
  { key = "home", label = "Home", icon = "Interface\\Icons\\Spell_Nature_SpiritWolf", pages = { "overview", "facts", "trainer", "wishlist", "notes" } },
  { key = "dungeons", label = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", pages = { "journal", "runs" } },
  { key = "crafting", label = "Crafting", icon = "Interface\\Icons\\Trade_BlackSmithing", pages = { "craftoverview", "recipes", "planner", "crafters", "orders" } },
  { key = "guild", label = "Guild", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", pages = { "guildoverview", "roster", "rares", "leveling", "players" } },
  { key = "questing", label = "Quests", icon = "Interface\\Icons\\INV_Misc_Book_08", pages = { "questlog", "quests" } },
}
local function groupOf(key)
  for _, g in ipairs(NAV) do
    if g.key == key then return g, g.pages[1] end
    for _, p in ipairs(g.pages) do if p == key then return g, p end end
  end
end

-- ---- helpers pages and views share -------------------------------------------

function ns.RunDuration(entry)
  if entry.live then return ns.RunElapsed(entry.run) end
  return entry.run.duration or 0
end

function ns.ClassLookup(run)
  local map = {}
  for _, m in ipairs(run.party or {}) do map[m.name] = m.class end
  return function(name) return map[UI.ShortName(name)] end
end

function ns.Money(copper)
  if not copper or copper < 0 then return "—" end
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = "|cffe8c35a" .. g .. "g|r" end
  if s > 0 then parts[#parts + 1] = "|cffc7ccd4" .. s .. "s|r" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = "|cffc47a4a" .. c .. "c|r" end
  return table.concat(parts, " ")
end

function ns.MoneyPlain(copper)
  copper = math.floor(copper or 0)
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

-- "5 min ago", "3 h ago", "Nov 12"
function ns.Ago(t)
  local s = math.max(0, GetServerTime() - (t or 0))
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  return date("%b %d", t)
end

-- ---- window ------------------------------------------------------------------

local W, current, ticker, layoutTimer
local navButtons = {}
local subButtons = {}
local compact = false
local navGroup, navPage -- what the sidebar shows as open

local function savePlace()
  local point, _, rel, x, y = W:GetPoint()
  ns.settings.window = { w = math.floor(W:GetWidth()), h = math.floor(W:GetHeight()), point = point, rel = rel, x = x, y = y }
end

local applyMode -- below
local function layout()
  layoutTimer = nil
  if applyMode then applyMode() end
  if not current or not current.frame then return end
  local w, h = W.content:GetWidth(), W.content:GetHeight()
  if current.Layout then
    local ok, err = pcall(current.Layout, current, w, h)
    if not ok then geterrorhandler()("Foxden page " .. current.key .. ": " .. tostring(err)) end
  end
end

local function refresh(arg)
  if not current or not current.frame then return end
  local ok, err = pcall(current.Refresh, current, arg)
  if not ok then geterrorhandler()("Foxden page " .. current.key .. ": " .. tostring(err)) end
end

local tabButtons = {}
local function drawTabs(group, key)
  local r, g, b = UI.Accent()
  local x = PAD - 4
  for i, pkey in ipairs(group.pages) do
    local t = tabButtons[i]
    if not t then
      t = CreateFrame("Button", nil, W.tabs)
      t.text = UI.Text(t, 13, C.dim, "CENTER"); t.text:SetPoint("CENTER")
      t.under = t:CreateTexture(nil, "ARTWORK"); t.under:SetPoint("BOTTOMLEFT", 8, 0); t.under:SetPoint("BOTTOMRIGHT", -8, 0); t.under:SetHeight(2)
      t:SetScript("OnClick", function(self) ns.OpenPage(self.key) end)
      t:SetScript("OnEnter", function(self) if not self.on then self.text:SetTextColor(unpack(C.text)) end end)
      t:SetScript("OnLeave", function(self) if not self.on then self.text:SetTextColor(unpack(C.dim)) end end)
      tabButtons[i] = t
    end
    local page
    for _, p in ipairs(ns.pages) do if p.key == pkey then page = p end end
    t.key, t.on = pkey, pkey == key
    t.text:SetText(page and page.label or pkey)
    t:SetSize(math.floor((t.text:GetStringWidth() or 60) + 0.5) + 28, TABS_H)
    t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", x, 0)
    x = x + t:GetWidth()
    t.under:SetShown(t.on); t.under:SetColorTexture(r, g, b, 1)
    t.text:SetTextColor(unpack(t.on and C.text or C.dim))
    t:SetShown(page ~= nil)
  end
  for i = #group.pages + 1, #tabButtons do tabButtons[i]:Hide() end
end

-- Settings, inside the window: the same page as Settings > AddOns > Foxden, borrowed from
-- the game's panel (it takes it back when you open it there). The game's panel opens on
-- the same layer as this window, so it could end up hidden behind it.
local settingsHost
function ns.ShowSettingsInWindow()
  if not W then ns.ToggleWindow() end
  if not W:IsShown() then W:Show() end
  local root = ns.SettingsRoot
  if not root then return end
  if current and current.frame then current.frame:Hide() end
  settingsHost = settingsHost or CreateFrame("Frame", nil, W.content)
  settingsHost:SetAllPoints(W.content)
  root:SetParent(settingsHost); root:ClearAllPoints(); root:SetAllPoints(settingsHost)
  settingsHost:Show(); root:Show()
  navGroup, navPage = nil, nil
  if ns.DrawNav then UI.Guard("the sidebar", ns.DrawNav) end
  if ns.RefreshSettings then ns.RefreshSettings() end
end
function ns.InWindowSettings() return settingsHost ~= nil and settingsHost:IsShown() end

-- key: a page ("journal") or a place ("dungeons": opens the tab you last used there).
function ns.OpenPage(key, arg)
  if not W then ns.ToggleWindow() end
  if not W:IsShown() then W:Show() end
  if key == "shop" or key == "costs" then key = "recipes" end -- older names
  local group, pkey = groupOf(key)
  if not group then return end
  ns.settings.tabs = ns.settings.tabs or {}
  if key == group.key then
    -- the tab you used last in this section, if it's still one of its tabs
    local last = ns.settings.tabs[group.key]
    for _, p in ipairs(group.pages) do if p == last then pkey = last end end
  end
  local page
  for _, p in ipairs(ns.pages) do if p.key == pkey then page = p end end
  if not page then return end
  if current and current ~= page and current.frame then current.frame:Hide() end
  if settingsHost then settingsHost:Hide() end
  if W.tabTitle then W.tabTitle:Hide() end
  current = page
  if not page.frame then
    page.frame = CreateFrame("Frame", nil, W.content)
    page.frame:SetAllPoints()
    local ok, err = pcall(page.Build, page, page.frame)
    if not ok then geterrorhandler()("Foxden page " .. pkey .. ": " .. tostring(err)) end
  end
  page.frame:Show()
  ns.settings.page = pkey
  ns.settings.tabs[group.key] = pkey
  navGroup, navPage = group, pkey
  if ns.DrawNav then UI.Guard("the sidebar", ns.DrawNav) end
  if ns.SetSectionArt then UI.Guard("the window look", ns.SetSectionArt, group.key) end
  layout()
  refresh(arg)
end

local function build()
  W = CreateFrame("Frame", "FoxdenFrame", UIParent)
  local saved = ns.settings.window
  W:SetSize(saved and saved.w or 1000, saved and saved.h or 640)
  if saved and saved.point then W:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0) else W:SetPoint("CENTER") end
  W:SetFrameStrata("HIGH")
  W:SetToplevel(true)
  W:SetClampedToScreen(true)
  W:SetMovable(true)
  W:SetResizable(true)
  if W.SetResizeBounds then W:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif W.SetMinResize then W:SetMinResize(MIN_W, MIN_H); W:SetMaxResize(MAX_W, MAX_H) end
  W:EnableMouse(true)
  W:Hide()
  UI.Fill(W, C.bg)
  UI.Border(W, { 1, 1, 1, 0.10 })
  tinsert(UISpecialFrames, "FoxdenFrame") -- Escape closes it

  -- header (drag to move)
  local header = CreateFrame("Frame", nil, W)
  header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(HEADER_H)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() W:StartMoving() end)
  header:SetScript("OnDragStop", function() W:StopMovingOrSizing(); savePlace() end)
  local accent = header:CreateTexture(nil, "ARTWORK")
  accent:SetSize(3, 18); accent:SetPoint("LEFT", PAD, 0)
  UI.Accented(accent)
  local title = UI.Text(header, 16); title:SetPoint("LEFT", accent, "RIGHT", 10, 0); title:SetText("Foxden")
  local close = UI.CloseButton(header, function() W:Hide() end)
  close:SetPoint("RIGHT", -12, 0)
  local settings = UI.Button(header, "Settings", 80, 26, function()
    if ns.InWindowSettings() then ns.OpenPage(current and current.key or "overview") else ns.ShowSettingsInWindow() end
  end)
  settings:SetPoint("RIGHT", close, "LEFT", -10, 0)
  -- dark / light
  local themeBtn = UI.Button(header, "", 64, 26, function(b)
    ns.settings.theme = (ns.settings.theme == "light") and "dark" or "light"
    UI.ApplyTheme(ns.settings.theme)
  end)
  themeBtn:SetPoint("RIGHT", settings, "LEFT", -8, 0)
  UI.OnTheme(function() themeBtn.label:SetText(UI.IsLight() and "Dark" or "Light") end)
  themeBtn:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Switch to the " .. (UI.IsLight() and "dark" or "light") .. " theme"); GameTooltip:Show() end)
  themeBtn:HookScript("OnLeave", GameTooltip_Hide)
  local sync = UI.Button(header, "Send now", 84, 26, function() ns.Sync() end, "primary")
  sync:SetPoint("RIGHT", themeBtn, "LEFT", -8, 0)
  sync:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Send now")
    GameTooltip:AddLine("Everything goes to the guild website and Discord by itself when you log out. This sends it now: your screen reloads for a second, the companion app sends your runs, notes and crafts, and brings back fresh prices, quests and loot.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  sync:HookScript("OnLeave", GameTooltip_Hide)
  W.siteAge = UI.Text(header, 11, C.faint, "RIGHT"); W.siteAge:SetPoint("RIGHT", sync, "LEFT", -14, 0)
  if ns.BuildSearch then ns.BuildSearch(W, header, SIDE_W + PAD) end
  local hl = header:CreateTexture(nil, "BORDER")
  UI.Paint(hl, C.line); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); hl:SetHeight(1)

  -- sidebar: you at the top, the places (the open one lists its pages), guild online at the bottom
  local side = CreateFrame("Frame", nil, W)
  side:SetPoint("TOPLEFT", 0, -HEADER_H - 1); side:SetPoint("BOTTOMLEFT", 0, 1); side:SetWidth(SIDE_W)
  UI.Fill(side, { 0, 0, 0, 0.18 })
  W.side = side
  local div = W:CreateTexture(nil, "BORDER")
  UI.Paint(div, C.line); div:SetPoint("TOPLEFT", side, "TOPRIGHT"); div:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT"); div:SetWidth(1)

  -- you
  local me = CreateFrame("Button", nil, side)
  me:SetPoint("TOPLEFT", 0, 0); me:SetPoint("TOPRIGHT", 0, 0); me:SetHeight(CHAR_H)
  UI.Fill(me, C.hover, "HIGHLIGHT")
  me.icon = me:CreateTexture(nil, "ARTWORK"); me.icon:SetSize(38, 38)
  me.name = UI.Text(me, 15); me.sub = UI.Text(me, 11, C.dim)
  me.bar = CreateFrame("StatusBar", nil, me); me.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); me.bar:SetHeight(4)
  -- stats: two columns, three rows
  me.stats = {}
  for i = 1, 6 do
    local cell = { label = UI.Text(me, 10, C.faint), value = UI.Text(me, 13, C.text) }
    me.stats[i] = cell
  end
  me.barBg = me.bar:CreateTexture(nil, "BACKGROUND"); me.barBg:SetAllPoints(); me.barBg:SetColorTexture(1, 1, 1, 0.08)
  me:SetScript("OnClick", function() ns.OpenPage("leveling") end)
  me:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(UnitName("player") or "")
    local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 1
    GameTooltip:AddLine(string.format("%s / %s XP (%d%%)", ns.Commas and ns.Commas(xp) or xp, ns.Commas and ns.Commas(mx) or mx, math.floor(xp / math.max(1, mx) * 100)), 1, 1, 1)
    local rest = GetXPExhaustion and GetXPExhaustion()
    if rest and rest > 0 then GameTooltip:AddLine((ns.Commas and ns.Commas(rest) or rest) .. " rested", 0.45, 0.65, 1) end
    GameTooltip:AddLine("Click: your leveling", 0.55, 0.85, 0.55)
    GameTooltip:Show()
  end)
  me:SetScript("OnLeave", GameTooltip_Hide)
  local meLine = side:CreateTexture(nil, "BORDER"); UI.Paint(meLine, C.line); meLine:SetHeight(1)
  meLine:SetPoint("TOPLEFT", me, "BOTTOMLEFT", 12, 0); meLine:SetPoint("TOPRIGHT", me, "BOTTOMRIGHT", -12, 0)
  W.me = me
  function ns.RefreshSidebarMe()
    local _, class = UnitClass("player")
    local r, g, b = UI.ClassColor(class)
    if not UI.SetClassIcon(me.icon, class, true) then me.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); me.icon:SetTexCoord(0, 1, 0, 1) end
    me.name:SetText(UnitName("player") or ""); me.name:SetTextColor(r, g, b)
    local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 1
    local maxed = GetMaxPlayerLevel and (UnitLevel("player") or 0) >= GetMaxPlayerLevel()
    me.bar:SetMinMaxValues(0, math.max(1, mx)); me.bar:SetValue(maxed and mx or xp); me.bar:SetStatusBarColor(r, g, b, 0.9)
    me.sub:SetText("Level " .. (UnitLevel("player") or "?") .. " " .. (UI.ClassName and UI.ClassName(class) or "")
      .. (maxed and "" or ("  ·  " .. math.floor(xp / math.max(1, mx) * 100) .. "%")))

    -- stats
    local function span(s)
      if not s then return "—" end
      s = math.floor(s)
      local d, h, m = math.floor(s / 86400), math.floor((s % 86400) / 3600), math.floor((s % 3600) / 60)
      if d > 0 then return d .. "d " .. h .. "h" end
      if h > 0 then return h .. "h " .. m .. "m" end
      return m .. "m"
    end
    local total, thisLevel = nil, nil
    if ns.Played then total, thisLevel = ns.Played() end
    local money = GetMoney and GetMoney() or 0
    local gold = math.floor(money / 10000)
    -- average item level of what you're wearing (shirt and tabard left out)
    local sum, n = 0, 0
    for slot = 1, 18 do
      if slot ~= 4 then
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if link then
          local lvl = (C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link))
            or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or select(4, GetItemInfo(link))
          if type(lvl) == "number" and lvl > 0 then sum, n = sum + lvl, n + 1 end
        end
      end
    end
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    local runs = ns.GetRuns and #ns.GetRuns() or 0
    local cells = {
      { "Played", span(total) },
      { "This level", maxed and "max" or span(thisLevel) },
      { "Gold", (ns.Commas and ns.Commas(gold) or gold) .. "g" },
      { "Item level", n > 0 and string.format("%d", math.floor(sum / n + 0.5)) or "—" },
      { "Rested", maxed and "—" or (math.floor((rest or 0) / math.max(1, mx) * 100) .. "%") },
      { "Runs", tostring(runs) },
    }
    for i, cell in ipairs(me.stats) do
      cell.label:SetText(cells[i][1]); cell.value:SetText(cells[i][2])
    end
    if (rest or 0) > 0 and not maxed then me.stats[5].value:SetTextColor(0.45, 0.65, 1) else me.stats[5].value:SetTextColor(unpack(C.text)) end
    me.stats[3].value:SetTextColor(0.91, 0.76, 0.35)
  end

  -- places
  for _, g in ipairs(NAV) do
    local b = CreateFrame("Button", nil, side)
    b.key = g.key
    b:SetHeight(36)
    b.sel = UI.Fill(b, C.raised); b.sel:Hide()
    b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(2); b.bar:Hide()
    local hover = UI.Fill(b, C.hover, "ARTWORK"); hover:Hide()
    b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(20, 20)
    b.icon:SetTexture(g.icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = UI.Text(b, 14, C.dim); b.text:SetText(g.label)
    b:SetScript("OnEnter", function(self)
      hover:Show()
      if compact then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(g.label); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() hover:Hide(); GameTooltip:Hide() end)
    b:SetScript("OnClick", function() ns.OpenPage(g.key) end)
    navButtons[#navButtons + 1] = b
  end

  -- guild online, at the bottom
  local foot = CreateFrame("Button", nil, side)
  foot:SetPoint("BOTTOMLEFT", 0, 0); foot:SetPoint("BOTTOMRIGHT", 0, 0); foot:SetHeight(52)
  UI.Fill(foot, C.hover, "HIGHLIGHT")
  local footLine = side:CreateTexture(nil, "BORDER"); UI.Paint(footLine, C.line); footLine:SetHeight(1)
  footLine:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 12, 0); footLine:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -12, 0)
  foot.dot = foot:CreateTexture(nil, "ARTWORK"); foot.dot:SetSize(8, 8); foot.dot:SetColorTexture(0.30, 0.78, 0.56, 1)
  pcall(foot.dot.SetMask, foot.dot, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
  foot.text = UI.Text(foot, 12, C.text); foot.ver = UI.Text(foot, 10, C.faint)
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  foot.ver:SetText("Foxden " .. ((meta and meta("Foxden", "Version")) or ""))
  foot:SetScript("OnClick", function() ns.OpenPage("roster") end)
  foot:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Guild roster"); GameTooltip:Show() end)
  foot:SetScript("OnLeave", GameTooltip_Hide)
  W.foot = foot
  function ns.RefreshSidebarFoot()
    local members = ns.db and ns.db.roster and ns.db.roster.members or {}
    local online = 0
    for _, m in ipairs(members) do if m.online then online = online + 1 end end
    foot.text:SetText(#members > 0 and (compact and tostring(online) or (online .. " of " .. #members .. " online")) or (compact and "" or "Guild"))
  end

  -- draws the sidebar for the open place and page (and the tab row, in the narrow layout)
  function ns.DrawNav()
    local w = compact and RAIL_W or SIDE_W
    side:SetWidth(w)
    -- you
    me:SetHeight(compact and 60 or CHAR_H)
    me.icon:ClearAllPoints()
    if compact then me.icon:SetPoint("CENTER", 0, 0) else me.icon:SetPoint("TOPLEFT", 16, -16) end
    me.name:SetShown(not compact); me.sub:SetShown(not compact)
    me.name:ClearAllPoints(); me.name:SetPoint("TOPLEFT", me.icon, "TOPRIGHT", 10, -1); me.name:SetPoint("RIGHT", me, "RIGHT", -10, 0)
    me.sub:ClearAllPoints(); me.sub:SetPoint("TOPLEFT", me.name, "BOTTOMLEFT", 0, -4)
    me.bar:ClearAllPoints()
    if compact then me.bar:SetPoint("BOTTOMLEFT", 10, 4); me.bar:SetPoint("BOTTOMRIGHT", -10, 4)
    else me.bar:SetPoint("TOPLEFT", 16, -64); me.bar:SetPoint("TOPRIGHT", -16, -64) end
    local colW = (SIDE_W - 32) / 2
    for i, cell in ipairs(me.stats) do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      cell.label:ClearAllPoints(); cell.value:ClearAllPoints()
      cell.label:SetPoint("TOPLEFT", me, "TOPLEFT", 16 + col * colW, -80 - row * 34)
      cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -3)
      cell.label:SetShown(not compact); cell.value:SetShown(not compact)
    end
    UI.Guard("the sidebar (you)", ns.RefreshSidebarMe)

    -- places, the open one with its pages under it
    local r, g, b = UI.Accent()
    local y = -(compact and 60 or CHAR_H) - 10
    local used = 0
    for i, btn in ipairs(navButtons) do
      local grp = NAV[i]
      local on = navGroup ~= nil and grp.key == navGroup.key
      btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", 8, y); btn:SetPoint("RIGHT", side, "RIGHT", -8, 0)
      btn.icon:ClearAllPoints()
      if compact then btn.icon:SetPoint("CENTER") else btn.icon:SetPoint("LEFT", 12, 0) end
      btn.text:ClearAllPoints(); btn.text:SetPoint("LEFT", 42, 0); btn.text:SetShown(not compact)
      btn.sel:SetShown(on); btn.bar:SetShown(on)
      btn.icon:SetDesaturated(not on); btn.icon:SetAlpha(on and 1 or 0.7)
      if on then btn.bar:SetColorTexture(r, g, b, 1); btn.text:SetTextColor(unpack(C.text)) else btn.text:SetTextColor(unpack(C.dim)) end
      y = y - 38
      if on and not compact then
        for _, pkey in ipairs(grp.pages) do
          local page
          for _, p in ipairs(ns.pages) do if p.key == pkey then page = p end end
          if page then
            used = used + 1
            local sb = subButtons[used]
            if not sb then
              sb = CreateFrame("Button", nil, side)
              sb:SetHeight(26)
              sb.hl = UI.Fill(sb, C.hover, "HIGHLIGHT")
              sb.dot = sb:CreateTexture(nil, "ARTWORK"); sb.dot:SetSize(4, 4); sb.dot:SetPoint("LEFT", 0, 0)
              sb.text = UI.Text(sb, 12, C.dim); sb.text:SetPoint("LEFT", 12, 0)
              sb:SetScript("OnClick", function(self) ns.OpenPage(self.key) end)
              subButtons[used] = sb
            end
            sb.key = pkey
            local cur = pkey == navPage
            sb:ClearAllPoints(); sb:SetPoint("TOPLEFT", 40, y); sb:SetPoint("RIGHT", side, "RIGHT", -8, 0)
            sb.text:SetText(page.label)
            if cur then sb.text:SetTextColor(r, g, b); sb.dot:SetColorTexture(r, g, b, 1); sb.dot:Show()
            else sb.text:SetTextColor(unpack(C.dim)); sb.dot:Hide() end
            sb:Show()
            y = y - 26
          end
        end
        y = y - 8
      end
    end
    for i = used + 1, #subButtons do subButtons[i]:Hide() end

    -- guild online
    foot:SetHeight(compact and 40 or 52)
    foot.dot:ClearAllPoints(); foot.text:ClearAllPoints(); foot.ver:ClearAllPoints()
    if compact then
      foot.dot:SetPoint("TOP", -8, -12); foot.text:SetPoint("LEFT", foot.dot, "RIGHT", 4, 0); foot.ver:Hide()
    else
      foot.dot:SetPoint("TOPLEFT", 18, -14); foot.text:SetPoint("LEFT", foot.dot, "RIGHT", 8, 0)
      foot.ver:SetPoint("TOPLEFT", 16, -32); foot.ver:Show()
    end
    UI.Guard("the sidebar (guild online)", ns.RefreshSidebarFoot)

    -- the tab row: only in the narrow layout (the sidebar lists the pages otherwise)
    W.tabs:SetHeight(compact and TABS_H or 1)
    if compact and navGroup then drawTabs(navGroup, navPage) else drawTabs({ pages = {} }, nil) end
    if W.tabTitle then W.tabTitle:Hide() end
  end

  -- narrow window: the slim layout
  applyMode = function()
    local want = (W:GetWidth() or 1000) < COMPACT_AT
    if want ~= compact then compact = want; UI.Guard("the sidebar", ns.DrawNav) end
  end
  side:RegisterEvent("PLAYER_XP_UPDATE"); side:RegisterEvent("PLAYER_LEVEL_UP"); side:RegisterEvent("GUILD_ROSTER_UPDATE")
  side:RegisterEvent("PLAYER_MONEY"); side:RegisterEvent("PLAYER_EQUIPMENT_CHANGED"); side:RegisterEvent("UPDATE_EXHAUSTION")
  -- played time counts on: once a minute while the window is open
  C_Timer.NewTicker(60, function() if W:IsShown() then UI.Guard("the sidebar (you)", ns.RefreshSidebarMe) end end)
  side:SetScript("OnEvent", function(_, ev)
    if not W:IsShown() then return end
    if ev == "GUILD_ROSTER_UPDATE" then C_Timer.After(1.2, function() UI.Guard("the sidebar (guild online)", ns.RefreshSidebarFoot) end)
    else UI.Guard("the sidebar (you)", ns.RefreshSidebarMe) end
  end)

  -- content
  W.tabs = CreateFrame("Frame", nil, W)
  W.tabs:SetPoint("TOPLEFT", side, "TOPRIGHT", 1, 0); W.tabs:SetPoint("RIGHT", W, "RIGHT", 0, 0); W.tabs:SetHeight(TABS_H)
  local tl = W.tabs:CreateTexture(nil, "BORDER")
  UI.Paint(tl, C.line); tl:SetPoint("BOTTOMLEFT"); tl:SetPoint("BOTTOMRIGHT"); tl:SetHeight(1)
  W.content = CreateFrame("Frame", nil, W)
  W.content:SetPoint("TOPLEFT", W.tabs, "BOTTOMLEFT", 0, 0)
  W.content:SetPoint("BOTTOMRIGHT", 0, 1)
  if ns.BuildLook then UI.Guard("the window look", ns.BuildLook, W, header, side) end

  -- resize grip
  local grip = CreateFrame("Button", nil, W)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() W:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() W:StopMovingOrSizing(); savePlace(); layout(); refresh() end)
  W:SetScript("OnSizeChanged", function()
    if not layoutTimer then layoutTimer = C_Timer.NewTimer(0.05, function() layout(); refresh() end) end
  end)

  W:SetScript("OnShow", function()
    W:SetScale(ns.settings.scale or 1)
    local site = ns.Site()
    W.siteAge:SetText(site and ("Updated " .. ns.Ago(site.at)) or "No guild website yet")
    ns.OpenPage(current and current.key or ns.settings.page or "overview")
    ticker = C_Timer.NewTicker(1, function()
      if ns.GetCurrentRun() and current and (current.key == "overview" or current.key == "runs") then refresh() end
    end)
  end)
  W:SetScript("OnHide", function() if ticker then ticker:Cancel(); ticker = nil end end)

  StaticPopupDialogs["FOXDEN_DELETE"] = {
    text = "Delete this run from the log?\n\nIf it was already posted, it stays in Discord and on the website.",
    button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    OnAccept = function(_, id) ns.DeleteRun(id) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

function ns.RefreshUI()
  if ns.RefreshSettings then ns.RefreshSettings() end
  if not W or not W:IsShown() then return end
  W:SetScale(ns.settings.scale or 1)
  refresh()
end

function ns.ToggleWindow()
  if not W then build() end
  if W:IsShown() then W:Hide() else W:Show() end
end

-- Minimap addon button (the addon compartment) entry
function Foxden_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then ns.OpenSettings()
  elseif IsShiftKeyDown and IsShiftKeyDown() and ns.ToggleNote then ns.ToggleNote()
  else ns.ToggleWindow() end
end
function Foxden_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  GameTooltip:SetText("Foxden")
  local run = ns.LiveRun()
  if run then GameTooltip:AddLine("In progress: " .. (run.dungeon or "?"), 1, 1, 1) end
  GameTooltip:AddLine(#ns.GetRuns() .. " runs logged", 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to open the dashboard", 0.5, 0.9, 0.77)
  GameTooltip:AddLine("Shift-click for a quick note", 0.5, 0.9, 0.77)
  GameTooltip:AddLine("Right-click for settings", 0.5, 0.9, 0.77)
  GameTooltip:Show()
end
function Foxden_OnAddonCompartmentLeave() GameTooltip:Hide() end
