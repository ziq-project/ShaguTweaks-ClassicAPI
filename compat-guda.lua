local _G = ShaguTweaks.GetGlobalEnv()
local API = ShaguTweaks.API
local AddBorder = ShaguTweaks.AddBorder
local hooksecurefunc = ShaguTweaks.hooksecurefunc
local HookAddonOrVariable = ShaguTweaks.HookAddonOrVariable

local Engine = ShaguTweaks.ItemRarityEngine
if not Engine then return end

local defaultColor = { r = .5, g = .5, b = .46 }

local function HideTexture(texture)
  if texture and texture.Hide then texture:Hide() end
end

local function HideGudaRarity(button)
  if not button then return end

  -- Guda draws its own quality border and four-edge inner rarity shadow.
  -- Hide only those rarity visuals so ShaguTweaks can be the single source
  -- of border/glow styling while either ShaguTweaks rarity module is active.
  if button._qualityBorder then
    button._qualityBorder:Hide()
  end

  local shadow = button.innerShadow
  if shadow then
    HideTexture(shadow.top)
    HideTexture(shadow.bottom)
    HideTexture(shadow.left)
    HideTexture(shadow.right)
  end
end

local function HideShaguRarity(button)
  if not button then return end
  if button.ShaguTweaks_border then button.ShaguTweaks_border:Hide() end
  if button.ShaguTweaks_itemRarityGlow then button.ShaguTweaks_itemRarityGlow:Hide() end
end

local function EnsureGlow(button)
  if not button then return end
  if button.ShaguTweaks_itemRarityGlow then
    return button.ShaguTweaks_itemRarityGlow
  end

  -- Keep this identical to Item Rarity Glows in mods/item-colors.lua.
  local inset = 14
  local texture = button:CreateTexture(nil, "OVERLAY")
  texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  texture:SetBlendMode("ADD")
  texture:SetPoint("TOPLEFT", button, "TOPLEFT", -inset, inset)
  texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", inset, -inset)
  texture:Hide()

  button.ShaguTweaks_itemRarityGlow = texture
  Engine.glowTextures = Engine.glowTextures or {}
  table.insert(Engine.glowTextures, texture)
  return texture
end

local function GetGudaItemID(button, bagID, slotID, itemData)
  local data = button and button.itemData or itemData

  if data then
    if data.itemID then
      local itemID = tonumber(data.itemID)
      if itemID then return itemID end
    end

    if data.link and API.GetItemIDFromLink then
      local itemID = API.GetItemIDFromLink(data.link)
      if itemID then return itemID end
    end
  end

  bagID = tonumber(bagID)
  slotID = tonumber(slotID)
  if bagID and slotID and API.GetContainerItemID then
    return API.GetContainerItemID(bagID, slotID)
  end
end

local function GetGudaQuality(itemID, itemData)
  if itemID and API.GetItemQualityByID then
    local quality = API.GetItemQualityByID(itemID)
    if quality ~= nil then return quality end
  end

  if itemData and itemData.quality ~= nil then
    return tonumber(itemData.quality)
  end
end

local function IsQuestItem(itemID)
  if not itemID or not API.GetItemInfoInstant then return false end
  local _, _, _, _, _, classID = API.GetItemInfoInstant(itemID)
  return classID == 12
end

local function RefreshGudaButton(button, bagID, slotID, itemData, isBank)
  if not button then return end

  -- If both ShaguTweaks rarity modules are disabled, leave Guda completely
  -- untouched. Also clear any stale Shagu visuals if settings changed live.
  if not Engine.borders and not Engine.glows then
    HideShaguRarity(button)
    return
  end

  -- Guda reuses pooled buttons for items and placeholders. Never paint rarity
  -- visuals onto an empty/category placeholder, and clear stale pooled state.
  if not button.hasItem then
    HideShaguRarity(button)
    return
  end

  HideGudaRarity(button)

  local data = button.itemData or itemData
  local itemID = GetGudaItemID(button, bagID, slotID, data)
  local quality = GetGudaQuality(itemID, data)
  local quest = IsQuestItem(itemID)
  local r, g, b
  local hasRarity = false
  local borderMin = isBank and 2 or 0

  if quest then
    r, g, b = 1, 1, 0
    hasRarity = true
  elseif quality ~= nil and quality >= borderMin then
    r, g, b = GetItemQualityColor(quality)
    hasRarity = true
  end

  if Engine.borders then
    local border = AddBorder(button, 3, defaultColor)
    if border then
      if hasRarity then
        border:SetBackdropBorderColor(r, g, b, 1)
      else
        border:SetBackdropBorderColor(defaultColor.r, defaultColor.g, defaultColor.b, 1)
      end
      border:Show()
    end
  elseif button.ShaguTweaks_border then
    button.ShaguTweaks_border:Hide()
  end

  if Engine.glows then
    local glow = EnsureGlow(button)
    if glow then
      local glowRarity = quest or (quality ~= nil and quality >= 2)
      if glowRarity then
        if not quest then r, g, b = GetItemQualityColor(quality) end
        glow:SetVertexColor(r, g, b, .7)
        glow:Show()
      else
        glow:Hide()
      end
    end
  elseif button.ShaguTweaks_itemRarityGlow then
    button.ShaguTweaks_itemRarityGlow:Hide()
  end
end

HookAddonOrVariable("Guda", function()
  if type(_G.Guda_ItemButton_SetItem) ~= "function" then return end

  -- Guda already refreshes a pooled button exactly when its item assignment
  -- changes. Post-hook that path instead of scanning bags or adding OnUpdate.
  hooksecurefunc("Guda_ItemButton_SetItem", RefreshGudaButton)
end)
