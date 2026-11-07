-- Pints Ledger: window, views, bottom tabs, minimap button.
local ADDON, NS = ...
-- coins drawn with the money icons (WoW Forever's own coin text came out as bare digits: 6s 64c showed as "664")
local GetCoinTextureString = function(v)
	v = math.floor((tonumber(v) or 0) + 0.5)
	local neg = v < 0; if neg then v = -v end
	local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
	if s > 0 then out[#out + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
	return (neg and "-" or "") .. table.concat(out, " ")
end
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local GetItemQualityColor = GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor)

local L = NS.L
local floor = math.floor

local W, H, NAVW, ROWH = 980, 548, 150, 22
local win, content, header, rowsFrame, footer, footerCells
local views, viewOrder, currentView = {}, {}, nil
local rows, collapsed = {}, {}
local tabs, currentTab = {}, "ledger"

---------------------------------------------------------------- formatting
local CLASS_COLOR = RAID_CLASS_COLORS or {}
local function ClassName(c)
  local col = CLASS_COLOR[c.classFile or ""]
  local hex = col and (col.colorStr or ("ff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255)) or "ffffffff"
  return "|c" .. hex .. (c.name or "?") .. "|r"
end
local function Ago(t)
  if not t then return "|cff808080never|r" end
  local d = time() - t
  if d < 3600 then return "< 1 hour" end
  if d < 86400 then return floor(d / 3600) .. (floor(d / 3600) == 1 and " hour" or " hours") end
  return floor(d / 86400) .. (floor(d / 86400) == 1 and " day" or " days")
end
local function Played(s)
  if not s then return "|cff808080?|r" end
  return ("%dd |cffffd100%d|rh |cffffd100%d|rm"):format(floor(s / 86400), floor(s % 86400 / 3600), floor(s % 3600 / 60))
end
local function Money(c) c = math.floor((c or 0) + 0.5); return GetCoinTextureString and GetCoinTextureString(c) or tostring(c) end
local function LevelText(c)
  local lvl = c.level or 0
  local frac = (c.xpMax and c.xpMax > 0 and c.level < 60) and (c.xp or 0) / c.xpMax or 0
  return ("|cff40ff40%.1f|r"):format(lvl + frac)
end
local function IsMe(c) local r, n = L.Me(); return c.realm == r and c.name == n end
local function GS(c)
  if c.gs then return c.gs, c.gsColor end
  local old = GearScoreLogDB and GearScoreLogDB[(c.realm or "") .. "." .. (c.name or "")]   -- earlier GearScoreLog data
  if old and old.gs then return old.gs, old.r and { old.r, old.g, old.b } end
end
local function ProfCell(p)
  if not p then return "|cff606060-|r" end
  local col = (p.rank >= (p.max or 0)) and "|cffff4040" or ((p.max and p.rank >= p.max - 10) and "|cffffd100" or "|cffffffff")
  local icon = L.PROF_ICON[p.name]
  return (icon and ("|T" .. icon .. ":16|t ") or "") .. col .. p.rank .. "|r"
end
local function Sum(list) local s = 0; for _, v in ipairs(list) do s = s + v end; return s end

---------------------------------------------------------------- views
-- column: { title, width, justify, text = fn(c) -> string, sort = fn(c) -> value, total = fn(list) -> string }
local NAME = { "Character", 150, "LEFT", text = function(c) return ClassName(c) end, sort = function(c) return c.name end }
local LEVEL = { "Level", 55, "CENTER", text = LevelText, sort = function(c) return (c.level or 0) + ((c.xp or 0) / math.max(c.xpMax or 1, 1)) end,
  total = function(list) local s = 0; for _, c in ipairs(list) do s = s + (c.level or 0) end; return s end }

views.roster = { label = "Roster", cols = {
  NAME, LEVEL,
  { "Rest XP", 65, "CENTER", text = function(c)
      if (c.level or 0) >= 60 then return "|cff808080-|r" end
      local p = L.RestPercent(c)
      local col = p >= 150 and "|cff40ff40" or (p >= 50 and "|cffffd100" or "|cffff6060")
      return col .. floor(p) .. "%|r"
    end, sort = function(c) return L.RestPercent(c) end },
  { "Gear Score", 80, "CENTER", text = function(c)
      local gs, col = GS(c)
      if not gs then return "|cff808080-|r" end
      return col and ("|cff%02x%02x%02x%d|r"):format(col[1] * 255, col[2] * 255, col[3] * 255, gs) or tostring(gs)
    end, sort = function(c) return GS(c) or 0 end },
  { "iLvl", 50, "CENTER", text = function(c) return ("|cffffd100%.1f|r"):format(c.ilvl or 0) end, sort = function(c) return c.ilvl or 0 end },
  { "Money", 120, "RIGHT", text = function(c) return Money(c.money) end, sort = function(c) return c.money or 0 end,
    total = function(list) local s = 0; for _, c in ipairs(list) do s = s + (c.money or 0) end; return Money(s) end },
  { "Played", 115, "RIGHT", text = function(c) return Played(c.played) end, sort = function(c) return c.played or 0 end,
    total = function(list) local s = 0; for _, c in ipairs(list) do s = s + (c.played or 0) end; return Played(s) end },
  { "Last Online", 100, "CENTER", text = function(c) return IsMe(c) and "|cff40ff40Online|r" or Ago(c.lastOnline) end,
    sort = function(c) return IsMe(c) and math.huge or (c.lastOnline or 0) end },
} }

local function bagSizes(t, from, to)
  if not t then return nil end
  local s, used, total, free = {}, 0, 0, 0
  for i = from, to do
    local b = t[i]
    if b then s[#s + 1] = b[1]; total = total + b[1]; free = free + b[2] else s[#s + 1] = 0 end
  end
  return table.concat(s, "/"), free, total
end
views.bags = { label = "Bag Space", cols = {
  NAME, LEVEL,
  { "Bags", 130, "CENTER", text = function(c) local s = bagSizes(c.bags, 0, 4); return s and ("|cffffd100" .. s .. "|r") or "-" end },
  { "Free", 75, "CENTER", text = function(c)
      local _, free, total = bagSizes(c.bags, 0, 4)
      if not total then return "-" end
      local col = free == 0 and "|cffff4040" or (free < 5 and "|cffffd100" or "|cff40ff40")
      return col .. free .. "|r/|cff66ccff" .. total .. "|r"
    end, sort = function(c) local _, f = bagSizes(c.bags, 0, 4); return f or 0 end,
    total = function(list) local s = 0; for _, c in ipairs(list) do local _, f = bagSizes(c.bags, 0, 4); s = s + (f or 0) end; return s .. " free" end },
  { "Bank Bags", 150, "CENTER", text = function(c)
      local s = bagSizes(c.bank, 1, 7)
      return s and ("|cffffd100" .. s .. "|r") or "|cffffd100Bank not visited yet|r"
    end },
  { "Bank Free", 80, "CENTER", text = function(c)
      local _, free, total = bagSizes(c.bank, 1, 7)
      if not total then return "|cff808080-|r" end
      return "|cff40ff40" .. free .. "|r/|cff66ccff" .. total .. "|r"
    end, sort = function(c) local _, f = bagSizes(c.bank, 1, 7); return f or -1 end },
  { "Bank Checked", 100, "CENTER", text = function(c) return Ago(c.bankSeen) end, sort = function(c) return c.bankSeen or 0 end },
} }

views.skills = { label = "Skills", cols = {
  NAME, LEVEL,
  { "Profession 1", 110, "LEFT", text = function(c) return ProfCell(c.profs and c.profs[1]) end, sort = function(c) return c.profs and c.profs[1] and c.profs[1].rank or 0 end,
    book = function(c) return c.profs and c.profs[1] and c.profs[1].name end },
  { "Profession 2", 110, "LEFT", text = function(c) return ProfCell(c.profs and c.profs[2]) end, sort = function(c) return c.profs and c.profs[2] and c.profs[2].rank or 0 end,
    book = function(c) return c.profs and c.profs[2] and c.profs[2].name end },
  { "Cooking", 85, "LEFT", text = function(c) return ProfCell(c.secondary and c.secondary.Cooking) end, sort = function(c) return c.secondary and c.secondary.Cooking and c.secondary.Cooking.rank or 0 end,
    book = function(c) return c.secondary and c.secondary.Cooking and "Cooking" end },
  { "First Aid", 85, "LEFT", text = function(c) return ProfCell(c.secondary and c.secondary["First Aid"]) end, sort = function(c) return c.secondary and c.secondary["First Aid"] and c.secondary["First Aid"].rank or 0 end,
    book = function(c) return c.secondary and c.secondary["First Aid"] and "First Aid" end },
  { "Fishing", 85, "LEFT", text = function(c) return ProfCell(c.secondary and c.secondary.Fishing) end, sort = function(c) return c.secondary and c.secondary.Fishing and c.secondary.Fishing.rank or 0 end },
} }

views.activity = { label = "Activity", cols = {
  NAME, LEVEL,
  { "Mail", 60, "CENTER", text = function(c) local n = c.mail or 0; return (n > 0 and "|cff40ff40" or "|cff808080") .. n .. "|r" end, sort = function(c) return c.mail or 0 end },
  { "Mailbox Checked", 120, "CENTER", text = function(c) return Ago(c.mailSeen) end, sort = function(c) return c.mailSeen or 0 end },
  { "Auctions", 70, "CENTER", text = function(c) return tostring(c.auctions or 0) end, sort = function(c) return c.auctions or 0 end },
  { "Bids", 60, "CENTER", text = function(c) return tostring(c.bids or 0) end, sort = function(c) return c.bids or 0 end },
  { "AH Checked", 110, "CENTER", text = function(c) return c.ahSeen and Ago(c.ahSeen) or "|cffffd100N/A|r" end, sort = function(c) return c.ahSeen or 0 end },
} }

views.misc = { label = "Miscellaneous", cols = {
  NAME, LEVEL,
  { "Guild", 130, "CENTER", text = function(c) return c.guild and ("|cff40ff40<" .. c.guild .. ">|r") or "|cff808080None|r" end, sort = function(c) return c.guild or "" end },
  { "Hearthstone", 140, "CENTER", text = function(c) return c.bind or "?" end, sort = function(c) return c.bind or "" end },
  { "Class / Spec", 150, "CENTER", text = function(c)
      local col = CLASS_COLOR[c.classFile or ""]
      local hex = col and (col.colorStr or "ffffffff") or "ffffffff"
      return "|c" .. hex .. (c.class or "?") .. "|r / " .. (c.spec and ("|cffffffff" .. c.spec .. "|r") or "|cff808080None|r")
    end, sort = function(c) return c.class or "" end },
  { "Last Zone", 120, "CENTER", text = function(c) return c.zone or "?" end, sort = function(c) return c.zone or "" end },
} }
-- WoW Forever currencies: Merchant's Favor and Honor Points first, then any others your characters have
local CUR_FIRST = { "Merchant's Favor", "Honor Points" }
local function CurCol(n)
  local short = (n == "Merchant's Favor") and "Merchant's Favor" or n
  return { short, math.max(110, #short * 7 + 30), "RIGHT",
    text = function(c)
      local v = c.cur and c.cur[n]
      if not v then return "|cff808080-|r" end
      local k = PintsLedgerDB.currencies and PintsLedgerDB.currencies[n]
      return (v > 0 and "|cffffffff" or "|cff808080") .. v .. "|r" .. (k and k.icon and (" |T" .. k.icon .. ":14:14:0:0|t") or "")
    end,
    sort = function(c) return c.cur and c.cur[n] or -1 end,
    total = function(list) local s = 0; for _, c in ipairs(list) do s = s + (c.cur and c.cur[n] or 0) end; return s end }
end
function L.CurrencyColumns()
  local cols, seen = { NAME, LEVEL }, {}
  local function add(n) if not seen[n] and #cols < 8 then seen[n] = true; cols[#cols + 1] = CurCol(n) end end
  for _, n in ipairs(CUR_FIRST) do add(n) end
  local others = {}
  for n in pairs(PintsLedgerDB.currencies or {}) do if not seen[n] then others[#others + 1] = n end end
  table.sort(others)
  for _, n in ipairs(others) do add(n) end
  return cols
end
views.currency = { label = "Currencies", cols = { NAME, LEVEL } }
viewOrder = { "roster", "bags", "skills", "activity", "misc" }
if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then table.insert(viewOrder, "currency") end

---------------------------------------------------------------- rendering
local headerBtns, Refresh = {}, nil

local function SortList(list, view)
  local ui = PintsLedgerDB.ui
  local col = view.cols[ui.sortCol or 1] or view.cols[1]
  local fn = col.sort or col.text
  local asc = ui.sortAsc ~= false
  table.sort(list, function(a, b)
    local x, y = fn(a), fn(b)
    if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
    if x == y then return (a.name or "") < (b.name or "") end
    if asc then return x < y else return x > y end
  end)
end

local function GetRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, rowsFrame)
  r:SetSize(W - NAVW - 44, ROWH)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0)
  r.cells = {}
  rows[i] = r
  return r
end

local function Cell(r, j)
  local fs = r.cells[j]
  if not fs then
    fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetWordWrap(false)
    r.cells[j] = fs
  end
  return fs
end

local function Layout(r, view, offset)
  local x = offset
  for j, col in ipairs(view.cols) do
    local fs = Cell(r, j)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", r, "LEFT", x, 0)
    fs:SetWidth(col[2] - 6)
    fs:SetJustifyH(col[3])
    fs:Show()
    x = x + col[2]
  end
  for j = #view.cols + 1, #r.cells do r.cells[j]:Hide() end
end

local FACTION_TEX = { Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance", Horde = "Interface\\TargetingFrame\\UI-PVP-Horde" }

local function RowTooltip(r, hint)
  local c = r.char
  if not c then return end
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ClassName(c) .. "  |cff909090" .. (c.realm or "") .. "|r")
  GameTooltip:AddLine(("Level %d %s %s"):format(c.level or 0, c.race or "", c.class or ""), 1, 1, 1)
  if c.faction then GameTooltip:AddLine(c.faction, c.faction == "Horde" and 1 or 0.4, c.faction == "Horde" and 0.3 or 0.6, c.faction == "Horde" and 0.3 or 1) end
  if c.zone then GameTooltip:AddDoubleLine("Last seen in", c.zone, 0.8, 0.8, 0.8, 1, 1, 1) end
  if c.xpMax and c.xpMax > 0 and (c.level or 0) < 60 then
    GameTooltip:AddDoubleLine("XP", ("%d / %d (%.0f%%)"):format(c.xp or 0, c.xpMax, (c.xp or 0) / c.xpMax * 100), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  for _, p in ipairs(c.profs or {}) do GameTooltip:AddDoubleLine(p.name, p.rank .. " / " .. (p.max or "?"), 0.8, 0.8, 0.8, 1, 1, 1) end
  if c.hardcore then GameTooltip:AddLine("Hardcore", 1, 0.3, 0.3) end
  GameTooltip:AddLine(" ")
  if type(hint) ~= "string" and currentView == "skills" then GameTooltip:AddLine("Click a profession to see their recipes", 0.4, 1, 0.4) end
  GameTooltip:AddLine(type(hint) == "string" and hint or "Shift + right-click to remove this character", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end
NS.CharTooltip = RowTooltip      -- the Characters tab's list uses the same tooltip

StaticPopupDialogs.PINTSLEDGER_FORGET = {
  text = "Remove %s from Pint's Alts?\n(It comes back next time you log into it.)",
  button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(_, data) L.Forget(data.realm, data.name); Refresh() end,
}

function Refresh()
  if not (win and win:IsShown() and currentTab == "ledger") then return end
  local view = views[currentView]
  if currentView == "currency" then view.cols = L.CurrencyColumns() end
  -- header buttons
  local x = 28
  for j, col in ipairs(view.cols) do
    local b = headerBtns[j]
    if not b then
      b = CreateFrame("Button", nil, header)
      b:SetHeight(24)
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.04)
      b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0)
      b:SetScript("OnClick", function(self)
        local ui = PintsLedgerDB.ui
        if ui.sortCol == self.index then ui.sortAsc = not (ui.sortAsc ~= false) else ui.sortCol, ui.sortAsc = self.index, true end
        Refresh()
      end)
      headerBtns[j] = b
    end
    b.index = j
    b:ClearAllPoints(); b:SetPoint("LEFT", header, "LEFT", x, 0); b:SetWidth(col[2] - 2)
    b.text:SetJustifyH(col[3])
    local ui = PintsLedgerDB.ui
    local arrow = ((ui.sortCol or 1) == j) and ((ui.sortAsc ~= false) and " |TInterface\\Buttons\\Arrow-Up-Up:12|t" or " |TInterface\\Buttons\\Arrow-Down-Up:12|t") or ""
    b.text:SetText(col[1] .. arrow)
    b:Show()
    x = x + col[2]
  end
  for j = #view.cols + 1, #headerBtns do headerBtns[j]:Hide() end

  -- group characters by realm
  local byRealm, realms = {}, {}
  for _, ch in ipairs(L.Characters(true)) do
    local c = ch.rec
    c.name, c.realm = ch.name, ch.realm
    if not byRealm[ch.realm] then byRealm[ch.realm] = {}; realms[#realms + 1] = ch.realm end
    table.insert(byRealm[ch.realm], c)
  end
  local myRealm = L.Me()
  table.sort(realms, function(a, b) if a == myRealm then return true elseif b == myRealm then return false end return a < b end)

  local i, all = 0, {}
  local function addRow(kind, payload, list)
    i = i + 1
    local r = GetRow(i)
    r.char, r.realmName = nil, nil
    r.bg:SetColorTexture(0, 0, 0, 0)
    r.icon:Hide()
    if kind == "realm" then
      local cells = Cell(r, 1)
      for j = 2, #r.cells do r.cells[j]:Hide() end
      cells:ClearAllPoints(); cells:SetPoint("LEFT", 28, 0); cells:SetWidth(500); cells:SetJustifyH("LEFT"); cells:Show()
      r.icon:SetTexture(collapsed[payload] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
      r.icon:SetTexCoord(0, 1, 0, 1); r.icon:Show()
      cells:SetText("|cffffd100" .. payload .. "|r  |cff909090(" .. #list .. " characters)|r")
      r.bg:SetColorTexture(1, 0.82, 0, 0.06)
      r.realmName = payload
    elseif kind == "char" then
      Layout(r, view, 28)
      for j, col in ipairs(view.cols) do
        local ok, t = pcall(col.text, payload)
        r.cells[j]:SetText(ok and t or "|cffff0000err|r")
      end
      local tex = FACTION_TEX[payload.faction or ""]
      if tex then r.icon:SetTexture(tex); r.icon:SetTexCoord(0.05, 0.6, 0.02, 0.6); r.icon:Show() end
      if i % 2 == 0 then r.bg:SetColorTexture(1, 1, 1, 0.025) end
      if IsMe(payload) then r.bg:SetColorTexture(0.25, 0.6, 1, 0.08) end
      r.char = payload
    elseif kind == "total" then
      Layout(r, view, 28)
      for j, col in ipairs(view.cols) do
        local t = ""
        if j == 1 then t = "|cffffd100Totals|r"
        elseif col.total then local ok, v = pcall(col.total, list); t = ok and ("|cffffffff" .. tostring(v) .. "|r") or "" end
        r.cells[j]:SetText(t)
      end
      r.bg:SetColorTexture(1, 0.82, 0, 0.04)
    end
    r:Show()
  end
  for _, rn in ipairs(realms) do
    local list = byRealm[rn]
    SortList(list, view)
    addRow("realm", rn, list)
    if not collapsed[rn] then
      for _, c in ipairs(list) do addRow("char", c); all[#all + 1] = c end
      if #realms > 1 then addRow("total", nil, list) end
    else
      for _, c in ipairs(list) do all[#all + 1] = c end
    end
  end
  for j = i + 1, #rows do rows[j]:Hide() end
  rowsFrame:SetHeight(math.max(1, i * ROWH))
  -- footer
  local lv, gold, played = 0, 0, 0
  for _, c in ipairs(all) do lv = lv + (c.level or 0); gold = gold + (c.money or 0); played = played + (c.played or 0) end
  footer.text:SetText("")
  footerCells = footerCells or {}
  local x = 28
  for j, col in ipairs(view.cols) do
    local fs = footerCells[j]
    if not fs then fs = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetWordWrap(false); footerCells[j] = fs end
    fs:ClearAllPoints(); fs:SetPoint("LEFT", footer, "LEFT", x, 0); fs:SetWidth(col[2] - 6); fs:SetJustifyH(col[3])
    local t = ""
    if j == 1 then t = ("|cffffd100Totals|r  |cff909090(%d)|r"):format(#all)
    elseif col.total then local ok, v = pcall(col.total, all); t = ok and tostring(v) or "" end
    fs:SetText(t); fs:Show()
    x = x + col[2]
  end
  for j = #view.cols + 1, #footerCells do footerCells[j]:Hide() end
end
L.OnChanged = function()
  if win and win:IsShown() then
    Refresh()
    if currentTab == "characters" and NS.RefreshCharacters then NS.RefreshCharacters() end
  end
end
NS.ClassName, NS.Money = ClassName, Money

---------------------------------------------------------------- window
local function Backdrop(f, a)
  f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  f:SetBackdropColor(0.04, 0.04, 0.06, a or 0.95)
end

local function SelectView(key)
  currentView = key
  PintsLedgerDB.ui.view = key
  PintsLedgerDB.ui.sortCol, PintsLedgerDB.ui.sortAsc = PintsLedgerDB.ui.sortCol or 1, PintsLedgerDB.ui.sortAsc
  for k, b in pairs(win.nav) do
    if k == key then b.sel:Show(); b.text:SetTextColor(1, 1, 1) else b.sel:Hide(); b.text:SetTextColor(1, 0.82, 0) end
  end
  Refresh()
end

local searchBox, RunSearch
local function ShowTab(key)
  currentTab = key
  if win.search then win.search:Hide() end
  if searchBox and searchBox:GetText() ~= "" then searchBox.quiet = true; searchBox:SetText(""); searchBox.quiet = nil; searchBox:ClearFocus() end
  for k, t in pairs(tabs) do
    t.sel:SetShown(k == key)
    t.text:SetTextColor(k == key and 1 or 1, k == key and 1 or 0.82, k == key and 1 or 0)
  end
  win.ledger:SetShown(key == "ledger")
  if key == "characters" then
    if not win.chars.built and NS.BuildCharacters then NS.BuildCharacters(win.chars); win.chars.built = true end
    win.chars:Show()
    if NS.RefreshCharacters then NS.RefreshCharacters() end
  else
    win.chars:Hide()
  end
  local cu = _G.CraftUpgradesFrame
  if key == "upgrades" then
    if cu then
      NS.BuildUpgradeList()
      cu:SetParent(win.upgrades); cu:ClearAllPoints(); cu:SetPoint("TOPRIGHT", win.upgrades, "TOPRIGHT", 0, 0)
      if CraftUpgradesAPI and CraftUpgradesAPI.SetDocked then CraftUpgradesAPI.SetDocked(true) end
      cu:SetFrameStrata(win:GetFrameStrata()); cu:SetMovable(false)
      cu:Show()
      if CraftUpgradesAPI and CraftUpgradesAPI.Scan then CraftUpgradesAPI.Scan() end
      win.upgrades.missing:Hide()
    else
      win.upgrades.missing:Show()
    end
    win.upgrades:Show()
  else
    win.upgrades:Hide()
    if cu and cu:GetParent() == win.upgrades then
      cu:Hide(); cu:SetParent(UIParent); cu:ClearAllPoints(); cu:SetPoint("CENTER"); cu:SetMovable(true); cu:SetFrameStrata("DIALOG")
      if CraftUpgradesAPI and CraftUpgradesAPI.SetDocked then CraftUpgradesAPI.SetDocked(false) end
    end
  end
  if key == "ledger" then Refresh() end
end

---------------------------------------------------------------- recipe book: any character's known recipes, without logging in
local BOOK_NAME = { Mining = "Smelting" }       -- the profession window for Mining is called Smelting
local KIND_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080" }
local CATS = { "All", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket",
  "Weapons", "Off-hand & Shields", "Ranged", "Bags", "Trade Goods", "Consumables", "Enchants", "Other" }
local LOC_CAT = { INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest",
  INVTYPE_ROBE = "Chest", INVTYPE_BODY = "Chest", INVTYPE_TABARD = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist",
  INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "Weapons",
  INVTYPE_2HWEAPON = "Weapons", INVTYPE_WEAPONMAINHAND = "Weapons", INVTYPE_WEAPONOFFHAND = "Weapons", INVTYPE_SHIELD = "Off-hand & Shields",
  INVTYPE_HOLDABLE = "Off-hand & Shields", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged", INVTYPE_BAG = "Bags" }
local ENCHANT_SLOT = { { "Bracer", "Wrist" }, { "Gloves", "Hands" }, { "Boots", "Feet" }, { "Chest", "Chest" }, { "Cloak", "Back" },
  { "Shield", "Off-hand & Shields" }, { "Weapon", "Weapons" } }
local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
-- the item a recipe makes: recorded, or read from its link (books saved before item ids were kept)
local function MadeItem(e)
  if e[5] then return e[5] end
  local id = e[2] and tonumber(e[2]:match("item:(%d+)"))
  e[5] = id
  return id
end
local function Category(e)
  local item = MadeItem(e)
  if item and Instant then
    local _, _, _, loc, _, classID = Instant(item)
    if loc and LOC_CAT[loc] then return LOC_CAT[loc] end
    if classID == 1 then return "Bags" elseif classID == 7 then return "Trade Goods" elseif classID == 0 then return "Consumables" end
    return "Other"
  end
  local name = e[1] or ""
  if name:find("^Enchant ") then
    for _, w in ipairs(ENCHANT_SLOT) do if name:find(w[1], 1, true) then return w[2] end end
    return "Enchants"
  end
  return "Other"
end
-- lowest auction price, if the item was seen on the auction house in the last week (Pint's Auctions)
local function AH(id)
  if not id then return end
  local P = _G.PintsAuctions
  if P and P.Price then
    local m, t = P.Price(id)
    if m and m > 0 and t and time() - t <= 7 * 86400 then return m end
    return
  end
  -- without Pint's Auctions: Auctionator's price, if it's installed
  local A = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
  if A and A.GetAuctionPriceByItemID then
    local ok, v = pcall(A.GetAuctionPriceByItemID, "PintsLedger", id)
    if ok and v and v > 0 then return v end
  end
end
local function ItemName(id) local n = GetItemInfo(id); return n or ("item " .. id) end
-- reagents vendors sell (unlimited stock), price each in copper - from the CMaNGOS Classic database
local VENDOR = { [159]=5,[1179]=25,[2320]=10,[2321]=100,[2324]=25,[2325]=1000,[2596]=120,[2604]=50,[2605]=100,[2665]=20,[2678]=2,[2692]=40,[2880]=100,[2894]=50,[3371]=4,[3372]=40,[3466]=2000,[3713]=160,[3857]=500,[4289]=50,[4291]=500,[4340]=350,[4341]=500,[4342]=2500,[4399]=200,[4400]=2000,[4470]=38,[4536]=5,[6260]=50,[6261]=1000,[6530]=100,[8343]=2000,[8925]=500,[10290]=2500,[10647]=2000,[10648]=500,[14341]=5000,[17034]=200,[17035]=400,[17194]=2,[17196]=50,[18256]=6000 }
-- best price for one: vendor if a vendor sells it, else the auction house; second value says which
local function UnitCost(id)
  if VENDOR[id] then return VENDOR[id], "vendor" end
  local p = AH(id)
  if p then return p, "ah" end
end
-- what any of your characters can make it from (Pint's Ledger's crafts on this realm)
local madeFrom
local function MadeFrom(id)
  if not madeFrom then
    madeFrom = {}
    local _, _, reagents = L.Craftables()
    for item, r in pairs(reagents or {}) do madeFrom[item] = r end
    C_Timer.After(30, function() madeFrom = nil end)      -- refresh now and then
  end
  return madeFrom[id]
end

local book
function NS.OpenBook(c, prof)
  local key = BOOK_NAME[prof] or prof
  if not book then
    book = CreateFrame("Frame", "PintsLedgerBook", UIParent, "BackdropTemplate")
    -- opens on top of the Ledger (right-hand side), solid, kept on screen
    book:SetSize(460, 620); book:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, -40); book:SetFrameStrata("DIALOG"); book:SetToplevel(true)
    book:SetClampedToScreen(true)
    book:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = false, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    book:SetBackdropColor(0.06, 0.06, 0.07, 1); book:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    book:EnableMouse(true); book:SetMovable(true); book:RegisterForDrag("LeftButton")
    book:SetScript("OnDragStart", book.StartMoving); book:SetScript("OnDragStop", book.StopMovingOrSizing)
    tinsert(UISpecialFrames, "PintsLedgerBook")
    book.title = book:CreateFontString(nil, "OVERLAY", "GameFontNormal"); book.title:SetPoint("TOPLEFT", 14, -12); book.title:SetWidth(400); book.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, book, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() book:Hide() end)
    book.search = CreateFrame("EditBox", nil, book, "InputBoxTemplate"); book.search:SetSize(150, 20); book.search:SetPoint("TOPLEFT", 20, -34)
    book.search:SetAutoFocus(false)
    book.search:SetScript("OnTextChanged", function() NS.RenderBook() end)
    book.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    -- type / slot filter
    book.cat = "All"
    book.catBtn = CreateFrame("Button", nil, book, "UIPanelButtonTemplate"); book.catBtn:SetSize(140, 22); book.catBtn:SetPoint("LEFT", book.search, "RIGHT", 8, 0)
    book.catBtn:SetScript("OnClick", function(self)
      local m = book.menu
      if not m then
        m = CreateFrame("Frame", nil, book, "BackdropTemplate"); book.menu = m
        m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
          insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        m:SetBackdropColor(0, 0, 0, 0.96); m:SetFrameStrata("FULLSCREEN_DIALOG"); m.rows = {}
      end
      if m:IsShown() then m:Hide(); return end
      local i = 0
      for _, cat in ipairs(CATS) do
        local n = book.counts and book.counts[cat] or 0
        if cat == "All" or n > 0 then
          i = i + 1
          local r = m.rows[i]
          if not r then
            r = CreateFrame("Button", nil, m); r:SetSize(150, 16); r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 16)
            r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 4, 0)
            r:SetScript("OnClick", function(rb) book.cat = rb.cat; m:Hide(); NS.RenderBook() end)
            m.rows[i] = r
          end
          r.cat = cat
          r.t:SetText((cat == book.cat and "|cffffd100" or "") .. cat .. (cat ~= "All" and ("  |cff909090" .. n .. "|r") or ""))
          r:Show()
        end
      end
      for k = i + 1, #m.rows do m.rows[k]:Hide() end
      m:SetSize(162, i * 16 + 12); m:ClearAllPoints(); m:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2); m:Show()
    end)
    book.count = book:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); book.count:SetPoint("LEFT", book.catBtn, "RIGHT", 8, 0)
    local hp = book:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); hp:SetPoint("TOPRIGHT", -36, -60); hp:SetText("Auction")
    local sf = CreateFrame("ScrollFrame", "PintsLedgerBookScroll", book, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -74); sf:SetPoint("BOTTOMRIGHT", -30, 262)
    book.content = CreateFrame("Frame", nil, sf); book.content:SetSize(410, 1); sf:SetScrollChild(book.content)
    book.lines = {}
    -- what the selected recipe costs to make, reagent by reagent
    local d = CreateFrame("Frame", nil, book, "BackdropTemplate")
    d:SetPoint("BOTTOMLEFT", 10, 34); d:SetPoint("BOTTOMRIGHT", -10, 34); d:SetHeight(222)
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); d:SetBackdropColor(1, 1, 1, 0.04)
    d.lines = {}
    for k = 1, 15 do
      local l = CreateFrame("Button", nil, d); l:SetSize(420, 14); l:SetPoint("TOPLEFT", 6, -4 - (k - 1) * 14)
      l.left = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l.left:SetPoint("LEFT"); l.left:SetWidth(270); l.left:SetJustifyH("LEFT"); l.left:SetWordWrap(false)
      l.right = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l.right:SetPoint("RIGHT"); l.right:SetJustifyH("RIGHT")
      l:SetScript("OnEnter", function(self) if self.id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.id); GameTooltip:Show() end end)
      l:SetScript("OnLeave", function() GameTooltip:Hide() end)
      d.lines[k] = l
    end
    book.detail = d
    book.foot = book:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); book.foot:SetPoint("BOTTOMLEFT", 14, 12); book.foot:SetWidth(430); book.foot:SetJustifyH("LEFT")
  end
  book.c, book.prof, book.sel, book.cat = c, key, nil, "All"
  book.title:SetText((ClassName(c) or c.name or "?") .. "'s " .. prof)
  book.search:SetText("")
  if book.menu then book.menu:Hide() end
  book:Show()
  NS.RenderBook()
end

local function Reagents(e)
  if e[6] then return e[6] end
  local item = MadeItem(e)
  local cr = item and book.c.crafts and book.c.crafts[book.prof] and book.c.crafts[book.prof][item]
  if cr and cr.reagents then
    local out = {}
    for _, r in ipairs(cr.reagents) do out[#out + 1] = { r[1], r[2] } end
    return out
  end
end
local SCAN_HINT = "|cff66ccffPrices missing? Scan the auction house (Pint's Auctions: Pint's tab > Full scan, or Auctionator).|r"
local function RenderDetail()
  local d, e = book.detail, book.sel
  local k = 0
  local function line(l, r, id)
    k = k + 1; local x = d.lines[k]; if not x then return end
    x.left:SetWidth((r and r ~= "") and 270 or 420)
    x.left:SetText(l or ""); x.right:SetText(r or ""); x.id = id; x:Show()
  end
  if not e then
    line("|cff909090Click a recipe to see what it costs to make.|r")
  else
    local item = MadeItem(e)
    local price = AH(item)
    line((KIND_COLOR[e[4]] or "|cffffffff") .. e[1] .. "|r", item and (price and ("sells for " .. Money(price)) or "|cffff6060not on AH|r") or "", item)
    local reag = Reagents(e)
    if not reag then
      line("|cff909090Reagents not recorded yet - open " .. (book.prof or "the profession") .. " on " .. (book.c.name or "this character") .. " once more.|r")
    else
      local total, missing = 0, 0
      for _, r in ipairs(reag) do
        local each, where = UnitCost(r[1])
        local buy = each and each * r[2]
        line(("   %dx %s"):format(r[2], ItemName(r[1])),
          each and (Money(each) .. " ea   " .. Money(buy) .. (where == "vendor" and "  |cffaaaaaa(Vendor)|r" or "")) or "|cffff6060not on AH|r", r[1])
        -- a trade good one of your characters makes (bolts, bars...): what its raw materials cost
        local sub = where ~= "vendor" and MadeFrom(r[1])
        local make
        if sub then
          make = 0
          for _, s2 in ipairs(sub) do
            local e2, w2 = UnitCost(s2[1])
            local n2 = s2[2] * r[2]
            line(("         %dx %s"):format(n2, ItemName(s2[1])), e2 and (Money(e2 * n2) .. (w2 == "vendor" and "  |cffaaaaaa(Vendor)|r" or "")) or "|cffff6060not on AH|r", s2[1])
            if e2 and make then make = make + e2 * n2 else make = nil end
          end
          if make then
            local better = (not buy) or make < buy
            line("         |cffaaaaaaraw materials|r", (better and "|cff40ff40" or "|cffaaaaaa") .. Money(make) .. (buy and better and "  (cheaper)" or "") .. "|r")
          end
        end
        local cost = (make and buy and math.min(make, buy)) or buy or make
        if cost then total = total + cost else missing = missing + 1 end
      end
      line("|cffffd100Cheapest reagents|r", Money(total) .. (missing > 0 and ("  |cffff6060+" .. missing .. " not on AH|r") or ""))
      if price and missing == 0 then
        local p = price - total
        line("|cffffd100Profit if sold|r", (p >= 0 and "|cff40ff40" or "|cffff4040-") .. Money(math.abs(p)) .. "|r")
      end
      if missing > 0 or (item and not price) then line(SCAN_HINT) end
    end
  end
  for i = k + 1, #d.lines do d.lines[i]:Hide() end
end

function NS.RenderBook()
  if not (book and book:IsShown()) then return end
  local c, prof = book.c, book.prof
  local data = c.recipes and c.recipes[prof]
  local filter = (book.search:GetText() or ""):lower()
  local n, shown, lastSection = 0, 0, false
  local function Line()
    n = n + 1
    local l = book.lines[n]
    if not l then
      l = CreateFrame("Button", nil, book.content); l:SetSize(410, 16); l:SetPoint("TOPLEFT", 0, -(n - 1) * 16)
      l.t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l.t:SetPoint("LEFT", 4, 0); l.t:SetWidth(320); l.t:SetJustifyH("LEFT"); l.t:SetWordWrap(false)
      l.p = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l.p:SetPoint("RIGHT", -4, 0); l.p:SetJustifyH("RIGHT")
      l.sel = l:CreateTexture(nil, "BACKGROUND"); l.sel:SetAllPoints(); l.sel:SetColorTexture(0.25, 0.55, 1, 0.3)
      l:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      l:SetScript("OnEnter", function(self) if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, self.link); GameTooltip:Show() end end)
      l:SetScript("OnLeave", function() GameTooltip:Hide() end)
      l:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link); return end
        if self.entry then book.sel = self.entry; NS.RenderBook() end
      end)
      book.lines[n] = l
    end
    l.sel:Hide(); l.p:SetText(""); l.entry = nil
    l:Show(); return l
  end
  book.counts = {}
  if not data then
    local l = Line(); l.link = nil
    l.t:SetText(("|cff909090Not recorded yet - open %s on %s once and it's saved.|r"):format(prof, c.name or "them"))
    book.count:SetText(""); book.foot:SetText("")
  else
    for _, e in ipairs(data.list) do
      local cat = Category(e)
      book.counts[cat] = (book.counts[cat] or 0) + 1
      if (book.cat == "All" or book.cat == cat) and (filter == "" or e[1]:lower():find(filter, 1, true)) then
        if e[3] ~= lastSection then
          lastSection = e[3]
          if e[3] then local h = Line(); h.link = nil; h.t:SetText("|cffffd100" .. e[3] .. "|r") end
        end
        local l = Line(); l.link = e[2]; l.entry = e
        l.t:SetText("   " .. (KIND_COLOR[e[4]] or "|cffffffff") .. e[1] .. "|r")
        local p = AH(MadeItem(e)); l.p:SetText(p and Money(p) or "")
        l.sel:SetShown(e == book.sel)
        shown = shown + 1
      end
    end
    if shown == 0 then local l = Line(); l.link = nil; l.t:SetText("|cff909090No recipes match.|r") end
    book.count:SetText(("%d of %d"):format(shown, #data.list))
    local hasColours = data.list[1] and data.list[1][4]
    book.foot:SetText(hasColours and ("Skill-up colours as of %s, when %s last opened %s. Shift-click a recipe to link it."):format(Ago(data.seen), c.name or "they", prof)
      or ("|cffffd100No skill-up colours yet:|r open %s on %s once more to record them. Shift-click a recipe to link it."):format(prof, c.name or "this character"))
  end
  book.catBtn:SetText("Show: " .. book.cat .. "  v")
  for i = n + 1, #book.lines do book.lines[i]:Hide() end
  book.content:SetHeight(math.max(1, n * 16))
  RenderDetail()
end

---------------------------------------------------------------- Craft Upgrades page: your characters down the left (like the Characters tab)
local upList = {}
function NS.RefreshUpgradeList()
  if not (win and win.upgrades and win.upgrades.list) then return end
  local area = win.upgrades.list
  local chars = {}
  for _, ch in ipairs(L.Characters()) do chars[#chars + 1] = ch end
  table.sort(chars, function(a, b)
    if (a.rec.level or 0) ~= (b.rec.level or 0) then return (a.rec.level or 0) > (b.rec.level or 0) end
    return a.name < b.name
  end)
  local who, alts = (GetUnitName and GetUnitName("player", false) or UnitName("player")), false
  if CraftUpgradesAPI and CraftUpgradesAPI.GetTarget then who, alts = CraftUpgradesAPI.GetTarget() end
  for i, ch in ipairs(chars) do
    local b = upList[i]
    if not b then
      b = CreateFrame("Button", nil, area)
      b:SetSize(126, 24); b:SetPoint("TOPLEFT", 2, -(i - 1) * 26)
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.04)
      b.sel = b:CreateTexture(nil, "BORDER"); b.sel:SetAllPoints(); b.sel:SetColorTexture(0.25, 0.55, 1, 0.35)
      b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 3, 0)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 25, 0); b.text:SetWidth(98); b.text:SetJustifyH("LEFT")
      b:SetScript("OnClick", function(self)
        if CraftUpgradesAPI and CraftUpgradesAPI.SetTarget then CraftUpgradesAPI.SetTarget(self.entry) end
        NS.RefreshUpgradeList()
      end)
      b:SetScript("OnEnter", function(self) if NS.CharTooltip then NS.CharTooltip(self, "Click to see craftable upgrades for this character") end end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      upList[i] = b
    end
    b.entry = ch
    b.char = ch.rec; ch.rec.name = ch.rec.name or ch.name; ch.rec.realm = ch.rec.realm or ch.realm
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[ch.rec.classFile or ""]
    if tc then b.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"); b.icon:SetTexCoord(unpack(tc)); b.icon:Show() else b.icon:Hide() end
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.rec.classFile or ""]
    b.text:SetText((col and ("|c" .. (col.colorStr or "ffffffff")) or "") .. ch.name .. (col and "|r" or "") .. " |cff40ff40" .. (ch.rec.level or "?") .. "|r")
    b.sel:SetShown(ch.name == who)          -- in Craft for Alts mode: the crafter
    b:Show()
  end
  for i = #chars + 1, #upList do upList[i]:Hide() end
end
function NS.BuildUpgradeList()
  if win.upgrades.list then NS.RefreshUpgradeList(); return end
  local area = CreateFrame("Frame", nil, win.upgrades)
  area:SetPoint("TOPLEFT", 0, -4); area:SetPoint("BOTTOMLEFT"); area:SetWidth(130)
  win.upgrades.list = area
  local hint = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", 4, 4); hint:SetWidth(122); hint:SetJustifyH("LEFT")
  hint:SetText("Pick whose upgrades to see - or, with Craft for Alts on, who's crafting.")
  if CraftUpgradesAPI then CraftUpgradesAPI.OnChange = NS.RefreshUpgradeList end
  NS.RefreshUpgradeList()
end

local function CreateWindow()
  win = CreateFrame("Frame", "PintsLedgerFrame", UIParent, "BackdropTemplate")
  win:SetSize(W, H); win:SetPoint("CENTER"); win:SetFrameStrata("HIGH"); win:SetToplevel(true)
  Backdrop(win)
  win:EnableMouse(true); win:SetMovable(true); win:SetClampedToScreen(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "PintsLedgerFrame")
  -- the recipe book and its menu go with it
  win:HookScript("OnHide", function() if book then book:Hide(); if book.menu then book.menu:Hide() end end end)

  local logo = win:CreateTexture(nil, "ARTWORK"); logo:SetSize(34, 34); logo:SetPoint("TOPLEFT", 16, -14)
  logo:SetTexture("Interface\\Icons\\INV_Drink_05"); logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("LEFT", logo, "RIGHT", 10, 6); title:SetText("|cffd4a017Pint's|r Alts")
  local sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -2); sub:SetText("Every character on your account, at a glance")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() win:Hide() end)   -- (hide it directly: the game's own close goes through a path combat can block)

  -- search: every character's bags, bank and mail, plus recorded guild banks
  searchBox = CreateFrame("EditBox", "PintsLedgerSearchBox", win, "InputBoxTemplate")
  searchBox:SetSize(230, 22); searchBox:SetPoint("TOPRIGHT", -44, -20); searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(60)
  local mag = searchBox:CreateTexture(nil, "OVERLAY"); mag:SetSize(14, 14); mag:SetPoint("RIGHT", searchBox, "LEFT", -4, 0)
  mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  searchBox.ph = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); searchBox.ph:SetPoint("LEFT", 2, 0)
  searchBox.ph:SetText("Search items on all characters...")
  win.search = CreateFrame("Frame", nil, win)
  win.search:SetPoint("TOPLEFT", 12, -58); win.search:SetPoint("BOTTOMRIGHT", -12, 44); win.search:Hide()
  local sr = win.search
  sr.info = sr:CreateFontString(nil, "OVERLAY", "GameFontNormal"); sr.info:SetPoint("TOPLEFT", 8, -4)
  sr.hint = sr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sr.hint:SetPoint("TOPRIGHT", -30, -6)
  sr.hint:SetText("Click a result to open that character's bags  -  Esc clears")
  local ssf = CreateFrame("ScrollFrame", "PintsLedgerSearchScroll", sr, "UIPanelScrollFrameTemplate")
  ssf:SetPoint("TOPLEFT", 0, -26); ssf:SetPoint("BOTTOMRIGHT", -26, 0)
  sr.list = CreateFrame("Frame", nil, ssf); sr.list:SetSize(W - 60, 1); ssf:SetScrollChild(sr.list)
  local srows = {}
  local function SRow(i)
    local r = srows[i]
    if r then return r end
    r = CreateFrame("Button", nil, sr.list); r:SetSize(W - 60, 22); r:SetPoint("TOPLEFT", 0, -(i - 1) * 23)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 4, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("LEFT", 30, 0); r.name:SetWidth(330); r.name:SetJustifyH("LEFT")
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.count:SetPoint("LEFT", 370, 0); r.count:SetWidth(60); r.count:SetJustifyH("RIGHT")
    r.who = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.who:SetPoint("LEFT", 450, 0); r.who:SetWidth(300); r.who:SetJustifyH("LEFT")
    r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisable"); r.where:SetPoint("LEFT", 760, 0); r.where:SetWidth(170); r.where:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
      if not self.res then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.res.id); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
      local res = self.res
      if not res then return end
      local realmName, charName, subKey = res.realm, res.who, "bags"
      if res.guild then
        charName, subKey = nil, "guild"
        for _, ch in ipairs(L.Characters(true)) do
          if ch.realm == res.realm and ch.rec.guild == res.guild then charName = ch.name; break end
        end
        if not charName then return end
      end
      ShowTab("characters")
      if NS.SelectCharacter then NS.SelectCharacter(realmName, charName, subKey) end
    end)
    srows[i] = r
    return r
  end
  local MAXR = 300
  RunSearch = function()
    local text = searchBox:GetText() or ""
    if #text < 2 then return end
    local res = L.Search(text)
    local n = math.min(#res, MAXR)
    sr.info:SetText(#res == 0 and ("No items match \"" .. text .. "\"") or
      (#res .. " result" .. (#res == 1 and "" or "s") .. " for \"" .. text .. "\"" .. (#res > MAXR and ("  (showing first " .. MAXR .. ")") or "")))
    for i = 1, n do
      local e, r = res[i], SRow(i)
      r.res = e
      local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(e.id)
      r.icon:SetTexture(icon or (GetItemIconByID and GetItemIconByID(e.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
      local cr, cg, cb = 1, 1, 1
      if quality and GetItemQualityColor then cr, cg, cb = GetItemQualityColor(quality) end
      r.name:SetText(e.name); r.name:SetTextColor(cr, cg, cb)
      r.count:SetText("x" .. (e.count or 1))
      local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
      r.who:SetText(e.who .. ((e.realm ~= select(1, L.Me())) and ("  |cff909090(" .. e.realm .. ")|r") or ""))
      if cc then r.who:SetTextColor(cc.r, cc.g, cc.b) else r.who:SetTextColor(0.4, 1, 0.4) end
      r.where:SetText(e.where)
      r:Show()
    end
    for i = n + 1, #srows do srows[i]:Hide() end
    sr.list:SetHeight(math.max(1, n * 23))
  end
  local pending
  searchBox:SetScript("OnTextChanged", function(self)
    self.ph:SetShown(self:GetText() == "" and not self:HasFocus())
    if self.quiet then return end
    local text = self:GetText() or ""
    if #text < 2 then
      if sr:IsShown() then ShowTab(currentTab or "ledger") end
      return
    end
    if not sr:IsShown() then
      win.ledger:Hide(); win.chars:Hide(); win.upgrades:Hide()
      for _, t in pairs(tabs) do t.sel:Hide() end
      sr:Show()
    end
    pending = (pending or 0) + 1
    local mine = pending
    C_Timer.After(0.3, function() if mine == pending then RunSearch() end end)
  end)
  searchBox:SetScript("OnEditFocusGained", function(self) self.ph:Hide() end)
  searchBox:SetScript("OnEditFocusLost", function(self) self.ph:SetShown(self:GetText() == "") end)
  searchBox:SetScript("OnEscapePressed", function(self)
    if self:GetText() ~= "" then self:SetText("") end
    self:ClearFocus()
  end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  -- item names that weren't cached yet: re-run once they arrive
  sr:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  sr:SetScript("OnEvent", function()
    if not sr:IsShown() then return end
    pending = (pending or 0) + 1
    local mine = pending
    C_Timer.After(0.4, function() if mine == pending and sr:IsShown() then RunSearch() end end)
  end)

  -- ledger page
  win.ledger = CreateFrame("Frame", nil, win)
  win.ledger:SetPoint("TOPLEFT", 12, -58); win.ledger:SetPoint("BOTTOMRIGHT", -12, 44)
  win.nav = {}
  for i, key in ipairs(viewOrder) do
    local b = CreateFrame("Button", nil, win.ledger)
    b:SetSize(NAVW - 10, 28); b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 32)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.05)
    b.sel = b:CreateTexture(nil, "BORDER"); b.sel:SetAllPoints(); b.sel:SetColorTexture(0.25, 0.55, 1, 0.35); b.sel:Hide()
    local bar = b:CreateTexture(nil, "ARTWORK"); bar:SetSize(3, 28); bar:SetPoint("LEFT"); bar:SetColorTexture(1, 0.82, 0, 0.8)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetPoint("LEFT", 12, 0); b.text:SetText(views[key].label)
    b:SetScript("OnClick", function() SelectView(key) end)
    win.nav[key] = b
  end
  local sep = win.ledger:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(1, 0.82, 0, 0.3); sep:SetWidth(1)
  sep:SetPoint("TOPLEFT", NAVW, 0); sep:SetPoint("BOTTOMLEFT", NAVW, 30)

  content = CreateFrame("Frame", nil, win.ledger)
  content:SetPoint("TOPLEFT", NAVW + 8, 0); content:SetPoint("BOTTOMRIGHT", 0, 30)
  header = CreateFrame("Frame", nil, content); header:SetHeight(26)
  header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT", -22, 0)
  local hl = header:CreateTexture(nil, "ARTWORK"); hl:SetColorTexture(1, 0.82, 0, 0.35); hl:SetHeight(1)
  hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT")
  local sf = CreateFrame("ScrollFrame", "PintsLedgerScroll", content, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -30); sf:SetPoint("BOTTOMRIGHT", -24, 0)
  rowsFrame = CreateFrame("Frame", nil, sf); rowsFrame:SetSize(W - NAVW - 44, 1)
  sf:SetScrollChild(rowsFrame)
  rowsFrame:SetScript("OnShow", nil)
  -- row interaction (delegated)
  local function hookRow(r)
    if r.hooked then return end
    r.hooked = true
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
      if self.realmName then collapsed[self.realmName] = not collapsed[self.realmName]; Refresh(); return end
      -- a profession in the Skills view: open that character's recipe book
      if self.char and button == "LeftButton" and not IsShiftKeyDown() then
        local view = views[currentView]
        local x = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
        local cx = 28
        for _, col in ipairs(view.cols) do
          if x >= cx and x < cx + col[2] then
            local prof = col.book and col.book(self.char)
            if prof then NS.OpenBook(self.char, prof) end
            break
          end
          cx = cx + col[2]
        end
      end
      if self.char and button == "RightButton" and IsShiftKeyDown() then
        if IsMe(self.char) then return end
        local d = StaticPopup_Show("PINTSLEDGER_FORGET", self.char.name)
        if d then d.data = { realm = self.char.realm, name = self.char.name } end
      end
    end)
  end
  local origGetRow = GetRow
  GetRow = function(i) local r = origGetRow(i); hookRow(r); return r end

  footer = CreateFrame("Frame", nil, win.ledger, "BackdropTemplate")
  footer:SetPoint("BOTTOMLEFT", NAVW + 8, 0); footer:SetPoint("BOTTOMRIGHT", 0, 0); footer:SetHeight(26)
  footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); footer:SetBackdropColor(1, 0.82, 0, 0.06)
  footer.text = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); footer.text:SetPoint("RIGHT", -10, 0)
  local hint = win.ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 8, 8); hint:SetWidth(NAVW - 12); hint:SetJustifyH("LEFT")
  hint:SetText("Log into each character once to add it.")

  -- characters page (built by Characters.lua on first use)
  win.chars = CreateFrame("Frame", nil, win)
  win.chars:SetPoint("TOPLEFT", 12, -58); win.chars:SetPoint("BOTTOMRIGHT", -12, 44); win.chars:Hide()

  -- upgrades page (Craft Upgrades docks here)
  win.upgrades = CreateFrame("Frame", nil, win)
  win.upgrades:SetPoint("TOPLEFT", 12, -58); win.upgrades:SetPoint("BOTTOMRIGHT", -12, 44); win.upgrades:Hide()
  win.upgrades.missing = win.upgrades:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.upgrades.missing:SetPoint("CENTER"); win.upgrades.missing:SetText("Pint's Craft Upgrades isn't installed or enabled.")

  -- bottom tabs
  local tabDefs = { { "ledger", "Ledger" }, { "characters", "Characters" }, { "upgrades", "Craft Upgrades" } }
  local tx = 16
  for _, td in ipairs(tabDefs) do
    local t = CreateFrame("Button", nil, win, "BackdropTemplate")
    t:SetSize(150, 30); t:SetPoint("BOTTOMLEFT", tx, 10)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    t:SetBackdropColor(0.15, 0.12, 0.05, 0.9); t:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    t.sel = t:CreateTexture(nil, "ARTWORK"); t.sel:SetPoint("TOPLEFT", 3, -3); t.sel:SetPoint("BOTTOMRIGHT", -3, 3)
    t.sel:SetColorTexture(0.25, 0.55, 1, 0.35); t.sel:Hide()
    t:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t.text:SetPoint("CENTER"); t.text:SetText(td[2])
    t:SetScript("OnClick", function() ShowTab(td[1]) end)
    tabs[td[1]] = t
    tx = tx + 156
  end

  win:SetScript("OnShow", function() ShowTab(currentTab or "ledger") end)
  win:SetScript("OnHide", function()
    if book then book:Hide(); if book.menu then book.menu:Hide() end end      -- the recipe book goes with it
    if currentTab == "upgrades" then ShowTab("ledger"); currentTab = "upgrades" end
  end)
  win:Hide()
  SelectView(PintsLedgerDB.ui.view or "roster")
end

function L.Toggle(tab)
  if not win then CreateWindow() end
  if tab then currentTab = tab end
  if win:IsShown() and not tab then win:Hide() else win:Show(); if tab then ShowTab(tab) end end
end

SLASH_PINTSLEDGER1 = "/alts"
SLASH_PINTSLEDGER2 = "/ledger"
SLASH_PINTSLEDGER3 = "/pl"
SlashCmdList.PINTSLEDGER = function(msg)
  if (msg or ""):lower():match("^%s*combat%s*$") then
    PintsLedgerDB.ui.keepInCombat = not PintsLedgerDB.ui.keepInCombat
    print("|cffd4a017Pint's Alts:|r " .. (PintsLedgerDB.ui.keepInCombat and "stays open in combat." or "closes when a fight starts."))
    return
  end
  L.Toggle()
end
-- a fight starts: the window (and its gear list) get out of the way (/alts combat keeps them open instead)
do
  local f = CreateFrame("Frame"); f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:SetScript("OnEvent", function()
    if PintsLedgerDB and PintsLedgerDB.ui and PintsLedgerDB.ui.keepInCombat then return end
    local w = _G.PintsLedgerFrame
    if w and w:IsShown() then w:Hide() end
    if NS.Try and NS.Try.HidePicker then NS.Try.HidePicker() end
    if _G.PintsLedgerBook and _G.PintsLedgerBook:IsShown() then _G.PintsLedgerBook:Hide() end
  end)
end

---------------------------------------------------------------- minimap button
local mm = CreateFrame("Frame")
mm:RegisterEvent("PLAYER_LOGIN")
mm:SetScript("OnEvent", function()
  local store = PintsLedgerDB.minimap
  local icon = "Interface\\Icons\\INV_Drink_05"
  local function Tip(tt)
    tt:AddLine("|cffd4a017Pint's|r Alts")
    tt:AddLine("Left-click: open the ledger", 1, 1, 1)
    tt:AddLine("Right-click: Craft Upgrades", 1, 1, 1)
  end
  local function Click(button) if button == "RightButton" then L.Toggle("upgrades") else L.Toggle() end end
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDB and Icon then
    local obj = LDB:NewDataObject("PintsLedger", { type = "launcher", text = "Pint's Alts", icon = icon,
      OnClick = function(_, b) Click(b) end, OnTooltipShow = Tip })
    Icon:Register("PintsLedger", obj, store)
    return
  end
  local b = CreateFrame("Button", "PintsLedgerMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(icon); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  local function Place() local a = math.rad(store.angle or 180); b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a)) end
  Place()
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
    store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place() end) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn) Click(btn) end)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end)
