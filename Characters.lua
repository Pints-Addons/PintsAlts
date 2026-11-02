-- Pints Ledger: Characters tab - pick an alt, see its gear (paper-doll layout), reputation and skills.
local ADDON, NS = ...
local L = NS.L
local floor = math.floor

local page, list, sel, sub = nil, {}, nil, "gear"
local listButtons, slotButtons, repRows, skillRows = {}, {}, {}, {}
local panes = {}

---------------------------------------------------------------- weapon skills
-- What each class may learn in Classic (wands come with Shoot, so they're not trained).
local CLASS_WEAPONS = {
  WARRIOR = { "Daggers", "Fist Weapons", "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces", "Swords", "Two-Handed Swords", "Polearms", "Staves", "Bows", "Crossbows", "Guns", "Thrown" },
  PALADIN = { "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces", "Swords", "Two-Handed Swords", "Polearms" },
  HUNTER  = { "Daggers", "Fist Weapons", "Axes", "Two-Handed Axes", "Swords", "Two-Handed Swords", "Polearms", "Staves", "Bows", "Crossbows", "Guns", "Thrown" },
  ROGUE   = { "Daggers", "Fist Weapons", "Maces", "Swords", "Bows", "Crossbows", "Guns", "Thrown" },
  PRIEST  = { "Daggers", "Maces", "Staves" },
  SHAMAN  = { "Daggers", "Fist Weapons", "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces", "Staves" },
  MAGE    = { "Daggers", "Swords", "Staves" },
  WARLOCK = { "Daggers", "Swords", "Staves" },
  DRUID   = { "Daggers", "Fist Weapons", "Maces", "Two-Handed Maces", "Staves" },
}
NS.CLASS_WEAPONS = CLASS_WEAPONS
-- Capital weapon masters: [faction][skill] = { "City (Trainer)", ... }
local WEAPON_TRAINERS = {
  Alliance = {
    ["Swords"] = { "Stormwind (Woo Ping)" }, ["Two-Handed Swords"] = { "Stormwind (Woo Ping)" },
    ["Polearms"] = { "Stormwind (Woo Ping)" }, ["Staves"] = { "Stormwind (Woo Ping)", "Darnassus (Ilyenia Moonfire)" },
    ["Crossbows"] = { "Stormwind (Woo Ping)", "Ironforge (Bixi Wobblebonk)" },
    ["Daggers"] = { "Ironforge (Bixi Wobblebonk)", "Darnassus (Ilyenia Moonfire)" },
    ["Thrown"] = { "Ironforge (Bixi Wobblebonk)", "Darnassus (Ilyenia Moonfire)" },
    ["Axes"] = { "Ironforge (Buliwyf Stonehand)" }, ["Two-Handed Axes"] = { "Ironforge (Buliwyf Stonehand)" },
    ["Maces"] = { "Ironforge (Buliwyf Stonehand)" }, ["Two-Handed Maces"] = { "Ironforge (Buliwyf Stonehand)" },
    ["Guns"] = { "Ironforge (Buliwyf Stonehand)" },
    ["Fist Weapons"] = { "Ironforge (Buliwyf Stonehand)", "Darnassus (Ilyenia Moonfire)" },
    ["Bows"] = { "Darnassus (Ilyenia Moonfire)" },
  },
  Horde = {
    ["Axes"] = { "Orgrimmar (Hanashi / Sayoc)" }, ["Two-Handed Axes"] = { "Orgrimmar (Hanashi / Sayoc)" },
    ["Bows"] = { "Orgrimmar (Hanashi / Sayoc)" }, ["Thrown"] = { "Orgrimmar (Hanashi / Sayoc)" },
    ["Daggers"] = { "Orgrimmar (Sayoc)", "Undercity (Archibald)" }, ["Fist Weapons"] = { "Orgrimmar (Sayoc)" },
    ["Staves"] = { "Orgrimmar (Hanashi)", "Thunder Bluff (Ansekhwa)" },
    ["Maces"] = { "Thunder Bluff (Ansekhwa)" }, ["Two-Handed Maces"] = { "Thunder Bluff (Ansekhwa)" },
    ["Guns"] = { "Thunder Bluff (Ansekhwa)" },
    ["Swords"] = { "Undercity (Archibald)" }, ["Two-Handed Swords"] = { "Undercity (Archibald)" },
    ["Polearms"] = { "Undercity (Archibald)" }, ["Crossbows"] = { "Undercity (Archibald)" },
  },
}
local WEAPON_COST = 1000   -- 10 silver per weapon skill (before reputation discounts)
local WEAPON_COST_BY = { Polearms = 10000 }   -- polearms are 1 gold

---------------------------------------------------------------- helpers
local function Money(c) return NS.Money and NS.Money(c) or tostring(c) end
local function Header(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
  return fs
end
local function Bar(parent, w, h)
  local b = CreateFrame("StatusBar", nil, parent)
  b:SetSize(w, h)
  b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0.5)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("CENTER")
  return b
end
local function Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -26, 4)
  local c = CreateFrame("Frame", nil, sf); c:SetSize(700, 1)
  sf:SetScrollChild(c)
  return c
end

---------------------------------------------------------------- gear (paper doll)
-- slot, empty-slot art; left column, right column, then weapons along the bottom (like the default UI)
local LEFT = { { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Chest" }, { 5, "Chest" }, { 4, "Shirt" }, { 19, "Tabard" }, { 9, "Wrists" } }
local RIGHT = { { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Finger" }, { 12, "Finger" }, { 13, "Trinket" }, { 14, "Trinket" } }
local BOTTOM = { { 16, "MainHand" }, { 17, "SecondaryHand" }, { 18, "Ranged" } }
LEFT[4][2] = "Chest"   -- back uses the chest art in Classic's slot set
local EMPTY = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Chest", [5] = "Chest", [4] = "Shirt", [19] = "Tabard", [9] = "Wrists",
  [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
  [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged" }

local function SlotButton(parent, slot, x, y)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(38, 38); b:SetPoint("TOPLEFT", x, y)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.border = b:CreateTexture(nil, "OVERLAY"); b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.border:SetBlendMode("ADD"); b.border:SetSize(68, 68); b.border:SetPoint("CENTER")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b.trial = b:CreateTexture(nil, "OVERLAY", nil, 2); b.trial:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  b.trial:SetBlendMode("ADD"); b.trial:SetAllPoints(); b.trial:SetVertexColor(1, 0.82, 0); b.trial:Hide()
  b.slot = slot
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:AddLine("Empty", 0.5, 0.5, 0.5) end
    GameTooltip:AddLine(" ")
    if self.isTrial then GameTooltip:AddLine("Trying on - right-click to put back what's equipped", 1, 0.82, 0) end
    GameTooltip:AddLine("Click: try on other gear for this slot", 0.4, 1, 0.4)
    GameTooltip:Show()
    if NS.ShowUpgrades then NS.ShowUpgrades(self, sel, self.slot) end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide(); if NS.HideUpgrades then NS.HideUpgrades() end end)
  b:SetScript("OnClick", function(self, button)
    if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link); return end
    if not (NS.Try and sel) then return end
    if button == "RightButton" then NS.Try.Clear(sel, self.slot)
    else if NS.HideUpgrades then NS.HideUpgrades() end; NS.Try.OpenPicker(self, sel, self.slot) end
  end)
  slotButtons[slot] = b
  return b
end

local function FillGear(c)
  local Try = NS.Try
  for slot, b in pairs(slotButtons) do
    local link, isTrial = c.gear and c.gear[slot], false
    if Try then link, isTrial = Try.Link(c, slot) end
    b.link, b.isTrial = link, isTrial
    b.trial:SetShown(isTrial)
    if link then
      local tex = GetItemIcon and GetItemIcon(link) or (C_Item and C_Item.GetItemIconByID(link))
      b.icon:SetTexture(tex or 134400)
      local q = select(3, GetItemInfo(link))
      local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
      if col and q >= 2 then b.border:SetVertexColor(col.r, col.g, col.b); b.border:Show() else b.border:Hide() end
    else
      b.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (EMPTY[slot] or "Chest"))
      b.border:Hide()
    end
  end
  local g = panes.gear
  local classCol = (RAID_CLASS_COLORS or {})[c.classFile or ""]
  g.name:SetText(NS.ClassName and NS.ClassName(c) or c.name)
  g.info:SetText(("Level %d %s %s"):format(c.level or 0, c.race or "", c.class or ""))
  g.guild:SetText(c.guild and ("<" .. c.guild .. ">") or "")
  -- race portrait (the 3D model is only available for the character you're logged into)
  local key = (c.raceFile or "HUMAN"):upper() .. ((c.sex == 3) and "_FEMALE" or "_MALE")
  if key:find("^UNDEAD") then key = key:gsub("^UNDEAD", "SCOURGE") end
  -- this client's race sheet is the original 4 x 4 grid (males on the top two rows, females below); the game's own
  -- RACE_ICON_TCOORDS table is laid out for a bigger sheet, so it can't be used here
  local RIC = {
    HUMAN_MALE = { 0, 0.25, 0, 0.25 }, DWARF_MALE = { 0.25, 0.5, 0, 0.25 }, GNOME_MALE = { 0.5, 0.75, 0, 0.25 }, NIGHTELF_MALE = { 0.75, 1, 0, 0.25 },
    TAUREN_MALE = { 0, 0.25, 0.25, 0.5 }, SCOURGE_MALE = { 0.25, 0.5, 0.25, 0.5 }, TROLL_MALE = { 0.5, 0.75, 0.25, 0.5 }, ORC_MALE = { 0.75, 1, 0.25, 0.5 },
    HUMAN_FEMALE = { 0, 0.25, 0.5, 0.75 }, DWARF_FEMALE = { 0.25, 0.5, 0.5, 0.75 }, GNOME_FEMALE = { 0.5, 0.75, 0.5, 0.75 }, NIGHTELF_FEMALE = { 0.75, 1, 0.5, 0.75 },
    TAUREN_FEMALE = { 0, 0.25, 0.75, 1 }, SCOURGE_FEMALE = { 0.25, 0.5, 0.75, 1 }, TROLL_FEMALE = { 0.5, 0.75, 0.75, 1 }, ORC_FEMALE = { 0.75, 1, 0.75, 1 } }
  local tc = RIC[key]
  if Try and g.model and Try.ShowModel(g.model, c) then
    g.portrait:Hide(); if g.lookNote then g.lookNote:Hide() end
  else
    if g.model then g.model:Hide() end
    g.portrait:Show()
    g.lookNote:SetText(("Log in as %s to see them in 3D,\nwearing their gear."):format(c.name or "this character")); g.lookNote:Show()
    if tc then g.portrait:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"); g.portrait:SetTexCoord(unpack(tc))
    else g.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); g.portrait:SetTexCoord(0, 1, 0, 1) end
  end
  -- stats; while trying gear on, the new value follows in (green up / red down)
  local s = c.stats or {}
  local pv = Try and Try.Preview(c)
  local function val(key, pct)
    local cur = s[key]
    if cur == nil then return "|cff808080?|r" end
    local txt = pct and ("%.2f%%"):format(cur) or tostring(cur)
    local new = pv and pv[key]
    if new ~= nil then
      local d = new - cur
      if math.abs(d) >= (pct and 0.005 or 0.5) then
        local nt = pct and ("%.2f%%"):format(new) or tostring(math.floor(new + 0.5))
        txt = txt .. (d > 0 and "  |cff40ff40(" or "  |cffff4040(") .. (pct and "~" or "") .. nt .. ")|r"
      end
    end
    return txt
  end
  local lines = { { "Strength", "str" }, { "Agility", "agi" }, { "Stamina", "sta" }, { "Intellect", "int" }, { "Spirit", "spi" }, { "Armor", "armor" } }
  local lines2 = { { "Health", "health" }, { (s.powerType == 1 and "Rage") or (s.powerType == 3 and "Energy") or "Mana", "power" },
    { "Attack Power", "ap" }, { "Ranged AP", "rap" }, { "Crit", "crit", true }, { "Dodge", "dodge", true } }
  for i, l in ipairs(lines) do g.statL[i]:SetText(("|cffffd100%s:|r %s"):format(l[1], val(l[2], l[3]))) end
  for i, l in ipairs(lines2) do g.statR[i]:SetText(("|cffffd100%s:|r %s"):format(l[1], val(l[2], l[3]))) end
  local res = s.res or {}
  local function rv(i)
    local cur, new = res[i], pv and pv.res and pv.res[i]
    if cur == nil then return "?" end
    if new and new ~= cur then return cur .. (new > cur and "|cff40ff40(" or "|cffff4040(") .. new .. ")|r" end
    return tostring(cur)
  end
  g.res:SetText(("|cffff8040Fire|r %s  |cff40ff40Nature|r %s  |cff80c0ffFrost|r %s  |cffb080ffShadow|r %s  |cffffffa0Arcane|r %s")
    :format(rv(2), rv(3), rv(4), rv(5), rv(6)))
  local gs = c.gs and (" -  Gear Score " .. c.gs) or ""
  local il = ("Item level %.1f"):format(c.ilvl or 0)
  if pv and pv.ilvl and math.abs(pv.ilvl - (c.ilvl or 0)) >= 0.05 then
    il = il .. ((pv.ilvl > (c.ilvl or 0)) and " |cff40ff40(" or " |cffff4040(") .. ("%.1f"):format(pv.ilvl) .. ")|r"
  end
  g.summary:SetText(il .. gs)
  g.reset:SetShown(Try and Try.Has(c) or false)
  g.hint:SetShown(not (Try and Try.Has(c)) and c.gear ~= nil)
  g.nodata:SetShown(not c.gear)
end

local function BuildGear(p)
  local g = CreateFrame("Frame", nil, p); g:SetAllPoints()
  for i, s in ipairs(LEFT) do SlotButton(g, s[1], 10, -10 - (i - 1) * 42) end
  for i, s in ipairs(RIGHT) do SlotButton(g, s[1], 430, -10 - (i - 1) * 42) end
  for i, s in ipairs(BOTTOM) do SlotButton(g, s[1], 166 + (i - 1) * 46, -352) end
  g.name = g:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); g.name:SetPoint("TOP", g, "TOPLEFT", 239, -12)
  g.info = g:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); g.info:SetPoint("TOP", g.name, "BOTTOM", 0, -3)
  g.guild = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); g.guild:SetPoint("TOP", g.info, "BOTTOM", 0, -2)
  g.portrait = g:CreateTexture(nil, "ARTWORK"); g.portrait:SetSize(96, 96); g.portrait:SetPoint("TOP", g, "TOPLEFT", 239, -70)
  g.lookNote = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  g.lookNote:SetPoint("TOP", g.portrait, "BOTTOM", 0, -10); g.lookNote:SetWidth(260); g.lookNote:SetJustifyH("CENTER")
  local model = NS.Try and NS.Try.CreateModel(g, 360, 262)
  if model then
    g.model = model; model:SetPoint("TOP", g, "TOPLEFT", 239, -62); model:SetFrameLevel(g:GetFrameLevel() + 1); model:Hide()
  end
  g.summary = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g.summary:SetPoint("TOP", g, "TOPLEFT", 239, -332)
  g.reset = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); g.reset:SetSize(150, 20); g.reset:SetText("Put back all gear")
  g.reset:SetPoint("TOPLEFT", g, "TOPLEFT", 318, -362); g.reset:Hide()
  g.reset:SetScript("OnClick", function() if sel and NS.Try then NS.Try.Clear(sel) end end)
  g.hint = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); g.hint:SetPoint("TOPLEFT", g, "TOPLEFT", 318, -366); g.hint:SetWidth(150); g.hint:SetJustifyH("LEFT")
  g.hint:SetText("Click any slot to try on other gear")
  g.statL, g.statR = {}, {}
  for i = 1, 6 do
    g.statL[i] = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g.statL[i]:SetPoint("TOPLEFT", 500, -14 - (i - 1) * 18)
    g.statR[i] = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g.statR[i]:SetPoint("TOPLEFT", 500, -136 - (i - 1) * 18)
  end
  Header(g, "Attributes", 500, 2)
  g.res = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g.res:SetPoint("TOPLEFT", 500, -256); g.res:SetWidth(200); g.res:SetJustifyH("LEFT")
  g.nodata = g:CreateFontString(nil, "OVERLAY", "GameFontDisable"); g.nodata:SetPoint("TOP", g, "TOPLEFT", 239, -300)
  g.nodata:SetText("Log into this character once to record its gear.")
  return g
end


---------------------------------------------------------------- craftable-upgrade popup (hover any gear)
local NEEDS_SKILL = {
  ["One-Handed Axes"] = "Axes", ["Two-Handed Axes"] = "Two-Handed Axes", ["Bows"] = "Bows", ["Guns"] = "Guns",
  ["One-Handed Maces"] = "Maces", ["Two-Handed Maces"] = "Two-Handed Maces", ["Polearms"] = "Polearms",
  ["One-Handed Swords"] = "Swords", ["Two-Handed Swords"] = "Two-Handed Swords", ["Staves"] = "Staves",
  ["Fist Weapons"] = "Fist Weapons", ["Daggers"] = "Daggers", ["Thrown"] = "Thrown", ["Crossbows"] = "Crossbows",
  ["Wands"] = "Wands", ["Shields"] = "Shield", ["Leather"] = "Leather", ["Mail"] = "Mail", ["Plate"] = "Plate Mail",
}
local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
  [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
  [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard" }

local pop
local function Popup()
  if pop then return pop end
  pop = CreateFrame("Frame", "PintsLedgerUpgradePopup", UIParent, "BackdropTemplate")
  pop:SetFrameStrata("TOOLTIP"); pop:SetWidth(360)
  pop:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  pop:SetBackdropColor(0.03, 0.06, 0.03, 0.95); pop:SetBackdropBorderColor(0.3, 1, 0.3, 0.8)
  pop.title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pop.title:SetPoint("TOPLEFT", 10, -10)
  pop.lines = {}
  pop:Hide()
  return pop
end

local function CanUse(c, subType)
  local need = subType and NEEDS_SKILL[subType]
  if not need then return true end
  for _, s in ipairs(c.skillList or {}) do if s[2] ~= 1 and s[1] == need then return true end end
  return false
end

-- craftable upgrades (recipes known by anyone on the realm) for character c in slot
local function UpgradesFor(c, slot)
  local S = _G.CraftUpgradesScore
  if not S or not S.UpgradeVs then return nil, "Craft Upgrades is needed for upgrade scoring." end
  local items, crafters = L.Craftables()
  local ctx = { role = S.RoleFor(c), class = c.classFile, gear = function(s) return c.gear and c.gear[s] end }
  local out, waiting = {}, 0
  for _, id in ipairs(items) do
    local name, link, _, _, minLevel, _, subType, _, equipLoc = GetItemInfo(id)
    if not name then
      waiting = waiting + 1
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    else
      local slots = S.SlotsFor(equipLoc)
      local fits = false
      for _, s in ipairs(slots or {}) do if s == slot or (slot == 12 and s == 11) or (slot == 14 and s == 13) then fits = true end end
      if fits and (minLevel or 0) <= (c.level or 0) + 2 and CanUse(c, subType) and NS.CrafterCanGive(id, crafters[id], c.name) then
        local ok, pct, empty = pcall(S.UpgradeVs, link, ctx)
        if ok and pct then
          out[#out + 1] = { link = link, pct = pct, empty = empty, who = crafters[id], lvl = minLevel or 0 }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.pct > b.pct end)
  return out, nil, waiting
end

-- Bind-on-pickup crafts (e.g. alchemy trinkets) can only be worn by the character who makes them
function NS.CrafterCanGive(id, who, forName)
  local bind = select(14, GetItemInfo(id))
  if bind ~= 1 then return true end
  for _, w in ipairs(who or {}) do
    if w == forName or w:sub(1, #forName + 1) == forName .. " " then return true end
  end
  return false
end

local function ShowUpgrades(owner, c, slot)
  if not c or not slot then return end
  local p = Popup()
  local list, err, waiting = UpgradesFor(c, slot)
  for _, l in ipairs(p.lines) do l:Hide() end
  p.title:SetText(("|cff40ff40Craftable upgrades|r for %s - %s"):format(NS.ClassName and NS.ClassName(c) or c.name, SLOT_NAME[slot] or "?"))
  local y, n = -30, 0
  local function line(text, small)
    n = n + 1
    local fs = p.lines[n]
    if not fs then fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetWidth(340); fs:SetJustifyH("LEFT"); p.lines[n] = fs end
    fs:SetFontObject(small and "GameFontDisableSmall" or "GameFontHighlightSmall")
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 10, y); fs:SetText(text); fs:Show()
    y = y - (fs:GetStringHeight() + 3)
  end
  if err then line(err, true)
  elseif #list == 0 then line(waiting and waiting > 0 and "Loading item data - hover again in a moment." or "No craftable upgrades from your characters' known recipes.", true)
  else
    for i = 1, math.min(#list, 8) do
      local u = list[i]
      local pct = u.empty and "|cff40ff40empty slot|r" or ("|cff40ff40+%d%%|r"):format(math.floor(u.pct + 0.5))
      local lvl = (u.lvl > (c.level or 0)) and ("  |cff66ccff(lvl " .. u.lvl .. ")|r") or ""
      line(u.link .. "  " .. pct .. lvl)
      line("      made by " .. table.concat(u.who or {}, ", "), true)
    end
    if #list > 8 then line(("...and %d more in the Craft Upgrades tab"):format(#list - 8), true) end
  end
  -- gear-making professions whose recipes haven't been recorded yet (the profession window has to be opened once)
  local missing = {}
  local GEAR_PROFS = { Blacksmithing = true, Leatherworking = true, Tailoring = true, Engineering = true, Enchanting = true, Alchemy = true }
  for _, ch in ipairs(L.Characters(true)) do
    for _, pr in ipairs(ch.rec.profs or {}) do
      if GEAR_PROFS[pr.name] and not (ch.rec.crafts and ch.rec.crafts[pr.name]) then
        missing[#missing + 1] = ch.name .. " (" .. pr.name .. ")"
      end
    end
  end
  if #missing > 0 then
    y = y - 4
    line("|cffffd100Not recorded yet:|r " .. table.concat(missing, ", "), true)
    line("Open each profession window once on that character to include its recipes.", true)
  end
  p:SetHeight(-y + 8)
  p:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == owner then
    p:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
  else
    p:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", 4, 0)
  end
  p:Show()
end
local function HideUpgrades() if pop then pop:Hide() end end
NS.ShowUpgrades, NS.HideUpgrades = ShowUpgrades, HideUpgrades

---------------------------------------------------------------- grid (every character's gear side by side)
local GRID_ROWS = { { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 4, "Shirt" }, { 19, "Tabard" },
  { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Finger" }, { 12, "Finger" },
  { 13, "Trinket" }, { 14, "Trinket" }, { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" } }
local CELL = 36
local gridCells, gridHeads = {}, {}

local function BuildGrid(p)
  local f = CreateFrame("Frame", nil, p); f:SetAllPoints()
  f.headArea = CreateFrame("Frame", nil, f); f.headArea:SetPoint("TOPLEFT", 0, 0); f.headArea:SetPoint("TOPRIGHT", 0, 0); f.headArea:SetHeight(40)
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -44); sf:SetPoint("BOTTOMRIGHT", -26, 0)
  f.content = CreateFrame("Frame", nil, sf); f.content:SetSize(700, #GRID_ROWS * (CELL + 4)); sf:SetScrollChild(f.content)
  for r, row in ipairs(GRID_ROWS) do
    local lbl = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("RIGHT", f.content, "TOPLEFT", 88, -(r - 1) * (CELL + 4) - CELL / 2); lbl:SetText(row[2]); lbl:SetJustifyH("RIGHT")
  end
  return f
end

local function GridCell(r, col)
  gridCells[r] = gridCells[r] or {}
  local b = gridCells[r][col]
  if b then return b end
  local f = panes.grid
  b = CreateFrame("Button", nil, f.content)
  b:SetSize(CELL, CELL)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.glow:SetBlendMode("ADD")
  b.glow:SetSize(64, 64); b.glow:SetPoint("CENTER")
  b.lvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.lvl:SetPoint("BOTTOMRIGHT", -2, 2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:AddLine(SLOT_NAME[self.slot] or "", 0.6, 0.6, 0.6); GameTooltip:AddLine("Empty", 0.5, 0.5, 0.5) end
    GameTooltip:AddLine(" "); GameTooltip:AddLine(self.char.name, 1, 0.82, 0)
    GameTooltip:Show()
    ShowUpgrades(self, self.char, self.slot)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide(); HideUpgrades() end)
  b:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) else sel = self.char; NS.RefreshCharacters() end
  end)
  gridCells[r][col] = b
  return b
end

local function FillGrid()
  local f = panes.grid
  for col, c in ipairs(list) do
    local x = 96 + (col - 1) * (CELL + 4)
    local h = gridHeads[col]
    if not h then
      h = CreateFrame("Button", nil, f.headArea); h:SetSize(CELL, CELL)
      h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetAllPoints()
      h.sel = h:CreateTexture(nil, "OVERLAY"); h.sel:SetPoint("TOPLEFT", -3, 3); h.sel:SetPoint("BOTTOMRIGHT", 3, -3)
      h.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight"); h.sel:SetBlendMode("ADD")
      h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(NS.ClassName and NS.ClassName(self.char) or self.char.name)
        GameTooltip:AddLine(("Level %d %s"):format(self.char.level or 0, self.char.class or ""), 1, 1, 1)
        GameTooltip:AddLine(("Item level %.1f"):format(self.char.ilvl or 0), 1, 0.82, 0)
        GameTooltip:Show()
      end)
      h:SetScript("OnLeave", function() GameTooltip:Hide() end)
      h:SetScript("OnClick", function(self) sel = self.char; NS.RefreshCharacters() end)
      gridHeads[col] = h
    end
    h.char = c
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", x, -2)
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile or ""]
    if tc then h.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"); h.icon:SetTexCoord(unpack(tc)) end
    h.sel:SetShown(c == sel)
    h:Show()
    for r, row in ipairs(GRID_ROWS) do
      local b = GridCell(r, col)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -(r - 1) * (CELL + 4))
      local slot = row[1]
      local link = c.gear and c.gear[slot]
      b.char, b.slot, b.link = c, slot, link
      if link then
        local _, _, q, ilvl = GetItemInfo(link)
        b.icon:SetTexture((GetItemIcon and GetItemIcon(link)) or 134400); b.icon:SetDesaturated(false)
        local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if col and q >= 2 then b.glow:SetVertexColor(col.r, col.g, col.b); b.glow:Show() else b.glow:Hide() end
        b.lvl:SetText(ilvl and ilvl > 1 and ilvl or "")
      else
        b.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (EMPTY[slot] or "Chest")); b.glow:Hide(); b.lvl:SetText("")
      end
      b:Show()
    end
  end
  for col = #list + 1, #gridHeads do
    gridHeads[col]:Hide()
    for r in ipairs(GRID_ROWS) do if gridCells[r] and gridCells[r][col] then gridCells[r][col]:Hide() end end
  end
  f.content:SetWidth(math.max(700, 100 + #list * (CELL + 4)))
end


---------------------------------------------------------------- bags + bank (slot by slot)
local SLOT_SIZE, PER_ROW = 32, 12
local bagCells, bagIcons, bagLabels = {}, {}, {}

local function ItemCell(pool, i, parent)
  local b = pool[i]
  if b then return b end
  b = CreateFrame("Button", nil, parent)
  b:SetSize(SLOT_SIZE, SLOT_SIZE)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.glow:SetBlendMode("ADD")
  b.glow:SetSize(58, 58); b.glow:SetPoint("CENTER")
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self) if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end end)
  pool[i] = b
  return b
end

local function SetCell(b, slot)
  if slot then
    b.link = slot[1]
    b.icon:SetTexture((GetItemIcon and GetItemIcon(slot[1])) or 134400)
    b.count:SetText((slot[2] or 1) > 1 and slot[2] or "")
    local q = select(3, GetItemInfo(slot[1]))
    local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if col and q >= 2 then b.glow:SetVertexColor(col.r, col.g, col.b); b.glow:Show() else b.glow:Hide() end
  else
    b.link = nil
    b.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    b.count:SetText(""); b.glow:Hide()
  end
  b:Show()
end

local function BuildBags(p)
  local f = CreateFrame("Frame", nil, p); f:SetAllPoints()
  f.content = Scroll(f)
  return f
end

local function FillBags(c)
  local f = panes.bags
  local cellN, iconN, labelN, y = 0, 0, 0, 0
  local function label(text)
    labelN = labelN + 1
    local fs = bagLabels[labelN]
    if not fs then fs = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal"); bagLabels[labelN] = fs end
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 4, -y); fs:SetText(text); fs:Show()
    y = y + 22
  end
  local function container(info, defaultIcon)
    if not info or (info.size or 0) == 0 then return end
    iconN = iconN + 1
    local ib = ItemCell(bagIcons, iconN, f.content)
    ib:ClearAllPoints(); ib:SetPoint("TOPLEFT", 4, -y)
    if info.bag then SetCell(ib, { info.bag, 1 }) else ib.link = nil; ib.icon:SetTexture(defaultIcon); ib.count:SetText(""); ib.glow:Hide(); ib:Show() end
    for s = 1, info.size do
      cellN = cellN + 1
      local b = ItemCell(bagCells, cellN, f.content)
      local col, row = (s - 1) % PER_ROW, math.floor((s - 1) / PER_ROW)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 50 + col * (SLOT_SIZE + 3), -y - row * (SLOT_SIZE + 3))
      SetCell(b, info.slots and info.slots[s])
    end
    y = y + math.ceil(info.size / PER_ROW) * (SLOT_SIZE + 3) + 6
  end
  label("Bags")
  if c.bagSlots then
    for bag = 0, 4 do container(c.bagSlots[bag], "Interface\\Buttons\\Button-Backpack-Up") end
  else
    label("|cff808080Log into this character once to record its bags.|r")
  end
  y = y + 8
  label("Bank" .. (c.bankSeen and ("  |cff909090(checked " .. date("%b %d %H:%M", c.bankSeen) .. ")|r") or ""))
  if c.bankSlots then
    for i = 1, #c.bankSlots do container(c.bankSlots[i], "Interface\\Icons\\INV_Misc_Bag_10_Blue") end
  else
    label("|cff808080Bank not visited yet - open the bank on this character to record it.|r")
  end
  for j = cellN + 1, #bagCells do bagCells[j]:Hide() end
  for j = iconN + 1, #bagIcons do bagIcons[j]:Hide() end
  for j = labelN + 1, #bagLabels do bagLabels[j]:Hide() end
  f.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------- guild bank
local gbCells, gbTabBtns = {}, {}
local gbTab = 1

local function BuildGuild(p)
  local f = CreateFrame("Frame", nil, p); f:SetAllPoints()
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.info:SetPoint("TOPLEFT", 4, -4); f.info:SetWidth(700); f.info:SetJustifyH("LEFT")
  f.grid = CreateFrame("Frame", nil, f); f.grid:SetPoint("TOPLEFT", 0, -60); f.grid:SetSize(480, 240)
  return f
end

local function FillGuild(c)
  local f = panes.guild
  local guilds = PintsLedgerDB.guilds and PintsLedgerDB.guilds[c.realm or ""] or {}
  local g = c.guild and guilds[c.guild]
  for _, b in ipairs(gbTabBtns) do b:Hide() end
  for _, b in ipairs(gbCells) do b:Hide() end
  if g and g.tabs and next(g.tabs) then
    f.info:SetText(("|cffffd100<%s>|r guild bank  |cff909090(updated %s)|r"):format(c.guild, date("%b %d %H:%M", g.seen or 0)))
    local i = 0
    for t, tab in pairs(g.tabs) do
      i = i + 1
      local b = gbTabBtns[i]
      if not b then
        b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); b:SetSize(100, 22)
        b:SetScript("OnClick", function(self) gbTab = self.tab; NS.RefreshCharacters() end)
        gbTabBtns[i] = b
      end
      b.tab = t; b:SetText(tab.name or ("Tab " .. t)); b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4 + (i - 1) * 104, -24); b:Show()
    end
    local tab = g.tabs[gbTab] or select(2, next(g.tabs))
    for s = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
      local b = ItemCell(gbCells, s, f.grid)
      local col, row = (s - 1) % 14, math.floor((s - 1) / 14)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4 + col * (SLOT_SIZE + 2), -row * (SLOT_SIZE + 2))
      SetCell(b, tab.slots and tab.slots[s])
    end
    f.grid:Show()
  else
    f.grid:Hide()
    f.info:SetText(c.guild and ("|cffffd100<" .. c.guild .. ">|r - open the guild bank on a character in this guild to record it.") or "This character isn't in a guild.")
  end
end

-- the Guild Bank tab only appears once the selected character's guild bank has been opened and recorded
function NS.HasGuildBank(c)
  local g = c and c.guild and PintsLedgerDB.guilds and PintsLedgerDB.guilds[c.realm or ""] and PintsLedgerDB.guilds[c.realm or ""][c.guild]
  return g and g.tabs and next(g.tabs) ~= nil
end

---------------------------------------------------------------- reputation
local function BuildRep(p)
  local f = CreateFrame("Frame", nil, p); f:SetAllPoints()
  f.content = Scroll(f)
  f.none = f:CreateFontString(nil, "OVERLAY", "GameFontDisable"); f.none:SetPoint("CENTER")
  f.none:SetText("Log into this character once to record its reputation.")
  return f
end
local function FillRep(c)
  local f = panes.rep
  local reps = c.reps or {}
  f.none:SetShown(#reps == 0)
  local y = 0
  for i, r in ipairs(reps) do
    local row = repRows[i]
    if not row then
      row = CreateFrame("Frame", nil, f.content); row:SetSize(560, 20)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(240); row.name:SetJustifyH("LEFT")
      row.bar = Bar(row, 260, 16); row.bar:SetPoint("LEFT", 250, 0)
      repRows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
    local fname, isHeader, standing, bmin, bmax, val, hasRep = r[1], r[2] == 1, r[3], r[4], r[5], r[6], r[7] == 1
    if isHeader and not hasRep then
      row.name:SetFontObject("GameFontNormal"); row.name:SetText(fname); row.bar:Hide()
    else
      row.name:SetFontObject(isHeader and "GameFontNormal" or "GameFontHighlight")
      row.name:SetText((isHeader and "" or "   ") .. fname)
      local col = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing] or { r = 0.5, g = 0.5, b = 0.5 }
      row.bar:SetMinMaxValues(0, math.max(1, bmax - bmin)); row.bar:SetValue(val - bmin)
      row.bar:SetStatusBarColor(col.r, col.g, col.b)
      local label = _G["FACTION_STANDING_LABEL" .. standing] or ""
      row.bar.text:SetText(("%s  %d / %d"):format(label, val - bmin, bmax - bmin))
      row.bar:Show()
    end
    row:Show()
    y = y + 22
  end
  for i = #reps + 1, #repRows do repRows[i]:Hide() end
  f.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------- skills
local function BuildSkills(p)
  local f = CreateFrame("Frame", nil, p); f:SetAllPoints()
  f.content = Scroll(f)
  f.none = f:CreateFontString(nil, "OVERLAY", "GameFontDisable"); f.none:SetPoint("CENTER")
  f.none:SetText("Log into this character once to record its skills.")
  return f
end
local function SkillRow(i, f)
  local row = skillRows[i]
  if not row then
    row = CreateFrame("Frame", nil, f.content); row:SetSize(700, 20)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(240); row.name:SetJustifyH("LEFT")
    row.bar = Bar(row, 260, 16); row.bar:SetPoint("LEFT", 250, 0)
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); row.cost:SetPoint("LEFT", 250, 0); row.cost:SetWidth(70); row.cost:SetJustifyH("LEFT")
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.note:SetPoint("LEFT", 330, 0); row.note:SetWidth(370)
    row.note:SetJustifyH("LEFT"); row.note:SetWordWrap(false)
    skillRows[i] = row
  end
  return row
end
local function FillSkills(c)
  local f = panes.skills
  local sk = c.skillList or {}
  f.none:SetShown(#sk == 0)
  local i, y = 0, 0
  local function place(row, gap) y = y + (gap or 0); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:Show(); y = y + 22 end
  local function plain(row) row.bar:Hide(); row.note:Hide(); row.cost:Hide() end

  local known = {}
  for _, s in ipairs(sk) do if s[2] ~= 1 then known[s[1]] = true end end
  -- weapons this class can still learn, with the capital weapon master and cost
  local missing = {}
  if #sk > 0 then
    for _, w in ipairs(CLASS_WEAPONS[c.classFile or ""] or {}) do if not known[w] then missing[#missing + 1] = w end end
  end
  local trainers = WEAPON_TRAINERS[c.faction or "Alliance"] or WEAPON_TRAINERS.Alliance
  local done = false
  local function addMissing()
    if done or #missing == 0 then return end
    done = true
    i = i + 1
    local h = SkillRow(i, f); plain(h)
    h.name:SetFontObject("GameFontNormalSmall"); h.name:SetText("   |cff66ccffStill to learn:|r")
    place(h, 2)
    for _, w in ipairs(missing) do
      i = i + 1
      local row = SkillRow(i, f); plain(row)
      row.name:SetFontObject("GameFontHighlight"); row.name:SetText("   |cffa0a0a0" .. w .. "|r")
      local cost = WEAPON_COST_BY[w] or WEAPON_COST
      local afford = (c.money or 0) >= cost
      row.cost:SetText((afford and "|cffffffff" or "|cffff4040") .. Money(cost) .. "|r"); row.cost:Show()
      row.note:SetText(trainers[w] and ("|cffffd100" .. table.concat(trainers[w], "  |cff808080or|r  ") .. "|r") or "|cff808080no trainer in your capitals|r")
      row.note:Show()
      place(row)
    end
  end

  local inWeapons = false
  for _, s in ipairs(sk) do
    local sname, isHeader, rank, max = s[1], s[2] == 1, s[3], s[4]
    if isHeader then
      if inWeapons then addMissing() end          -- end of the Weapon Skills section
      inWeapons = (sname == "Weapon Skills")
    end
    i = i + 1
    local row = SkillRow(i, f); plain(row)
    if isHeader then
      row.name:SetFontObject("GameFontNormal"); row.name:SetText(sname)
      place(row, 4)
    else
      row.name:SetFontObject("GameFontHighlight"); row.name:SetText("   " .. sname)
      if max and max > 1 then
        row.bar:SetMinMaxValues(0, max); row.bar:SetValue(rank)
        local atCap = rank >= max
        row.bar:SetStatusBarColor(atCap and 0.8 or 0.15, atCap and 0.25 or 0.45, atCap and 0.2 or 0.85)
        row.bar.text:SetText(rank .. " / " .. max)
        row.bar:Show()
      end
      place(row)
    end
  end
  addMissing()                                      -- no Weapon Skills header (or it was last)
  for j = i + 1, #skillRows do skillRows[j]:Hide() end
  f.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------- page
local function ShowSub(key)
  if not panes[key] then key = "gear" end
  sub = key
  for k, pane in pairs(panes) do pane:SetShown(k == key) end
  for k, t in pairs(page.subTabs) do t.sel:SetShown(k == key) end
  NS.RefreshCharacters()
end

NS.ShowSub = function(k) ShowSub(k) end
function NS.SelectCharacter(realm, name, subKey)
  for _, ch in ipairs(L.Characters(true)) do
    if ch.realm == realm and ch.name == name then ch.rec.name, ch.rec.realm = ch.name, ch.realm; sel = ch.rec end
  end
  if subKey then ShowSub(subKey) else NS.RefreshCharacters() end
end

function NS.RefreshCharacters()
  if not page or not page:IsShown() then return end
  -- character list (this realm first)
  list = {}
  local myRealm, myName = L.Me()
  for _, ch in ipairs(L.Characters(true)) do
    ch.rec.name, ch.rec.realm = ch.name, ch.realm
    list[#list + 1] = ch.rec
  end
  local ui = PintsLedgerDB.ui
  local mode = ui.charSort or "name"
  ui.charOrder = ui.charOrder or {}
  local pos = {}
  for idx, k in ipairs(ui.charOrder) do pos[k] = idx end
  table.sort(list, function(a, b)
    if (a.realm == myRealm) ~= (b.realm == myRealm) then return a.realm == myRealm end
    if a.realm ~= b.realm then return a.realm < b.realm end
    if mode == "level" and (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    if mode == "class" and (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
    if mode == "custom" then
      local pa, pb = pos[a.realm .. "." .. a.name], pos[b.realm .. "." .. b.name]
      if pa and pb and pa ~= pb then return pa < pb end
      if pa and not pb then return true end
      if pb and not pa then return false end
    end
    return a.name < b.name
  end)
  -- remember the order shown, so switching to "custom" starts from it
  local order = {}
  for _, c in ipairs(list) do order[#order + 1] = c.realm .. "." .. c.name end
  page.shownOrder = order
  for k, b in pairs(page.sortBtns) do b.sel:SetShown(k == mode) end
  if not sel then
    for _, c in ipairs(list) do if c.realm == myRealm and c.name == myName then sel = c end end
    sel = sel or list[1]
  end
  for i, c in ipairs(list) do
    local b = listButtons[i]
    if not b then
      b = CreateFrame("Button", nil, page.listArea)
      b:SetSize(140, 24); b:SetPoint("TOPLEFT", 4, -34 - (i - 1) * 26)
      b:RegisterForDrag("LeftButton")
      b:SetScript("OnDragStart", function(self)
        if (PintsLedgerDB.ui.charSort or "name") ~= "custom" then return end
        page.dragging = self; self:SetAlpha(0.5)
      end)
      b:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        if page.dragging ~= self then return end
        page.dragging = nil
        local scale = page.listArea:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local top = page.listArea:GetTop()
        local target = math.floor((top - cy / scale - 34) / 26) + 1
        local order = page.shownOrder
        target = math.max(1, math.min(#order, target))
        local key = self.char.realm .. "." .. self.char.name
        local from
        for idx, k in ipairs(order) do if k == key then from = idx end end
        if from and target ~= from then
          table.remove(order, from)
          table.insert(order, target, key)
          PintsLedgerDB.ui.charOrder = order
          NS.RefreshCharacters()
        end
      end)
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.04)
      b.sel = b:CreateTexture(nil, "BORDER"); b.sel:SetAllPoints(); b.sel:SetColorTexture(0.25, 0.55, 1, 0.35)
      b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 3, 0)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 25, 0); b.text:SetWidth(112); b.text:SetJustifyH("LEFT")
      b:SetScript("OnClick", function(self) sel = self.char; NS.RefreshCharacters() end)
      b:SetScript("OnEnter", function(self)
        if not NS.CharTooltip then return end
        local custom = (PintsLedgerDB.ui.charSort or "name") == "custom"
        NS.CharTooltip(self, custom and "Click to view  -  drag to reorder" or "Click to view this character")
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      listButtons[i] = b
    end
    b.char = c
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile or ""]
    if tc then b.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"); b.icon:SetTexCoord(unpack(tc)) else b.icon:SetTexture(nil) end
    b.text:SetText((NS.ClassName and NS.ClassName(c) or c.name) .. " |cff40ff40" .. (c.level or "") .. "|r")
    b.sel:SetShown(c == sel)
    b:Show()
  end
  for i = #list + 1, #listButtons do listButtons[i]:Hide() end
  if not sel then return end
  -- sub-tabs: Guild Bank only shows once this character's guild bank has been recorded
  local hasGB, x = NS.HasGuildBank(sel), 160
  for _, d in ipairs(page.subOrder or {}) do
    local t = page.subTabs[d[1]]
    if d[1] ~= "guild" or hasGB then t:ClearAllPoints(); t:SetPoint("TOPLEFT", x, 0); t:Show(); x = x + 102 else t:Hide() end
  end
  if sub == "guild" and not hasGB then
    sub = "bags"
    for k, pane in pairs(panes) do pane:SetShown(k == sub) end
    for k, t in pairs(page.subTabs) do t.sel:SetShown(k == sub) end
  end
  if NS.Try and NS.Try.PickerFor() and (NS.Try.PickerFor() ~= sel or sub ~= "gear") then NS.Try.HidePicker() end
  if sub == "gear" then FillGear(sel) elseif sub == "grid" then FillGrid() elseif sub == "bags" then FillBags(sel)
  elseif sub == "guild" then FillGuild(sel) elseif sub == "rep" then FillRep(sel) else FillSkills(sel) end
end

function NS.BuildCharacters(parent)
  page = parent
  page:SetScript("OnShow", function() NS.RefreshCharacters() end)
  page.listArea = CreateFrame("Frame", nil, page)
  page.listArea:SetPoint("TOPLEFT"); page.listArea:SetPoint("BOTTOMLEFT"); page.listArea:SetWidth(150)
  -- sort buttons above the character list
  page.sortBtns = {}
  local sorts = { { "name", "A-Z", "Alphabetical" }, { "level", "Lvl", "Highest level first" }, { "class", "Class", "Grouped by class" },
                  { "custom", "Drag", "Your own order - drag names up or down" } }
  for i, d in ipairs(sorts) do
    local b = CreateFrame("Button", nil, page.listArea, "BackdropTemplate")
    b:SetSize(34, 22); b:SetPoint("TOPLEFT", 4 + (i - 1) * 36, -4)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0.15, 0.12, 0.05, 0.9); b:SetBackdropBorderColor(1, 0.82, 0, 0.5)
    b.sel = b:CreateTexture(nil, "ARTWORK"); b.sel:SetPoint("TOPLEFT", 2, -2); b.sel:SetPoint("BOTTOMRIGHT", -2, 2); b.sel:SetColorTexture(0.25, 0.55, 1, 0.4)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("CENTER"); b.text:SetText(d[2])
    b:SetScript("OnClick", function()
      if d[1] == "custom" and PintsLedgerDB.ui.charSort ~= "custom" then PintsLedgerDB.ui.charOrder = page.shownOrder end
      PintsLedgerDB.ui.charSort = d[1]
      NS.RefreshCharacters()
    end)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(d[3]); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.sortBtns[d[1]] = b
  end
  local sep = page:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(1, 0.82, 0, 0.3); sep:SetWidth(1)
  sep:SetPoint("TOPLEFT", 150, 0); sep:SetPoint("BOTTOMLEFT", 150, 0)
  local area = CreateFrame("Frame", nil, page)
  area:SetPoint("TOPLEFT", 160, -30); area:SetPoint("BOTTOMRIGHT", 0, 0)
  panes.gear = BuildGear(area)
  panes.grid = BuildGrid(area)
  panes.bags = BuildBags(area)
  panes.guild = BuildGuild(area)
  panes.rep = BuildRep(area)
  panes.skills = BuildSkills(area)
  page.subTabs = {}
  local defs = { { "gear", "Character" }, { "grid", "Gear Grid" }, { "bags", "Bags" }, { "guild", "Guild Bank" },
                  { "rep", "Reputation" }, { "skills", "Skills" } }
  for i, d in ipairs(defs) do
    local t = CreateFrame("Button", nil, page, "BackdropTemplate")
    t:SetSize(98, 24)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    t:SetBackdropColor(0.15, 0.12, 0.05, 0.9); t:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    t.sel = t:CreateTexture(nil, "ARTWORK"); t.sel:SetPoint("TOPLEFT", 2, -2); t.sel:SetPoint("BOTTOMRIGHT", -2, 2); t.sel:SetColorTexture(0.25, 0.55, 1, 0.35)
    t:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t.text:SetPoint("CENTER"); t.text:SetText(d[2])
    t:SetScript("OnClick", function() ShowSub(d[1]) end)
    page.subTabs[d[1]] = t
  end
  page.subOrder = defs
  ShowSub(sub)
end
