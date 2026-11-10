local ADDON, ns = ...

local format = string.format
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
local C = {
  bg       = { 0.06, 0.07, 0.09, 0.97 },
  panel    = { 0.10, 0.11, 0.14, 1 },
  panelHi  = { 0.14, 0.15, 0.19, 1 },
  border   = { 0.20, 0.22, 0.27, 1 },
  accent   = { 1.00, 0.78, 0.30, 1 },   -- warm gold
  text     = { 0.93, 0.94, 0.96, 1 },
  muted    = { 0.58, 0.61, 0.67, 1 },
  good     = { 0.35, 0.82, 0.50, 1 },
}
local HEX = { accent = "ffc84d", muted = "939aa8", good = "5ad17f", bad = "ff6b6b" }
local TIER_RGB = {
  Apprentice = { 0.80, 0.80, 0.82 },
  Journeyman = { 0.35, 0.82, 0.40 },
  Expert     = { 0.30, 0.58, 1.00 },
  Artisan    = { 0.72, 0.45, 1.00 },
}

local WIDTH, HEIGHT = 760, 560
local PAD = 14
local ROW_HEIGHT = 28

local function font(name, size, flags)
  local f = CreateFont(name)
  f:SetFont(FONT, size, flags or "")
  f:SetShadowColor(0, 0, 0, 0.8)
  f:SetShadowOffset(1, -1)
  return f
end
local F = {
  title  = font("CrateValueFontTitle", 15),
  big    = font("CrateValueFontBig", 17),
  body   = font("CrateValueFontBody", 13),
  small  = font("CrateValueFontSmall", 11),
  header = font("CrateValueFontHeader", 11),
}

local function text(parent, fontObj, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(fontObj)
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function skin(f, bg, border)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(unpack(bg or C.panel))
  f:SetBackdropBorderColor(unpack(border or C.border))
end

local function solid(parent, layer, color)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetVertexColor(unpack(color))
  return t
end

-- Flat button. style = "primary" | "ghost"
local function flatButton(parent, label, w, h, style)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b.label = text(b, F.body, style == "primary" and { 0.1, 0.08, 0.02, 1 } or C.text, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  b.style = style
  function b:Refresh()
    if self.style == "primary" then
      if self:IsEnabled() and not self.muted then
        skin(self, self.hover and { 1, 0.85, 0.45, 1 } or C.accent, C.accent)
        self.label:SetTextColor(0.1, 0.08, 0.02)
      else
        skin(self, C.panelHi, C.border)
        self.label:SetTextColor(unpack(C.muted))
      end
    elseif self.active then
      skin(self, { 0.28, 0.22, 0.10, 1 }, C.accent)
      self.label:SetTextColor(unpack(C.accent))
    else
      skin(self, self.hover and C.panelHi or C.panel, C.border)
      self.label:SetTextColor(unpack(self.hover and C.text or C.muted))
    end
  end
  b:SetScript("OnEnter", function(self) self.hover = true; self:Refresh() if self.tip then self.tip(self) end end)
  b:SetScript("OnLeave", function(self) self.hover = false; self:Refresh(); GameTooltip:Hide() end)
  b:SetScript("OnEnable", b.Refresh)
  b:SetScript("OnDisable", b.Refresh)
  b:Refresh()
  return b
end

-- Flat checkbox with label.
local function flatCheck(parent, label, width, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(18)
  b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.box:SetSize(14, 14)
  b.box:SetPoint("LEFT")
  skin(b.box, C.panel, C.border)
  b.fill = solid(b.box, "ARTWORK", C.accent)
  b.fill:SetPoint("TOPLEFT", 3, -3)
  b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  b.label = text(b, F.small, C.muted)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 7, 0)
  b.label:SetText(label)
  -- fixed width: text measurement is unreliable before fonts finish loading
  b:SetWidth(width)
  b.label:SetWidth(width - 22)
  function b:SetChecked(v)
    self.checked = v and true or false
    self.fill:SetShown(self.checked)
    self.box:SetBackdropBorderColor(unpack(self.checked and C.accent or C.border))
    self.label:SetTextColor(unpack(self.checked and C.text or C.muted))
  end
  b:SetScript("OnClick", function(self) self:SetChecked(not self.checked); onToggle(self.checked) end)
  return b
end

-- shared with Options.lua so the options page matches the window
ns.UIKit = { C = C, HEX = HEX, F = F, text = text, skin = skin, solid = solid, flatButton = flatButton, flatCheck = flatCheck }

local function iconTexture(parent, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return t
end

local function setIcon(tex, itemID)
  local icon = itemID and GetItemIcon and GetItemIcon(itemID)
  tex:SetTexture(icon or 134400) -- question mark
end

---------------------------------------------------------------------------
-- Columns and sorting
---------------------------------------------------------------------------
local COLUMNS = {
  { key = "name",     label = "CRATE",          width = 214, justify = "LEFT" },
  { key = "favor",    label = "FAVOR",          width = 66,  justify = "CENTER" },
  { key = "bundle",   label = "CHEAPEST FILL",  width = 184, justify = "LEFT" },
  { key = "total",    label = "COST",           width = 92,  justify = "RIGHT" },
  { key = "perFavor", label = "PER FAVOR",      width = 108, justify = "RIGHT" },
  { key = "owned",    label = "HAVE",           width = 48,  justify = "CENTER" },
}
local LIST_WIDTH = 0
for _, col in ipairs(COLUMNS) do LIST_WIDTH = LIST_WIDTH + col.width end

local TIERS = { "All", "Apprentice", "Journeyman", "Expert", "Artisan" }
local TIER_RANK = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

local frame, scrollChild, emptyText
local rows, headerButtons, tierButtons = {}, {}, {}
local scanButton, crateCheck, ownedCheck, cards = nil, nil, nil, {}
local footerHint

local function sortValue(r, key)
  -- Crate column: tier (Apprentice -> Artisan), then white before green, then name
  if key == "name" then
    return format("%d%d%s", TIER_RANK[r.crate.tier], r.crate.quality or 1, ns.ShortName(r.crate))
  end
  if key == "favor" then return r.favor end
  if key == "bundle" then return r.best and ns.ItemName(r.best.itemID) or nil end
  if key == "owned" then return r.owned end
  return r[key]
end

local function sortResults(list)
  local key, asc = CrateValueDB.sortKey, CrateValueDB.sortAsc
  table.sort(list, function(a, b)
    local va, vb = sortValue(a, key), sortValue(b, key)
    if va == nil and vb == nil then return ns.ShortName(a.crate) < ns.ShortName(b.crate) end
    if va == nil then return false end   -- unpriced crates sink to the bottom
    if vb == nil then return true end
    if va == vb then return TIER_RANK[a.crate.tier] < TIER_RANK[b.crate.tier] end
    if asc then return va < vb else return va > vb end
  end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function showRowTooltip(row)
  local r = row.result
  if not r then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(r.crate.name, 1, 1, 1)
  GameTooltip:AddLine(format("%s  ||  level %d  ||  %s crate  ||  %d favor%s",
    r.crate.tier, ns.TIER_LEVEL[r.crate.tier],
    ns.CrateQuality(r.crate) == "uncommon" and "|cff1eff00green|r" or "white",
    r.favor, r.estimated and " (estimate)" or ""), 0.75, 0.75, 0.78)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Fill with any one of:", 1, 0.78, 0.3)
  for _, b in ipairs(r.bundles) do
    local left = format("%s%dx %s", (b == r.best) and "|cff5ad17f>|r " or "   ", b.qty, ns.ItemName(b.itemID))
    local right
    if b.cost then
      local note
      if b.source == "manual" then
        note = format("|cff%sset by hand|r", HEX.accent)
      elseif b.supply and b.supply.short > 0 then
        note = format("|cff%sonly %d listed|r", HEX.bad, b.supply.available)
      elseif b.supply then
        note = format("|cff%sreal listings|r", HEX.good)
      else
        note = format("|cff%s%s ea|r", HEX.muted, ns.Money(b.unit))
      end
      right = ns.Money(b.cost) .. "  " .. note
    else
      right = ns.Money(nil)
    end
    GameTooltip:AddDoubleLine(left, right, 1, 1, 1)
  end

  -- cost of filling more than one crate with the cheapest bundle (prices rise as cheap listings run out)
  if r.best then
    local counts = { 1 }
    if r.owned > 1 then tinsert(counts, r.owned) end
    if r.owned < 5 then tinsert(counts, 5) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("Filling with %s:", ns.ItemName(r.best.itemID)), 1, 0.78, 0.3)
    for _, n in ipairs(counts) do
      local per, supply = ns.CostForCrates(r.best.itemID, r.best.qty, n)
      if per then
        local extra = CrateValueDB.includeCrateCost and r.crateCost or 0
        local label = (n == 1) and "1 crate" or format("%d crates%s", n, n == r.owned and " (in bags)" or "")
        local warn = (supply and supply.short > 0) and format("  |cff%snot enough listed|r", HEX.bad) or ""
        GameTooltip:AddDoubleLine(label, format("%s / favor%s", ns.Money((per + extra) / r.favor), warn), 0.75, 0.75, 0.78)
      end
    end
    if not r.best.supply then
      GameTooltip:AddLine("Based on the single lowest price; click to check real supply.", 0.5, 0.5, 0.55, true)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Empty crate on the AH", ns.Money(r.crateCost), 0.75, 0.75, 0.78)
  if r.perFavor then GameTooltip:AddDoubleLine("Gold per favor", ns.Money(r.perFavor), 1, 0.78, 0.3) end
  if r.best and r.best.source then GameTooltip:AddLine("Price source: " .. r.best.source, 0.5, 0.5, 0.55) end
  if ns.IsCheckingSupply(r.crate) then
    GameTooltip:AddLine("Checking Auction House supply...", 0.35, 0.82, 0.5)
  elseif ns.IsAHOpen() then
    GameTooltip:AddLine("Click to check real Auction House supply.", 0.5, 0.5, 0.55)
  end
  GameTooltip:AddLine("Right-click to set a price by hand.  Shift-click to link.", 0.5, 0.5, 0.55)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Setting prices by hand (right-click a crate row)
---------------------------------------------------------------------------
local function popupEditBox(dialog)
  return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

StaticPopupDialogs["CRATEVALUE_SET_PRICE"] = {
  text = "Price each for %s\n\nType silver (45) or gold and silver (1g20s).\nClear goes back to Auction House prices.",
  button1 = SAVE or "Save",
  button2 = CANCEL or "Cancel",
  button3 = "Clear",
  hasEditBox = 1,
  maxLetters = 16,
  OnShow = function(self, itemID)
    local eb = popupEditBox(self)
    local cur = CrateValueDB.manual[itemID] or ns.GetPrice(itemID)
    eb:SetText(cur and ns.MoneyPlain(cur) or "")
    eb:HighlightText()
    eb:SetFocus()
  end,
  OnAccept = function(self, itemID) ns.SetManualPrice(itemID, popupEditBox(self):GetText()) end,
  OnAlt = function(_, itemID) ns.SetManualPrice(itemID, nil) end,
  EditBoxOnEnterPressed = function(eb, itemID)
    if ns.SetManualPrice(itemID, eb:GetText()) then eb:GetParent():Hide() end
  end,
  EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.EditPrice(itemID)
  StaticPopup_Show("CRATEVALUE_SET_PRICE", ns.ItemName(itemID), nil, itemID)
end

-- Right-click menu: every material this crate takes, plus the empty crate itself.
local function showPriceMenu(row)
  local r = row.result
  if not r then return end
  local function label(itemID, prefix)
    local manual = CrateValueDB.manual[itemID]
    local price = manual or ns.GetPrice(itemID)
    return format("%s%s  %s%s", prefix or "", ns.ItemName(itemID), ns.Money(price),
      manual and format(" |cff%s(by hand)|r", HEX.accent) or "")
  end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    if r.best then ns.EditPrice(r.best.itemID) end
    return
  end
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle("Set a price by hand")
    local anyManual = false
    for _, b in ipairs(r.bundles) do
      root:CreateButton(label(b.itemID), function() ns.EditPrice(b.itemID) end)
      anyManual = anyManual or CrateValueDB.manual[b.itemID] ~= nil
    end
    root:CreateButton(label(r.crate.id, "Empty crate: "), function() ns.EditPrice(r.crate.id) end)
    anyManual = anyManual or CrateValueDB.manual[r.crate.id] ~= nil
    if anyManual then
      root:CreateDivider()
      root:CreateButton("Clear this crate's hand-set prices", function()
        for _, b in ipairs(r.bundles) do CrateValueDB.manual[b.itemID] = nil end
        CrateValueDB.manual[r.crate.id] = nil
        ns.ClearPriceCache()
        ns.Refresh()
        if ns.RefreshOptions then ns.RefreshOptions() end
      end)
    end
  end)
end

local function createRow(i)
  local row = CreateFrame("Button", nil, scrollChild)
  row:SetSize(LIST_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

  row.zebra = (i % 2 == 0) and 0.025 or 0
  row.bg = solid(row, "BACKGROUND", { 1, 1, 1, row.zebra })
  row.bg:SetAllPoints()
  row.hl = solid(row, "HIGHLIGHT", { 1, 0.78, 0.3, 0.08 })
  row.hl:SetAllPoints()
  row.sep = solid(row, "BORDER", { 1, 1, 1, 0.04 })
  row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
  -- green frame drawn around the BEST row
  row.topLine = solid(row, "BORDER", C.good)
  row.topLine:SetPoint("TOPLEFT"); row.topLine:SetPoint("TOPRIGHT"); row.topLine:SetHeight(1)
  row.topLine:Hide()

  -- tier stripe
  row.stripe = solid(row, "ARTWORK", { 1, 1, 1, 1 })
  row.stripe:SetPoint("TOPLEFT", 0, -5); row.stripe:SetPoint("BOTTOMLEFT", 0, 5); row.stripe:SetWidth(3)

  local x = 0
  row.cells = {}
  for c, col in ipairs(COLUMNS) do
    local cell = text(row, F.body, C.text, col.justify)
    local inset = (c == 1 or c == 3) and 34 or 8
    if c == 1 then inset = 38 end
    cell:SetPoint("LEFT", x + inset, 0)
    cell:SetWidth(col.width - inset - 8)
    row.cells[c] = cell
    col.x = x
    x = x + col.width
  end

  row.crateIcon = iconTexture(row, 20)
  row.crateIcon:SetPoint("LEFT", 10, 0)
  row.matIcon = iconTexture(row, 18)
  row.matIcon:SetPoint("LEFT", COLUMNS[3].x + 8, 0)

  -- "value bar" behind the per-favor cell: longer = cheaper
  local pf = COLUMNS[5]
  row.bar = solid(row, "BORDER", { C.good[1], C.good[2], C.good[3], 0.16 })
  row.bar:SetPoint("RIGHT", row, "LEFT", pf.x + pf.width - 4, 0)
  row.bar:SetHeight(ROW_HEIGHT - 10)

  row.badge = text(row, F.small, C.good, "LEFT")
  row.badge:SetPoint("RIGHT", row, "LEFT", COLUMNS[1].x + COLUMNS[1].width - 4, 0)

  row:SetScript("OnEnter", showRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    local r = self.result
    if not r then return end
    if button == "RightButton" then
      GameTooltip:Hide()
      showPriceMenu(self)
    elseif IsShiftKeyDown() and r.best then
      local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(r.best.itemID)
      if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    else
      ns.CheckSupply(r.crate)
      ns.Refresh()
      if GameTooltip:IsOwned(self) then showRowTooltip(self) end
    end
  end)
  rows[i] = row
  return row
end

local function fillRow(row, r, bestPerFavor, rank)
  row.result = r
  local c = row.cells
  local tc = TIER_RGB[r.crate.tier]
  row.stripe:SetVertexColor(tc[1], tc[2], tc[3], 0.9)
  setIcon(row.crateIcon, r.crate.id)

  c[1]:SetText(ns.ShortName(r.crate))
  c[1]:SetTextColor(unpack(C.text))
  c[2]:SetText(r.estimated and format("%d|cff%s*|r", r.favor, HEX.muted) or tostring(r.favor))

  if r.best then
    setIcon(row.matIcon, r.best.itemID)
    row.matIcon:SetDesaturated(false)
    row.matIcon:SetAlpha(1)
    local tag = ""
    if r.best.supply and r.best.supply.short > 0 then
      tag = format(" |cff%s(low supply)|r", HEX.bad)
    elseif ns.IsCheckingSupply(r.crate) then
      tag = format(" |cff%s...|r", HEX.muted)
    end
    c[3]:SetText(format("|cff%s%dx|r %s%s", HEX.muted, r.best.qty, ns.ItemName(r.best.itemID), tag))
  else
    row.matIcon:SetTexture(134400)
    row.matIcon:SetDesaturated(true)
    row.matIcon:SetAlpha(0.4)
    c[3]:SetText(format("|cff%sno prices yet|r", HEX.muted))
  end

  c[4]:SetText(ns.Money(r.total) .. ((r.best and r.best.supply) and format(" |cff%s+|r", HEX.good) or ""))
  c[5]:SetText(ns.Money(r.perFavor))
  c[6]:SetText(r.owned > 0 and format("|cff%s%d|r", HEX.good, r.owned) or format("|cff%s-|r", HEX.muted))

  if r.perFavor and bestPerFavor then
    local frac = math.max(0.06, math.min(1, bestPerFavor / r.perFavor))
    row.bar:SetWidth((COLUMNS[5].width - 8) * frac)
    row.bar:Show()
  else
    row.bar:Hide()
  end

  local nameWidth = COLUMNS[1].width - 46
  if rank == 1 or (r.owned > 0 and r.perFavor) then nameWidth = nameWidth - 52 end
  c[1]:SetWidth(nameWidth)

  -- the best crate gets a green background and a green frame
  if rank == 1 then
    row.bg:SetVertexColor(0.13, 0.20, 0.14, 1)
    row.sep:SetVertexColor(C.good[1], C.good[2], C.good[3], 0.6)
    row.topLine:SetVertexColor(C.good[1], C.good[2], C.good[3], 0.6)
    row.topLine:Show()
  else
    row.bg:SetVertexColor(1, 1, 1, row.zebra)
    row.sep:SetVertexColor(1, 1, 1, 0.04)
    row.topLine:Hide()
  end

  if rank == 1 then
    row.badge:SetText("BEST")
    row.badge:SetTextColor(unpack(C.good))
  elseif r.owned > 0 and r.perFavor then
    row.badge:SetText("IN BAGS")
    row.badge:SetTextColor(unpack(C.accent))
  else
    row.badge:SetText("")
  end
  row:Show()
end

---------------------------------------------------------------------------
-- Summary cards
---------------------------------------------------------------------------
local function createCard(parent, label, w)
  local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  card:SetSize(w, 62)
  skin(card, C.panel, C.border)
  card.accent = solid(card, "ARTWORK", C.accent)
  card.accent:SetPoint("TOPLEFT", 1, -1); card.accent:SetPoint("BOTTOMLEFT", 1, 1); card.accent:SetWidth(2)
  card.label = text(card, F.header, C.muted)
  card.label:SetPoint("TOPLEFT", 12, -9)
  card.label:SetText(label)
  card.value = text(card, F.big, C.text)
  card.value:SetPoint("TOPLEFT", 12, -24)
  card.value:SetPoint("RIGHT", -10, 0)
  card.sub = text(card, F.small, C.muted)
  card.sub:SetPoint("TOPLEFT", 12, -44)
  card.sub:SetPoint("RIGHT", -10, 0)
  card:EnableMouse(true)
  card:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
  card:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return card
end

local function lastScanAge()
  local newest
  for _, e in pairs(CrateValueDB.scan) do
    if e.time and (not newest or e.time > newest) then newest = e.time end
  end
  if not newest then return nil end
  local mins = math.floor((time() - newest) / 60)
  if mins < 1 then return "just now" end
  if mins < 60 then return mins .. "m ago" end
  if mins < 48 * 60 then return math.floor(mins / 60) .. "h ago" end
  return math.floor(mins / 1440) .. "d ago"
end

-- Price source picker: the game's dropdown menu when available, otherwise click to cycle.
function ns.ShowSourceMenu(owner)
  local opts = ns.SOURCE_OPTIONS
  if MenuUtil and MenuUtil.CreateContextMenu then
    local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      root:CreateTitle("Price source")
      for _, o in ipairs(opts) do
        local label = ns.SourceAvailable(o.key) and o.label or (o.label .. " (no data)")
        local radio = root:CreateRadio(label,
          function(key) return CrateValueDB.source == key end,
          function(key) ns.SetSource(key) end, o.key)
        if radio.SetTooltip then
          radio:SetTooltip(function(tip) GameTooltip_SetTitle(tip, o.label); GameTooltip_AddNormalLine(tip, o.desc) end)
        end
        if radio.SetEnabled and not ns.SourceAvailable(o.key) then radio:SetEnabled(false) end
      end
    end)
    if ok then return end
  end
  -- Fallback: step to the next source that has data.
  local cur = 1
  for i, o in ipairs(opts) do if o.key == CrateValueDB.source then cur = i end end
  for step = 1, #opts do
    local o = opts[(cur + step - 1) % #opts + 1]
    if ns.SourceAvailable(o.key) then
      ns.SetSource(o.key)
      ns.Print("price source: " .. o.label .. ". " .. o.desc)
      return
    end
  end
end

local function refreshCards(all)
  local best = ns.BestPerFavor(all)
  if best then
    cards.favor.value:SetText(ns.Money(best.perFavor) .. format(" |cff%s/ favor|r", HEX.muted))
    cards.favor.sub:SetText(format("%s  ||  %dx %s", ns.ShortName(best.crate), best.best.qty, ns.ItemName(best.best.itemID)))
  else
    cards.favor.value:SetText(format("|cff%s-|r", HEX.muted))
    cards.favor.sub:SetText("Scan the AH to rank crates")
  end

  local route = ns.RepRoute(all)
  cards.rep.route = route
  local _, _, reaction = ns.TradeFaction()
  local locked = reaction and reaction < 5
  if route and not route.missingCrate then
    cards.rep.value:SetText(ns.Money(route.total) .. format(" |cff%s/ 50 rep|r", HEX.muted))
    cards.rep.sub:SetText(locked and format("|cff%sNeeds Friendly|r", HEX.bad) or (ns.Money(route.perRep) .. " per rep"))
  elseif route then
    cards.rep.value:SetText(ns.Money(route.favorGold) .. format(" |cff%s+ crate|r", HEX.muted))
    cards.rep.sub:SetText(locked and format("|cff%sNeeds Friendly|r", HEX.bad) or "Scan to price a crate")
  else
    cards.rep.value:SetText(format("|cff%s-|r", HEX.muted))
    cards.rep.sub:SetText("Scan the AH to price")
  end

  local verified, totalCrates = ns.VerifiedCount()
  footerHint:SetText(format("|cff%s*|r estimate   ||   |cff%s+|r real supply   ||   %d/%d verified", HEX.accent, HEX.good, verified, totalCrates))

  local src = CrateValueDB.source
  local age = lastScanAge()
  if not ns.SourceAvailable(src) or #ns.AvailableSources() == 0 then
    cards.prices.value:SetText(format("%s |cff%sno data|r", ns.SourceLabel(src), HEX.bad))
    cards.prices.sub:SetText(src == "auto" and "Open the AH and press Scan" or "Click Change to pick another")
  else
    cards.prices.value:SetText(ns.SourceLabel(src))
    cards.prices.sub:SetText("Last scan " .. (age or "never"))
  end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local refreshNow

-- Many events can ask for a refresh in the same moment (scan batches, listings, bag changes).
-- Coalesce them into a single redraw a moment later, and never redraw while hidden.
local refreshPending = false
function ns.Refresh()
  if refreshPending or not (frame and frame:IsShown()) then return end
  refreshPending = true
  C_Timer.After(0.05, function()
    refreshPending = false
    refreshNow()
  end)
end

refreshNow = function()
  if not (frame and frame:IsShown()) then return end
  local all = ns.EvaluateAll()
  local shown = {}
  for _, r in ipairs(all) do
    local tierOK = CrateValueDB.tier == "All" or r.crate.tier == CrateValueDB.tier
    local ownedOK = not CrateValueDB.onlyOwned or r.owned > 0
    if tierOK and ownedOK then tinsert(shown, r) end
  end
  sortResults(shown)

  -- rank by per-favor within the current view, independent of the sort column
  local bestPerFavor, bestResult
  for _, r in ipairs(shown) do
    if r.perFavor and (not bestPerFavor or r.perFavor < bestPerFavor) then bestPerFavor, bestResult = r.perFavor, r end
  end

  local n = #shown
  for i, r in ipairs(shown) do
    fillRow(rows[i] or createRow(i), r, bestPerFavor, (r == bestResult) and 1 or nil)
  end
  for i = n + 1, #rows do rows[i]:Hide(); rows[i].result = nil end
  -- keep an open row tooltip in sync as supply results arrive
  for i = 1, n do
    if GameTooltip:IsOwned(rows[i]) then showRowTooltip(rows[i]) end
  end
  scrollChild:SetHeight(math.max(1, n * ROW_HEIGHT))

  if #shown == 0 then
    emptyText:SetText(CrateValueDB.onlyOwned and "You have no Waylaid Crates in your bags." or "Nothing to show for this filter.")
    emptyText:Show()
  else
    emptyText:Hide()
  end

  for _, hb in ipairs(headerButtons) do
    local active = hb.key == CrateValueDB.sortKey
    hb.text:SetTextColor(unpack(active and C.accent or C.muted))
    hb.arrow:SetShown(active)
    if active then
      hb.arrow:SetTexture(CrateValueDB.sortAsc and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
    end
  end
  for _, tb in ipairs(tierButtons) do
    tb.active = tb.tier == CrateValueDB.tier
    tb:Refresh()
  end
  crateCheck:SetChecked(CrateValueDB.includeCrateCost)
  ownedCheck:SetChecked(CrateValueDB.onlyOwned)
  refreshCards(all)
end

function ns.OnScanProgress(done, total)
  if not scanButton then return end
  if done and ns.IsScanning() then
    scanButton.label:SetText(format("Stop  %d/%d", done, total))
  else
    scanButton.label:SetText(ns.IsAHOpen() and "Scan AH" or "Open AH to scan")
  end
end

-- The Scan button stays clickable (so hovering always shows why) but looks greyed out
-- and says so while the Auction House is closed.
local function updateScanButton()
  if scanButton then
    scanButton.muted = not ns.IsAHOpen()
    if not ns.IsScanning() then scanButton.label:SetText(scanButton.muted and "Open AH to scan" or "Scan AH") end
    scanButton:Refresh()
    if GameTooltip:IsOwned(scanButton) then scanButton.tip(scanButton) end
  end
end

function ns.OnAHChanged()
  updateScanButton()
  if CrateValueDB and frame and frame:IsShown() then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function build()
  frame = CreateFrame("Frame", "CrateValueFrame", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, HEIGHT)
  skin(frame, C.bg, C.border)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetScale(CrateValueDB.scale or 1)
  local pos = CrateValueDB.pos
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
  tinsert(UISpecialFrames, "CrateValueFrame")
  ns.frame = frame

  -- Title bar (drag handle)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(38)
  local barBg = solid(bar, "BACKGROUND", C.panel); barBg:SetAllPoints()
  local barLine = solid(bar, "BORDER", C.border)
  barLine:SetPoint("BOTTOMLEFT"); barLine:SetPoint("BOTTOMRIGHT"); barLine:SetHeight(1)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() frame:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local p, _, rp, x, y = frame:GetPoint()
    CrateValueDB.pos = { p, rp, x, y }
  end)

  local logo = bar:CreateTexture(nil, "ARTWORK")
  logo:SetSize(22, 22)
  logo:SetPoint("LEFT", PAD, 0)
  logo:SetTexture("Interface\\Icons\\INV_Crate_07")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local title = text(bar, F.title, C.text)
  title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
  title:SetText("CrateValue")
  local subtitle = text(bar, F.small, C.muted)
  subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
  subtitle:SetText(format("v%s  ||  by %s", ns.VERSION, ns.AUTHOR))

  local close = CreateFrame("Button", nil, bar)
  close:SetSize(28, 28)
  close:SetPoint("RIGHT", -6, 0)
  close.x = text(close, F.title, C.muted, "CENTER")
  close.x:SetPoint("CENTER", 0, 1)
  close.x:SetText("x")
  close:SetScript("OnEnter", function() close.x:SetTextColor(1, 0.42, 0.42) end)
  close:SetScript("OnLeave", function() close.x:SetTextColor(unpack(C.muted)) end)
  close:SetScript("OnClick", function() frame:Hide() end)

  local options = flatButton(bar, "Options", 64, 22, "ghost")
  options:SetPoint("RIGHT", close, "LEFT", -8, 0)
  options:SetScript("OnClick", function() frame:Hide(); ns.OpenOptions() end)

  -- Toolbar: tier tabs + scan
  local x = PAD
  for _, tier in ipairs(TIERS) do
    local w = tier == "All" and 46 or 96
    local b = flatButton(frame, tier, w, 26, "ghost")
    b:SetPoint("TOPLEFT", x, -52)
    b.tier = tier
    b:SetScript("OnClick", function() CrateValueDB.tier = tier; ns.Refresh() end)
    tinsert(tierButtons, b)
    x = x + w + 6
  end

  scanButton = flatButton(frame, "Scan AH", 132, 26, "primary")
  scanButton:SetPoint("TOPRIGHT", -PAD, -52)
  scanButton:SetScript("OnClick", ns.Scan)
  scanButton.tip = function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if ns.IsScanning() then
      GameTooltip:SetText("Scanning the Auction House")
      GameTooltip:AddLine("Click to stop.", 1, 1, 1)
    elseif ns.IsAHOpen() then
      GameTooltip:SetText("Scan crate materials")
      GameTooltip:AddLine("Searches the Auction House for every crate material and empty crate and keeps the lowest price. Takes about a minute.", 1, 1, 1, true)
    else
      GameTooltip:SetText("Auction House not open", 1, 0.42, 0.42)
      GameTooltip:AddLine("Talk to an auctioneer to open the Auction House, then press Scan.", 1, 1, 1, true)
      GameTooltip:AddLine("Until then, Auctionator or TSM prices (if installed) and your last scan are used.", 0.6, 0.6, 0.65, true)
    end
    GameTooltip:Show()
  end

  -- Summary cards
  local gap = 10
  local cw = math.floor((WIDTH - PAD * 2 - gap * 2) / 3)
  cards.favor = createCard(frame, "CHEAPEST FAVOR", cw)
  cards.favor:SetPoint("TOPLEFT", PAD, -90)
  cards.rep = createCard(frame, "REPUTATION COST", cw)
  cards.rep:SetPoint("LEFT", cards.favor, "RIGHT", gap, 0)
  cards.prices = createCard(frame, "PRICE DATA", cw)
  cards.prices:SetPoint("LEFT", cards.rep, "RIGHT", gap, 0)
  cards.prices.accent:SetVertexColor(0.30, 0.58, 1.00)
  local changeSource = flatButton(cards.prices, "Change", 58, 18, "ghost")
  changeSource:SetPoint("TOPRIGHT", -6, -6)
  changeSource:SetScript("OnClick", function(self) ns.ShowSourceMenu(self) end)
  cards.prices:SetScript("OnMouseUp", function(self) ns.ShowSourceMenu(changeSource) end)
  local function sourceTip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Price source")
    for _, o in ipairs(ns.SOURCE_OPTIONS) do
      local current = o.key == CrateValueDB.source
      local avail = ns.SourceAvailable(o.key)
      local r, g, b = 0.75, 0.75, 0.78
      if current then r, g, b = 1, 0.78, 0.3 elseif not avail then r, g, b = 0.45, 0.45, 0.48 end
      GameTooltip:AddDoubleLine((current and "> " or "   ") .. o.label, avail and "" or "not available", r, g, b, 0.45, 0.45, 0.48)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to change. Prices you set by hand (right-click a crate) always win.", 0.6, 0.6, 0.65, true)
    GameTooltip:Show()
  end
  cards.prices.tip = sourceTip
  changeSource.tip = sourceTip
  cards.rep.accent:SetVertexColor(unpack(C.good))
  cards.rep.tip = function(self)
    local _, factionName, reaction, standing = ns.TradeFaction()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(factionName or "Reputation cost")
    GameTooltip:AddLine("Forged Delivery Receipt (15 favor) + any empty crate = 50 rep. Sealed crates give favor only.", 1, 1, 1, true)
    local r = self.route
    if r then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("15 favor", ns.Money(r.favorGold), 0.75, 0.75, 0.78, 1, 1, 1)
      GameTooltip:AddDoubleLine("Empty crate", r.missingCrate and "not scanned" or ns.Money(r.cratePrice), 0.75, 0.75, 0.78, 1, 1, 1)
      if not r.missingCrate then
        GameTooltip:AddDoubleLine("Per 1,000 rep", ns.Money(r.perRep * 1000), 1, 0.78, 0.3, 1, 0.78, 0.3)
      end
    end
    if reaction and reaction < 5 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Receipts need Friendly" .. (standing and (" (you are " .. standing .. ")") or "") .. ".", 1, 0.42, 0.42, true)
    end
    GameTooltip:Show()
  end

  -- Table panel
  local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", PAD, -164)
  panel:SetPoint("BOTTOMRIGHT", -PAD, 44)
  skin(panel, C.panel, C.border)

  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(26)
  local hbg = solid(header, "BACKGROUND", C.panelHi); hbg:SetAllPoints()
  local hx = 0
  for c, col in ipairs(COLUMNS) do
    local hb = CreateFrame("Button", nil, header)
    hb:SetSize(col.width, 26)
    hb:SetPoint("LEFT", hx + 1, 0)
    local inset = (c == 1) and 38 or (c == 3 and 34 or (col.justify == "CENTER" and 2 or 8))
    hb.text = text(hb, F.header, C.muted, col.justify)
    hb.text:SetPoint("LEFT", inset, 0)
    hb.text:SetWidth(col.width - inset - (col.justify == "CENTER" and 2 or 8))
    hb.text:SetText(col.label)
    hb.arrow = hb:CreateTexture(nil, "OVERLAY")
    hb.arrow:SetSize(12, 12)
    if col.justify == "RIGHT" then
      hb.arrow:SetPoint("RIGHT", hb.text, "LEFT", hb.text:GetWidth() - hb.text:GetStringWidth() - 2, 0)
    elseif col.justify == "CENTER" then
      hb.arrow:SetPoint("LEFT", hb.text, "CENTER", hb.text:GetStringWidth() / 2 + 2, 0)
    else
      hb.arrow:SetPoint("LEFT", hb.text, "LEFT", hb.text:GetStringWidth() + 3, 0)
    end
    hb.arrow:SetVertexColor(unpack(C.accent))
    hb.key = col.key
    hb:SetScript("OnEnter", function() if hb.key ~= CrateValueDB.sortKey then hb.text:SetTextColor(unpack(C.text)) end end)
    hb:SetScript("OnLeave", function()
      hb.text:SetTextColor(unpack(hb.key == CrateValueDB.sortKey and C.accent or C.muted))
    end)
    hb:SetScript("OnClick", function()
      if CrateValueDB.sortKey == col.key then
        CrateValueDB.sortAsc = not CrateValueDB.sortAsc
      else
        CrateValueDB.sortKey, CrateValueDB.sortAsc = col.key, true
      end
      ns.Refresh()
    end)
    tinsert(headerButtons, hb)
    hx = hx + col.width
  end

  -- Prefer the modern minimal scrollbar, fall back to the classic one.
  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "ScrollFrameTemplate")
  if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate") end
  scroll:SetPoint("TOPLEFT", 1, -28)
  scroll:SetPoint("BOTTOMRIGHT", -18, 2)
  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(LIST_WIDTH, 1)
  scroll:SetScrollChild(scrollChild)

  emptyText = text(panel, F.body, C.muted, "CENTER")
  emptyText:SetPoint("CENTER", 0, -10)
  emptyText:Hide()

  -- Footer
  crateCheck = flatCheck(frame, "Add the empty crate's AH price", 260, function(v)
    CrateValueDB.includeCrateCost = v; ns.Refresh()
  end)
  crateCheck:SetPoint("BOTTOMLEFT", PAD, 15)
  ownedCheck = flatCheck(frame, "Only crates in my bags", 160, function(v)
    CrateValueDB.onlyOwned = v; ns.Refresh()
  end)
  ownedCheck:SetPoint("LEFT", crateCheck, "RIGHT", 16, 0)

  footerHint = text(frame, F.small, C.muted, "RIGHT")
  footerHint:SetPoint("BOTTOMRIGHT", -PAD, 17)
  footerHint:SetPoint("LEFT", ownedCheck, "RIGHT", 12, 0)

  frame:SetScript("OnShow", function() ns.SyncFromGame(); updateScanButton(); refreshNow() end)
  frame:Hide() -- new frames start shown; Toggle decides visibility
end

function ns.SetScale(v)
  v = math.max(0.6, math.min(1.6, math.floor(v * 20 + 0.5) / 20))
  CrateValueDB.scale = v
  if frame then frame:SetScale(v) end
  return v
end

function ns.ResetWindowPosition()
  CrateValueDB.pos = nil
  if frame then frame:ClearAllPoints(); frame:SetPoint("CENTER") end
end

function ns.Toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Keep the Scan button state in sync when the Auction House opens or closes.
local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function()
  if frame then ns.OnAHChanged() end   -- the window is only built the first time you open it
end)
