-- Dungeons that are several dungeons in one: which bosses belong to which wing, the
-- wing's last boss, and words the game may show inside it (zone, sub-zone, group finder
-- name) to tell which wing you walked into. Inside, Forever reports every wing as the
-- same dungeon, so the first boss you kill settles it too (Modules/Wings.lua).
-- Hand-written; boss names as in Data/Dungeons.lua.
local _, ns = ...
ns.Wings = {
  [189] = { -- Scarlet Monastery
    { name = "Graveyard", final = "Bloodmage Thalnos", bosses = { "Interrogator Vishas", "Bloodmage Thalnos" },
      match = { "Graveyard", "Chamber of Atonement", "Forlorn Cloister" } },
    { name = "Library", final = "Arcanist Doan", bosses = { "Houndmaster Loksey", "Arcanist Doan" },
      match = { "Library", "Huntsman's Cloister", "Gallery of Treasures", "Athenaeum" } },
    { name = "Armory", final = "Herod", bosses = { "Herod" },
      match = { "Armory", "Hall of Champions", "Training Grounds" } },
    { name = "Cathedral", final = "High Inquisitor Whitemane", bosses = { "High Inquisitor Fairbanks", "High Inquisitor Whitemane" },
      match = { "Cathedral", "Chapel Gardens", "Crusader's Chapel" } },
  },
  [429] = { -- Dire Maul
    { name = "East", final = "Alzzin the Wildshaper", bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" },
      match = { "Dire Maul - East", "Dire Maul East", "Warpwood Quarter", "The Hidden Reach", "The Shrine of Eldretharr" } },
    { name = "West", final = "Prince Tortheldrin", bosses = { "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Lord Hel'nurath", "Tsu'zee", "Prince Tortheldrin" },
      match = { "Dire Maul - West", "Dire Maul West", "Capital Gardens", "Court of the Highborne", "Prison of Immol'thar" } },
    { name = "North", final = "King Gordok", bosses = { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok" },
      match = { "Dire Maul - North", "Dire Maul North", "Gordok Commons", "Halls of Destruction" } },
  },
  [229] = { -- Blackrock Spire
    { name = "Lower Blackrock Spire", final = "Overlord Wyrmthalak",
      bosses = { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak" },
      match = { "Lower Blackrock", "Hordemar City", "Skitterweb Tunnels", "Mok'Doom", "Spire Throne" } },
    { name = "Upper Blackrock Spire", final = "General Drakkisath",
      bosses = { "Pyroguard Emberseer", "Warchief Rend Blackhand", "The Beast", "Lord Valthalak", "General Drakkisath" },
      match = { "Upper Blackrock", "Hall of Blackhand", "Dragonspire Hall", "Hall of Binding", "The Rookery", "Blackrock Stadium" } },
  },
  [329] = { -- Stratholme
    { name = "Main Gate", final = "Balnazzar",
      bosses = { "Skul", "Hearthsinger Forresten", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Crimson Hammersmith", "Postmaster Malown", "Archivist Galford", "The Unforgiven", "Balnazzar" },
      match = { "Main Gate", "King's Square", "Festival Lane", "Market Row", "Crusaders' Square", "Scarlet Bastion", "Hall of Lights" } },
    { name = "Service Entrance", final = "Baron Rivendare",
      bosses = { "Magistrate Barthilas", "Stonespine", "Baroness Anastari", "Nerub'enkan", "Maleki the Pallid", "Ramstein the Gorger", "Black Guard Swordsmith", "Baron Rivendare" },
      match = { "Service Entrance", "Elders' Square", "Slaughter Square", "The Gauntlet", "The Slaughter House", "Ziggurat" } },
  },
}
