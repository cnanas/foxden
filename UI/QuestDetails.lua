-- Foxden: the quest details panel. Click a quest in the quest tracker and this opens beside it
-- with everything about the quest: its text, objectives (live), where to turn it in, its quest
-- chain, the guild's note, and the rewards as item icons you can hover (the item's own tooltip),
-- shift-click to link or ctrl-click to try on. Buttons: show it on the map, an arrow to the
-- turn-in, link it in chat, abandon it (asks first). Foxden's own frame, so it works in combat too. Esc or X closes it.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local W, MAXH, PAD = 380, 560, 14
local panel, current
local texts, items, usedT, usedI = {}, {}, 0, 0
ns.questDetailParts = { texts = texts, items = items } -- for the test harness

local function hex(r, g, b)
  local function c(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
  return string.format("|cff%02x%02x%02x", c(r), c(g), c(b))
end

-- ---- dungeon and raid quests ------------------------------------------------------------------
-- Which dungeon or raid a quest is for: name, isRaid (or nil). The website's dungeon quest lists
-- first, else a dungeon or raid named in the quest's objective (QuestieDB). Cached per quest.
local ALIASES = { -- what quest text calls them, for names it doesn't use whole
  ["Stormwind Stockade"] = { "Stockade" }, ["Sunken Temple"] = { "Atal'Hakkar", "Sunken Temple" },
  ["Ahn'Qiraj Temple"] = { "Temple of Ahn'Qiraj" }, ["Deadmines"] = { "Deadmines" },
}
local instCache, names = {}, nil
function ns.QuestInstance(id)
  if not id then return nil end
  local c = instCache[id]
  if c ~= nil then if c then return c[1], c[2] end; return nil end
  local found
  local slug = ns.DungeonOfQuest and ns.DungeonOfQuest(id)
  for _, d in pairs(ns.Dungeons or {}) do
    if slug and ns.Slug(d.name) == slug then found = { d.name, d.raid and true or false } end
  end
  if not found then
    if not names then
      names = {}
      for _, d in pairs(ns.Dungeons or {}) do
        for _, n in ipairs(ALIASES[d.name] or { (d.name:gsub("^The ", "")) }) do names[#names + 1] = { n:lower(), d.name, d.raid and true or false } end
      end
      table.sort(names, function(a, b) return #a[1] > #b[1] end) -- longest first: "Upper Blackrock Spire" before "Blackrock"
    end
    local r = ns.QuestDB and ns.QuestDB[id]
    local text = r and type(r[23]) == "string" and r[23]:lower() or ""
    if text ~= "" then
      for _, n in ipairs(names) do
        if text:find(n[1], 1, true) then found = { n[2], n[3] }; break end
      end
    end
  end
  instCache[id] = found or false
  if found then return found[1], found[2] end
end

-- ---- quest links ----------------------------------------------------------------------------
-- A quest's chat link. GetQuestLink takes a quest ID on newer clients and the quest's place in
-- your log on older ones (Forever); quests you don't have get a link built by hand.
function ns.QuestLink(id)
  if not id then return nil end
  local function try(arg)
    if not (GetQuestLink and arg) then return nil end
    local ok, link = pcall(GetQuestLink, arg)
    return ok and type(link) == "string" and link:find("|Hquest:" .. id .. ":") and link or nil
  end
  local link = try(id)
  if not link then
    local index = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id))
      or (GetQuestLogIndexByID and GetQuestLogIndexByID(id))
    if index and index > 0 then link = try(index) end
  end
  if link then return link end
  local r = ns.QuestDB and ns.QuestDB[id]
  local x = ns.Quests and ns.Quests.InLog(id)
  local title, level = (x and x.title) or (r and r[1]), (x and x.level) or (r and r[3]) or 0
  if not title then return nil end
  return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, level, title)
end

-- Put a link in chat: into the box you're typing in, else open one with it.
function ns.LinkInChat(link)
  if not link then return false end
  if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
  elseif ChatFrame_OpenChat then ChatFrame_OpenChat(link)
  else return false end
  return true
end

-- ---- rewards as items ---------------------------------------------------------------------
-- { money, items = { entry }, choices = { entry } }; entry = { id, name, icon, count, quality, logType, logIndex }
local function rewardsOf(q)
  local out = { items = {}, choices = {} }
  local function fromLog(kind, countFn, infoFn, into)
    if not countFn then return end
    local ok, n = pcall(countFn, q.id, kind == "choice" or nil)
    for i = 1, ok and n or 0 do
      local okI, name, icon, count, quality, _, itemID = pcall(infoFn, i, q.id)
      if okI and name then into[#into + 1] = { id = itemID, name = name, icon = icon, count = count, quality = quality, logType = kind, logIndex = i } end
    end
  end
  if GetQuestLogRewardMoney then local ok, m = pcall(GetQuestLogRewardMoney, q.id); if ok and m and m > 0 then out.money = m end end
  fromLog("reward", GetNumQuestLogRewards, GetQuestLogRewardInfo, out.items)
  fromLog("choice", GetNumQuestLogChoices, GetQuestLogChoiceInfo, out.choices)
  -- not from the log (or the log isn't ready): the website's copy of Blizzard's rewards
  local site = ns.Site and ns.Site()
  local rw = site and type(site.rewards) == "table" and (site.rewards[q.id] or site.rewards[tostring(q.id)])
  if type(rw) == "table" then
    if not out.money and (rw[1] or 0) > 0 then out.money = rw[1] end
    if #out.items == 0 then for _, id in ipairs(type(rw[2]) == "table" and rw[2] or {}) do out.items[#out.items + 1] = { id = id } end end
    if #out.choices == 0 then for _, id in ipairs(type(rw[3]) == "table" and rw[3] or {}) do out.choices[#out.choices + 1] = { id = id } end end
  end
  return out
end

local function itemInfo(e)
  if e.id and C_Item and C_Item.GetItemInfo then
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(e.id)
    if not name and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
    e.name, e.quality, e.icon, e.link = e.name or name, e.quality or quality, e.icon or icon, link
    e.icon = e.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id))
  end
  return e
end

-- ---- building blocks ------------------------------------------------------------------------
local function text(size, color, indent)
  usedT = usedT + 1
  local t = texts[usedT]
  if not t then
    t = panel.body:CreateFontString(nil, "OVERLAY")
    t:SetJustifyH("LEFT"); t:SetJustifyV("TOP"); t:SetWordWrap(true)
    texts[usedT] = t
  end
  t:SetFont(UI.Font(), size, "")
  t:SetTextColor(unpack(color or C.text))
  t:ClearAllPoints(); t:SetPoint("TOPLEFT", indent or 0, -panel.y); t:SetWidth(W - PAD * 2 - (indent or 0))
  t:Show()
  return t
end
local function add(str, size, color, gap, indent)
  local t = text(size or 12, color, indent)
  t:SetText(str)
  panel.y = panel.y + (t:GetStringHeight() or 14) + (gap or 4)
  return t
end
local function header(str)
  panel.y = panel.y + 8
  local t = add(str, 13, nil, 6)
  t:SetTextColor(UI.Accent())
end

-- One chain step: click to open that quest here, hover for its rewards and XP.
local steps, usedS = {}, 0
local function stepRow(str, color, id)
  usedS = usedS + 1
  local b = steps[usedS]
  if not b then
    b = CreateFrame("Button", nil, panel.body)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFont(UI.Font(), 11, ""); b.t:SetPoint("LEFT", 4, 0); b.t:SetPoint("RIGHT", -4, 0)
    b.t:SetJustifyH("LEFT"); b.t:SetWordWrap(false)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function(s) if ns.OpenQuestDetails then ns.OpenQuestDetails(s.id) end end)
    b:SetScript("OnEnter", function(s) if ns.QuestRewardTooltip then ns.QuestRewardTooltip(s, s.id) end end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    steps[usedS] = b
  end
  b.id = id
  b.t:SetText(str); b.t:SetTextColor(unpack(color or C.text))
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", 2, -panel.y); b:SetSize(W - PAD * 2 - 4, 18)
  b:Show()
  panel.y = panel.y + 19
end

local function itemButton()
  usedI = usedI + 1
  local b = items[usedI]
  if not b then
    b = CreateFrame("Button", nil, panel.body)
    b:SetSize((W - PAD * 2 - 8) / 2, 38)
    UI.Fill(b, C.raised); UI.Border(b)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 4, 0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetFont(UI.Font(), 10, "OUTLINE"); b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
    b.name = b:CreateFontString(nil, "OVERLAY"); b.name:SetFont(UI.Font(), 11, ""); b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", -6, 0); b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(true)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      local ok = false
      if s.e.logType and GameTooltip.SetQuestLogItem then ok = pcall(GameTooltip.SetQuestLogItem, GameTooltip, s.e.logType, s.e.logIndex, current) end
      if not ok and s.e.id then pcall(GameTooltip.SetItemByID, GameTooltip, s.e.id) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(s)
      local link = s.e.link
      if not link and s.e.logType and GetQuestLogItemLink then local ok, l = pcall(GetQuestLogItemLink, s.e.logType, s.e.logIndex, current); if ok then link = l end end
      if not link then return end
      if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
      elseif IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink(link) end
    end)
    items[usedI] = b
  end
  return b
end

local function itemGrid(list)
  local col = 0
  for _, e in ipairs(list) do
    itemInfo(e)
    local b = itemButton()
    b.e = e
    b.icon:SetTexture(e.icon or 134400)
    b.count:SetText((e.count or 1) > 1 and e.count or "")
    local r, g, bl = 1, 1, 1
    if e.quality and C_Item and C_Item.GetItemQualityColor then r, g, bl = C_Item.GetItemQualityColor(e.quality) end
    b.name:SetText(hex(r or 1, g or 1, bl or 1) .. (e.name or ("Item " .. tostring(e.id))) .. "|r")
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", col * ((W - PAD * 2) / 2 + 4), -panel.y)
    b:Show()
    col = col + 1
    if col == 2 then col = 0; panel.y = panel.y + 42 end
  end
  if col == 1 then panel.y = panel.y + 42 end
end

-- ---- the panel ------------------------------------------------------------------------------
local function build()
  panel = CreateFrame("Frame", "FoxdenQuestDetails", UIParent)
  panel:SetSize(W, 300)
  panel:SetFrameStrata("MEDIUM"); panel:SetToplevel(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  UI.Fill(panel, C.surface); UI.Border(panel)
  panel.bar = panel:CreateTexture(nil, "ARTWORK"); panel.bar:SetPoint("TOPLEFT"); panel.bar:SetSize(3, 30); UI.Accented(panel.bar)
  panel.title = UI.Text(panel, 14); panel.title:SetPoint("TOPLEFT", PAD, -9); panel.title:SetPoint("RIGHT", -36, 0)
  panel.close = UI.CloseButton(panel, function() panel:Hide() end); panel.close:SetPoint("TOPRIGHT", -4, -4)
  panel.sub = UI.Text(panel, 11, C.dim); panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4); panel.sub:SetPoint("RIGHT", -12, 0)
  panel.scroll = CreateFrame("ScrollFrame", nil, panel)
  panel.scroll:SetPoint("TOPLEFT", PAD, -50); panel.scroll:SetPoint("BOTTOMRIGHT", -PAD, 46)
  panel.body = CreateFrame("Frame", nil, panel.scroll); panel.body:SetSize(W - PAD * 2, 10)
  panel.scroll:SetScrollChild(panel.body)
  panel.scroll:EnableMouseWheel(true)
  panel.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (panel.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  local line = panel:CreateTexture(nil, "BORDER"); line:SetColorTexture(unpack(C.line)); line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, 40); line:SetPoint("BOTTOMRIGHT", 0, 40)
  local function q() return current and ns.Quests and ns.Quests.InLog(current) end
  -- a quest you don't have yet: where it starts
  local function giver()
    local r = current and ns.QuestDB and ns.QuestDB[current]
    if r and (r[16] or 0) > 0 then return r[16], r[17], r[18], r[15] end
  end
  panel.map = UI.Button(panel, "Map", 52, 26, function()
    local x = q()
    if x then if ns.ShowQuestOnMap then ns.ShowQuestOnMap(x) end; return end
    local m = giver(); if m and OpenWorldMap then pcall(OpenWorldMap, m) end
  end)
  panel.pin = UI.Button(panel, "Arrow", 64, 26, function()
    local x = q()
    if x then if ns.PinQuest then ns.PinQuest(x) end; return end
    local m, gx, gy, who = giver()
    if m and ns.SetArrow then ns.SetArrow(m, gx, gy, who or "Quest giver") end
  end)
  panel.link = UI.Button(panel, "Link", 56, 26, function()
    if not ns.LinkInChat(ns.QuestLink(current)) then ns.say("Couldn't link that quest.") end
  end)
  panel.map:SetPoint("BOTTOMLEFT", PAD, 8); panel.pin:SetPoint("LEFT", panel.map, "RIGHT", 6, 0); panel.link:SetPoint("LEFT", panel.pin, "RIGHT", 6, 0)
  -- share with your group, when the game allows it for this quest
  panel.share = UI.Button(panel, "Share", 60, 26, function()
    if not current then return end
    local ok = pcall(function()
      if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(current) end
      QuestLogPushQuest()
    end)
    if not ok then ns.say("Couldn't share that quest.") end
  end)
  panel.share:SetPoint("LEFT", panel.link, "RIGHT", 6, 0)
  panel.abandon = UI.Button(panel, "Abandon", 80, 26, function()
    local x = q()
    if x then StaticPopup_Show("FOXDEN_ABANDON_QUEST", x.title or "this quest", nil, x.id) end
  end, "danger")
  panel.abandon:SetPoint("BOTTOMRIGHT", -PAD, 8)
  StaticPopupDialogs["FOXDEN_ABANDON_QUEST"] = {
    text = "Abandon %s?\n\nYou'll lose its progress and any items it gave you.",
    button1 = ABANDON_QUEST_ABBREV or "Abandon", button2 = CANCEL or "Cancel",
    OnAccept = function(_, id) ns.AbandonQuest(id) end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
  panel:Hide()
  if UISpecialFrames then tinsert(UISpecialFrames, "FoxdenQuestDetails") end
  if ns.Quests then
    ns.Quests.OnChange(function()
      if not panel:IsShown() or not current then return end
      local x = ns.Quests.InLog(current)
      if x then ns.Quests.Try("quest details", ns.ShowQuestDetails, x)
      elseif not panel.notInLog then panel:Hide() end
    end)
  end
end

function ns.ShowQuestDetails(q, anchorTo)
  if not panel then build() end
  current = q.id
  panel.notInLog = q.notInLog
  usedT, usedI, usedS, panel.y = 0, 0, 0, 0
  local ar, ag, ab = UI.Accent()
  local r, g, b = 1, 0.82, 0
  if ns.Quests then r, g, b = ns.Quests.Color(q.level) end
  panel.title:SetText(hex(r, g, b) .. "[" .. (q.level or "?") .. "] " .. (q.title or "?") .. "|r")
  local tags = {}
  local inst, raid = ns.QuestInstance(q.id)
  if inst then tags[#tags + 1] = (raid and "|cffff8040Raid quest|r: " or "|cff8fb3ffDungeon quest|r: ") .. inst elseif (q.group or 0) > 0 then tags[#tags + 1] = "Group quest (" .. q.group .. ")" end
  if q.complete then tags[#tags + 1] = "|cff6fd39aReady to turn in|r" elseif q.failed then tags[#tags + 1] = "|cffef6b6bFailed|r" end
  panel.sub:SetText(table.concat(tags, "  ·  "))

  local clean = ns.CleanQuestText or tostring
  local desc, obj
  if ns.QuestLogText then desc, obj = ns.QuestLogText(q) end
  local dbr = ns.QuestDB and ns.QuestDB[q.id]
  obj = (obj and obj ~= "") and obj or (dbr and dbr[23] ~= "" and dbr[23]) or nil
  if obj then add(clean(obj), 12, C.text, 6) end

  if q.notInLog then
    local st = ns.QuestState and ns.QuestState(q.id)
    add(st == "done" and "|cff6fd39aYou've done this quest.|r" or "Not in your quest log.", 12, C.dim, 4)
    if dbr and dbr[15] and dbr[15] ~= "" then
      header("Starts with")
      add(dbr[15] .. (((dbr[17] or 0) > 0) and string.format("  |cff99a1b0(%d, %d)|r", math.floor(dbr[17] + 0.5), math.floor(dbr[18] + 0.5)) or ""), 12)
    end
  end
  if not q.notInLog then header("Objectives") end
  if q.notInLog then
  elseif q.complete then add("Done. Turn it in.", 12, { 0.43, 0.83, 0.6, 1 }) end
  for _, o in ipairs(not q.notInLog and q.objectives or {}) do add("- " .. o.text, 12, o.done and { 0.43, 0.83, 0.6, 1 } or C.text, 2) end
  if not q.notInLog and #(q.objectives or {}) == 0 and not q.complete then add("Nothing to track: talk to the quest's NPC.", 12, C.dim) end

  -- where to turn it in
  local spots = ns.db and ns.db.questSpots and ns.db.questSpots[q.id]
  local who, map, tx, ty
  if dbr and (dbr[20] or 0) > 0 then who, map, tx, ty = dbr[19], dbr[20], dbr[21], dbr[22]
  elseif spots and spots.e then who, map, tx, ty = spots.e.n, spots.e.m, spots.e.x, spots.e.y end
  if who and who ~= "" then
    local zone
    if map and C_Map and C_Map.GetMapInfo then local ok, info = pcall(C_Map.GetMapInfo, map); zone = ok and type(info) == "table" and info.name or nil end
    header("Turn in to")
    add(who .. (zone and (", " .. zone) or "") .. (tx and string.format("  |cff99a1b0(%d, %d)|r", math.floor(tx + 0.5), math.floor(ty + 0.5)) or ""), 12)
  end

  -- its chain: the website's for dungeon quests, else built from the quest database.
  -- Every step can be clicked (opens it here) and hovered (its rewards and XP).
  local site = ns.Site and ns.Site()
  local chain, ends
  for _, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, d in ipairs(type(rows) == "table" and rows or {}) do
      if not chain and type(d[23]) == "table" and #d[23] > 1 then
        for _, st in ipairs(d[23]) do if st[1] == q.id then chain = d[23]; if d[2] ~= st[2] then ends = d[2] end end end
      end
    end
  end
  chain = chain or (ns.Quests and ns.Quests.ChainFromDB and ns.Quests.ChainFromDB(q.id))
  if type(chain) == "table" and #chain > 1 then
    local k, cur
    for i, st in ipairs(chain) do
      if st[1] == q.id then k = i end
      if not cur and not (ns.QuestState and ns.QuestState(st[1]) == "done") then cur = i end
    end
    header(string.format("Quest chain: step %d of %d", k or 1, #chain))
    for i, st in ipairs(chain) do
      local state = ns.QuestState and ns.QuestState(st[1])
      local col = i == k and { ar, ag, ab, 1 } or state == "done" and { 0.43, 0.83, 0.6, 1 } or state == "have" and { 0.91, 0.76, 0.35, 1 } or C.dim
      local tag = state == "done" and "  |TInterface\\RaidFrame\\ReadyCheck-Ready:11:11|t"
        or state == "have" and "  (in your log)" or (i == cur and i ~= k) and "  <- you're here" or ""
      local inst, raid = ns.QuestInstance(st[1])
      local kind = inst and (raid and "  |cffff8040Raid|r" or "  |cff8fb3ffDungeon|r") or ""
      stepRow(i .. ". " .. tostring(st[2]) .. kind .. tag, col, st[1])
    end
    if ends then add("Ends with " .. ends, 11, C.dim, 2, 6) end
    add("Click a step to open it, hover for its rewards.", 10, C.faint, 2, 6)
  end

  -- rewards
  local rw = rewardsOf(q)
  header("Rewards")
  local xp = ns.Quests and ns.Quests.XP(q.id, q.level)
  local bits = {}
  if xp and xp > 0 then bits[#bits + 1] = (ns.Commas and ns.Commas(xp) or xp) .. " XP" end
  if rw.money then bits[#bits + 1] = ns.Money(rw.money) end
  if #bits > 0 then add(table.concat(bits, "   "), 12) end
  local rep = ns.QuestRep and ns.QuestRep(q.id)
  if rep then add("|cff8fb3ff" .. rep .. " reputation|r", 12) end
  if #rw.items > 0 then add(#rw.choices > 0 and "You also get" or "You get", 11, C.dim, 4); itemGrid(rw.items) end
  if #rw.choices > 0 then add("Choose one", 11, C.dim, 4); itemGrid(rw.choices) end
  if #bits == 0 and not rep and #rw.items == 0 and #rw.choices == 0 then add("No rewards listed.", 12, C.dim) end

  -- the story
  if desc and desc ~= "" then
    header("Description")
    add(clean(desc), 11, { 0.75, 0.77, 0.81, 1 }, 4)
  end

  -- the guild's note
  local notes = site and type(site.questNotes) == "table" and site.questNotes
  local note = notes and (notes[q.id] or notes[tostring(q.id)])
  if type(note) == "table" and note[1] then
    header("Guild note")
    add(note[1] .. ((note[2] and note[2] ~= "") and ("  |cff99a1b0(" .. note[2] .. ")|r") or ""), 12)
  end

  for i = usedT + 1, #texts do texts[i]:Hide() end
  for i = usedI + 1, #items do items[i]:Hide() end
  for i = usedS + 1, #steps do steps[i]:Hide() end
  panel.body:SetHeight(math.max(1, panel.y))
  panel:SetHeight(math.min(MAXH, 50 + panel.y + 54))
  local max = math.max(0, panel.y - (panel:GetHeight() - 96))
  if (panel.scroll:GetVerticalScroll() or 0) > max then panel.scroll:SetVerticalScroll(max) end
  panel.map:SetShown(true)
  panel.abandon:SetShown(not q.notInLog)
  panel.pin:SetShown(who ~= nil or (q.notInLog and dbr ~= nil and (dbr[16] or 0) > 0))
  local pushable = C_QuestLog and C_QuestLog.IsPushableQuest and select(2, pcall(C_QuestLog.IsPushableQuest, q.id))
  local grouped = IsInGroup and IsInGroup()
  panel.share:SetShown(pushable == true and grouped and QuestLogPushQuest ~= nil)
  if pushable == true then
    local sub = panel.sub:GetText() or ""
    panel.sub:SetText(sub .. (sub ~= "" and "  ·  " or "") .. "|cff99a1b0Can be shared|r")
  end

  if anchorTo then
    panel:ClearAllPoints()
    local x = anchorTo:GetCenter()
    if x and x > (UIParent:GetWidth() or 1000) / 2 then panel:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -36, 0)
    else panel:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 8, 0) end
  end
  panel:Show()
end

-- Drop a quest from your log, the way the game's quest log does it.
function ns.AbandonQuest(id)
  local ok = false
  if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
    ok = pcall(function() C_QuestLog.SetSelectedQuest(id); C_QuestLog.SetAbandonQuest(); C_QuestLog.AbandonQuest() end)
  elseif SelectQuestLogEntry and SetAbandonQuest and AbandonQuest and GetQuestLogIndexByID then
    ok = pcall(function() SelectQuestLogEntry(GetQuestLogIndexByID(id)); SetAbandonQuest(); AbandonQuest() end)
  end
  if not ok then ns.say("Couldn't abandon that quest here. Use the game's quest log.") end
  if panel and current == id then panel:Hide() end
end

-- Click a quest: open its details; click the same one again: close.
function ns.ToggleQuestDetails(q, anchorTo)
  if panel and panel:IsShown() and current == q.id then panel:Hide(); return end
  if ns.Quests then ns.Quests.Try("quest details", ns.ShowQuestDetails, q, anchorTo) else ns.ShowQuestDetails(q, anchorTo) end
  if panel and anchorTo then panel.scroll:SetVerticalScroll(0) end
end

-- Open any quest by ID: from your log when it's there, else from the quest database.
function ns.OpenQuestDetails(id)
  local x = ns.Quests and ns.Quests.InLog(id)
  if not x then
    local r = ns.QuestDB and ns.QuestDB[id]
    if not r then return end
    x = { id = id, title = r[1], level = r[3], objectives = {}, notInLog = true }
  end
  if ns.Quests then ns.Quests.Try("quest details", ns.ShowQuestDetails, x) else ns.ShowQuestDetails(x) end
  if panel then panel.scroll:SetVerticalScroll(0) end
end

-- A quest's rewards in the tooltip: XP, gold, reputation, items (from your log or the website's copy).
function ns.QuestRewardTooltip(owner, id)
  local r = ns.QuestDB and ns.QuestDB[id]
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local cr, cg, cb = 1, 0.82, 0
  if ns.Quests and r then cr, cg, cb = ns.Quests.Color(r[3]) end
  GameTooltip:SetText((r and ("[" .. (r[3] or "?") .. "] " .. r[1]) or ("Quest " .. id)), cr, cg, cb)
  if r and (r[2] or 0) > 0 then GameTooltip:AddLine("Available from level " .. r[2], 0.7, 0.72, 0.78) end
  local inst, raid = ns.QuestInstance(id)
  if inst then
    if raid then GameTooltip:AddLine("Raid quest: " .. inst, 1, 0.5, 0.25) else GameTooltip:AddLine("Dungeon quest: " .. inst, 0.56, 0.7, 1) end
  end
  local st = ns.QuestState and ns.QuestState(id)
  if st == "done" then GameTooltip:AddLine("Done", 0.43, 0.83, 0.6) elseif st == "have" then GameTooltip:AddLine("In your quest log", 0.91, 0.76, 0.35) end
  local inLog = ns.Quests and ns.Quests.InLog(id)
  local rw
  if not inLog then
    -- not in the log: only the website's copy applies
    local site = ns.Site and ns.Site()
    local x = site and type(site.rewards) == "table" and (site.rewards[id] or site.rewards[tostring(id)])
    rw = { items = {}, choices = {} }
    if type(x) == "table" then
      if (x[1] or 0) > 0 then rw.money = x[1] end
      for _, i in ipairs(type(x[2]) == "table" and x[2] or {}) do rw.items[#rw.items + 1] = { id = i } end
      for _, i in ipairs(type(x[3]) == "table" and x[3] or {}) do rw.choices[#rw.choices + 1] = { id = i } end
    end
  else
    rw = rewardsOf(inLog)
  end
  local xp = ns.Quests and ns.Quests.XP(id, r and r[3])
  local bits = {}
  if xp and xp > 0 then bits[#bits + 1] = (ns.Commas and ns.Commas(xp) or xp) .. " XP" end
  if rw.money then bits[#bits + 1] = ns.Money(rw.money) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(#bits > 0 and table.concat(bits, "   ") or "No XP or gold listed", 1, 1, 1)
  local rep = ns.QuestRep and ns.QuestRep(id)
  if rep then GameTooltip:AddLine(rep .. " reputation", 0.56, 0.7, 1) end
  local function itemLines(list, label)
    if #list == 0 then return end
    GameTooltip:AddLine(label, 0.6, 0.63, 0.69)
    for _, e in ipairs(list) do
      itemInfo(e)
      local qr, qg, qb = 1, 1, 1
      if e.quality and GetItemQualityColor then qr, qg, qb = GetItemQualityColor(e.quality) end
      GameTooltip:AddLine((e.icon and ("|T" .. e.icon .. ":14:14:0:0|t ") or "") .. (e.name or ("item " .. (e.id or "?"))), qr, qg, qb)
    end
  end
  itemLines(rw.items, #rw.choices > 0 and "You also get" or "You get")
  itemLines(rw.choices, "Choose one")
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: open it", 0.55, 0.85, 0.55)
  GameTooltip:Show()
end
