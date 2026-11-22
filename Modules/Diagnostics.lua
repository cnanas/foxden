-- Module: Diagnostics. Foxden's own error log and a self-test.
--
-- Error log: Foxden's Lua errors (even when the game hides errors), and any part of a page that
-- failed to draw (UI.Guard). The last 50, with the version and a count; a short chat notice once
-- a session. /fox errors shows them with a box to copy everything, to paste into a report.
--   FoxdenDB.errors = { { msg, where, at, version, n }, ... }  newest first
--
-- Self-test: /fox selftest opens every page, switches the theme there and back, checks that the
-- dungeon, profession and class pictures load and that the data is there, then says in chat what
-- passed and what didn't. Anything that fails goes into the error log too.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local MAX = 50
local noticed = false

local function version()
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  return meta and meta("Foxden", "Version") or "?"
end

-- Record one error. where: what was going on ("Home (dungeons)", "selftest: page Recipes", ...)
function ns.LogError(where, msg)
  if not ns.db then return end
  msg = tostring(msg or "?"):gsub("Interface[/\\]AddOns[/\\]Foxden[/\\]", ""):sub(1, 900)
  ns.db.errors = ns.db.errors or {}
  local list = ns.db.errors
  for i, e in ipairs(list) do
    if e.msg == msg and e.where == where then
      e.n, e.at, e.version = (e.n or 1) + 1, time(), version()
      table.insert(list, 1, table.remove(list, i))
      return
    end
  end
  table.insert(list, 1, { msg = msg, where = where, at = time(), version = version(), n = 1 })
  while #list > MAX do table.remove(list) end
  if not noticed then
    noticed = true
    C_Timer.After(1, function()
      if ns.say then ns.say("|cffef6b6bFoxden hit an error.|r Type /fox errors to see it (and copy it for a report).", true) end
    end)
  end
end

-- Lua errors from Foxden's files, whatever the game's "show errors" setting: wrap the error handler.
local function hookErrors()
  if not (geterrorhandler and seterrorhandler) then return end
  local previous = geterrorhandler()
  seterrorhandler(function(msg, ...)
    local text = tostring(msg)
    if text:find("AddOns[/\\]Foxden[/\\]") or text:find("^Foxden page") then
      local stack = debugstack and debugstack(3, 6, 0) or ""
      pcall(ns.LogError, "Lua error", text .. (stack ~= "" and ("\n" .. stack) or ""))
    end
    if previous then return previous(msg, ...) end
  end)
end

-- ---- /fox errors -----------------------------------------------------------------------------
local win
local function report()
  local lines = { "Foxden " .. version() .. " errors (" .. date("%Y-%m-%d %H:%M") .. ")" }
  for i, e in ipairs(ns.db and ns.db.errors or {}) do
    lines[#lines + 1] = string.format("%d. [%s] %s, v%s, x%d\n%s", i, date("%m-%d %H:%M", e.at or 0), e.where or "?", e.version or "?", e.n or 1, e.msg or "")
  end
  if #lines == 1 then lines[#lines + 1] = "No errors recorded." end
  return table.concat(lines, "\n\n")
end

function ns.ShowErrors()
  if not win then
    win = CreateFrame("Frame", "FoxdenErrors", UIParent)
    win:SetSize(560, 420); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
    win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    UI.Fill(win, C.bg); UI.Border(win)
    win.title = UI.Text(win, 14); win.title:SetPoint("TOPLEFT", 16, -14); win.title:SetText("Foxden errors")
    win.hint = UI.Text(win, 11, C.dim); win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetText("Click in the box, press Ctrl+A then Ctrl+C, and paste it into your report.")
    local close = UI.CloseButton(win, function() win:Hide() end); close:SetPoint("TOPRIGHT", -8, -8)
    local clear = UI.Button(win, "Clear", 70, 24, function() if ns.db then ns.db.errors = {} end; win.box:SetText(report()) end)
    clear:SetPoint("BOTTOMRIGHT", -12, 12)
    local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -56); sf:SetPoint("BOTTOMRIGHT", -34, 46)
    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFont(UI.Font(), 11, ""); box:SetWidth(500)
    box:SetTextColor(unpack(C.text))
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus(); win:Hide() end)
    box:SetScript("OnTextChanged", function(s, user) if user then s:SetText(win.text or "") end end)
    sf:SetScrollChild(box)
    win.box = box
    if UISpecialFrames then tinsert(UISpecialFrames, "FoxdenErrors") end
  end
  win.text = report()
  win.box:SetText(win.text)
  win:Show()
end

-- ---- /fox selftest -----------------------------------------------------------------------------
function ns.SelfTest()
  local ok, bad = 0, {}
  local function check(name, fn)
    local passed, err = pcall(fn)
    if passed and err ~= false then ok = ok + 1
    else
      bad[#bad + 1] = name .. (type(err) == "string" and (": " .. err) or "")
      ns.LogError("selftest: " .. name, err == false and "check failed" or err)
    end
  end
  -- every page: open it (builds, lays out and draws it)
  local before = ns.settings and ns.settings.page
  for _, p in ipairs(ns.pages or {}) do
    check("page " .. (p.label or p.key), function()
      ns.OpenPage(p.key)
      if p.Refresh then p:Refresh() end
    end)
  end
  -- the theme there and back
  local theme = ns.settings.theme or "dark"
  check("theme switch", function()
    UI.ApplyTheme(theme == "dark" and "light" or "dark"); UI.ApplyTheme(theme)
  end)
  -- pictures load
  local probe = UIParent:CreateTexture()
  local function loads(file) local okT, r = pcall(probe.SetTexture, probe, file); return okT and r ~= false end
  local missing = 0
  for id, art in pairs(ns.DungeonArt or {}) do if not loads(art[1]) then missing = missing + 1 end end
  check("dungeon pictures", function() if missing > 0 then error(missing .. " didn't load") end end)
  check("class icons", function() return loads("Interface\\TargetingFrame\\UI-Classes-Circles") end)
  check("rounded corners", function() return loads("Interface\\AddOns\\Foxden\\Media\\corner") end)
  check("profession pictures", function()
    local n = 0
    for _, file in pairs(ns.ProfessionArt or {}) do if not loads(file) then n = n + 1 end end
    if n > 0 then error(n .. " didn't load") end
  end)
  -- data
  check("dungeon list", function() local n = 0; for _ in pairs(ns.Dungeons or {}) do n = n + 1 end; if n < 20 then error(n .. " dungeons") end end)
  check("quest data", function() local n = 0; for _ in pairs(ns.QuestDB or {}) do n = n + 1 end; if n < 1000 then error(n .. " quests") end end)
  local site = ns.Site and ns.Site()
  local siteNote = not site and "no game data"
    or site.bundled and ("built-in game data from " .. date("%b %d", site.pricesAt or site.at or 0) .. " (no companion)")
    or ("website data from " .. (ns.Ago and ns.Ago(site.at) or "?"))
  if before then pcall(ns.OpenPage, before) end

  local total = ok + #bad
  if #bad == 0 then
    ns.say(string.format("|cff6fd39aSelf-test passed:|r %d/%d checks. %s.", ok, total, siteNote), true)
  else
    ns.say(string.format("|cffef6b6bSelf-test: %d of %d checks failed.|r %s.", #bad, total, siteNote), true)
    for i = 1, math.min(6, #bad) do ns.say("  - " .. bad[i], true) end
    ns.say("Details: /fox errors", true)
  end
end

-- "/fox errors" and "/fox selftest", ahead of the core's commands
local base = SlashCmdList.FOXDEN
SlashCmdList.FOXDEN = function(msg)
  local m = type(msg) == "string" and strtrim(msg:lower()) or ""
  if m == "errors" or m == "error" then return ns.ShowErrors() end
  if m == "selftest" or m == "self-test" or m == "test" then return ns.SelfTest() end
  return base(msg)
end

ns.RegisterModule({
  name = "Diagnostics",
  events = { PLAYER_LOGIN = function() hookErrors() end },
})
