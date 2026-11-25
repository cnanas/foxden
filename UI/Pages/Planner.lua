-- Page: Leveling planner. The cheapest way to raise a profession from one skill to
-- another at today's prices: which recipes to make at each skill, about how many, and
-- one shopping list (less what's already in your bags and bank).
--
-- At each skill point it picks the recipe with the lowest expected cost of one skill-up:
-- a recipe always gives a point while it's orange (below its yellow threshold), then less
-- often until it turns grey: chance = (grey - skill) / (grey - yellow). Whether you can
-- already learn a recipe comes from profession trainers the guild has visited (or you know it
-- already); without that it's taken as its yellow threshold: trainers never ask for more than
-- that (often exactly that), so the plan never counts on a recipe before you can learn it.
-- Things an earlier step makes (Fire Oil for Elixir of Fire Power) are used before buying more.
-- Data: ns.Site().costs (cost, yellow, grey), .mats (materials and prices), .skill.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD = 16

local page = { key = "planner", label = "Leveling planner", order = 55 }
local prof, from, to
local fromTyped, toTyped -- typed by hand; otherwise they follow your current skill and cap
local skip = {}

-- the game's live numbers first, then the last profession-window scan
local function mySkill(profession)
  local live, liveMax = ns.LiveSkill and ns.LiveSkill(profession)
  if live then return live, liveMax end
  local c = ns.Crafting and ns.Crafting()
  local me = c and c.chars and c.chars[ns.CharKey()]
  local p = me and me.professions and me.professions[profession]
  return p and tonumber(p.skill) or nil, p and tonumber(p.maxSkill) or nil
end

-- the trainer rank that lifts each cap
local RANKS = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan", [300] = "Master", [375] = "Grand Master" }

local function learnSkills()
  local map = {}
  for _, d in pairs(ns.db and ns.db.trainers and ns.db.trainers.prof or {}) do
    for _, s in ipairs(d.spells or {}) do if s.name and s.skillReq then map[s.name] = s.skillReq end end
  end
  local site = ns.Site()
  for name, req in pairs(site and type(site.skill) == "table" and site.skill or {}) do map[name] = map[name] or req end
  return map
end

-- The highest skill a trainer list read for this profession asks for (0: none read yet).
-- A recipe that turns yellow at or below it but isn't on the list isn't sold by trainers.
local function listedUpTo(profession, learn)
  local site, top = ns.Site(), 0
  for _, c in ipairs(site and site.costs or {}) do
    local req = c[4] == profession and learn[c[3]]
    if req and req > 1 and req > top then top = req end
  end
  return top
end
-- Not sold by trainers, as far as the trainer lists read so far show: quests, NPCs, drops.
local function worldRecipe(c, learn, top)
  return learn[c[3]] == nil and top > 0 and (c[10] or 0) <= top
end
ns.PlannerListedUpTo, ns.PlannerWorldRecipe = listedUpTo, worldRecipe

-- returns steps { { c = costRow, from, to, crafts, cost, estimated } }, total cost, skill reached, materials { [item] = { qty, name, each } }
-- withWorld: also use recipes no trainer sells that you don't know yet (to show what they'd save)
function ns.PlanProfession(profession, fromSkill, toSkill, skipped, withWorld)
  local site = ns.Site()
  local learn = learnSkills()
  local top = listedUpTo(profession, learn)
  local usable, known = {}, ns.KnownRecipes and ns.KnownRecipes() or {}
  for _, c in ipairs(site and site.costs or {}) do
    -- recipes from plans (drops, quests, vendors) or the world only once this character has learned them
    if c[4] == profession and (c[11] or 0) > 0 and (c[7] or -1) > 0 and not (skipped and skipped[c[1]])
      and (not ns.RecipeReachable or ns.RecipeReachable(c, known))
      and (withWorld or known[c[2]] or known[c[3]] or not worldRecipe(c, learn, top)) then usable[#usable + 1] = c end
  end
  local steps, cur, exact, reached = {}, nil, 0, fromSkill
  for s = fromSkill, toSkill - 1 do
    local best, bestCost, bestChance
    for _, c in ipairs(usable) do
      local yellow, grey = c[10] or 0, c[11]
      local mine = known[c[2]] or known[c[3]]
      local learnAt = mine and 1 or learn[c[3]] or math.max(1, yellow)
      if s < grey and s >= learnAt then
        local chance = (s < yellow) and 1 or ((grey > yellow) and (grey - s) / (grey - yellow) or 0)
        if chance > 0 then
          local cost = c[7] * math.max(1, c[6] or 1) / chance
          if cur and cur.c == c then cost = cost * 0.97 end -- stay on a recipe unless switching really saves
          if not bestCost or cost < bestCost then best, bestCost, bestChance = c, cost, chance end
        end
      end
    end
    if not best then break end
    if not cur or cur.c ~= best then
      if cur then cur.crafts = math.ceil(exact) end
      cur = { c = best, from = s, to = s + 1, crafts = 0, estimated = learn[best[3]] == nil and not (known[best[2]] or known[best[3]]) }
      steps[#steps + 1] = cur; exact = 0
    end
    exact = exact + 1 / bestChance
    cur.to = s + 1; reached = s + 1
  end
  if cur then cur.crafts = math.ceil(exact) end
  local total, mats, made = 0, {}, {}
  for _, st in ipairs(steps) do
    st.cost = st.crafts * st.c[7] * math.max(1, st.c[6] or 1)
    for _, m in ipairs(ns.MaterialsFor(st.c[2] > 0 and st.c[2] or nil, st.c[3]) or {}) do
      local need = (m[2] or 1) * st.crafts
      local own = math.min(need, made[m[1]] or 0)
      if own > 0 then
        made[m[1]] = made[m[1]] - own
        if (m[4] or -1) > 0 then st.cost = st.cost - own * m[4] end
      end
      if need > own then
        local e = mats[m[1]] or { id = m[1], qty = 0, name = m[3], each = m[4] or -1 }
        e.qty = e.qty + need - own
        mats[m[1]] = e
      end
    end
    st.cost = math.max(0, st.cost)
    total = total + st.cost
    if (st.c[2] or 0) > 0 then made[st.c[2]] = (made[st.c[2]] or 0) + st.crafts * math.max(1, st.c[6] or 1) end
  end
  return steps, total, reached, mats
end

-- How to learn a recipe, best answer first: { line, more lines... }.
-- ctx = { known, learn, hasList } (hasList: a trainer list for this profession has been read)
function ns.LearnSource(c, ctx)
  ctx = ctx or {}
  local known, learn = ctx.known or {}, ctx.learn or {}
  if known[c[2]] or known[c[3]] then return { "|cff6fd39aYou know it|r" } end
  local noted = ns.RecipeSource and ns.RecipeSource(c[3])
  if noted and not noted:find("^Trainer") then return { noted } end
  if learn[c[3]] then return { "Trainer, from skill " .. learn[c[3]] .. (noted and noted:match("^Trainer(.*)") or "") } end
  if noted then return { noted } end
  if (c[12] or 0) > 0 then
    local n = UI.ItemLook and UI.ItemLook(c[12]) or nil
    local out = { "Learned from " .. (n or ("item " .. c[12])) .. ", not a trainer" }
    for _, l in ipairs(ns.ItemSources and ns.ItemSources(c[12]) or {}) do out[#out + 1] = l end
    if #out > 1 then out[1] = (n or "Recipe item") .. ": " .. out[2] end
    return out
  end
  if ctx.top and ctx.top > 0 and (c[10] or 0) <= ctx.top then
    return { "|cffff9933Not on the trainer's list:|r a world recipe; nobody in the guild has noted where yet",
      "Forever hides some recipes until you know them. When anyone with Foxden learns it, Foxden notes where (quest, NPC, place) and shares it." }
  end
  if ctx.top and ctx.top > 0 then
    return { "|cff999fb0Check a higher-rank trainer|r: the list read so far stops at " .. ctx.top,
      "The trainer list the guild has read goes up to skill " .. ctx.top .. ". Opening a trainer that teaches the next rank fills in the rest." }
  end
  return { "|cff999fb0Check your trainer|r: nobody in the guild has read its list yet",
    "Open a trainer for this profession once with Foxden on (any character): then every recipe shows the skill it needs, or that it isn't sold there." }
end

local function numberBox(parent, onChange)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(60, 26); box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(3)
  box:SetFont(UI.Font(), 12, ""); box:SetTextColor(unpack(C.text)); box:SetTextInsets(10, 6, 0, 0)
  UI.Fill(box, C.raised); UI.Border(box)
  local function done(self) self:ClearFocus(); onChange(tonumber(self:GetText())) end
  box:SetScript("OnEnterPressed", done); box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", function(self) onChange(tonumber(self:GetText())) end)
  return box
end

function page:Build(f)
  self.prof = UI.Dropdown(f, 200, "Profession", function(v) prof = v; from, to, fromTyped, toTyped = nil, nil, false, false; skip = {}; self:Refresh() end)
  self.fromLabel = UI.Text(f, 11, C.dim); self.fromLabel:SetText("From skill")
  self.fromBox = numberBox(f, function(v) if v and v ~= from then from = math.max(1, math.min(449, v)); fromTyped = true; self:Refresh() end end)
  self.toLabel = UI.Text(f, 11, C.dim); self.toLabel:SetText("to")
  self.toBox = numberBox(f, function(v) if v and v ~= to then to = math.max(2, math.min(450, v)); toTyped = true; self:Refresh() end end)
  self.summary = UI.Text(f, 13); self.summary:SetWordWrap(true)

  self.stepsHead = UI.Text(f, 14); self.stepsHead:SetText("What to make")
  self.steps = UI.List(f, 60, function(r)
    UI.ItemRow(r, 62)
    r.range = UI.Text(r, 11, C.dim); r.range:SetPoint("LEFT", 10, 0)
    r.name = UI.Text(r, 12); r.name:SetPoint("TOPLEFT", 90, -6); r.name:SetWordWrap(false)
    r.mats = UI.Text(r, 11, C.text); r.mats:SetPoint("LEFT", 90, 0); r.mats:SetWordWrap(false)
    r.src = UI.Text(r, 10, C.dim); r.src:SetPoint("BOTTOMLEFT", 90, 6); r.src:SetWordWrap(false)
    r.skipB = UI.Button(r, "Skip", 44, 20, function(b) local st = b:GetParent().st; if st then skip[st.c[1]] = true; self:Refresh() end end)
    r.skipB:SetPoint("RIGHT", -6, 0)
    r.cost = UI.Text(r, 12, C.text, "RIGHT"); r.cost:SetPoint("RIGHT", r.skipB, "LEFT", -10, 0); r.cost:SetWidth(70)
    r.crafts = UI.Text(r, 12, C.dim, "RIGHT"); r.crafts:SetPoint("RIGHT", r.cost, "LEFT", -8, 0); r.crafts:SetWidth(40)
    -- where to learn it, in full, under the item's tooltip
    r:HookScript("OnEnter", function(row)
      if not row.srcFull then return end
      if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:AddLine(row.st and row.st.c[3] or "", 1, 1, 1) end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("How to learn it", UI.Accent())
      for _, l in ipairs(row.srcFull) do GameTooltip:AddLine(l, 0.8, 0.8, 0.85, true) end
      GameTooltip:Show()
    end)
  end, function(r, st)
    local w = self.steps:GetWidth()
    r.st = st
    r.range:SetText(st.from .. "-" .. st.to)
    UI.SetRowItem(r, st.c[2], nil, st.c[3])
    local textW = math.max(60, w - 90 - 6 - 44 - 10 - 70 - 8 - 40 - 10)
    r.name:SetWidth(textW); r.src:SetWidth(textW); r.mats:SetWidth(textW)
    r.name:SetText(st.c[3])
    -- materials for one craft, as icons: 1 [Briarthorn] 1 [Murloc Eye] 1 [Empty Vial]
    local parts = {}
    for _, m in ipairs(ns.MaterialsFor(st.c[2] > 0 and st.c[2] or nil, st.c[3]) or {}) do
      local _, _, _, icon = UI.ItemLook(m[1])
      parts[#parts + 1] = (m[2] or 1) .. " |T" .. tostring(icon or 134400) .. ":14:14|t"
    end
    r.mats:SetText(#parts > 0 and ("|cff999fb0each:|r " .. table.concat(parts, "  ")) or "")
    r.srcFull = ns.LearnSource(st.c, self.learnCtx)
    r.src:SetText(r.srcFull and r.srcFull[1] or "")
    r.crafts:SetText(st.crafts .. "x")
    r.cost:SetText(ns.Money(math.floor(st.cost + 0.5)))
  end)
  UI.Fill(self.steps, { 0, 0, 0, 0.12 })

  self.shopHead = UI.Text(f, 14); self.shopHead:SetText("Shopping list")
  self.shopTotal = UI.Text(f, 13, C.text, "RIGHT")
  self.shop = UI.List(f, 34, function(r)
    UI.ItemRow(r, 10)
    r.showMats = false
    r.name = UI.Text(r, 12); r.name:SetPoint("LEFT", 38, 0)
    r.have = UI.Text(r, 11, C.dim, "RIGHT")
    r.cost = UI.Text(r, 12, C.text, "RIGHT"); r.cost:SetPoint("RIGHT", -10, 0)
  end, function(r, m)
    local w = self.shop:GetWidth()
    r.name:SetWidth(math.max(60, w - 38 - 170))
    local n = UI.SetRowItem(r, m.id, nil, m.name)
    r.name:SetText(m.qty .. "x " .. (n or m.name or "?"))
    r.have:ClearAllPoints(); r.have:SetPoint("RIGHT", -86, 0)
    r.have:SetText(m.have > 0 and ("have " .. m.have) or "")
    if m.need == 0 then r.cost:SetText("|cff6fd39agot it|r")
    elseif m.each >= 0 then r.cost:SetText(ns.Money(m.each * m.need))
    else r.cost:SetText("|cff999fb0no price|r") end
  end)
  UI.Fill(self.shop, { 0, 0, 0, 0.12 })
  self.reset = UI.Button(f, "Bring back skipped", 150, 22, function() skip = {}; self:Refresh() end)
  self.note = UI.Text(f, 11, C.faint); self.note:SetWordWrap(true)
  self.empty = UI.EmptyNote(f)
end

function page:Layout(w, h)
  self.lastW, self.lastH = w, h
  local inner = w - PAD * 2
  self.prof:ClearAllPoints(); self.prof:SetPoint("TOPLEFT", PAD, -PAD)
  self.fromLabel:ClearAllPoints(); self.fromLabel:SetPoint("LEFT", self.prof, "RIGHT", 14, 0)
  self.fromBox:ClearAllPoints(); self.fromBox:SetPoint("LEFT", self.fromLabel, "RIGHT", 8, 0)
  self.toLabel:ClearAllPoints(); self.toLabel:SetPoint("LEFT", self.fromBox, "RIGHT", 8, 0)
  self.toBox:ClearAllPoints(); self.toBox:SetPoint("LEFT", self.toLabel, "RIGHT", 8, 0)
  self.summary:ClearAllPoints(); self.summary:SetPoint("TOPLEFT", PAD, -PAD - 40); self.summary:SetWidth(inner)
  local top = -PAD - 52 - math.max(32, math.ceil(self.summary:GetStringHeight() or 0))
  local leftW = math.floor(inner * 0.58)
  local rightX, rightW = PAD + leftW + 16, inner - leftW - 16
  local bodyH = h + top - 24 - PAD - 56
  self.stepsHead:ClearAllPoints(); self.stepsHead:SetPoint("TOPLEFT", PAD, top)
  self.reset:ClearAllPoints(); self.reset:SetPoint("TOPRIGHT", self.steps:GetParent(), "TOPLEFT", PAD + leftW, top + 4)
  self.steps:ClearAllPoints(); self.steps:SetPoint("TOPLEFT", PAD, top - 24); self.steps:SetSize(leftW, bodyH)
  self.shopHead:ClearAllPoints(); self.shopHead:SetPoint("TOPLEFT", rightX, top)
  self.shopTotal:ClearAllPoints(); self.shopTotal:SetPoint("TOPRIGHT", self.steps:GetParent(), "TOPLEFT", rightX + rightW, top)
  self.shop:ClearAllPoints(); self.shop:SetPoint("TOPLEFT", rightX, top - 24); self.shop:SetSize(rightW, bodyH)
  self.note:ClearAllPoints(); self.note:SetPoint("BOTTOMLEFT", PAD, PAD); self.note:SetWidth(inner)
  self.empty:ClearAllPoints(); self.empty:SetPoint("CENTER"); self.empty:SetWidth(inner - 60)
end

function page:Refresh()
  local site = ns.Site()
  local has = site ~= nil
  local all = { self.prof, self.fromLabel, self.fromBox, self.toLabel, self.toBox, self.summary, self.stepsHead, self.steps, self.shopHead, self.shopTotal, self.shop, self.reset, self.note }
  for _, el in ipairs(all) do el:SetShown(has) end
  self.empty:SetShown(not has)
  if not has then self.empty:SetText(ns.NO_SITE); return end

  local profs, seen = {}, {}
  for _, c in ipairs(site.costs or {}) do seen[c[4]] = (seen[c[4]] or 0) + 1 end
  for p, n in pairs(seen) do if n > 10 then profs[#profs + 1] = { value = p, label = p } end end
  table.sort(profs, function(a, b) return a.label < b.label end)
  if not prof then for _, p in ipairs(profs) do if not prof and mySkill(p.value) then prof = p.value end end end
  prof = prof or (profs[1] and profs[1].value)
  self.prof:SetOptions(profs, prof)
  local mine, cap = mySkill(prof)
  if not fromTyped or not from then from = mine or from or 1 end
  -- at the cap, plan the next rank's worth (75 points) so it's ready once you train
  if not toTyped or not to then to = math.min(450, (cap and cap > from) and cap or (from + 75)) end
  if to <= from then to = math.min(450, from + 1) end
  if not self.fromBox:HasFocus() then self.fromBox:SetText(from) end
  if not self.toBox:HasFocus() then self.toBox:SetText(to) end

  local steps, total, reached, mats = ns.PlanProfession(prof, from, to, skip)
  -- for each step's "where to learn it" line
  local learn = learnSkills()
  self.learnCtx = { known = ns.KnownRecipes and ns.KnownRecipes() or {}, learn = learn, top = listedUpTo(prof, learn) }
  -- world recipes you don't know yet that would make it cheaper: say which, and where they're from
  local worldNote = ""
  local wSteps, wTotal, wReached = ns.PlanProfession(prof, from, to, skip, true)
  if wReached >= reached and wTotal < total * 0.9 then
    local names, seenW = {}, {}
    for _, st in ipairs(wSteps) do
      local c = st.c
      if not seenW[c[3]] and worldRecipe(c, learn, self.learnCtx.top) and not (self.learnCtx.known[c[2]] or self.learnCtx.known[c[3]]) then
        seenW[c[3]] = true
        local src = ns.RecipeSource and ns.RecipeSource(c[3])
        names[#names + 1] = c[3] .. (src and (" (" .. src .. ")") or " (not sold by trainers)")
      end
    end
    if #names > 0 then
      worldNote = string.format("|cff999fb0Cheaper by %s if you learn %s.|r  ", ns.MoneyPlain and ns.MoneyPlain(math.floor(total - wTotal)) or "", table.concat(names, ", "))
    end
  end
  -- the shopping list, less what's in your bags and bank
  local c = ns.Crafting and ns.Crafting()
  local me = c and c.chars and c.chars[ns.CharKey()] or {}
  local list, shopTotal, missingPrice = {}, 0, false
  for _, m in pairs(mats) do
    m.have = ((me.bags or {})[m.id] or 0) + ((me.bank or {})[m.id] or 0)
    m.need = math.max(0, m.qty - m.have)
    if m.need > 0 then if m.each >= 0 then shopTotal = shopTotal + m.each * m.need else missingPrice = true end end
    list[#list + 1] = m
  end
  table.sort(list, function(a, b) return math.max(0, a.each) * a.need > math.max(0, b.each) * b.need end)
  self.steps:SetItems(steps); self.shop:SetItems(list)
  self.shopTotal:SetText(#list > 0 and (ns.Money(math.floor(shopTotal + 0.5)) .. (missingPrice and " +" or "")) or "")
  local nSkip = 0; for _ in pairs(skip) do nSkip = nSkip + 1 end
  self.reset:SetShown(nSkip > 0)
  -- the skill cap: every 75 points the trainer's next rank lifts it
  local capNote = ""
  if mine and cap and cap < 450 then
    local rank = RANKS[cap]
    local train = rank and ("train " .. rank .. " " .. prof .. " at a " .. prof .. " trainer") or ("train the next " .. prof .. " rank at a trainer")
    if mine >= cap then
      capNote = string.format("|cffff9933You're at your cap (%d/%d): %s before any of this gives skill-ups.|r  ", mine, cap, train)
    elseif to > cap then
      capNote = string.format("|cffff9933Your cap is %d: %s when you get there.|r  ", cap, train)
    end
  end
  if #steps == 0 then
    self.summary:SetText(capNote .. "No recipe with known prices gives skill-ups at " .. from .. ". Try another starting skill, or log in again later for fresh prices.")
  else
    local crafts = 0; for _, st in ipairs(steps) do crafts = crafts + st.crafts end
    self.summary:SetText(capNote .. string.format("%s %d to %d: about %d crafts, %s of materials%s.%s", prof, from, reached, crafts, ns.MoneyPlain(math.floor(total + 0.5)),
      shopTotal < total - 1 and (" (" .. ns.MoneyPlain(math.floor(shopTotal + 0.5)) .. " to buy after what you have)") or "",
      reached < to and ("  It stops at " .. reached .. ": nothing with known prices gives skill-ups after that.") or "") .. "  " .. worldNote)
  end
  if self.lastW then self:Layout(self.lastW, self.lastH) end -- the summary can take more lines
  self.note:SetText("Craft counts are averages: a recipe always gives a point while it's orange, then less often until it turns grey. Under each recipe: where to learn it (hover for more). Skip a recipe you can't learn and the plan works around it. Your bank is counted as of the last time you opened it.")
end

ns.RegisterPage(page)
