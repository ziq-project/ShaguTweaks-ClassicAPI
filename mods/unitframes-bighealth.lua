local T = ShaguTweaks.T
local hooksecurefunc = hooksecurefunc or ShaguTweaks.hooksecurefunc

local module = ShaguTweaks:register({
  title = T["Unit Frame Big Health"],
  description = T["Increases the healthbar of the player and target unitframe."],
  expansions = { ["vanilla"] = true },
  category = T["Unit Frames"],
  enabled = nil,
})

local addonpath
local tocs = { "", "-master", "-tbc", "-wotlk" }
for i = 1, table.getn(tocs) do
  local current = string.format("ShaguTweaks%s", tocs[i])
  local _, title = GetAddOnInfo(current)
  if title then
    addonpath = "Interface\\AddOns\\" .. current
    break
  end
end
addonpath = addonpath or "Interface\\AddOns\\ShaguTweaks"

module.enable = function(self)
  local normalTexture = addonpath .. "\\img\\UI-TargetingFrame"
  local eliteTexture = addonpath .. "\\img\\UI-TargetingFrame-Elite"
  local rareTexture = addonpath .. "\\img\\UI-TargetingFrame-Rare"

  -- Darkened UI and Big Health can be enabled in either order because modules
  -- are initialized from an unordered table. If Darkened UI ran first, Big
  -- Health replaces the already-darkened textures with fresh bright ones.
  -- Apply the configured dark tint directly to our replacement textures so the
  -- result is deterministic without adding any permanent OnUpdate work.
  local function ApplyDarkModeTextures()
    if not ShaguTweaks.DarkMode then return end

    local darkModule = ShaguTweaks.mods[T["Darkened UI"]]
    local color = ShaguTweaks_config
      and ShaguTweaks_config.overwrites
      and ShaguTweaks_config.overwrites["darkmode.color"]

    color = color
      or (darkModule and darkModule.config and darkModule.config["darkmode.color"])

    if not color then return end

    local r = tonumber(color.r) or color.r
    local g = tonumber(color.g) or color.g
    local b = tonumber(color.b) or color.b
    local a = tonumber(color.a) or color.a or 1

    if PlayerFrameTexture then PlayerFrameTexture:SetVertexColor(r, g, b, a) end
    if PlayerStatusTexture then PlayerStatusTexture:SetVertexColor(r, g, b, a) end
    if TargetFrameTexture then TargetFrameTexture:SetVertexColor(r, g, b, a) end
  end

  -- Big Health is presentation-only. Numeric health/power values are owned by
  -- the independent Real Health Numbers module.
  --
  -- (2026-09-10, reported on Project Legacy, round 2): leaving
  -- PlayerFrameTexture completely untouched (the first attempt at this fix)
  -- avoided erasing the server's Prestige border, but broke the frame art
  -- itself -- the default border texture's health/mana divider line is
  -- drawn for the STOCK (thin) bar height, so once PlayerFrameHealthBar
  -- grew to 30px that divider line now sits visibly across the MIDDLE of
  -- the enlarged bar (see the reported screenshot). The addon's own
  -- normalTexture/eliteTexture/rareTexture assets exist specifically to
  -- avoid that -- they're redrawn to fit the taller bar -- so the border
  -- swap is genuinely needed, just not as a one-shot overwrite.
  --
  -- Project Legacy's Prestige tiers are described as "rare mob border" /
  -- "elite character frame" -- the exact vanilla vocabulary for the stock
  -- Interface\TargetingFrame\UI-TargetingFrame[-Elite|-Rare] border
  -- textures, just applied to the PLAYER's own frame instead of a target's.
  -- That's the same asset-naming convention this addon's own replacement
  -- textures already follow. So instead of setting PlayerFrameTexture once,
  -- hook its SetTexture and, whenever something (Prestige, a rank-up, a
  -- relog) sets it to a recognizable stock/default border path, immediately
  -- substitute our matching tall-bar-fitted asset of the SAME tier -- this
  -- keeps the correct Prestige tier visible AND keeps the border
  -- proportioned for the taller bar, whenever that texture gets (re)applied.
  -- Not yet confirmed in-game -- please test and report back.
  local ourTextures = { [normalTexture]=true, [eliteTexture]=true, [rareTexture]=true }

  local function ClassifyBorderPath(path)
    if not path then return nil end
    local lower = string.lower(path)
    if string.find(lower, "elite", 1, true) then return eliteTexture end
    if string.find(lower, "rare", 1, true) then return rareTexture end
    if string.find(lower, "targetingframe", 1, true) then return normalTexture end
    return nil
  end

  -- Same substitution, reused for both PlayerFrameTexture and
  -- TargetFrameTexture -- see the note above and the one on
  -- UpdateTargetClassificationTexture below (2026-09-10, round 3): Prestige
  -- apparently isn't limited to the player's OWN frame -- targeting another
  -- player who has a Prestige rank looked just as broken as the player frame
  -- did before this same fix, while NPC targets were already fine. So the
  -- TargetFrameTexture needs the identical hook.
  local function MakeBorderReplacer(frameTexture)
    local applying = false
    return function(_, path)
      if applying or ourTextures[path] then return end
      local replacement = ClassifyBorderPath(path)
      if not replacement or replacement == path then return end
      applying = true
      frameTexture:SetTexture(replacement)
      applying = false
    end
  end

  local ReplacePlayerBorder = MakeBorderReplacer(PlayerFrameTexture)
  local ReplaceTargetBorder = MakeBorderReplacer(TargetFrameTexture)

  hooksecurefunc(PlayerFrameTexture, "SetTexture", ReplacePlayerBorder)
  hooksecurefunc(TargetFrameTexture, "SetTexture", ReplaceTargetBorder)
  -- Apply once immediately too, in case Prestige (or the stock default) has
  -- already set the border before this module got enabled.
  ReplacePlayerBorder(nil, PlayerFrameTexture:GetTexture())

  PlayerFrameHealthBar:SetPoint("TOPLEFT", 106, -22)
  PlayerFrameHealthBar:SetHeight(30)

  PlayerStatusTexture:SetTexture(addonpath .. "\\img\\UI-Player-Status")

  TargetFrameTexture:SetTexture(normalTexture)
  TargetFrameHealthBar:SetPoint("TOPRIGHT", -106, -22)
  TargetFrameHealthBar:SetHeight(30)

  ApplyDarkModeTextures()

  local world = CreateFrame("Frame")
  world:RegisterEvent("PLAYER_ENTERING_WORLD")
  world:SetScript("OnEvent", function()
    ApplyDarkModeTextures()
    this:UnregisterAllEvents()
  end)

  -- Delay hook installation by one frame so all enabled unit-frame modules have
  -- finished their setup first. This keeps hooks attached to final handlers.
  local deferred = CreateFrame("Frame")
  deferred:SetScript("OnUpdate", function()
    this:SetScript("OnUpdate", nil)
    this:Hide()

    local function UpdateTargetClassificationTexture()
      -- (2026-09-10, round 3): reported broken specifically when targeting
      -- players (self or others), while NPC targets were already fine.
      -- UnitClassification is a mob-only concept -- it's always "normal" for
      -- a player -- so this used to force TargetFrameTexture back to
      -- normalTexture on every single TargetFrame_CheckClassification firing,
      -- which happens for player targets too. If Project Legacy's Prestige
      -- system also marks OTHER players' target frames with a rare/elite
      -- border (matching what it already does to the player's own frame --
      -- see the PlayerFrameTexture note above), that unconditional reset
      -- wiped it out immediately. Leave whatever's already on the frame
      -- alone for player targets -- ReplaceTargetBorder (hooked above) still
      -- reshapes it to our tall-bar-fitted asset if Prestige (or anything
      -- else) sets it to a recognizable stock border path, without this
      -- classification logic fighting over which tier to show.
      if UnitIsPlayer("target") then
        ApplyDarkModeTextures()
        return
      end

      local classification = UnitClassification("target")
      if classification == "worldboss"
        or classification == "rareelite"
        or classification == "elite" then
        TargetFrameTexture:SetTexture(eliteTexture)
      elseif classification == "rare" then
        TargetFrameTexture:SetTexture(rareTexture)
      else
        TargetFrameTexture:SetTexture(normalTexture)
      end

      ApplyDarkModeTextures()
    end

    hooksecurefunc("TargetFrame_CheckClassification", UpdateTargetClassificationTexture)

    local playerSetStatusBarColor = PlayerFrameHealthBar.SetStatusBarColor
    local targetSetStatusBarColor = TargetFrameHealthBar.SetStatusBarColor

    local function ApplyPlayerHealthColor()
      if not PlayerFrameNameBackground or not playerSetStatusBarColor then return end
      local r, g, b, a = PlayerFrameNameBackground:GetVertexColor()
      playerSetStatusBarColor(PlayerFrameHealthBar, r, g, b, a)
    end

    local function ApplyTargetHealthColor()
      if not TargetFrameNameBackground or not targetSetStatusBarColor then return end
      local r, g, b, a = TargetFrameNameBackground:GetVertexColor()
      targetSetStatusBarColor(TargetFrameHealthBar, r, g, b, a)
    end

    -- Keep the Big Health colors without replacing SetStatusBarColor with a
    -- no-op. Other addons may still call the original method normally.
    if PlayerFrameNameBackground then
      hooksecurefunc(PlayerFrameHealthBar, "SetStatusBarColor", ApplyPlayerHealthColor)
      hooksecurefunc(PlayerFrameNameBackground, "Show", function()
        PlayerFrameNameBackground:Hide()
      end)
      PlayerFrameNameBackground:Hide()
      ApplyPlayerHealthColor()
    end

    if TargetFrameNameBackground then
      hooksecurefunc(TargetFrameHealthBar, "SetStatusBarColor", ApplyTargetHealthColor)
      hooksecurefunc(TargetFrameNameBackground, "Show", function()
        TargetFrameNameBackground:Hide()
      end)
      TargetFrameNameBackground:Hide()
      ApplyTargetHealthColor()
    end

    hooksecurefunc("TargetFrame_CheckFaction", ApplyTargetHealthColor)

    UpdateTargetClassificationTexture()
    TargetFrame_CheckFaction()
  end)
end
