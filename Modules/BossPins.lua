-- Module: BossPins. Where each boss stands on a dungeon's map, for the Journal's Map tab.
-- Forever's game data doesn't say, so pins come from:
--   1. pins you or a guildmate placed (Map tab > Place bosses), saved in FoxdenDB.bossPins
--   2. a few starting pins Foxden ships (measured by hand on the game's own map pictures)
-- A floor is named by its floor id (ns.DungeonFloors: "RazorfenDowns1" for a client map picture,
-- "m300" for a game map). Coordinates are 0..1000 across the picture.
--
-- Messages (prefix "Foxden", GUILD): "BP <dungeon slug> <boss> <floor id> <x> <y>" when you place
-- a pin; x = -1 removes it. Only after the welcome popup, like everything else Foxden sends.

local _, ns = ...
local PREFIX = "Foxden"

-- [dungeon slug] = { [boss] = { floor id, x, y } }
local SEEDS = {
  ["razorfen-downs"] = {
    ["Tuten'kash"] = { "RazorfenDowns1", 591, 340 },
    ["Mordresh Fire Eye"] = { "RazorfenDowns1", 443, 600 },
    ["Glutton"] = { "RazorfenDowns1", 346, 666 },
    ["Amnennar the Coldbringer"] = { "RazorfenDowns1", 857, 467 },
  },
}

local function store()
  ns.db.bossPins = ns.db.bossPins or {}
  return ns.db.bossPins
end

-- floor id, x, y of a boss's pin, or nil
function ns.BossPin(dungeon, boss)
  local slug = ns.Slug(dungeon)
  local mine = ns.db and ns.db.bossPins and ns.db.bossPins[slug] and ns.db.bossPins[slug][boss]
  if mine then
    if (mine.x or -1) < 0 then return nil end
    return mine.f, mine.x, mine.y
  end
  local s = SEEDS[slug] and SEEDS[slug][boss]
  if s then return s[1], s[2], s[3] end
end

local function save(slug, boss, f, x, y, by)
  local d = store()
  d[slug] = d[slug] or {}
  d[slug][boss] = { f = f or "", x = x, y = y, by = by, at = time() }
end

local function canSend() return ns.settings.welcomed and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage end

-- x = nil removes the pin
function ns.SetBossPin(dungeon, boss, f, x, y)
  local slug = ns.Slug(dungeon)
  save(slug, boss, f, x or -1, y or -1, UnitName("player"))
  if canSend() then ns.Send(table.concat({ "BP", slug, boss, f or "", x or -1, y or -1 }, "\t"), "GUILD") end
end

local function onMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not ns.settings.welcomed then return end
  if ns.IsSecret and (ns.IsSecret(text) or ns.IsSecret(sender)) then return end
  local kind, slug, boss, f, x, y = strsplit("\t", text)
  if kind ~= "BP" or not (slug and boss and f) then return end
  local short = Ambiguate and Ambiguate(sender or "", "short") or sender
  if short == UnitName("player") then return end
  x, y = tonumber(x), tonumber(y)
  if not (x and y) or x > 1000 or y > 1000 then return end
  save(slug, boss, f, x, y, short)
  if ns.RefreshUI then ns.RefreshUI() end
end

ns.RegisterModule({
  name = "BossPins",
  events = {
    CHAT_MSG_ADDON = function(_, _, prefix, text, channel, sender) onMessage(prefix, text, channel, sender) end,
  },
})
