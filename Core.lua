-- Pints Ledger: account-wide character ledger (data collection).
-- Every character you log into records its own snapshot; the window shows all of them.
local ADDON, NS = ...
local L = {}
_G.PintsLedger = L
NS.L = L

local realm, name, me, rec
local ev = CreateFrame("Frame")

---------------------------------------------------------------- helpers
local function now() return time() end
L.PROF_ICON = {
  Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
  Herbalism = "Interface\\Icons\\Trade_Herbalism", Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
  Mining = "Interface\\Icons\\Trade_Mining", Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  Tailoring = "Interface\\Icons\\Trade_Tailoring", Cooking = "Interface\\Icons\\INV_Misc_Food_15",
  ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", Fishing = "Interface\\Icons\\Trade_Fishing",
}
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }

---------------------------------------------------------------- snapshots
local function ScanBasics()
  local _, classFile = UnitClass("player")
  rec.class, rec.classFile = UnitClass("player"), classFile
  local raceName, raceFile, raceID = UnitRace("player")
  rec.race, rec.raceFile, rec.raceID = raceName, raceFile, raceID
  rec.sex = UnitSex("player")
  rec.faction = UnitFactionGroup("player")
  rec.level = UnitLevel("player")
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  -- the client reports 0 XP-to-level while the world is loading/unloading; keep the last good values then
  if (xpMax or 0) > 0 or (rec.level or 0) >= 60 then
    rec.xp, rec.xpMax = xp, xpMax
    rec.rested = GetXPExhaustion() or 0
    rec.resting = IsResting() and true or false
  end
  rec.money = GetMoney()
  rec.guild = (IsInGuild() and GetGuildInfo("player")) or nil
  rec.bind = GetBindLocation()
  rec.zone = GetRealZoneText()
  rec.lastOnline = now()
  rec.hardcore = C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() or nil
end

local function ScanTalents()
  if not GetNumTalentTabs then return end
  local best, bestPts = nil, 0
  for i = 1, (GetNumTalentTabs() or 0) do
    local a, b, c, d, e = GetTalentTabInfo(i)
    local tabName, pts
    if type(a) == "number" then tabName, pts = b, e else tabName, pts = a, c end   -- old vs new return order
    if type(pts) == "number" and pts > bestPts then best, bestPts, rec.specIndex = tabName, pts, i end
  end
  if not best then rec.specIndex = 0 end
  rec.spec = best
end

local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function ScanGear()
  local sum, n = 0, 0
  for _, s in ipairs(SLOTS) do
    local link = GetInventoryItemLink("player", s)
    if link then
      local ilvl = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or select(4, GetItemInfo(link))
      if ilvl then sum, n = sum + ilvl, n + 1 end
    end
  end
  rec.ilvl = n > 0 and (sum / n) or 0
  -- the gear itself, for the Characters tab
  rec.gear = {}
  for s = 1, 19 do rec.gear[s] = GetInventoryItemLink("player", s) end
  -- character sheet stats
  local st = {}
  for i = 1, 5 do local _, eff = UnitStat("player", i); st[i] = eff end
  local _, armor = UnitArmor("player")
  local apBase, apPos, apNeg = UnitAttackPower("player")
  local rapBase, rapPos, rapNeg = UnitRangedAttackPower("player")
  local res = {}
  for i = 2, 6 do local _, total = UnitResistance("player", i); res[i] = total end
  rec.stats = { str = st[1], agi = st[2], sta = st[3], int = st[4], spi = st[5], armor = armor,
    health = UnitHealthMax("player"), power = UnitPowerMax("player"), powerType = UnitPowerType("player"),
    ap = (apBase or 0) + (apPos or 0) + (apNeg or 0), rap = (rapBase or 0) + (rapPos or 0) + (rapNeg or 0), res = res,
    crit = GetCritChance and GetCritChance() or nil, dodge = GetDodgeChance and GetDodgeChance() or nil }
  -- GearScore from TacoTip when it's installed (optional)
  if TT_GS and TT_GS.GetScore then
    local ok, gs = pcall(TT_GS.GetScore, TT_GS, "player")
    if ok and gs and gs > 0 then
      rec.gs = gs
      local ok2, r, g, b = pcall(TT_GS.GetQuality, TT_GS, gs)
      if ok2 and r then rec.gsColor = { r, g, b } end
    end
  end
end

local function ScanSkills()
  local profs, sec, all = {}, {}, {}
  for i = 1, (GetNumSkillLines() or 0) do
    local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if skillName then all[#all + 1] = { skillName, isHeader and 1 or 0, rank or 0, maxRank or 0 } end
    if not isHeader and L.PROF_ICON[skillName] then
      local t = { name = skillName, rank = rank, max = maxRank }
      if SECONDARY[skillName] then sec[skillName] = t else profs[#profs + 1] = t end
    end
  end
  rec.profs, rec.secondary, rec.skillList = profs, sec, all
end

-- remember item names so search works without the game's item cache
local function Remember(link)
  if not link then return end
  local id, nm = link:match("item:(%d+)"), link:match("%[(.-)%]")
  if id and nm then PintsLedgerDB.names[tonumber(id)] = nm end
end
L.Remember = Remember

-- counts into `into`; returns size, free and the slot contents { [slot] = { link, count } }
local function CountContainer(bag, into)
  local size = C_Container.GetContainerNumSlots(bag) or 0
  local free = C_Container.GetContainerNumFreeSlots(bag) or 0
  local slots = {}
  for slot = 1, size do
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info and info.itemID then
      into[info.itemID] = (into[info.itemID] or 0) + (info.stackCount or 1)
      slots[slot] = { info.hyperlink, info.stackCount or 1, info.isBound and 1 or nil }
      Remember(info.hyperlink)
    end
  end
  return size, free, slots
end
local function BagItemLink(bag)
  if bag == 0 or bag == (BANK_CONTAINER or -1) then return nil end
  local inv = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag)
  return inv and GetInventoryItemLink("player", inv)
end

local function ScanBags()
  rec.bags, rec.items = {}, rec.items or {}
  local items = {}
  rec.bagSlots = {}
  for bag = 0, 4 do
    local size, free, slots = CountContainer(bag, items)
    rec.bags[bag] = { size, free }
    rec.bagSlots[bag] = { size = size, bag = BagItemLink(bag), slots = slots }
  end
  rec.items.bags = items
end

local function ScanBank()
  rec.bank, rec.items = {}, rec.items or {}
  local items = {}
  local bags = { BANK_CONTAINER or -1 }
  for b = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 6) do bags[#bags + 1] = b end
  rec.bankSlots = {}
  for i, bag in ipairs(bags) do
    local size, free, slots = CountContainer(bag, items)
    rec.bank[i] = { size, free }
    rec.bankSlots[i] = { size = size, bag = BagItemLink(bag), slots = slots }
  end
  rec.items.bank = items
  rec.bankSeen = now()
end

local function ScanMail()
  local n = GetInboxNumItems() or 0
  local items = {}
  for i = 1, n do
    for a = 1, (ATTACHMENTS_MAX_RECEIVE or 12) do
      local link = GetInboxItemLink(i, a)
      if link then
        local id = tonumber(link:match("item:(%d+)"))
        local _, _, _, count = GetInboxItem(i, a)
        if id then items[id] = (items[id] or 0) + (count or 1) end
        Remember(link)
      end
    end
  end
  rec.mail, rec.mailSeen = n, now()
  rec.items = rec.items or {}
  rec.items.mail = items
end

local function ScanAuctions()
  if GetNumAuctionItems then
    rec.auctions = select(1, GetNumAuctionItems("owner")) or 0
    rec.bids = select(1, GetNumAuctionItems("bidder")) or 0
  end
  rec.ahSeen = now()
end

-- Every recipe this character knows, per profession (for the recipe book): { name, link, section }
-- Only saved when the window shows the full list - a search or filter in the profession window would hide some
function L.SaveBook(prof, book)
  if not prof or #book == 0 then return end
  rec.recipes = rec.recipes or {}
  local old = rec.recipes[prof]
  if old and #book < #old.list then
    -- fewer than last time: probably a filter is on; keep the longer list but add anything new
    local have = {}
    for i, e in ipairs(old.list) do have[e[1]] = i end
    for _, e in ipairs(book) do
      if have[e[1]] then old.list[have[e[1]]] = e else old.list[#old.list + 1] = e end   -- newer colours / reagents
    end
    old.seen = now()
    return
  end
  rec.recipes[prof] = { list = book, seen = now() }
end

-- Recipes this character knows that make an item, with reagents (used by Craft Upgrades)
local function ScanTradeSkill()
  local prof = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end
  rec.crafts = rec.crafts or {}
  local list = rec.crafts[prof] or {}
  local book, section = {}, nil
  for i = 1, (GetNumTradeSkills() or 0) do
    local skillName, kind = GetTradeSkillInfo(i)
    if skillName and kind == "header" then section = skillName end
    if skillName and kind ~= "header" then
      local link = GetTradeSkillItemLink(i)
      local item = link and tonumber(link:match("item:(%d+)"))
      local reag = {}
      for r = 1, (GetTradeSkillNumReagents(i) or 0) do
        local rl = GetTradeSkillReagentItemLink(i, r)
        local _, _, count = GetTradeSkillReagentInfo(i, r)
        local rid = rl and tonumber(rl:match("item:(%d+)"))
        if rid then reag[#reag + 1] = { rid, count or 1 } end
      end
      local rlink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      -- book entry: name, link, section, skill-up colour, item it makes, reagents
      book[#book + 1] = { skillName, rlink or link, section, kind, item, reag }
      if item then list[item] = { name = skillName, reagents = reag } end
    end
  end
  rec.crafts[prof] = list
  L.SaveBook(prof, book)
end

-- Reputation as shown in the Reputation tab (collapsed headers keep their last known contents)
local function ScanReps()
  if not GetNumFactions then return end
  local list = {}
  for i = 1, (GetNumFactions() or 0) do
    local fname, _, standing, barMin, barMax, value, _, _, isHeader, isCollapsed, hasRep = GetFactionInfo(i)
    if fname then list[#list + 1] = { fname, isHeader and 1 or 0, standing or 0, barMin or 0, barMax or 0, value or 0, hasRep and 1 or 0 } end
  end
  if #list > 0 then rec.reps = list end
end

-- Guild bank: Classic Era has none, but clients with one (and the API) get scanned when it's opened.
local function ScanGuildBank()
  if not (GetNumGuildBankTabs and GetGuildBankItemLink) or not IsInGuild() then return end
  local guild = GetGuildInfo("player")
  if not guild then return end
  PintsLedgerDB.guilds[realm] = PintsLedgerDB.guilds[realm] or {}
  local g = PintsLedgerDB.guilds[realm][guild] or { tabs = {} }
  for tab = 1, (GetNumGuildBankTabs() or 0) do
    local tname, icon, viewable = GetGuildBankTabInfo(tab)
    if viewable then
      local slots = {}
      for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
          local _, count = GetGuildBankItemInfo(tab, slot)
          slots[slot] = { link, count or 1 }
          Remember(link)
        end
      end
      g.tabs[tab] = { name = tname, icon = icon, slots = slots }
    end
  end
  g.seen = now()
  PintsLedgerDB.guilds[realm][guild] = g
end
L.HasGuildBankAPI = function() return GetNumGuildBankTabs ~= nil end

---------------------------------------------------------------- played time (quietly)
local playedAsked
local function OnTimePlayed(total)
  rec.played = total
  rec.playedAt = now()
end

-- Enchanting uses the separate "craft" window in Classic; only its item-making recipes (wands, rods, oils) matter here
local function ScanCraft()
  if not GetNumCrafts or not GetCraftDisplaySkillLine then return end
  local prof = GetCraftDisplaySkillLine()
  if not prof then return end
  rec.crafts = rec.crafts or {}
  local list = rec.crafts[prof] or {}
  local book, section = {}, nil
  for i = 1, (GetNumCrafts() or 0) do
    local craftName, craftSub, kind = GetCraftInfo(i)
    if craftName and kind == "header" then section = craftName end
    if craftName and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local item = link and tonumber(link:match("item:(%d+)"))
      local reag = {}
      for r = 1, (GetCraftNumReagents(i) or 0) do
        local rl = GetCraftReagentItemLink and GetCraftReagentItemLink(i, r)
        local _, _, count = GetCraftReagentInfo(i, r)
        local rid = rl and tonumber(rl:match("item:(%d+)"))
        if rid then reag[#reag + 1] = { rid, count or 1 } end
      end
      local rlink = GetCraftRecipeLink and GetCraftRecipeLink(i)
      book[#book + 1] = { craftName .. ((craftSub and craftSub ~= "") and (" (" .. craftSub .. ")") or ""), rlink or link, section, kind, item, reag }
      if item then list[item] = { name = craftName, reagents = reag } end
    end
  end
  rec.crafts[prof] = list
  L.SaveBook(prof, book)
end

---------------------------------------------------------------- public API (also used by Craft Upgrades)
-- All characters on this realm: { key = "Realm.Name", rec }
function L.Characters(allRealms)
  local out = {}
  for r, chars in pairs(PintsLedgerDB.chars) do
    if allRealms or r == realm then
      for n, c in pairs(chars) do out[#out + 1] = { realm = r, name = n, rec = c } end
    end
  end
  return out
end

-- How many of an item each character has: returns { {name, bags, bank, mail}, ... }, total
function L.ItemCounts(itemID)
  local out, total = {}, 0
  for _, ch in ipairs(L.Characters()) do
    local it = ch.rec.items or {}
    local b = it.bags and it.bags[itemID] or 0
    local k = it.bank and it.bank[itemID] or 0
    local m = it.mail and it.mail[itemID] or 0
    if b + k + m > 0 then
      out[#out + 1] = { ch.name, b, k, m }
      total = total + b + k + m
    end
  end
  return out, total
end

-- Every craftable item known on this realm: items[], crafters[item] = {"Name (Prof)"}, reagents[item]
function L.Craftables()
  local items, crafters, reagents = {}, {}, {}
  for _, ch in ipairs(L.Characters()) do
    for prof, list in pairs(ch.rec.crafts or {}) do
      for item, info in pairs(list) do
        if not crafters[item] then crafters[item] = {}; items[#items + 1] = item end
        table.insert(crafters[item], ch.name .. " (" .. prof .. ")")
        reagents[item] = reagents[item] or info.reagents
      end
    end
  end
  return items, crafters, reagents
end

-- Profession ranks on this realm: ranks[profName] = { {charName, rank}, ... }
function L.ProfessionRanks()
  local out = {}
  for _, ch in ipairs(L.Characters()) do
    local function add(p) out[p.name] = out[p.name] or {}; table.insert(out[p.name], { ch.name, p.rank }) end
    for _, p in ipairs(ch.rec.profs or {}) do add(p) end
    for _, p in pairs(ch.rec.secondary or {}) do add(p) end
  end
  return out
end

-- Rested XP right now as a % of a level, counting time since the character logged out
function L.RestPercent(c)
  if not c.xpMax or c.xpMax <= 0 then return 0 end
  local rested = c.rested or 0
  if c.lastOnline and not (c.name == name and c.realm == realm) then
    local hours = (now() - c.lastOnline) / 3600
    local perHour = c.xpMax * 0.05 / 8 * (c.resting and 1 or 0.25)   -- 5% of a level per 8h at an inn
    rested = rested + hours * perHour
  end
  rested = math.min(rested, c.xpMax * 1.5)
  if c.level and c.level >= 60 then return 0 end
  return rested / c.xpMax * 100
end

-- Search every character's bags, bank and mail, plus recorded guild banks, by item name.
-- returns { { id, name, link?, where = "Lonehealer - Bags", count }, ... }
function L.Search(text)
  text = (text or ""):lower()
  if #text < 2 then return {} end
  local names = PintsLedgerDB.names
  local out = {}
  local function nameOf(id)
    local n = names[id]
    if not n then
      local gi = GetItemInfo(id)
      if gi then names[id] = gi; n = gi elseif C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    end
    return n
  end
  for _, ch in ipairs(L.Characters(true)) do
    local it = ch.rec.items or {}
    for _, place in ipairs({ { "bags", "Bags" }, { "bank", "Bank" }, { "mail", "Mail" } }) do
      for id, count in pairs(it[place[1]] or {}) do
        local n = nameOf(id)
        if n and n:lower():find(text, 1, true) then
          out[#out + 1] = { id = id, name = n, who = ch.name, realm = ch.realm, where = place[2], count = count, class = ch.rec.classFile }
        end
      end
    end
  end
  for r, guilds in pairs(PintsLedgerDB.guilds or {}) do
    for gname, g in pairs(guilds) do
      local totals = {}
      for _, tab in pairs(g.tabs or {}) do
        for _, sl in pairs(tab.slots or {}) do
          local id = tonumber(sl[1]:match("item:(%d+)"))
          if id then totals[id] = (totals[id] or 0) + sl[2] end
        end
      end
      for id, count in pairs(totals) do
        local n = nameOf(id)
        if n and n:lower():find(text, 1, true) then
          out[#out + 1] = { id = id, name = n, who = "<" .. gname .. ">", guild = gname, realm = r, where = "Guild Bank", count = count }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.who < b.who end)
  return out
end

function L.Me() return realm, name end
function L.Record(r, n) return PintsLedgerDB.chars[r] and PintsLedgerDB.chars[r][n] end
function L.Forget(r, n) if PintsLedgerDB.chars[r] then PintsLedgerDB.chars[r][n] = nil end end

---------------------------------------------------------------- events
local pending = {}
local function Soon(key, fn, delay)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay or 0.5, function() pending[key] = nil; pcall(fn); if L.OnChanged then L.OnChanged() end end)
end

ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    PintsLedgerDB = PintsLedgerDB or {}
    PintsLedgerDB.chars = PintsLedgerDB.chars or {}
    PintsLedgerDB.ui = PintsLedgerDB.ui or {}
    PintsLedgerDB.minimap = PintsLedgerDB.minimap or { hide = false }
    PintsLedgerDB.names = PintsLedgerDB.names or {}
    PintsLedgerDB.guilds = PintsLedgerDB.guilds or {}
  elseif event == "PLAYER_LOGIN" then
    realm, name = GetRealmName(), UnitName("player")
    me = realm .. "." .. name
    PintsLedgerDB.chars[realm] = PintsLedgerDB.chars[realm] or {}
    PintsLedgerDB.chars[realm][name] = PintsLedgerDB.chars[realm][name] or {}
    rec = PintsLedgerDB.chars[realm][name]
    rec.name, rec.realm = name, realm
    pcall(ScanBasics); pcall(ScanTalents); pcall(ScanSkills); pcall(ScanBags); pcall(ScanReps)
    C_Timer.After(3, function() pcall(ScanGear); pcall(ScanBasics) end)
    -- Altoholic/DataStore already asks for /played at login; only ask ourselves if nobody does
    C_Timer.After(12, function() if not rec.playedAt or now() - rec.playedAt > 60 then playedAsked = true; RequestTimePlayed() end end)
    for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
      "PLAYER_GUILD_UPDATE", "HEARTHSTONE_BOUND", "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
      "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
      "AUCTION_OWNED_LIST_UPDATE", "AUCTION_BIDDER_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
      "TIME_PLAYED_MSG", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA", "UPDATE_FACTION", "UNIT_INVENTORY_CHANGED" }) do
      ev:RegisterEvent(e)
    end
    if GetNumGuildBankTabs then
      for _, e in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do pcall(ev.RegisterEvent, ev, e) end
    end

  elseif not rec then
    return
  elseif event == "TIME_PLAYED_MSG" then
    OnTimePlayed(arg1)
  elseif event == "PLAYER_LOGOUT" then
    -- don't rescan here: at logout the client already reports 0 gold, 0 XP and "not resting",
    -- which used to overwrite the good values. Everything is kept current while playing instead.
    rec.lastOnline = now()
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 ~= ((Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker) or 10) then
    return
  elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKBAGSLOTS_CHANGED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    if event ~= "GUILDBANKBAGSLOTS_CHANGED" and QueryGuildBankTab then
      for t = 1, (GetNumGuildBankTabs() or 0) do pcall(QueryGuildBankTab, t) end
    end
    Soon("gbank", ScanGuildBank, 1)
  elseif event == "UPDATE_FACTION" then
    Soon("reps", ScanReps, 1)
  elseif event == "UNIT_INVENTORY_CHANGED" then
    if arg1 == "player" then Soon("gear", ScanGear, 1.5) end
  elseif event == "SKILL_LINES_CHANGED" then
    Soon("skills", ScanSkills)
  elseif event == "CHARACTER_POINTS_CHANGED" then
    Soon("talents", ScanTalents)
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    Soon("gear", ScanGear, 1.5)
  elseif event == "BAG_UPDATE_DELAYED" then
    Soon("bags", ScanBags)
    if L.bankOpen then Soon("bank", ScanBank) end
  elseif event == "BANKFRAME_OPENED" then
    L.bankOpen = true
    Soon("bank", ScanBank)
  elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
    Soon("bank", ScanBank)
  elseif event == "MAIL_INBOX_UPDATE" then
    Soon("mail", ScanMail)
  elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_OWNED_LIST_UPDATE" or event == "AUCTION_BIDDER_LIST_UPDATE" then
    Soon("ah", ScanAuctions, 1)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
    Soon("trade", ScanTradeSkill, 0.5)
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    Soon("craft", ScanCraft, 0.5)
  else
    Soon("basics", ScanBasics)
    if event == "PLAYER_LEVEL_UP" then Soon("gear", ScanGear, 2) end
  end
end)

-- leaving the bank
local bf = CreateFrame("Frame")
bf:RegisterEvent("BANKFRAME_CLOSED")
bf:SetScript("OnEvent", function() L.bankOpen = false end)

-- keep our own /played request out of chat
if ChatFrame_DisplayTimePlayed then
  local orig = ChatFrame_DisplayTimePlayed
  ChatFrame_DisplayTimePlayed = function(...)
    if playedAsked then playedAsked = nil; return end
    return orig(...)
  end
end
