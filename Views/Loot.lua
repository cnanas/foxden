-- View: Loot. Everything you and your group looted in the run, best first: who got it
-- and which boss dropped it. Hover for the tooltip, shift-click to link.

local _, ns = ...
local UI = ns.UI
local C = UI.C

local view = { key = "loot", label = "Loot", order = 15 }

function view:Build(pane)
  self.head = UI.Text(pane, 12, C.dim); self.head:SetPoint("TOPLEFT", 0, 0)
  self.list = UI.List(pane, 30, function(r)
    UI.ItemRow(r, 8)
    r.name = UI.Text(r, 12); r.name:SetPoint("LEFT", 36, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -230, 0)
    r.who = UI.Text(r, 11, C.dim, "RIGHT"); r.who:SetPoint("RIGHT", -12, 0); r.who:SetWidth(210)
  end, function(r, g)
    local n, _, q = UI.ItemLook(g.i)
    UI.SetRowItem(r, g.i, nil, n)
    r.name:SetText((n or ("Item " .. g.i)) .. ((g.n or 1) > 1 and ("  |cff99a1b0x" .. g.n .. "|r") or ""))
    r.name:SetTextColor(UI.QualityColor(q or g.q))
    local bits = {}
    if g.w then bits[#bits + 1] = g.w end
    if g.b then bits[#bits + 1] = "from " .. g.b end
    r.who:SetText(table.concat(bits, "  ·  "))
  end)
  self.list:SetPoint("TOPLEFT", 0, -24); self.list:SetPoint("BOTTOMRIGHT")
  self.empty = UI.Text(pane, 13, C.dim, "CENTER"); self.empty:SetPoint("CENTER", 0, 20); self.empty:SetWordWrap(true); self.empty:SetWidth(420)
end

function view:Layout() if self.list.Layout then self.list:Layout() end end

function view:Refresh(e)
  local list, grey = ns.RunLootList(e.run)
  local good = 0
  for _, g in ipairs(list) do if (g.q or 1) >= 2 then good = good + 1 end end
  self.head:SetText(#list == 0 and "" or string.format("%d %s  ·  %d green or better%s", #list, #list == 1 and "item" or "items", good,
    grey > 0 and ("  ·  " .. grey .. " grey") or ""))
  self.list:SetItems(list)
  self.list:SetShown(#list > 0)
  self.empty:SetShown(#list == 0)
  self.empty:SetText(e.run.got and "Nothing looted yet." or "Foxden didn't record loot for this run. Runs from version 2.2.2 on list everything your group looted.")
end

ns.RegisterView(view)
