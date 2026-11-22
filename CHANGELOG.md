# Foxden

## 2.3.12

### All in one
- **Foxden works on its own from CurseForge.** No companion app and no other addons needed: recipes, materials and costs, the leveling planner, boss loot, quest rewards, dungeon quests, class trainer lists, rare timers and an auction price snapshot are built in. A weekly data update keeps them fresh, so keep Foxden updated (turn on Auto-update in the CurseForge app).
- **QuestieDB is optional now:** dungeon entrance marks and trash drops are built in too. If it's installed, Foxden still reads its newest data.
- The companion app is an extra: daily prices, website requests, and posting runs to Discord.

### Also
- **/fox errors** shows anything that went wrong in Foxden, with a box to copy it all for a report. **/fox selftest** checks every page, the themes, the pictures and the data.
- **Fixed: "No player named '…' is currently playing"** for guildmates with a surname (WoW Forever): Foxden now whispers names exactly as the game writes them.

## 2.3.11

- **Your stats** (Home → Your stats): this week or all time. Kills, deaths, quests, gold looted, levels and dungeon runs, plus fun facts: most killed, the enemy you died fighting most, your most dangerous zone, favourite ability, favourite zone, dungeon nemesis and fastest clear. Most of these start counting now; quests and levels come from the game's own records, so they go back to level 1.
- **This week** tile on Home: your runs, levels, quests, kills and deaths, and what you killed most.
- **Wowhead link in quest details:** click a quest in the quest tracker, and copy its Wowhead link from the panel.

## 2.3.10

- **Light and dark themes:** Settings → **Theme**, or the **Light / Dark** button at the top of the Foxden window. Switches straight away.
- **Readable in light mode:** every text color meets the WCAG AA contrast standard (4.5:1) on the light background. Class colors, gold, the accent and colored text are darkened just enough when they'd be too pale.

## 2.3.9

### A new look
- **Picture cards everywhere:** Dungeons opens on a grid of dungeon and raid cards with the game's own art (Forever's new dungeons use their loading screens), your quest progress, levels, runs and who wants to run it. Click one to open it; **< All dungeons** goes back.
- **Home as tiles:** you (XP bar), your trainer, picture cards for the dungeons at your level, guild online with class icons, looking for group and your runs.
- **Overviews for every section:** Crafting (a card per profession with your skill, crafters and offers), Guild (online now, dungeon night, rares, leveling, and a tile per guildmate online) and Quests (**Your quests**: a card per zone in your log).
- **A richer sidebar:** you at the top (class icon, level, XP, played time, time this level, gold, item level, rested, runs), each section's pages listed under it, and guild online at the bottom. On narrow windows it becomes a slim icon rail with the tabs on top; the window can now be made smaller.
- **Window look** (Settings): **Stone + art** (default) uses the game's marble and rock with a warm trim and a dimmed picture across the top of each section; **Stone** without the pictures; **Plain** is the old flat look.

### Fixed
- Overview tabs that did nothing when clicked.
- The window opening empty, and Home tiles left blank: round class icons now come from the game's round icon sheet.
- Stretched zone pictures, and dungeon headers in your quest log now use the dungeon's art.

## 2.3.8

- **Guildmates' zones on the world map:** everyone online, even without Foxden, as a badge on their zone with how many are there (names and levels on hover). The game only tells addons the zone, not the spot; guildmates who share their location with Foxden are still exact dots. Someone inside a dungeon shows at its entrance. Turn it off in Settings (**Guildmates' zones on the world map**).
- **Class icons** for guildmates on the Guild page map and the world map, instead of letters and plain dots.
- **Fixed: the same guildmate showing more than once** on the Guild page map (old saved locations under a second name are merged).
- **Boss loot learns from the whole group:** everything anyone in your group gets from a boss now goes on that boss's loot list, not only what you loot yourself. The new dungeons fill in as the guild runs them.
- **Look it up online** on every boss: a Wowhead link to copy, for its loot, guides and comments.

## 2.3.7

- **Boss icons on dungeon maps for 12 dungeons**, from Blizzard's own boss positions: Wailing Caverns, Blackfathom Deeps, Razorfen Kraul, Gnomeregan, Razorfen Downs, Uldaman, Zul'Farrak, Maraudon, Sunken Temple, Blackrock Depths, Dire Maul and Stratholme. Hover a boss for its loot, click for the loot list. Others still need **Place bosses** once (it's shared with the guild).
- **The dungeon's map on the world map:** inside a dungeon or raid, the map (M) shows the dungeon's own map with its bosses. Floor buttons for dungeons with several floors; right-click or **Game map** for the game's map. Turn it off in Settings (**Dungeon map on the world map**).
- **Dungeons and raids are picked separately** on the Dungeons page (**Dungeons | Raids**).
- **Quest chains for every quest:** click a quest in the quest tracker and its details show the whole chain, with **you're here**, done steps and steps in your log. Hover a step for its XP, gold, reputation and items; click it to open that quest, even one you don't have yet (Map and Arrow then go to its quest giver). Dungeon and raid quests are tagged.
- **Fixed: the quest Link button** (and shift-click in the quest tracker) did nothing.

## 2.3.6

- **Fixed: pressing M (or any key) set it as the Fishing key** and unbound what it did before ("M was "Toggle World Map Pane" before; that action is now unbound"). The key picker now only listens after you click it. On your next login Foxden takes back any fishing key you didn't pick yourself and gives M back to the world map. Want a fishing key? Set it again in **Settings → Keys**.
- **Quest chains on every quest card** in a dungeon's Quests tab, not just the one you pick, with the step you're on marked **you're here** (or **in your log** when you have it).
- **Dungeon entrances use the game's swirl** on the world map (the raid swirl for raids). Hover for the levels, coloured for your level.

## 2.3.5

- **Auction prices anywhere:** item tooltips show what the item goes for on the auction house ("Auction: 1g 20s (14 listed)"), wherever you are, not just at the auctioneer. `/fox price <item>` does the same: shift-click the item into chat or type its name. The prices come from your guild website, refreshed daily, and arrive with the website data (the companion app). Turn it off in Settings (**Auction prices in tooltips**).
- **Quest switches in Settings:** **Quest tracker** turns Foxden's quest list at the side of the screen off, and **Quest marks** turns off every ! and ? on the map and minimap at once.
- **The game's quest tracker comes back** when Foxden's is off. Before, hiding the game's tracker stayed on and left you with none.

## 2.3.4

- **Fishing key:** one key that casts Fishing. Set it in **Settings → Keys → Fishing key** (or the game's Key Bindings under AddOns → Foxden). It starts unbound, so nothing changes until you pick a key. You still press it for every cast.

## 2.3.3

- **No more "No player named '…-' is currently playing" spam.** When Foxden passed a run to a guildmate for the website, it could address them with an empty realm ("Foxwarrior-"), which the server rejects, once per piece of the run. It now whispers the plain name. Same fix for the whisper Foxden sends when you ask a crafter to make something.
- **Dungeon maps:** each dungeon's page shows its map with every floor, falling back to the game's own map pictures. Hover a boss for its loot, click for the full loot list.
- **Boss pins:** place pins on a dungeon map and share them with the guild.
- **Write boss tips in game:** Dungeons → a boss → **Write a tip**. Pick Tank, DPS, Healer or Everyone and save; the companion app sends it to the website with your character's name, and it shows for the whole guild after their next update. Yours shows straight away as "on its way". Same rules as the website: 600 characters, no links; removing a tip is still for officers, on the website.

## 2.3.2

- **The game's quest tracker (and EllesmereUI's) stays hidden** when **Hide the game's quest tracker** is on. It kept coming back: Edit Mode puts the game's tracker back on screen, and EllesmereUI redraws its own. Foxden now uses EllesmereUI's own switch for hiding its tracker, and hides the game's again whenever something shows it.
- **The run tracker shows up by itself** when a run starts or picks back up. It could stay hidden after a loading screen until you gained XP or gold.
- **Back in after leaving mid-run:** go back into a dungeon within an hour of leaving it before the last boss and Foxden picks your run up where it stopped, instead of starting a new one at 0/6. Pieces of one run that an older Foxden closed at each death are joined back into one, and the website drops the extra copies. A run that had already started again (no boss down yet) is folded in. Right-click the run tracker to end it if you're really starting over.
- **Dungeon entrances on the world map:** a skull at every dungeon and raid entrance, ringed in its level colour (bigger for raids), on the zone map and the continent. Hover for its levels, wings and boss count; click to open it in Foxden, shift-click for the arrow. Turn it off on the Quests page (**Dungeon entrances**). Needs the QuestieDB addon, like the Entrance button.

## 2.3.1

- **Dying no longer ends the run.** Releasing (or hearthing, or stepping out to a vendor) before the last boss keeps the run going; go back in and it carries on. A run ends at the last boss, when you enter a different dungeon, or when you end it yourself: right-click the run tracker, the **End run** button on the run's page, or `/fox end`.

## 2.3.0

### Fixed
- Quest marks stopped drawing ("Couldn't draw quest marks (quest details)") after opening the details of a quest that can be shared.

### Dungeon runs
- **Run summary:** when the last boss dies, a summary pops up once you're out of combat: time, XP, gold, and every boss with the time it died, plus **Full summary** for the whole run. It also shows if you leave before the last boss. Turn it off in Settings (**Run summary**), or bring it back with `/fox summary`.
- **The clock starts on your first pull,** not when you zone in, and **stops at the last boss**, so a run's time is pull to final kill. Looting and walking out afterwards don't count.
- **Loot:** the summary shows everything your group looted (icons, best first; hover for who got it and which boss dropped it, shift-click to link). The full run has a new **Loot** tab with the whole list.
- **Wings:** Scarlet Monastery, Dire Maul, Blackrock Spire and Stratholme count as the wing you're in (Graveyard, Library, Armory, Cathedral; East, West, North; Lower and Upper; Main Gate and Service Entrance). The tracker, the summary and the run list show only that wing's bosses, and the run ends at the wing's last boss. Foxden tells the wing from the zone text on the way in, or from the first boss you kill.
- **Boss portraits in the tracker** for bosses nobody in the guild has fought yet, from the looks the Dungeons page reads.
- **Click the dungeon tracker** to open the run in Foxden; right-click a boss on it for its loot. It also says how many bosses are left.
- The run summary shows **XP gained** and **Gold looted**, and lists every boss (it stopped at five).

### Dungeons page
- A new layout: pick a dungeon from the menu at the top (or scroll over it, or use the arrows), then **Map, Bosses, Quests** and **Runs** tabs. Bosses have portraits, a 3D model and their loot as item cards.
- Quests show the right faction. Many were marked "Both factions" by mistake; quests Foxden can't place yet now say "Faction not known yet".
- **Bosses** show their level on a badge over a round portrait, and loot that drops from many bosses is folded under **Show shared loot**.
- **Quest chains:** the picked quest opens to show its whole chain, with the steps you've done ticked. The quest itself says which step you're on, and **Show on map** points to the next step you need.
- **Guild notes on quests,** written on the website's dungeon page, and **Guides online**: a link to the quest's Wowhead Forever page (with player comments) to copy into your browser.
- **Trash tab:** items that drop only from a dungeon's trash mobs (not its bosses), with the mobs that drop them, worked out from the QuestieDB addon's data.
- **Entrance** button on a dungeon: the arrow points to its entrance and the world map opens there (QuestieDB's dungeon list).
- Profession quests show only when you have that profession at that level (the count of hidden ones is shown); quests your race can't take are greyed out with the reason.
- **Loot filter** (boss loot and trash): only loot your class can use, hide recipes, only gear with the stats you pick.
- Faction filter is now the two crests: click the other one to list its quests too.

### Quests (Foxden can replace a quest helper now)
- **Quest givers on the map:** a ! on every quest giver with a quest you can pick up (your faction, race, class and level, with whatever it needs first done), and a ? where finished quests are turned in. Hover for the quests, their objectives and the XP each gives you at your level; hold Shift for gold and item rewards. Quest givers standing close together share one mark with a count. From QuestieDB's data for WoW Forever: read from the QuestieDB addon when you have it (it comes with Questie, and has Forever's new zones like Riverglades), else Foxden's own copy.
- **Minimap marks:** the same marks on your minimap for the ones nearby, turning with it if your minimap rotates.
- **Quest tracker:** your quests at the side of the screen, grouped by zone (the zone you're in first; click a zone to fold it), with levels in difficulty colours, "Dungeon" and "Group" tags, live objective progress and "Ready to turn in" with whom. Click a quest to open its details beside the tracker (works in combat): text, live objectives, turn-in, chain, guild note, and the rewards as item icons to hover, shift-click to link or ctrl-click to try on, with Map, Arrow, Link, Share (when you're in a group and the quest can be shared) and Abandon (asks first). Hover a quest for its full card: description, objectives, who to turn it in to and where, XP, gold, items and reputation, its quest chain and the guild's note. Quests with an item to use get a button beside them (click to use it, with its cooldown). Click a quest to see it on the map, right-click for a map pin to its turn-in, shift-click to link it. Drag the title to move it. The game's own quest tracker (and EllesmereUI's) is hidden while Foxden's is on.
- **Quests page** (new place in the sidebar, or the gear on the tracker): what the quest helper knows and shows right now, and all its settings: map and minimap marks, mark size, how far above your level, grey quests, and the tracker's text size, width, background and lock. `/fox quests` prints the same check in chat.

### Getting there
- **Waypoint arrow:** an arrow on screen that points to the NPC you're heading for, with how far it is; it turns green as you head straight for it and says "Arrived" when you're there. Click it to target the NPC, right-click to stop, drag to move it. Set it by right-clicking a quest in the tracker or a mark on the map, "Arrow to turn-in" in the quest details, or "Show on map" on the Dungeons page.
- **Item sources in tooltips:** any item tooltip (bags, loot rolls, chat links) says which boss or quest it comes from. Key binding (Key Bindings > Foxden): open the hovered item on the Dungeons page.
- The Dungeons page fills in Forever's new dungeon quests (where they start and end, levels, objectives, quest chains) from the QuestieDB addon when you have it.

### World map
- **Dungeon quests on the map:** a mark on every quest giver with a dungeon quest you can pick up, including the earlier steps of its chain (The Defias Brotherhood before Red Silk Bandanas, and so on). Hover for the quests and where they lead; click to open the quest in Foxden. Quests far above or below your level are left out. Turn it off in Settings (**Dungeon quests on the world map**).
- **Learns Forever's new quest chains as you play:** no database has the chains for Forever's new dungeons yet, so Foxden notes which quest an NPC gives you right after you turn one in, and the guild's website joins them into chains for everyone.

### Fixes
- Recipe materials were missing from tooltips and the Recipes page.
- You showed up in your own "Guildmates near your level" (level-up card and Home), and could get rare alerts for rares you found yourself.
- Guildmates were sometimes counted twice (Forever adds a second name to players in guild messages), which showed you twice on the guild map.
- Guildmates in zones you've never visited now show on the guild map.
- Dropdown menus no longer get covered by other parts of the window.
- **Settings** opens inside the Foxden window (the game's own settings window could open hidden behind it). It's still under the game's Settings > AddOns too.

## 2.2.1

- **Fixed:** errors on login about unknown events ("TRADE_SKILL_UPDATE", "LEARNED_SPELL_IN_TAB"). They also stopped recipe scanning and trainer tracking from working. Foxden now skips any event the game doesn't have.
- **No more "sync":** notes, craft requests, "Ask the guild" and "I want to run this" send the moment you click (your screen reloads for a second so the companion app can post them). Everything else goes out by itself when you log out. Turn off **Send right away** in Settings to wait for logout instead.
- The **Sync** button is now **Send now**, and `/fox send` does the same.

## 2.2.0

A big one: a simpler window, every Forever dungeon with its bosses, quests and loot, a loot
wishlist, a rare tracker, crafting tools and notes.

### A simpler window
- Four places in the sidebar (**Home, Dungeons, Crafting, Guild**) with tabs, instead of eleven pages. It remembers the tab you used last.
- A **search box** in the header finds any dungeon, boss, quest, loot item or recipe and jumps to it.
- **Home** is about you: dungeons for your level with the quests you can still pick up, what's ready at your trainer, your recent runs, and guildmates online near your level.
- Item and spell **tooltips everywhere** (hover any item; shift-click to link it), and a **minimap button** (click to open, right-click for Settings, shift-click for a note).

### Dungeons
- **Every Forever dungeon and raid**, including the nine new ones, with its full boss list (lists from ForeverDungeonRoutes, MIT). Scarlet Monastery, Blackrock Spire and Dire Maul show as one dungeon with their wings.
- **Bosses:** the boss's model, its loot as real items, the guild's tips and record.
- **Quests:** every dungeon quest with level, Alliance / Horde / both, objectives, rewards, and **map pins** for where to get it and turn it in. Quests show **Done** or **In your quest log**, and Foxden tells you what you haven't picked up when you walk in.
- **Runs:** your guild's runs of that dungeon. Click **I want to run this** to tell guildmates; their wishes show on Home.
- **Dungeon tracker** while you're inside: time, XP gained, gold looted, the bosses as portraits ticked off as you kill them, and how far ahead or behind the guild's best run you are.
- What each boss drops in your runs is recorded, so the journal fills in as the guild plays.

### Loot wishlist
- Star any boss drop as **main spec, off spec or transmog**. Foxden reminds you at the boss, tells you when it drops, and takes it off the list when you get it. Guildmates see who wants what. Home has a Wishlist tab.

### Rare tracker
- Every rare and rare elite with its spawn points (Guild → Rares). Foxden notes when you see or kill one, tells guildmates with a note on screen, and shows when it may be up again from respawn times the guild learns or enters.

### Crafting
- **Recipes:** one list for every recipe with profession, category (pick several), show and sort dropdowns. Each recipe shows where it turns yellow and grey, coloured for your own skill. Pick one for each material's auction price and a total, who can make it, and **Request**, **Whisper** or **Ask the guild**.
- **Leveling planner:** the cheapest way to level a profession at today's prices, with a shopping list that leaves out what's in your bags and bank.
- **Crafting is free:** no fees and no cash-on-delivery. You bring the materials, a guildmate makes it.

### Leveling and trainer
- **Trainer:** visit your class trainer once and Foxden keeps its whole list (what's ready, what's coming, the cost). Right-click to skip an ability; **Learn all** at the trainer learns the rest.
- **Level-up card** with your gains, how long the level took and what's new at your trainer; guildmates see a note when you ding. Every level-up is listed on the Leveling page.

### Notes
- `/fox note` opens a small note window to keep beside you: write, add where you are, take a screenshot. Share it in guild chat, send it to Discord with its screenshots (through the companion), or share its spot as a **guild map pin**.

### Guild
- **Roster map:** guildmates who share their location show on a map of the continent, at the last place they were seen.
- Your runs reach the guild website even without the companion app: Foxden hands them to a guildmate who runs it. `/fox copy` gives a run to paste on the website.

### Also
- Foxden is now **GPL-3.0-or-later** (it was MIT), so it can include data from other open projects; see THIRD-PARTY-NOTICES.md.
- Visits to a dungeon with no fight aren't saved. Guild messages are paced to stay under the game's limit. Windows are solid, and the Settings page scrolls.

## 2.1.0

First public release.

- **Dungeon log:** records each run's dungeon, difficulty, time, party, boss kills, wipes and per-player totals from the game's damage meter.
- **Journal:** every dungeon's bosses, abilities and loot from the game's Encounter Journal.
- **Crafters:** see which guildmates can craft what.
- **Roster:** your guild with rank, level, class, online status and zone, plus optional location sharing on the world map.
- **You choose what to share:** nothing is sent until you answer the welcome popup (`/fox welcome` to change it).
- **Update notice:** tells you once per session when a guildmate has a newer version.
- Commands: `/fox`, `/foxden` or `/fd`.
