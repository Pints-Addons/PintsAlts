-- Pint's Alts: BiS tab (WoW Forever). Best-in-slot gear for the character's spec and level bracket, from the
-- WoW Forever BiS lists at wowtbc.gg (BisData.lua). Each slot: the picks, what you wear now, where each drops,
-- the level it needs, which of your characters already has it, upgrade % (with Craft Upgrades), and a wishlist star.
-- Click an item to try it on (Character tab). Shift-click links it.
local ADDON, NS = ...
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)

local B = {}
NS.Bis = B
local BRACKETS = { 20, 30, 40, 50, 60 }
-- the site's slot names -> inventory slot, in paper-doll order
local SLOTS = {
  { "head", 1, "Head" }, { "neck", 2, "Neck" }, { "shoulder", 3, "Shoulder" }, { "back", 15, "Back" }, { "chest", 5, "Chest" },
  { "wrist", 9, "Wrist" }, { "hands", 10, "Hands" }, { "waist", 6, "Waist" }, { "legs", 7, "Legs" }, { "feet", 8, "Feet" },
  { "finger", 11, "Rings" }, { "trinket", 13, "Trinkets" }, { "mainhand", 16, "Main Hand" }, { "twohand", 16, "Two-Hand" },
  { "offhand", 17, "Off Hand" }, { "ranged", 18, "Ranged / Relic" },
}
local CLS = { DRUID = "druid", HUNTER = "hunter", MAGE = "mage", PALADIN = "paladin", PRIEST = "priest", ROGUE = "rogue",
  SHAMAN = "shaman", WARLOCK = "warlock", WARRIOR = "warrior" }
local ROW_H, HEAD_H = 30, 20
-- dungeons and raids, roughly in level order (the filter lists the ones in the list you're looking at, in this order).
-- Wings share their dungeon: "Scarlet Monastery: Library" is under Scarlet Monastery.
local DUNGEONS = { "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade",
  "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "Sunken Temple",
  "Blackrock Depths", "Blackrock Spire", "Dire Maul", "Scholomance", "Stratholme",
  -- WoW Forever's own dungeons
  "Excavation Site: Wetlands", "Ruins of Lordaeron", "Hall of Thanes", "City of Dalaran", "The Drowned City",
  -- raids
  "Zul'Gurub", "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas" }
local DORDER = {}
for i, d in ipairs(DUNGEONS) do DORDER[d] = i end
local SPECIAL = { ["Arugal's Voidwalker"] = { "Shadowfang Keep" } }
-- the dungeon(s) a drop comes from: "Rhahk'Zor - The Deadmines" -> The Deadmines; quests, zones and crafting -> none
local dunCache = {}
local function DungeonsOf(src)
  if not src or src == "" then return {} end
  local hit = dunCache[src]
  if hit then return hit end
  hit = SPECIAL[src]
  if not hit then
    hit = {}
    local where = src:match(".* %- (.+)$") or src
    where = where:gsub("%s*%b()$", "")
    for part in where:gmatch("[^/]+") do
      part = part:gsub("^%s+", ""):gsub("%s+$", "")
      local d = DORDER[part] and part or part:match("^(.-):") 
      if d and DORDER[d] then hit[#hit + 1] = d end
    end
  end
  dunCache[src] = hit
  return hit
end
local function FromDungeon(src, d)
  for _, x in ipairs(DungeonsOf(src)) do if x == d then return true end end
  return false
end

function B.Available()
  return PintsBisData and PintsBisData.specs and (select(4, GetBuildInfo()) or 0) >= 16000 and true or false
end

local function Key(c) return (c.realm or "") .. "." .. (c.name or "") end
local function Pretty(spec, cls)
  local s = spec:gsub("%-" .. cls .. "$", ""):gsub("%-", " ")
  return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end
-- this class's specs on the site
local function ClassSpecs(cls)
  local out = {}
  for k in pairs(PintsBisData.specs) do if k:sub(-#cls - 1) == "-" .. cls then out[#out + 1] = k end end
  table.sort(out)
  return out
end
-- the spec to show: your pick, else the talent tree you've put the most into
function B.SpecFor(c)
  local cls = CLS[c.classFile or ""]
  if not cls then return nil end
  local ui = PintsLedgerDB.ui
  ui.bisSpec = ui.bisSpec or {}
  local pick = ui.bisSpec[Key(c)]
  if pick and PintsBisData.specs[pick] then return pick, false end
  local s = (c.spec or ""):lower():gsub(" combat$", ""):gsub("%s+", "-")
  if s == "feral" then s = "feral-dps" end
  local k = s ~= "" and (s .. "-" .. cls) or nil
  if k and PintsBisData.specs[k] then return k, true end
  return ClassSpecs(cls)[1], true
end
-- the bracket you've reached (the list for it is fully usable) and the next one (parts of it already are)
local function Floor(level)
  local f = BRACKETS[1]
  for _, b in ipairs(BRACKETS) do if (level or 1) >= b then f = b end end
  return f
end
local function Need(id)
  local it = PintsBisData.items[id]
  local req = select(5, GetItemInfo(id))
  if req and req > 0 then return req end
  return it and it[2] or 0
end
-- by level: the list for the bracket you've reached, plus every piece of the next bracket's list you can already
-- use (those first - they're the stronger picks); each level up brings in more of the next list
local function ByLevel(specLists, level)
  local f = Floor(level)
  local nextCap = f + 10
  local cur, nxt = specLists[f] or {}, (level >= f and specLists[nextCap]) or nil
  if level < BRACKETS[1] then cur, nxt = specLists[BRACKETS[1]] or {}, nil end
  local out, fromNext = {}, 0
  for _, sd in ipairs({ "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket",
      "mainhand", "twohand", "offhand", "ranged" }) do
    local list, seen = {}, {}
    for _, id in ipairs(nxt and nxt[sd] or {}) do
      if Need(id) <= level and not seen[id] then seen[id] = true; list[#list + 1] = { id, nextCap }; fromNext = fromNext + 1 end
    end
    for _, id in ipairs(cur[sd] or {}) do if not seen[id] then seen[id] = true; list[#list + 1] = { id, f } end end
    if #list > 0 then out[sd] = list end
  end
  return out, f, nxt and nextCap, fromNext
end

---------------------------------------------------------------- who has an item already
local function Holdings(c)
  local out = {}   -- [itemID] = "worn" | "Name (bags)" ...
  local L = NS.L
  local myKey = Key(c)
  local function put(id, text, mine)
    if not id then return end
    if mine or not out[id] then out[id] = text end
  end
  for _, ch in ipairs(L and L.Characters and L.Characters(true) or {}) do
    if ch.realm == c.realm then
      local rec, self = ch.rec, (ch.realm .. "." .. ch.name) == myKey
      for s = 1, 19 do
        local link = rec.gear and rec.gear[s]
        local id = link and tonumber(link:match("item:(%d+)"))
        put(id, self and "|cff40ff40worn|r" or ("|cff80c0ff" .. ch.name .. " wears it|r"), self)
      end
      local it = rec.items or {}
      for _, place in ipairs({ { "bags", "bags" }, { "bank", "bank" }, { "mail", "mail" } }) do
        for id in pairs(it[place[1]] or {}) do
          put(id, self and ("|cff40ff40in your " .. place[2] .. "|r") or ("|cff80c0ff" .. ch.name .. " (" .. place[2] .. ")|r"), self)
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------- the pane
local pane, rows = nil, {}
local view = {}            -- [charKey] = bracket shown (nil = by level)
local atLevel = {}         -- [charKey] = level typed in the level box (nil = the character's own)
local dungeon = nil        -- the dungeon filter (nil = every source)

local function Menu(owner, items, onPick)
  local m = B.menu
  if not m then
    m = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:EnableMouse(true); m:Hide()
    if m.SetBackdrop then
      m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      m:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    end
    m.btns = {}
    m:SetScript("OnShow", function() pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN") end)
    m:SetScript("OnHide", function() pcall(m.UnregisterEvent, m, "GLOBAL_MOUSE_DOWN") end)
    m:SetScript("OnEvent", function() if not m:IsMouseOver() and not (m.owner and m.owner:IsMouseOver()) then m:Hide() end end)
    B.menu = m
  end
  if m:IsShown() and m.owner == owner then m:Hide(); return end
  m.owner = owner
  for i, it in ipairs(items) do
    local b = m.btns[i]
    if not b then
      b = CreateFrame("Button", nil, m); b:SetSize(170, 18)
      b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 6, 0)
      m.btns[i] = b
    end
    b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 18)
    b.text:SetText((it.sel and "|cff40ff40> |r" or "   ") .. it.text)
    b:SetScript("OnClick", function() m:Hide(); onPick(it.value) end)
    b:Show()
  end
  for i = #items + 1, #m.btns do m.btns[i]:Hide() end
  m:SetSize(180, #items * 18 + 10)
  m:ClearAllPoints(); m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  m:Show()
end

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, pane.content)
  r:SetSize(760, ROW_H - 2)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.rank:SetPoint("LEFT", 0, 0); r.rank:SetWidth(22); r.rank:SetJustifyH("RIGHT")
  r.star = CreateFrame("Button", nil, r); r.star:SetSize(16, 16); r.star:SetPoint("LEFT", 26, 0)
  r.star.tex = r.star:CreateTexture(nil, "OVERLAY"); r.star.tex:SetAllPoints()
  r.star.tex:SetTexture("Interface\\COMMON\\ReputationStar"); r.star.tex:SetTexCoord(0, 0.5, 0, 0.5)
  r.star:SetScript("OnClick", function(self)
    local PL, e = _G.PintsLoot, self:GetParent().e
    if PL and PL.ToggleWishFor and e and pane.c then PL.ToggleWishFor(Key(pane.c), e.id, e.src); B.Fill(pane.c) end
  end)
  r.star:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Wishlist (shared with Pint's Loot)"); GameTooltip:Show()
  end)
  r.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 46, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 76, -2)
  r.name:SetWidth(310); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.src = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.src:SetPoint("BOTTOMLEFT", 76, 2)
  r.src:SetWidth(360); r.src:SetJustifyH("LEFT"); r.src:SetWordWrap(false)
  r.have = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.have:SetPoint("RIGHT", -150, 0)
  r.have:SetWidth(170); r.have:SetJustifyH("RIGHT"); r.have:SetWordWrap(false)
  r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.pct:SetPoint("RIGHT", -60, 0); r.pct:SetWidth(80); r.pct:SetJustifyH("RIGHT")
  r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.lvl:SetPoint("RIGHT", -6, 0); r.lvl:SetWidth(50); r.lvl:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self)
    if not self.e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.e.id)
    GameTooltip:AddLine(" ")
    if self.e.src and self.e.src ~= "" then GameTooltip:AddLine(self.e.src, 1, 0.82, 0, true) end
    GameTooltip:AddLine("Click: try it on   Shift-click: link   Star: wishlist", 0.6, 0.8, 1)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    local e, c = self.e, pane.c
    if not e or not c then return end
    local link = select(2, GetItemInfo(e.id)) or ("item:" .. e.id)
    if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link); return end
    if NS.Try and NS.Try.Set and e.slot then NS.Try.Set(c, e.slot, link); if NS.ShowSub then NS.ShowSub("gear") end end
  end)
  rows[i] = r
  return r
end

function B.Build(parent)
  pane = CreateFrame("Frame", nil, parent); pane:SetAllPoints()
  -- top bar: spec picker, level brackets, source credit
  pane.spec = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"); pane.spec:SetSize(190, 22); pane.spec:SetPoint("TOPLEFT", 4, -4)
  pane.spec:SetScript("OnClick", function(self)
    local c = pane.c; if not c then return end
    local cls = CLS[c.classFile or ""]; if not cls then return end
    local cur, auto = B.SpecFor(c)
    local items = { { text = "By talents (auto)", value = false, sel = auto } }
    for _, k in ipairs(ClassSpecs(cls)) do items[#items + 1] = { text = Pretty(k, cls), value = k, sel = (not auto and k == cur) } end
    Menu(self, items, function(v)
      PintsLedgerDB.ui.bisSpec = PintsLedgerDB.ui.bisSpec or {}
      PintsLedgerDB.ui.bisSpec[Key(c)] = v or nil
      B.Fill(c)
    end)
  end)
  pane.brk = {}
  -- a level to plan for: type one (1-60); empty or "Mine" goes back to the character's own level
  local ll = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); ll:SetPoint("LEFT", pane.spec, "RIGHT", 12, 0); ll:SetText("Level")
  pane.lvl = CreateFrame("EditBox", nil, pane, "InputBoxTemplate"); pane.lvl:SetSize(28, 20); pane.lvl:SetPoint("LEFT", ll, "RIGHT", 8, 0)
  pane.lvl:SetAutoFocus(false); pane.lvl:SetNumeric(true); pane.lvl:SetMaxLetters(2)
  local function TakeLevel(self)
    local c = pane.c; if not c then return end
    local v = tonumber(self:GetText() or "")
    if v and v >= 1 and v <= 60 and v ~= (c.level or 1) then atLevel[Key(c)] = v else atLevel[Key(c)] = nil end
    view[Key(c)] = nil                      -- (a typed level shows the by-level list)
    self:ClearFocus()
    B.Fill(c)
  end
  pane.lvl:SetScript("OnEnterPressed", TakeLevel)
  pane.lvl:SetScript("OnEditFocusLost", function(self) if pane.c then TakeLevel(self) end end)
  pane.lvl:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  pane.mine = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"); pane.mine:SetSize(44, 22); pane.mine:SetPoint("LEFT", pane.lvl, "RIGHT", 4, 0)
  pane.mine:SetText("Mine")
  pane.mine:SetScript("OnClick", function() local c = pane.c; if c then atLevel[Key(c)] = nil; view[Key(c)] = nil; B.Fill(c) end end)
  local lab = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lab:SetPoint("LEFT", pane.mine, "RIGHT", 12, 0); lab:SetText("Whole list:")
  for i, b in ipairs(BRACKETS) do
    local t = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"); t:SetSize(40, 22)
    t:SetPoint("LEFT", lab, "RIGHT", 6 + (i - 1) * 43, 0); t:SetText(tostring(b))
    t:SetScript("OnClick", function()
      local c = pane.c; if not c then return end
      view[Key(c)] = (view[Key(c)] == b) and nil or b
      B.Fill(c)
    end)
    pane.brk[i] = t
  end
  -- only what drops in one dungeon (the numbers keep each item's place in its slot's list)
  pane.dun = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"); pane.dun:SetSize(150, 22)
  pane.dun:SetPoint("LEFT", pane.brk[#BRACKETS], "RIGHT", 8, 0)
  pane.dun:SetScript("OnClick", function(self)
    local c = pane.c; if not c then return end
    local counts = pane.dunCounts or {}
    local items = { { text = "Every source", value = "", sel = dungeon == nil } }
    local names = {}
    for d in pairs(counts) do names[#names + 1] = d end
    if dungeon and not counts[dungeon] then names[#names + 1] = dungeon end
    table.sort(names, function(a, b) return (DORDER[a] or 99) < (DORDER[b] or 99) end)
    for _, d in ipairs(names) do items[#items + 1] = { text = ("%s |cff909090(%d)|r"):format(d, counts[d] or 0), value = d, sel = d == dungeon } end
    if #names == 0 then items[#items + 1] = { text = "|cff909090No dungeon drops in this list|r", value = "" } end
    Menu(self, items, function(v) dungeon = (v ~= "" and v) or nil; B.Fill(c) end)
  end)
  pane.note = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); pane.note:SetPoint("TOPLEFT", 6, -32); pane.note:SetWidth(740)
  pane.note:SetJustifyH("LEFT")
  -- list
  local sf = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -50); sf:SetPoint("BOTTOMRIGHT", -26, 4)
  pane.content = CreateFrame("Frame", nil, sf); pane.content:SetSize(760, 1); sf:SetScrollChild(pane.content)
  pane.none = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable"); pane.none:SetPoint("CENTER")
  pane:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  local wait
  pane:SetScript("OnEvent", function()
    if wait or not pane:IsVisible() then return end
    wait = true
    C_Timer.After(0.5, function() wait = false; if pane:IsVisible() and pane.c then B.Fill(pane.c) end end)
  end)
  return pane
end

function B.Fill(c)
  if not pane or not c then return end
  pane.c = c
  local cls = CLS[c.classFile or ""]
  local spec, auto = cls and B.SpecFor(c)
  if not spec then
    for _, r in ipairs(rows) do r:Hide() end
    pane.none:SetText("No BiS list for this character's class."); pane.none:Show(); return
  end
  pane.none:Hide()
  pane.spec:SetText(Pretty(spec, cls) .. (auto and "  |cff909090(auto)|r" or "") .. "  |cffaaaaaav|r")
  local planned = atLevel[Key(c)]
  local lvl = planned or c.level or 1
  if not pane.lvl:HasFocus() then pane.lvl:SetText(tostring(lvl)) end
  pane.mine:SetEnabled(planned ~= nil)
  local pickCap = view[Key(c)]
  local lists = PintsBisData.specs[spec]
  local list, note
  if pickCap then
    -- a bracket picked by hand: that whole list
    list = {}
    for sd, ids in pairs(lists[pickCap] or {}) do local l = {}; for _, id in ipairs(ids) do l[#l + 1] = { id, pickCap } end; list[sd] = l end
    note = ("%s: the level %d list (click it again for your level).  Source: wowtbc.gg"):format(Pretty(spec, cls), pickCap)
  else
    local f, nextCap, n
    list, f, nextCap, n = ByLevel(lists, lvl)
    note = ("%s at level %d%s: the level %d list%s.  Source: wowtbc.gg"):format(Pretty(spec, cls), lvl,
      planned and (" |cff80c0ff(planning ahead - you're " .. (c.level or 1) .. ")|r") or "", f,
      (nextCap and n > 0) and (", plus |cff40ff40" .. n .. "|r piece" .. (n == 1 and "" or "s") .. " from the level " .. nextCap .. " list you can use now") or "")
  end
  for i, b in ipairs(BRACKETS) do
    local on = b == pickCap
    pane.brk[i]:SetText((on and "|cff40ff40" or "") .. b .. "|r")
  end
  pane.note:SetText(note .. (c.spec and "" or "  |cffff8040- log in once to read the talent tree|r"))
  local D = PintsBisData
  local held = Holdings(c)
  local S = _G.CraftUpgradesScore
  local ctx = S and S.UpgradeVs and { role = S.RoleFor and S.RoleFor(c), class = c.classFile, gear = function(s) return c.gear and c.gear[s] end }
  local PL = _G.PintsLoot
  -- the dungeon filter: count what each dungeon has in this list (for the menu), then keep only the picked one's
  local counts = {}
  for _, l in pairs(list) do
    for _, pair in ipairs(l) do
      local it = D.items[pair[1]]
      for _, d in ipairs(DungeonsOf(it and it[1] and D.sources[it[1]])) do counts[d] = (counts[d] or 0) + 1 end
    end
  end
  pane.dunCounts = counts
  pane.dun:SetText(dungeon and ("|cff40ff40" .. dungeon .. "|r") or "Every source  |cffaaaaaav|r")
  local i, y = 0, 0
  for _, sd in ipairs(SLOTS) do
    local ids = {}
    for rank, pair in ipairs(list[sd[1]] or {}) do
      local it = D.items[pair[1]]
      if not dungeon or FromDungeon(it and it[1] and D.sources[it[1]], dungeon) then ids[#ids + 1] = { pair[1], pair[2], rank } end
    end
    if #ids > 0 then
      i = i + 1
      local h = Row(i)
      h.e = nil
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetHeight(HEAD_H)
      h.bg:SetColorTexture(1, 0.82, 0, 0.10)
      h.icon:Hide(); h.star:Hide(); h.rank:SetText(""); h.src:SetText(""); h.pct:SetText(""); h.lvl:SetText("")
      local worn = c.gear and c.gear[sd[2]]
      local wn = worn and GetItemInfo(worn)
      h.name:ClearAllPoints(); h.name:SetPoint("LEFT", 8, 0)
      h.name:SetText("|cffffd100" .. sd[3] .. "|r")
      h.have:SetText(worn and ("|cff909090wearing:|r " .. (wn or "...")) or "|cff909090(empty)|r")
      h:Show()
      y = y + HEAD_H + 2
      for _, pair in ipairs(ids) do
        local id, fromCap = pair[1], pair[2]
        local it = D.items[id] or {}
        i = i + 1
        local r = Row(i)
        local src = it[1] and D.sources[it[1]] or ""
        r.e = { id = id, slot = sd[2], src = src }
        r.rank:SetText(pair[3] == 1 and ("|cffffd100" .. pair[3] .. ".|r") or ("|cffc0c0c0" .. pair[3] .. ".|r"))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetHeight(ROW_H - 2)
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        local name, link, q, _, req = GetItemInfo(id)
        local icon = select(5, GetItemInfoInstant(id))
        if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark"); r.icon:Show()
        r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 76, -2)
        local col = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
        r.name:SetText(((col and col.hex) or "|cffffffff") .. (name or it[3] or ("item " .. id)) .. "|r")
        r.src:SetText("|cffd4a24c" .. (src ~= "" and src or "Source unknown") .. "|r" ..
          ((not pickCap and fromCap > Floor(lvl)) and ("  |cff40ff40(level " .. fromCap .. " list)|r") or ""))
        r.have:SetText(held[id] or "")
        local need = (req and req > 0) and req or it[2] or 0
        r.lvl:SetText(need > lvl and ("|cffff6060lvl " .. need .. "|r") or ("|cffa0a0a0lvl " .. need .. "|r"))
        r.pct:SetText("")
        if ctx and link and not (held[id] and held[id]:find("worn")) then
          local ok, pct, empty = pcall(S.UpgradeVs, link, ctx)
          if ok and empty then r.pct:SetText("|cff40ff40new slot|r")
          elseif ok and pct then r.pct:SetText((pct >= 0.5 and "|cff40ff40+" or (pct <= -0.5 and "|cffff4040" or "|cffa0a0a0")) .. math.floor(pct + 0.5) .. "%|r") end
        end
        if PL and PL.IsWishedFor then
          local on = PL.IsWishedFor(Key(c), id)
          r.star.tex:SetDesaturated(not on); r.star:SetAlpha(on and 1 or 0.6); r.star:Show()
        else r.star:Hide() end
        r:Show()
        y = y + ROW_H
      end
    end
  end
  for j = i + 1, #rows do rows[j]:Hide() end
  pane.content:SetHeight(math.max(1, y))
  if i == 0 then
    pane.none:SetText(dungeon and ("Nothing from " .. dungeon .. " in this list - pick Every source, or try another level or Whole list.") or "Nothing listed for this spec and level.")
    pane.none:Show()
  end
end
