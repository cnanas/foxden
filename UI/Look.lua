-- Foxden: the window's look (Settings > Window look).
--   plain: flat dark surfaces.
--   stone: the game's own dark marble behind the pages and rock behind the sidebar (by file
--          ID), a soft light under the header, a warm-gold hairline, a faint vignette.
--   art:   stone, plus a dimmed picture across the top of each section that fades into it:
--          Home the dungeon for your level, Dungeons the open dungeon, Crafting your profession,
--          Guild a hall, Quests your zone's map. Pages can set their own (ns.SetBannerArt).

local _, ns = ...
local UI = ns.UI
local C = UI.C

local MARBLE, ROCK = 374154, 374155
local GOLD = { 0.86, 0.70, 0.42 }
local BANNER_H = 190

local L = {}
local bannerArt, sectionKey

local function look() return ns.settings and ns.settings.look or "art" end

local function tiled(parent, layer, sub, file, alpha)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(file, "REPEAT", "REPEAT")
  if t.SetHorizTile then t:SetHorizTile(true); t:SetVertTile(true) end
  t:SetAlpha(alpha)
  return t
end

function ns.BuildLook(W, header, side)
  -- pages: marble over the flat background
  L.marble = tiled(W, "BACKGROUND", 1, MARBLE, 0.55)
  L.marble:SetPoint("TOPLEFT", 1, -1); L.marble:SetPoint("BOTTOMRIGHT", -1, 1)
  -- sidebar: rock, a little darker
  L.rock = tiled(side, "BACKGROUND", 2, ROCK, 0.5)
  L.rock:SetAllPoints()
  L.rockShade = side:CreateTexture(nil, "BACKGROUND", nil, 3); L.rockShade:SetAllPoints(); L.rockShade:SetColorTexture(0, 0, 0, 0.35)
  -- header: a soft light falling from the top, and a gold hairline under it
  L.headLight = header:CreateTexture(nil, "BACKGROUND", nil, 2); L.headLight:SetAllPoints()
  UI.Shade(L.headLight, 0.0, 0.0)
  if CreateColor and L.headLight.SetGradient then
    pcall(L.headLight.SetGradient, L.headLight, "VERTICAL", CreateColor(1, 0.9, 0.7, 0), CreateColor(1, 0.9, 0.7, 0.06))
  end
  L.gold = header:CreateTexture(nil, "OVERLAY"); L.gold:SetHeight(1)
  L.gold:SetPoint("BOTTOMLEFT", 0, 0); L.gold:SetPoint("BOTTOMRIGHT", 0, 0)
  L.gold:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
  -- a faint vignette round the edges of the page area
  L.vig = {}
  for i, spot in ipairs({ { "TOP", "h" }, { "BOTTOM", "h" }, { "LEFT", "v" }, { "RIGHT", "v" } }) do
    local t = W.content:CreateTexture(nil, "BACKGROUND", nil, 5)
    t:SetColorTexture(1, 1, 1, 1)
    if spot[2] == "h" then t:SetHeight(60); t:SetPoint(spot[1] .. "LEFT"); t:SetPoint(spot[1] .. "RIGHT")
    else t:SetWidth(60); t:SetPoint("TOP" .. spot[1]); t:SetPoint("BOTTOM" .. spot[1]) end
    local dark, clear = CreateColor and CreateColor(0, 0, 0, 0.35), CreateColor and CreateColor(0, 0, 0, 0)
    local ok = false
    if dark and t.SetGradient then
      local dir = spot[2] == "h" and "VERTICAL" or "HORIZONTAL"
      -- VERTICAL goes bottom (min) to top (max); HORIZONTAL left (min) to right (max)
      local minC, maxC = clear, dark
      if spot[1] == "BOTTOM" or spot[1] == "LEFT" then minC, maxC = dark, clear end
      ok = pcall(t.SetGradient, t, dir, minC, maxC)
    end
    if not ok then t:SetColorTexture(0, 0, 0, 0.08) end
    L.vig[i] = t
  end
  -- the art banner, behind the top of the page, fading into the stone
  L.banner = W.content:CreateTexture(nil, "BACKGROUND", nil, 3)
  L.banner:SetPoint("TOPLEFT", 0, 0); L.banner:SetPoint("TOPRIGHT", 0, 0); L.banner:SetHeight(BANNER_H)
  L.bannerFade = W.content:CreateTexture(nil, "BACKGROUND", nil, 4)
  L.bannerFade:SetPoint("TOPLEFT", L.banner, "TOPLEFT"); L.bannerFade:SetPoint("BOTTOMRIGHT", L.banner, "BOTTOMRIGHT")
  L.bannerFade:SetColorTexture(1, 1, 1, 1)
  if CreateColor and L.bannerFade.SetGradient then
    pcall(L.bannerFade.SetGradient, L.bannerFade, "VERTICAL", CreateColor(C.bg[1], C.bg[2], C.bg[3], 1), CreateColor(C.bg[1], C.bg[2], C.bg[3], 0.45))
  else
    L.bannerFade:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.7)
  end
  L.W = W
  W.content:HookScript("OnSizeChanged", function() ns.ApplyLook() end)
  ns.ApplyLook()
end

-- The section's default picture.
local function defaultArt(key)
  if key == "home" or key == "dungeons" then
    local level = UnitLevel("player") or 1
    local best
    for id, d in pairs(ns.Dungeons or {}) do
      if not d.raid and d.levels and level >= d.levels[1] and level <= d.levels[2] and ns.DungeonArt and ns.DungeonArt[id] then
        if not best or d.levels[1] > best.levels[1] then best = d; best._id = id end
      end
    end
    return best and ns.DungeonArt[best._id] or (ns.DungeonArt and ns.DungeonArt[189])
  elseif key == "crafting" then
    local c = ns.Crafting and ns.Crafting()
    local me = c and c.chars and c.chars[ns.CharKey()]
    for name in pairs(me and me.professions or {}) do
      if ns.ProfessionArt and ns.ProfessionArt[name] then return { ns.ProfessionArt[name], "prof" } end
    end
    return { 4625448, "prof" } -- blacksmithing
  elseif key == "guild" then
    return { 7963781, "screen" } -- The Hall of Thanes
  elseif key == "questing" then
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local ok, tex = pcall(C_Map.GetMapArtLayerTextures, map, 1)
    if ok and type(tex) == "table" and tex[6] then return { tex[6], "square" } end
  end
end

function ns.SetSectionArt(key)
  sectionKey = key
  bannerArt = defaultArt(key)
  ns.ApplyLook()
end

-- A page can show its own picture (e.g. the open dungeon); nil goes back to the section's.
function ns.SetBannerArt(art)
  bannerArt = art or defaultArt(sectionKey)
  ns.ApplyLook()
end

function ns.ApplyLook()
  if not L.W then return end
  local mode = look()
  local stone = mode ~= "plain"
  L.marble:SetShown(stone); L.rock:SetShown(stone); L.rockShade:SetShown(stone)
  L.headLight:SetShown(stone); L.gold:SetShown(stone)
  for _, t in ipairs(L.vig) do t:SetShown(stone) end
  local art = mode == "art" and bannerArt
  if art then
    local file, kind = art, "full"
    if type(art) == "table" then file, kind = art[1], art[2] end
    local ok, r = pcall(L.banner.SetTexture, L.banner, file)
    if ok and r ~= false then
      local w = L.W.content:GetWidth() or 800
      L.banner:SetTexCoord(UI.CoverCoords(kind, w, BANNER_H))
      L.banner:SetAlpha(0.42); L.banner:SetDesaturated(false)
      L.banner:Show(); L.bannerFade:Show()
      return
    end
  end
  L.banner:Hide(); L.bannerFade:Hide()
end
