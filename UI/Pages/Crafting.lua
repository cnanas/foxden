-- Page: Crafting overview. A tile for open requests and a picture card per profession: your
-- skill (and your other characters'), how many recipes it has, who in the guild can craft it and
-- what's on offer. Click a profession for its recipes. Crafting between guildmates is free.
-- Art: the game's own profession window backgrounds (Interface\Professions, by file ID).

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, GAP = 16, 14

local page = { key = "craftoverview", label = "Overview", order = 45 }

-- [profession] = { background art file ID, icon }
local PROF = {
  Alchemy = { 4625450, "Interface\\Icons\\Trade_Alchemy" },
  Blacksmithing = { 4625448, "Interface\\Icons\\Trade_BlackSmithing" },
  Enchanting = { 4723320, "Interface\\Icons\\Trade_Engraving" },
  Engineering = { 4722478, "Interface\\Icons\\Trade_Engineering" },
  Leatherworking = { 4723154, "Interface\\Icons\\Trade_LeatherWorking" },
  Tailoring = { 4627497, "Interface\\Icons\\Trade_Tailoring" },
  Jewelcrafting = { 4723112, "Interface\\Icons\\INV_Misc_Gem_01" },
  Inscription = { 4723119, "Interface\\Icons\\INV_Misc_Book_11" },
  Cooking = { 4671747, "Interface\\Icons\\INV_Misc_Food_15" },
  ["First Aid"] = { 4659666, "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
  Mining = { 4723189, "Interface\\Icons\\Trade_Mining" },
  Herbalism = { 4723159, "Interface\\Icons\\Trade_Herbalism" },
  Skinning = { 4723308, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
  Fishing = { 4723316, "Interface\\Icons\\Trade_Fishing" },
}
local GATHERING = { Mining = true, Herbalism = true, Skinning = true, Fishing = true }
ns.ProfessionArt = {}
for name, v in pairs(PROF) do ns.ProfessionArt[name] = v[1] end -- the window's art banner uses these

function page:Build(f)
  self.scroll = CreateFrame("ScrollFrame", nil, f)
  self.scroll:EnableMouseWheel(true)
  self.body = CreateFrame("Frame", nil, self.scroll)
  self.scroll:SetScrollChild(self.body)
  self.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (self.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  local b = self.body
  self.requests = UI.Tile(b); self.requests.onClick = function() ns.OpenPage("orders") end
  self.crafters = UI.Tile(b); self.crafters.onClick = function() ns.OpenPage("crafters") end
  self.planner = UI.Tile(b); self.planner.onClick = function() ns.OpenPage("planner") end
  self.head = UI.Text(b, 15); self.head:SetText("Professions")
  self.note = UI.Text(b, 11, C.faint); self.note:SetText("Crafting in the guild is free: bring the materials.")
  self.cards = {}
end

function page:Layout(w, h)
  self.w, self.h = w, h
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 0, 0); self.scroll:SetSize(w, h)
  self.body:SetWidth(w)
  local inner = w - PAD * 2
  local tw = math.floor((inner - GAP * 2) / 3)
  for i, t in ipairs({ self.requests, self.crafters, self.planner }) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + GAP), -PAD); t:SetSize(tw, 118)
  end
  local y = -PAD - 118 - GAP - 4
  self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", PAD, y - 4)
  self.note:ClearAllPoints(); self.note:SetPoint("LEFT", self.head, "RIGHT", 12, -1)
  self.cardTop = y - 24 - 10
  self.cols = inner >= 760 and 3 or 2
  self.cardW = math.floor((inner - GAP * (self.cols - 1)) / self.cols)
  self.cardH = math.max(96, math.min(124, math.floor(self.cardW * 0.40)))
end

function page:Refresh()
  local site = ns.Site and ns.Site()
  local c = ns.Crafting and ns.Crafting()

  -- requests for your characters, from the website
  local open = 0
  for _, o in ipairs(site and type(site.orders) == "table" and site.orders or {}) do
    if o[5] ~= "delivered" and o[5] ~= "cancelled" then open = open + 1 end
  end
  self.requests:Set({ title = "Craft requests for you", big = tostring(open), unit = open == 1 and "open" or "open",
    body = open > 0 and "Guildmates asked you to make something." or "Nothing waiting. Turn on \"Take craft requests\" in Settings to get some.",
    icon = "Interface\\Icons\\INV_Letter_15" })

  -- who can craft, by profession
  local byProf, crafters = {}, 0
  local function count(chars, mine)
    for key, ch in pairs(chars or {}) do
      local any = false
      for name, p in pairs(ch.professions or {}) do
        local e = byProf[name] or { guild = 0, mine = {} }
        if mine then e.mine[#e.mine + 1] = { key = key, skill = tonumber(p.skill) or 0, max = tonumber(p.maxSkill) or 0 }
        else e.guild = e.guild + 1 end
        byProf[name] = e
        any = true
      end
      if any and not mine then crafters = crafters + 1 end
    end
  end
  count(c and c.chars, true)
  count(c and c.guild, false)
  self.crafters:Set({ title = "Crafters in the guild", big = tostring(crafters), unit = crafters == 1 and "guildmate" or "guildmates",
    body = "Who can make what, with every recipe they know.", icon = "Interface\\Icons\\INV_Hammer_20" })
  self.planner:Set({ title = "Leveling planner", big = "Cheapest", unit = "path",
    body = "What to craft from one skill to another at today's auction prices, with one shopping list.",
    icon = "Interface\\Icons\\INV_Misc_Note_01" })

  -- recipes and offers per profession (the website's lists)
  local recipes, offers = {}, {}
  for _, r in ipairs(site and site.costs or {}) do recipes[r[4]] = (recipes[r[4]] or 0) + 1 end
  for _, l in ipairs(site and site.shop or {}) do offers[l[4]] = (offers[l[4]] or 0) + 1 end

  -- the list: your professions first, then the rest
  local list = {}
  for name in pairs(PROF) do
    if (recipes[name] or 0) > 0 or byProf[name] then list[#list + 1] = name end
  end
  local me = ns.CharKey()
  local function mine(name)
    for _, m in ipairs(byProf[name] and byProf[name].mine or {}) do if m.key == me then return m end end
  end
  table.sort(list, function(a, b2)
    local ma, mb = mine(a) and 1 or 0, mine(b2) and 1 or 0
    if ma ~= mb then return ma > mb end
    return a < b2
  end)

  for i, name in ipairs(list) do
    local card = self.cards[i]
    if not card then
      card = UI.ArtCard(self.body)
      card.onClick = function(cd)
        if GATHERING[cd.prof] or (recipes[cd.prof] or 0) == 0 then ns.OpenPage("crafters") else ns.OpenPage("recipes", { profession = cd.prof }) end
      end
      card.onEnter = function(cd)
        GameTooltip:SetOwner(cd, "ANCHOR_RIGHT")
        GameTooltip:SetText(cd.prof)
        for _, m in ipairs(byProf[cd.prof] and byProf[cd.prof].mine or {}) do
          GameTooltip:AddDoubleLine(UI.ShortName(m.key), m.skill .. (m.max > 0 and ("/" .. m.max) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddLine((GATHERING[cd.prof] or (recipes[cd.prof] or 0) == 0) and "Click: who in the guild has it" or "Click: its recipes", 0.55, 0.85, 0.55)
        GameTooltip:Show()
      end
      self.cards[i] = card
    end
    card.prof = name
    local m = mine(name)
    local alts = 0
    for _, x in ipairs(byProf[name] and byProf[name].mine or {}) do if x.key ~= me then alts = alts + 1 end end
    local right = {}
    local g = byProf[name] and byProf[name].guild or 0
    if g > 0 then right[#right + 1] = g .. (g == 1 and " crafter" or " crafters") end
    if (offers[name] or 0) > 0 then right[#right + 1] = "|cff8fe3b0" .. offers[name] .. " on offer|r" end
    local left = GATHERING[name] and "Gathering" or ((recipes[name] or 0) > 0 and (recipes[name] .. " recipes") or nil)
    if alts > 0 then left = (left and (left .. "  ·  ") or "") .. alts .. (alts == 1 and " alt" or " alts") end
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", PAD + ((i - 1) % self.cols) * (self.cardW + GAP), self.cardTop - math.floor((i - 1) / self.cols) * (self.cardH + GAP))
    card:SetSize(self.cardW, self.cardH)
    card:Set({ art = { PROF[name][1], "prof" }, icon = PROF[name][2], title = name,
      tag = m and (m.skill .. (m.max > 0 and ("/" .. m.max) or "")) or nil, tagDone = m and m.max > 0 and m.skill >= m.max,
      bottomLeft = left, bottomRight = table.concat(right, "   "), dim = not m and alts == 0 })
    card:Show()
  end
  for i = #list + 1, #self.cards do self.cards[i]:Hide() end
  local rows = math.ceil(#list / self.cols)
  self.body:SetHeight(-self.cardTop + rows * (self.cardH + GAP) + PAD)
end

ns.RegisterPage(page)
