-- Foxden: picture cards and tiles for the overview pages (rounded, Apple-tile style).
-- A big picture card. The art fills the card (cropped to its shape), with darkened top
-- and bottom bands for text: a title top left, a tag top right (e.g. "3/5 quests"), and lines
-- bottom left and bottom right. Used for the dungeon and raid grid, and the other overview pages.
--
--   local c = UI.ArtCard(parent)
--   c:Set({ art = { fileDataID, "lore" | "screen" | "prof" } or "Interface\\path", title, icon, tag, tagDone, bottomLeft, bottomRight, dim })
--   c:SetSize(w, h)   (call Set again, or c:Crop(), after resizing so the art is re-cropped)
--   c.onClick = function(card, button) end

local _, ns = ...
local UI = ns.UI
local C = UI.C

-- Where the picture sits in each kind of art file (0..1), so it can be cropped to the card.
--   lore:   the dungeon journal's 512x512 file; the scene is inside a frame at x 34..356, y 44..292
--   screen: Forever's 2992x1684 loading screens, letterboxed: the scene is y 0.157..0.843
local AREAS = {
  lore = { l = 34 / 512, r = 356 / 512, t = 44 / 512, b = 292 / 512, px = 322 / 248 },
  screen = { l = 0, r = 1, t = 0.157, b = 0.843, px = 2992 / (1684 * 0.686) },
  -- prof:   the profession window backgrounds (1024x1024; the picture is the top-left 677x546)
  prof = { l = 0, r = 677 / 1024, t = 2 / 1024, b = 548 / 1024, px = 677 / 546 },
  -- square: a square picture (a 256px map tile), cropped to the card's shape
  square = { l = 0, r = 1, t = 0, b = 1, px = 1 },
  full = { l = 0, r = 1, t = 0, b = 1, px = nil },
}

-- texcoords that fill a w x h card from an area, cropping the middle (cover, not stretch)
local function cover(area, w, h)
  local l, r, t, b = area.l, area.r, area.t, area.b
  local px = area.px
  if not px or w <= 0 or h <= 0 then return l, r, t, b end
  local want = w / h
  if want > px then
    -- card is wider than the art: use the full width, a band of the height
    local keep = (b - t) * px / want
    local mid = (t + b) / 2
    return l, r, mid - keep / 2, mid + keep / 2
  else
    local keep = (r - l) * want / px
    local mid = (l + r) / 2
    return mid - keep / 2, mid + keep / 2, t, b
  end
end

local function shade(tex, fromA, toA, vertical)
  -- a dark fade (newer clients: SetGradient with colors; older: SetGradientAlpha)
  tex:SetColorTexture(1, 1, 1, 1)
  local ok = false
  if CreateColor and tex.SetGradient then
    ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(0, 0, 0, toA), CreateColor(0, 0, 0, fromA))
  end
  if not ok and tex.SetGradientAlpha then ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL", 0, 0, 0, toA, 0, 0, 0, fromA) end
  if not ok then tex:SetColorTexture(0, 0, 0, math.max(fromA, toA) * 0.8) end
end

-- For other code (the window's art banner and stone look): crop coords, and a dark fade.
function UI.CoverCoords(kind, w, h) return cover(AREAS[kind] or AREAS.full, w, h) end
UI.Shade = shade

-- Rounded corners: four small pieces in the background colour laid over a frame's corners
-- (WoW can't round a frame itself). radius in pixels; color = what's behind the frame.
local CORNER = "Interface\\AddOns\\Foxden\\Media\\corner"
function UI.RoundCorners(f, radius, color)
  radius = radius or 8
  color = color or C.bg
  f.corners = f.corners or {}
  local spots = {
    { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
    { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
  }
  for i, sp in ipairs(spots) do
    local t = f.corners[i] or f:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture(CORNER); t:SetTexCoord(sp[2], sp[3], sp[4], sp[5])
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    if UI.Track and not t.tracked then UI.Track(t, color, "vertex"); t.tracked = true end
    t:SetSize(radius, radius); t:ClearAllPoints(); t:SetPoint(sp[1])
    f.corners[i] = t
  end
end

-- A plain rounded tile: a small title, a big value, a line or two under it, an optional icon top
-- right, and the whole tile clickable. For the overview pages.
--   local t = UI.Tile(parent); t:Set({ title, big, body, icon = texture or { texture, l, r, t, b } })
function UI.Tile(parent)
  local t = CreateFrame("Button", nil, parent)
  t:RegisterForClicks("LeftButtonUp")
  -- a little see-through, so the window's stone and art read faintly through it
  t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints()
  UI.OnTheme(function() t.bg:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], UI.IsLight() and 0.92 or 0.86) end)
  t.sheen = t:CreateTexture(nil, "BACKGROUND", nil, 1); t.sheen:SetPoint("TOPLEFT"); t.sheen:SetPoint("TOPRIGHT"); t.sheen:SetHeight(46)
  t.sheen:SetColorTexture(1, 1, 1, 1)
  if not (CreateColor and t.sheen.SetGradient and pcall(t.sheen.SetGradient, t.sheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.045))) then t.sheen:Hide() end
  t.hl = t:CreateTexture(nil, "HIGHLIGHT"); t.hl:SetAllPoints(); t.hl:SetColorTexture(1, 1, 1, 0.035)
  t.title = UI.Text(t, 12, C.dim); t.title:SetPoint("TOPLEFT", 16, -14)
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(34, 34); t.icon:SetPoint("TOPRIGHT", -14, -12); t.icon:Hide()
  t.big = t:CreateFontString(nil, "OVERLAY"); t.big:SetFont(UI.Font(), 30, ""); t.big:SetPoint("TOPLEFT", 16, -34)
  t.big:SetJustifyH("LEFT"); t.big:SetTextColor(unpack(C.text))
  t.unit = UI.Text(t, 13, C.dim); t.unit:SetPoint("BOTTOMLEFT", t.big, "BOTTOMRIGHT", 6, 4)
  t.body = UI.Text(t, 12, C.dim); t.body:SetWordWrap(true); t.body:SetJustifyV("TOP")
  t.body:SetPoint("TOPLEFT", t.big, "BOTTOMLEFT", 0, -8); t.body:SetPoint("RIGHT", -16, 0)
  UI.RoundCorners(t, 8)
  t:SetScript("OnClick", function(self, b) if self.onClick then self.onClick(self, b) end end)
  t:SetScript("OnEnter", function(self) if self.onEnter then self.onEnter(self) end end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function t:Set(o)
    o = o or {}
    self.title:SetText(o.title or "")
    self.big:SetText(o.big or ""); self.unit:SetText(o.unit or "")
    self.body:SetText(o.body or "")
    if o.bigColor then self.big:SetTextColor(unpack(o.bigColor)) else self.big:SetTextColor(unpack(C.text)) end
    local ic = o.icon
    if ic then
      if type(ic) == "table" then self.icon:SetTexture(ic[1]); self.icon:SetTexCoord(ic[2] or 0, ic[3] or 1, ic[4] or 0, ic[5] or 1)
      else self.icon:SetTexture(ic); self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
      self.icon:Show()
    else self.icon:Hide() end
  end
  return t
end

function UI.ArtCard(parent)
  local c = CreateFrame("Button", nil, parent)
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(); UI.Paint(c.bg, C.raised)
  c.art = c:CreateTexture(nil, "BORDER"); c.art:SetPoint("TOPLEFT", 1, -1); c.art:SetPoint("BOTTOMRIGHT", -1, 1)
  c.top = c:CreateTexture(nil, "ARTWORK"); c.top:SetPoint("TOPLEFT", 1, -1); c.top:SetPoint("TOPRIGHT", -1, -1); c.top:SetHeight(40)
  shade(c.top, 0.75, 0)
  c.bot = c:CreateTexture(nil, "ARTWORK"); c.bot:SetPoint("BOTTOMLEFT", 1, 1); c.bot:SetPoint("BOTTOMRIGHT", -1, 1); c.bot:SetHeight(34)
  shade(c.bot, 0, 0.75)
  c.line = c:CreateTexture(nil, "OVERLAY"); c.line:SetPoint("BOTTOMLEFT", 1, 1); c.line:SetPoint("BOTTOMRIGHT", -1, 1); c.line:SetHeight(2)
  UI.Accented(c.line, 0.85)
  UI.RoundCorners(c, 8)
  c.hl = c:CreateTexture(nil, "HIGHLIGHT"); c.hl:SetAllPoints(); c.hl:SetColorTexture(1, 1, 1, 0.07)

  c.title = c:CreateFontString(nil, "OVERLAY"); c.title:SetFont(UI.Font(), 17, "OUTLINE"); c.title:SetPoint("TOPLEFT", 12, -10)
  c.title:SetJustifyH("LEFT"); c.title:SetWordWrap(false); c.title:SetTextColor(1, 0.88, 0.62)
  c.icon = c:CreateTexture(nil, "OVERLAY"); c.icon:SetSize(30, 30); c.icon:SetPoint("TOPLEFT", 12, -10)
  c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); c.icon:Hide()
  c.tag = c:CreateFontString(nil, "OVERLAY"); c.tag:SetFont(UI.Font(), 12, "OUTLINE"); c.tag:SetPoint("TOPRIGHT", -12, -13)
  c.tag:SetJustifyH("RIGHT"); c.tag:SetTextColor(0.92, 0.92, 0.92)
  c.done = c:CreateTexture(nil, "OVERLAY"); c.done:SetSize(16, 16); c.done:SetPoint("RIGHT", c.tag, "LEFT", -4, 0)
  c.done:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  c.bl = c:CreateFontString(nil, "OVERLAY"); c.bl:SetFont(UI.Font(), 12, "OUTLINE"); c.bl:SetPoint("BOTTOMLEFT", 12, 9)
  c.bl:SetJustifyH("LEFT"); c.bl:SetTextColor(0.95, 0.95, 0.95)
  c.br = c:CreateFontString(nil, "OVERLAY"); c.br:SetFont(UI.Font(), 11, "OUTLINE"); c.br:SetPoint("BOTTOMRIGHT", -12, 9)
  c.br:SetJustifyH("RIGHT"); c.br:SetTextColor(0.85, 0.86, 0.9)
  c.title:SetPoint("RIGHT", c.tag, "LEFT", -24, 0)

  c:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
  c:SetScript("OnEnter", function(self) if self.onEnter then self.onEnter(self) end end)
  c:SetScript("OnLeave", function(self) GameTooltip:Hide(); if self.onLeave then self.onLeave(self) end end)

  function c:Crop()
    local area = self.area
    if not area then return end
    local w, h = self:GetWidth() - 2, self:GetHeight() - 2
    self.art:SetTexCoord(cover(area, w, h))
  end

  function c:Set(o)
    o = o or {}
    local art, kind = o.art, "full"
    self.art:SetDesaturated(o.dim and true or false)
    self.art:SetVertexColor(o.dim and 0.55 or 1, o.dim and 0.55 or 1, o.dim and 0.55 or 1)
    if type(art) == "table" then art, kind = art[1], art[2] or "full" end
    if art then
      local ok, r = pcall(self.art.SetTexture, self.art, art)
      self.hasArt = ok and r ~= false
    else
      self.hasArt = false
    end
    if not self.hasArt then
      -- no picture in this client: a plain tinted card
      self.art:SetTexture(nil); self.art:SetColorTexture(0.12, 0.12, 0.15, 1)
      self.area = nil; self.art:SetTexCoord(0, 1, 0, 1)
    else
      self.area = AREAS[kind] or AREAS.full
      self:Crop()
    end
    self.title:SetText(o.title or "")
    self.title:ClearAllPoints()
    if o.icon then
      self.icon:SetTexture(o.icon); self.icon:Show()
      self.title:SetPoint("LEFT", self.icon, "RIGHT", 10, 0)
    else
      self.icon:Hide(); self.title:SetPoint("TOPLEFT", 12, -10)
    end
    self.title:SetPoint("RIGHT", self.tag, "LEFT", -24, 0)
    self.tag:SetText(o.tag or "")
    self.done:SetShown(o.tagDone and true or false)
    self.bl:SetText(o.bottomLeft or "")
    self.br:SetText(o.bottomRight or "")
  end

  c:SetScript("OnSizeChanged", function(self) self:Crop() end)
  return c
end
