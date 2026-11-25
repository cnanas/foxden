-- Proc flashes: glowing arcs beside your character while a reactive ability is ready,
-- like the modern game's spell alerts, one design per ability, for every class.
-- This client hides buffs from addons in combat, so nothing here reads a buff. Three signals:
--   usable  - the game says the ability can be pressed now (Revenge, Riposte, Hammer of Wrath...)
--   instant - a spell with a cast time has become instant (Shadow Trance, Hot Streak, Surge of Light...)
--   free    - a spell that costs mana has become free (Clearcasting)
-- Warriors also get an icon while Battle Shout is missing.
-- The art is our own (Media/Procs, drawn by tools/make-proc-art.py): this client ships none.
local _, ns = ...

local ART = "Interface\\AddOns\\Foxden\\Media\\Procs\\"
local W, H = 128, 256

-- spell = rank 1 id (only used to get the name in your language; the name finds the rank you know)
-- window = seconds the proc lasts (we time it ourselves for the "about to expire" blink)
local BY_CLASS = {
  WARRIOR = {
    -- each flash has a fixed place so you learn where to look: most used closest in
    { key = "revenge",   art = "revenge",   spell = 6572,   fallback = "Revenge",      window = 5,  where = "sides", dist = 190, color = { 1.00, 0.45, 0.08 } },
    { key = "overpower", art = "overpower", spell = 7384,   fallback = "Overpower",    window = 5,  where = "sides", dist = 334, color = { 0.55, 0.78, 1.00 } },
    { key = "victory",   art = "victory",   spell = 402927, fallback = "Victory Rush", window = 20, where = "sides", dist = 262, color = { 1.00, 0.86, 0.22 } },
    { key = "execute",   art = "execute",   spell = 5308,   fallback = "Execute",      where = "top",   dist = 170, color = { 1.00, 0.16, 0.10 } },
  },
  ROGUE = {
    { key = "riposte", art = "riposte", spell = 14251, fallback = "Riposte", window = 5, where = "sides", dist = 190, color = { 1.00, 0.88, 0.25 } },
  },
  HUNTER = {
    { key = "mongoose",      art = "mongoose",      spell = 1495,  fallback = "Mongoose Bite", window = 5, where = "sides", dist = 190, color = { 0.50, 1.00, 0.30 } },
    { key = "counterattack", art = "counterattack", spell = 19306, fallback = "Counterattack", window = 5, where = "sides", dist = 262, color = { 0.25, 0.95, 0.80 } },
  },
  PALADIN = {
    { key = "hammer", art = "hammer", spell = 24275, fallback = "Hammer of Wrath", where = "top", dist = 170, color = { 1.00, 0.86, 0.50 } },
  },
  -- casters: "watch" lists spells to test, first one in your spellbook wins
  MAGE = {
    { key = "clearcast", art = "arcane", label = "Clearcasting",                 detect = "free",    watch = { 116, 133, 5143 }, window = 15, where = "sides", dist = 190, color = { 0.78, 0.45, 1.00 } },
    { key = "pyro",      art = "flame",  label = "Instant Pyroblast",            detect = "instant", watch = { 11366 },          window = 10, where = "sides", dist = 262, color = { 1.00, 0.38, 0.08 } },
    { key = "fireball",  art = "ice",    label = "Instant Fireball",             detect = "instant", watch = { 133 },            window = 15, where = "top",   dist = 170, color = { 0.50, 0.82, 1.00 } },
  },
  WARLOCK = {
    { key = "trance", art = "shadow", label = "Shadow Trance (instant Shadow Bolt)", detect = "instant", watch = { 686 }, window = 10, where = "sides", dist = 190, color = { 0.66, 0.34, 1.00 } },
  },
  PRIEST = {
    { key = "surge", art = "wings", label = "Instant Smite or Flash Heal", detect = "instant", watch = { 585, 2061 }, any = true, window = 10, where = "sides", dist = 190, color = { 1.00, 0.92, 0.66 } },
  },
  DRUID = {
    { key = "clearcast", art = "moon", label = "Clearcasting",          detect = "free",    watch = { 5176, 5185 }, window = 15, where = "top",   dist = 170, color = { 0.60, 0.80, 1.00 } },
    { key = "swift",     art = "vine", label = "Instant Healing Touch", detect = "instant", watch = { 5185 },                    where = "sides", dist = 190, color = { 0.42, 1.00, 0.45 } },
  },
  SHAMAN = {
    { key = "clearcast", art = "lightning", label = "Clearcasting",           detect = "free",    watch = { 403 }, window = 15, where = "sides", dist = 190, color = { 0.45, 0.72, 1.00 } },
    { key = "maelstrom", art = "maelstrom", label = "Instant Lightning Bolt", detect = "instant", watch = { 403 }, window = 30, where = "sides", dist = 262, color = { 0.30, 0.90, 0.95 } },
  },
}
local PROCS = {} -- this character's class, set on login
local CLASS
local function isWarrior() return CLASS == "WARRIOR" end

local SHOUT = { spell = 6673, fallback = "Battle Shout", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", level = 0, on = false }

local root, testUntil

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function usable(name)
  -- returns: ready to press, and whether the proc itself is up (ready, or only short on rage)
  local ok, noPower
  if C_Spell and C_Spell.IsSpellUsable then ok, noPower = C_Spell.IsSpellUsable(name)
  elseif IsUsableSpell then ok, noPower = IsUsableSpell(name) end
  if issecretvalue and issecretvalue(noPower) then noPower = false end
  if not ok then return false, noPower == true end
  -- ready to press: ignore the global cooldown, hide during the ability's own cooldown
  local start, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(name)
    if cd then start, dur = cd.startTime, cd.duration end
  elseif GetSpellCooldown then
    start, dur = GetSpellCooldown(name)
  end
  -- in combat this client hides cooldown numbers from addons ("secret" values): they can't be
  -- compared, so trust "usable" alone then
  if issecretvalue and (issecretvalue(start) or issecretvalue(dur)) then return true, true end
  return not (start and dur and start > 0 and dur > 1.6), true
end

-- has a spell that normally takes time to cast become instant? (nil when the game won't say)
local function isInstant(name)
  local t
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(name)
    t = i and i.castTime
  elseif GetSpellInfo then
    t = select(4, GetSpellInfo(name))
  end
  if t == nil or (issecretvalue and issecretvalue(t)) then return nil end
  return t == 0
end

-- has a spell that normally costs something become free? (nil when the game won't say)
local function isFree(name)
  local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(name)
    or (GetSpellPowerCost and GetSpellPowerCost(name))
  if type(costs) ~= "table" or #costs == 0 then return nil end
  for _, c in ipairs(costs) do
    local v = c.cost
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    if v > 0 then return false end
  end
  return true
end

-- one proc: ready to show, and whether the proc itself is up
local function check(p)
  if p.detect == "instant" or p.detect == "free" then
    local test = p.detect == "instant" and isInstant or isFree
    for _, name in ipairs(p.names or {}) do
      local r = test(name)
      if r == true then return true, true end
      if r == false and not p.any then return false, false end -- first spell you know decides
    end
    return false, false
  end
  return usable(p.name)
end

-- the aura if you have the buff. Only readable out of combat: in a fight this client hides
-- buffs from addons (by name it just says nil; by index it errors).
local function findBuff(name)
  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    return C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
  end
  if AuraUtil and AuraUtil.FindAuraByName then
    local n, _, _, _, _, expires = AuraUtil.FindAuraByName(name, "player", "HELPFUL")
    return n and { expirationTime = expires } or nil
  end
end

local SHOUT_LASTS = 120

-- Battle Shout missing while it matters: in a fight, or anywhere inside a dungeon or raid.
-- Out of combat we read the buff and remember when it runs out; in combat we go by that
-- memory, renewed when you cast it yourself. (Someone else's shout landing mid-fight is not seen.)
local function needShout()
  if not SHOUT.name or not SHOUT.known then return false end
  if UnitIsDeadOrGhost("player") then return false end
  local fighting = UnitAffectingCombat("player")
  if not fighting then
    local ok, a = pcall(findBuff, SHOUT.name)
    if ok then
      if a then
        local e = a.expirationTime
        local hidden = issecretvalue and issecretvalue(e)
        SHOUT.expires = (not hidden and type(e) == "number" and e > 0) and e or (GetTime() + SHOUT_LASTS)
      else
        SHOUT.expires = nil
      end
    end
  end
  if not (fighting or IsInInstance()) then return false end
  return not (SHOUT.expires and GetTime() < SHOUT.expires)
end

-- your own casts: the one way to see a shout go up mid-fight
local function onCast(unit, spellID)
  if unit ~= "player" then return end
  if issecretvalue and issecretvalue(spellID) then SHOUT.lastCast = "<hidden>"; return end
  SHOUT.lastCast = spellID
  local ok, name = pcall(spellName, spellID)
  if ok and name and name == SHOUT.name then SHOUT.expires = GetTime() + SHOUT_LASTS end
end

local function buildShout()
  local f = CreateFrame("Frame", nil, root)
  f:SetSize(46, 46); f:SetPoint("CENTER", 0, -150); f:SetAlpha(0); f:Hide()
  local glow = f:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  glow:SetBlendMode("ADD"); glow:SetVertexColor(1, 0.25, 0.12)
  glow:SetPoint("CENTER"); glow:SetSize(84, 84)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetTexture(SHOUT.icon)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOP", f, "BOTTOM", 0, -4)
  label:SetTextColor(1, 0.82, 0.7)
  SHOUT.frame, SHOUT.label = f, label
end

local function arc(parent, art, color, flip)
  local set = {}
  for i, file in ipairs({ art, art .. "_core" }) do
    local t = parent:CreateTexture(nil, "ARTWORK", nil, i)
    t:SetTexture(ART .. file)
    t:SetBlendMode("ADD")
    t:SetSize(W, H)
    if flip then t:SetTexCoord(1, 0, 0, 1) end
    if i == 1 then t:SetVertexColor(color[1], color[2], color[3])
    else t:SetVertexColor(1, 0.94, 0.78, 0.9) end
    set[i] = t
  end
  return set
end

local function build()
  if root then return end
  root = CreateFrame("Frame", "FoxdenProcs", UIParent)
  root:SetSize(1, 1)
  root:SetPoint("CENTER", 0, 10)
  root:SetFrameStrata("LOW")
  for _, p in ipairs(PROCS) do
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(1, 1); f:SetPoint("CENTER"); f:SetAlpha(0); f:Hide()
    if p.where == "sides" then
      p.left, p.right = arc(f, p.art, p.color, false), arc(f, p.art, p.color, true)
      for _, t in ipairs(p.left) do t:SetPoint("CENTER", -p.dist, 0) end
      for _, t in ipairs(p.right) do t:SetPoint("CENTER", p.dist, 0) end
    else
      for _, t in ipairs(arc(f, p.art, p.color, false)) do
        t:SetPoint("CENTER", 0, p.dist)
        if t.SetRotation then t:SetRotation(-math.pi / 2) end
      end
    end
    p.frame, p.level, p.on = f, 0, false
  end
  buildShout()

  local since = 0
  root:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since >= 0.12 then
      since = 0
      local testing = testUntil and GetTime() < testUntil
      if testUntil and not testing then testUntil = nil end
      for _, p in ipairs(PROCS) do
        local ok, ready, up = pcall(check, p)
        local off = ns.settings.procOff and ns.settings.procOff[CLASS .. "." .. p.key]
        local enabled = ns.settings.procs ~= false and not off and p.name ~= nil and ok
        p.on = testing or (enabled and ready == true)
        -- time the proc ourselves (the game doesn't say how long is left)
        local active = testing or (enabled and up == true)
        if active and not p.active then
          p.since = GetTime()
          if not testing and ns.settings.procSound and p.on then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "SFX") end
        end
        p.active = active or false
        p.win = testing and 8 or p.window
      end
      SHOUT.on = (testing and isWarrior()) or (ns.settings.shoutReminder ~= false and needShout())
    end
    local now = GetTime()
    for _, p in ipairs(PROCS) do
      local target = p.on and 1 or 0
      if p.level ~= target then
        local step = dt / (p.on and 0.18 or 0.30)
        p.level = p.on and math.min(1, p.level + step) or math.max(0, p.level - step)
      end
      if p.level <= 0 then
        if p.frame:IsShown() then p.frame:Hide() end
      else
        if not p.frame:IsShown() then p.frame:Show() end
        -- pops in slightly large and settles, then breathes while it is up
        p.frame:SetScale(1 + 0.22 * (1 - p.level))
        -- last two seconds of the window: a fast, deep blink
        local left = p.win and p.since and (p.win - (now - p.since))
        if left and left <= 2 and left > -0.5 then
          p.frame:SetAlpha(p.level * (0.78 + 0.22 * math.sin(now * 10)))
        else
          p.frame:SetAlpha(p.level * (0.82 + 0.18 * math.sin(now * 5)))
        end
      end
    end
    local s = SHOUT
    local target = s.on and 1 or 0
    if s.level ~= target then
      local step = dt / 0.25
      s.level = s.on and math.min(1, s.level + step) or math.max(0, s.level - step)
    end
    if s.level <= 0 then
      if s.frame:IsShown() then s.frame:Hide() end
    else
      if not s.frame:IsShown() then s.frame:Show() end
      s.frame:SetAlpha(s.level * (0.7 + 0.3 * math.sin(now * 4)))
    end
  end)
end


-- on for warriors with the setting on (or while testing); otherwise nothing runs at all
function ns.RefreshProcs()
  local s = ns.settings
  if not CLASS then
    CLASS = select(2, UnitClass("player"))
    PROCS = BY_CLASS[CLASS] or {}
  end
  local want = (s.procs ~= false and #PROCS > 0) or (s.shoutReminder ~= false and isWarrior()) or (testUntil ~= nil)
  if not want then
    if root then root:Hide() end
    return
  end
  build()
  local war = isWarrior()
  for _, p in ipairs(PROCS) do
    if p.watch then
      p.names = {}
      for _, id in ipairs(p.watch) do p.names[#p.names + 1] = spellName(id) end
      p.name = p.label
    else
      p.name = spellName(p.spell) or p.fallback
    end
  end
  SHOUT.name = spellName(SHOUT.spell) or SHOUT.fallback
  SHOUT.known = war -- every warrior has it from level 1; asking the game by rank can wrongly say no
  SHOUT.label:SetText(SHOUT.name)
  root:SetScale(ns.settings.procScale or 1)
  root:Show()
end

-- for the settings page: this class's flashes as { id, name } (id is the key saved in procOff)
function ns.ProcList()
  local class = CLASS or select(2, UnitClass("player"))
  local out = {}
  for _, p in ipairs(BY_CLASS[class or ""] or {}) do
    out[#out + 1] = { id = class .. "." .. p.key, name = p.label or spellName(p.spell) or p.fallback }
  end
  return out
end

-- /fox procs test: show this class's flashes for a few seconds
function ns.ProcsTest()
  testUntil = GetTime() + 8
  ns.RefreshProcs()
  C_Timer.After(8.5, function() ns.RefreshProcs() end)
  local names = {}
  for _, p in ipairs(PROCS) do names[#names + 1] = p.name or p.fallback end
  if #names == 0 then
    testUntil = nil
    ns.say("Proc flashes: nothing set up for your class.", true)
    return
  end
  ns.say("Proc flashes: showing " .. table.concat(names, ", ") .. " for 8 seconds (the last 2 blink).", true)
end

-- /fox procs debug: print what the game tells us right now (type it mid-fight)
function ns.ProcsDebug()
  local function show(v)
    if issecretvalue and issecretvalue(v) then return "<hidden>" end
    return tostring(v)
  end
  local function try(label, fn)
    local r = { pcall(fn) }
    local out = {}
    for i = 2, math.max(2, #r) do out[#out + 1] = show(r[i]) end
    ns.say(label .. ": " .. (r[1] and "" or "ERROR ") .. table.concat(out, ", "), true)
  end
  ns.say("procs debug: combat=" .. tostring(UnitAffectingCombat("player")) .. " shout name=" .. tostring(SHOUT.name), true)
  try("shout by name", function()
    local a = C_UnitAuras.GetAuraDataBySpellName("player", SHOUT.name, "HELPFUL")
    return a and "found" or "nil", a and a.spellId
  end)
  try("buff list", function()
    local n, hidden, hit, ids = 0, 0, "no", {}
    for i = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      n = n + 1
      if issecretvalue and issecretvalue(a.name) then hidden = hidden + 1
      else
        if a.name == SHOUT.name then hit = "yes id " .. show(a.spellId) end
        if #ids < 8 then ids[#ids + 1] = a.name end
      end
    end
    return "count " .. n, "hidden " .. hidden, "shout " .. hit, table.concat(ids, "/")
  end)
  for _, p in ipairs(PROCS) do
    if p.watch then
      for _, name in ipairs(p.names or {}) do
        try(p.key .. " watching " .. tostring(name), function()
          local i = C_Spell.GetSpellInfo(name)
          local costs = C_Spell.GetSpellPowerCost(name)
          return "cast time", i and i.castTime, "cost", costs and costs[1] and costs[1].cost
        end)
      end
      try(p.key .. " lit", function() return check(p) end)
    else
      try(p.key .. " (" .. tostring(p.name) .. ") usable by name", function() return C_Spell.IsSpellUsable(p.name) end)
      try(p.key .. " book id", function() local i = C_Spell.GetSpellInfo(p.name); return i and i.spellID end)
    end
  end
  ns.say("stance=" .. tostring(GetShapeshiftForm and GetShapeshiftForm()) .. " last cast seen=" .. tostring(SHOUT.lastCast)
    .. " shout memory=" .. tostring(SHOUT.expires and math.floor(SHOUT.expires - GetTime())), true)
  for _, p in ipairs(PROCS) do
    if not p.watch then try(p.key .. " bar button", function()
      local i = C_Spell.GetSpellInfo(p.name)
      local slots = i and C_ActionBar and C_ActionBar.FindSpellActionButtons and C_ActionBar.FindSpellActionButtons(i.spellID)
      local slot = slots and slots[1]
      if not slot then return "not on bars" end
      return "slot " .. slot, IsUsableAction(slot)
    end) end
  end
  -- can the game tell us about buff procs some other way?
  local function valid(e) return tostring(C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(e)) end
  ns.say("events: overlay show=" .. valid("SPELL_ACTIVATION_OVERLAY_SHOW") .. " glow show=" .. valid("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    .. " | api: IsSpellOverlayed=" .. tostring(IsSpellOverlayed ~= nil) .. " C_SpellActivationOverlay=" .. tostring(C_SpellActivationOverlay ~= nil)
    .. " GetPlayerAuraBySpellID=" .. tostring(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID ~= nil), true)
  try("target health", function() return UnitHealth("target"), UnitHealthMax("target") end)
  try("target health %", function() return UnitHealthPercent and UnitHealthPercent("target") or "no api" end)
end

ns.RegisterModule({
  name = "Procs",
  events = {
    PLAYER_LOGIN = function() ns.RefreshProcs() end,
    SPELLS_CHANGED = function() ns.RefreshProcs() end,
    -- a kill that gives experience restarts Victory Rush's 20 seconds
    PLAYER_XP_UPDATE = function()
      for _, p in ipairs(PROCS) do
        if p.key == "victory" and p.active then p.since = GetTime() end
      end
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(_, _, unit, _, spellID) onCast(unit, spellID) end,
  },
})
