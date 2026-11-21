-- Page: Quests. Everything about the quest helper: what it knows and shows right now, and its
-- settings (map and minimap marks, which quests count, the quest tracker's look).
-- Opened from the sidebar, the gear on the quest tracker, or /fox quests.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, ROW_W = 16, 560

local page = { key = "quests", label = "Quest helper", order = 60 }

local function changed()
  if ns.Quests then ns.Quests.Dirty() end
  if ns.QuestMarksDirty then ns.QuestMarksDirty() end
  if ns.RefreshMapPins then ns.RefreshMapPins() end
  if ns.RefreshMinimapPins then ns.RefreshMinimapPins() end
  if ns.RefreshQuestTracker then ns.RefreshQuestTracker() end
end
local function get(k) return function() return ns.settings[k] end end
local function set(k, after) return function(v) ns.settings[k] = v; changed(); if after then after(v) end end end

function page:Build(f)
  self.scroll = CreateFrame("ScrollFrame", nil, f)
  self.body = CreateFrame("Frame", nil, self.scroll)
  self.scroll:SetScrollChild(self.body)
  self.scroll:EnableMouseWheel(true)
  self.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (self.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  local b = self.body
  self.rows = {}
  local last
  local function add(row, gap)
    row:ClearAllPoints()
    if last then row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 0)) else row:SetPoint("TOPLEFT", 0, 0) end
    self.rows[#self.rows + 1] = row
    last = row
    return row
  end
  local function section(text)
    local holder = CreateFrame("Frame", nil, b); holder:SetSize(ROW_W, 34)
    local fs = UI.SectionLabel(holder, text); fs:SetPoint("BOTTOMLEFT", 0, 6)
    holder.Refresh = function() end
    return add(holder, 8)
  end

  -- status card: what Foxden knows and shows
  local card = CreateFrame("Frame", nil, b); card:SetSize(ROW_W, 92)
  UI.Fill(card, C.surface); UI.Border(card)
  card.title = UI.Text(card, 14); card.title:SetPoint("TOPLEFT", 14, -12)
  card.lines = UI.Text(card, 12, C.dim); card.lines:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8)
  card.lines:SetWidth(ROW_W - 28); card.lines:SetWordWrap(true); card.lines:SetJustifyV("TOP")
  card.enable = UI.Button(card, "Turn on QuestieDB and reload", 210, 24, function() if ns.EnableQuestieDB then ns.EnableQuestieDB() end end, "primary")
  card.enable:SetPoint("TOPRIGHT", -12, -10)
  card.Refresh = function() self:RefreshStatus() end
  self.card = card
  add(card)

  section("On the map")
  add(UI.Toggle(b, ROW_W, "Quest givers on the world map",
    "! where you can pick up a quest, ? where you turn one in.",
    get("questPinsAll"), set("questPinsAll")))
  add(UI.Toggle(b, ROW_W, "Dungeon quests and their chains",
    "Ringed, with the earlier steps of their chains. Click to open.",
    get("questPins"), set("questPins")))
  add(UI.Toggle(b, ROW_W, "Dungeon entrances",
    "A mark at every dungeon and raid entrance, coloured by its level. Click to open the dungeon.",
    get("entrancePins"), set("entrancePins")))
  add(UI.Toggle(b, ROW_W, "Marks on the minimap", "The same marks for the ones close by.",
    get("questMinimap"), set("questMinimap")))
  add(UI.Stepper(b, ROW_W, "Mark size", "How big the ! and ? are on the world map.",
    { { 14, "Small" }, { 18, "Normal" }, { 22, "Large" }, { 26, "Larger" } }, get("questMarkSize"), set("questMarkSize")))

  section("Which quests")
  add(UI.Stepper(b, ROW_W, "Quests above your level", "Shown in red until you reach them.",
    { { 0, "None" }, { 1, "1 level" }, { 2, "2 levels" }, { 3, "3 levels" }, { 5, "5 levels" }, { 10, "10 levels" } },
    get("questAhead"), set("questAhead")))
  add(UI.Toggle(b, ROW_W, "Show grey quests", "Far below your level, next to no XP.",
    get("questShowGrey"), set("questShowGrey")))

  section("Quest tracker")
  add(UI.Toggle(b, ROW_W, "Show the quest tracker",
    "Grouped by zone. Click: map. Right-click: pin the turn-in.",
    get("questTracker"), set("questTracker")))
  add(UI.Toggle(b, ROW_W, "Hide the game's quest tracker",
    "Also EllesmereUI's. Questie's is off in Questie's settings.",
    get("hideGameTracker"), set("hideGameTracker", function() if ns.ApplyGameTracker then ns.ApplyGameTracker() end end)))
  add(UI.Toggle(b, ROW_W, "Quest item buttons", "Click to use a quest's item, beside the quest.",
    get("questTrackerItems"), set("questTrackerItems")))
  add(UI.Toggle(b, ROW_W, "Show finished objectives", "In green. Off: only what's left.",
    get("questShowDoneObj"), set("questShowDoneObj")))
  add(UI.Stepper(b, ROW_W, "Text size", nil,
    { { 11, "Small" }, { 12, "Normal" }, { 13, "Large" }, { 14, "Larger" } }, get("questTrackerFont"), set("questTrackerFont")))
  add(UI.Stepper(b, ROW_W, "Width", nil,
    { { 220, "Narrow" }, { 270, "Normal" }, { 320, "Wide" }, { 380, "Wider" } }, get("questTrackerWidth"), set("questTrackerWidth")))
  add(UI.Stepper(b, ROW_W, "Background", nil,
    { { 0, "None" }, { 0.25, "Light" }, { 0.45, "Normal" }, { 0.75, "Dark" } }, get("questTrackerBg"), set("questTrackerBg")))
  add(UI.Toggle(b, ROW_W, "Lock its position", "Dragging its title won't move it.",
    get("questTrackerLocked"), set("questTrackerLocked")))
  local reset = CreateFrame("Frame", nil, b); reset:SetSize(ROW_W, 44); reset.Refresh = function() end
  local rb = UI.Button(reset, "Reset its place and size", 170, 26, function()
    ns.settings.questTrackerPos, ns.settings.questTrackerHeight, ns.settings.questTrackerWidth = nil, nil, 270
    local t = FoxdenQuestTracker
    if t then t:ClearAllPoints(); t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -220) end
    if ns.RefreshQuestTracker then ns.RefreshQuestTracker() end
  end)
  rb:SetPoint("LEFT", 0, 0)
  add(reset, 6)

  local note = CreateFrame("Frame", nil, b); note:SetSize(ROW_W, 60); note.Refresh = function() end
  local nt = UI.Text(note, 11, C.faint); nt:SetPoint("TOPLEFT", 0, -8); nt:SetWidth(ROW_W); nt:SetWordWrap(true)
  nt:SetText("Quest data: QuestieDB by the Questie team (GPLv3), read from the QuestieDB addon when it's installed (it comes with Questie), else Foxden's own copy. Forever's new quests come from what your guild learns as they play. Running Questie as well shows its marks next to these: turn its map icons off if you see two of each.")
  add(note, 4)
  self.last = last
end

function page:RefreshStatus()
  local card = self.card
  local n, avail, spots, turnins, logged = 0, 0, 0, 0, 0
  for _ in pairs(ns.QuestDB or {}) do n = n + 1 end
  if ns.Quests then
    for _, g in pairs(ns.Quests.Givers()) do
      spots = spots + 1
      for _, e in ipairs(g.quests) do if e.kind == "turnin" then turnins = turnins + 1 else avail = avail + 1 end end
    end
    for _, grp in ipairs(ns.Quests.Log()) do logged = logged + #grp.quests end
  end
  card.title:SetText(n > 0 and (avail .. " quests you can pick up") or "No quest data loaded")
  card.enable:SetShown(ns.QuestieDBState and ns.QuestieDBState() == "off")
  local lines = {
    string.format("%d at %d quest givers, %d ready to turn in, %d in your log. Foxden knows %d quests, from %s.", avail, spots, turnins, logged, n,
      ns.QuestSource and ((ns.QuestSource.building and "QuestieDB (still reading it)" or ns.QuestSource.name)
        .. (ns.QuestSource.note and (". " .. ns.QuestSource.note) or "")) or "its own data"),
    ns.QuestMapStatus and ns.QuestMapStatus() or "",
  }
  local last = ns.Quests and ns.Quests.LastError and ns.Quests.LastError()
  if last then lines[#lines + 1] = "|cffef6b6bLast problem (" .. last .. ")|r" end
  card.lines:SetText(table.concat(lines, "\n"))
  card:SetHeight(math.max(72, 12 + 18 + 8 + (card.lines:GetStringHeight() or 30) + 14))
end

function page:Layout(w, h)
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", PAD, -PAD); self.scroll:SetSize(w - PAD * 2, h - PAD * 2)
  self.body:SetWidth(w - PAD * 2)
end

function page:Refresh()
  for _, r in ipairs(self.rows) do if r.Refresh then r:Refresh() end end
  -- height of everything, for scrolling
  local top, bottom = self.body:GetTop(), self.last and self.last:GetBottom()
  self.body:SetHeight(top and bottom and (top - bottom + 20) or 1200)
end

ns.RegisterPage(page)
