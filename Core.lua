local ADDON, ns = ...

local floor, format, min = math.floor, string.format, math.min
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Version and author come from the .toc so there is one place to change them.
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "dev"
ns.AUTHOR = (GetMeta and GetMeta(ADDON, "Author")) or "MrHi6hway2"
ns.LICENSE = (GetMeta and GetMeta(ADDON, "X-License")) or "MIT"

ns.byID = {}          -- crate itemID -> crate
ns.watched = {}       -- itemID -> true for every material and crate we price
for _, crate in ipairs(ns.CRATES) do
  ns.byID[crate.id] = crate
  ns.watched[crate.id] = true
  for _, b in ipairs(crate.bundles) do ns.watched[b[1]] = true end
end

local DEFAULTS = {
  source = "auto",          -- auto | auctionator | tsm | scan
  includeCrateCost = false, -- add the Waylaid Crate's own AH price (for when you'd buy the crate)
  onlyOwned = false,
  tier = "All",
  sortKey = "perFavor",
  sortAsc = true,
  manual = {},              -- [itemID] = copper per unit
  scan = {},                -- [itemID] = { price = copper, time = epoch }
  learned = {},             -- ["Artisan-common"] = favor seen on turn-in
  scale = 1,                -- window scale (/cval scale)
  minimapHide = false,      -- hide the minimap button
  minimapAngle = 200,       -- minimap button position, degrees around the minimap
  depth = {},               -- [itemID] = { time = epoch, tiers = { {unit, qty}, ... } } real AH listings
}

local function applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      db[k] = type(v) == "table" and {} or v
    end
  end
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
function ns.Money(copper)
  if not copper then return "|cff808080-|r" end
  copper = floor(copper + 0.5)
  local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
  if g > 0 then
    return format("|cffffd700%dg|r |cffc7c7cf%02ds|r", g, s)
  elseif s > 0 then
    return format("|cffc7c7cf%ds|r |cffeda55f%02dc|r", s, c)
  end
  return format("|cffeda55f%dc|r", c)
end

function ns.ItemName(itemID)
  local name = GetItemInfo(itemID)
  return name or ns.MATERIALS[itemID] or (ns.byID[itemID] and ns.byID[itemID].name) or ("item:" .. itemID)
end

function ns.ShortName(crate)
  return (crate.name:gsub("^Waylaid Crate: ", ""))
end

function ns.Print(msg)
  print("|cff33ff99CrateValue|r: " .. msg)
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
local function auctionatorPrice(itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
  if ok and price and price > 0 then return price end
end

local TSM_SOURCES = { "DBMinBuyout", "DBRecent", "DBMarket" }
local function tsmPrice(itemID)
  if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
  for _, src in ipairs(TSM_SOURCES) do
    local ok, price = pcall(TSM_API.GetCustomPriceValue, src, "i:" .. itemID)
    if ok and price and price > 0 then return price end
  end
end

local function scanPrice(itemID)
  local e = CrateValueDB.scan[itemID]
  if e and e.price and e.price > 0 then return e.price end
end

local SOURCES = { auctionator = auctionatorPrice, tsm = tsmPrice, scan = scanPrice }
local AUTO_ORDER = { "scan", "auctionator", "tsm" }

-- Prices are cached for one evaluation pass so a refresh asks Auctionator/TSM
-- at most once per item. The cache is dropped at the start of every pass.
local priceCache, sourceCache = {}, {}
local NONE = false
local cacheDirty = false
function ns.ClearPriceCache()
  wipe(priceCache)
  wipe(sourceCache)
  cacheDirty = false
end

local lookupPrice
function ns.GetPrice(itemID)
  if cacheDirty then ns.ClearPriceCache() end
  local p = priceCache[itemID]
  if p == nil then
    local src
    p, src = lookupPrice(itemID)
    priceCache[itemID] = p or NONE
    sourceCache[itemID] = src
  end
  if p == NONE then return nil end
  return p, sourceCache[itemID]
end

-- Returns unit price in copper and the source label, or nil.
lookupPrice = function(itemID)
  local db = CrateValueDB
  local m = db.manual[itemID]
  if m then return m, "manual" end
  if db.source ~= "auto" and SOURCES[db.source] then
    local p = SOURCES[db.source](itemID)
    if p then return p, db.source end
    return nil
  end
  -- auto: the freshest data wins. Our own scan is used when it is newer than 6h,
  -- otherwise Auctionator, then TSM, then an older scan of ours.
  local e = db.scan[itemID]
  if e and e.price and e.time and (time() - e.time) < 6 * 3600 then return e.price, "scan" end
  for _, key in ipairs(AUTO_ORDER) do
    if key ~= "scan" then
      local p = SOURCES[key](itemID)
      if p then return p, key end
    end
  end
  local p = scanPrice(itemID)
  if p then return p, "scan" end
end

function ns.ResetPrices()
  CrateValueDB.scan = {}
  CrateValueDB.manual = {}
  CrateValueDB.depth = {}
  ns.ClearPriceCache()
  ns.Print("cleared scanned and manual prices.")
  if ns.Refresh then ns.Refresh() end
end

-- Price source choices shown in the window's picker and accepted by /cval source.
ns.SOURCE_OPTIONS = {
  { key = "auto",        label = "Auto",        desc = "Freshest data wins: your scan if under 6h old, then Auctionator, then TSM." },
  { key = "scan",        label = "My AH scan",  desc = "Only prices from this addon's own Scan AH button." },
  { key = "auctionator", label = "Auctionator", desc = "Only Auctionator's last-scan prices." },
  { key = "tsm",         label = "TSM",         desc = "Only TradeSkillMaster's DBMinBuyout / market prices." },
}

function ns.SourceLabel(key)
  for _, o in ipairs(ns.SOURCE_OPTIONS) do if o.key == key then return o.label end end
  return key
end

-- Whether a source can give prices right now (installed addon, or scan data saved).
function ns.SourceAvailable(key)
  if key == "auto" then return true end
  if key == "auctionator" then return (Auctionator and Auctionator.API) and true or false end
  if key == "tsm" then return TSM_API and true or false end
  if key == "scan" then return next(CrateValueDB.scan) ~= nil end
  return false
end

function ns.SetSource(key)
  if key ~= "auto" and not SOURCES[key] then return false end
  CrateValueDB.source = key
  ns.ClearPriceCache()
  if ns.Refresh then ns.Refresh() end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

function ns.AvailableSources()
  local list = {}
  if Auctionator and Auctionator.API then tinsert(list, "Auctionator") end
  if TSM_API then tinsert(list, "TSM") end
  if next(CrateValueDB.scan) then tinsert(list, "own scan") end
  return list
end

---------------------------------------------------------------------------
-- Favor and evaluation
---------------------------------------------------------------------------
function ns.CrateQuality(crate)
  return crate.quality == 2 and "uncommon" or "common"
end

-- Favor for a crate's sealed version, and whether the number is an estimate.
function ns.GetFavor(crate)
  local q = ns.CrateQuality(crate)
  local learned = CrateValueDB.learned[crate.tier .. "-" .. q]
  if learned then return learned, false end
  local t = ns.FAVOR[crate.tier]
  return t[q], t.estimated and true or false
end

---------------------------------------------------------------------------
-- Real supply ("depth"): what it costs to actually buy N of an item from the
-- listed auctions, cheapest first, instead of N x the single lowest price.
---------------------------------------------------------------------------
local DEPTH_FRESH = 30 * 60   -- listings older than 30 minutes are ignored

function ns.DepthFor(itemID)
  local d = CrateValueDB.depth[itemID]
  if d and d.time and (time() - d.time) < DEPTH_FRESH and d.tiers and #d.tiers > 0 then return d end
end

-- Returns cost (copper, or nil) and a supply table, or nil when no fresh listings are known.
-- supply = { available = total listed, short = how many are missing (0 if enough), age = seconds }
function ns.CostToBuy(itemID, qty)
  local db = CrateValueDB
  if db.manual[itemID] then return nil end                       -- a hand-set price wins
  if db.source == "auctionator" or db.source == "tsm" then return nil end
  local d = ns.DepthFor(itemID)
  if not d then return nil end
  local need, cost, available = qty, 0, 0
  for _, tier in ipairs(d.tiers) do
    available = available + tier[2]
    if need > 0 then
      local take = math.min(need, tier[2])
      cost = cost + take * tier[1]
      need = need - take
    end
  end
  -- if there were more listings than we stored, running out is not real scarcity
  local supply = { available = available, short = d.more and 0 or need, more = d.more, age = time() - d.time }
  if need > 0 then
    -- not enough listed: price the missing part at the most expensive listing seen, and flag it
    local last = d.tiers[#d.tiers][1]
    cost = cost + need * last
  end
  return cost, supply
end

-- Average cost per crate when filling n crates with the same bundle.
function ns.CostForCrates(itemID, qty, n)
  local cost, supply = ns.CostToBuy(itemID, qty * n)
  if not cost then
    local unit = ns.GetPrice(itemID)
    return unit and unit * qty or nil, nil
  end
  return cost / n, supply
end

-- Returns a result table for a crate:
-- { crate, favor, estimated, best = {itemID, qty, unit, cost, source}, bundles = {...},
--   fillCost, crateCost, total, perFavor, owned }
function ns.Evaluate(crate)
  local r = { crate = crate, bundles = {} }
  r.favor, r.estimated = ns.GetFavor(crate)
  for _, b in ipairs(crate.bundles) do
    local itemID, qty = b[1], b[2]
    local unit, src = ns.GetPrice(itemID)
    local entry = { itemID = itemID, qty = qty, unit = unit, source = src, cost = unit and unit * qty or nil }
    -- a price you set by hand always wins over live listings
    local cost, supply
    if src ~= "manual" then cost, supply = ns.CostToBuy(itemID, qty) end
    if supply then
      entry.supply = supply
      if cost then entry.cost, entry.source = cost, "AH listings" end
    end
    tinsert(r.bundles, entry)
  end
  -- cheapest bundle you can actually buy: options with too few listings only win if nothing else is priced
  for _, entry in ipairs(r.bundles) do
    if entry.cost then
      local short = entry.supply and entry.supply.short > 0
      local bestShort = r.best and r.best.supply and r.best.supply.short > 0
      if not r.best or (bestShort and not short) or (short == bestShort and entry.cost < r.best.cost) then
        r.best = entry
      end
    end
  end
  r.crateCost = ns.GetPrice(crate.id)
  r.owned = GetItemCount(crate.id) or 0
  if r.best then
    r.fillCost = r.best.cost
    r.total = r.fillCost
    if CrateValueDB.includeCrateCost then
      r.total = r.crateCost and (r.total + r.crateCost) or nil
    end
    if r.total then r.perFavor = r.total / r.favor end
  end
  return r
end

function ns.EvaluateAll()
  ns.ClearPriceCache()
  local list = {}
  for _, crate in ipairs(ns.CRATES) do tinsert(list, ns.Evaluate(crate)) end
  return list
end

-- Cheapest gold per favor across every crate with prices (always includes crate cost=false logic as configured).
function ns.BestPerFavor(results)
  local best
  for _, r in ipairs(results) do
    if r.perFavor and (not best or r.perFavor < best.perFavor) then best = r end
  end
  return best
end

-- Reputation route: Forged Delivery Receipt (15 favor) + cheapest empty Waylaid Crate -> 50 rep.
function ns.RepRoute(results)
  local cheapestCrate, cheapestPrice
  for _, r in ipairs(results) do
    if r.crateCost and (not cheapestPrice or r.crateCost < cheapestPrice) then
      cheapestCrate, cheapestPrice = r.crate, r.crateCost
    end
  end
  local best = ns.BestPerFavor(results)
  if not best then return nil end
  local favorGold = ns.RECEIPT.favorCost * best.perFavor
  local total = favorGold + (cheapestPrice or 0)
  return {
    crate = cheapestCrate, cratePrice = cheapestPrice, favorGold = favorGold,
    total = total, perRep = total / ns.RECEIPT.rep, bestFavorCrate = best.crate,
    missingCrate = cheapestPrice == nil,
  }
end

---------------------------------------------------------------------------
-- Player's trade faction and standing (for the reputation card)
---------------------------------------------------------------------------
local FACTION_BY_SIDE = { Alliance = 2586, Horde = 2587 }
local FACTION_NAME = { [2586] = "Azeroth Commerce Authority", [2587] = "Durotar Supply and Logistics" }

-- Returns factionID, name, reaction (4 = Neutral, 5 = Friendly, ...), reactionLabel. Any may be nil.
function ns.TradeFaction()
  local side = UnitFactionGroup and UnitFactionGroup("player")
  if type(issecretvalue) == "function" and issecretvalue(side) then side = nil end
  local id = FACTION_BY_SIDE[side or ""]
  if not id then return nil end
  local name, reaction = FACTION_NAME[id], nil
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and data then
      name = data.name or name
      reaction = data.reaction
    end
  end
  local label = reaction and _G["FACTION_STANDING_LABEL" .. reaction]
  return id, name, reaction, label
end

---------------------------------------------------------------------------
-- Read crate recipes from the game itself, so the addon follows Blizzard's
-- own item text instead of any website. Works on English clients; on other
-- languages the built-in data (taken from the same item text) is used.
---------------------------------------------------------------------------
local nameToID
local function materialID(name)
  if not nameToID then
    nameToID = {}
    for id, n in pairs(ns.MATERIALS) do nameToID[n:lower()] = id end
  end
  return nameToID[name:lower()]
end

ns.verified = {}   -- [crateID] = true once its in-game text matched (or corrected) our data
local syncAttempts, MAX_SYNC_ATTEMPTS = 0, 4
function ns.SyncFromGame()
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
  -- on non-English clients the text never parses; stop retrying after a few tries
  if syncAttempts >= MAX_SYNC_ATTEMPTS or ns.VerifiedCount() == #ns.CRATES then return end
  syncAttempts = syncAttempts + 1
  local changed = 0
  for _, crate in ipairs(ns.CRATES) do
    if not ns.verified[crate.id] then
      local ok, data = pcall(C_TooltipInfo.GetItemByID, crate.id)
      local bundles = {}
      if ok and data and data.lines then
        for _, line in ipairs(data.lines) do
          local t = line.leftText
          if type(t) == "string" and not (type(issecretvalue) == "function" and issecretvalue(t)) then
            for qty, name in t:gmatch("%-%s*(%d+)%s+([^\n\r]+)") do
              local id = materialID((name:gsub("%s+$", "")))
              if id then tinsert(bundles, { id, tonumber(qty) }) end
            end
          end
        end
      end
      if #bundles > 0 then
        local same = #bundles == #crate.bundles
        if same then
          for i, b in ipairs(bundles) do
            local o = crate.bundles[i]
            if o[1] ~= b[1] or o[2] ~= b[2] then same = false break end
          end
        end
        if not same then
          crate.bundles = bundles
          changed = changed + 1
          for _, b in ipairs(bundles) do ns.watched[b[1]] = true end
        end
        ns.verified[crate.id] = true
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, crate.id)
      end
    end
  end
  if changed > 0 then
    ns.Print(format("%d crate recipe(s) changed in the game; using the game's numbers.", changed))
  end
end

function ns.VerifiedCount()
  local n = 0
  for _ in pairs(ns.verified) do n = n + 1 end
  return n, #ns.CRATES
end

---------------------------------------------------------------------------
-- Learning real favor values from turn-ins ("A Sealed Crate" quests)
---------------------------------------------------------------------------
local function favorQuantity()
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, ns.FAVOR_CURRENCY_ID)
    local q = ok and info and info.quantity
    if type(issecretvalue) == "function" and issecretvalue(q) then return nil end
    return type(q) == "number" and q or nil
  end
end

local pending
local function onQuestDialog()
  if (GetTitleText and GetTitleText()) ~= "A Sealed Crate" then return end
  pending = pending or {}
  local link = GetQuestItemLink and GetQuestItemLink("required", 1)
  if link then pending.link = link end
  pending.before = favorQuantity()
end

local function onTurnedIn()
  if not (pending and pending.link and pending.before) then pending = nil return end
  local p = pending
  pending = nil
  C_Timer.After(1.5, function()
    local after = favorQuantity()
    if not after then return end
    local gained = after - p.before
    local name, _, quality = GetItemInfo(p.link)
    local tier = name and name:match("^Sealed (%a+) Crate")
    if not (tier and gained > 0 and ns.FAVOR[tier]) then return end
    local q = (quality == 2 and "uncommon") or (quality == 3 and "rare") or "common"
    local key = tier .. "-" .. q
    local old = CrateValueDB.learned[key]
    -- Keep the lowest value seen so Performance Bonus double-favor procs don't inflate it.
    if not old or gained < old then
      CrateValueDB.learned[key] = gained
      ns.Print(format("learned %s %s crate = %d Merchant's Favor.", q, tier, gained))
      if ns.Refresh then ns.Refresh() end
    end
  end)
end

---------------------------------------------------------------------------
-- Auction house scanning (own "last scan" data)
---------------------------------------------------------------------------
local ahOpen = false
local function record(itemID, unit)
  if not (itemID and ns.watched[itemID] and unit and unit > 0) then return false end
  local e = CrateValueDB.scan[itemID]
  if e then
    e.price, e.time = unit, time()
  else
    CrateValueDB.scan[itemID] = { price = unit, time = time() }
  end
  cacheDirty = true
  return true
end

local PRICE_SORT
local function priceSorts()
  if PRICE_SORT == nil then
    PRICE_SORT = {}
    if Enum and Enum.AuctionHouseSortOrder then
      PRICE_SORT = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    end
  end
  return PRICE_SORT
end

local MODERN = C_AuctionHouse and C_AuctionHouse.GetBrowseResults and true or false

-- Store the listed auctions for a commodity (cheapest first).
local MAX_TIERS = 40
local function recordCommodityDepth(itemID)
  if not (itemID and ns.watched[itemID] and C_AuctionHouse.GetNumCommoditySearchResults) then return false end
  local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
  if not ok or not n or n == 0 then return end
  local tiers = {}
  for i = 1, math.min(n, MAX_TIERS) do
    local ok2, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
    if ok2 and info and info.unitPrice and info.quantity then
      tinsert(tiers, { info.unitPrice, info.quantity })
    end
  end
  if #tiers > 0 then
    table.sort(tiers, function(a, b) return a[1] < b[1] end)
    CrateValueDB.depth[itemID] = { time = time(), tiers = tiers, more = n > MAX_TIERS }
    record(itemID, tiers[1][1])
    return true
  end
  return false
end

-- Non-commodity listings (in case crates are sold as items): only single-item auctions are unambiguous.
local function recordItemDepth(itemKey)
  local itemID = itemKey and itemKey.itemID
  if not (itemID and ns.watched[itemID] and C_AuctionHouse.GetNumItemSearchResults) then return false end
  local ok, n = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
  if not ok or not n or n == 0 then return end
  local tiers = {}
  for i = 1, math.min(n, MAX_TIERS) do
    local ok2, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
    if ok2 and info and info.buyoutAmount and (info.quantity or 1) == 1 then
      tinsert(tiers, { info.buyoutAmount, 1 })
    end
  end
  if #tiers > 0 then
    table.sort(tiers, function(a, b) return a[1] < b[1] end)
    CrateValueDB.depth[itemID] = { time = time(), tiers = tiers }
    record(itemID, tiers[1][1])
    return true
  end
  return false
end

-- One-item-at-a-time lookups, triggered by clicking a crate. Gentle on the server:
-- one query per second, waits for the AH throttle, skips items checked in the last 5 minutes.
local depthQueue, depthQueued, depthBusy = {}, {}, false
local DEPTH_GAP, DEPTH_RECHECK = 1.0, 5 * 60

local function depthStep()
  if not ahOpen then depthQueue, depthQueued, depthBusy = {}, {}, false return end
  if ns.IsScanning and ns.IsScanning() then C_Timer.After(1, depthStep) return end
  local itemID = tremove(depthQueue, 1)
  if not itemID then
    depthBusy = false
    if ns.Refresh then ns.Refresh() end
    return
  end
  depthQueued[itemID] = nil
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    tinsert(depthQueue, 1, itemID)
    depthQueued[itemID] = true
    C_Timer.After(0.5, depthStep)
    return
  end
  pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(itemID), priceSorts(), false)
  if ns.Refresh then ns.Refresh() end
  C_Timer.After(DEPTH_GAP, depthStep)
end

-- Queue supply checks for a crate's materials (and the crate itself). Returns how many were queued.
function ns.CheckSupply(crate)
  if not (MODERN and ahOpen and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
    if not ahOpen then ns.Print("open the Auction House to check real supply.") end
    return 0
  end
  local n = 0
  local ids = {}
  for _, b in ipairs(crate.bundles) do tinsert(ids, b[1]) end
  tinsert(ids, crate.id)
  for _, id in ipairs(ids) do
    local d = CrateValueDB.depth[id]
    local fresh = d and d.time and (time() - d.time) < DEPTH_RECHECK
    if not fresh and not depthQueued[id] then
      tinsert(depthQueue, id)
      depthQueued[id] = true
      n = n + 1
    end
  end
  if n > 0 and not depthBusy then
    depthBusy = true
    depthStep()
  end
  return n
end

function ns.IsCheckingSupply(crate)
  if not crate then return depthBusy end
  for _, b in ipairs(crate.bundles) do if depthQueued[b[1]] then return true end end
  return depthQueued[crate.id] and true or false
end

local function readBrowseResults()
  local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
  if not ok or not results then return end
  local n = 0
  for _, res in ipairs(results) do
    if res.itemKey and res.minPrice and record(res.itemKey.itemID, res.minPrice) then
      n = n + 1
    end
  end
  if n > 0 and ns.Refresh then ns.Refresh() end
end

-- Classic-style AH fallback: sequential exact-name queries.
local classicQueue, classicCurrent, classicMin
local classicFrame = CreateFrame("Frame")
classicFrame:Hide()
classicFrame:SetScript("OnUpdate", function(self)
  if classicCurrent or not CanSendAuctionQuery or not CanSendAuctionQuery() then return end
  local nextID = classicQueue and tremove(classicQueue, 1)
  if not nextID then
    self:Hide()
    ns.Print("scan finished.")
    if ns.Refresh then ns.Refresh() end
    return
  end
  classicCurrent, classicMin = nextID, nil
  QueryAuctionItems(ns.ItemName(nextID), nil, nil, 0, false, nil, false, true)
end)

local function readClassicList()
  if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
  local mins = {}
  for i = 1, GetNumAuctionItems("list") do
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
    if itemID and buyout and buyout > 0 and count and count > 0 then
      local unit = buyout / count
      if not mins[itemID] or unit < mins[itemID] then mins[itemID] = unit end
    end
  end
  for itemID, unit in pairs(mins) do record(itemID, unit) end
  classicCurrent = nil
end

-- Modern AH scan. Sending all ~126 item keys in one request got players disconnected,
-- so we send small batches, wait for each batch's results and respect the AH throttle.
local BATCH_SIZE = 5
local BATCH_DELAY = 1.5   -- seconds between batches
local BATCH_TIMEOUT = 6   -- give up waiting for a batch's results after this long
local scan = { active = false }

local function scanDone(msg)
  scan.active, scan.waiting, scan.queue = false, false, nil
  if msg then ns.Print(msg) end
  if ns.OnScanProgress then ns.OnScanProgress() end
  if ns.Refresh then ns.Refresh() end
end

local scanStep
local function scheduleStep(delay)
  local id = scan.id
  C_Timer.After(delay, function()
    if scan.active and scan.id == id then scanStep() end
  end)
end

scanStep = function()
  if not scan.active then return end
  if not ahOpen then return scanDone("scan stopped (Auction House closed).") end
  if #scan.queue == 0 then return scanDone(format("scan finished: %d items checked.", scan.total)) end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    return scheduleStep(0.5)
  end
  local keys = {}
  while #keys < BATCH_SIZE and #scan.queue > 0 do
    tinsert(keys, C_AuctionHouse.MakeItemKey(tremove(scan.queue, 1)))
  end
  local ok, err = pcall(C_AuctionHouse.SearchForItemKeys, keys, priceSorts())
  if not ok then return scanDone("scan failed: " .. tostring(err)) end
  scan.waiting = true
  scan.batch = (scan.batch or 0) + 1
  local batch = scan.batch
  if ns.OnScanProgress then ns.OnScanProgress(scan.total - #scan.queue, scan.total) end
  -- if the results never arrive, move on anyway after a timeout
  C_Timer.After(BATCH_TIMEOUT, function()
    if scan.active and scan.waiting and scan.batch == batch then
      scan.waiting = false
      scanStep()
    end
  end)
end

-- called from the browse-results event
local function onScanResults()
  if scan.active and scan.waiting then
    scan.waiting = false
    scheduleStep(BATCH_DELAY)
  end
end
ns.OnScanResults = onScanResults

function ns.IsScanning() return scan.active end

function ns.StopScan()
  if scan.active then scanDone("scan stopped.") end
  classicFrame:Hide()
end

function ns.Scan()
  if scan.active then return ns.StopScan() end
  if not ahOpen then
    ns.Print("open the Auction House first, then press Scan.")
    return
  end
  local ids = {}
  for id in pairs(ns.watched) do tinsert(ids, id) end
  if MODERN and C_AuctionHouse.SearchForItemKeys and C_AuctionHouse.MakeItemKey then
    scan.active, scan.waiting, scan.batch = true, false, 0
    scan.id = (scan.id or 0) + 1
    scan.queue, scan.total = ids, #ids
    ns.Print(format("scanning %d items in small batches (about %d seconds). Press Scan again to stop.",
      #ids, math.ceil(#ids / BATCH_SIZE * (BATCH_DELAY + 0.5))))
    scanStep()
  elseif QueryAuctionItems then
    classicQueue, classicCurrent = ids, nil
    classicFrame:Show()
    ns.Print(format("scanning %d items (one query each, about %d seconds)...", #ids, #ids))
  else
    ns.Print("no auction house API found on this client.")
  end
end

function ns.IsAHOpen() return ahOpen end

---------------------------------------------------------------------------
-- Tooltips on Waylaid Crates
---------------------------------------------------------------------------
local tipCache = { id = nil, at = 0, result = nil }
local function addCrateLines(tooltip, itemID)
  if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
  local crate = itemID and ns.byID[itemID]
  if not crate then return end
  -- tooltips can refresh several times a second while hovered; reuse the result briefly
  local now = GetTime()
  local r = tipCache.result
  if tipCache.id ~= itemID or now - tipCache.at > 1 or cacheDirty then
    r = ns.Evaluate(crate)
    tipCache.id, tipCache.at, tipCache.result = itemID, now, r
  end
  tooltip:AddLine(" ")
  tooltip:AddLine(format("|cff33ff99CrateValue|r  %d Merchant's Favor%s", r.favor, r.estimated and " (est.)" or ""))
  for _, b in ipairs(r.bundles) do
    local mark = (b == r.best) and "|cff00ff00>|r " or "   "
    tooltip:AddDoubleLine(format("%s%dx %s", mark, b.qty, ns.ItemName(b.itemID)), ns.Money(b.cost), 1, 1, 1)
  end
  if r.perFavor then
    tooltip:AddDoubleLine("Cost per favor", ns.Money(r.perFavor), 1, 0.82, 0)
  end
  tooltip:Show()
end

local function hookTooltips()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if data and data.id then addCrateLines(tooltip, data.id) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      local id = link and tonumber(link:match("item:(%d+)"))
      addCrateLines(tooltip, id)
    end)
  end
end

---------------------------------------------------------------------------
-- Events and slash commands
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
local function tryRegister(ev) pcall(events.RegisterEvent, events, ev) end
tryRegister("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
tryRegister("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
tryRegister("COMMODITY_SEARCH_RESULTS_UPDATED")
tryRegister("ITEM_SEARCH_RESULTS_UPDATED")
tryRegister("AUCTION_ITEM_LIST_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    CrateValueDB = CrateValueDB or {}
    applyDefaults(CrateValueDB, DEFAULTS)
    ns.PruneSavedData()
    hookTooltips()
    -- Item info is not cached at login on Forever; ask the client to load names for our items.
    if C_Item and C_Item.RequestLoadItemDataByID then
      for id in pairs(ns.watched) do pcall(C_Item.RequestLoadItemDataByID, id) end
    end
  elseif event == "PLAYER_LOGIN" then
    -- item text is loaded lazily; give the client a moment, then check recipes twice
    C_Timer.After(5, ns.SyncFromGame)
    C_Timer.After(30, ns.SyncFromGame)
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    if ns.OnAHChanged then ns.OnAHChanged() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    ns.StopScan()
    if ns.OnAHChanged then ns.OnAHChanged() end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    readBrowseResults()
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then ns.OnScanResults() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if recordCommodityDepth(arg1) and ns.Refresh then ns.Refresh() end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if recordItemDepth(arg1) and ns.Refresh then ns.Refresh() end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    readClassicList()
  elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
    onQuestDialog()
  elseif event == "QUEST_TURNED_IN" then
    onTurnedIn()
  elseif event == "BAG_UPDATE_DELAYED" then
    if ns.frame and ns.frame:IsShown() and ns.Refresh then ns.Refresh() end
  end
end)

-- Keep SavedVariables small: drop listings older than an hour (they are only used for 30 minutes)
-- and anything recorded for items the addon no longer tracks.
function ns.PruneSavedData()
  local now = time()
  for id, d in pairs(CrateValueDB.depth) do
    if not ns.watched[id] or not d.time or now - d.time > 3600 then CrateValueDB.depth[id] = nil end
  end
  for id in pairs(CrateValueDB.scan) do
    if not ns.watched[id] then CrateValueDB.scan[id] = nil end
  end
  for id, v in pairs(CrateValueDB.manual) do
    if not ns.watched[id] or type(v) ~= "number" or v <= 0 then CrateValueDB.manual[id] = nil end
  end
end

local function memoryKB()
  local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
  local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
  if not (update and get) then return nil end
  local ok = pcall(update)
  if not ok then return nil end
  local ok2, kb = pcall(get, ADDON)
  return ok2 and kb or nil
end
ns.MemoryKB = memoryKB

local function findItemID(text)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if id then return id end
  local lower = text:lower()
  for itemID, name in pairs(ns.MATERIALS) do
    if name:lower() == lower then return itemID end
  end
  for _, crate in ipairs(ns.CRATES) do
    if crate.name:lower() == lower or ns.ShortName(crate):lower() == lower then return crate.id end
  end
end

local MAX_PRICE = 9999999 * 10000   -- 9,999,999 gold
local function parseMoney(s)
  -- accepts "1g20s5c", "1.5g", "35s", "35" (silver). Returns nil for anything else.
  s = s:lower():gsub("%s", "")
  if #s == 0 or #s > 20 then return nil end
  local total
  if s:match("^[%d%.]+$") then
    local n = tonumber(s)
    total = n and n * 100
  else
    -- the whole string must be number+unit pairs, e.g. "1g20s"
    if s:gsub("[%d%.]+[gsc]", "") ~= "" then return nil end
    total = 0
    for num, unit in s:gmatch("([%d%.]+)([gsc])") do
      local n = tonumber(num)
      if not n then return nil end
      total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
  end
  if not total or total ~= total then return nil end   -- nil or NaN
  total = floor(total + 0.5)
  if total <= 0 or total > MAX_PRICE then return nil end
  return total
end
ns.ParseMoney = parseMoney

-- Copper as plain text people can type back in, e.g. "1g20s5c".
function ns.MoneyPlain(copper)
  copper = floor(copper + 0.5)
  local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
  local out = (g > 0 and (g .. "g") or "") .. (s > 0 and (s .. "s") or "") .. (c > 0 and (c .. "c") or "")
  return out ~= "" and out or "0c"
end

-- Set (or clear, with nil/empty text) a hand-entered price. Returns true on success.
function ns.SetManualPrice(itemID, textValue)
  if not ns.watched[itemID] then
    ns.Print("that item isn't a Waylaid Crate or one of its materials.")
    return false
  end
  textValue = textValue and textValue:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if textValue == "" or textValue:lower() == "clear" then
    CrateValueDB.manual[itemID] = nil
    ns.Print("cleared the hand-set price for " .. ns.ItemName(itemID) .. ".")
  else
    local copper = parseMoney(textValue)
    if not copper then
      ns.Print("couldn't read that price. Use silver like 45, or 1g20s (more than 0).")
      return false
    end
    CrateValueDB.manual[itemID] = copper
    ns.Print(format("%s set to %s each.", ns.ItemName(itemID), ns.Money(copper)))
  end
  ns.ClearPriceCache()
  if ns.Refresh then ns.Refresh() end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

SLASH_CRATEVALUE1 = "/cratevalue"
SLASH_CRATEVALUE2 = "/cval"
SlashCmdList.CRATEVALUE = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "show" then
    ns.Toggle()
  elseif cmd == "scan" then
    ns.Scan()
  elseif cmd == "source" then
    local s = rest:lower()
    if ns.SetSource(s) then
      ns.Print("price source set to " .. ns.SourceLabel(s) .. ".")
      if not ns.SourceAvailable(s) then ns.Print("note: no " .. ns.SourceLabel(s) .. " data yet, so prices will be blank until there is.") end
    else
      ns.Print("usage: /cval source auto|auctionator|tsm|scan")
    end
  elseif cmd == "price" then
    -- /cval price <item name or link> <amount>   (amount in silver, or like 1g20s)
    local item, amount = rest:match("^(.-)%s+(%S+)$")
    local id = item and findItemID(item)
    local copper = amount and parseMoney(amount)
    if id and (amount == "clear" or copper) then
      ns.SetManualPrice(id, amount)
    else
      ns.Print("usage: /cval price <item name or link> <silver | 1g20s | clear>")
    end
  elseif cmd == "favor" then
    -- /cval favor <tier> <common> <uncommon>
    local tier, c, u = rest:match("^(%a+)%s+(%d+)%s+(%d+)$")
    tier = tier and (tier:sub(1, 1):upper() .. tier:sub(2):lower())
    if tier and ns.FAVOR[tier] then
      CrateValueDB.learned[tier .. "-common"] = tonumber(c)
      CrateValueDB.learned[tier .. "-uncommon"] = tonumber(u)
      ns.Print(format("%s crates set to %s / %s favor.", tier, c, u))
      if ns.Refresh then ns.Refresh() end
    else
      ns.Print("usage: /cval favor <apprentice|journeyman|expert|artisan> <white> <green>")
    end
  elseif cmd == "options" or cmd == "config" then
    ns.OpenOptions()
  elseif cmd == "minimap" then
    ns.SetMinimapShown(CrateValueDB.minimapHide)
    ns.Print(CrateValueDB.minimapHide and "minimap button hidden (/cval minimap to show it)." or "minimap button shown.")
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if v and v >= 0.6 and v <= 1.6 then
      v = ns.SetScale(v)
      ns.Print(format("window scale set to %.2f.", v))
    else
      ns.Print("usage: /cval scale <0.6 - 1.6>   (default 1)")
    end
  elseif cmd == "about" or cmd == "version" then
    ns.Print(format("version %s, by %s (%s license).", ns.VERSION, ns.AUTHOR, ns.LICENSE))
    ns.Print("Ranks Waylaid Crates by gold per Merchant's Favor and prices ACA / DSL reputation.")
    ns.Print("Crate recipes: the game's own item text. Prices: your AH scans, Auctionator or TSM.")
    ns.Print("Built with the help of Claude.")
    local depthCount = 0
    for _ in pairs(CrateValueDB.depth) do depthCount = depthCount + 1 end
    local scanCount = 0
    for _ in pairs(CrateValueDB.scan) do scanCount = scanCount + 1 end
    local kb = memoryKB()
    ns.Print(format("stored prices: %d items, live listings: %d items%s.", scanCount, depthCount,
      kb and format(", memory: %.0f KB", kb) or ""))
  elseif cmd == "reset" then
    ns.ResetPrices()
  else
    ns.Print("/cval  - open the window")
    ns.Print("/cval options  - open the options page (also: Esc > Options > AddOns)")
    ns.Print("/cval minimap  - show or hide the minimap button")
    ns.Print("/cval scan  - scan crate materials at the open Auction House")
    ns.Print("/cval source auto|auctionator|tsm|scan  - pick the price source")
    ns.Print("/cval price <item> <silver|1g20s|clear>  - set a price by hand")
    ns.Print("/cval favor <tier> <white> <green>  - override favor values")
    ns.Print("/cval scale <0.6-1.6>  - make the window bigger or smaller")
    ns.Print("/cval reset  - forget scanned and manual prices")
    ns.Print("/cval about  - version, author and memory use")
  end
end
