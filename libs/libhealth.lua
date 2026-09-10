local _G = ShaguTweaks.GetGlobalEnv()

-- Real-health fallback for stock Vanilla servers.
--
-- Turtle WoW and some custom clients expose real UnitHealth/UnitHealthMax
-- values directly. Stock 1.12 often exposes target health as 0..100 instead.
-- Keep the original ShaguTweaks estimation idea, but leave it completely
-- dormant until Real Health Numbers asks for it and only listen to combat/
-- health events while the current target actually needs estimation.

local mobdb = {}
local targetKey
local damage = 0
local percent = 0

local libhealth = CreateFrame("Frame")
libhealth.enabled = false
libhealth.reqhit = 2
libhealth.reqdmg = 10

local function InitCache()
  ShaguTweaks_cache = ShaguTweaks_cache or {}
  ShaguTweaks_cache["libhealth"] = ShaguTweaks_cache["libhealth"] or {}
  mobdb = ShaguTweaks_cache["libhealth"]
end

local function IsPercentHealth(unit)
  if not unit or not UnitExists(unit) then return false end

  local cur = _G.UnitHealth(unit)
  local max = _G.UnitHealthMax(unit)

  return cur ~= nil and max == 100 and cur <= 100
end

local function StopSampling()
  libhealth:UnregisterEvent("UNIT_COMBAT")
  libhealth:UnregisterEvent("UNIT_HEALTH")
end

local function StartSampling()
  libhealth:RegisterEvent("UNIT_COMBAT")
  libhealth:RegisterEvent("UNIT_HEALTH")
end

local function SelectTarget()
  StopSampling()

  damage = 0
  percent = _G.UnitHealth("target") or 0
  targetKey = nil

  if not IsPercentHealth("target") then return end

  local name = UnitName("target")
  local level = UnitLevel("target")
  if not name or not level then return end

  targetKey = string.format("%s:%s", name, level)
  StartSampling()
end

local function GetCachedHealth(unitstr, cur, max)
  local name = UnitName(unitstr)
  local level = UnitLevel(unitstr)
  if not name or not level then return cur, max end

  local key = string.format("%s:%s", name, level)
  local data = mobdb[key]
  if data and data[1] and data[2]
    and data[2] > libhealth.reqdmg
    and (not data[3] or data[3] > libhealth.reqhit) then
    return ceil(data[1] / 100 * cur), data[1], true
  end

  return cur, max
end

-- DIAGNOSED (2026-09-10, reported on Project Legacy, from git history + the
-- reported symptom -- not yet re-confirmed in-game after this fix): this
-- used to also try _G.UnitHealthMissing(unitstr) as an "immediate" real-
-- deficit estimate
-- before falling back to the historical combat estimator, on the assumption
-- that ClassicAPI's UnitHealthMissing exposes the true absolute HP deficit
-- even when stock UnitHealth() only reports a 0-100 percentage. On this
-- server it doesn't -- it returns the same percentage-based deficit
-- (100 - cur) that UnitHealth() itself is already restricted to for
-- ungrouped hostile targets (the server simply never sends real mob HP to
-- the client, so no client-side API can conjure it up). Feeding that into
-- the "missing/lostPercent*100" ratio below always landed on
-- estimatedMax ~= 100 -- i.e. just the raw percent again -- but got
-- returned with known=true, so the caller (health-numbers.lua) skipped its
-- own "show it as an honest percent" fallback and displayed the bare
-- percent NUMBER with no "%" sign, looking like a broken/truncated value.
-- Removed entirely -- the historical combat-sample estimator (GetCachedHealth
-- below, unchanged since before this regression) is the only source of a
-- real absolute-HP guess on this server; everything else should honestly
-- fall through to the caller's percent display.
function libhealth:GetUnitHealth(unitstr)
  -- Preserve the old public library behavior for external consumers while
  -- keeping the estimator lazy: the first actual query activates it.
  if not self.enabled then self:Enable() end

  local cur = _G.UnitHealth(unitstr)
  local max = _G.UnitHealthMax(unitstr)

  if not cur or not max then return cur or 0, max or 0 end

  -- Real values are already available: do not estimate.
  if cur > 100 or max > 100 or max < 100 then
    return cur, max, true
  end

  return GetCachedHealth(unitstr, cur, max)
end

function libhealth:GetUnitHealthByName(name, level, cur, max)
  if not self.enabled then self:Enable() end

  if not cur or not max then return cur or 0, max or 0 end

  if cur > 100 or max > 100 or max < 100 then
    return cur, max, true
  end

  if not name or not level then return cur, max end

  local key = string.format("%s:%s", name, level)
  local data = mobdb[key]
  if data and data[1] and data[2]
    and data[2] > libhealth.reqdmg
    and (not data[3] or data[3] > libhealth.reqhit) then
    return ceil(data[1] / 100 * cur), data[1], true
  end

  return cur, max
end

function libhealth:Enable()
  if self.enabled then return end
  self.enabled = true

  InitCache()

  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  SelectTarget()
end

function libhealth:Disable()
  if not self.enabled then return end
  self.enabled = false

  self:UnregisterAllEvents()
  targetKey = nil
  damage = 0
  percent = 0
end

libhealth:SetScript("OnEvent", function()
  if not libhealth.enabled then return end

  if event == "PLAYER_ENTERING_WORLD" then
    InitCache()
    SelectTarget()
  elseif event == "PLAYER_TARGET_CHANGED" then
    SelectTarget()
  elseif targetKey and event == "UNIT_COMBAT" and arg1 == "target" then
    if arg2 == "HEAL" then return end

    local amount = tonumber(arg4) or 0
    if amount > 0 then
      damage = damage + amount
    end
  elseif targetKey and event == "UNIT_HEALTH" and arg1 == "target" then
    local currentPercent = _G.UnitHealth("target") or 0
    local diff = percent - currentPercent

    if damage > 0 and diff > 0 then
      local estimate = ceil(damage / diff * 100)
      local data = mobdb[targetKey]

      if not data or not data[2] or diff > data[2] then
        mobdb[targetKey] = {
          estimate,
          diff,
          data and data[3] and data[3] + 1 or 1,
        }
      elseif data then
        data[3] = data[3] and data[3] + 1 or 1
      end
    end

    damage = 0
    percent = currentPercent
  end
end)

ShaguTweaks.libhealth = libhealth
