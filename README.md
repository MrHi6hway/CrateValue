# CrateValue (WoW Forever)

Ranks every Waylaid Crate by **gold per Merchant's Favor**, using Auction House prices, and shows what
**Azeroth Commerce Authority / Durotar Supply and Logistics reputation** costs in gold.

## Install
Copy the `CrateValue` folder into your Forever client's `Interface\AddOns\` folder
(the beta used `World of Warcraft\_classic_beta_\Interface\AddOns\`). Restart the client if it doesn't show up.
Interface is `16001`; check yours with `/dump select(4, GetBuildInfo())` and edit `CrateValue.toc` if it differs.

## Use
- Click the **minimap button** (or type `/cval`) to open the window. Right-click it for **options**, also under Esc > Options > AddOns > CrateValue.
- `/cval` (or `/cratevalue`) opens the window. Click column headers to sort, use the tier buttons to filter.
- At the Auction House, press **Scan AH** (or `/cval scan`): searches all 96 materials + 30 crates in small batches (about 50 seconds), lowest price kept. Press again to stop.
- Pick where prices come from with **Change** on the Price Data card (Auto, My AH scan, Auctionator, TSM).
- Prices also come from **Auctionator** (its last-scan data) or **TSM** if installed. Fresh own-scan data (<6h) wins, then Auctionator, then TSM.
- **Click a crate row at the AH** to check real supply: it reads the listings for that crate's materials and prices
  the full amount cheapest-first (marked `+`). Low supply is flagged, and the tooltip shows cost per favor for 1 vs several crates.
- **Right-click a crate row** to set a material's price by hand (for example, what you pay a farmer). Hand-set prices always win.
- Hover a Waylaid Crate anywhere (bags, AH) to see each bundle's cost and the cheapest one.
- "Add the empty crate's AH price" adds the crate's own price, for when you'd buy crates rather than loot them.

Commands: `/cval source auto|auctionator|tsm|scan`, `/cval price <item> <silver|1g20s|clear>`,
`/cval favor <tier> <white> <green>`, `/cval scale <0.6-1.6>`, `/cval options`, `/cval minimap`, `/cval about`, `/cval reset`.

## The numbers
- Raw-material crates (Textiles, Ore, Herbs, Curiosities) seal **white**; crafted ones (Fabrics, Ingots, Parts) seal **green** for double favor.
  Apprentice 5/10, Journeyman 10/20, Expert 15/30. **Artisan is unconfirmed**, estimated 20/40 (marked `*`).
  The addon learns the real value the first time you turn in a sealed crate (lowest value seen, so Performance Bonus procs don't inflate it).
- Crate recipes are read from each crate's own tooltip in game and corrected automatically if Blizzard changes them (English clients).
- **Sealed crates give no reputation.** Crate-based rep is the Forged Delivery Receipt (Friendly, 15 favor) + any empty Waylaid Crate
  = 50 rep. The "Reputation cost" card prices that route: 15 x your cheapest gold-per-favor + the cheapest empty crate on the AH.
  Other rep: Craftsman's Writs (75 / 125 / 200 rep, daily each) and the one-time Shipping Label (2,000 rep, 50 favor).

Author: MrHi6hway2. Released under the MIT license (see LICENSE). Built with the help of Claude.

Sources: crate recipes come from the game's own Waylaid Crate item text (also listed in Wowhead's WoW Forever
database) and are re-checked in game every session. Favor values come from Wowhead's "A Sealed Crate" quest data;
reputation rules from the in-game vendors and Wowhead's Forever reputation guides.
