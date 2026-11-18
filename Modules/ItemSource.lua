-- Module: ItemSource. Where an item comes from, on its tooltip: bags, loot rolls, chat links,
-- other players' gear. One or two lines at the bottom, in Foxden's colour:
--   Rhahk'Zor, The Deadmines            (boss loot: the website's lists and the guild's runs)
--   Quest: Red Silk Bandanas, Deadmines (quest rewards: dungeon quests, then every quest)
-- Key binding "Open the hovered item in Foxden" (Key Bindings > Foxden) jumps to that boss or
-- quest on the Dungeons page. Setting: "Item sources in tooltips".

local _, ns = ...
local UI = ns.UI
local index, indexFor, indexDB -- itemID -> { { kind, boss, dungeon, slug, quest, title }, ... }

local function names()
  local out = {}
  for _, d in pairs(ns.Dungeons or {}) do out[ns.Slug(d.name)] = d.name end
  return out
end

local function build()
  local site = ns.Site and ns.Site()
  if index and indexFor == site and indexDB == ns.QuestDB then return index end
  index, indexFor, indexDB = {}, site, ns.QuestDB
  local dn = names()
  local function add(id, src)
    if type(id) ~= "number" or id <= 0 then return end
    local list = index[id] or {}
    for _, x in ipairs(list) do if x.kind == src.kind and x.boss == src.boss and x.quest == src.quest then return end end
    if #list < 4 then list[#list + 1] = src end
    index[id] = list
  end
  -- boss loot: the website's lists (QuestieDB for classic dungeons + what the guild saw drop)
  for slug, bosses in pairs(site and type(site.loot) == "table" and site.loot or {}) do
    for boss, items in pairs(type(bosses) == "table" and bosses or {}) do
      for _, it in ipairs(type(items) == "table" and items or {}) do
        add(type(it) == "table" and it[1] or it, { kind = "boss", boss = boss, slug = slug, dungeon = dn[slug] or slug })
      end
    end
  end
  -- and what dropped in this computer's runs
  for _, st in ipairs(ns.Stats and ns.Stats.Dungeons() or {}) do
    for _, r in ipairs(st.runs or {}) do
      for _, l in ipairs(r.loot or {}) do
        if l.i and l.b then add(l.i, { kind = "boss", boss = l.b, slug = ns.Slug(st.name), dungeon = st.name }) end
      end
    end
  end
  -- dungeon quest rewards
  for slug, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, q in ipairs(type(rows) == "table" and rows or {}) do
      for _, field in ipairs({ 17, 18 }) do
        for _, id in ipairs(type(q[field]) == "table" and q[field] or {}) do
          add(id, { kind = "quest", quest = q[1], title = q[2], slug = slug, dungeon = dn[slug] or slug })
        end
      end
    end
  end
  -- every other quest's rewards (Blizzard's API via the website)
  for qid, rw in pairs(site and type(site.rewards) == "table" and site.rewards or {}) do
    qid = tonumber(qid)
    local r = qid and ns.QuestDB and ns.QuestDB[qid]
    if type(rw) == "table" and r then
      for _, field in ipairs({ 2, 3 }) do
        for _, id in ipairs(type(rw[field]) == "table" and rw[field] or {}) do add(id, { kind = "quest", quest = qid, title = r[1] }) end
      end
    end
  end
  return index
end
ns.ItemSources = function(id) return build()[id] end

local function addLines(tt, id)
  if not (ns.settings and ns.settings.itemSource ~= false) or type(id) ~= "number" then return end
  local list = build()[id]
  if not list then return end
  local r, g, b = UI.Accent()
  for i, src in ipairs(list) do
    if i > 2 then tt:AddLine("   ...and " .. (#list - 2) .. " more", 0.6, 0.63, 0.69); break end
    if src.kind == "boss" then tt:AddLine("|TInterface\\Icons\\INV_Misc_Head_Dragon_01:12:12|t " .. src.boss .. ", " .. src.dungeon, r, g, b)
    else tt:AddLine("|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t Quest: " .. (src.title or "?") .. (src.dungeon and (", " .. src.dungeon) or ""), r, g, b) end
  end
end

-- The hovered item: open its boss or quest on the Dungeons page (key binding).
function Foxden_OpenHoveredItem()
  local _, link = GameTooltip:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  local list = id and build()[id]
  local src = list and list[1]
  if not src then ns.say("Foxden doesn't know where that item comes from."); return end
  if src.slug and src.kind == "boss" then ns.OpenPage("journal", { dungeon = src.slug, boss = src.boss, view = "bosses" })
  elseif src.slug then ns.OpenPage("journal", { dungeon = src.slug, view = "quests", quest = src.quest })
  else ns.say("A reward from the quest " .. (src.title or "?") .. ".") end
end
function Foxden_Toggle() if ns.ToggleWindow then ns.ToggleWindow() end end
BINDING_HEADER_FOXDEN = "Foxden"
BINDING_NAME_FOXDEN_TOGGLE = "Open or close Foxden"
BINDING_NAME_FOXDEN_OPENITEM = "Open the hovered item in Foxden"

ns.RegisterModule({
  name = "ItemSource",
  events = {
    PLAYER_LOGIN = function()
      if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
          if tt and tt.AddLine and type(data) == "table" and not ns.IsSecret(data.id) then pcall(addLines, tt, data.id) end
        end)
      elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
          local _, link = tt:GetItem()
          local id = link and tonumber(link:match("item:(%d+)"))
          if id then pcall(addLines, tt, id) end
        end)
      end
    end,
  },
})
