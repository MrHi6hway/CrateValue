-- CrateValue: minimap button, addon compartment entry and the options page
-- (Esc > Options > AddOns > CrateValue).
local ADDON, ns = ...

local format = string.format

---------------------------------------------------------------------------
-- Minimap button (no libraries: a small round button you can drag around the minimap)
---------------------------------------------------------------------------
local mmButton

local function placeMinimapButton()
  local a = math.rad(CrateValueDB.minimapAngle or 200)
  local x, y = math.cos(a), math.sin(a)
  local w = (Minimap:GetWidth() / 2) + 5
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    -- square minimaps (many UI packs): ride along the edge instead of a circle
    local d = math.sqrt(2 * w * w) - 10
    x = math.max(-w, math.min(x * d, w))
    y = math.max(-w, math.min(y * d, w))
  else
    x, y = x * w, y * w
  end
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Only runs while the button is being dragged.
local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  CrateValueDB.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx)) % 360
  placeMinimapButton()
end

local function showButtonTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText("CrateValue")
  GameTooltip:AddLine(format("v%s", ns.VERSION), 0.6, 0.6, 0.65)
  GameTooltip:AddLine("Left-click: open the window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: options", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.65)
  GameTooltip:Show()
end

local function createMinimapButton()
  if mmButton or not Minimap then return end
  local b = CreateFrame("Button", "CrateValueMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\INV_Crate_07")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then ns.OpenOptions() else ns.Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", dragUpdate)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
  end)
  b:SetScript("OnEnter", showButtonTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  mmButton = b
  placeMinimapButton()
  b:SetShown(not CrateValueDB.minimapHide)
end

function ns.SetMinimapShown(show)
  CrateValueDB.minimapHide = not show
  if show and not mmButton then createMinimapButton() end
  if mmButton then
    if show then placeMinimapButton() end
    mmButton:SetShown(show)
  end
  if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Addon compartment (the puzzle-piece menu by the minimap), when the client has one.
-- Named in the TOC, so these must be globals.
function CrateValue_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then ns.OpenOptions() else ns.Toggle() end
end
function CrateValue_OnAddonCompartmentEnter(_, menuButton)
  showButtonTooltip(menuButton)
end
function CrateValue_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Options page
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "CrateValueOptionsPanel")
panel.name = "CrateValue"
local controls = {}
local category

StaticPopupDialogs["CRATEVALUE_RESET_PRICES"] = {
  text = "Clear all CrateValue scanned and manual prices?",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function() ns.ResetPrices(); if ns.RefreshOptions then ns.RefreshOptions() end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.RefreshOptions()
  if not controls.minimap then return end
  local db = CrateValueDB
  controls.minimap:SetChecked(not db.minimapHide)
  controls.crateCost:SetChecked(db.includeCrateCost)
  controls.owned:SetChecked(db.onlyOwned)
  controls.scaleValue:SetText(format("%.2f", db.scale or 1))
  controls.source.label:SetText(ns.SourceLabel(db.source))
  local scanCount = 0
  for _ in pairs(db.scan) do scanCount = scanCount + 1 end
  local manualCount = 0
  for _ in pairs(db.manual) do manualCount = manualCount + 1 end
  controls.dataInfo:SetText(format("%d scanned prices, %d set by hand", scanCount, manualCount))
end

-- Built the first time the page is shown, so it costs nothing until then.
local function buildPanel()
  local K = ns.UIKit
  local C, F = K.C, K.F
  local y = -16

  local function heading(label)
    local h = K.text(panel, F.header, C.accent)
    h:SetPoint("TOPLEFT", 16, y)
    h:SetText(label)
    local line = K.solid(panel, "ARTWORK", C.border)
    line:SetPoint("TOPLEFT", 16, y - 16); line:SetPoint("RIGHT", panel, "RIGHT", -16, 0); line:SetHeight(1)
    y = y - 28
  end
  local function row(widget, height, x)
    widget:SetPoint("TOPLEFT", x or 20, y)
    y = y - (height or 26)
  end
  local function note(textValue)
    local n = K.text(panel, F.small, C.muted)
    n:SetPoint("TOPLEFT", 20, y)
    n:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    n:SetText(textValue)
    y = y - 20
    return n
  end

  local title = K.text(panel, F.title, C.text)
  title:SetPoint("TOPLEFT", 16, y)
  title:SetText("CrateValue")
  local sub = K.text(panel, F.small, C.muted)
  sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
  sub:SetText(format("v%s  ||  by %s", ns.VERSION, ns.AUTHOR))
  local open = K.flatButton(panel, "Open CrateValue", 130, 24, "primary")
  open:SetPoint("TOPRIGHT", -16, y + 4)
  open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    if not (ns.frame and ns.frame:IsShown()) then ns.Toggle() end
  end)
  y = y - 40

  heading("DISPLAY")
  controls.minimap = K.flatCheck(panel, "Show the minimap button", 260, function(v) ns.SetMinimapShown(v) end)
  row(controls.minimap)

  local scaleLabel = K.text(panel, F.body, C.text)
  scaleLabel:SetText("Window size")
  row(scaleLabel, 0)
  local minus = K.flatButton(panel, "-", 24, 22, "ghost")
  minus:SetPoint("TOPLEFT", 130, y + 3)
  controls.scaleValue = K.text(panel, F.body, C.text, "CENTER")
  controls.scaleValue:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  controls.scaleValue:SetWidth(44)
  local plus = K.flatButton(panel, "+", 24, 22, "ghost")
  plus:SetPoint("LEFT", controls.scaleValue, "RIGHT", 4, 0)
  minus:SetScript("OnClick", function() ns.SetScale((CrateValueDB.scale or 1) - 0.05); ns.RefreshOptions() end)
  plus:SetScript("OnClick", function() ns.SetScale((CrateValueDB.scale or 1) + 0.05); ns.RefreshOptions() end)
  local resetPos = K.flatButton(panel, "Reset window position", 170, 22, "ghost")
  resetPos:SetPoint("LEFT", plus, "RIGHT", 16, 0)
  resetPos:SetScript("OnClick", ns.ResetWindowPosition)
  y = y - 34

  heading("PRICES")
  local srcLabel = K.text(panel, F.body, C.text)
  srcLabel:SetText("Price source")
  row(srcLabel, 0)
  controls.source = K.flatButton(panel, "Auto", 150, 22, "ghost")
  controls.source:SetPoint("TOPLEFT", 130, y + 3)
  controls.source:SetScript("OnClick", function(self) ns.ShowSourceMenu(self) end)
  y = y - 30
  note("Auto uses your own scan when it is under 6 hours old, then Auctionator, then TSM.")
  y = y - 4
  controls.crateCost = K.flatCheck(panel, "Add the empty crate's AH price (for when you buy crates)", 400, function(v)
    CrateValueDB.includeCrateCost = v; ns.ClearPriceCache(); if ns.Refresh then ns.Refresh() end
  end)
  row(controls.crateCost)
  controls.owned = K.flatCheck(panel, "Only show crates in my bags", 260, function(v)
    CrateValueDB.onlyOwned = v; if ns.Refresh then ns.Refresh() end
  end)
  row(controls.owned, 34)

  heading("SAVED DATA")
  controls.dataInfo = note("")
  y = y - 6
  local reset = K.flatButton(panel, "Clear saved prices", 150, 24, "ghost")
  row(reset, 0)
  reset:SetScript("OnClick", function() StaticPopup_Show("CRATEVALUE_RESET_PRICES") end)
  local clearManual = K.flatButton(panel, "Clear prices set by hand", 180, 24, "ghost")
  clearManual:SetPoint("LEFT", reset, "RIGHT", 10, 0)
  clearManual:SetScript("OnClick", function()
    wipe(CrateValueDB.manual)
    ns.ClearPriceCache()
    if ns.Refresh then ns.Refresh() end
    ns.RefreshOptions()
    ns.Print("cleared all prices set by hand.")
  end)
  y = y - 36
  note("To set a price by hand, right-click a crate in the CrateValue window.")
end

panel:SetScript("OnShow", function()
  if not controls.minimap then buildPanel() end
  ns.RefreshOptions()
end)

function ns.OpenOptions()
  if InCombatLockdown and InCombatLockdown() then
    ns.Print("options can't open during combat; try again after.")
    return
  end
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- older clients need this twice to land on the right page
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    ns.Print("options page isn't available on this client; use /cval help.")
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "CrateValue")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  if not CrateValueDB.minimapHide then
    createMinimapButton()
    -- UI packs (EllesmereUI and others) restyle or tidy the minimap during login,
    -- which can hide or move our button. Re-apply its position and visibility once things settle.
    local function reapply()
      if mmButton and not CrateValueDB.minimapHide then
        placeMinimapButton()
        mmButton:Show()
      end
    end
    C_Timer.After(1, reapply)
    C_Timer.After(5, reapply)
  end
end)
