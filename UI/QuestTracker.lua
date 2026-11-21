-- Foxden: the quest tracker. Your quest log at the side of the screen, grouped by zone:
--   Zone headers fold and unfold (click). The zone you're in is listed first.
--   Each quest: [level] title in the game's difficulty colour, "Dungeon" / "Group" tags, its
--   objectives with progress (done ones in green), or "Ready to turn in" and to whom.
--   Click a quest to show it on the world map, right-click to put a map pin on where it's
--   turned in (or where it started), shift-click to link it in chat.
--   Quests with an item to use (a kit, a totem, a sample jar) get its button at the left of the
--   tracker: click to use it, like the game's own tracker. These are secure buttons, so they
--   only move and change outside combat (the game doesn't allow it during a fight).
--   Drag the title to move it (unless locked); the minus folds everything; the gear opens the
--   Quests page (text size, width, background, lock, and the map and minimap options).

local _, ns = ...
local UI = ns.UI
local C = UI.C
local W = 270 -- from settings: questTrackerWidth
local frame, lines, used = nil, {}, 0
ns.questTrackerLines = lines -- for the test harness
local folded -- { [header] = true }

local function settings() return ns.settings or {} end
local function hex(r, g, b) return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end

local function dungeonOf(id)
  local site = ns.Site and ns.Site()
  for slug, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, q in ipairs(type(rows) == "table" and rows or {}) do if q[1] == id then return slug end end
  end
end

-- Pins the turn-in (or start) on the map, using QuestieDB's spots or the guild's learned ones.
local function pinQuest(q)
  local r = ns.QuestDB and ns.QuestDB[q.id]
  local spots = ns.db and ns.db.questSpots and ns.db.questSpots[q.id]
  local name, map, x, y
  if r and (r[20] or 0) > 0 then name, map, x, y = r[19], r[20], r[21], r[22]
  elseif spots and spots.e then name, map, x, y = spots.e.n, spots.e.m, spots.e.x, spots.e.y
  elseif r and (r[16] or 0) > 0 then name, map, x, y = r[15], r[16], r[17], r[18]
  elseif spots and spots.s then name, map, x, y = spots.s.n, spots.s.m, spots.s.x, spots.s.y end
  if not map then ns.say("Foxden doesn't know where " .. (q.title or "that quest") .. " is turned in yet."); return end
  local who = (name and name ~= "") and name or q.title
  -- the arrow (works everywhere), and the game's own pin where that works
  if ns.SetArrow then ns.SetArrow(map, x, y, name, (q.complete and "Turn in: " or "") .. (q.title or "")) end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
    pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
  end
  ns.say(string.format("Arrow to %s (%d, %d).", who, math.floor(x + 0.5), math.floor(y + 0.5)))
end

local function openOnMap(q)
  local r = ns.QuestDB and ns.QuestDB[q.id]
  local map = r and ((q.complete and (r[20] or 0) > 0 and r[20]) or (r[16] or 0) > 0 and r[16]) or nil
  if QuestMapFrame_OpenToQuestDetails and not map then pcall(QuestMapFrame_OpenToQuestDetails, q.id); return end
  if map and OpenWorldMap then pcall(OpenWorldMap, map); return end
  if ToggleWorldMap then ToggleWorldMap() end
end

-- ---- the full quest card on hover ------------------------------------------------------
-- The quest log's text for a quest. Newer clients take the log index; older ones read the
-- selected quest, so select it for a moment and put the old selection back.
local function questText(q)
  if not GetQuestLogQuestText then return nil end
  -- the reliable way everywhere: select it for a moment, read, put the old selection back
  if C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.SetSelectedQuest then
    local okB, before = pcall(C_QuestLog.GetSelectedQuest)
    pcall(C_QuestLog.SetSelectedQuest, q.id)
    local ok, desc, obj = pcall(GetQuestLogQuestText)
    if okB and before and before ~= q.id then pcall(C_QuestLog.SetSelectedQuest, before) end
    if ok and type(desc) == "string" then return desc, obj end
  end
  local index = q.index
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, q.id); if ok and i then index = i end
  end
  local ok, desc, obj = pcall(GetQuestLogQuestText, index)
  if ok and type(desc) == "string" then return desc, obj end
end

local function clean(t)
  return (tostring(t or ""):gsub("%$[Nn]", UnitName("player") or "you"):gsub("%$[Cc]", (UnitClass("player"))):gsub("%$[Rr]", (UnitRace("player")))
    :gsub("%$[Bb]", "\n"):gsub("%$[Gg]([^:;]*):([^;]*);", "%1"))
end

ns.QuestLogText, ns.CleanQuestText, ns.DungeonOfQuest = questText, clean, dungeonOf
ns.PinQuest, ns.ShowQuestOnMap = pinQuest, openOnMap

function ns.QuestCard(owner, q)
  local ar, ag, ab = UI.Accent()
  local x = owner:GetCenter()
  GameTooltip:SetOwner(owner, (x and x > (UIParent:GetWidth() or 1000) / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  local r, g, b = 1, 0.82, 0
  if ns.Quests then r, g, b = ns.Quests.Color(q.level) end
  local tag = dungeonOf(q.id) and "Dungeon" or (q.group or 0) > 0 and ("Group " .. q.group) or ""
  GameTooltip:AddDoubleLine("[" .. (q.level or "?") .. "] " .. (q.title or "?"), tag, r, g, b, 0.7, 0.72, 0.78)
  local desc, objText = questText(q)
  local dbr = ns.QuestDB and ns.QuestDB[q.id]
  objText = (objText and objText ~= "") and objText or (dbr and dbr[23] ~= "" and dbr[23]) or nil
  if objText then GameTooltip:AddLine(clean(objText), 1, 1, 1, true) end
  if desc and desc ~= "" then
    desc = clean(desc)
    if #desc > 420 then desc = desc:sub(1, 400):gsub("%s+%S*$", "") .. "..." end
    GameTooltip:AddLine(desc, 0.62, 0.65, 0.7, true)
  end
  -- objectives
  if #q.objectives > 0 or q.complete then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Objectives", ar, ag, ab)
    if q.complete then GameTooltip:AddLine("Ready to turn in", 0.43, 0.83, 0.6) end
    for _, o in ipairs(q.objectives) do
      if o.done then GameTooltip:AddLine("- " .. o.text, 0.43, 0.83, 0.6, true) else GameTooltip:AddLine("- " .. o.text, 0.9, 0.9, 0.9, true) end
    end
  end
  -- where to turn it in
  local spots = ns.db and ns.db.questSpots and ns.db.questSpots[q.id]
  local who, map, tx, ty
  if dbr and (dbr[20] or 0) > 0 then who, map, tx, ty = dbr[19], dbr[20], dbr[21], dbr[22]
  elseif spots and spots.e then who, map, tx, ty = spots.e.n, spots.e.m, spots.e.x, spots.e.y end
  if who and who ~= "" then
    local zone
    if map and C_Map and C_Map.GetMapInfo then local ok, info = pcall(C_Map.GetMapInfo, map); zone = ok and type(info) == "table" and info.name or nil end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Turn in to", ar, ag, ab)
    GameTooltip:AddLine(who .. (zone and (", " .. zone) or "") .. (tx and string.format(" (%d, %d)", math.floor(tx + 0.5), math.floor(ty + 0.5)) or ""), 1, 1, 1, true)
  end
  -- the next quest in its chain (dungeon quests, from the website)
  local site = ns.Site and ns.Site()
  for _, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, d in ipairs(type(rows) == "table" and rows or {}) do
      local chain = d[23]
      if type(chain) == "table" and #chain > 1 then
        for i, st in ipairs(chain) do
          if st[1] == q.id then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Quest chain: step %d of %d", i, #chain), ar, ag, ab)
            if chain[i + 1] then GameTooltip:AddLine("Next: " .. tostring(chain[i + 1][2]), 1, 1, 1, true) end
            if d[2] ~= st[2] then GameTooltip:AddLine("Leads to " .. d[2], 0.85, 0.87, 0.9, true) end
            break
          end
        end
      end
    end
  end
  -- rewards
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Rewards", ar, ag, ab)
  local xp = ns.Quests and ns.Quests.XP(q.id, q.level)
  if xp and xp > 0 then GameTooltip:AddLine((ns.Commas and ns.Commas(xp) or xp) .. " XP", 1, 1, 1) end
  for _, l in ipairs(ns.QuestRewardLines and ns.QuestRewardLines(q.id) or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
  -- the guild's note
  local notes = site and type(site.questNotes) == "table" and site.questNotes
  local note = notes and (notes[q.id] or notes[tostring(q.id)])
  if type(note) == "table" and note[1] then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Guild note", ar, ag, ab)
    GameTooltip:AddLine(note[1] .. ((note[2] and note[2] ~= "") and ("  |cff99a1b0(" .. note[2] .. ")|r") or ""), 1, 1, 1, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: all the details. Right-click: arrow to the turn-in. Shift-click: link it.", 0.6, 0.63, 0.69, true)
  GameTooltip:Show()
end

local function line(i)
  local l = lines[i]
  if not l then
    l = CreateFrame("Button", nil, frame.body)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l.text = UI.Text(l, 12); l.text:SetWordWrap(true); l.text:SetJustifyV("TOP")
    l.text:SetShadowOffset(1, -1); l.text:SetShadowColor(0, 0, 0, 0.9)
    l.text:SetPoint("TOPLEFT", 0, 0)
    l.hover = l:CreateTexture(nil, "BACKGROUND"); l.hover:SetAllPoints(); l.hover:SetColorTexture(1, 1, 1, 0.06); l.hover:Hide()
    l:SetScript("OnEnter", function(s)
      if s.kind ~= "obj" then s.hover:Show() end
      if s.quest then ns.QuestCard(s, s.quest) end
    end)
    l:SetScript("OnLeave", function(s) s.hover:Hide(); GameTooltip:Hide() end)
    l:SetScript("OnClick", function(s, button)
      if s.kind == "zone" then
        folded[s.header] = not folded[s.header] or nil
        ns.RefreshQuestTracker()
      elseif s.quest then
        local q = s.quest
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ns.QuestLink then
          ns.LinkInChat(ns.QuestLink(q.id))
        elseif button == "RightButton" then pinQuest(q)
        elseif ns.ToggleQuestDetails then GameTooltip:Hide(); ns.ToggleQuestDetails(q, frame)
        else openOnMap(q) end
      end
    end)
    lines[i] = l
  end
  return l
end

-- ---- quest item buttons -----------------------------------------------------------------
local itemButtons, itemWanted, itemPending = {}, {}, false
local function itemButton(i)
  local b = itemButtons[i]
  if not b then
    b = CreateFrame("Button", "FoxdenQuestItem" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetSize(26, 26)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    UI.Fill(b, C.bg)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    UI.Border(b)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.15)
    b.count = UI.Text(b, 10, C.text, "RIGHT"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count:SetShadowOffset(1, -1); b.count:SetShadowColor(0, 0, 0, 1)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); b.cd:SetAllPoints(b.icon)
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_LEFT")
      local ok = s.logIndex and GameTooltip.SetQuestLogSpecialItem and pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, s.logIndex)
      if not ok and s.link then GameTooltip:SetHyperlink(s.link) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    itemButtons[i] = b
  end
  return b
end

-- The item a quest gives you to use, if any: { link, icon, charges, item, index }
local function questItem(q)
  if not GetQuestLogSpecialItemInfo then return nil end
  local index = q.index
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, q.id); if ok and i then index = i end
  end
  if not index then return nil end
  local ok, link, icon, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
  if not ok or type(link) ~= "string" then return nil end
  if q.complete and not showWhenComplete then return nil end
  local id = link:match("item:(%d+)")
  return { link = link, icon = icon, charges = charges, item = id and ("item:" .. id) or link, index = index }
end

-- Put the buttons beside their quests (outside combat only).
local function placeItems()
  if InCombatLockdown and InCombatLockdown() then itemPending = true; return end
  itemPending = false
  local n = 0
  local s = settings()
  if frame and frame:IsShown() and not s.questTrackerFolded and s.questTrackerItems ~= false then
    local left, top = frame:GetLeft(), frame:GetTop()
    -- the list's visible height, from the tracker's own (the scroll area may not have caught up yet)
    local scroll, viewH = frame.scroll:GetVerticalScroll() or 0, (frame:GetHeight() or 0) - 38
    for _, w in ipairs(itemWanted) do
      local y = w.y - scroll
      if left and top and y >= -6 and y + 20 <= viewH + 6 then
        n = n + 1
        local b = itemButton(n)
        b.link, b.logIndex = w.link, w.index
        b.icon:SetTexture(w.icon)
        b.count:SetText((w.charges or 0) > 1 and w.charges or "")
        b:SetAttribute("item", w.item)
        b:ClearAllPoints(); b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - 4, top - 30 - y + 4)
        local okC, start, dur = false, 0, 0
        if GetQuestLogSpecialItemCooldown then okC, start, dur = pcall(GetQuestLogSpecialItemCooldown, w.index) end
        if okC and start and dur and dur > 0 then b.cd:SetCooldown(start, dur) else b.cd:SetCooldown(0, 0) end
        b:Show()
      end
    end
  end
  for i = n + 1, #itemButtons do itemButtons[i]:Hide() end
end
ns.PlaceQuestItems = placeItems

local function fontSize(base) return base + ((tonumber(settings().questTrackerFont) or 12) - 12) end

local function put(kind, text, size, indent, opts)
  size = fontSize(size)
  used = used + 1
  local l = line(used)
  l.kind, l.quest, l.header = kind, opts and opts.quest, opts and opts.header
  l.text:SetFont(UI.Font(), size, "")
  l.text:SetWidth(W - 20 - indent)
  l.text:SetText(text)
  if opts and opts.color then l.text:SetTextColor(unpack(opts.color)) else l.text:SetTextColor(unpack(C.text)) end
  local h = math.max(size + 2, (l.text:GetStringHeight() or size) + 2)
  l:SetHeight(h)
  l:ClearAllPoints(); l:SetPoint("TOPLEFT", frame.body, "TOPLEFT", indent, -frame.y); l:SetWidth(W - 20 - indent)
  l:Show()
  frame.y = frame.y + h + (opts and opts.gap or 2)
end

local function build()
  frame = CreateFrame("Frame", "FoxdenQuestTracker", UIParent)
  frame:SetSize(W, 100)
  frame:SetMovable(true); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("LOW")
  local pos = settings().questTrackerPos
  if pos then frame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -220) end
  frame.bg = frame:CreateTexture(nil, "BACKGROUND"); frame.bg:SetAllPoints(); frame.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.45)
  -- title bar: drag to move
  local head = CreateFrame("Button", nil, frame)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(26)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() if not settings().questTrackerLocked then frame.moving = true; frame:StartMoving() end end)
  head:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, _, x, y = frame:GetPoint(1)
    ns.settings.questTrackerPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    frame.moving = false
    placeItems()
  end)
  -- the item buttons follow while you drag it
  head:SetScript("OnUpdate", function() if frame.moving then placeItems() end end)
  head.bar = head:CreateTexture(nil, "ARTWORK"); head.bar:SetPoint("TOPLEFT", 0, 0); head.bar:SetPoint("BOTTOMLEFT", 0, 0); head.bar:SetWidth(2); UI.Accented(head.bar)
  frame.title = UI.Text(head, 13); frame.title:SetPoint("LEFT", 10, 0)
  frame.title:SetShadowOffset(1, -1); frame.title:SetShadowColor(0, 0, 0, 0.9)
  frame.gear = CreateFrame("Button", nil, head); frame.gear:SetSize(18, 18); frame.gear:SetPoint("RIGHT", -30, 0)
  frame.gear.t = frame.gear:CreateTexture(nil, "ARTWORK"); frame.gear.t:SetAllPoints()
  frame.gear.t:SetTexture("Interface\\Buttons\\UI-OptionsButton"); frame.gear.t:SetVertexColor(0.7, 0.72, 0.78)
  frame.gear:SetScript("OnClick", function() if ns.OpenPage then ns.OpenPage("quests") end end)
  frame.gear:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText("Quest settings"); GameTooltip:Show() end)
  frame.gear:SetScript("OnLeave", GameTooltip_Hide)
  frame.fold = CreateFrame("Button", nil, head); frame.fold:SetSize(22, 22); frame.fold:SetPoint("RIGHT", -4, 0)
  frame.fold.t = UI.Text(frame.fold, 16, C.dim, "CENTER"); frame.fold.t:SetPoint("CENTER", 0, 1)
  frame.fold:SetScript("OnClick", function() settings().questTrackerFolded = not settings().questTrackerFolded; ns.RefreshQuestTracker() end)
  frame.fold:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText(settings().questTrackerFolded and "Show quests" or "Fold the tracker")
    GameTooltip:AddLine("Drag the title to move it, the corner to resize it; scroll with the mouse wheel. Click a quest for all its details, right-click for a map pin to its turn-in.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame.fold:SetScript("OnLeave", GameTooltip_Hide)
  -- the list scrolls (mouse wheel) when it's taller than the tracker
  frame.scroll = CreateFrame("ScrollFrame", nil, frame)
  frame.scroll:SetPoint("TOPLEFT", 10, -30); frame.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
  frame.body = CreateFrame("Frame", nil, frame.scroll)
  frame.body:SetSize(W - 20, 10)
  frame.scroll:SetScrollChild(frame.body)
  frame.scroll:EnableMouseWheel(true)
  frame.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (frame.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 36)))
    frame.thumbUpdate()
    placeItems()
  end)
  frame.thumb = frame:CreateTexture(nil, "OVERLAY"); frame.thumb:SetWidth(2); UI.Accented(frame.thumb, 0.6)
  function frame.thumbUpdate()
    local view, full = frame.scroll:GetHeight() or 0, frame.body:GetHeight() or 0
    if full <= view + 1 or view <= 0 then frame.thumb:Hide(); return end
    local th = math.max(16, view * view / full)
    local off = (frame.scroll:GetVerticalScroll() or 0) / (full - view) * (view - th)
    frame.thumb:ClearAllPoints(); frame.thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -30 - off); frame.thumb:SetHeight(th)
    frame.thumb:Show()
  end
  -- resize from the bottom-right corner: width, and how tall it may grow before it scrolls
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(200, 90, 700, 1400)
  elseif frame.SetMinResize then frame:SetMinResize(200, 90); frame:SetMaxResize(700, 1400) end
  local grip = CreateFrame("Button", nil, frame); grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip.t = grip:CreateTexture(nil, "OVERLAY"); grip.t:SetAllPoints()
  grip.t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); grip.t:SetAlpha(0.5)
  grip:SetScript("OnEnter", function() grip.t:SetAlpha(1) end)
  grip:SetScript("OnLeave", function() grip.t:SetAlpha(0.5) end)
  grip:SetScript("OnMouseDown", function()
    if settings().questTrackerLocked then return end
    frame.sizing = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not frame.sizing then return end
    frame.sizing = false
    frame:StopMovingOrSizing()
    ns.settings.questTrackerWidth = math.floor(frame:GetWidth() + 0.5)
    ns.settings.questTrackerHeight = math.floor(frame:GetHeight() + 0.5)
    local point, _, _, x, y = frame:GetPoint(1)
    ns.settings.questTrackerPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    ns.RefreshQuestTracker()
  end)
  frame:SetScript("OnSizeChanged", function()
    if frame.sizing then
      W = frame:GetWidth()
      if not frame.relayout then
        frame.relayout = true
        C_Timer.After(0.05, function() frame.relayout = false; if frame.sizing then ns.RefreshQuestTracker() end end)
      end
    end
  end)
  frame.grip = grip
end

function ns.RefreshQuestTracker()
  if not frame then return end
  local s = settings()
  folded = s.questTrackerZones or {}
  s.questTrackerZones = folded
  if s.questTracker == false then frame:Hide(); placeItems(); return end
  if frame.sizing then W = frame:GetWidth() else W = tonumber(s.questTrackerWidth) or 270; frame:SetWidth(W) end
  frame.body:SetWidth(W - 20)
  local bgA = tonumber(s.questTrackerBg) or 0.45
  frame.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], bgA)
  local log = ns.Quests and ns.Quests.Log() or {}
  local count = 0
  for _, g in ipairs(log) do count = count + #g.quests end
  local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or (MAX_QUESTS or 25)
  local ar, ag, ab = UI.Accent()
  frame.title:SetText(hex(ar, ag, ab) .. "Quests|r  " .. count .. "/" .. max)
  frame.fold.t:SetText(s.questTrackerFolded and "+" or "-")
  used, frame.y = 0, 0
  wipe(itemWanted)
  if count == 0 and not s.questTrackerFolded then
    put("info", "No quests in your log. Look for ! on the map.", 11, 0, { color = C.dim })
  end
  if not s.questTrackerFolded then
    -- the zone you're in first
    local zone = GetRealZoneText and GetRealZoneText() or nil
    local order = {}
    for _, g in ipairs(log) do if g.header == zone then order[#order + 1] = g end end
    for _, g in ipairs(log) do if g.header ~= zone then order[#order + 1] = g end end
    for _, g in ipairs(order) do
      local closed = folded[g.header]
      put("zone", g.header .. "  " .. (closed and "|cff99a1b0+ " .. #g.quests .. "|r" or "|cff99a1b0-|r"), 13, 0, { header = g.header, color = C.dim, gap = 4 })
      if not closed then
        for _, q in ipairs(g.quests) do
          local r, gg, b = 1, 0.82, 0
          if ns.Quests then r, gg, b = ns.Quests.Color(q.level) end
          local tags = {}
          local dslug = dungeonOf(q.id)
          if dslug then tags[#tags + 1] = "Dungeon" elseif (q.group or 0) > 0 then tags[#tags + 1] = "Group " .. q.group end
          if q.failed then tags[#tags + 1] = "|cffef6b6bFailed|r" end
          local item = s.questTrackerItems ~= false and questItem(q)
          if item then item.y = frame.y; itemWanted[#itemWanted + 1] = item end
          put("quest", hex(r, gg, b) .. "[" .. (q.level or "?") .. "] " .. (q.title or "?") .. "|r" .. (#tags > 0 and ("  |cff99a1b0(" .. table.concat(tags, ", ") .. ")|r") or ""),
            12, 6, { quest = q })
          if q.complete then
            local dbr = ns.QuestDB and ns.QuestDB[q.id]
            local to = dbr and dbr[19] ~= "" and dbr[19] or nil
            put("obj", "|cff6fd39aReady to turn in" .. (to and (": " .. to) or "") .. "|r", 11, 16, { gap = 3, quest = q })
          else
            for _, o in ipairs(q.objectives) do
              if not o.done or s.questShowDoneObj ~= false then
                put("obj", (o.done and "|cff6fd39a" or "|cffd8dbe0") .. "- " .. o.text .. "|r", 11, 16, { quest = q })
              end
            end
            frame.y = frame.y + 2
          end
        end
      end
      frame.y = frame.y + 4
    end
  end
  for i = used + 1, #lines do lines[i]:Hide() end
  frame.body:SetHeight(math.max(1, frame.y))
  -- as tall as the list, up to the height you've sized it to (default: 70% of the screen)
  local maxH = tonumber(s.questTrackerHeight) or math.floor((UIParent:GetHeight() or 800) * 0.7)
  local want = 30 + frame.y + (used > 0 and 8 or 0)
  if not frame.sizing then frame:SetHeight(math.max(40, math.min(want, maxH))) end
  local max = math.max(0, frame.y - (frame.scroll:GetHeight() or 0))
  if (frame.scroll:GetVerticalScroll() or 0) > max then frame.scroll:SetVerticalScroll(max) end
  frame.grip:SetShown(not s.questTrackerLocked and not s.questTrackerFolded)
  frame.thumbUpdate()
  frame.bg:SetShown(used > 0 and bgA > 0)
  frame:Show()
  placeItems()
end

-- Hide the game's own quest tracker (on by default; Quests page), and EllesmereUI's.
--  * EllesmereUI: its own switch for other addons (_EQT_SetSuppressed), which hides its
--    tracker and the game's one it skins, and keeps them hidden.
--  * The game's ObjectiveTrackerFrame belongs to Edit Mode, which puts it back on screen
--    (moving it into a hidden frame didn't stick). Instead, whenever anything shows it,
--    Foxden hides it again; in combat, where hiding it is blocked, it goes see-through
--    and is hidden properly when combat ends.
--  * The older QuestWatchFrame is moved into a hidden frame.
local vault, moved, hooked = nil, {}, false
local function hideOTF(otf)
  if InCombatLockdown() then otf:SetAlpha(0) else otf:SetAlpha(1); otf:Hide() end
end
-- only while Foxden's own tracker is on: turning ours off brings the game's back
local function wantHidden()
  local s = settings()
  return (s.hideGameTracker and s.questTracker ~= false) and true or false
end

function ns.ApplyGameTracker()
  local hide = wantHidden()
  local eui = type(_G._EQT_SetSuppressed) == "function"
  if eui then pcall(_G._EQT_SetSuppressed, "Foxden", hide) end

  local otf = _G.ObjectiveTrackerFrame
  if otf and not eui then
    if hide and not hooked then
      hooked = true
      hooksecurefunc(otf, "Show", function(self) if wantHidden() then hideOTF(self) end end)
      otf:HookScript("OnShow", function(self) if wantHidden() then hideOTF(self) end end)
    end
    if hide then if otf:IsShown() then hideOTF(otf) end
    elseif not InCombatLockdown() then otf:SetAlpha(1); if not otf:IsShown() then otf:Show() end end
  end

  local qwf = _G.QuestWatchFrame
  if qwf and qwf.GetParent then
    if hide then
      vault = vault or CreateFrame("Frame"); vault:Hide()
      if qwf:GetParent() ~= vault then moved.QuestWatchFrame = moved.QuestWatchFrame or qwf:GetParent(); pcall(qwf.SetParent, qwf, vault) end
    elseif moved.QuestWatchFrame then
      pcall(qwf.SetParent, qwf, moved.QuestWatchFrame); moved.QuestWatchFrame = nil
    end
  end
end

ns.RegisterModule({
  name = "QuestTracker",
  events = {
    PLAYER_LOGIN = function()
      build()
      if ns.Quests then ns.Quests.OnChange(function() ns.Quests.Try("tracker", ns.RefreshQuestTracker) end) end
      ns.RefreshQuestTracker()
      ns.ApplyGameTracker()
      -- other addons build their trackers after us: hide those once they exist
      C_Timer.After(2, ns.ApplyGameTracker); C_Timer.After(6, ns.ApplyGameTracker)
    end,
    ZONE_CHANGED_NEW_AREA = function() ns.RefreshQuestTracker() end,
    PLAYER_REGEN_ENABLED = function()
      if itemPending then placeItems() end
      -- hidden for real now that combat is over (it was only see-through)
      local otf = _G.ObjectiveTrackerFrame
      if otf and wantHidden() and type(_G._EQT_SetSuppressed) ~= "function" and otf:IsShown() then hideOTF(otf) end
    end,
    BAG_UPDATE_COOLDOWN = function() if not (InCombatLockdown and InCombatLockdown()) then placeItems() end end,
  },
})
