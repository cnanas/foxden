-- Module: Relay. Gets your finished runs to the guild's website even if you
-- don't run the companion app yourself.
--
-- A "courier" is anyone whose companion app has written Data/SiteData.lua in the
-- last two weeks. When you have runs that haven't left your computer, Foxden asks
-- the guild for a courier and, if one answers, whispers the runs to them over
-- hidden addon messages. The courier's companion uploads them on its next pass.
-- Nothing happens before the welcome popup is answered.
--
-- Messages (prefix "Foxden"):
--   GUILD    "C?"                         anyone with runs waiting: "is a courier online?"
--   GUILD/WHISPER "C\t<siteUrl>"          a courier, at login and in answer to C?
--   WHISPER  "RS\t<id>\t<parts>\t<bytes>"  start of one run (to the courier)
--   WHISPER  "RD\t<id>\t<n>\t<data>"       part n of the run's JSON
--   WHISPER  "RA\t<id>"                   courier: got it, the run is safe with me
--
-- Courier side:  FoxdenDB.relay[sender .. "/" .. id] = { from, at, json }   (the companion reads these)
-- Sender side:   run.relayedTo = courier, run.relayedAt = time
--
-- Parcels: besides runs, a guildmate without the companion hands over what it shares with the
-- website, as one JSON "parcel" (id "P<hash>", same messages): their wishlist, "want to run" and
-- map pins, craft asks and craft requests, boss tips written in game, and notes queued for
-- Discord (text only). Sent again only when something in it changed (FoxdenDB.parcelSent = hash).
-- The courier's companion uploads each part with the same once-only checks as its own.

local _, ns = ...
local CHUNK = 200
local FRESH = 14 * 86400        -- a courier's site data must be newer than this
local KEEP_RUNS = 14 * 86400     -- only offer runs from the last two weeks
local ASK_EVERY = 15 * 60        -- seconds between "C?" while runs are waiting
local MAX_BYTES = 200000

local db
local lastAsk, lastAnswer = -1e9, {}
local incoming = {}              -- courier: [sender/id] = { parts, bytes, got = {}, count, t }
local sending                    -- sender: { run, to, sentAt }

local function me() return ns.CharKey() end
local function ready() return ns.settings.welcomed and IsInGuild() end
local function fullName(sender)
  sender = ns.SenderKey(sender) -- "Name-Realm", without Forever's second name
  return sender
end

function ns.IsCourier()
  local s = ns.SiteLive()
  return s ~= nil and type(s.at) == "number" and GetServerTime() - s.at < FRESH
end

-- The guild website's address, from our own site data or a courier's announcement.
function ns.SiteUrl()
  local s = ns.SiteLive()
  if s and type(s.site) == "string" and s.site ~= "" then return s.site end
  return db and db.siteUrl or nil
end

local function waiting()
  local list, now = {}, GetServerTime()
  if ns.IsCourier() then return list end -- our own companion uploads our runs
  for _, r in ipairs(ns.GetRuns()) do
    if not r.relayedTo and (r.endTime or 0) > now - KEEP_RUNS then list[#list + 1] = r end
  end
  return list
end
ns.RelayWaiting = waiting

-- ---- the parcel: what this character shares with the website ------------------------------
local function hash(str)
  local h = 5381
  for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end
local MAX_PARCEL = 30000
local function parcel()
  if not ns.ToJSON then return nil end
  local key, short = me(), UnitName("player")
  local p = { parcel = true, v = 1, char = key }
  p.member = db.member and db.member[key] or nil
  local function mineOnly(list, field)
    local out = {}
    for _, x in ipairs(type(list) == "table" and list or {}) do
      if type(x) == "table" and (not field or x[field] == key or x[field] == short) then out[#out + 1] = x end
    end
    return #out > 0 and out or nil
  end
  p.asks = mineOnly(db.boardAsks, "char")
  p.requests = mineOnly(db.craftRequests, "char")
  p.tips = mineOnly(db.tipOutbox, "by")
  local notes = {}
  for _, n in ipairs(type(db.notes) == "table" and db.notes or {}) do
    if type(n) == "table" and n.discord == "queued" and (n.char == key or not n.char) then
      notes[#notes + 1] = { id = n.id, char = n.char or key, at = n.at, text = n.text, loc = n.loc, discord = "queued", discordAt = n.discordAt }
    end
  end
  p.notes = #notes > 0 and notes or nil
  if not (p.member or p.asks or p.requests or p.tips or p.notes) then return nil end
  local ok, json = pcall(ns.ToJSON, p)
  if not ok or type(json) ~= "string" or #json > MAX_PARCEL then return nil end
  return json, hash(json)
end
local function parcelDue()
  if ns.IsCourier() then return nil end -- our own companion uploads it
  local json, h = parcel()
  if json and h ~= db.parcelSent then return json, h end
end

local function ask(force)
  if not ready() or sending then return end
  if #waiting() == 0 and not parcelDue() then return end
  if not force and GetTime() - lastAsk < ASK_EVERY then return end
  lastAsk = GetTime()
  ns.Send("C?", "GUILD")
end

local function announce(to)
  if not (ready() and ns.IsCourier()) then return end
  local url = ns.SiteUrl() or ""
  if to then ns.Send("C\t" .. url, "WHISPER", to) else ns.Send("C\t" .. url, "GUILD") end
end

-- ---- sending a run to a courier ----------------------------------------------

local function sendNext(to)
  if sending then return end
  local run = waiting()[1]
  local json, id
  if run then
    json, id = ns.RunForTransfer(run), run.id
    if #json > MAX_BYTES then run.relayedTo = "too large"; return sendNext(to) end
    sending = { run = run, id = id, to = to, sentAt = nil }
  else
    local pj, h = parcelDue()
    if not pj then return end
    json, id = pj, "P" .. h
    sending = { parcel = h, id = id, to = to, sentAt = nil }
  end
  local parts = math.ceil(#json / CHUNK)
  ns.Send(table.concat({ "RS", id, parts, #json }, "\t"), "WHISPER", to)
  for i = 1, parts do
    local last = i == parts
    ns.Send(table.concat({ "RD", id, i, json:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"), "WHISPER", to, false,
      last and function()
        sending.sentAt = GetTime()
        -- no answer within a minute and a half: give up for now, ask again later
        C_Timer.After(90, function()
          if sending and sending.id == id and GetTime() - (sending.sentAt or 0) >= 89 then sending = nil end
        end)
      end or nil)
  end
end

-- ---- receiving ---------------------------------------------------------------

local function store(from, id, json)
  db.relay = db.relay or {}
  -- forget relayed runs after a month; the companion has had plenty of chances
  local now, n = GetServerTime(), 0
  for k, v in pairs(db.relay) do
    if now - (v.at or 0) > 30 * 86400 then db.relay[k] = nil else n = n + 1 end
  end
  if n >= 200 then return false end
  db.relay[from .. "/" .. id] = { from = from, at = now, json = json }
  return true
end

local function onMessage(prefix, text, channel, sender)
  if prefix ~= ns.PREFIX or ns.IsSecret(text) or ns.IsSecret(sender) then return end
  sender = fullName(sender)
  if sender == me() then return end
  local kind, a, b, c = strsplit("\t", text, 4)

  if kind == "C?" and channel == "GUILD" then
    if ns.IsCourier() and GetTime() - (lastAnswer[sender] or -1e9) > 20 then
      lastAnswer[sender] = GetTime()
      C_Timer.After(1 + math.random() * 3, function() announce(sender) end)
    end

  elseif kind == "C" then
    if a and a:match("^https?://[%w%.%-:/]+$") then db.siteUrl = a end
    -- first courier to answer gets our waiting runs, then our parcel
    if not sending and (#waiting() > 0 or parcelDue()) then sendNext(sender) end

  elseif kind == "RS" and channel == "WHISPER" and ns.IsCourier() then
    local parts, bytes = tonumber(b), tonumber(c)
    if a and parts and bytes and parts > 0 and parts <= 2000 and bytes <= MAX_BYTES then
      incoming[sender .. "/" .. a] = { parts = parts, bytes = bytes, got = {}, count = 0, t = GetTime() }
    end

  elseif kind == "RD" and channel == "WHISPER" then
    local key, n = sender .. "/" .. (a or ""), tonumber(b)
    local inc = incoming[key]
    if not (inc and n and c) or inc.got[n] then return end
    inc.got[n], inc.count = c, inc.count + 1
    if inc.count == inc.parts then
      incoming[key] = nil
      local json = table.concat(inc.got, "", 1, inc.parts)
      if #json == inc.bytes and json:sub(1, 1) == "{" and store(sender, a, json) then
        ns.Send("RA\t" .. a, "WHISPER", sender)
        if tostring(a):sub(1, 1) == "P" then
          ns.say(string.format("Passed along %s's wishlist, requests and tips; your companion will upload them.", (sender:gsub("%-.*", ""))))
        else
          ns.say(string.format("Passed along a run from %s; your companion will upload it.", (sender:gsub("%-.*", ""))))
        end
      end
    end

  elseif kind == "RA" and channel == "WHISPER" then
    if sending and sending.to == sender and sending.id == a then
      if sending.run then
        sending.run.relayedTo, sending.run.relayedAt = sender, GetServerTime()
        ns.say(string.format("Run sent to %s for the website: %s.", (sender:gsub("%-.*", "")), sending.run.dungeon or "dungeon"))
      else
        -- the parcel: wishlist, requests, tips, notes are on their way to the website
        db.parcelSent = sending.parcel
        ns.say(string.format("Your wishlist, requests and tips went to %s for the guild website.", (sender:gsub("%-.*", ""))))
      end
      sending = nil
      ns.Changed()
      C_Timer.After(2, function() sendNext(sender) end)
    end
  end
end

ns.RegisterModule({
  name = "Relay",
  OnLoad = function(_, saved) db = saved end,
  OnRunSaved = function() C_Timer.After(10, function() ask(true) end) end,
  events = {
    PLAYER_LOGIN = function()
      C_Timer.After(25, function() announce(); ask(true) end)
      if C_Timer.NewTicker then C_Timer.NewTicker(60, function() ask(false) end) end
    end,
    CHAT_MSG_ADDON = function(_, _, prefix, text, channel, sender) onMessage(prefix, text, channel, sender) end,
  },
})

table.insert(ns.statusLines, function()
  if ns.IsCourier() then
    local n = 0
    for _ in pairs(db and db.relay or {}) do n = n + 1 end
    return string.format("Your companion is set up: you pass guildmates' runs to the website (%d waiting for it).", n)
  end
  local w = #waiting()
  local lines = {}
  if w > 0 then lines[#lines + 1] = string.format("%d run%s waiting for a guildmate who runs the companion.", w, w == 1 and "" or "s") end
  if parcelDue() then lines[#lines + 1] = "Your wishlist, requests or tips are waiting for a guildmate who runs the companion." end
  return #lines > 0 and table.concat(lines, " ") or nil
end)
