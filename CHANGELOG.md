# CrateValue changelog

## 1.6.0
- Scan button says "Open AH to scan" while the Auction House is closed, and its tooltip explains why.
- Fixed a possible UI taint: the addon no longer reassigns Blizzard's StaticPopupDialogs table.
- Price entry is stricter: odd input (like "1.2.3" or "0") is rejected instead of causing a Lua error, prices are capped,
  and hand-set prices only apply to crates and their materials.
- Crate tooltips refresh as new prices arrive even with the window closed, and reuse their result while hovered.
- Options won't try to open during combat.

## 1.5.2
- Set prices by hand from the window: right-click a crate row, pick a material (or the empty crate), type a price.
  Hand-set prices show "set by hand" in the tooltip and always beat AH data. Clear them per crate, or all at once in Options.

## 1.5.1
- Minimap button now reappears after UI packs (like EllesmereUI) tidy the minimap at login.

## 1.5.0
- Minimap button: left-click opens the window, right-click opens options, drag to move it around the minimap.
- Options page under Esc > Options > AddOns > CrateValue (also the Options button in the window, or `/cval options`):
  minimap button, window size, reset window position, price source, empty-crate price, bags filter, clear saved prices.
- Also listed in the addon compartment menu by the minimap, where the client has one.

## 1.4.4
- Best crate is highlighted in the list itself (green background and frame, BEST tag); the separate box is gone.
- FAVOR and HAVE column headers no longer cut off; shorter label for the empty-crate checkbox.

## 1.4.1
- Price source picker: click **Change** on the Price Data card (Auto, My AH scan, Auctionator, TSM). Sources with no data are greyed out.
- Rep card renamed "Reputation cost" with shorter text and a much shorter tooltip.

## 1.4.0
- Version and author shown in the title bar; new `/cval about` (version, author, stored data, memory use).
- Performance pass: redraws are coalesced (one redraw per burst of events), prices are looked up once per redraw,
  unrelated Auction House browsing no longer triggers redraws, and the window is only built the first time you open it.
- Saved data is pruned at login (old listings, untracked items) so the SavedVariables file stays small.
- In-game recipe check stops retrying after a few attempts on non-English clients.

## 1.3.1
- Sorting by Crate now orders by tier (Apprentice, Journeyman, Expert, Artisan), then white before green crates, then name.

## 1.3.0
- Real supply: click a crate at the Auction House to read the actual listings for its materials (one item per second).
  Costs then reflect buying the full amount cheapest-first instead of N x the lowest price; "+" marks checked costs.
- Bundles without enough listings are flagged "(low supply)" and only win when nothing else is priced.
- Tooltip shows gold per favor for 1 crate, all crates in your bags, and 5 crates, so you can see prices climb.

## 1.2.1
- Fixed the footer: the two checkboxes and the hint text no longer overlap. "/cval help" moved to the title bar.

## 1.2.0
- Crate recipes now come from the game itself: each crate's tooltip is read in game and the built-in data (taken from the same item text via Wowhead) is corrected if Blizzard changes it.
- Reworked the reputation card: "Rep via Delivery Receipt" shows the cost per 50-rep turn-in, your faction standing, and warns when receipts are still locked (below Friendly). Hover for step-by-step instructions.

## 1.1.0
- New flat dark window: summary cards, item icons, tier stripes, value bars, BEST / IN BAGS tags.
- AH scan now sends small throttled batches (5 items, 1.5s apart) instead of one large request that could disconnect you.
- Scan button shows progress and can be clicked again to stop. `/cval scale` to resize the window.

## 1.0.0
- First release: ranks all 30 Waylaid Crates by gold per Merchant's Favor using its own AH scan, Auctionator or TSM prices.
