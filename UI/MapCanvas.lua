-- Foxden: a dungeon floor drawn with the game's own map art, plus numbered
-- pins. Used by the Journal page.
--   local m = UI.MapCanvas(parent)
--   m:Draw(uiMapID, width, height, pins, tiles)   tiles = client map picture prefix ("Interface\\WorldMap\\X\\X1_"), used when the map API has no art
--   pins = { { x = 0..1000, y = 0..1000, label, sub, n, on, class }, ... }   class: a class icon instead of n
--   returns true if the floor had map art

local _, ns = ...
local UI = ns.UI
local C = UI.C

function UI.MapCanvas(parent)
  local m = CreateFrame("Frame", nil, parent)
  m:SetClipsChildren(true)
  UI.Fill(m, C.surface)
  UI.Border(m)
  m.tiles, m.pins = {}, {}
  m.noArt = UI.Text(m, 12, C.faint, "CENTER"); m.noArt:SetPoint("CENTER")
  m.noArt:SetText("No map picture for this floor in this client")

  -- a click on the picture: m.onClick(x, y, button) with x, y in 0..1000
  m:EnableMouse(true)
  m:SetScript("OnMouseUp", function(self, button)
    if not self.onClick then return end
    local cx, cy = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    local left, top, w, h = self:GetLeft(), self:GetTop(), self:GetWidth(), self:GetHeight()
    if not (left and top and w > 0 and h > 0) then return end
    local x, y = (cx / scale - left) / w, (top - cy / scale) / h
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    self.onClick(math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5), button)
  end)

  local function tile(i)
    local t = m.tiles[i]
    if not t then t = m:CreateTexture(nil, "ARTWORK"); m.tiles[i] = t end
    return t
  end
  local function pin(i)
    local p = m.pins[i]
    if not p then
      p = CreateFrame("Button", nil, m)
      p:SetSize(20, 20)
      p.ring = p:CreateTexture(nil, "BORDER"); p.ring:SetPoint("TOPLEFT", -1, 1); p.ring:SetPoint("BOTTOMRIGHT", 1, -1); p.ring:SetColorTexture(0, 0, 0, 0.85)
      p.bg = p:CreateTexture(nil, "ARTWORK"); p.bg:SetAllPoints()
      p.num = UI.Text(p, 11, { 0.05, 0.06, 0.08, 1 }, "CENTER"); p.num:SetPoint("CENTER")
      p.icon = p:CreateTexture(nil, "OVERLAY"); p.icon:SetPoint("TOPLEFT", 1, -1); p.icon:SetPoint("BOTTOMRIGHT", -1, 1); p.icon:Hide()
      p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      p:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if m.onPinEnter then m.onPinEnter(s, GameTooltip) else
          GameTooltip:SetText(s.label or "Boss"); if s.sub then GameTooltip:AddLine(s.sub, 1, 1, 1, true) end
        end
        GameTooltip:Show()
      end)
      p:SetScript("OnLeave", GameTooltip_Hide)
      p:SetScript("OnClick", function(s, button) if m.onPin then m.onPin(s.key, button, s) end end)
      m.pins[i] = p
    end
    return p
  end

  function m:Draw(map, w, h, pins, tiles)
    self:SetSize(w, h)
    for _, t in ipairs(self.tiles) do t:Hide() end
    for _, p in ipairs(self.pins) do p:Hide() end
    local hasArt = false
    if map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
      local okL, layers = pcall(C_Map.GetMapArtLayers, map)
      local okT, textures = pcall(C_Map.GetMapArtLayerTextures, map, 1)
      if okL and type(layers) == "table" and layers[1] and okT and type(textures) == "table" and #textures > 0 then
        local layer = layers[1]
        local lw, lh = layer.layerWidth or 1002, layer.layerHeight or 668
        local tw, th = layer.tileWidth or 256, layer.tileHeight or 256
        local cols = math.max(1, math.ceil(lw / tw))
        local sx, sy = w / lw, h / lh
        for i, tex in ipairs(textures) do
          local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
          local t = tile(i)
          t:ClearAllPoints(); t:SetSize(tw * sx, th * sy)
          t:SetPoint("TOPLEFT", self, "TOPLEFT", col * tw * sx, -row * th * sy)
          t:SetTexture(tex); t:SetTexCoord(0, 1, 0, 1); t:Show()
        end
        hasArt = true
      end
    end
    -- no art from the map API: the client's own dungeon map picture, 12 tiles of 256px (4 x 3) over 1002 x 668
    if not hasArt and tiles then
      local sx, sy = w / 1002, h / 668
      for i = 1, 12 do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local t = tile(i)
        t:ClearAllPoints(); t:SetSize(256 * sx, 256 * sy)
        t:SetPoint("TOPLEFT", self, "TOPLEFT", col * 256 * sx, -row * 256 * sy)
        t:SetTexture(tiles .. i); t:SetTexCoord(0, 1, 0, 1); t:Show()
      end
      hasArt = true
    end
    self.noArt:SetShown(not hasArt)
    local r, g, b = UI.Accent()
    for i, p in ipairs(pins or {}) do
      local f = pin(i)
      f.key, f.label, f.sub = p.key, p.label, p.sub
      f:ClearAllPoints(); f:SetPoint("CENTER", self, "TOPLEFT", p.x / 1000 * w, -p.y / 1000 * h)
      if p.on then f.bg:SetColorTexture(r, g, b, 1) else f.bg:SetColorTexture(0.62, 0.65, 0.70, 1) end
      f.num:SetText(p.n or "")
      -- a class icon instead of the number (guildmates); the ring shows how fresh it is
      local icon = p.class and UI.SetClassIcon(f.icon, p.class)
      f.icon:SetShown(icon and true or false); f.num:SetShown(not icon)
      if icon then f.icon:SetDesaturated(not p.on); f.icon:SetAlpha(p.on and 1 or 0.6) end
      f:Show()
    end
    return hasArt
  end
  return m
end
