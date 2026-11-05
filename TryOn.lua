-- Pints Ledger: try-on. A turnable, zoomable model, plus a gear picker for any slot that shows the stats you'd have
-- after the swap. Candidates: your bags/bank, alts' bags/bank, what alts can craft, dungeon and raid drops, world drops,
-- quest rewards and recipes nobody has learned yet (static data in GearData.lua).
local ADDON, NS = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemStats = GetItemStats or (C_Item and C_Item.GetItemStats)

local L = NS.L
local T = {}
NS.Try = T

local trials = {}                 -- ["Realm.Name"] = { [slot] = link | false (slot emptied) }
local function Key(c) return (c.realm or "") .. "." .. (c.name or "") end

---------------------------------------------------------------- slot / class rules
local INV = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
  [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER",
  [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK",
  [17] = "INVTYPE_2HWEAPON", [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND",
  [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC" }
local SLOTS_FOR = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
  INVTYPE_TABARD = { 19 } }
-- class*100+subclass -> skill needed
local SKILL = { [200] = "Axes", [201] = "Two-Handed Axes", [202] = "Bows", [203] = "Guns", [204] = "Maces", [205] = "Two-Handed Maces",
  [206] = "Polearms", [207] = "Swords", [208] = "Two-Handed Swords", [210] = "Staves", [213] = "Fist Weapons", [215] = "Daggers",
  [216] = "Thrown", [218] = "Crossbows", [402] = "Leather", [403] = "Mail", [404] = "Plate Mail", [406] = "Shield" }
local RELIC = { [407] = "PALADIN", [408] = "DRUID", [409] = "SHAMAN" }
local WAND_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local LATE_ARMOR = { [403] = { HUNTER = true, SHAMAN = true }, [404] = { WARRIOR = true, PALADIN = true } }   -- learned at 40

local function Knows(c, skill)
  for _, s in ipairs(c.skillList or {}) do if s[2] ~= 1 and s[1] == skill then return true end end
end
local function CanTrain(c, skill)
  for _, w in ipairs((NS.CLASS_WEAPONS or {})[c.classFile or ""] or {}) do if w == skill then return true end end
end

-- can character c wear this (class*100+subclass) item in `slot`? returns ok, note
local function Usable(c, csub, equipLoc, slot, maxLevel)
  local slots = SLOTS_FOR[equipLoc or ""]
  local fits = false
  for _, s in ipairs(slots or {}) do if s == slot or (slot == 12 and s == 11) or (slot == 14 and s == 13) then fits = true end end
  if not fits then return false end
  if slot == 17 and equipLoc == "INVTYPE_WEAPON" then
    local cf = c.classFile
    if not (cf == "ROGUE" or ((cf == "WARRIOR" or cf == "HUNTER") and (maxLevel or 0) >= 20)) then return false end
    if cf ~= "ROGUE" and not Knows(c, "Dual Wield") and (c.level or 0) < 20 then return true, "|cffff8040dual wield at 20|r" end
  end
  if RELIC[csub] then return RELIC[csub] == c.classFile end
  if csub == 219 then return WAND_CLASSES[c.classFile or ""] == true end
  if csub == 220 then return false end                              -- fishing poles
  local need = SKILL[csub]
  if not need then return true end
  if Knows(c, need) then return true end
  if csub >= 400 then
    if LATE_ARMOR[csub] and LATE_ARMOR[csub][c.classFile or ""] and (maxLevel or 0) >= 40 then return true, "|cffff8040at level 40|r" end
    return false
  end
  if CanTrain(c, need) then return true, "|cffff8040train " .. need .. "|r" end
  return false
end

---------------------------------------------------------------- trial gear
function T.Link(c, slot)
  local t = trials[Key(c)]
  if t and t[slot] ~= nil then return t[slot] or nil, true end
  return c.gear and c.gear[slot], false
end
function T.Has(c) local t = trials[Key(c)]; return t and next(t) ~= nil end
local function Changed() if NS.RefreshCharacters then NS.RefreshCharacters() end; if T.picker and T.picker:IsShown() then T.Render() end end
function T.Set(c, slot, link)
  local k = Key(c)
  trials[k] = trials[k] or {}
  local t = trials[k]
  t[slot] = link
  local loc = link and select(9, GetItemInfo(link))
  if slot == 16 and loc == "INVTYPE_2HWEAPON" then t[17] = false end                 -- two-hander empties the off hand
  if slot == 17 and link then
    local main = T.Link(c, 16)
    if main and select(9, GetItemInfo(main)) == "INVTYPE_2HWEAPON" then t[16] = false end
  end
  -- drop entries that just restore what's really equipped
  for s, v in pairs(t) do if v and c.gear and c.gear[s] == v then t[s] = nil end end
  Changed()
end
function T.Clear(c, slot)
  local t = trials[Key(c)]
  if not t then return end
  if slot then
    t[slot] = nil
    if slot == 16 and t[17] == false then t[17] = nil end
    if slot == 17 and t[16] == false then t[16] = nil end
  else
    trials[Key(c)] = nil
  end
  Changed()
end

---------------------------------------------------------------- stat preview
local KEYS = { str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
  int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT" }
local function ItemStats(link)
  local t = { str = 0, agi = 0, sta = 0, int = 0, spi = 0, armor = 0, ap = 0, rap = 0, crit = 0, dodge = 0, res = { 0, 0, 0, 0, 0, 0 } }
  if not link then return t end
  local s = GetItemStats(link) or {}
  for k, key in pairs(KEYS) do t[k] = s[key] or 0 end
  t.armor = (s.RESISTANCE0_NAME or 0) + (s.ITEM_MOD_EXTRA_ARMOR_SHORT or 0)
  t.ap = s.ITEM_MOD_ATTACK_POWER_SHORT or 0
  t.rap = s.ITEM_MOD_RANGED_ATTACK_POWER_SHORT or 0
  t.crit = s.ITEM_MOD_CRIT_RATING_SHORT or s.ITEM_MOD_CRIT_MELEE_RATING_SHORT or 0
  t.dodge = s.ITEM_MOD_DODGE_RATING_SHORT or 0
  for i = 2, 6 do t.res[i] = s["RESISTANCE" .. i .. "_NAME"] or 0 end
  return t
end
local AP_STR = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2, ROGUE = 1, HUNTER = 1, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
local AP_AGI = { ROGUE = 1, HUNTER = 1 }
local RAP_AGI = { HUNTER = 2, WARRIOR = 1, ROGUE = 1 }
local AGI_CRIT60 = { ROGUE = 29, HUNTER = 53 }
local AGI_DODGE60 = { ROGUE = 14.5, HUNTER = 26.5 }

-- stats after the trial swaps, or nil when nothing is being tried on. Crit/dodge from agility are estimates.
function T.Preview(c)
  if not T.Has(c) then return nil end
  local s = c.stats or {}
  local d = { str = 0, agi = 0, sta = 0, int = 0, spi = 0, armor = 0, ap = 0, rap = 0, crit = 0, dodge = 0, res = { 0, 0, 0, 0, 0, 0 } }
  local loading = false
  for slot, link in pairs(trials[Key(c)]) do
    local old = c.gear and c.gear[slot]
    if (link and not GetItemInfo(link)) or (old and not GetItemInfo(old)) then loading = true end
    local a, b = ItemStats(link or nil), ItemStats(old)
    for k in pairs(KEYS) do d[k] = d[k] + a[k] - b[k] end
    for _, k in ipairs({ "armor", "ap", "rap", "crit", "dodge" }) do d[k] = d[k] + a[k] - b[k] end
    for i = 2, 6 do d.res[i] = d.res[i] + a.res[i] - b.res[i] end
  end
  local cf, lvl = c.classFile or "", math.max(c.level or 1, 1)
  local scale = 0.25 + 0.75 * math.min(lvl, 60) / 60
  local n = {}
  local function add(k, v) n[k] = s[k] and (s[k] + v) or nil end
  add("str", d.str); add("agi", d.agi); add("sta", d.sta); add("int", d.int); add("spi", d.spi)
  add("armor", d.armor + d.agi * 2)
  add("health", d.sta * 10)
  add("power", (s.powerType == 0 or s.powerType == nil) and d.int * 15 or 0)
  add("ap", d.ap + d.str * (AP_STR[cf] or 1) + d.agi * (AP_AGI[cf] or 0))
  add("rap", d.rap + d.agi * (RAP_AGI[cf] or 1))
  add("crit", d.crit + d.agi / ((AGI_CRIT60[cf] or 20) * scale))
  add("dodge", d.dodge + d.agi / ((AGI_DODGE60[cf] or 20) * scale))
  n.res = {}
  for i = 2, 6 do n.res[i] = (s.res and s.res[i]) and (s.res[i] + d.res[i]) or nil end
  -- average item level
  local sum, cnt = 0, 0
  for _, sl in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
    local link = T.Link(c, sl)
    if link then
      local il = select(4, GetItemInfo(link))
      if il then sum, cnt = sum + il, cnt + 1 else loading = true end
    end
  end
  n.ilvl = cnt > 0 and sum / cnt or 0
  n.loading = loading
  return n
end

---------------------------------------------------------------- model: drag to turn, wheel to zoom, right-drag to move
function T.CreateModel(g, w, h)
  local ok, m = pcall(CreateFrame, "DressUpModel", nil, g)
  if not ok or not m then ok, m = pcall(CreateFrame, "PlayerModel", nil, g) end
  if not ok or not m then return end
  m:SetSize(w, h)
  m:EnableMouse(true); m:EnableMouseWheel(true)
  m.zoom, m.facing, m.px, m.py = 0, 0, 0, 0
  local function Apply()
    if m.SetPortraitZoom then m:SetPortraitZoom(m.zoom) end
    m:SetFacing(m.facing)
    if m.SetPosition then m:SetPosition(0, m.px, m.py) end
  end
  m.Apply = Apply
  m:SetScript("OnMouseWheel", function(self, delta)
    self.zoom = math.max(0, math.min(0.9, self.zoom + delta * 0.1)); Apply()
  end)
  m:SetScript("OnMouseDown", function(self, button)
    local x, y = GetCursorPosition()
    self.drag, self.x0, self.y0, self.f0, self.px0, self.py0 = button, x, y, self.facing, self.px, self.py
    self:SetScript("OnUpdate", function()
      local cx, cy = GetCursorPosition()
      if self.drag == "LeftButton" then
        self.facing = self.f0 + (cx - self.x0) * 0.02
      else
        self.px = self.px0 + (cx - self.x0) / 220; self.py = self.py0 + (cy - self.y0) / 220
      end
      Apply()
    end)
  end)
  m:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil); self.drag = nil end)
  m:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  m:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Drag to turn  -  mouse wheel to zoom  -  right-drag to move", 1, 1, 1)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local r = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); r:SetSize(70, 18); r:SetText("Reset view")
  r:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -2, 2)
  r:SetScript("OnClick", function() m.zoom, m.facing, m.px, m.py = 0, 0, 0, 0; Apply() end)
  m.resetBtn = r
  return m
end

-- dress the model as character c (current character: real look; alts: their race/sex with default face and hair)
local RACE_ID = { HUMAN = 1, ORC = 2, DWARF = 3, NIGHTELF = 4, SCOURGE = 5, UNDEAD = 5, TAUREN = 6, GNOME = 7, TROLL = 8, BLOODELF = 10, DRAENEI = 11 }
local function RaceID(c)
  if c.raceID then return c.raceID end
  local f = (c.raceFile or ""):upper():gsub("%s", "")
  return RACE_ID[f]
end
local function FileID(m) return m.GetModelFileID and m:GetModelFileID() or nil end
local function Diag(t)
  PintsLedgerDB = PintsLedgerDB or {}
  local d = PintsLedgerDB.modelDiag or {}
  PintsLedgerDB.modelDiag = d
  d.build = select(4, GetBuildInfo())
  for k, v in pairs(t) do d[k] = v end
end

function T.ShowModel(m, c)
  if not m then return false end
  local r, n = L.Me()
  local isMe = c.realm == r and c.name == n
  m:Show(); if m.resetBtn then m.resetBtn:Show() end
  m:SetUnit("player")
  if isMe then
    local t = trials[Key(c)]
    if t and m.TryOn then
      for s, link in pairs(t) do
        if link then pcall(m.TryOn, m, link) elseif m.UndressSlot then pcall(m.UndressSlot, m, s) end
      end
    end
    m.Apply()
    return true
  end
  -- an alt: the game's own model for their race and sex (default face and hair - the game keeps no record of their
  -- real look), dressed in their saved gear
  local race, female = RaceID(c), (c.sex == 3)
  local _, myRaceFile = UnitRace("player")
  local sameBody = (RACE_ID[(myRaceFile or ""):upper()] == race) and ((UnitSex("player") == 3) == female)
  local method
  if race and m.SetCustomRace then
    local before = FileID(m)
    local ok = pcall(m.SetCustomRace, m, race, female and 1 or 0)
    local after = FileID(m)
    if ok and (sameBody or not before or not after or before ~= after) then method = "race" end
    Diag({ setCustomRace = true, lastName = c.name, lastOk = ok and true or false, before = before, after = after, method = method or "none" })
  else
    Diag({ setCustomRace = m.SetCustomRace ~= nil, lastName = c.name, method = "unsupported" })
  end
  if not method and sameBody then method = "mine" end       -- same race and sex as you: your body, their gear
  if not method then m:Hide(); if m.resetBtn then m.resetBtn:Hide() end; return false end
  if m.Undress then m:Undress() end
  for s = 1, 19 do local link = T.Link(c, s); if link then pcall(m.TryOn, m, link) end end
  local t = trials[Key(c)]
  if t then for s, link in pairs(t) do if link then pcall(m.TryOn, m, link) elseif m.UndressSlot then pcall(m.UndressSlot, m, s) end end end
  m.Apply()
  return true
end

---------------------------------------------------------------- candidate gathering
local PROF_BY_SKILL = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting" }
local function Str(i) local d = PintsGearData; return d and d.strings[i] or "?" end

local function DescribeStatic(src, fac)
  local out, best = {}, nil
  for part in (src or ""):gmatch("[^;]+") do
    local kind, rest = part:sub(1, 1), part:sub(2)
    local a, b, cc = rest:match("^(%d+):(%d+):?(%d*)$")
    a, b, cc = tonumber(a), tonumber(b), tonumber(cc)
    if kind == "D" or kind == "R" then
      out[#out + 1] = { k = kind == "D" and "dungeon" or "raid", text = ("%s - %s |cff808080(%d%%)|r"):format(Str(a), Str(b), cc or 0) }
    elseif kind == "W" then
      out[#out + 1] = { k = "world", text = ("World drop |cff808080(mobs %d-%d)|r"):format(a or 0, b or 0) }
    elseif kind == "Q" then
      if not cc or cc == 0 or cc == fac then
        out[#out + 1] = { k = "quest", lvl = b, text = ("Quest: %s |cff808080(lvl %d)|r"):format(Str(a), b or 0) }
      end
    end
  end
  return out
end

-- every candidate item for character c in slot; list of { id, link?, src, kind, note }
local function Gather(c, slot, opts)
  local D = PintsGearData and PintsGearData.items or {}
  local lvl = c.level or 1
  local lo, hi = math.max(0, lvl - opts.below), lvl + opts.ahead
  local fac = (c.faction == "Horde") and 1 or 2
  local out, seen = {}, {}
  local function add(id, link, kind, text, note)
    if not id then return end
    local e = seen[id]
    if e then
      if not e.link and link then e.link = link end
      return
    end
    e = { id = id, link = link, kind = kind, src = text, note = note }
    seen[id] = e; out[#out + 1] = e
  end
  -- checks an item by id/link; returns ok, note, reqLevel
  local function check(id, link, lowBound)
    local st = D[id]
    local csub, loc, req, cmask
    if st then
      csub, loc, req, cmask = st[2], INV[st[1]], st[3], st[5]
    else
      local _, _, _, _, rl, _, _, _, el, _, _, cid, scid = GetItemInfo(link or id)
      if not el then return nil end
      csub, loc, req, cmask = (cid or 0) * 100 + (scid or 0), el, rl or 0, 0
    end
    if req > hi or (lowBound and req < lo) then return false end
    if cmask and cmask ~= 0 and bit and bit.band and CLASS_BIT[c.classFile or ""] and bit.band(cmask, CLASS_BIT[c.classFile]) == 0 then return false end
    return Usable(c, csub, loc, slot, hi)
  end
  local pending = 0
  local function try(id, link, kind, text, lowBound)
    local ok, note = check(id, link, lowBound)
    if ok == nil then
      pending = pending + 1
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    elseif ok then
      add(id, link, kind, text, note)
    end
  end
  local idOf = function(link) return link and tonumber(link:match("item:(%d+)")) end
  local myKey = Key(c)
  -- bags & bank of this character, then alts
  for _, ch in ipairs(L.Characters(true)) do
    local isSelf = (Key({ realm = ch.realm, name = ch.name }) == myKey)
    if (isSelf and opts.src.bags) or (not isSelf and opts.src.altbag and ch.realm == c.realm) then
      for _, set in ipairs({ ch.rec.bagSlots or {}, ch.rec.bankSlots or {} }) do
        for bag, info in pairs(set) do
          local inBank = set == ch.rec.bankSlots
          for _, sl in pairs(info.slots or {}) do
            local link = sl[1]
            if link and (isSelf or not sl[3]) then
              local where = isSelf and (inBank and "In your bank" or "In your bags")
                or ("On " .. ch.name .. (inBank and " (bank)" or "") .. (sl[3] == nil and " |cff808080- bind unknown|r" or ""))
              try(idOf(link), link, isSelf and "bags" or "altbag", where, false)
            end
          end
        end
      end
    end
  end
  -- what can be crafted now: by this character (self) or by an alt
  if (opts.src.craftself or opts.src.craftalt) and L.Craftables then
    local items, crafters = L.Craftables()
    for _, id in ipairs(items) do
      local mine, others = {}, {}
      for _, w in ipairs(crafters[id] or {}) do
        if w == c.name or w:sub(1, #c.name + 1) == c.name .. " " then mine[#mine + 1] = w else others[#others + 1] = w end
      end
      local bop = select(14, GetItemInfo(id)) == 1
      if opts.src.craftself and #mine > 0 then
        try(id, nil, "craftself", "You craft it: " .. table.concat(mine, ", "), true)
      elseif opts.src.craftalt and #others > 0 and not bop then
        try(id, nil, "craftalt", "Crafted by " .. table.concat(others, ", "), true)
      end
    end
  end
  -- static: dungeons, raids, world drops, quests
  if opts.src.dungeon or opts.src.raid or opts.src.world or opts.src.quest then
    for id, st in pairs(D) do
      -- most Classic quest rewards have no required level, so those are ranged by the quest's level instead
      local quick = st[3] > 0 and (st[3] > hi or st[3] < lo)
      if st[6] ~= "" and not quick then
        local srcs = DescribeStatic(st[6], fac)
        local pick
        for _, s in ipairs(srcs) do
          local lv = (st[3] > 0) and st[3] or s.lvl or 0
          if lv <= hi and lv >= lo then
            if (s.k == "dungeon" and opts.src.dungeon) or (s.k == "raid" and opts.src.raid) then pick = pick or s
            elseif s.k == "quest" and opts.src.quest then pick = pick or s
            elseif s.k == "world" and opts.src.world then pick = pick or s end
          end
        end
        if pick then try(id, nil, pick.k, pick.text, false) end
      end
    end
  end
  -- recipes nobody on the realm knows yet, that one of your characters has the profession for
  local RD = _G.RecipeSourcesData
  if (opts.src.recipeself or opts.src.recipealt) and RD and RD.recipes and RD.make then
    local profs = {}
    for _, ch in ipairs(L.Characters(true)) do
      if ch.realm == c.realm then
        for _, p in ipairs(ch.rec.profs or {}) do
          profs[p.name] = profs[p.name] or {}
          table.insert(profs[p.name], { ch.name, p.rank or 0, (ch.rec.crafts and ch.rec.crafts[p.name]) or {} })
        end
      end
    end
    for spell, r in pairs(RD.recipes) do
      local mk, pn = RD.make[spell], PROF_BY_SKILL[r[1]]
      local item = mk and mk[1]
      local st = item and D[item]
      if st and pn and profs[pn] and r[4] == 0 and st[3] <= hi and st[3] >= lo then
        local known, selfWho, altWho = false, nil, nil
        for _, who in ipairs(profs[pn]) do
          if who[3][item] then known = true end
          if who[1] == c.name then selfWho = who
          elseif not altWho or who[2] > altWho[2] then altWho = who end
        end
        if st[7] == 1 then altWho = nil end          -- bind on pickup: only useful if you make it yourself
        local okWho, kind
        if opts.src.recipeself and selfWho then okWho, kind = selfWho, "recipeself"
        elseif opts.src.recipealt and altWho then okWho, kind = altWho, "recipealt" end
        if not known and okWho then
          local rank, need = okWho[2], r[2]
          local col = rank >= need and "|cff40ff40" or "|cffffd100"
          try(item, nil, kind, ("Recipe: %s %d - %s%s (%d)|r"):format(pn, need, col, okWho[1], rank), true)
        end
      end
    end
  end
  return out, pending
end

---------------------------------------------------------------- picker window
local P, sdeb, deb
local ROWS, ROW_H = 120, 34
local SRC = { { "bags", "My bags" }, { "altbag", "Alt bag (BoE)" }, { "craftself", "Crafted (self)" }, { "craftalt", "Crafted (alt)" },
              { "recipeself", "Recipe (self)" }, { "recipealt", "Recipe (alt)" }, { "dungeon", "Dungeons" }, { "raid", "Raids" },
              { "world", "World drops" }, { "quest", "Quests" } }
local KIND_COL = { bags = "|cffffffff", altbag = "|cff66ccff", craftself = "|cff40ff40", craftalt = "|cff80ffb0", recipeself = "|cffffd100",
  recipealt = "|cffffe880", dungeon = "|cffff8040", raid = "|cffff4040", world = "|cffc0c0c0", quest = "|cffffff80" }
local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket", [15] = "Back", [16] = "Main Hand",
  [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard" }

local function Opts()
  local ui = PintsLedgerDB.ui
  ui.pick = ui.pick or {}
  local o = ui.pick
  if o.below == nil then o.below = 8 end
  if o.ahead == nil then o.ahead = 3 end
  o.src = o.src or {}
  for _, d in ipairs(SRC) do if o.src[d[1]] == nil then o.src[d[1]] = true end end
  return o
end

local function NumBox(parent, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 18); e:SetAutoFocus(false); e:SetNumeric(true); e:SetMaxLetters(2)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

local function Build()
  P = CreateFrame("Frame", "PintsLedgerGearPicker", UIParent, "BackdropTemplate")
  T.picker = P
  P:SetSize(430, 540); P:SetFrameStrata("DIALOG"); P:SetToplevel(true); P:SetClampedToScreen(true)
  P:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  P:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
  P:EnableMouse(true); P:SetMovable(true); P:RegisterForDrag("LeftButton")
  P:SetScript("OnDragStart", P.StartMoving); P:SetScript("OnDragStop", P.StopMovingOrSizing)
  P.title = P:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); P.title:SetPoint("TOPLEFT", 16, -14)
  local close = CreateFrame("Button", nil, P, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
  -- sources
  P.checks = {}
  for i, d in ipairs(SRC) do
    local cb = CreateFrame("CheckButton", nil, P, "UICheckButtonTemplate"); cb:SetSize(20, 20)
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    cb:SetPoint("TOPLEFT", 12 + col * 102, -38 - row * 20)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); cb.text:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cb.text:SetText((KIND_COL[d[1]] or "") .. d[2] .. "|r")
    cb:SetScript("OnClick", function(self) Opts().src[d[1]] = self:GetChecked() and true or false; T.Render() end)
    P.checks[d[1]] = cb
  end
  -- check / uncheck all
  P.all = CreateFrame("Button", nil, P, "UIPanelButtonTemplate"); P.all:SetSize(120, 20)
  P.all:SetPoint("TOPLEFT", 12 + 2 * 102 + 4, -78)
  P.all:SetScript("OnClick", function()
    local o, every = Opts(), true
    for _, d in ipairs(SRC) do if not o.src[d[1]] then every = false end end
    for _, d in ipairs(SRC) do o.src[d[1]] = not every end
    T.Render()
  end)
  -- level range
  local lt = P:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lt:SetPoint("TOPLEFT", 16, -108); lt:SetText("Required level")
  P.lo = NumBox(P, 26); P.lo:SetPoint("LEFT", lt, "RIGHT", 10, 0)
  local dash = P:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); dash:SetPoint("LEFT", P.lo, "RIGHT", 4, 0); dash:SetText("to")
  P.hi = NumBox(P, 26); P.hi:SetPoint("LEFT", dash, "RIGHT", 8, 0)
  local function SetRange()
    local c = P.c; if not c then return end
    local o, lvl = Opts(), c.level or 1
    local lo, hi = tonumber(P.lo:GetText()), tonumber(P.hi:GetText())
    if lo then o.below = math.max(0, lvl - lo) end
    if hi then o.ahead = math.max(0, math.min(60, hi) - lvl) end
    T.Render()
  end
  P.lo:SetScript("OnEditFocusLost", SetRange); P.hi:SetScript("OnEditFocusLost", SetRange)
  -- name filter
  P.search = CreateFrame("EditBox", nil, P, "InputBoxTemplate"); P.search:SetSize(150, 18); P.search:SetAutoFocus(false)
  P.search:SetPoint("TOPRIGHT", -20, -106)
  P.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  P.search:SetScript("OnTextChanged", function(self)
    self.ph:SetShown(self:GetText() == "" and not self:HasFocus())
    if sdeb then sdeb:Cancel() end
    sdeb = C_Timer.NewTimer(0.25, function() T.Render() end)
  end)
  P.search:SetScript("OnEditFocusGained", function(self) self.ph:Hide() end)
  P.search:SetScript("OnEditFocusLost", function(self) self.ph:SetShown(self:GetText() == "") end)
  P.search.ph = P.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); P.search.ph:SetPoint("LEFT", 2, 0); P.search.ph:SetText("Filter by name...")
  P.status = P:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); P.status:SetPoint("TOPLEFT", 16, -130); P.status:SetWidth(400); P.status:SetJustifyH("LEFT")
  -- list
  local sf = CreateFrame("ScrollFrame", "PintsLedgerGearPickerScroll", P, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -148); sf:SetPoint("BOTTOMRIGHT", -32, 14)
  P.list = CreateFrame("Frame", nil, sf); P.list:SetSize(386, 1); sf:SetScrollChild(P.list)
  P.rows = {}
  P:SetScript("OnHide", function() if sdeb then sdeb:Cancel() end end)
  P:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  P:SetScript("OnEvent", function()
    if not P:IsShown() then return end
    if deb then return end
    deb = true
    C_Timer.After(0.4, function() deb = nil; if P:IsShown() then T.Render(); if NS.RefreshCharacters then NS.RefreshCharacters() end end end)
  end)
  P:Hide()
end

local function Row(i)
  local r = P.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.list)
  r:SetSize(386, ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.0)
  r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.18)
  r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(28, 28); r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 36, -2); r.name:SetWidth(270); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.src = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.src:SetPoint("BOTTOMLEFT", 36, 3); r.src:SetWidth(300); r.src:SetJustifyH("LEFT"); r.src:SetWordWrap(false)
  r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.pct:SetPoint("TOPRIGHT", -4, -3)
  r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.lvl:SetPoint("BOTTOMRIGHT", -4, 3)
  r:SetScript("OnClick", function(self)
    if not P.c then return end
    if self.keep then T.Clear(P.c, P.slot) else
      local link = self.e and (self.e.link or select(2, GetItemInfo(self.e.id)))
      if link then T.Set(P.c, P.slot, link) end
    end
  end)
  r:SetScript("OnEnter", function(self)
    local link = self.keep and (P.c.gear and P.c.gear[P.slot]) or (self.e and (self.e.link or ("item:" .. self.e.id)))
    if not link then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetHyperlink(link)
    if self.e and self.e.src then GameTooltip:AddLine(" "); GameTooltip:AddLine(self.e.src, 1, 1, 1, true) end
    GameTooltip:AddLine(self.keep and "Click: put back what's equipped" or "Click: try it on", 0.4, 1, 0.4)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  P.rows[i] = r
  return r
end

function T.Render()
  if not P or not P:IsShown() or not P.c then return end
  local c, slot, o = P.c, P.slot, Opts()
  local lvl = c.level or 1
  P.title:SetText(("%s  |cffa0a0a0- %s|r"):format(SLOT_NAME[slot] or "?", c.name or ""))
  local every = true
  for k, cb in pairs(P.checks) do cb:SetChecked(o.src[k] and true or false); if not o.src[k] then every = false end end
  P.all:SetText(every and "Uncheck all" or "Check all")
  if not P.lo:HasFocus() then P.lo:SetText(tostring(math.max(0, lvl - o.below))) end
  if not P.hi:HasFocus() then P.hi:SetText(tostring(math.min(60, lvl + o.ahead))) end
  local list, pending = Gather(c, slot, o)
  local filter = (P.search:GetText() or ""):lower()
  local S = _G.CraftUpgradesScore
  local ctx = S and { role = S.RoleFor and S.RoleFor(c), class = c.classFile, gear = function(s) return c.gear and c.gear[s] end }
  local shown = {}
  for _, e in ipairs(list) do
    local name, link, q, _, req, _, _, _, _, icon = GetItemInfo(e.link or e.id)
    if name then
      if filter == "" or name:lower():find(filter, 1, true) then
        e.name, e.link, e.q, e.req, e.icon = name, e.link or link, q, req or 0, icon
        e.pct, e.empty = nil, nil
        if ctx and S.UpgradeVs then
          local ok, pct, empty = pcall(S.UpgradeVs, e.link, ctx)
          if ok then e.pct, e.empty = pct, empty end
        end
        shown[#shown + 1] = e
      end
    else
      pending = pending + 1
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.id) end
    end
  end
  table.sort(shown, function(a, b)
    local pa, pb = a.empty and 1e9 or (a.pct or -1e9), b.empty and 1e9 or (b.pct or -1e9)
    if pa ~= pb then return pa > pb end
    if a.req ~= b.req then return a.req > b.req end
    return a.name < b.name
  end)
  local current = T.Link(c, slot)
  -- first row: keep / put back what's equipped
  local i = 1
  local r = Row(1)
  r.keep, r.e = true, nil
  local eq = c.gear and c.gear[slot]
  local eqName, eqQ, eqIcon
  if eq then local _; eqName, _, eqQ, _, _, _, _, _, _, eqIcon = GetItemInfo(eq) end
  r.icon:SetTexture(eqIcon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  r.name:SetText(eq and ((ITEM_QUALITY_COLORS[eqQ or 1] and ITEM_QUALITY_COLORS[eqQ or 1].hex or "|cffffffff") .. (eqName or "?") .. "|r") or "|cff808080Nothing equipped|r")
  r.src:SetText("|cffa0a0a0Currently equipped - click to put it back|r")
  r.pct:SetText(""); r.lvl:SetText("")
  r.sel:SetShown(current == eq)
  r:Show()
  local n = math.min(#shown, ROWS - 1)
  for k = 1, n do
    local e = shown[k]
    i = i + 1
    r = Row(i)
    r.keep, r.e = false, e
    r.icon:SetTexture(e.icon)
    local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.q or 1]
    r.name:SetText(((col and col.hex) or "|cffffffff") .. e.name .. "|r" .. (e.note and ("  " .. e.note) or ""))
    r.src:SetText((KIND_COL[e.kind] or "") .. (e.src or "") .. "|r")
    if e.empty then r.pct:SetText("|cff40ff40new slot|r")
    elseif e.pct then r.pct:SetText((e.pct >= 0.5 and "|cff40ff40+" or (e.pct <= -0.5 and "|cffff4040" or "|cffa0a0a0")) .. math.floor(e.pct + 0.5) .. "%|r")
    else r.pct:SetText("") end
    r.lvl:SetText(e.req > lvl and ("|cff66ccfflvl " .. e.req .. "|r") or ("|cffa0a0a0lvl " .. e.req .. "|r"))
    r.sel:SetShown(current ~= nil and e.link == current)
    r:Show()
  end
  for k = i + 1, #P.rows do P.rows[k]:Hide() end
  P.list:SetHeight(math.max(1, i * ROW_H))
  local more = #shown > n and ("  (best %d shown)"):format(n) or ""
  P.status:SetText(("%d items%s%s"):format(#shown, more, pending > 0 and ("  |cffffd100- loading %d more...|r"):format(pending) or "")
    .. (S and "" or "  |cffff8040(enable Craft Upgrades for upgrade %)|r"))
end

function T.OpenPicker(owner, c, slot)
  if not c or not slot then return end
  if not P then Build() end
  if P:IsShown() and P.c == c and P.slot == slot then P:Hide(); return end
  P.c, P.slot = c, slot
  P:ClearAllPoints()
  local main = _G.PintsLedgerFrame
  local right = main and main:GetRight()
  if right and right + 440 < UIParent:GetRight() then P:SetPoint("TOPLEFT", main, "TOPRIGHT", -6, -40)
  elseif main and main:GetLeft() and main:GetLeft() > 440 then P:SetPoint("TOPRIGHT", main, "TOPLEFT", 6, -40)
  else P:SetPoint("TOPRIGHT", main or UIParent, "TOPRIGHT", -14, -96) end
  P:Show()
  T.Render()
end
function T.HidePicker() if P then P:Hide() end end
function T.PickerFor() return P and P:IsShown() and P.c end
