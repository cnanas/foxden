-- Foxden: shared look.
-- Flat surfaces, 1px hairlines, one accent color, in a dark or a light theme (Settings > Theme).
-- The palette tables in UI.C keep their identity; switching theme rewrites their values and
-- repaints everything drawn through UI.Fill / UI.Border / UI.Text / UI.RoundCorners (and
-- whatever registered with UI.OnTheme), so it changes live. When EllesmereUI is
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
local FOX = { 0.498, 0.890, 0.769 } -- #7FE3C4 (dark theme); the light theme uses a deeper teal

local THEMES = {
  dark = {
    bg = { 0.055, 0.060, 0.072, 1 }, surface = { 0.085, 0.092, 0.108, 1 }, raised = { 0.115, 0.124, 0.145, 1 },
    hover = { 1, 1, 1, 0.05 }, line = { 1, 1, 1, 0.08 },
    text = { 0.93, 0.94, 0.96, 1 }, dim = { 0.60, 0.63, 0.69, 1 }, faint = { 0.42, 0.45, 0.50, 1 },
    danger = { 0.94, 0.42, 0.42, 1 }, accent = { 0.498, 0.890, 0.769 },
  },
  light = {
    bg = { 0.925, 0.910, 0.885, 1 }, surface = { 0.985, 0.978, 0.965, 1 }, raised = { 0.895, 0.880, 0.855, 1 },
    hover = { 0, 0, 0, 0.045 }, line = { 0, 0, 0, 0.11 },
    text = { 0.11, 0.11, 0.13, 1 }, dim = { 0.28, 0.29, 0.33, 1 }, faint = { 0.33, 0.34, 0.38, 1 },
    danger = { 0.78, 0.22, 0.22, 1 }, accent = { 0.07, 0.50, 0.42 },
  },
}
UI.theme = "dark"
function UI.IsLight() return UI.theme == "light" end

-- ---- contrast (WCAG AA: 4.5:1 for text) ------------------------------------------------------
-- In the light theme, any text color too pale for the light background (class colors, gold,
-- the accent, colors written into text as |cff codes) is darkened, same hue, until it passes.
local function channel(c) c = math.max(0, math.min(1, c)); return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function luminance(r, g, b) return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b) end
UI.Luminance = luminance
-- the darkest background text sits on in the light theme: list panels (the page darkened 12%,
-- luminance about 0.60). Text at least 4.5:1 against that passes on every lighter surface too.
local DARKEST_BG_L = 0.60
local MAX_L = (DARKEST_BG_L + 0.05) / 4.5 - 0.05
function UI.Readable(r, g, b)
  if UI.theme ~= "light" or not r then return r, g, b end
  if luminance(r, g, b) <= MAX_L then return r, g, b end
  local lo, hi = 0, 1 -- scale toward black until it passes
  for _ = 1, 14 do
    local mid = (lo + hi) / 2
    if luminance(r * mid, g * mid, b * mid) <= MAX_L then lo = mid else hi = mid end
  end
  return r * lo, g * lo, b * lo
end
local function readableHex(hex)
  local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  r, g, b = UI.Readable(r, g, b)
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function UI.ReadableText(text)
  if UI.theme ~= "light" or type(text) ~= "string" or not text:find("|c", 1, true) then return text end
  return (text:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, rgb) return "|c" .. a .. readableHex(rgb) end))
end

-- what's painted in a palette color, so a theme switch can repaint it: { region, colorTable, kind }
local themed, themeHooks = {}, {}
local function roleColor(color)
  for _, v in pairs(UI.C) do if v == color then return true end end
  return false
end
local trackedAt = setmetatable({}, { __mode = "k" }) -- region -> its entry, so it's tracked once
local function track(region, color, kind)
  if not (color and roleColor(color)) then return end
  local e = trackedAt[region]
  if e then e[2], e[3] = color, kind; return end
  e = { region, color, kind }
  themed[#themed + 1] = e; trackedAt[region] = e
end
-- paint a texture in a palette color and keep it painted through theme switches
function UI.Paint(tex, color) tex:SetColorTexture(unpack(color)); track(tex, color, "tex") end
UI.Track = track
-- run fn now and again whenever the theme changes
function UI.OnTheme(fn) themeHooks[#themeHooks + 1] = fn; fn() end

local skin -- EllesmereUI skin handle, when available
local accented = {} -- { region, alpha, kind }

function UI.Accent()
  if skin and skin.IsEnabled and skin.IsEnabled() and skin.GetAccentColor then
    local r, g, b = skin.GetAccentColor()
    if r then return r, g, b end
  end
  local a = THEMES[UI.theme].accent
  return a[1], a[2], a[3]
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
  track(t, color, "tex")
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
    track(t, color, "tex")
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

local function readableFontString(fs)
  local setColor, setText = fs.SetTextColor, fs.SetText
  fs.SetTextColor = function(self, r, g, b, a)
    self._rgb = { r, g, b, a } -- as asked, so a theme switch can redo it
    local rr, gg, bb = UI.Readable(r, g, b)
    return setColor(self, rr, gg, bb, a)
  end
  fs.SetText = function(self, text)
    self._raw = text
    return setText(self, UI.ReadableText(text))
  end
  fs.RefreshReadable = function(self)
    if self._rgb then local c = self._rgb; local rr, gg, bb = UI.Readable(c[1], c[2], c[3]); setColor(self, rr, gg, bb, c[4]) end
    if self._raw ~= nil then setText(self, UI.ReadableText(self._raw)) end
  end
end
local readables = setmetatable({}, { __mode = "k" })

function UI.Text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  readableFontString(fs); readables[fs] = true
  fs:SetFont(UI.Font(), size, "")
  fs:SetTextColor(unpack(color or UI.C.text))
  track(fs, color or UI.C.text, "text")
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
    UI.Paint(l, UI.C.dim)
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
  UI.Paint(sep, UI.C.line)
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
      UI.Paint(track, UI.C.raised)
      UI.Paint(knob, UI.C.dim)
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

-- A class's icon on a texture (the game's class icon sheet). Returns false for an unknown class.
-- round = the game's round class icons (target frames). Never mask these: newer clients error
-- when a masked texture's tex coords are set.
function UI.ClassIconSpec(class, round)
  local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if not c then return nil end
  if round then return { "Interface\\TargetingFrame\\UI-Classes-Circles", c[1], c[2], c[3], c[4] } end
  -- the square sheet: trim its border a little
  local dx, dy = (c[2] - c[1]) * 0.06, (c[4] - c[3]) * 0.06
  return { "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", c[1] + dx, c[2] - dx, c[3] + dy, c[4] - dy }
end
function UI.SetClassIcon(tex, class, round)
  local spec = UI.ClassIconSpec(class, round)
  if not spec then return false end
  tex:SetTexture(spec[1]); tex:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
  return true
end

-- Run one part of a page. If it fails, the rest of the page still draws, and the error is said
-- in chat once (the game hides Lua errors unless you turn them on), so it can be reported.
local guardSeen = {}
function UI.Guard(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local msg = label .. ": " .. tostring(err)
    if not guardSeen[msg] then
      guardSeen[msg] = true
      if ns.say then ns.say("|cffef6b6bSomething went wrong drawing " .. msg .. "|r", true) end
    end
  end
  return ok
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

-- Switch theme ("dark" or "light"): rewrite the palette's values and repaint.
function UI.ApplyTheme(name)
  name = THEMES[name] and name or "dark"
  UI.theme = name
  for role, v in pairs(THEMES[name]) do
    local c = UI.C[role]
    if c then for i = 1, #v do c[i] = v[i] end end
  end
  for _, e in ipairs(themed) do
    local region, color, kind = e[1], e[2], e[3]
    if kind == "text" then region:SetTextColor(unpack(color))
    elseif kind == "vertex" then region:SetVertexColor(unpack(color))
    else region:SetColorTexture(unpack(color)) end
  end
  for _, fn in ipairs(themeHooks) do pcall(fn) end
  for fs in pairs(readables) do pcall(fs.RefreshReadable, fs) end
  recolor() -- accent-colored regions, then the open page
end
