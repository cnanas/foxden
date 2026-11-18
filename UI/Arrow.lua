-- Foxden: the waypoint arrow. Points from you to a spot (a quest giver, a turn-in) wherever
-- you're facing, with the name and how far it is, and turns green as you head straight for it.
-- Within reach it says "Arrived" and goes away a few seconds later.
--   Click: target the NPC it leads to.  Right-click: stop.  Drag: move it (remembered).
-- Set from the quest tracker (right-click a quest), the quest details panel, the Dungeons page
-- ("Show on map"), and the world map (right-click a quest mark): ns.SetArrow(map, x, y, name).
-- The game's own map pin is set too where it works; Forever's isn't always reliable, so the
-- arrow uses world positions instead (the same ones as the minimap marks).
-- The arrow itself is an ordinary frame (it shows and hides any time). A secure button sits on
-- top of it so a click can target the NPC; the game only lets that change outside combat, so a
-- target set mid-fight becomes clickable once the fight ends.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local ARRIVED = 8 -- yards
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end -- (Lua 5.1 in game; 5.3 in tests)
local frame, clicker, target, pendingName

local function playerWorld()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
  local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not okM or type(map) ~= "number" or ns.IsSecret(map) then return nil end
  local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not okP or not pos then return nil end
  local px = pos:GetXY()
  if type(px) ~= "number" or ns.IsSecret(px) then return nil end
  local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
  if not ok or not cont or not v then return nil end
  local wx, wy = v:GetXY()
  return cont, wx, wy
end

local function setTargetName(name)
  if InCombatLockdown and InCombatLockdown() then pendingName = name or ""; return end
  pendingName = nil
  clicker:SetAttribute("type1", name and name ~= "" and "macro" or nil)
  clicker:SetAttribute("macrotext1", name and name ~= "" and ("/targetexact " .. name) or nil)
  clicker:SetShown(name ~= nil)
end

local function build()
  frame = CreateFrame("Frame", "FoxdenArrow", UIParent)
  frame:SetSize(56, 56)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true); frame:SetClampedToScreen(true)
  -- the click: a secure button over the arrow
  clicker = CreateFrame("Button", "FoxdenArrowClick", UIParent, "SecureActionButtonTemplate")
  clicker:SetAllPoints(frame)
  clicker:SetFrameStrata("MEDIUM"); clicker:SetFrameLevel(frame:GetFrameLevel() + 5)
  clicker:RegisterForClicks("AnyUp", "AnyDown")
  clicker:RegisterForDrag("LeftButton")
  clicker:Hide()
  local pos = ns.settings and ns.settings.arrowPos
  if pos then frame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
  frame.tex = frame:CreateTexture(nil, "ARTWORK"); frame.tex:SetAllPoints()
  frame.tex:SetTexture("Interface\\AddOns\\Foxden\\Media\\arrow")
  frame.name = frame:CreateFontString(nil, "OVERLAY"); frame.name:SetFont(UI.Font(), 13, "OUTLINE")
  frame.name:SetPoint("TOP", frame, "BOTTOM", 0, -2)
  frame.dist = frame:CreateFontString(nil, "OVERLAY"); frame.dist:SetFont(UI.Font(), 11, "OUTLINE")
  frame.dist:SetPoint("TOP", frame.name, "BOTTOM", 0, -2); frame.dist:SetTextColor(unpack(C.dim))
  clicker:SetScript("OnDragStart", function() if not (InCombatLockdown and InCombatLockdown()) then frame:StartMoving() end end)
  clicker:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, _, x, y = frame:GetPoint(1)
    ns.settings.arrowPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
  end)
  clicker:SetScript("PostClick", function(_, button) if button == "RightButton" then ns.ClearArrow() end end)
  clicker:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText(target and target.name or "Foxden arrow")
    if target and target.note then GameTooltip:AddLine(target.note, 1, 1, 1, true) end
    GameTooltip:AddLine("Click: target them. Right-click: stop. Drag: move.", 0.6, 0.63, 0.69, true)
    GameTooltip:Show()
  end)
  clicker:SetScript("OnLeave", GameTooltip_Hide)
  local acc, arrivedAt = 0, nil
  frame:SetScript("OnUpdate", function(s, elapsed)
    acc = acc + elapsed
    if acc < 0.03 or not target then return end
    acc = 0
    local cont, px, py = playerWorld()
    if not cont or not target.w or cont ~= target.w[1] then
      s.tex:SetAlpha(0.35); s.dist:SetText(cont and "On another continent" or "Can't tell where you are here")
      return
    end
    s.tex:SetAlpha(1)
    local north, west = target.w[2] - px, target.w[3] - py
    local d = math.sqrt(north * north + west * west)
    if d < ARRIVED then
      s.tex:SetVertexColor(0.43, 0.83, 0.6); s.dist:SetText("Arrived")
      arrivedAt = arrivedAt or GetTime()
      if GetTime() - arrivedAt > 4 then ns.ClearArrow() end
      return
    end
    arrivedAt = nil
    -- the target's bearing (anticlockwise from north), against the way you're facing
    local rel = atan2(west, north) - (GetPlayerFacing and GetPlayerFacing() or 0)
    s.tex:SetRotation(rel)
    -- straight ahead: green; behind you: red; in between: gold
    local off = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi) / math.pi
    if off < 0.5 then s.tex:SetVertexColor(0.43 + off * 1.1, 0.83, 0.6 - off * 1.2)
    else s.tex:SetVertexColor(1, 0.82 - (off - 0.5) * 1.2, 0.2) end
    s.dist:SetText(d >= 1000 and string.format("%.1f km", d / 1000) or (math.floor(d + 0.5) .. " yd"))
  end)
  frame:Hide()
end

-- Point at a spot: map ID, x and y in 0-100, the NPC's name (and a note for the tooltip).
function ns.SetArrow(map, x, y, name, note)
  if not (map and x and y) then return false end
  if not frame then build() end
  local ok, cont, v = false, nil, nil
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100)) end
  local w
  if ok and cont and v then local wx, wy = v:GetXY(); w = { cont, wx, wy } end
  target = { map = map, x = x, y = y, name = name or "", note = note, w = w }
  frame.name:SetText(name and name ~= "" and name or "Waypoint")
  frame.tex:SetVertexColor(1, 0.82, 0.2)
  setTargetName(name)
  frame:Show()
  return w ~= nil
end

function ns.ClearArrow()
  target = nil
  if frame then frame:Hide(); setTargetName(nil) end
end

ns.RegisterModule({
  name = "Arrow",
  events = {
    PLAYER_REGEN_ENABLED = function()
      if frame and pendingName then setTargetName(pendingName ~= "" and pendingName or nil) end
    end,
  },
})
