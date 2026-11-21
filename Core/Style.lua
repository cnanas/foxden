-- Foxden: shared look.
-- Flat dark surfaces, 1px hairlines, one accent color. When EllesmereUI is
-- installed, its skinning API hands us the player's accent color and UI font so
-- these windows sit comfortably next to the rest of their interface.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

UI.C = {
  bg       = { 0.055, 0.060, 0.072, 1 },
  surface  = { 0.085, 0.092, 0.108, 1 },
  raised   = { 0.115, 0.124, 0.145, 1 },
  hover    = { 1, 1, 1, 0.05 },
  line     = { 1, 1, 1, 0.08 },
  text     = { 0.93, 0.94, 0.96, 1 },
  dim      = { 0.60, 0.63, 0.69, 1 },
  faint    = { 0.42, 0.45, 0.50, 1 },
  danger   = { 0.94, 0.42, 0.42, 1 },
}
local FOX = { 0.498, 0.890, 0.769 } -- #7FE3C4

local skin -- EllesmereUI skin handle, when available
local accented = {} -- { region, alpha, kind }

function UI.Accent()
  if skin and skin.IsEnabled and skin.IsEnabled() and skin.GetAccentColor then
    local r, g, b = skin.GetAccentColor()
    if r then return r, g, b end
  end
  return FOX[1], FOX[2], FOX[3]
end

function UI.Font()
  if skin and skin.IsEnabled and skin.IsEnabled() and skin.GetFont then
    local path = skin.GetFont()
    if path then return path end
  end
  return STANDARD_TEXT_FONT
end

-- Paint a texture or font string in the accent color and keep it in sync.
function UI.Accented(region, alpha)
  accented[#accented + 1] = { region, alpha or 1 }
  local r, g, b = UI.Accent()
  if region.SetColorTexture then region:SetColorTexture(r, g, b, alpha or 1)
  else region:SetTextColor(r, g, b, alpha or 1) end
  return region
end

local texts = {}
local function recolor()
  local r, g, b = UI.Accent()
  for _, a in ipairs(accented) do
    local region, alpha = a[1], a[2]
    if region.SetColorTexture then region:SetColorTexture(r, g, b, alpha)
    else region:SetTextColor(r, g, b, alpha) end
  end
  local font = UI.Font()
  for _, t in ipairs(texts) do t.fs:SetFont(font, t.size, "") end
  if ns.RefreshUI then ns.RefreshUI() end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin(ADDON, function(S)
    skin = S
    if S.OnLooksChanged then S.OnLooksChanged(recolor) end
    recolor()
  end)
end

-- ---- primitives ------------------------------------------------------------

function UI.Fill(frame, color, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(unpack(color))
  return t
end

-- 1px hairline border drawn inside the frame
function UI.Border(frame, color)
  color = color or UI.C.line
  local edges = {}
  for i, pts in ipairs({
    { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
  }) do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(color))
    t:SetPoint(pts[1]); t:SetPoint(pts[2])
    if pts[3] then t:SetWidth(pts[3]) else t:SetHeight(pts[4]) end
    edges[i] = t
  end
  return edges
end

-- Make a texture round. Newer clients use a mask texture (the old SetMask(file) quietly does
-- nothing there, leaving it square); older ones SetMask.
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function UI.Round(owner, tex)
  if owner.CreateMaskTexture and tex.AddMaskTexture then
    local m = owner:CreateMaskTexture()
    m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)
    tex:AddMaskTexture(m)
  elseif tex.SetMask then
    pcall(tex.SetMask, tex, ROUND)
  end
end

function UI.Text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(UI.Font(), size, "")
  fs:SetTextColor(unpack(color or UI.C.text))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  texts[#texts + 1] = { fs = fs, size = size }
  return fs
end

-- Flat button. style: nil (quiet), "primary" (accent), "danger"
function UI.Button(parent, label, width, height, onClick, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 26)
  local bg = UI.Fill(b, style == "primary" and { 0, 0, 0, 0 } or UI.C.raised)
  if style == "primary" then UI.Accented(bg, 0.16) end
  UI.Border(b, UI.C.line)
  local hover = UI.Fill(b, UI.C.hover, "ARTWORK"); hover:Hide()
  b.label = UI.Text(b, 12, style == "danger" and UI.C.danger or UI.C.text, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  if style == "primary" then UI.Accented(b.label) end
  b:SetScript("OnEnter", function() hover:Show() end)
  b:SetScript("OnLeave", function() hover:Hide() end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Small square icon-less close button: an X drawn from two rotated lines
function UI.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  local hover = UI.Fill(b, UI.C.hover, "ARTWORK"); hover:Hide()
  for _, angle in ipairs({ 45, -45 }) do
    local l = b:CreateTexture(nil, "OVERLAY")
    l:SetColorTexture(unpack(UI.C.dim))
    l:SetSize(12, 1.5)
    l:SetPoint("CENTER")
    l:SetRotation(math.rad(angle))
  end
  b:SetScript("OnEnter", function() hover:Show() end)
  b:SetScript("OnLeave", function() hover:Hide() end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A settings row: title and description on the left, control on the right.
local function settingRow(parent, width, title, desc)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(width, desc and 52 or 40)
  row.title = UI.Text(row, 13)
  row.title:SetPoint("TOPLEFT", 0, desc and -10 or -13)
  row.title:SetText(title)
  if desc then
    row.desc = UI.Text(row, 11, UI.C.dim)
    row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.desc:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.desc:SetText(desc)
  end
  local sep = row:CreateTexture(nil, "BORDER")
  sep:SetColorTexture(unpack(UI.C.line))
  sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetHeight(1)
  return row
end

-- On/off switch. get() -> boolean, set(boolean)
function UI.Toggle(parent, width, title, desc, get, set)
  local row = settingRow(parent, width, title, desc)
  local sw = CreateFrame("Button", nil, row)
  sw:SetSize(38, 20)
  sw:SetPoint("RIGHT", 0, 0)
  local track = sw:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints()
  local knob = sw:CreateTexture(nil, "ARTWORK"); knob:SetSize(14, 14)
  UI.Border(sw, UI.C.line)
  function row:Refresh()
    local on = get()
    if on then
      local r, g, b = UI.Accent()
      track:SetColorTexture(r, g, b, 0.85)
      knob:SetColorTexture(0.05, 0.06, 0.07, 1)
      knob:ClearAllPoints(); knob:SetPoint("RIGHT", -3, 0)
    else
      track:SetColorTexture(unpack(UI.C.raised))
      knob:SetColorTexture(unpack(UI.C.dim))
      knob:ClearAllPoints(); knob:SetPoint("LEFT", 3, 0)
    end
  end
  sw:SetScript("OnClick", function() set(not get()); row:Refresh() end)
  row:EnableMouse(true)
  row:SetScript("OnMouseUp", function() set(not get()); row:Refresh() end)
  row:Refresh()
  return row
end

-- Key picker for a game binding. Click, then press a key (with Shift/Ctrl/Alt
-- if wanted) or a mouse button 3-5. Escape cancels, right-click clears.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

function UI.KeyBind(parent, width, title, desc, command)
  local row = settingRow(parent, width, title, desc)
  local b = UI.Button(row, "", 132, 24)
  b:SetPoint("RIGHT")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local listening = false

  local function current() return GetBindingKey and GetBindingKey(command) end
  function row:Refresh()
    if listening then b.label:SetText("Press a key...") return end
    local key = current()
    b.label:SetText(key and (GetBindingText and GetBindingText(key) or key) or "Not set")
    b.label:SetTextColor(unpack(key and UI.C.text or UI.C.dim))
  end
  local function stop()
    listening = false
    b:EnableKeyboard(false)
    row:Refresh()
  end
  local function save()
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
  end
  local function clear()
    for _, k in ipairs({ GetBindingKey(command) }) do SetBinding(k) end
  end
  local function bind(key)
    if InCombatLockdown and InCombatLockdown() then
      if ns.say then ns.say("Can't change keys in combat.", true) end
      return stop()
    end
    local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
      .. (IsShiftKeyDown() and "SHIFT-" or "") .. ((IsMetaKeyDown and IsMetaKeyDown()) and "META-" or "")
    local full = mods .. key
    local was = GetBindingAction and GetBindingAction(full)
    clear()
    if SetBinding(full, command) then
      -- remember the player chose this key (the fishing repair leaves chosen keys alone)
      ns.settings.keysChosen = ns.settings.keysChosen or {}
      ns.settings.keysChosen[command] = true
      save()
      if was and was ~= "" and was ~= command and ns.say then
        ns.say(full .. " was \"" .. (GetBindingName and GetBindingName(was) or was) .. "\" before; that action is now unbound.", true)
      end
    end
    stop()
  end

  b:SetScript("OnClick", function(_, mouse)
    if listening then return end
    if mouse == "RightButton" then
      if not (InCombatLockdown and InCombatLockdown()) then
        clear(); save()
        if ns.settings.keysChosen then ns.settings.keysChosen[command] = nil end
      end
      return row:Refresh()
    end
    listening = true
    b:EnableKeyboard(true)
    if b.SetPropagateKeyboardInput then b:SetPropagateKeyboardInput(false) end
    row:Refresh()
  end)
  b:SetScript("OnKeyDown", function(_, key)
    -- only after a click on the button: setting an OnKeyDown script can switch the frame's
    -- keyboard on, and then any key pressed (M for the map) was taken as the new binding
    if not listening then return end
    if MODIFIER_KEYS[key] then return end
    if key == "ESCAPE" then return stop() end
    bind(key)
  end)
  b:SetScript("OnMouseDown", function(_, mouse)
    if listening and MOUSE_KEYS[mouse] then bind(MOUSE_KEYS[mouse]) end
  end)
  b:EnableKeyboard(false)
  b:HookScript("OnHide", function() if listening then stop() end end)
  b:HookScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    GameTooltip:AddLine("Click, then press a key. Escape cancels. Right-click clears.", 0.6, 0.63, 0.69, true)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", GameTooltip_Hide)
  row:Refresh()
  return row
end

-- Pick one of a list of values with < and > arrows.
-- values = { {value, "label"}, ... }
function UI.Stepper(parent, width, title, desc, values, get, set)
  local row = settingRow(parent, width, title, desc)
  local box = CreateFrame("Frame", nil, row)
  box:SetSize(132, 24)
  box:SetPoint("RIGHT")
  UI.Fill(box, UI.C.raised); UI.Border(box)
  local label = UI.Text(box, 12, UI.C.text, "CENTER")
  label:SetPoint("CENTER")
  local function index()
    local cur = get()
    for i, v in ipairs(values) do if v[1] == cur then return i end end
    return 1
  end
  local function arrow(text, delta, point)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(24, 24); b:SetPoint(point)
    local hover = UI.Fill(b, UI.C.hover, "ARTWORK"); hover:Hide()
    local fs = UI.Text(b, 13, UI.C.dim, "CENTER"); fs:SetPoint("CENTER"); fs:SetText(text)
    b:SetScript("OnEnter", function() hover:Show() end)
    b:SetScript("OnLeave", function() hover:Hide() end)
    b:SetScript("OnClick", function()
      local i = math.max(1, math.min(#values, index() + delta))
      set(values[i][1]); row:Refresh()
    end)
    return b
  end
  local prev, nextB = arrow("<", -1, "LEFT"), arrow(">", 1, "RIGHT")
  function row:Refresh()
    local i = index()
    label:SetText(values[i][2])
    prev:SetAlpha(i > 1 and 1 or 0.3)
    nextB:SetAlpha(i < #values and 1 or 0.3)
  end
  row:Refresh()
  return row
end

function UI.SectionLabel(parent, text)
  local fs = UI.Text(parent, 11, nil)
  UI.Accented(fs)
  fs:SetText(text:upper())
  return fs
end

-- ---- formatting ------------------------------------------------------------

function UI.Time(s)
  s = math.max(0, math.floor((s or 0) + 0.5))
  local floor = math.floor
  if s >= 3600 then return string.format("%d:%02d:%02d", floor(s / 3600), floor((s % 3600) / 60), s % 60) end
  return string.format("%d:%02d", floor(s / 60), s % 60)
end

function UI.Num(n)
  n = n or 0
  if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n + 0.5))
end

function UI.ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.62, 0.65, 0.70
end

function UI.ClassName(class)
  if not class then return "" end
  if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] then
    return LOCALIZED_CLASS_NAMES_MALE[class]
  end
  return class:sub(1, 1) .. class:sub(2):lower()
end

-- "Name-Realm" and "Name" refer to the same player in stats and party lists
function UI.ShortName(name)
  return name and (name:gsub("%-.*$", "")) or "?"
end
