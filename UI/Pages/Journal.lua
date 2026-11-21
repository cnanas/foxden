-- Page: Dungeons. Pick a dungeon at the top; a header card shows its name, levels and who
-- wants to run it, with tabs for its Map, Bosses, Quests and the guild's Runs.
--   Bosses: a list of boss cards (round portrait with the boss's level, the guild's record) and,
--           for the one picked, its portrait, loot as item cards (loot that drops from many
--           bosses folded away), abilities and the guild's tips.
--   Quests: quest cards (level, faction, done or in your log); the picked one opens to show its
--           quest chain. The detail side shows the objective, where it starts and ends (with map
--           pins), where you are in the chain, the guild's note, rewards and a link to read more online.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, PICK_H, HEAD_H, GAP = 16, 28, 86, 12
local ROLE_TAG = { tank = "Tank", damage = "DPS", healer = "Healer", deadly = "Deadly", important = "Important",
  interruptible = "Interrupt", magic = "Magic", curse = "Curse", poison = "Poison", disease = "Disease", enrage = "Enrage" }
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SKULL_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

local page = { key = "journal", label = "Dungeons", order = 30 }
local selDungeon, selBoss, selFloor, selQuest
local placing -- { dungeon, i }: placing boss pins on the Map tab, boss i next
function ns.JournalDungeon() return selDungeon end
local jview = "bosses" -- or "map", "quests", "runs"
local showFaction -- { A = true/false, H = true/false }; starts as your own faction
local showShared, showChain, showLink = false, false, false

local function hex(r, g, b) return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end

-- A game texture by atlas name when this client has it, else a texture file.
local function art(tex, atlas, file, l, r, t, b)
  if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture(file)
    if l then tex:SetTexCoord(l, r, t, b) else tex:SetTexCoord(0, 1, 0, 1) end
  end
end
local function round(tex) UI.Round(tex:GetParent(), tex) end
local function crest(tex, f)
  if f == "A" then art(tex, "MountJournalIcons-Alliance", "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 0.625, 0, 0.625)
  else art(tex, "MountJournalIcons-Horde", "Interface\\TargetingFrame\\UI-PVP-Horde", 0, 0.625, 0, 0.625) end
end
local function questIcon(tex, state)
  if state == "done" then tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); tex:SetTexCoord(0, 1, 0, 1)
  elseif state == "have" then art(tex, "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon")
  else art(tex, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon") end
end

-- A flat panel: surface fill and a hairline border.
local function panel(parent)
  local p = CreateFrame("Frame", nil, parent)
  UI.Fill(p, C.surface); UI.Border(p)
  return p
end
local function heading(parent, text)
  local t = UI.Text(parent, 14); t:SetText(text); return t
end

-- ---- data --------------------------------------------------------------------------

-- Every Forever dungeon and raid (Data/Dungeons.lua), the game's journal when it has data,
-- and anything else you've run. Sorted by level like the game's dungeon list; raids last.
local function dungeonList()
  local list, bySlug = {}, {}
  local function entry(name)
    local k = ns.Slug(name)
    if not bySlug[k] then bySlug[k] = { name = name }; list[#list + 1] = bySlug[k] end
    return bySlug[k]
  end
  for _, d in pairs(ns.Dungeons or {}) do entry(d.name).static = d end
  for _, d in ipairs(ns.db and ns.db.journal and ns.db.journal.dungeons or {}) do entry(d.name).journal = d end
  for _, st in ipairs(ns.Stats.Dungeons()) do entry(st.name).stats = st end
  local function lvl(e) return e.static and e.static.levels and e.static.levels[1] or 99 end
  table.sort(list, function(a, b)
    local ra, rb = a.static and a.static.raid and 1 or 0, b.static and b.static.raid and 1 or 0
    if ra ~= rb then return ra < rb end
    if lvl(a) ~= lvl(b) then return lvl(a) < lvl(b) end
    return a.name < b.name
  end)
  return list
end

-- Dungeons and raids are picked separately (the Dungeons / Raids buttons beside the picker).
local kind = "dungeon"
-- The page opens on a grid of picture cards (one per dungeon or raid); clicking one opens it.
local grid = true
local function kindOf(e) return e.static and e.static.raid and "raid" or "dungeon" end
local function listOf(k)
  local out = {}
  for _, x in ipairs(dungeonList()) do if kindOf(x) == k then out[#out + 1] = x end end
  return out
end

local function levelsOf(e)
  local l = e.static and e.static.levels
  return l and #l == 2 and (l[1] .. "-" .. l[2]) or nil
end

-- Bosses: the journal's, or the ones killed in your runs. Pins: journal, else where the map recorder saw them.
local function bossesOf(e)
  local bosses = {}
  if e.journal then
    for i, b in ipairs(e.journal.bosses) do bosses[#bosses + 1] = { name = b.name, n = i, j = b, pins = b.pins } end
  else
    local seen = {}
    for _, r in ipairs(e.stats and e.stats.runs or {}) do
      for _, b in ipairs(r.bosses or {}) do
        if not seen[b.name] then seen[b.name] = true; bosses[#bosses + 1] = { name = b.name, n = #bosses + 1, pins = {} } end
      end
      for map, list in pairs(r.route and r.route.pins or {}) do
        for _, p in ipairs(list) do
          for _, b in ipairs(bosses) do if b.name == p.name and #b.pins == 0 then b.pins[1] = { m = tonumber(map), x = p.x, y = p.y } end end
        end
      end
    end
    -- the rest of the dungeon's bosses, in the game's order
    for _, b in ipairs(e.static and e.static.bosses or {}) do
      if not seen[b.name] then seen[b.name] = true; bosses[#bosses + 1] = { name = b.name, n = #bosses + 1, pins = {} } end
    end
  end
  -- level and rare flag (QuestieDB, Data/Dungeons.lua)
  local st = {}
  for _, b in ipairs(e.static and e.static.bosses or {}) do st[b.name] = b end
  for _, b in ipairs(bosses) do local x = st[b.name]; if x then b.level, b.rare = x.level, x.rare end end
  return bosses
end

-- Loot the website lists under 3 or more of a dungeon's bosses: world drops with a low chance,
-- folded away under "Show shared loot" so each boss shows its own loot first.
local sharedCache = {}
local function sharedOf(e)
  local site = ns.Site()
  local byBoss = site and type(site.loot) == "table" and site.loot[ns.Slug(e.name)]
  if type(byBoss) ~= "table" then return {} end
  local c = sharedCache[e.name]
  if c and c.src == byBoss then return c.set end
  local count, nb = {}, 0
  for _, list in pairs(byBoss) do
    nb = nb + 1
    local seen = {}
    for _, it in ipairs(type(list) == "table" and list or {}) do
      local id = type(it) == "table" and it[1]
      if id and not seen[id] then seen[id] = true; count[id] = (count[id] or 0) + 1 end
    end
  end
  local set = {}
  if nb >= 3 then for id, n in pairs(count) do if n >= 3 then set[id] = true end end end
  sharedCache[e.name] = { src = byBoss, set = set }
  return set
end

-- What a boss looks like: a display ID Foxden noted in a fight (or a guildmate's, from the
-- website), else its NPC ID (Data/Dungeons.lua, or learned in a fight).
local function visual(e, name)
  local look, npc
  local looks, npcs = ns.db and ns.db.bossLooks or {}, ns.db and ns.db.bossNpc or {}
  for _, b in ipairs(e.static and e.static.bosses or {}) do
    if b.name == name then
      npc = b.npc
      for _, id in ipairs(b.ids or {}) do look = look or looks[id]; npc = npc or npcs[id] end
    end
  end
  local site = ns.Site()
  for _, r in ipairs(site and type(site.bosses) == "table" and site.bosses[ns.Slug(e.name)] or {}) do
    if r[2] == name then
      if not look and (r[3] or 0) > 0 then look = r[3] end
      if not npc and (r[4] or 0) > 0 then npc = r[4] end
      look = look or looks[r[1]]; npc = npc or npcs[r[1]]
    end
  end
  for _, run in ipairs(e.stats and e.stats.runs or {}) do
    for _, k in ipairs(run.bosses or {}) do if k.name == name then look = look or k.look; npc = npc or k.npc end end
  end
  if not look and npc and ns.db and ns.db.npcLooks then look = ns.db.npcLooks[npc] end
  return look, npc
end

-- The flat boss portraits need a display ID; many bosses only have an NPC ID. A hidden model
-- loads each one once and reads its display ID, kept in FoxdenDB.npcLooks.
local resolver, queue, tried, dirty = nil, {}, {}, false
local function resolveNext()
  local npc = table.remove(queue, 1)
  if not npc then
    if resolver then resolver.busy = false end
    if dirty then dirty = false; if ns.RefreshUI then ns.RefreshUI() end; if ns.RefreshTracker then ns.RefreshTracker() end end
    return
  end
  resolver.busy, resolver.npc = true, npc
  local token = {}
  resolver.token = token
  if resolver.ClearModel then pcall(resolver.ClearModel, resolver) end
  if not pcall(resolver.SetCreature, resolver, npc) then return resolveNext() end
  -- no answer in time: skip it (reading the model now could give the previous creature's ID)
  C_Timer.After(2, function() if resolver.token == token then resolver.token = nil; resolveNext() end end)
end
local function resolveLooks(npcs)
  if not ns.db or #npcs == 0 or not CreateFrame then return end
  ns.db.npcLook = nil -- the first version saved wrong IDs
  ns.db.npcLooks = ns.db.npcLooks or {}
  if not resolver then
    resolver = CreateFrame("PlayerModel", nil, UIParent)
    resolver:SetSize(2, 2); resolver:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); resolver:SetAlpha(0)
    function resolver.finish()
      resolver.token = nil
      local ok, d = pcall(resolver.GetDisplayInfo, resolver)
      -- the same ID as the creature before is a stale read, not this one
      if ok and type(d) == "number" and d > 0 and d ~= resolver.last and resolver.npc then
        ns.db.npcLooks[resolver.npc] = d; resolver.last = d; dirty = true
      end
      resolveNext()
    end
    resolver:SetScript("OnModelLoaded", function() if resolver.token then resolver.finish() end end)
  end
  for _, npc in ipairs(npcs) do
    if not tried[npc] and not ns.db.npcLooks[npc] then tried[npc] = true; queue[#queue + 1] = npc end
  end
  if not resolver.busy then resolveNext() end
end
ns.ResolveNpcLooks = resolveLooks -- the dungeon tracker asks for its bosses too

local function floorsOf(e)
  if e.journal and #(e.journal.floors or {}) > 0 then
    for _, f in ipairs(e.journal.floors) do f.key = f.key or f.map; f.fid = f.fid or ("m" .. f.map) end
    return e.journal.floors
  end
  local list, seen = {}, {}
  for _, r in ipairs(e.stats and e.stats.runs or {}) do
    for _, f in ipairs(r.route and r.route.floors or {}) do
      local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(f.map)
      local isDungeonMap = not info or not info.mapType or info.mapType >= 4 -- 4 = dungeon, 5 = micro
      if isDungeonMap and not seen[f.map] and ns.MapHasArt and ns.MapHasArt(f.map) then seen[f.map] = true; list[#list + 1] = { key = f.map, fid = "m" .. f.map, map = f.map, name = f.name } end
    end
  end
  -- no journal, no runs yet: find the dungeon's map by name in the game's map list
  if #list == 0 and ns.DungeonFloors then list = ns.DungeonFloors(e.name) end
  return list
end

-- The guild's record against one boss, from fight breakdowns.
local function bossRecord(e, name)
  local kills, wipes, fastest = 0, 0, nil
  for _, r in ipairs(e.stats and e.stats.runs or {}) do
    for _, s in ipairs(r.segments or {}) do
      if s.kind == "boss" and s.label == name then
        if s.kill then kills = kills + 1; if not fastest or s.duration < fastest then fastest = s.duration end else wipes = wipes + 1 end
      end
    end
  end
  return kills, wipes, fastest
end
local function recordText(e, name)
  local kills, wipes, fastest = bossRecord(e, name)
  if kills + wipes == 0 then return "Not fought by the guild yet" end
  return string.format("%d %s, %d %s%s", kills, kills == 1 and "kill" or "kills", wipes, wipes == 1 and "wipe" or "wipes",
    fastest and (", fastest " .. UI.Time(fastest)) or "")
end

-- A boss's loot: the game's journal, drops the guild has seen, and the website's list.
local function lootOf(e, boss)
  local loot = {}
  if boss.j and #(boss.j.loot or {}) > 0 then
    for _, id in ipairs(boss.j.loot) do loot[#loot + 1] = { id = id } end
    return loot, nil
  end
  local count, order = {}, {}
  for _, r in ipairs(e.stats and e.stats.runs or {}) do
    for _, l in ipairs(r.loot or {}) do
      if l.b == boss.name and l.i then
        if not count[l.i] then order[#order + 1] = l.i end
        count[l.i] = (count[l.i] or 0) + 1
      end
    end
  end
  local site = ns.Site()
  local listed = site and type(site.loot) == "table" and site.loot[ns.Slug(e.name)] and site.loot[ns.Slug(e.name)][boss.name]
  local names = {}
  for _, it in ipairs(listed or {}) do
    if type(it) == "table" and it[1] then
      names[it[1]] = it[2]
      if not count[it[1]] then order[#order + 1] = it[1]; count[it[1]] = 0 end
    end
  end
  for _, id in ipairs(order) do loot[#loot + 1] = { id = id, seen = count[id], name = names[id] } end
  local n = {}
  if #order == 0 then n[#n + 1] = "Nothing recorded yet. Foxden learns what this boss drops from the guild's runs: everything your group gets from it, not just what you loot." end
  if listed and #listed > 0 then n[#n + 1] = "Loot tables for classic dungeons: QuestieDB (GPLv3)." end
  if e.static then n[#n + 1] = "Boss list: ForeverDungeonRoutes by Checkov23 (MIT)." end
  return loot, table.concat(n, "\n")
end

-- Description, abilities and the guild's tips, as one block of text.
local function bossText(e, boss)
  local ar, ag, ab = UI.Accent()
  local head = hex(ar, ag, ab)
  local dim = hex(C.dim[1], C.dim[2], C.dim[3])
  local lines = {}
  local function section(title) lines[#lines + 1] = (#lines > 0 and "\n" or "") .. head .. title .. "|r" end
  local j = boss.j
  if j and j.desc and j.desc ~= "" then lines[#lines + 1] = j.desc end
  if j and #(j.sections or {}) > 0 then
    section("Abilities")
    for _, s in ipairs(j.sections) do
      local tags = {}
      for flag in (s.flags or ""):gmatch("[^,]+") do if ROLE_TAG[flag] then tags[#tags + 1] = "[" .. ROLE_TAG[flag] .. "]" end end
      lines[#lines + 1] = string.rep("    ", s.depth or 0) .. "• |cffffffff" .. (s.t or "") .. "|r" .. (#tags > 0 and ("  " .. dim .. table.concat(tags, " ") .. "|r") or "")
      if s.d and s.d ~= "" then lines[#lines + 1] = string.rep("    ", (s.depth or 0) + 1) .. dim .. s.d .. "|r" end
    end
  end
  local site = ns.Site()
  local tips = {}
  for _, t in ipairs(site and site.tips or {}) do
    if t[1] == ns.Slug(e.name) and t[2] == boss.name then tips[#tips + 1] = t end
  end
  -- yours written in game, on their way to the website: they replace that role's tip here
  local pending = ns.PendingTips and ns.PendingTips(ns.Slug(e.name), boss.name) or {}
  for i = #tips, 1, -1 do if pending[tips[i][3]] then table.remove(tips, i) end end
  for role, p in pairs(pending) do tips[#tips + 1] = { p.d, p.b, role, p.t, "you, on its way to the website" } end
  section("Guild tips")
  if #tips > 0 then
    local order = { tank = 1, damage = 2, healer = 3, all = 4 }
    table.sort(tips, function(a, b) return (order[a[3]] or 9) < (order[b[3]] or 9) end)
    for _, t in ipairs(tips) do
      lines[#lines + 1] = "|cffffffff" .. (ROLE_TAG[t[3]] or "Everyone") .. ":|r " .. t[4] .. (t[5] and t[5] ~= "" and (dim .. "  (" .. t[5] .. ")|r") or "")
    end
  else
    lines[#lines + 1] = dim .. "No tips yet. Click Write a tip below, or add one on the website's Journal page.|r"
  end
  return table.concat(lines, "\n")
end

-- ---- item cards: the game's own item data (icon, quality colour, slot, tooltip) ---------
local waitingItems = false
local function itemLook(id, fallback)
  local name, link, quality, _, _, itype, subtype, _, equipLoc, _, _, classID
  if C_Item and C_Item.GetItemInfo then name, link, quality, _, _, itype, subtype, _, equipLoc, _, _, classID = C_Item.GetItemInfo(id)
  elseif GetItemInfo then name, link, quality, _, _, itype, subtype, _, equipLoc, _, _, classID = GetItemInfo(id) end
  if not name then
    waitingItems = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
  local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or 134400
  -- "Neck", "Wrist, Cloth", "One-Hand, Sword"
  local slot = equipLoc and equipLoc ~= "" and _G[equipLoc] or nil
  local kind = (classID == 2 or classID == 4) and subtype and subtype ~= "" and subtype ~= MISCELLANEOUS and subtype ~= "Miscellaneous" and subtype or nil
  local sub = slot and (kind and (slot .. ", " .. kind) or slot) or (itype ~= "" and itype or nil)
  return name or fallback or ("Item " .. id), link, quality, icon, sub
end
local function qualityRGB(quality)
  if quality and C_Item and C_Item.GetItemQualityColor then local r, g, b = C_Item.GetItemQualityColor(quality); return r or 1, g or 1, b or 1 end
  if quality and GetItemQualityColor then local r, g, b = GetItemQualityColor(quality); return r or 1, g or 1, b or 1 end
  return 1, 1, 1
end

local function itemCard(parent, h)
  local r = CreateFrame("Button", nil, parent); r:SetHeight(h or 46)
  UI.Fill(r, C.raised); UI.Border(r)
  local hover = UI.Fill(r, C.hover, "ARTWORK"); hover:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize((h or 46) - 12, (h or 46) - 12); r.icon:SetPoint("LEFT", 6, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = UI.Text(r, 13); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
  r.slot = UI.Text(r, 11, C.dim); r.slot:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 2)
  -- wishlist star (boss loot only)
  r.star = CreateFrame("Button", nil, r); r.star:SetSize(20, 20); r.star:SetPoint("RIGHT", -10, 0)
  r.star.tex = r.star:CreateTexture(nil, "ARTWORK"); r.star.tex:SetAllPoints()
  r.star.tex:SetTexture("Interface\\Common\\ReputationStar"); r.star.tex:SetTexCoord(0, 0.5, 0, 0.5)
  r.star:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.star:SetScript("OnClick", function(b, which)
    local row = b:GetParent()
    if not row.id or not row.wish then return end
    local name = row.itemName or row.name:GetText()
    local kind
    if which == "RightButton" then kind = ns.SetWish(row.id, nil) else kind = ns.CycleWish(row.id, name, row.wish.boss, row.wish.dungeon) end
    ns.say(kind and (name .. ": on your wishlist as " .. ns.WISH_LABEL[kind]:lower() .. ".") or (name .. " removed from your wishlist."))
    ns.RefreshUI()
  end)
  r.star:SetScript("OnEnter", function(b)
    local kind = ns.WishKind(b:GetParent().id)
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(kind and ("On your wishlist: " .. ns.WISH_LABEL[kind]) or "Add to your wishlist")
    GameTooltip:AddLine("Click to step through Main spec, Off spec, Transmog, off. Right-click removes it.", 1, 1, 1, true)
    GameTooltip:AddLine("Foxden reminds you at this boss, tells you when it drops, and shows guildmates what you want it for.", 0.7, 0.72, 0.78, true)
    GameTooltip:Show()
  end)
  r.star:SetScript("OnLeave", GameTooltip_Hide)
  r.star:Hide()
  r.seen = UI.Text(r, 11, C.dim, "RIGHT"); r.seen:SetPoint("RIGHT", r.star, "LEFT", -8, 0)
  r.name:SetPoint("RIGHT", r.seen, "LEFT", -8, 0); r.slot:SetPoint("RIGHT", r.seen, "LEFT", -8, 0)
  r:SetScript("OnEnter", function(self)
    if not self.id then return end
    hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.id) then GameTooltip:AddLine(self.name:GetText() or "") end
    GameTooltip:AddLine("Shift-click to link it in chat.", 0.6, 0.63, 0.69)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() hover:Hide(); GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if IsModifiedClick and IsModifiedClick("CHATLINK") and self.link and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
  end)
  return r
end
local function fillCard(r, id, fallback)
  local name, link, quality, icon, sub = itemLook(id, fallback)
  r.id, r.link, r.itemName = id, link, name
  r.icon:SetTexture(icon); r.name:SetText(name); r.name:SetTextColor(qualityRGB(quality))
  r.slot:SetText(sub or "")
  r.seen:SetText(""); r.star:Hide()
end

-- ---- quests (from the website: Blizzard's quest text and rewards, QuestieDB givers) -----
-- row: { id, title, faction, level, minLevel, giver, area, map, x, y, ender, objective, after, xp, money, rep, items, choice, text, endMap, endX, endY }
local function factionShown()
  if not showFaction then
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    showFaction = { A = mine ~= "Horde", H = mine ~= "Alliance" }
  end
  return showFaction
end
local hiddenProf = 0
local function questsOf(e)
  hiddenProf = 0
  local site = ns.Site()
  local rows = site and type(site.quests) == "table" and site.quests[ns.Slug(e.name)] or {}
  local sf = factionShown()
  local out = {}
  for _, q in ipairs(rows) do
    -- "B": either faction; "": not known yet (shown, so nothing is hidden by mistake)
    if type(q) == "table" and ns.Quests then q = ns.Quests.Enrich(q) end -- QuestieDB fills the gaps
    local lock, why
    if type(q) == "table" and ns.Quests then lock, why = ns.Quests.Locked(q[1]) end
    if type(q) == "table" and (q[3] == "" or q[3] == "B" or sf[q[3]]) then
      -- profession quests you can't take are left out (counted); race-locked ones are greyed
      if why == "profession" and not (ns.settings and ns.settings.showProfQuests) then hiddenProf = hiddenProf + 1
      else q.locked = lock; out[#out + 1] = q end
    end
  end
  return out, #rows
end

-- Where to read guides and player comments online: Wowhead's WoW Forever quest page. Same rule as
-- the website (site/lib/quests.ts questUrl).
function ns.QuestUrl(q)
  local slug = tostring(q[2] or ""):lower():gsub("’", ""):gsub("'", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return "https://www.wowhead.com/forever/quest=" .. q[1] .. (slug ~= "" and ("/" .. slug) or "")
end

-- The quest's chain ({ {id, title, giver, map, x, y, min level, faction, level}, ... }, this quest included), which step this quest is, and the
-- first step you haven't done (nil when you've done them all).
local function chainOf(q)
  local chain = q[23]
  if type(chain) ~= "table" or #chain < 2 then return nil end
  local k, cur
  for i, step in ipairs(chain) do
    if step[1] == q[1] then k = i end
    if not cur and not (ns.QuestState and ns.QuestState(step[1]) == "done") then cur = i end
  end
  return chain, k or 1, cur
end
-- The chain as numbered lines: done steps green with a tick, this quest in the accent colour,
-- the step you're on marked "you're here" (gold "in your log" when you already have it).
-- Long chains show the steps around this one.
local TICK = " |TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local HERE = "  |TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t|cffe8c35ayou're here|r"
local function chainLines(chain, k, cur)
  local ar, ag, ab = UI.Accent()
  local first, last = 1, #chain
  if #chain > 10 then first, last = math.max(1, k - 4), math.min(#chain, k + 4) end
  local out = {}
  if first > 1 then out[#out + 1] = "|cff6b7280   ...|r" end
  for i = first, last do
    local step = chain[i]
    local st = ns.QuestState and ns.QuestState(step[1])
    local line = i .. ". " .. tostring(step[2])
    local here = i == cur and st ~= "have" and HERE or ""
    if i == k then line = hex(ar, ag, ab) .. line .. "|r" .. (st == "done" and TICK or st == "have" and "|cffe8c35a  (in your log)|r" or here)
    elseif st == "done" then line = "|cff6fd39a" .. line .. "|r" .. TICK
    elseif st == "have" then line = "|cffe8c35a" .. line .. "  (in your log)|r"
    else line = "|cffc8ccd4" .. line .. "|r" .. here end
    out[#out + 1] = line
  end
  if last < #chain then out[#out + 1] = "|cff6b7280   ... " .. #chain .. " steps|r" end
  return table.concat(out, "\n")
end
local function questNote(q)
  local site = ns.Site()
  local notes = site and type(site.questNotes) == "table" and site.questNotes
  local n = notes and (notes[q[1]] or notes[tostring(q[1])])
  if type(n) == "table" and type(n[1]) == "string" and n[1] ~= "" then return n[1], n[2] end
end
local FACTION = { A = "Alliance", H = "Horde", B = "Both factions", [""] = "Faction not known yet" }
local function questLevel(q)
  if (q[4] or 0) == 0 then return "" end
  return "Level " .. q[4] .. (((q[5] or 0) > 0 and q[5] ~= q[4]) and (", from " .. q[5]) or "")
end

local function pinOnMap(map, x, y, name)
  if not (map and map > 0) then return false end
  -- the arrow (works everywhere), and the game's own pin where that works
  local ok = ns.SetArrow and ns.SetArrow(map, x, y, name) or false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and not (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map)) then
    pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
  end
  ns.say(string.format("Arrow to %s (%d, %d).", name, math.floor(x + 0.5), math.floor(y + 0.5)))
  return ok
end

-- ---- build ---------------------------------------------------------------------------

local function scrollArea(parent)
  local s = CreateFrame("ScrollFrame", nil, parent)
  s:EnableMouseWheel(true)
  local body = CreateFrame("Frame", nil, s)
  s:SetScrollChild(body)
  s:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  return s, body
end

function page:Build(f)
  self.f = f
  -- dungeon picker: < [dropdown] >
  local function step(d)
    local list = listOf(kind)
    for i, x in ipairs(list) do
      if x.name == selDungeon then
        local n = list[((i - 1 + d) % #list) + 1]
        selDungeon, selBoss, selFloor, selQuest = n.name, nil, nil, nil
        self:Refresh(); return
      end
    end
  end
  self.back = UI.Button(f, "< All " .. "dungeons", 120, PICK_H, function() grid = true; self:Refresh() end)
  self.back:SetPoint("TOPLEFT", 0, 0)
  self.prev = UI.Button(f, "<", 28, PICK_H, function() step(-1) end)
  self.picker = UI.Dropdown(f, 300, "Dungeon", function(v) selDungeon, selBoss, selFloor, selQuest = v, nil, nil, nil; grid = false; self:Refresh() end)
  self.picker:SetHeight(PICK_H)
  self.next = UI.Button(f, ">", 28, PICK_H, function() step(1) end)
  self.prev:SetPoint("LEFT", self.back, "RIGHT", 6, 0)
  self.picker:SetPoint("LEFT", self.prev, "RIGHT", 6, 0)
  self.next:SetPoint("LEFT", self.picker, "RIGHT", 6, 0)
  -- Dungeons | Raids
  self.kinds = {}
  for i, k in ipairs({ { "dungeon", "Dungeons" }, { "raid", "Raids" } }) do
    local b = UI.Button(f, k[2], 90, PICK_H, function()
      if kind == k[1] then return end
      kind = k[1]; selDungeon, selBoss, selFloor, selQuest = nil, nil, nil, nil
      grid = true
      self:Refresh()
    end)
    b.kind = k[1]
    if i == 1 then b:SetPoint("LEFT", self.next, "RIGHT", 16, 0) else b:SetPoint("LEFT", self.kinds[1], "RIGHT", 4, 0) end
    self.kinds[i] = b
  end

  -- header card
  self.head = panel(f)
  self.title = UI.Text(self.head, 22); self.title:SetPoint("TOPLEFT", 16, -14)
  self.sub = UI.Text(self.head, 12, C.dim); self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
  self.lfgWho = UI.Text(self.head, 11, C.faint); self.lfgWho:SetPoint("TOPLEFT", self.sub, "BOTTOMLEFT", 0, -6)
  self.lfg = UI.Button(self.head, "I want to run this", 150, 24, function()
    if not selDungeon then return end
    local on = ns.ToggleLfg(ns.Slug(selDungeon))
    if on then ns.SendNow("You're listed as wanting " .. selDungeon .. ".")
    else ns.say("You're no longer listed for " .. selDungeon .. ".") end
    ns.RefreshUI()
  end)
  self.lfg:SetPoint("BOTTOMRIGHT", -14, 12)
  -- loot filter (boss loot and trash drops)
  self.filterBtn = UI.Button(self.head, "Loot filter", 110, 24, function(b) if ns.LootFilter then ns.LootFilter.Toggle(b) end end)
  self.filterBtn:SetPoint("RIGHT", self.lfg, "LEFT", -8, 0)
  -- the dungeon's entrance: the arrow points there, and the world map opens on it
  self.entranceBtn = UI.Button(self.head, "Entrance", 90, 24, function()
    local e = self.entry
    local map, x, y = e and ns.DungeonEntrance and ns.DungeonEntrance(e.name)
    if not map then ns.say("Foxden doesn't know where " .. (e and e.name or "this dungeon") .. "'s entrance is yet."); return end
    if ns.SetArrow then ns.SetArrow(map, x, y, e.name .. " entrance") end
    if OpenWorldMap then pcall(OpenWorldMap, map) end
    ns.say(string.format("Arrow to %s's entrance (%d, %d).", e.name, math.floor(x + 0.5), math.floor(y + 0.5)))
  end)

  -- Trash: items the dungeon's trash mobs drop (from QuestieDB, Core/Trash.lua)
  self.trashPanel = panel(f)
  self.trashHead = heading(self.trashPanel, "Trash drops"); self.trashHead:SetPoint("TOPLEFT", 14, -12)
  self.trashNote = UI.Text(self.trashPanel, 11, C.dim); self.trashNote:SetPoint("TOPLEFT", self.trashHead, "BOTTOMLEFT", 0, -6)
  self.trashNote:SetWordWrap(true)
  self.trashScroll, self.trashBody = scrollArea(self.trashPanel)
  self.trashRows = {}
  if ns.Trash then ns.Trash.OnReady(function() if self.trashPanel:IsVisible() then ns.RefreshUI() end end) end

  -- view tabs, with game icons
  self.viewTabs = {}
  local tabs = {
    { "map", "Map", function(t) t:SetTexture("Interface\\Icons\\INV_Misc_Map_01"); t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end },
    { "bosses", "Bosses", function(t) t:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull"); t:SetTexCoord(0, 1, 0, 1) end },
    { "quests", "Quests", function(t) questIcon(t, "new") end },
    { "trash", "Trash", function(t) t:SetTexture("Interface\\Icons\\INV_Misc_Bag_10"); t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end },
    { "runs", "Runs", function(t) t:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end },
  }
  for _, v in ipairs(tabs) do
    local b = CreateFrame("Button", nil, self.head)
    b.key = v[1]
    UI.Fill(b, C.raised); UI.Border(b)
    b.bg = b:CreateTexture(nil, "ARTWORK"); b.bg:SetAllPoints(); UI.Accented(b.bg, 0.14); b.bg:Hide()
    b.under = b:CreateTexture(nil, "OVERLAY"); b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
    b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 10, 0); v[3](b.icon)
    b.text = UI.Text(b, 12, C.dim); b.text:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
    b.text:SetText(v[2])
    b:SetSize(104, 30)
    local hover = UI.Fill(b, C.hover, "HIGHLIGHT")
    b:SetScript("OnClick", function() jview = v[1]; ns.RefreshUI() end)
    self.viewTabs[#self.viewTabs + 1] = b
  end

  -- Bosses: list on the left, the picked boss on the right
  self.bossPanel = panel(f)
  self.bossHead = heading(self.bossPanel, "Bosses"); self.bossHead:SetPoint("TOPLEFT", 14, -12)
  self.bosses = UI.List(self.bossPanel, 68, function(r)
    r.tint = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.tint:SetAllPoints(); UI.Accented(r.tint, 0.10); r.tint:Hide()
    r.ring = r:CreateTexture(nil, "ARTWORK"); r.ring:SetSize(54, 54); r.ring:SetPoint("LEFT", 14, 0)
    r.ring:SetColorTexture(1, 1, 1, 0.22); round(r.ring)
    -- Masked textures can't be changed much afterwards (the game refuses tex coords on them),
    -- so only textures that never change get a mask. The portrait the game makes is round already.
    r.por = r:CreateTexture(nil, "ARTWORK", nil, 1); r.por:SetSize(50, 50); r.por:SetPoint("CENTER", r.ring)
    r.skull = r:CreateTexture(nil, "ARTWORK", nil, 1); r.skull:SetSize(50, 50); r.skull:SetPoint("CENTER", r.ring)
    r.skull:SetTexture(SKULL_ICON); round(r.skull)
    -- the boss's level, in a badge on the portrait
    r.badgeRing = r:CreateTexture(nil, "OVERLAY"); r.badgeRing:SetSize(24, 24); r.badgeRing:SetPoint("BOTTOMLEFT", r.ring, "BOTTOMLEFT", -5, -5)
    UI.Accented(r.badgeRing); round(r.badgeRing)
    r.badge = r:CreateTexture(nil, "OVERLAY", nil, 1); r.badge:SetSize(21, 21); r.badge:SetPoint("CENTER", r.badgeRing)
    r.badge:SetColorTexture(unpack(C.bg)); round(r.badge)
    r.num = UI.Text(r, 10, C.text, "CENTER"); r.num:SetPoint("CENTER", r.badge, "CENTER", 0, 0); r.num:SetDrawLayer("OVERLAY", 2)
    r.rare = UI.Text(r, 10, C.dim, "RIGHT"); r.rare:SetPoint("TOPRIGHT", -14, -14); r.rare:SetText("RARE"); UI.Accented(r.rare)
    r.name = UI.Text(r, 14); r.name:SetPoint("TOPLEFT", r.ring, "TOPRIGHT", 14, -9); r.name:SetPoint("RIGHT", r.rare, "LEFT", -8, 0)
    r.sub = UI.Text(r, 11, C.dim); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -6); r.sub:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r:SetScript("OnClick", function(row) selBoss = row.bname; showShared = false; ns.RefreshUI() end)
  end, function(r, b)
    r.bname = b.name
    r.name:SetText(b.name); r.num:SetText(b.level or "??")
    r.rare:SetShown(b.rare == true)
    local e = self.entry
    local look = e and visual(e, b.name)
    local ok = look and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, r.por, look)
    r.por:SetShown(ok and true or false); r.skull:SetShown(not ok)
    r.sub:SetText(e and ("Boss " .. b.n .. "  ·  " .. recordText(e, b.name)) or "")
    local on = b.name == selBoss
    self.bosses:Select(r, on)
    r.tint:SetShown(on)
    if on then r.name:SetTextColor(UI.Accent()) else r.name:SetTextColor(unpack(C.text)) end
  end)

  self.detailPanel = panel(f)
  self.scroll, self.detail = scrollArea(self.detailPanel)
  -- the boss's own model, drawn by the game
  self.portraitBox = CreateFrame("Frame", nil, self.detail); self.portraitBox:SetSize(96, 96); self.portraitBox:SetPoint("TOPLEFT")
  UI.Fill(self.portraitBox, C.bg); UI.Border(self.portraitBox)
  self.portrait = CreateFrame("PlayerModel", nil, self.portraitBox); self.portrait:SetPoint("TOPLEFT", 1, -1); self.portrait:SetPoint("BOTTOMRIGHT", -1, 1)
  self.portraitBox:Hide()
  -- the round portrait (when the boss's look is known), with its level badge
  local big = CreateFrame("Frame", nil, self.detail); big:SetSize(96, 96); big:SetPoint("TOPLEFT")
  big.ring = big:CreateTexture(nil, "ARTWORK"); big.ring:SetAllPoints(); big.ring:SetColorTexture(1, 1, 1, 0.22); round(big.ring)
  big.por = big:CreateTexture(nil, "ARTWORK", nil, 1); big.por:SetSize(90, 90); big.por:SetPoint("CENTER")
  big.badgeRing = big:CreateTexture(nil, "OVERLAY"); big.badgeRing:SetSize(32, 32); big.badgeRing:SetPoint("BOTTOMLEFT", -4, -4)
  UI.Accented(big.badgeRing); round(big.badgeRing)
  big.badge = big:CreateTexture(nil, "OVERLAY", nil, 1); big.badge:SetSize(28, 28); big.badge:SetPoint("CENTER", big.badgeRing)
  big.badge:SetColorTexture(unpack(C.bg)); round(big.badge)
  big.level = UI.Text(big, 13, C.text, "CENTER"); big.level:SetPoint("CENTER", big.badge); big.level:SetDrawLayer("OVERLAY", 2)
  big:Hide()
  self.big = big
  self.sharedBtn = UI.Button(self.detail, "", 200, 24, function() showShared = not showShared; ns.RefreshUI() end)
  self.sharedNote = UI.Text(self.detail, 11, C.faint)
  self.bossTitle = UI.Text(self.detail, 18)
  self.bossSub = UI.Text(self.detail, 12, C.dim)
  self.lootHead = UI.Text(self.detail, 13); UI.Accented(self.lootHead); self.lootHead:SetText("Loot")
  self.lootRows = {}
  self.body = UI.Text(self.detail, 12, C.text); self.body:SetWordWrap(true); self.body:SetJustifyV("TOP")
  self.tipBtn = UI.Button(self.detail, "Write a tip", 100, 24, function(b)
    if b.e and b.boss and ns.OpenTipEditor then ns.OpenTipEditor(b.e.name, b.boss.name) end
  end)
  self.lootNote = UI.Text(self.detail, 11, C.faint); self.lootNote:SetWordWrap(true); self.lootNote:SetJustifyV("TOP")
  -- the boss on Wowhead (its loot, guides, comments): a link to copy, nothing read from there
  self.webBtn = UI.Button(self.detail, "Look it up online", 140, 24, function(b)
    self.webOpen = not self.webOpen; ns.RefreshUI()
  end)
  self.webBox = UI.CopyBox(self.detail, 300)
  self.webHint = UI.Text(self.detail, 11, C.faint); self.webHint:SetWordWrap(true)
  self.webHint:SetText("Wowhead's WoW Forever page for this boss: its loot, guides and comments. Click the box, press Ctrl+C, then paste it in your browser.")

  -- Map
  self.mapPanel = panel(f)
  self.floorButtons = {}
  self.map = UI.MapCanvas(self.mapPanel)
  self.placeBtn = UI.Button(self.mapPanel, "Place bosses", 120, 24, function()
    if placing then placing = nil else placing = { dungeon = selDungeon, i = 1 } end
    ns.RefreshUI()
  end)
  self.skipBtn = UI.Button(self.mapPanel, "Skip", 60, 24, function()
    if placing then placing.i = placing.i + 1 end
    ns.RefreshUI()
  end)
  self.mapNote = UI.Text(self.mapPanel, 11, C.faint); self.mapNote:SetWordWrap(true)

  -- Quests: cards on the left (the picked one opens to show its chain), the picked quest on the right
  self.qPanel = panel(f)
  self.qHead = heading(self.qPanel, "Quests"); self.qHead:SetPoint("TOPLEFT", 14, -12)
  self.qfilterNote = UI.Text(self.qPanel, 11, C.dim); self.qfilterNote:SetPoint("TOPLEFT", self.qHead, "BOTTOMLEFT", 0, -6)
  -- faction crests: your own is on; click the other one to list its quests too
  self.fbtn = {}
  for _, fac in ipairs({ "A", "H" }) do
    local b = CreateFrame("Button", nil, self.qPanel); b:SetSize(32, 32)
    UI.Fill(b, C.raised); UI.Border(b)
    b.on = b:CreateTexture(nil, "ARTWORK"); b.on:SetAllPoints(); UI.Accented(b.on, 0.18)
    b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(24, 24); b.icon:SetPoint("CENTER"); crest(b.icon, fac)
    UI.Fill(b, C.hover, "HIGHLIGHT")
    b.fac = fac
    b:SetScript("OnClick", function(btn)
      local sf = factionShown()
      sf[btn.fac] = not sf[btn.fac]
      if not sf.A and not sf.H then sf[btn.fac == "A" and "H" or "A"] = true end
      ns.RefreshUI()
    end)
    b:SetScript("OnEnter", function(btn)
      GameTooltip:SetOwner(btn, "ANCHOR_TOP")
      GameTooltip:SetText((btn.fac == "A" and "Alliance" or "Horde") .. " quests: " .. (factionShown()[btn.fac] and "shown" or "hidden"))
      GameTooltip:AddLine("Click to show or hide them. Quests for both factions are always listed.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    self.fbtn[fac] = b
  end
  self.fbtn.H:SetPoint("TOPRIGHT", -12, -10); self.fbtn.A:SetPoint("RIGHT", self.fbtn.H, "LEFT", -6, 0)
  self.qlistScroll, self.qcards = scrollArea(self.qPanel)
  self.cards = {}
  self.qempty = UI.Text(self.qPanel, 12, C.dim); self.qempty:SetWordWrap(true)

  self.qdPanel = panel(f)
  self.qscroll, self.qbody = scrollArea(self.qdPanel)
  local qd = {}
  self.qd = qd
  qd.title = UI.Text(self.qbody, 18); qd.title:SetPoint("TOPLEFT"); qd.title:SetWordWrap(true)
  qd.meta = UI.Text(self.qbody, 12, C.dim)
  qd.c1 = self.qbody:CreateTexture(nil, "ARTWORK"); qd.c1:SetSize(20, 20)
  qd.c2 = self.qbody:CreateTexture(nil, "ARTWORK"); qd.c2:SetSize(20, 20)
  qd.status = UI.Text(self.qbody, 12)
  qd.line = self.qbody:CreateTexture(nil, "BORDER"); qd.line:SetColorTexture(unpack(C.line)); qd.line:SetHeight(1)
  qd.text = UI.Text(self.qbody, 12, C.text); qd.text:SetWordWrap(true); qd.text:SetJustifyV("TOP")
  qd.chainLine = UI.Text(self.qbody, 12); qd.chainLine:SetWordWrap(true)
  qd.chainBtn = UI.Button(self.qbody, "Show quest chain", 130, 24, function() showChain = not showChain; ns.RefreshUI() end)
  qd.pin = UI.Button(self.qbody, "Show on map", 110, 24, function(btn) local t = btn.target; if t then pinOnMap(t[1], t[2], t[3], t[4]) end end)
  qd.pinEnd = UI.Button(self.qbody, "Pin the turn-in", 120, 24, function(btn) local q = btn.q; if q then pinOnMap(q[20], q[21], q[22], q[11] ~= "" and q[11] or q[6] ~= "" and q[6] or "the turn-in") end end)
  qd.linkBtn = UI.Button(self.qbody, "Guides online", 116, 24, function() showLink = not showLink; ns.RefreshUI() end)
  qd.chainBox = CreateFrame("Frame", nil, self.qbody); UI.Fill(qd.chainBox, C.bg); UI.Border(qd.chainBox)
  qd.chainText = UI.Text(qd.chainBox, 12); qd.chainText:SetWordWrap(true); qd.chainText:SetJustifyV("TOP"); qd.chainText:SetSpacing(4)
  qd.chainText:SetPoint("TOPLEFT", 12, -10)
  qd.link = UI.CopyBox(self.qbody, 300)
  qd.linkHint = UI.Text(self.qbody, 11, C.faint); qd.linkHint:SetWordWrap(true)
  qd.linkHint:SetText("Wowhead's WoW Forever page for this quest, with guides and player comments. Click the box, press Ctrl+C, then paste it in your browser.")
  qd.noteHead = UI.Text(self.qbody, 13); UI.Accented(qd.noteHead); qd.noteHead:SetText("Guild note")
  qd.note = UI.Text(self.qbody, 12, C.text); qd.note:SetWordWrap(true); qd.note:SetJustifyV("TOP")
  qd.chooseHead = UI.Text(self.qbody, 13); UI.Accented(qd.chooseHead)
  qd.alsoHead = UI.Text(self.qbody, 13); UI.Accented(qd.alsoHead)
  qd.money = UI.Text(self.qbody, 12, C.text); qd.money:SetWordWrap(true)
  qd.rows = {}
  qd.story = UI.Text(self.qbody, 11, C.dim); qd.story:SetWordWrap(true); qd.story:SetJustifyV("TOP")
  self.qnote = UI.Text(self.qbody, 11, C.faint); self.qnote:SetWordWrap(true)
  self.qnote:SetText("Quest text and rewards: Blizzard Entertainment. Quest givers, locations, levels and objectives: QuestieDB (GPLv3) for classic dungeons; for the new dungeons, Foxden learns where quests start and end as the guild picks them up and turns them in.")

  -- Runs
  self.runPanel = panel(f)
  self.runList = UI.List(self.runPanel, 48, function(r)
    r.name = UI.Text(r, 13); r.name:SetPoint("TOPLEFT", 14, -8)
    r.sub = UI.Text(r, 11, C.dim); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -5)
    r.time = UI.Text(r, 13, C.text, "RIGHT"); r.time:SetPoint("TOPRIGHT", -14, -8)
    r.meta = UI.Text(r, 11, C.dim, "RIGHT"); r.meta:SetPoint("TOPRIGHT", r.time, "BOTTOMRIGHT", 0, -5)
    r:SetScript("OnClick", function(row) ns.OpenPage("runs", row.id) end)
  end, function(r, run)
    r.id = run.id
    r.name:SetText(run.endTime and date("%b %d, %H:%M", run.endTime) or "Run")
    local names = {}
    for _, m in ipairs(run.party or {}) do names[#names + 1] = m.name end
    r.sub:SetText(#names > 0 and table.concat(names, ", ") or (run.loggedBy and ("Logged by " .. run.loggedBy) or ""))
    r.time:SetText(UI.Time(run.duration or 0))
    local b, w = run.bosses and #run.bosses or 0, run.wipes or 0
    r.meta:SetText(b .. (b == 1 and " boss" or " bosses") .. (w > 0 and (", " .. w .. (w == 1 and " wipe" or " wipes")) or ""))
  end)
  self.runEmpty = UI.Text(self.runPanel, 12, C.dim); self.runEmpty:SetWordWrap(true)
  self.runEmpty:SetText("No runs of this dungeon logged yet. Walk in and Foxden records it on its own.")

  self.empty = UI.Text(f, 13, C.dim, "CENTER"); self.empty:SetWordWrap(true)
  -- the grid of dungeon (or raid) cards
  self.gridScroll, self.gridBody = scrollArea(f)
  self.gridCards = {}
  self.empty:SetText("No dungeons yet. Run a dungeon and it appears here.")
end

function page:Layout(w, h)
  self.w, self.h = w, h
  local top = -(PICK_H + 10)
  self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", 0, top); self.head:SetPoint("TOPRIGHT", 0, top); self.head:SetHeight(HEAD_H)
  local tx = -14
  for i = #self.viewTabs, 1, -1 do
    local b = self.viewTabs[i]
    b:ClearAllPoints(); b:SetPoint("TOPRIGHT", tx, -12)
    tx = tx - b:GetWidth() - 6
  end
  local tabsW = -tx
  self.title:SetWidth(math.max(160, w - tabsW - 40))
  self.sub:SetWidth(w - 200); self.lfgWho:SetWidth(w - 200)

  local cy = top - HEAD_H - GAP
  local ch = h + cy
  local leftW = math.max(250, math.min(340, math.floor(w * 0.38)))
  local rightW = w - leftW - GAP
  self.leftW, self.rightW, self.contentH = leftW, rightW, ch
  for _, p in ipairs({ self.bossPanel, self.qPanel }) do
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", 0, cy); p:SetSize(leftW, ch)
  end
  for _, p in ipairs({ self.detailPanel, self.qdPanel }) do
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", leftW + GAP, cy); p:SetSize(rightW, ch)
  end
  for _, p in ipairs({ self.mapPanel, self.runPanel, self.trashPanel }) do
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", 0, cy); p:SetSize(w, ch)
  end
  self.bosses:ClearAllPoints(); self.bosses:SetPoint("TOPLEFT", 4, -38); self.bosses:SetSize(leftW - 8, ch - 44)
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 16, -16); self.scroll:SetSize(rightW - 32, ch - 28)
  self.detail:SetWidth(rightW - 40)
  self.qlistScroll:ClearAllPoints(); self.qlistScroll:SetPoint("TOPLEFT", 10, -54); self.qlistScroll:SetSize(leftW - 20, ch - 62)
  self.qcards:SetWidth(leftW - 20)
  self.qempty:ClearAllPoints(); self.qempty:SetPoint("TOPLEFT", 14, -60); self.qempty:SetWidth(leftW - 28)
  self.qscroll:ClearAllPoints(); self.qscroll:SetPoint("TOPLEFT", 16, -16); self.qscroll:SetSize(rightW - 32, ch - 28)
  self.qbody:SetWidth(rightW - 40)
  self.runList:ClearAllPoints(); self.runList:SetPoint("TOPLEFT", 4, -6); self.runList:SetSize(w - 8, ch - 12)
  self.runEmpty:ClearAllPoints(); self.runEmpty:SetPoint("TOPLEFT", 16, -16); self.runEmpty:SetWidth(w - 32)
  -- map: as big as fits at 3:2, under the floor buttons
  local mw, mh = w - 32, ch - 16 - 34 - 30
  if mw / 1.5 > mh then mw = math.floor(mh * 1.5) else mh = math.floor(mw / 1.5) end
  self.mapW, self.mapH = mw, mh
  self.mapX = math.floor((w - mw) / 2)
  self.map:ClearAllPoints(); self.map:SetPoint("TOPLEFT", self.mapX, -16 - 34)
  self.mapNote:ClearAllPoints(); self.mapNote:SetPoint("TOPLEFT", self.mapX, -16 - 34 - mh - 8); self.mapNote:SetWidth(mw)
  self.placeBtn:ClearAllPoints(); self.placeBtn:SetPoint("TOPRIGHT", self.mapPanel, "TOPLEFT", self.mapX + mw, -16)
  self.skipBtn:ClearAllPoints(); self.skipBtn:SetPoint("RIGHT", self.placeBtn, "LEFT", -6, 0)
  self.empty:ClearAllPoints(); self.empty:SetPoint("CENTER"); self.empty:SetWidth(w - 40)
  -- the grid: even padding all round (PAD), under the Dungeons | Raids buttons
  local gtop = -(PAD - 4) - PICK_H - PAD -- buttons, then the same gap as the padding
  self.gridScroll:ClearAllPoints(); self.gridScroll:SetPoint("TOPLEFT", PAD, gtop); self.gridScroll:SetSize(w - PAD * 2, h + gtop - PAD)
  self.gridBody:SetWidth(w - PAD * 2)
end

-- ---- refresh: bosses ----------------------------------------------------------------

function page:SetPortrait(look, npc)
  local m, box = self.portrait, self.portraitBox
  local key = look and ("d" .. look) or npc and ("n" .. npc) or nil
  if not key then box:Hide(); self.portraitKey = nil; return false end
  if self.portraitKey ~= key then
    self.portraitKey = key
    local ok = false
    if m.ClearModel then pcall(m.ClearModel, m) end
    if look and m.SetDisplayInfo then ok = pcall(m.SetDisplayInfo, m, look) end
    if not ok and npc and m.SetCreature then ok = pcall(m.SetCreature, m, npc) end
    if ok and m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0.75) end
    self.portraitOk = ok
  end
  box:SetShown(self.portraitOk == true)
  return self.portraitOk == true
end

function page:ShowBoss(e, boss)
  local w = self.detail:GetWidth() or 300
  local hasPortrait = false
  local big = self.big
  big:Hide()
  if boss then
    local look, npc = visual(e, boss.name)
    -- round portrait when its look is known; else the game's 3D model in a square
    local ok = look and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, big.por, look)
    if ok then
      self:SetPortrait(nil, nil)
      big.level:SetText(boss.level or "??"); big:Show(); hasPortrait = true
    else
      hasPortrait = self:SetPortrait(look, npc)
    end
  else self:SetPortrait(nil, nil) end
  local tx = hasPortrait and 112 or 0
  self.bossTitle:ClearAllPoints(); self.bossTitle:SetPoint("TOPLEFT", tx, hasPortrait and -28 or 0); self.bossTitle:SetWidth(w - tx)
  self.bossSub:ClearAllPoints(); self.bossSub:SetPoint("TOPLEFT", self.bossTitle, "BOTTOMLEFT", 0, -6); self.bossSub:SetWidth(w - tx)
  self.bossTitle:SetText(boss and boss.name or "No bosses known for this dungeon yet")
  local nb = #bossesOf(e)
  self.bossSub:SetText(boss and (string.format("Boss %d of %d", boss.n, nb) .. (boss.level and ("  ·  level " .. boss.level) or "")
    .. (boss.rare and "  ·  rare spawn" or "") .. "  ·  " .. recordText(e, boss.name)) or "")
  local y = hasPortrait and -(96 + 16) or -(24 + 6 + 14 + 16)

  local loot, note = {}, nil
  if boss then loot, note = lootOf(e, boss) end
  self.lootHead:SetShown(boss ~= nil)
  if boss then self.lootHead:ClearAllPoints(); self.lootHead:SetPoint("TOPLEFT", 0, y); y = y - 24 end
  waitingItems = false
  -- this boss's own loot first; loot shared by many bosses behind a toggle
  local shared, own, common = sharedOf(e), {}, {}
  local hiddenByFilter = 0
  if ns.LootFilter and ns.LootFilter.Active() then
    local kept = {}
    for _, it in ipairs(loot) do if ns.LootFilter.Pass(it.id) then kept[#kept + 1] = it else hiddenByFilter = hiddenByFilter + 1 end end
    loot = kept
  end
  for _, it in ipairs(loot) do
    if shared[it.id] and not (it.seen and it.seen > 0) then common[#common + 1] = it else own[#own + 1] = it end
  end
  if #own == 0 then own, common = common, {} end
  local showList = {}
  for _, it in ipairs(own) do showList[#showList + 1] = it end
  local function placeShared()
    self.sharedBtn:SetShown(#common > 0); self.sharedNote:SetShown(#common > 0)
    if #common == 0 then return end
    self.sharedBtn.label:SetText((showShared and "Hide" or "Show") .. " shared loot (" .. #common .. ")")
    self.sharedBtn:SetWidth(self.sharedBtn.label:GetStringWidth() + 24)
    self.sharedBtn:ClearAllPoints(); self.sharedBtn:SetPoint("TOPLEFT", 0, y - 4)
    self.sharedNote:ClearAllPoints(); self.sharedNote:SetPoint("LEFT", self.sharedBtn, "RIGHT", 10, 0)
    self.sharedNote:SetText("drops from many bosses, low chance")
    y = y - 36
  end
  local loot = showList
  for i, it in ipairs(loot) do
    local r = self.lootRows[i] or itemCard(self.detail); self.lootRows[i] = r
    fillCard(r, it.id, it.name)
    local kind, others = ns.WishKind and ns.WishKind(it.id), ns.WantedBy and ns.WantedBy(it.id)
    local bits = {}
    if kind then bits[#bits + 1] = ns.WISH_COLOR[kind] .. ns.WISH_LABEL[kind] .. "|r" end
    if others then bits[#bits + 1] = "wanted by " .. others end
    if it.seen and it.seen > 0 then bits[#bits + 1] = "seen " .. it.seen .. "x" end
    r.seen:SetText(table.concat(bits, "  ·  "))
    r.wish = { boss = boss.name, dungeon = e.name }
    r.star:Show(); r.star.tex:SetDesaturated(not kind); r.star.tex:SetAlpha(kind and 1 or 0.35)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetWidth(w); r:Show()
    y = y - 52
  end
  local nrows = #loot
  placeShared()
  if showShared then
    for _, it in ipairs(common) do
      nrows = nrows + 1
      local r = self.lootRows[nrows] or itemCard(self.detail); self.lootRows[nrows] = r
      fillCard(r, it.id, it.name)
      local kind = ns.WishKind and ns.WishKind(it.id)
      r.seen:SetText(kind and (ns.WISH_COLOR[kind] .. ns.WISH_LABEL[kind] .. "|r") or "")
      r.wish = { boss = boss.name, dungeon = e.name }
      r.star:Show(); r.star.tex:SetDesaturated(not kind); r.star.tex:SetAlpha(kind and 1 or 0.35)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetWidth(w); r:Show()
      y = y - 52
    end
  end
  for i = nrows + 1, #self.lootRows do self.lootRows[i]:Hide() end
  if boss and nrows == 0 and #common == 0 then y = y + 4 end

  self.body:SetShown(boss ~= nil)
  if boss then
    self.body:SetWidth(w); self.body:SetText(bossText(e, boss))
    self.body:ClearAllPoints(); self.body:SetPoint("TOPLEFT", 0, y - 10)
    y = y - 10 - (self.body:GetStringHeight() or 0)
    self.tipBtn.e, self.tipBtn.boss = e, boss
    self.tipBtn:ClearAllPoints(); self.tipBtn:SetPoint("TOPLEFT", 0, y - 10)
    self.webBtn:ClearAllPoints(); self.webBtn:SetPoint("LEFT", self.tipBtn, "RIGHT", 8, 0)
    self.webBtn.label:SetText(self.webOpen and "Hide the link" or "Look it up online")
    y = y - 10 - 24
    if self.webOpen then
      local npc
      for _, sb in ipairs(e.static and e.static.bosses or {}) do if sb.name == boss.name then npc = sb.npc end end
      local slug = tostring(boss.name):lower():gsub("['’]", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
      local url = npc and ("https://www.wowhead.com/forever/npc=" .. npc .. "/" .. slug)
        or ("https://www.wowhead.com/forever/search?q=" .. tostring(boss.name):gsub(" ", "+"))
      self.webBox:SetWidth(w); self.webBox:SetLink(url)
      self.webBox:ClearAllPoints(); self.webBox:SetPoint("TOPLEFT", 0, y - 8); y = y - 8 - 26
      self.webHint:SetWidth(w); self.webHint:ClearAllPoints(); self.webHint:SetPoint("TOPLEFT", 0, y - 4)
      y = y - 4 - (self.webHint:GetStringHeight() or 14)
    end
  end
  self.tipBtn:SetShown(boss ~= nil)
  self.webBtn:SetShown(boss ~= nil)
  self.webBox:SetShown(boss ~= nil and self.webOpen == true)
  self.webHint:SetShown(boss ~= nil and self.webOpen == true)
  self.lootNote:SetShown(note ~= nil and note ~= "")
  if self.lootNote:IsShown() then
    self.lootNote:SetWidth(w); self.lootNote:SetText(note)
    self.lootNote:ClearAllPoints(); self.lootNote:SetPoint("TOPLEFT", 0, y - 16)
    y = y - 16 - (self.lootNote:GetStringHeight() or 14)
  end
  self.detail:SetHeight(-y + 16)

  local key = tostring(e.name) .. "/" .. tostring(boss and boss.name)
  if self.itemKey ~= key then self.itemKey, self.itemTries = key, 0; self.scroll:SetVerticalScroll(0) end
  if waitingItems and not self.itemWait and self.itemTries < 5 then
    -- item data arrives a moment later; redraw once it has
    self.itemTries = self.itemTries + 1
    self.itemWait = true
    C_Timer.After(0.6, function() self.itemWait = nil; if self.scroll:IsVisible() then ns.RefreshUI() end end)
  end
end

-- ---- refresh: quests ----------------------------------------------------------------

function page:ShowQuest(q)
  local qd, w = self.qd, self.qbody:GetWidth() or 400
  local ar, ag, ab = UI.Accent()
  local head = hex(ar, ag, ab)
  qd.title:SetWidth(w - 60); qd.title:SetText(q[2])
  local st = ns.QuestState and ns.QuestState(q[1])
  qd.meta:ClearAllPoints(); qd.meta:SetPoint("TOPLEFT", qd.title, "BOTTOMLEFT", 0, -8)
  qd.meta:SetText((questLevel(q) ~= "" and (questLevel(q) .. "  ·  ") or "") .. (FACTION[q[3] or ""] or FACTION[""]))
  if q[3] == "B" then crest(qd.c1, "A"); crest(qd.c2, "H"); qd.c1:Show(); qd.c2:Show()
  elseif q[3] == "A" or q[3] == "H" then crest(qd.c2, q[3]); qd.c1:Hide(); qd.c2:Show()
  else qd.c1:Hide(); qd.c2:Hide() end
  qd.c2:ClearAllPoints(); qd.c2:SetPoint("TOPRIGHT", 0, 0)
  qd.c1:ClearAllPoints(); qd.c1:SetPoint("RIGHT", qd.c2, "LEFT", -4, 0)
  qd.status:ClearAllPoints(); qd.status:SetPoint("TOPLEFT", qd.meta, "BOTTOMLEFT", 0, -6)
  qd.status:SetText(st == "done" and "|cff6fd39aYou've done this quest|r" or st == "have" and "|cffe8c35aIn your quest log|r"
    or q.locked and ("|cffef6b6b" .. q.locked .. "|r") or "")
  local y = (qd.title:GetStringHeight() or 20) + 8 + 14 + ((st or q.locked) and (6 + 14) or 0) + 12
  qd.line:ClearAllPoints(); qd.line:SetPoint("TOPLEFT", 0, -y); qd.line:SetPoint("TOPRIGHT", 0, -y)
  y = y + 14

  local lines = {}
  local function sec(label, text) lines[#lines + 1] = (#lines > 0 and "\n" or "") .. head .. label .. "|r\n" .. text end
  if q[12] ~= "" then sec("Objective", q[12]) end
  if q[6] ~= "" then
    sec("Starts at", q[6] .. (q[7] ~= "" and (" in " .. q[7]) or "") .. ((q[9] or 0) > 0 and string.format(" (%d, %d)", math.floor(q[9] + 0.5), math.floor(q[10] + 0.5)) or ""))
  end
  local sameEnd = (q[20] or 0) == 0 or (q[20] == q[8] and math.abs((q[21] or 0) - (q[9] or 0)) <= 1 and math.abs((q[22] or 0) - (q[10] or 0)) <= 1)
  if q[11] ~= "" or not sameEnd then
    local who = q[11] ~= "" and q[11] or q[6]
    sec("Turn in to", who .. ((not sameEnd) and string.format(" (%d, %d)", math.floor(q[21] + 0.5), math.floor(q[22] + 0.5)) or ""))
  end
  local chain, k, cur = chainOf(q)
  if not chain and q[13] ~= "" then sec("Needs first", q[13]) end
  qd.text:SetWidth(w); qd.text:SetText(table.concat(lines, "\n"))
  qd.text:ClearAllPoints(); qd.text:SetPoint("TOPLEFT", 0, -y)
  y = y + (qd.text:GetStringHeight() or 0) + 12

  -- where you are in its quest chain
  qd.chainLine:SetShown(chain ~= nil)
  if chain then
    local n, txt = #chain, nil
    if st == "done" then txt = "|cff99a1b0Step " .. k .. " of " .. n .. " in a quest chain.|r"
    elseif cur and cur < k then txt = "|cffef6b6bNeeds the quests before it first: you're on step " .. cur .. " of " .. n .. ", this is step " .. k .. ".|r"
    elseif st == "have" then txt = "|cffe8c35aStep " .. k .. " of " .. n .. " in a quest chain, in your quest log.|r"
    elseif k == 1 then txt = "|cff6fd39aStep 1 of " .. n .. ": this quest starts the chain.|r"
    else txt = "|cff6fd39aStep " .. k .. " of " .. n .. ": you've done the quests before it.|r" end
    qd.chainLine:SetWidth(w); qd.chainLine:SetText(txt)
    qd.chainLine:ClearAllPoints(); qd.chainLine:SetPoint("TOPLEFT", 0, -y)
    y = y + (qd.chainLine:GetStringHeight() or 14) + 10
  end

  -- buttons, wrapping onto a second row when they don't fit
  qd.pinEnd.q = q
  -- "Show on map": the quest giver, or the giver of the chain step you're on when that comes first
  local nextStep = chain and cur and cur < k and chain[cur] or nil
  if nextStep and (nextStep[4] or 0) > 0 then
    qd.pin.target = { nextStep[4], nextStep[5], nextStep[6], (nextStep[3] ~= "" and nextStep[3] or nextStep[2]) .. " (step " .. cur .. ")" }
    qd.pin.label:SetText("Show step " .. cur .. " on map")
  else
    qd.pin.target = (q[8] or 0) > 0 and { q[8], q[9], q[10], q[6] ~= "" and q[6] or "the quest start" } or nil
    qd.pin.label:SetText("Show on map")
  end
  local hasStart, hasEnd = qd.pin.target ~= nil, (q[20] or 0) > 0
  qd.chainBtn.label:SetText(showChain and "Hide quest chain" or "Show quest chain")
  qd.linkBtn.label:SetText(showLink and "Hide the link" or "Guides online")
  local btns = {}
  if chain then btns[#btns + 1] = qd.chainBtn end
  if hasStart then btns[#btns + 1] = qd.pin end
  if hasEnd then btns[#btns + 1] = qd.pinEnd end
  btns[#btns + 1] = qd.linkBtn
  qd.chainBtn:SetShown(chain ~= nil); qd.pin:SetShown(hasStart); qd.pinEnd:SetShown(hasEnd)
  local bx, rowY = 0, y
  for _, b in ipairs(btns) do
    local bw = math.floor((b.label:GetStringWidth() or 60) + 24)
    b:SetWidth(bw)
    if bx > 0 and bx + bw > w then bx = 0; rowY = rowY + 30 end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", bx, -rowY); b:Show()
    bx = bx + bw + 8
  end
  y = rowY + 34

  -- the whole chain
  qd.chainBox:SetShown(chain ~= nil and showChain)
  if chain and showChain then
    qd.chainText:SetWidth(w - 24); qd.chainText:SetText(chainLines(chain, k, cur))
    local hh = (qd.chainText:GetStringHeight() or 0) + 20
    qd.chainBox:ClearAllPoints(); qd.chainBox:SetPoint("TOPLEFT", 0, -y); qd.chainBox:SetSize(w, hh)
    y = y + hh + 10
  end
  -- the link to read more online (the game can't open web pages)
  qd.link:SetShown(showLink); qd.linkHint:SetShown(showLink)
  if showLink then
    qd.link:SetWidth(w); qd.link:SetLink(ns.QuestUrl(q))
    qd.link:ClearAllPoints(); qd.link:SetPoint("TOPLEFT", 0, -y); y = y + 30
    qd.linkHint:SetWidth(w); qd.linkHint:ClearAllPoints(); qd.linkHint:SetPoint("TOPLEFT", 0, -y)
    y = y + (qd.linkHint:GetStringHeight() or 14) + 12
  end

  -- the guild's note
  local note, by = questNote(q)
  qd.noteHead:ClearAllPoints(); qd.noteHead:SetPoint("TOPLEFT", 0, -y); y = y + 20
  qd.note:SetWidth(w)
  qd.note:SetText(note and (note .. ((by and by ~= "") and ("  |cff99a1b0(" .. by .. ")|r") or ""))
    or "|cff99a1b0No note yet. Guild members write them on the website's dungeon page; they show here after the next sync.|r")
  qd.note:ClearAllPoints(); qd.note:SetPoint("TOPLEFT", 0, -y)
  y = y + (qd.note:GetStringHeight() or 14) + 16

  -- rewards: "choose one" cards in two columns, then what you get anyway
  waitingItems = false
  local n = 0
  local function cards(ids, x0, colW, cols)
    local rowsUsed = 0
    for i, id in ipairs(ids) do
      n = n + 1
      local r = qd.rows[n] or itemCard(self.qbody, 44); qd.rows[n] = r
      fillCard(r, id)
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", x0 + col * (colW + 8), -(y + row * 50)); r:SetWidth(colW); r:Show()
      rowsUsed = row + 1
    end
    y = y + rowsUsed * 50
  end
  local cols = w >= 420 and 2 or 1
  local colW = cols == 2 and math.floor((w - 8) / 2) or w
  local choice = q[18] or {}
  qd.chooseHead:SetShown(#choice > 0)
  if #choice > 0 then
    qd.chooseHead:SetText(#choice == 1 and "You receive" or "Choose one reward")
    qd.chooseHead:ClearAllPoints(); qd.chooseHead:SetPoint("TOPLEFT", 0, -y); y = y + 22
    cards(choice, 0, colW, cols)
    y = y + 6
  end
  local items = q[17] or {}
  local extra = {}
  if (q[14] or 0) > 0 then extra[#extra + 1] = UI.Num(q[14]) .. " XP" end
  if (q[15] or 0) > 0 then extra[#extra + 1] = ns.Money(q[15]) end
  if q[16] ~= "" then extra[#extra + 1] = q[16] .. " reputation" end
  local hasAlso = #items > 0 or #extra > 0
  qd.alsoHead:SetShown(hasAlso)
  if hasAlso then
    qd.alsoHead:SetText(#choice > 0 and "You will also receive" or "Rewards")
    qd.alsoHead:ClearAllPoints(); qd.alsoHead:SetPoint("TOPLEFT", 0, -y); y = y + 22
    cards(items, 0, colW, cols)
  end
  for k = n + 1, #qd.rows do qd.rows[k]:Hide() end
  qd.money:SetShown(#extra > 0)
  if #extra > 0 then
    qd.money:SetWidth(w); qd.money:SetText(table.concat(extra, "   ·   "))
    qd.money:ClearAllPoints(); qd.money:SetPoint("TOPLEFT", 0, -(y + 2)); y = y + 24
  end
  qd.story:SetWidth(w); qd.story:SetText(q[19] or "")
  qd.story:SetShown((q[19] or "") ~= "")
  if qd.story:IsShown() then
    qd.story:ClearAllPoints(); qd.story:SetPoint("TOPLEFT", 0, -(y + 10)); y = y + 10 + (qd.story:GetStringHeight() or 0)
  end
  self.qnote:ClearAllPoints(); self.qnote:SetPoint("TOPLEFT", 0, -(y + 18)); self.qnote:SetWidth(w)
  y = y + 18 + (self.qnote:GetStringHeight() or 14)
  self.qbody:SetHeight(y + 16)

  local key = "q/" .. tostring(q[1])
  if self.qkey ~= key then self.qkey, self.qtries = key, 0; self.qscroll:SetVerticalScroll(0) end
  if waitingItems and not self.qwait and self.qtries < 5 then
    self.qtries = self.qtries + 1
    self.qwait = true
    C_Timer.After(0.6, function() self.qwait = nil; if self.qscroll:IsVisible() then ns.RefreshUI() end end)
  end
end

-- One quest card: icon, title, level and status, faction crests, and the quest's chain with
-- your progress (every card, so you can see where you are in each chain at a glance).
local function questCard(parent)
  local c = CreateFrame("Button", nil, parent)
  UI.Fill(c, C.raised); UI.Border(c)
  c.tint = c:CreateTexture(nil, "BACKGROUND", nil, 1); c.tint:SetAllPoints(); UI.Accented(c.tint, 0.12); c.tint:Hide()
  c.bar = c:CreateTexture(nil, "ARTWORK"); c.bar:SetPoint("TOPLEFT"); c.bar:SetPoint("BOTTOMLEFT"); c.bar:SetWidth(2); UI.Accented(c.bar); c.bar:Hide()
  UI.Fill(c, C.hover, "HIGHLIGHT")
  c.qicon = c:CreateTexture(nil, "ARTWORK"); c.qicon:SetSize(20, 20); c.qicon:SetPoint("TOPLEFT", 12, -12)
  c.c2 = c:CreateTexture(nil, "ARTWORK"); c.c2:SetSize(20, 20); c.c2:SetPoint("TOPRIGHT", -10, -10)
  c.c1 = c:CreateTexture(nil, "ARTWORK"); c.c1:SetSize(20, 20); c.c1:SetPoint("RIGHT", c.c2, "LEFT", -4, 0)
  c.title = UI.Text(c, 13); c.title:SetWordWrap(true); c.title:SetJustifyV("TOP"); c.title:SetPoint("TOPLEFT", 42, -12)
  c.sub = UI.Text(c, 11, C.dim); c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
  c.inset = CreateFrame("Frame", nil, c); UI.Fill(c.inset, C.bg); UI.Border(c.inset)
  c.steps = UI.Text(c.inset, 12); c.steps:SetWordWrap(true); c.steps:SetJustifyV("TOP"); c.steps:SetSpacing(4)
  c.steps:SetPoint("TOPLEFT", 10, -8)
  c:SetScript("OnClick", function(self) selQuest = self.qid; showLink = false; ns.RefreshUI() end)
  return c
end

function page:LayoutQuests(e)
  local quests, totalQuests = questsOf(e)
  local sf = factionShown()
  self.qHead:SetText("Quests  |cff99a1b0" .. #quests .. "|r")
  for fac, b in pairs(self.fbtn) do
    b.on:SetShown(sf[fac] == true); b.icon:SetDesaturated(not sf[fac]); b.icon:SetAlpha(sf[fac] and 1 or 0.5)
    b:SetShown(totalQuests > 0)
  end
  local who = sf.A and sf.H and "Both factions" or sf.A and "Alliance" or "Horde"
  self.qfilterNote:SetText(totalQuests == 0 and "" or (string.format("%s  ·  %d of %d", who, #quests, totalQuests)
    .. (hiddenProf > 0 and string.format("  ·  %d profession %s hidden", hiddenProf, hiddenProf == 1 and "quest" or "quests") or "")))
  -- keep the picked quest; else the first one you haven't done
  local q
  for _, x in ipairs(quests) do if x[1] == selQuest then q = x end end
  if not q then
    for _, x in ipairs(quests) do if not q and not (ns.QuestState and ns.QuestState(x[1]) == "done") then q = x end end
    q = q or quests[1]
    selQuest = q and q[1]
  end

  local cw = self.qcards:GetWidth() or 300
  local y = 0
  for i, x in ipairs(quests) do
    local c = self.cards[i] or questCard(self.qcards); self.cards[i] = c
    c.qid = x[1]
    local st = ns.QuestState and ns.QuestState(x[1])
    questIcon(c.qicon, st == "done" and "done" or st == "have" and "have" or "new")
    if x[3] == "B" then crest(c.c1, "A"); crest(c.c2, "H"); c.c1:Show(); c.c2:Show()
    elseif x[3] == "A" or x[3] == "H" then crest(c.c2, x[3]); c.c1:Hide(); c.c2:Show()
    else c.c1:Hide(); c.c2:Hide() end
    local on = x[1] == selQuest
    c.tint:SetShown(on); c.bar:SetShown(on)
    c.title:SetWidth(cw - 42 - 58); c.title:SetText(x[2])
    if on then c.title:SetTextColor(UI.Accent()) else c.title:SetTextColor(unpack((st == "done" or x.locked) and C.dim or C.text)) end
    local chain, k, cur = chainOf(x)
    local bits = {}
    local lvl = (x[5] or 0) > 0 and x[5] or x[4]
    if (lvl or 0) > 0 then bits[#bits + 1] = "From level " .. lvl end
    if x.locked then bits[#bits + 1] = "|cffef6b6b" .. x.locked .. "|r" end
    if chain then bits[#bits + 1] = "step " .. k .. " of " .. #chain end
    if st == "done" then bits[#bits + 1] = "|cff6fd39aDone|r" elseif st == "have" then bits[#bits + 1] = "|cffe8c35aIn your log|r" end
    c.sub:SetText(table.concat(bits, "  ·  "))
    local h = 12 + math.max(16, c.title:GetStringHeight() or 16) + 5 + 12 + 12
    c.inset:SetShown(chain ~= nil)
    if chain then
      c.steps:SetWidth(cw - 24 - 20); c.steps:SetText(chainLines(chain, k, cur))
      local ih = (c.steps:GetStringHeight() or 0) + 16
      c.inset:ClearAllPoints(); c.inset:SetPoint("TOPLEFT", 12, -h); c.inset:SetPoint("RIGHT", c, "RIGHT", -12, 0); c.inset:SetHeight(ih)
      h = h + ih + 12
    end
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetSize(cw, h); c:Show()
    y = y + h + 6
  end
  for i = #quests + 1, #self.cards do self.cards[i]:Hide() end
  self.qcards:SetHeight(math.max(1, y))
  local max = math.max(0, y - (self.qlistScroll:GetHeight() or 0))
  if (self.qlistScroll:GetVerticalScroll() or 0) > max then self.qlistScroll:SetVerticalScroll(max) end

  self.qlistScroll:SetShown(#quests > 0)
  self.qempty:SetShown(#quests == 0)
  self.qempty:SetText(ns.Site() and ns.Site().quests and "No quests listed for this dungeon." or "Quests come from your guild's website and load when you log in with the companion app running.")
  self.qdPanel:SetShown(q ~= nil)
  if q then self:ShowQuest(q) end
  return #quests
end

-- ---- refresh: trash -----------------------------------------------------------------

function page:ShowTrash(e)
  local w = (self.w or 800) - 32
  self.trashScroll:ClearAllPoints(); self.trashScroll:SetPoint("TOPLEFT", 16, -52); self.trashScroll:SetSize(w, (self.contentH or 400) - 64)
  self.trashBody:SetWidth(w)
  self.trashNote:SetWidth(w)
  local list = ns.Trash and ns.Trash.For(e.name)
  local stateNow = ns.Trash and ns.Trash.State() or "missing"
  for _, r in ipairs(self.trashRows) do r:Hide() end
  if not list then
    self.trashHead:SetText("Trash drops")
    self.trashNote:SetText(stateNow == "missing" and "Trash drops come from the QuestieDB addon (it comes with Questie). Turn it on to see them."
      or "Reading QuestieDB for every dungeon's trash drops... a couple of seconds, once per session.")
    return
  end
  -- best first; the loot filter applies here too
  local shown, hidden = {}, 0
  for _, it in ipairs(list) do
    if not ns.LootFilter or ns.LootFilter.Pass(it.id) then shown[#shown + 1] = it else hidden = hidden + 1 end
  end
  waitingItems = false
  local q = {}
  for _, it in ipairs(shown) do local _, _, quality = itemLook(it.id); q[it.id] = quality or 0 end
  table.sort(shown, function(a, b) if q[a.id] ~= q[b.id] then return q[a.id] > q[b.id] end; return a.id < b.id end)
  -- grey and white items are clutter
  local kept = {}
  for _, it in ipairs(shown) do if q[it.id] >= 2 or q[it.id] == 0 then kept[#kept + 1] = it end end
  self.trashHead:SetText("Trash drops  |cff99a1b0" .. #kept .. "|r")
  self.trashNote:SetText(#list == 0 and "QuestieDB lists no drops that only this dungeon's trash has."
    or ((hidden > 0 and (hidden .. " hidden by the loot filter. ") or "") .. "Items that drop only from this dungeon's trash (not its bosses), from QuestieDB."))
  local y = 0
  for i, it in ipairs(kept) do
    local r = self.trashRows[i] or itemCard(self.trashBody); self.trashRows[i] = r
    fillCard(r, it.id)
    local mobs = table.concat(it.mobs, ", ")
    if #mobs > 60 then mobs = mobs:sub(1, 57) .. "..." end
    r.seen:SetText(mobs)
    r.seen:SetWidth(math.floor(w * 0.45))
    local kind = ns.WishKind and ns.WishKind(it.id)
    r.wish = { boss = "Trash", dungeon = e.name }
    r.star:Show(); r.star.tex:SetDesaturated(not kind); r.star.tex:SetAlpha(kind and 1 or 0.35)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(w); r:Show()
    y = y + 52
  end
  self.trashBody:SetHeight(math.max(1, y))
  local key = "trash/" .. tostring(e.name)
  if self.trashKey ~= key then self.trashKey, self.trashTries = key, 0; self.trashScroll:SetVerticalScroll(0) end
  if waitingItems and not self.trashWait and (self.trashTries or 0) < 5 then
    self.trashTries = (self.trashTries or 0) + 1
    self.trashWait = true
    C_Timer.After(0.6, function() self.trashWait = nil; if self.trashScroll:IsVisible() then ns.RefreshUI() end end)
  end
end

-- ---- refresh ------------------------------------------------------------------------

-- ---- the grid of dungeon / raid cards --------------------------------------------------

local idByName
local function artOf(e)
  if not idByName then
    idByName = {}
    for id, d in pairs(ns.Dungeons or {}) do idByName[d.name] = id end
  end
  local id = idByName[e.name]
  return id and ns.DungeonArt and ns.DungeonArt[id] or nil
end

function page:LayoutGrid(list)
  local w = (self.w or 600) - PAD * 2
  local cols = w >= 600 and 2 or 1
  local gap = PAD
  local cw = math.floor((w - gap * (cols - 1)) / cols)
  local ch = math.max(96, math.min(150, math.floor(cw * 0.33)))
  for i, e in ipairs(list) do
    local c = self.gridCards[i]
    if not c then
      c = UI.ArtCard(self.gridBody)
      c.onClick = function(card)
        selDungeon, selBoss, selFloor, selQuest = card.entry.name, nil, nil, nil
        grid = false; jview = "bosses"
        self:Refresh()
      end
      c.onEnter = function(card)
        local x = card.entry
        GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
        GameTooltip:SetText(x.name)
        local lv = levelsOf(x)
        if lv then GameTooltip:AddLine((x.static and x.static.raid and "Raid" or "Dungeon") .. ", levels " .. lv, 0.8, 0.8, 0.8) end
        local nb = #bossesOf(x)
        if nb > 0 then GameTooltip:AddLine(nb .. (nb == 1 and " boss" or " bosses"), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine("Click to open: bosses, loot, map, quests and runs", 0.55, 0.85, 0.55)
        GameTooltip:Show()
      end
      self.gridCards[i] = c
    end
    c.entry = e
    local quests = questsOf(e)
    local done = 0
    for _, q in ipairs(quests) do if ns.QuestState and ns.QuestState(q[1]) == "done" then done = done + 1 end end
    local runs = e.stats and e.stats.runs and #e.stats.runs or 0
    local seekers = ns.LfgFor and ns.LfgFor(ns.Slug(e.name)) or {}
    local right = {}
    if runs > 0 then right[#right + 1] = runs .. (runs == 1 and " run" or " runs") end
    if #seekers > 0 then right[#right + 1] = "|cff8fe3b0" .. #seekers .. " want to run it|r" end
    local lv = levelsOf(e)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", ((i - 1) % cols) * (cw + gap), -math.floor((i - 1) / cols) * (ch + gap))
    c:SetSize(cw, ch)
    c:Set({
      art = artOf(e), title = e.name,
      tag = #quests > 0 and (done .. "/" .. #quests .. " quests") or nil, tagDone = #quests > 0 and done == #quests,
      bottomLeft = lv and ("LV " .. lv) or nil, bottomRight = table.concat(right, "   "),
    })
    c:Show()
  end
  for i = #list + 1, #self.gridCards do self.gridCards[i]:Hide() end
  local rows = math.ceil(#list / cols)
  self.gridBody:SetHeight(math.max(1, rows * (ch + gap)))
  local max = math.max(0, rows * (ch + gap) - (self.gridScroll:GetHeight() or 0))
  if (self.gridScroll:GetVerticalScroll() or 0) > max then self.gridScroll:SetVerticalScroll(max) end
end

function page:Refresh(arg)
  local list = dungeonList()
  if type(arg) == "table" and arg.dungeon then
    -- a jump from search or Home: pick the dungeon (and boss or tab)
    local want = ns.Slug(arg.dungeon)
    for _, x in ipairs(list) do
      if ns.Slug(x.name) == want then
        selDungeon, selBoss, selFloor, selQuest = x.name, arg.boss, nil, arg.quest
        kind = kindOf(x)
        grid = false
        showLink, showShared = false, false
        jview = arg.view or "bosses"
      end
    end
  end
  local e
  for _, x in ipairs(list) do if x.name == selDungeon then e = x end end
  if e then kind = kindOf(e) end
  list = listOf(kind)
  if not e then e = list[1]; selDungeon = e and e.name end
  self.entry = e
  for _, b in ipairs(self.kinds) do
    if b.kind == kind then b.label:SetTextColor(UI.Accent()) else b.label:SetTextColor(unpack(C.dim)) end
  end

  local opts = {}
  for _, x in ipairs(list) do
    local lv = levelsOf(x)
    opts[#opts + 1] = { value = x.name, label = x.name .. (lv and ("  |cff99a1b0" .. lv .. "|r") or "") }
  end
  self.picker:SetOptions(opts, selDungeon)
  self.picker.value:SetText(selDungeon or "")

  local has = e ~= nil
  -- Dungeons | Raids sit after the picker in a dungeon, at the left above the grid
  self.kinds[1]:ClearAllPoints()
  if grid then self.kinds[1]:SetPoint("TOPLEFT", PAD, -PAD + 4) else self.kinds[1]:SetPoint("LEFT", self.next, "RIGHT", 16, 0) end
  self.gridScroll:SetShown(grid)
  if grid then
    for _, el in ipairs({ self.head, self.back, self.prev, self.picker, self.next, self.empty }) do el:Hide() end
    local panels = { self.mapPanel, self.bossPanel, self.detailPanel, self.qPanel, self.qdPanel, self.runPanel, self.trashPanel }
    for _, p in ipairs(panels) do p:Hide() end
    self:LayoutGrid(list)
    if ns.SetBannerArt then ns.SetBannerArt(nil) end
    return
  end
  if ns.SetBannerArt and e then ns.SetBannerArt(artOf(e)) end
  self.back.label:SetText(kind == "raid" and "< All raids" or "< All dungeons")
  self.back:SetShown(has)
  for _, el in ipairs({ self.head, self.prev, self.picker, self.next }) do el:SetShown(has) end
  self.picker.title:SetText(kind == "raid" and "Raid" or "Dungeon")
  self.empty:SetShown(not has)
  local panels = { map = { self.mapPanel }, bosses = { self.bossPanel, self.detailPanel }, quests = { self.qPanel, self.qdPanel }, runs = { self.runPanel }, trash = { self.trashPanel } }
  for k, ps in pairs(panels) do for _, p in ipairs(ps) do p:SetShown(has and k == jview) end end
  if not has then return end

  -- header
  self.title:SetText(e.name)
  local bits = {}
  local lv = levelsOf(e)
  bits[#bits + 1] = (e.static and e.static.raid and "Raid" or "Dungeon") .. (lv and (", levels " .. lv) or "")
  local nb = #bossesOf(e)
  if nb > 0 then bits[#bits + 1] = nb .. (nb == 1 and " boss" or " bosses") end
  local s = e.stats
  if s then
    bits[#bits + 1] = #s.runs .. (#s.runs == 1 and " run" or " runs") .. (s.best and (", best " .. UI.Time(s.best.duration)) or "")
  else
    bits[#bits + 1] = "not run by the guild yet"
  end
  if e.static and e.static.wings then
    local wg = {}
    for _, x in ipairs(e.static.wings) do wg[#wg + 1] = x.name end
    bits[#bits + 1] = "wings: " .. table.concat(wg, ", ")
  end
  self.sub:SetText(table.concat(bits, "  ·  "))
  local slug = ns.Slug(e.name)
  local wantIt = ns.IsLfg and ns.IsLfg(slug)
  self.lfg.label:SetText(wantIt and "You want to run this" or "I want to run this")
  if wantIt then self.lfg.label:SetTextColor(UI.Accent()) else self.lfg.label:SetTextColor(unpack(C.text)) end
  local seekers, names = ns.LfgFor and ns.LfgFor(slug) or {}, {}
  for _, sk in ipairs(seekers) do names[#names + 1] = (sk.me and "you" or sk.name) .. (sk.level and (" " .. sk.level) or "") end
  self.lfgWho:SetText(#names > 0 and ("Want to run it: " .. table.concat(names, ", ")) or "Nobody has asked for this one yet.")

  local nq = #questsOf(e)
  local ar, ag, ab = UI.Accent()
  for _, t in ipairs(self.viewTabs) do
    local on = t.key == jview
    t.bg:SetShown(on); t.under:SetShown(on); t.under:SetColorTexture(ar, ag, ab, 1)
    t.text:SetTextColor(unpack(on and C.text or C.dim))
    if t.key == "quests" then
      local qp = ns.QuestProgress and ns.QuestProgress(e.name)
      t.text:SetText(qp and qp.total > 0 and ("Quests " .. qp.done .. "/" .. qp.total) or nq > 0 and ("Quests " .. nq) or "Quests")
    elseif t.key == "runs" then
      local nr = s and #s.runs or 0
      t.text:SetText(nr > 0 and ("Runs " .. nr) or "Runs")
    end
    t:SetWidth(math.max(92, (t.text:GetStringWidth() or 40) + 46))
    t:Show()
  end
  self:Layout(self.w or 800, self.h or 500)

  self.filterBtn.label:SetText(ns.LootFilter and ns.LootFilter.Active() and "Loot filter: on" or "Loot filter")
  self.filterBtn:SetShown(jview == "bosses" or jview == "trash")
  self.entranceBtn:ClearAllPoints()
  if self.filterBtn:IsShown() then self.entranceBtn:SetPoint("RIGHT", self.filterBtn, "LEFT", -8, 0) else self.entranceBtn:SetPoint("RIGHT", self.lfg, "LEFT", -8, 0) end
  self.entranceBtn:SetShown(ns.DungeonEntrance and ns.DungeonEntrance(e.name) ~= nil)
  if jview == "trash" then self:ShowTrash(e); return end
  if jview == "runs" then
    local runs = {}
    for i = #(s and s.runs or {}), 1, -1 do runs[#runs + 1] = s.runs[i] end
    self.runList:SetItems(runs)
    self.runEmpty:SetShown(#runs == 0)
    return
  end
  if jview == "quests" then
    if self.qdungeon ~= e.name then self.qdungeon = e.name; self.qlistScroll:SetVerticalScroll(0) end
    self:LayoutQuests(e)
    return
  end

  local bosses = bossesOf(e)
  local found = false
  for _, b in ipairs(bosses) do if b.name == selBoss then found = true end end
  if not found then selBoss = bosses[1] and bosses[1].name end

  if jview == "map" then
    local floors = floorsOf(e)
    local valid = false
    local cur
    local curN
    for i, fl in ipairs(floors) do if fl.key == selFloor then cur, curN = fl, i end end
    if not cur then cur, curN = floors[1], 1; selFloor = cur and cur.key end
    local bx = self.mapX or 16
    for i, fl in ipairs(floors) do
      local b = self.floorButtons[i]
      if not b then b = UI.Button(self.mapPanel, "", 80, 24, function(btn) selFloor = btn.map; ns.RefreshUI() end); self.floorButtons[i] = b end
      b.map = fl.key
      b.label:SetText(fl.name or ("Floor " .. i))
      b:SetWidth(math.min(170, b.label:GetStringWidth() + 20))
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", bx, -16)
      if fl.key == selFloor then b.label:SetTextColor(UI.Accent()) else b.label:SetTextColor(unpack(C.text)) end
      bx = bx + b:GetWidth() + 6
      b:SetShown(#floors > 1)
    end
    for i = #floors + 1, #self.floorButtons do self.floorButtons[i]:Hide() end
    -- where each boss stands: placed by you or the guild, else seen in your runs, else the game's own data
    local onMap = ns.EncounterPins and ns.EncounterPins(floors) or {}
    local ids = {}
    for _, sb in ipairs(e.static and e.static.bosses or {}) do ids[sb.name] = sb.ids end
    local pins, unplaced = {}, {}
    for _, b in ipairs(bosses) do
      local f, x, y = ns.BossPin and ns.BossPin(e.name, b.name)
      local p
      if f then
        if ns.PinOnFloor(f, cur, curN) then p = { x = x, y = y } end
      else
        for _, q in ipairs(b.pins or {}) do if cur and cur.map and q.m == cur.map then p = q end end
        if not p and #(b.pins or {}) == 0 then
          for _, id in ipairs(ids[b.name] or {}) do
            local q = onMap[id]
            if q and cur and q.m == cur.map then p = q; break end
          end
        end
      end
      if p then pins[#pins + 1] = { x = p.x, y = p.y, n = b.n, key = b.name, label = b.name, on = b.name == selBoss }
      elseif not f then unplaced[#unplaced + 1] = b.name end
    end
    self.map:SetShown(#floors > 0)
    if cur then self.map:Draw(cur.map, self.mapW or 400, self.mapH or 267, pins, cur.tiles) end

    -- placing pins: click the map where each boss stands, one after another
    local dungeon = e.name
    self.placeBtn:SetShown(cur ~= nil and #bosses > 0)
    if placing and placing.dungeon ~= dungeon then placing = nil end
    if placing and not bosses[placing.i] then placing = nil end
    self.placeBtn.label:SetText(placing and "Done" or "Place bosses")
    self.skipBtn:SetShown(placing ~= nil)
    if placing then
      local who = bosses[placing.i].name
      self.map.onClick = function(x, y, button)
        if button ~= "LeftButton" or not cur then return end
        ns.SetBossPin(dungeon, who, cur.fid, x, y)
        placing.i = placing.i + 1
        if not bosses[placing.i] then placing = nil; ns.say("Boss pins saved and shared with the guild.") end
        ns.RefreshUI()
      end
      self.mapNote:SetText(string.format("|cffffd27aClick the map where %d. %s stands.|r  Skip moves on; right-click a pin removes it; Done stops.", placing.i, who))
    else
      self.map.onClick = nil
      self.mapNote:SetText(#floors == 0 and "The game has no map picture for this dungeon."
        or (#pins == 0 and "No boss locations on this floor yet. Press Place bosses and click where each one stands (the skulls on the map)."
        or ("Hover a boss for its loot, click it for the loot list. Numbers are the boss order."
          .. (#unplaced > 0 and ("  Not placed yet: " .. table.concat(unplaced, ", ") .. ".") or ""))))
    end
    self.map.onPin = function(name, button, pinFrame)
      if button == "RightButton" then
        if placing then ns.SetBossPin(dungeon, name, nil, nil, nil); ns.RefreshUI()
        else selBoss = name; jview = "bosses"; ns.RefreshUI() end
        return
      end
      ns.ShowBossLootPopup(pinFrame, dungeon, name)
    end
    self.map.onPinEnter = function(pinFrame, tip)
      local name = pinFrame.key
      local boss
      for _, b in ipairs(bosses) do if b.name == name then boss = b end end
      tip:SetText(name)
      local lvl = e.static and (function() for _, sb in ipairs(e.static.bosses or {}) do if sb.name == name then return sb.level end end end)()
      if lvl then tip:AddLine("Level " .. lvl, 0.7, 0.72, 0.78) end
      tip:AddLine(recordText(e, name), 0.7, 0.72, 0.78)
      local loot = boss and lootOf(e, boss) or {}
      if #loot > 0 then
        tip:AddLine(" ")
        for i, it in ipairs(loot) do
          if i > 10 then tip:AddLine("+ " .. (#loot - 10) .. " more", 0.6, 0.63, 0.69); break end
          local iname, _, quality, icon = itemLook(it.id, it.name)
          local r, g, bl = qualityRGB(quality)
          tip:AddLine((icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. (iname or ("item " .. it.id)), r, g, bl)
        end
      else
        tip:AddLine("No loot known yet.", 0.6, 0.63, 0.69)
      end
      tip:AddLine(" ")
      tip:AddLine("Click: loot list (hover items for details)", 0.55, 0.85, 0.55)
      tip:AddLine(placing and "Right-click: remove this pin" or "Right-click: open the boss page", 0.55, 0.85, 0.55)
    end
    return
  end

  -- bosses
  local npcs = {}
  for _, b in ipairs(bosses) do
    local look, npc = visual(e, b.name)
    if not look and npc then npcs[#npcs + 1] = npc end
  end
  resolveLooks(npcs)
  if self.bdungeon ~= e.name then self.bdungeon = e.name; self.bosses.offset = 0 end
  self.bossHead:SetText("Bosses  |cff99a1b0" .. #bosses .. "|r")
  self.bosses:SetItems(bosses)
  local boss
  for _, b in ipairs(bosses) do if b.name == selBoss then boss = b end end
  self:ShowBoss(e, boss)
end

-- ---- boss loot popup (right-click a boss on the dungeon tracker) ------------------------
local pop
function ns.ShowBossLootPopup(anchor, dungeonName, bossName)
  if not (dungeonName and bossName) then return end
  if pop and pop:IsShown() and pop.key == dungeonName .. "/" .. bossName then pop:Hide(); return end
  local e
  for _, x in ipairs(dungeonList()) do if ns.Slug(x.name) == ns.Slug(dungeonName) then e = x end end
  local boss
  for _, b in ipairs(e and bossesOf(e) or {}) do if b.name == bossName then boss = b end end
  local loot = (e and boss) and lootOf(e, boss) or {}
  local shown = {}
  for _, it in ipairs(loot) do if not ns.LootFilter or ns.LootFilter.Pass(it.id) then shown[#shown + 1] = it end end
  if not pop then
    pop = CreateFrame("Frame", "FoxdenBossLoot", UIParent)
    pop:SetFrameStrata("DIALOG"); pop:EnableMouse(true)
    UI.Fill(pop, C.surface); UI.Border(pop)
    pop.title = UI.Text(pop, 13); pop.title:SetPoint("TOPLEFT", 12, -10)
    pop.close = UI.CloseButton(pop, function() pop:Hide() end); pop.close:SetPoint("TOPRIGHT", -4, -4)
    pop.note = UI.Text(pop, 11, C.dim); pop.note:SetWordWrap(true)
    pop.rows = {}
    if UISpecialFrames then tinsert(UISpecialFrames, "FoxdenBossLoot") end
  end
  local W = 300
  pop.key = dungeonName .. "/" .. bossName
  pop.title:SetText(bossName)
  local y = 34
  waitingItems = false
  for i, it in ipairs(shown) do
    if i > 12 then break end
    local r = pop.rows[i] or itemCard(pop, 40); pop.rows[i] = r
    fillCard(r, it.id, it.name)
    local kind = ns.WishKind and ns.WishKind(it.id)
    r.seen:SetText(kind and (ns.WISH_COLOR[kind] .. ns.WISH_LABEL[kind] .. "|r") or "")
    r.wish = { boss = bossName, dungeon = dungeonName }
    r.star:Show(); r.star.tex:SetDesaturated(not kind); r.star.tex:SetAlpha(kind and 1 or 0.35)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -y); r:SetWidth(W - 20); r:Show()
    y = y + 44
  end
  for i = math.min(#shown, 12) + 1, #pop.rows do pop.rows[i]:Hide() end
  pop.note:ClearAllPoints(); pop.note:SetPoint("TOPLEFT", 12, -y - 2); pop.note:SetWidth(W - 24)
  pop.note:SetText(#loot == 0 and "No loot known for this boss yet." or (#shown < #loot and ((#loot - #shown) .. " hidden by the loot filter.") or ""))
  y = y + ((pop.note:GetText() or "") ~= "" and 22 or 4)
  pop:SetSize(W, y + 8)
  pop:ClearAllPoints()
  local x = anchor:GetCenter()
  if x and x > (UIParent:GetWidth() or 1000) / 2 then pop:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0) else pop:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0) end
  pop:Show()
  -- item names arrive a moment after we ask: draw again once
  if waitingItems then C_Timer.After(0.6, function() if pop:IsShown() and pop.key == dungeonName .. "/" .. bossName then pop:Hide(); ns.ShowBossLootPopup(anchor, dungeonName, bossName) end end) end
end

ns.RegisterPage(page)
