-- Module: AuctionPrices. Auction house prices anywhere, not only at the auctioneer.
-- The game only lets addons read the auction house at an auctioneer, so these come from the
-- guild website instead: it reads the whole auction house from Blizzard once a day, and the
-- companion app brings the prices into the game with the rest of the site data.
--   * Item tooltips: "Auction: 1g 20s each (14 listed)", with the age when it's over a day old.
--   * /fox price <item>: shift-click an item into the box, or type its name.
-- Data: ns.Site().ah = { [itemID] = { fair, lowest, quantity } } in copper, for house .house,
-- read at .pricesAt. "fair" is the average of the cheapest 20% listed: closer to what you'd pay
-- than the single lowest listing. Setting: "Auction prices in tooltips".

local _, ns = ...

local function prices()
  local site = ns.Site and ns.Site()
  return site and type(site.ah) == "table" and site.ah or nil, site
end

local function age(at)
  if type(at) ~= "number" or at <= 0 then return nil end
  local s = GetServerTime() - at
  if s < 3600 then return "under an hour ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

-- One item's price: fair, lowest, quantity, when (or nil when nobody has it listed).
function ns.AuctionPrice(id)
  local ah, site = prices()
  local p = ah and ah[id]
  if type(p) ~= "table" then return nil end
  return p[1], p[2], p[3], site.pricesAt
end

local function addLines(tt, id)
  if not (ns.settings and ns.settings.auctionPrices ~= false) or type(id) ~= "number" then return end
  local ah, site = prices()
  if not ah then return end
  local p = ah[id]
  if type(p) == "table" and (p[1] or -1) >= 0 then
    local old = site.pricesAt and GetServerTime() - site.pricesAt > 86400
    tt:AddDoubleLine("Auction", ns.Money(p[1]) .. " |cff999fb0(" .. (p[3] or 0) .. " listed" .. (old and (", " .. age(site.pricesAt)) or "") .. ")|r",
      0.6, 0.63, 0.69, 1, 1, 1)
  end
end

local function itemID(text)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
  if id then return id end
  local name = text:gsub("^%s+", ""):gsub("%s+$", "")
  local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(name))
  return link and tonumber(link:match("item:(%d+)")) or nil
end

local function priceCommand(text)
  local ah, site = prices()
  if not ah then
    ns.say("No auction prices yet. They come with the website data: run the companion app, or ask a guildmate who does.", true)
    return
  end
  local id = itemID(text)
  if not id then
    ns.say("Foxden doesn't know that item. Shift-click it into the box (from your bags, chat or a link), or check the spelling.", true)
    return
  end
  local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)) or ("item " .. id)
  local p = ah[id]
  local when = age(site.pricesAt)
  if type(p) ~= "table" then
    ns.say(link .. ": none on the auction house" .. (when and (" (" .. when .. ")") or "") .. ".", true)
    return
  end
  ns.say(string.format("%s: %s each, lowest %s, %d listed%s.", link, ns.Money(p[1]), ns.Money(p[2]), p[3] or 0,
    when and (" (" .. when .. ")") or ""), true)
end

-- "/fox price ..." before Core's handler, which lowercases everything (item names keep their case here)
local base = SlashCmdList.FOXDEN
SlashCmdList.FOXDEN = function(msg)
  local rest = type(msg) == "string" and msg:match("^%s*[Pp][Rr][Ii][Cc][Ee]%s+(.+)$")
  if rest then return priceCommand(rest) end
  return base(msg)
end

ns.RegisterModule({
  name = "AuctionPrices",
  events = {
    PLAYER_LOGIN = function()
      if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
          if tt and tt.AddDoubleLine and type(data) == "table" and not ns.IsSecret(data.id) then pcall(addLines, tt, data.id) end
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
