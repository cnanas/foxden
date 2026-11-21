-- Foxden: write a guild tip for a boss in game (Dungeons -> Bosses -> Write a tip).
-- Tips wait in FoxdenDB.tipOutbox; the companion app uploads them to the website, and
-- they come back to everyone with the website's data. Until then yours shows as
-- "on its way". Same rules as the website: up to 600 characters, no links.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local MAX = 600
local ROLES = { { "tank", "Tank" }, { "damage", "DPS" }, { "healer", "Healer" }, { "all", "Everyone" } }
local W = 420
local pop, cur

local function outbox()
  ns.db.tipOutbox = ns.db.tipOutbox or {}
  return ns.db.tipOutbox
end

local function siteTip(slug, boss, role)
  local site = ns.Site and ns.Site()
  for _, t in ipairs(site and site.tips or {}) do
    if t[1] == slug and t[2] == boss and t[3] == role then return t end
  end
end

-- Your tips for this boss that the website doesn't have yet: { [role] = entry }.
function ns.PendingTips(slug, boss)
  local out = {}
  for _, t in ipairs(ns.db and ns.db.tipOutbox or {}) do
    if t.d == slug and t.b == boss then out[t.r] = t end
  end
  return out
end

-- Drop the ones the website has now (same text came back), and any older than two weeks.
local function tidy()
  local list, now = outbox(), GetServerTime()
  for i = #list, 1, -1 do
    local t = list[i]
    local s = siteTip(t.d, t.b, t.r)
    if (s and s[4] == t.t) or now - (t.at or 0) > 14 * 86400 then table.remove(list, i) end
  end
end

local function current(role)
  local mine = ns.PendingTips(cur.slug, cur.boss)[role]
  if mine then return mine.t end
  local s = siteTip(cur.slug, cur.boss, role)
  return s and s[4] or ""
end

local function refresh()
  for _, b in ipairs(pop.roles) do
    local on = b.role == cur.role
    b.on:SetShown(on)
    b.label:SetTextColor(unpack(on and C.text or C.dim))
  end
  pop.title:SetText("Tip for " .. cur.boss)
  local s = siteTip(cur.slug, cur.boss, cur.role)
  pop.sub:SetText(s and ("Replaces the tip by " .. (s[5] ~= "" and s[5] or "a guildmate") .. ". Older versions stay in the website's history.")
    or "No tip for this role yet.")
end

local function setRole(role)
  cur.role = role
  pop.edit:SetText(current(role))
  refresh()
end

local function save()
  local text = (pop.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s*\n%s*", " ")
  if text == "" then ns.say("Write something first. To remove a tip, ask an officer (on the website).", true); return end
  if text:find("https?://") or text:find("www%.") then ns.say("Tips can't contain links.", true); return end
  local list = outbox()
  for i = #list, 1, -1 do
    local t = list[i]
    if t.d == cur.slug and t.b == cur.boss and t.r == cur.role then table.remove(list, i) end
  end
  list[#list + 1] = { d = cur.slug, b = cur.boss, r = cur.role, t = text:sub(1, MAX), by = ns.CharKey(), at = GetServerTime() }
  pop:Hide()
  ns.Changed()
  if ns.RefreshUI then ns.RefreshUI() end
  ns.SendNow("Tip saved. It goes to the website through the companion app.")
end

local function build()
  pop = CreateFrame("Frame", "FoxdenTipEditor", UIParent)
  pop:SetSize(W, 300); pop:SetPoint("CENTER"); pop:SetFrameStrata("DIALOG"); pop:SetClampedToScreen(true)
  pop:EnableMouse(true); pop:SetMovable(true); pop:RegisterForDrag("LeftButton")
  pop:SetScript("OnDragStart", pop.StartMoving); pop:SetScript("OnDragStop", pop.StopMovingOrSizing)
  UI.Fill(pop, C.bg); UI.Border(pop, { 1, 1, 1, 0.14 })
  tinsert(UISpecialFrames, "FoxdenTipEditor") -- Escape closes it
  pop.title = UI.Text(pop, 15); pop.title:SetPoint("TOPLEFT", 16, -14); pop.title:SetWidth(W - 60)
  UI.CloseButton(pop, function() pop:Hide() end):SetPoint("TOPRIGHT", -8, -8)

  pop.roles = {}
  local x = 16
  for _, r in ipairs(ROLES) do
    local b = CreateFrame("Button", nil, pop)
    b.role = r[1]
    b.label = UI.Text(b, 12, C.dim, "CENTER"); b.label:SetPoint("CENTER"); b.label:SetText(r[2])
    b:SetSize(math.floor(b.label:GetStringWidth() + 0.5) + 26, 26)
    UI.Fill(b, C.raised)
    b.on = b:CreateTexture(nil, "ARTWORK"); b.on:SetPoint("BOTTOMLEFT"); b.on:SetPoint("BOTTOMRIGHT"); b.on:SetHeight(2); UI.Accented(b.on)
    b:SetPoint("TOPLEFT", x, -44); x = x + b:GetWidth() + 4
    b:SetScript("OnClick", function() setRole(b.role) end)
    pop.roles[#pop.roles + 1] = b
  end

  local box = CreateFrame("Frame", nil, pop)
  box:SetPoint("TOPLEFT", 16, -80); box:SetPoint("TOPRIGHT", -16, -80); box:SetHeight(130)
  UI.Fill(box, C.surface); UI.Border(box)
  local scroll = CreateFrame("ScrollFrame", nil, box)
  scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true); edit:SetAutoFocus(false)
  edit:SetFont(UI.Font(), 13, ""); edit:SetTextColor(unpack(C.text))
  edit:SetWidth(W - 32 - 16)
  if edit.SetMaxLetters then edit:SetMaxLetters(MAX) end
  scroll:SetScrollChild(edit)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnTextChanged", function(self)
    pop.count:SetText(#(self:GetText() or "") .. " / " .. MAX)
  end)
  edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top = scroll:GetVerticalScroll()
    if -y < top then scroll:SetVerticalScroll(-y) elseif -y + h > top + scroll:GetHeight() then scroll:SetVerticalScroll(-y + h - scroll:GetHeight()) end
  end)
  box:EnableMouse(true); box:SetScript("OnMouseDown", function() edit:SetFocus() end)
  pop.edit = edit

  pop.count = UI.Text(pop, 11, C.faint, "RIGHT"); pop.count:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
  pop.sub = UI.Text(pop, 11, C.dim); pop.sub:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6); pop.sub:SetWidth(W - 110); pop.sub:SetWordWrap(true)
  local hint = UI.Text(pop, 11, C.faint); hint:SetPoint("BOTTOMLEFT", 16, 18); hint:SetWidth(W - 220); hint:SetWordWrap(true)
  hint:SetText("Shown with your character's name. No links.")
  local saveBtn = UI.Button(pop, "Save tip", 90, 26, save, "primary")
  saveBtn:SetPoint("BOTTOMRIGHT", -16, 12)
  local cancel = UI.Button(pop, "Cancel", 80, 26, function() pop:Hide() end)
  cancel:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
  pop:SetScript("OnHide", function() edit:ClearFocus() end)
end

function ns.OpenTipEditor(dungeonName, bossName, role)
  if not pop then build() end
  cur = { slug = ns.Slug(dungeonName), boss = bossName, role = role or "all" }
  setRole(cur.role)
  pop:Show()
  pop.edit:SetFocus()
end

ns.RegisterModule({
  name = "TipEditor",
  OnLoad = function() tidy() end,
})
