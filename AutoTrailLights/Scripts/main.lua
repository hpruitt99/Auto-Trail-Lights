-- Auto Trail Lights for Ski-E-O! Ski Resort Tycoon (UE4SS Lua mod)
-- Adds a "Trail lights" section to a trail's panel (Edit tab). Pick a style and one click places the game's own
-- Tower Light (/Game/Blueprints/Decorations/BP_TowerLight) along both edges of the trail, evenly spaced and close
-- enough that the trail is lit end to end, charges their normal price and switches night skiing on for that trail.
--   Uniform  pairs of lights facing each other across the trail
--   Jagged   a zipper: the same spacing, but the lights on one side sit opposite the gaps on the other
-- Once installed, the other style can be picked (the old lights are sold back and the new ones placed), the lights
-- removed, or their color changed: preset swatches or custom R/G/B sliders, for the beam and the lamp's glow, free.
-- "Party" makes them a moving rainbow, like an RGB light strip.
-- The mod only ever touches the lights it placed itself: they are named "<trail> Light #<n>" (plus " · <color>" when
-- colored), a name the game keeps in the save; the mod reads the color back from it after a reload, as the game
-- doesn't save light colors. Lights placed by hand are left alone.
-- How it works:
--   * A tower light lights everything within its LightZone (an AoEEffectComponent, kind Light, 50 m).
--   * The trail's shape comes from TrailMapSubsystem.RegisteredTrails (quadratic curves + corridor width); bowls
--     (open areas, not runs) get no lights: the section is hidden for them.
--     the game's own IsPositionInCorridor decides what is inside the trail.
--   * The spacing is the widest even one at which pairs still light all of the trail the edges can reach; connected
--     curves of one trail count as one path, so the spacing runs on across them.
--   * Towers are spawned like the game's: deferred spawn, FinalizePlacement, then the price is deducted.
-- Everything runs on the game thread. No files, no console commands, no keys.

local TAG = "[AutoTrailLights] "
local M = rawget(_G, "AUTO_TRAIL_LIGHTS") or {}       -- the same table if this file runs again: no second loops
_G.AUTO_TRAIL_LIGHTS = M
M.VERSION = "1.1.1"
M.stopped = false                                  -- this file running means the mod is on (see live switching below)

local CFG = {
  TOWER_CLASS     = "/Game/Blueprints/Decorations/BP_TowerLight.BP_TowerLight_C",
  TOWER_CDO       = "/Game/Blueprints/Decorations/BP_TowerLight.Default__BP_TowerLight_C",
  LIGHT_TEMPLATE  = "/Game/Blueprints/Decorations/BP_TowerLight.BP_TowerLight_C:LightZone_GEN_VARIABLE",
  LIGHT_KIND      = 3,       -- EAoEEffectKind::Light
  DEFAULT_RADIUS  = 5000,    -- cm, the tower light's LightZone radius (read from the game when it can be)
  COVER           = 0.8,     -- plan with 80% of the light radius, so slopes and the gaps between lights stay lit
  DEFAULT_COST    = 820,     -- the Tower Light's price, used only until a placed tower tells us the real one
  EDGE_OFFSET     = 450,     -- cm outside the trail's edge (where players usually put them)
  FINE_STEP       = 500,     -- cm between measured points along the trail
  SPACING_STEP    = 250,     -- cm: even spacings tried, widest first
  OCCUPIED        = 800,     -- cm: a spot that already has a building this close is skipped
  MAX_EDGE_SEARCH = 20000,   -- cm: widest half-width looked for
  MAX_TOWERS      = 120,     -- per trail
  MAX_SAMPLES     = 3000,    -- trail points checked for light
  CLEAR_RADIUS    = 400,     -- cm of trees cleared under a tower placed in the woods (charged like the game does)
  ENABLE_NIGHT    = true,    -- switch the trail's night skiing on after lighting it
  SPAWN_PER_FRAME  = 1,      -- lights placed per frame (all at once froze the game for a second)
  REMOVE_PER_FRAME = 4,      -- lights sold back per frame
  PARTY_PER_FRAME  = 60,     -- party lights recolored per frame (more than that: each one a little less often)
  PARTY_CYCLE      = 6.0,    -- seconds for the rainbow to go round once
  PARTY_WAVE       = 40000,  -- cm of trail per rainbow: the colors chase down the trail like an LED strip
  NAME_SUFFIX     = " Light #",
}
M.CFG = CFG
local STYLES = { "uniform", "jagged" }
local STYLE_LABEL = { uniform = "Uniform", jagged = "Jagged" }

local function log(s) print(TAG .. s .. "\n") end
local function valid(o) return o ~= nil and o:IsValid() end   -- check EVERY object: a method on a null one crashes
local function guarded(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log(name .. ": " .. tostring(err)) end
  end
end

---------------------------------------------------------------------------------------------------------- game refs
-- The resort's world is the one its TrailMapSubsystem lives in. NOT FindFirstOf("World"): the main menu's world
-- (Map_Shared) stays loaded behind the game, and lights spawned there are charged for but never seen or saved.
-- Everything here (subsystems, lights, spawning, clocks) is taken from, or checked against, that world.
local R = {}
local refsTick = 0
local function worldOf(o)
  local ok, w = pcall(function() return o:GetWorld() end)
  if ok and valid(w) then return w end
end
local function sameObj(a, b)
  local ok, same = pcall(function() return a:GetAddress() == b:GetAddress() end)
  if ok then return same end
  return a:GetFullName() == b:GetFullName()
end
local function sameWorld(o, world)
  local w = worldOf(o)
  return (w and world) and sameObj(w, world) or false
end
local function findIn(cls, world)                  -- the object of class `cls` that lives in `world`
  for _, o in ipairs(FindAllOf(cls) or {}) do
    if valid(o) and sameWorld(o, world) then return o end
  end
end
local function pickTrailMap()                      -- the loaded resort's (an initialized one, if there are several)
  local best
  for _, o in ipairs(FindAllOf("TrailMapSubsystem") or {}) do
    if valid(o) then
      local ok, init = pcall(function() return o:IsInitialized() end)
      if ok and init then return o end
      best = best or o
    end
  end
  return best
end
local function refs(force)                         -- FindAllOf walks every object: only for what's missing, ~1/s
  refsTick = refsTick + 1
  if not force and valid(R.tm) and valid(R.world) and refsTick % 4 ~= 0 then return R end
  if not valid(R.tm) or refsTick % 40 == 0 then  -- every ~10 s make sure it's still the loaded resort's
    local tm = pickTrailMap()
    if tm ~= nil and not (valid(R.tm) and sameObj(tm, R.tm)) then
      R.tm, R.eco, R.obs, R.reg, R.world = tm, nil, nil, nil, nil
    end
  end
  if not valid(R.tm) then return R end
  if not valid(R.world) then R.world = worldOf(R.tm) end
  if not valid(R.world) then return R end
  if not valid(R.eco) then R.eco = findIn("EconomySubsystem", R.world) end
  if not valid(R.obs) then R.obs = findIn("ObstacleDataManager", R.world) end
  if not valid(R.reg) then R.reg = findIn("PlaceableRegistrySubsystem", R.world) end
  if not valid(R.TU) then R.TU = StaticFindObject("/Script/SkiResortSimulator.Default__TerrainUtils") end
  if not valid(R.GS) then R.GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
  if not valid(R.cls) then R.cls = StaticFindObject(CFG.TOWER_CLASS) end
  return R
end
local function ready(r)
  return valid(r.tm) and valid(r.TU) and valid(r.world) and valid(r.GS) and valid(r.cls) and valid(r.reg)
end

-- An actor the mod destroyed stays findable (and IsValid) until the engine's garbage collection, and
-- IsActorBeingDestroyed() still says false; its refund value drops to 0 at once. So: remember what was destroyed
-- (by address) and treat it as gone while its refund is 0 (a new light later at the same address has a price).
M.dead = M.dead or {}
local function addressOf(a)
  local ok, addr = pcall(function() return a:GetAddress() end)
  if ok then return addr end
  return a:GetFullName()
end
local function gone(a)
  local key = addressOf(a)
  if not M.dead[key] then return false end
  local ok, v = pcall(function() return a:GetRefundValue() end)
  if ok and v == 0 then return true end
  M.dead[key] = nil
  return false
end

-- every Tower Light in the loaded resort (and, separately, any in other worlds)
local function resortTowers()
  local r = refs()
  local here, elsewhere = {}, {}
  if not valid(r.world) then return here, elsewhere end
  for _, a in ipairs(FindAllOf("BP_TowerLight_C") or {}) do
    if valid(a) and not gone(a) then
      if sameWorld(a, r.world) then here[#here + 1] = a else elsewhere[#elsewhere + 1] = a end
    end
  end
  return here, elsewhere
end

local function lightRadius()
  local t = StaticFindObject(CFG.LIGHT_TEMPLATE)
  if valid(t) then
    local ok, v = pcall(function() return t.EffectRadius end)
    if ok and type(v) == "number" and v > 100 then return v end
  end
  return CFG.DEFAULT_RADIUS
end

-- the steepest ground a Tower Light may stand on, as the game checks it: towers follow the terrain, so the game's
-- limit is ConformingMaxSlopeAngle (40) rather than MaxSlopeAngle (22)
local function maxSlope()
  local cdo = StaticFindObject(CFG.TOWER_CDO)
  if valid(cdo) then
    local ok, v = pcall(function()
      local vc = cdo.ValidationComponent
      if not valid(vc) then return nil end
      if cdo.bConformsToTerrain then return vc.ConformingMaxSlopeAngle end
      return vc.MaxSlopeAngle
    end)
    if ok and type(v) == "number" and v > 0 then return v end
  end
  return 40
end

local function towerCost()
  if M.knownCost then return M.knownCost end
  for _, a in ipairs((resortTowers())) do
    if valid(a) then
      local ok, c = pcall(function() return a.BaseCost end)
      if ok and type(c) == "number" and c > 0 and c < 100000 then M.knownCost = c; return c end   -- CDO: placeholder
    end
  end
  return CFG.DEFAULT_COST
end

local function money(n)
  local neg = n < 0
  local s = tostring(math.floor(math.abs(n) + 0.5))
  local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-$" or "$") .. r
end

------------------------------------------------------------------------------------------------------------- trails
local function copyCurve(c)                        -- plain Lua copies: nothing holds on to game memory
  return { sx = c.StartPoint.X, sy = c.StartPoint.Y, cx = c.ControlPoint.X, cy = c.ControlPoint.Y,
           ex = c.Endpoint.X, ey = c.Endpoint.Y }
end

local function readTrails()
  local r = refs()
  local list = {}
  if not valid(r.tm) then return list end
  r.tm.RegisteredTrails:ForEach(function(k, v)
    local id, info = k:get(), v:get()
    local t = { id = id, name = info.DisplayName:ToString(), shape = info.Shape, night = info.bNightSkiing,
                curves = { copyCurve(info.Curve) } }
    local extra = info.AdditionalCurves
    for i = 1, #extra do t.curves[#t.curves + 1] = copyCurve(extra[i]) end
    list[#list + 1] = t
  end)
  return list
end

function M.trailByName(name)
  local found
  for _, t in ipairs(readTrails()) do
    if t.name == name then
      if found then return nil, "Two trails are called \"" .. name .. "\": rename one." end
      found = t
    end
  end
  return found
end

function M.trailById(id)
  for _, t in ipairs(readTrails()) do if t.id == id then return t end end
end

---------------------------------------------------------------------------------------------- measuring the trail
local function bez(a, b, c, t) local u = 1 - t; return u * u * a + 2 * u * t * b + t * t * c end
local function dbez(a, b, c, t) return 2 * (1 - t) * (b - a) + 2 * t * (c - b) end
local function inside(tm, x, y, id) return tm:IsPositionInCorridor({ X = x, Y = y, Z = 0 }, id) end

-- distance from (x, y) along (nx, ny) to the edge of trail `id`, starting the search near `guess`
local function edgeDistance(tm, x, y, nx, ny, id, guess)
  if not inside(tm, x, y, id) then return nil end
  local step = 250
  local d = math.max(0, math.floor((guess or 0) / step) * step)
  if d > 0 and not inside(tm, x + nx * d, y + ny * d, id) then
    repeat d = d - step until d <= 0 or inside(tm, x + nx * d, y + ny * d, id)
    d = math.max(d, 0)
  end
  while d < CFG.MAX_EDGE_SEARCH and inside(tm, x + nx * (d + step), y + ny * (d + step), id) do d = d + step end
  local lo, hi = d, d + step
  for _ = 1, 3 do
    local mid = (lo + hi) / 2
    if inside(tm, x + nx * mid, y + ny * mid, id) then lo = mid else hi = mid end
  end
  return lo
end

-- "segments" (curves that connect end to start make one): points every FINE_STEP with both edge distances
local function measure(tm, trail)
  local segs = {}
  for _, cv in ipairs(trail.curves) do
    local N, px, py, acc = 96, cv.sx, cv.sy, 0
    local tab = { { t = 0, s = 0 } }
    for i = 1, N do
      local t = i / N
      local x, y = bez(cv.sx, cv.cx, cv.ex, t), bez(cv.sy, cv.cy, cv.ey, t)
      acc = acc + math.sqrt((x - px) ^ 2 + (y - py) ^ 2); px, py = x, y
      tab[#tab + 1] = { t = t, s = acc }
    end
    if acc > 100 then
      local seg = { len = acc, pts = {} }
      local n = math.max(1, math.ceil(acc / CFG.FINE_STEP))
      local j, gl, gr = 1, nil, nil
      for k = 0, n do
        local s = acc * k / n
        while j < #tab - 1 and tab[j + 1].s < s do j = j + 1 end
        local a, b2 = tab[j], tab[j + 1]
        local t = a.t + (b2.t - a.t) * ((s - a.s) / math.max(b2.s - a.s, 1e-6))
        local x, y = bez(cv.sx, cv.cx, cv.ex, t), bez(cv.sy, cv.cy, cv.ey, t)
        local dx, dy = dbez(cv.sx, cv.cx, cv.ex, t), dbez(cv.sy, cv.cy, cv.ey, t)
        local l = math.sqrt(dx * dx + dy * dy)
        if l > 1e-3 then
          local nx, ny = -dy / l, dx / l
          local dl = edgeDistance(tm, x, y, nx, ny, trail.id, gl)
          local dr = edgeDistance(tm, x, y, -nx, -ny, trail.id, gr)
          gl, gr = dl or gl, dr or gr
          seg.pts[#seg.pts + 1] = { s = s, x = x, y = y, nx = nx, ny = ny, dl = dl, dr = dr }
        end
      end
      if #seg.pts >= 2 then
        local prev = segs[#segs]
        local last = prev and prev.pts[#prev.pts]
        if last and (last.x - seg.pts[1].x) ^ 2 + (last.y - seg.pts[1].y) ^ 2 < 200 ^ 2 then
          for i = 2, #seg.pts do                   -- carries on from the previous curve
            local q = seg.pts[i]; q.s = q.s + prev.len; prev.pts[#prev.pts + 1] = q
          end
          prev.len = prev.len + seg.len
        else
          segs[#segs + 1] = seg
        end
      end
    end
  end
  return segs
end

-- the spot EDGE_OFFSET outside the edge on `side` (1 = left, -1 = right) at distance s along a segment
local function spotAt(seg, s, side)
  local pts = seg.pts
  if s <= pts[1].s then s = pts[1].s end
  if s >= pts[#pts].s then s = pts[#pts].s end
  local i = 1
  while i < #pts - 1 and pts[i + 1].s < s do i = i + 1 end
  local a, b = pts[i], pts[math.min(i + 1, #pts)]
  local f = (b.s > a.s) and (s - a.s) / (b.s - a.s) or 0
  local key = side == 1 and "dl" or "dr"
  local da, db = a[key], b[key]
  if not da and not db then return nil end
  da, db = da or db, db or da
  local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
  local nx, ny = a.nx + (b.nx - a.nx) * f, a.ny + (b.ny - a.ny) * f
  local l = math.sqrt(nx * nx + ny * ny); nx, ny = nx / l * side, ny / l * side
  local d = da + (db - da) * f + CFG.EDGE_OFFSET
  return { x = x + nx * d, y = y + ny * d, yaw = math.deg(math.atan(-ny, -nx)), s = s, side = side }
end

--------------------------------------------------------------------------------------------------- the mod's lights
-- one of the mod's lights for this trail: named "<this trail> Light #n" (or "<a trail that no longer has that name>
-- Light #n", after a rename) and standing beside this trail. A neighbour's lights are never taken.
local NAME_PATTERN = "^(.*)" .. CFG.NAME_SUFFIX:gsub("#", "%%#") .. "%d+$"
local COLOR_SEP = " \u{B7} "                         -- " · " between the name and the color: "... Light #3 · Blue"

-- "Upper Parlor Light #3 · Blue" -> "Upper Parlor Light #3", "Blue"
local function splitName(name)
  local base, tag = name:match("^(.-)" .. COLOR_SEP .. "(.+)$")
  if base and base:match(NAME_PATTERN) then return base, tag end
  return name, nil
end

local PRESETS = {                                  -- hex is sRGB; nil = the game's own warm white
  { name = "Warm white" }, { name = "Cool white", hex = "#DCEBFF" }, { name = "Blue", hex = "#3A7BFF" },
  { name = "Green", hex = "#36D46A" }, { name = "Red", hex = "#FF3B30" }, { name = "Purple", hex = "#A55BFF" },
  { name = "Amber", hex = "#FFB020" }, { name = "Pink", hex = "#FF5FB4" },
}
local DEFAULT_SPOT = { R = 1, G = 1, B = 1, A = 1 }               -- the game's: NightSpot LightColor 255,255,255
local DEFAULT_GLOW = { R = 1.0, G = 0.91, B = 0.67, A = 1 }       -- MI_BrightLight "EmssiveColor" (sic)

-- A color is nil (warm white), "#RRGGBB", or "party" (the moving rainbow); in names: "Blue", "#3366FF", "Party".
local PARTY = "party"
local function tagHex(tag)                         -- the color part of a name -> "#RRGGBB" / "party" (nil: warm white)
  if not tag then return nil end
  if tag == "Party" then return PARTY end
  if tag:match("^#%x%x%x%x%x%x$") then return tag:upper() end
  for _, p in ipairs(PRESETS) do if p.name == tag then return p.hex end end
  return nil
end
local function hexTag(hex)                         -- "#RRGGBB" -> what goes in the name ("Blue", or the hex)
  if not hex then return nil end
  if hex == PARTY then return "Party" end
  for _, p in ipairs(PRESETS) do if p.hex == hex then return p.name end end
  return hex
end
local function hexRGB(hex) return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) end
local function lin(c) c = c / 255; if c <= 0.04045 then return c / 12.92 end; return ((c + 0.055) / 1.055) ^ 2.4 end
local function hexLinear(hex) local r, g, b = hexRGB(hex); return { R = lin(r), G = lin(g), B = lin(b), A = 1 } end
local function colorName(hex)
  if not hex then return "Warm white" end
  return hexTag(hex)
end

local function isOurs(a, tm, trail, names)
  local ok, name = pcall(function() return a.InstanceName:ToString() end)
  if not (ok and name) then return false end
  local prefix = splitName(name):match(NAME_PATTERN)
  if not prefix then return false end
  if prefix ~= trail.name and names[prefix] then return false end      -- another trail's
  local l = a:K2_GetActorLocation()
  return tm:GetDistanceToCorridor({ X = l.X, Y = l.Y, Z = l.Z }, trail.id) <= CFG.EDGE_OFFSET + 500
end

function M.ourLights(trail)
  local r = refs()
  local list = {}
  if not valid(r.tm) then return list end
  local names = {}
  for _, t in ipairs(readTrails()) do names[t.name] = true end
  for _, a in ipairs((resortTowers())) do
    if isOurs(a, r.tm, trail, names) then list[#list + 1] = a end
  end
  return list
end

-- the color of a trail's lights (from the first one's name); nil = warm white
local function lightsHex(ours)
  for _, a in ipairs(ours) do
    if valid(a) then
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      if ok then local _, tag = splitName(name); return tagHex(tag) end
    end
  end
  return nil
end
M.lightsHex = lightsHex

-- the lamp's glow material: a per-light copy (made once) of MI_BrightLight, whose color can be set
local function arrayItem(o)                        -- TArray items can come wrapped
  if o ~= nil and type(o) == "userdata" and o.IsValid == nil and o.get then return o:get() end
  return o
end
-- A Tower Light has more than one spot light: NightSpot, plus one the game's light-quality system adds at runtime
-- and fades to (it copies NightSpot's color at that moment, so one made before a recolor stays white). The beam you
-- see can be either, so every color change goes to all of them.
local LOCAL_LIGHT
local function beams(a)
  LOCAL_LIGHT = LOCAL_LIGHT or StaticFindObject("/Script/Engine.LocalLightComponent")
  local list = {}
  pcall(function()
    local ls = a:K2_GetComponentsByClass(LOCAL_LIGHT)
    for i = 1, #ls do
      local c = arrayItem(ls[i])
      if c ~= nil and c.IsValid ~= nil and c:IsValid() then list[#list + 1] = c end
    end
  end)
  if #list == 0 then pcall(function() if valid(a.NightSpot) then list[1] = a.NightSpot end end) end
  return list
end

local MESH_CLASS
local function glowMaterial(a)
  MESH_CLASS = MESH_CLASS or StaticFindObject("/Script/Engine.StaticMeshComponent")
  local ms = a:K2_GetComponentsByClass(MESH_CLASS)
  for i = 1, #ms do
    local m = arrayItem(ms[i])
    if m ~= nil and m.IsValid ~= nil and m:IsValid() then
      for slot = 0, m:GetNumMaterials() - 1 do
        local mat = m:GetMaterial(slot)
        if valid(mat) then
          local n = mat:GetFName():ToString()
          if n == "ATL_Glow" then return mat end
          if n == "MI_BrightLight" then return m:CreateDynamicMaterialInstance(slot, mat, FName("ATL_Glow")) end
        end
      end
    end
  end
end

-- Party lights: kept in M.party (by object name) with their beam, glow material and position; M.partyStep()
-- recolors PARTY_PER_FRAME of them each frame from the real clock, so the rainbow runs at the same speed whatever
-- the game speed or frame rate.
local EMISSIVE = FName("EmssiveColor")
M.party = M.party or {}
local partyList, partyDirty, partyCursor, partyTick = {}, true, 0, 0
local BEAMS_RECHECK = 90                           -- frames between looks at a party light's spot lights

-- Each party light's distance along its own trail (from the trail's start), so the rainbow runs down the trail
-- like an LED strip and the two lights of a pair always match. Trails are sampled once (plain Lua, no game calls)
-- and again when a light names a trail that isn't sampled yet.
local trailPaths = nil
local function samplePaths()
  trailPaths = {}
  for _, t in ipairs(readTrails()) do
    local pts, acc = {}, 0
    for _, cv in ipairs(t.curves) do
      local px, py
      for i = 0, 48 do
        local u = i / 48
        local x, y = bez(cv.sx, cv.cx, cv.ex, u), bez(cv.sy, cv.cy, cv.ey, u)
        if px then acc = acc + math.sqrt((x - px) ^ 2 + (y - py) ^ 2) end
        px, py = x, y
        pts[#pts + 1] = { x, y, acc }
      end
    end
    trailPaths[t.name] = pts
  end
end
local function alongTrail(trailName, x, y)
  if not trailPaths or (trailName and not trailPaths[trailName]) then samplePaths() end
  local pts = trailName and trailPaths[trailName]
  if not pts then return nil end
  local best, bd = nil, math.huge
  for _, p in ipairs(pts) do
    local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
    if d < bd then best, bd = p[3], d end
  end
  return best
end

local function partyAdd(a)
  local key = a:GetFullName()
  if M.party[key] and valid(M.party[key].a) then return end
  local l = a:K2_GetActorLocation()
  local mid
  pcall(function() mid = glowMaterial(a) end)
  local s
  pcall(function()
    local trailName = splitName(a.InstanceName:ToString()):match(NAME_PATTERN)
    s = alongTrail(trailName, l.X, l.Y)
  end)
  M.party[key] = { a = a, beams = beams(a), beamsAt = partyTick + BEAMS_RECHECK, mid = mid,
                    s = s or (l.X * 0.7071 + l.Y * 0.7071) }
  partyDirty = true
end

local function partyDrop(a)
  local ok, key = pcall(function() return a:GetFullName() end)
  if ok and M.party[key] then M.party[key] = nil; partyDirty = true end
end

local function hsv(h)                              -- full saturation and value, h in 0..1 -> linear color
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local q, t = 1 - f, f
  local r, g, b
  if i == 0 then r, g, b = 1, t, 0 elseif i == 1 then r, g, b = q, 1, 0 elseif i == 2 then r, g, b = 0, 1, t
  elseif i == 3 then r, g, b = 0, q, 1 elseif i == 4 then r, g, b = t, 0, 1 else r, g, b = 1, 0, q end
  return { R = lin(r * 255), G = lin(g * 255), B = lin(b * 255), A = 1 }
end

function M.partyStep()
  partyTick = partyTick + 1
  if partyDirty then
    partyList = {}
    for _, e in pairs(M.party) do partyList[#partyList + 1] = e end
    partyDirty = false
  end
  local n = #partyList
  if n == 0 then return end
  local r = refs()
  if not (valid(r.GS) and valid(r.tm)) then return end
  local now = r.GS:GetRealTimeSeconds(r.tm)          -- the resort's clock (a world-context object of that world)
  local phase = now / CFG.PARTY_CYCLE
  for _ = 1, math.min(n, CFG.PARTY_PER_FRAME) do
    partyCursor = partyCursor % n + 1
    local e = partyList[partyCursor]
    if not valid(e.a) then
      for k, v in pairs(M.party) do if v == e then M.party[k] = nil end end
      partyDirty = true
    else
      local h = phase - e.s / CFG.PARTY_WAVE
      local c = hsv(h - math.floor(h))
      if partyTick >= e.beamsAt then e.beams, e.beamsAt = beams(e.a), partyTick + BEAMS_RECHECK end
      for _, b in ipairs(e.beams) do if valid(b) then b:SetLightColor(c, true) end end
      if e.mid and valid(e.mid) then e.mid:SetVectorParameterValue(EMISSIVE, c) end
    end
  end
end

-- beam and glow of one light (hex nil: back to the game's own colors; "party": the rainbow)
local function paint(a, hex)
  if hex == PARTY then partyAdd(a) return end
  partyDrop(a)
  local spot, glow = DEFAULT_SPOT, DEFAULT_GLOW
  if hex then spot = hexLinear(hex); glow = spot end
  for _, b in ipairs(beams(a)) do pcall(function() b:SetLightColor(spot, true) end) end
  pcall(function()
    local g = glowMaterial(a)
    if valid(g) then g:SetVectorParameterValue(EMISSIVE, glow) end
  end)
end

-- colors a trail's lights; rename = true also writes the color into their names (that's what gets saved)
function M.setColor(ours, hex, rename)
  local n = 0
  for _, a in ipairs(ours) do
    if valid(a) then
      paint(a, hex)
      n = n + 1
      if rename then
        local ok, name = pcall(function() return a.InstanceName:ToString() end)
        if ok then
          local base = splitName(name)
          local tag = hexTag(hex)
          pcall(function() a:SetInstanceName(FText(tag and (base .. COLOR_SEP .. tag) or base)) end)
        end
      end
    end
  end
  return n
end

-- after a resort loads the lights are the game's color again: color every light whose name says otherwise
local SPOT_CHECK = 4                               -- 0-255 tolerance when comparing the beam with its name
function M.repaintAll()
  local r = refs()
  if not valid(r.tm) then return 0 end
  local n = 0
  for _, a in ipairs((resortTowers())) do
    if valid(a) then
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      if ok then
        local base, tag = splitName(name)
        local hex = tag and base:match(NAME_PATTERN) and tagHex(tag)
        if hex == PARTY then
          local okk, key = pcall(function() return a:GetFullName() end)
          if okk and not M.party[key] then paint(a, hex); n = n + 1 end
        elseif hex then
          local want = { hexRGB(hex) }
          local off = false
          for _, b in ipairs(beams(a)) do
            local okc, c = pcall(function() local lc = b.LightColor; return { lc.R, lc.G, lc.B } end)
            if not okc or math.abs(c[1] - want[1]) > SPOT_CHECK or math.abs(c[2] - want[2]) > SPOT_CHECK
               or math.abs(c[3] - want[3]) > SPOT_CHECK then off = true; break end
          end
          if off then paint(a, hex); n = n + 1 end
        end
      end
    end
  end
  if n > 0 then log("recolored " .. n .. " lights") end
  return n
end

-------------------------------------------------------------------------------------------------------- planning
local function cellKey(x, y, size) return math.floor(x / size) .. ":" .. math.floor(y / size) end

-- how many of `samples` are within `reach` of any light in `lights` (spatial hash: lights are few, samples many)
local function coverage(samples, lights, reach, mark)
  local size, grid = reach, {}
  for _, l in ipairs(lights) do
    local k = cellKey(l.x, l.y, size); grid[k] = grid[k] or {}; table.insert(grid[k], l)
  end
  local r2, n = reach * reach, 0
  for i, p in ipairs(samples) do
    local cx, cy = math.floor(p[1] / size), math.floor(p[2] / size)
    local hit = false
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local cell = grid[gx .. ":" .. gy]
        if cell then
          for _, l in ipairs(cell) do
            if (p[1] - l.x) ^ 2 + (p[2] - l.y) ^ 2 <= r2 then hit = true; break end
          end
        end
        if hit then break end
      end
      if hit then break end
    end
    if hit then n = n + 1; if mark then mark[i] = true end end
  end
  return n
end

-- everything a plan needs about one trail; built once per trail (and again when it changes)
function M.prepare(trail)
  if trail.shape == 1 then return nil, "Bowls don't get trail lights." end
  local r = refs(true)
  if not ready(r) then return nil, "The resort isn't loaded." end
  local tm = r.tm
  local ctx = { trail = trail, r = r, radius = lightRadius(), slopeMax = maxSlope() }
  ctx.reach = ctx.radius * CFG.COVER
  ctx.segs = measure(tm, trail)
  if #ctx.segs == 0 then return nil, "Couldn't find this trail's edges." end

  -- bounds of the trail, from its edges
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for _, seg in ipairs(ctx.segs) do
    for _, p in ipairs(seg.pts) do
      for _, side in ipairs({ 1, -1 }) do
        local d = side == 1 and p.dl or p.dr
        if d then
          local x, y = p.x + p.nx * side * d, p.y + p.ny * side * d
          minx, maxx, miny, maxy = math.min(minx, x), math.max(maxx, x), math.min(miny, y), math.max(maxy, y)
        end
      end
    end
  end
  if minx == math.huge then return nil, "Couldn't find this trail's edges." end

  -- trail points that need light: a grid over the trail, kept if inside it
  local area = (maxx - minx + 1) * (maxy - miny + 1)
  local step = math.max(600, math.sqrt(area / CFG.MAX_SAMPLES))
  ctx.samples = {}
  for x = minx + step / 2, maxx, step do
    for y = miny + step / 2, maxy, step do
      if inside(tm, x, y, trail.id) then ctx.samples[#ctx.samples + 1] = { x, y } end
    end
  end
  if #ctx.samples == 0 then return nil, "This trail has no area to light." end

  -- the mod's own lights on this trail (a new style replaces them) and other buildings
  ctx.ours = M.ourLights(trail)
  local oursSet = {}
  for _, a in ipairs(ctx.ours) do oursSet[a:GetFullName()] = true end
  ctx.buildings = {}
  local b = r.reg.Buildings
  for i = 1, #b do
    local a = b[i]
    if valid(a) and not oursSet[a:GetFullName()] then
      local l = a:K2_GetActorLocation()
      ctx.buildings[#ctx.buildings + 1] = { x = l.X, y = l.Y }
    end
  end
  -- what the edges can reach at all: lights every FINE_STEP on both sides
  local all = {}
  for _, seg in ipairs(ctx.segs) do
    for _, p in ipairs(seg.pts) do
      for _, side in ipairs({ 1, -1 }) do
        local sp = spotAt(seg, p.s, side); if sp then all[#all + 1] = sp end
      end
    end
  end
  ctx.reachable = coverage(ctx.samples, all, ctx.reach)
  return ctx
end

local function spotOk(ctx, sp, gap)
  local r = ctx.r
  if r.tm:GetDistanceToCorridor({ X = sp.x, Y = sp.y, Z = 0 }, -1) < CFG.EDGE_OFFSET * 0.5 then return false end
  for _, p in ipairs(ctx.buildings) do
    if (p.x - sp.x) ^ 2 + (p.y - sp.y) ^ 2 < gap * gap then return false end
  end
  if r.TU:GetSlopeAngleAtLocation(r.world, { X = sp.x, Y = sp.y }) > ctx.slopeMax then return false end
  return true
end

-- even spots for one spacing: "uniform" pairs at 0, D, 2D ... on both sides; "jagged" the same on the left and
-- half a step on (D/2, 3D/2 ...) on the right, so each light faces a gap: a zipper.
local function pattern(ctx, spacing, style)
  local list = {}
  for _, seg in ipairs(ctx.segs) do
    local n = math.max(1, math.ceil(seg.len / spacing))
    local step = seg.len / n
    for k = 0, n do local sp = spotAt(seg, step * k, 1); if sp then list[#list + 1] = sp end end
    if style == "jagged" then
      for k = 0, n - 1 do local sp = spotAt(seg, step * (k + 0.5), -1); if sp then list[#list + 1] = sp end end
    else
      for k = 0, n do local sp = spotAt(seg, step * k, -1); if sp then list[#list + 1] = sp end end
    end
  end
  return list
end

-- a spot that can't be used (another trail, a building, too steep) slides a little along the edge
local function settle(ctx, list)
  local out, segOf = {}, {}
  for _, seg in ipairs(ctx.segs) do segOf[seg] = true end
  for _, sp in ipairs(list) do
    local placed = false
    if spotOk(ctx, sp, CFG.OCCUPIED) then out[#out + 1] = sp; placed = true end
    if not placed then
      for _, seg in ipairs(ctx.segs) do
        for _, ds in ipairs({ 250, -250, 500, -500, 750, -750 }) do
          local p2 = spotAt(seg, sp.s + ds, sp.side)
          if p2 and (p2.x - sp.x) ^ 2 + (p2.y - sp.y) ^ 2 < 1200 ^ 2 and spotOk(ctx, p2, CFG.OCCUPIED) then
            out[#out + 1] = p2; placed = true; break
          end
        end
        if placed then break end
      end
    end
  end
  -- no two closer than 5 m (segments meet end to start)
  local final = {}
  for _, sp in ipairs(out) do
    local dup = false
    for _, q in ipairs(final) do if (q.x - sp.x) ^ 2 + (q.y - sp.y) ^ 2 < 500 ^ 2 then dup = true; break end end
    if not dup then final[#final + 1] = sp end
  end
  return final
end

-- the widest spacing at which pairs light everything the edges can reach (a zipper with the same spacing lights at
-- least as much); measured once per trail
local function evenSpacing(ctx)
  if ctx.spacing then return ctx.spacing end
  local target = ctx.reachable - math.max(1, math.floor(ctx.reachable * 0.005))
  ctx.spacing = CFG.FINE_STEP
  for spacing = math.floor(2 * ctx.reach / CFG.SPACING_STEP) * CFG.SPACING_STEP, CFG.FINE_STEP, -CFG.SPACING_STEP do
    if coverage(ctx.samples, pattern(ctx, spacing, "uniform"), ctx.reach) >= target then ctx.spacing = spacing; break end
  end
  return ctx.spacing
end

local function planEven(ctx, style)
  local best = { spacing = evenSpacing(ctx) }
  best.list = pattern(ctx, best.spacing, style)
  -- the even spacing actually used (each segment is split into equal parts no longer than `spacing`)
  local total, parts = 0, 0
  for _, seg in ipairs(ctx.segs) do
    total = total + seg.len
    parts = parts + math.max(1, math.ceil(seg.len / best.spacing))
  end
  return settle(ctx, best.list), total / math.max(parts, 1)
end

-- { style, towers = {spots}, removeCount, refund, cost (each), net, same (already installed like this) }
function M.plan(ctx, style)
  if style ~= "jagged" then style = "uniform" end
  local towers, spacing = planEven(ctx, style)
  while #towers > CFG.MAX_TOWERS do table.remove(towers) end
  local cost = towerCost()
  local refund = 0
  for _, a in ipairs(ctx.ours) do
    local ok, v = pcall(function() return a:GetRefundValue() end)
    if ok and type(v) == "number" then refund = refund + v end
  end
  -- the same lights already standing? (each planned spot has one of ours within 3 m, and as many)
  local same = #ctx.ours > 0 and #ctx.ours == #towers
  if same then
    for _, sp in ipairs(towers) do
      local hit = false
      for _, a in ipairs(ctx.ours) do
        if valid(a) then
          local l = a:K2_GetActorLocation()
          if (l.X - sp.x) ^ 2 + (l.Y - sp.y) ^ 2 < 300 ^ 2 then hit = true; break end
        end
      end
      if not hit then same = false; break end
    end
  end
  local lit = coverage(ctx.samples, towers, ctx.reach)
  return { style = style, ctx = ctx, towers = towers, spacing = spacing, cost = cost, removeCount = #ctx.ours,
           refund = refund, net = cost * #towers - refund, same = same,
           dark = ctx.reachable < #ctx.samples or lit < ctx.reachable * 0.98 }
end

------------------------------------------------------------------------------------------------------------ placing
-- sells one light back; returns the refund (nil if it couldn't be removed)
local function removeOne(r, a)
  if not valid(a) or gone(a) then return nil end
  local v = 0
  pcall(function() v = a:GetRefundValue() end)
  if not pcall(function() a:K2_DestroyActor() end) then return nil end
  M.dead[addressOf(a)] = true
  if v > 0 and valid(r.eco) then pcall(function() r.eco:RefundExpense(v, 0) end) else v = 0 end   -- 0: Construction
  return v
end

local function spawnTower(r, sp, name, hex)
  local z = r.TU:GetHeightAtLocation(r.world, { X = sp.x, Y = sp.y })
  if valid(r.obs) and r.obs:IsLocationBlocked({ X = sp.x, Y = sp.y, Z = z }, 300) then
    pcall(function() r.obs:ClearObstaclesInRadius({ X = sp.x, Y = sp.y, Z = z }, CFG.CLEAR_RADIUS, true) end)
  end
  local h = math.rad(sp.yaw) / 2
  local xf = { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = sp.x, Y = sp.y, Z = z },
               Scale3D = { X = 1, Y = 1, Z = 1 } }
  local a = r.GS:BeginDeferredActorSpawnFromClass(r.world, r.cls, xf, 1, nil, 0)   -- 1: always spawn
  if not valid(a) then return nil end
  a = r.GS:FinishSpawningActor(a, xf, 0)
  if not valid(a) then return nil end
  pcall(function() a:K2_SetActorRotation({ Pitch = 0, Yaw = sp.yaw, Roll = 0 }, false) end)
  pcall(function() a:FinalizePlacement() end)
  pcall(function() a:SetInstanceName(FText(name)) end)
  if hex then paint(a, hex) end
  return a
end

-- Placing and removing run a little every frame (M.job, stepped by M.stepJob from the per-frame loop): dozens of
-- lights in one frame froze the game for a second. The old lights go first (sold back), then the new ones, one a frame.

-- starts replacing the trail's lights with the plan's; returns nil, or a message if it can't start
function M.apply(p)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  if p.same then return "Already installed." end
  if valid(r.eco) and p.net > 0 and not r.eco:CanAfford(p.net) then
    return "Not enough money: " .. money(p.net) .. " needed."
  end
  local hex = lightsHex(p.ctx.ours)                -- a new style keeps the trail's color
  M.job = { kind = "place", p = p, trail = p.ctx.trail, hex = hex, tag = hexTag(hex), world = r.world,
            remove = p.ctx.ours, ri = 1, si = 1, removed = 0, back = 0, placed = 0, spent = 0 }
  return nil
end

-- The mod's lights in another world than the resort's (spawned there by an older version: unseen, never saved) are
-- sold back and removed, a few at a time.
function M.cleanupElsewhere()
  local r = refs()
  if not ready(r) then return 0 end
  local _, elsewhere = resortTowers()
  local n, back = 0, 0
  for _, a in ipairs(elsewhere) do
    local ok, name = pcall(function() return a.InstanceName:ToString() end)
    if ok and splitName(name):match(NAME_PATTERN) then
      local v = removeOne(r, a)
      if v then n = n + 1; back = back + v end
      if n >= 20 then break end
    end
  end
  if n > 0 then log(string.format("removed %d lights that were outside the resort (%s back)", n, money(back))) end
  return n
end

-- starts selling the trail's lights back
function M.remove(trail)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  M.job = { kind = "remove", trail = trail, world = r.world, remove = M.ourLights(trail), ri = 1, removed = 0, back = 0 }
  return nil
end

local function finishJob(j, r, why)
  M.job = nil
  local t = j.trail
  if j.kind == "place" then
    if j.placed > 0 and CFG.ENABLE_NIGHT and valid(r.tm) then pcall(function() r.tm:SetTrailNightSkiing(t.id, true) end) end
    log(string.format("trail %d \"%s\": %s, removed %d (%s back), placed %d (%s)%s", t.id, t.name, j.p.style,
      j.removed, money(j.back), j.placed, money(j.spent), why and (" - " .. why) or ""))
  else
    log(string.format("trail %d \"%s\": removed %d lights (%s back)%s", t.id, t.name, j.removed, money(j.back),
      why and (" - " .. why) or ""))
  end
  if M.P then
    M.P.key = nil                                  -- the panel measures the trail again
    if why then M.P.msg = "Stopped: " .. why .. "." end
  end
end

function M.stepJob()
  local j = M.job
  if not j then return end
  local r = refs()
  if not (valid(j.world) and ready(r)) then        -- the resort was closed or another one loaded
    M.job = nil
    log("stopped: the resort was closed")
    return
  end
  if j.ri <= #j.remove then                        -- 1. the old lights
    for _ = 1, CFG.REMOVE_PER_FRAME do
      local a = j.remove[j.ri]
      if a == nil then break end
      j.ri = j.ri + 1
      local v = removeOne(r, a)
      if v then j.removed = j.removed + 1; j.back = j.back + v end
    end
    return
  end
  if j.kind ~= "place" then finishJob(j, r) return end
  for _ = 1, CFG.SPAWN_PER_FRAME do                -- 2. the new ones
    local i = j.si
    local sp = j.p.towers[i]
    if not sp then break end
    j.si = i + 1
    local a = spawnTower(r, sp, j.trail.name .. CFG.NAME_SUFFIX .. i .. (j.tag and (COLOR_SEP .. j.tag) or ""), j.hex)
    if not a then log("a tower didn't spawn at " .. math.floor(sp.x) .. ", " .. math.floor(sp.y)) else
      local cost = j.p.cost
      pcall(function() if a.BaseCost > 0 and a.BaseCost < 100000 then cost = a.BaseCost; M.knownCost = cost end end)
      if valid(r.eco) and not r.eco:TryDeductFunds(cost) then
        pcall(function() a:K2_DestroyActor() end)
        finishJob(j, r, "ran out of money")
        return
      end
      j.placed, j.spent = j.placed + 1, j.spent + cost
    end
  end
  if j.si > #j.p.towers then finishJob(j, r) end
end

function M.jobProgress()
  local j = M.job
  if not j then return nil end
  if j.ri <= #j.remove then return string.format("Removing old lights...  %d / %d", j.ri - 1, #j.remove) end
  if j.kind == "place" then return string.format("Placing lights...  %d / %d", j.si - 1, #j.p.towers) end
  return "Removing lights..."
end

-- the whole thing, by trail id or name (handy from a console/REPL too)
function M.lightTrail(idOrName, style)
  local t, err
  if type(idOrName) == "number" then t = M.trailById(idOrName) else t, err = M.trailByName(idOrName) end
  if not t then return err or "no such trail" end
  local ctx, cerr = M.prepare(t)
  if not ctx then return cerr end
  return M.apply(M.plan(ctx, style or "uniform"))
end

----------------------------------------------------------------------------------------------- the trail panel part
local C = { on = { R = 0.10, G = 0.32, B = 0.62, A = 1 }, off = { R = 0.16, G = 0.18, B = 0.22, A = 1 },
            red = { R = 0.45, G = 0.14, B = 0.12, A = 1 }, text = { R = 1, G = 1, B = 1, A = 1 },
            dim = { R = 0.62, G = 0.68, B = 0.75, A = 1 }, ok = { R = 0.45, G = 0.85, B = 0.50, A = 1 },
            warn = { R = 0.98, G = 0.70, B = 0.25, A = 1 } }
local P = M.P or {}
M.P = P
P.styleOf = P.styleOf or {}                        -- trail id -> the style picked in the panel (this session)

local function newWidget(tree, cn) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cn), tree) end
local function newText(tree, s, size, color, bold)
  local t = newWidget(tree, "TextBlock")
  t:SetText(FText(s))
  local f = t.Font                                 -- edit the default font in place: a partial struct table crashes
  f.Size = size
  f.TypefaceFontName = FName(bold and "Bold" or "Regular")
  t:SetFont(f)
  t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
  return t
end
local function newButton(tree, row, label, fill, fn)
  local b = newWidget(tree, "Button")
  b:SetBackgroundColor(C.off)
  local t = newText(tree, label, 10, C.text, true)
  t:SetJustification(1)
  b:SetContent(t)
  local s = row:AddChildToHorizontalBox(b)
  s:SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })
  s:SetSize({ Value = fill or 1, SizeRule = 1 })
  local c = { w = b, label = t, fn = fn, was = false, enabled = true }
  P.controls[#P.controls + 1] = c
  return c
end
local function setButton(c, text, color, enabled)
  if text then c.label:SetText(FText(text)) end
  c.w:SetBackgroundColor(color)
  c.enabled = enabled
end

local refresh, refreshColor                        -- below

local function swatchTint(hex)                     -- what a swatch button shows
  if not hex then return { R = 1.0, G = 0.80, B = 0.45, A = 1 } end
  return hexLinear(hex)
end

-- a color picked in the panel: paints this trail's lights; commit = also save it in their names
local function pickColor(hex, commit)
  if not (P.ctx and P.ctx.ours) then return end
  M.setColor(P.ctx.ours, hex, commit)
  P.color = hex
  if commit then P.colorSaved = hex end
end

local function inject(w)
  local tree = w.WidgetTree
  local box = w.EditTabContent
  if not (valid(tree) and valid(box)) then return false end
  P.controls = {}
  local root = newWidget(tree, "VerticalBox")
  local title = newText(tree, "Trail lights", 11, C.text, true)
  root:AddChildToVerticalBox(title):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 3 })

  local styles = newWidget(tree, "HorizontalBox")
  root:AddChildToVerticalBox(styles):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 3 })
  P.styleButtons = {}
  for _, st in ipairs(STYLES) do
    P.styleButtons[st] = newButton(tree, styles, STYLE_LABEL[st], 1, function()
      if P.trail then P.styleOf[P.trail.id] = st end
      refresh(false)
    end)
  end

  local actions = newWidget(tree, "HorizontalBox")
  root:AddChildToVerticalBox(actions):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 3 })
  P.main = newButton(tree, actions, "Install trail lights", 3, function()
    if not P.plan then return end
    local msg = M.apply(P.plan)                    -- runs over the next frames; the panel re-plans when it's done
    if msg then P.msg = msg; P.key = nil end
  end)
  P.removeBtn = newButton(tree, actions, "Remove", 1, function()
    if not P.trail then return end
    local msg = M.remove(P.trail)
    if msg then P.msg = msg; P.key = nil end
  end)

  P.note = newText(tree, "", 9, C.dim, false)
  P.note:SetAutoWrapText(true)
  root:AddChildToVerticalBox(P.note):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })

  -- light color: shown once this trail has the mod's lights
  P.colorBox = newWidget(tree, "VerticalBox")
  root:AddChildToVerticalBox(P.colorBox):SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 0 })
  P.colorTitle = newText(tree, "Light color", 10, C.text, true)
  P.colorBox:AddChildToVerticalBox(P.colorTitle):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 3 })
  local sw = newWidget(tree, "HorizontalBox")
  P.colorBox:AddChildToVerticalBox(sw):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 3 })
  P.swatches = {}
  for _, pr in ipairs(PRESETS) do
    local c = newButton(tree, sw, " ", 1, function()
      pickColor(pr.hex, true)
      P.customOpen = false
      refresh(false)
    end)
    c.hex = pr.hex
    c.w:SetBackgroundColor(swatchTint(pr.hex))
    P.swatches[#P.swatches + 1] = c
  end
  local crow = newWidget(tree, "HorizontalBox")
  P.colorBox:AddChildToVerticalBox(crow):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 3 })
  P.customBtn = newButton(tree, crow, "Custom color", 1, function()
    P.customOpen = not P.customOpen
    refresh(false)
  end)
  P.partyBtn = newButton(tree, crow, "Party", 1, function()
    if P.color == PARTY then pickColor(nil, true) else pickColor(PARTY, true) end   -- off again: warm white
    P.customOpen = false
    refresh(false)
  end)
  P.sliderBox = newWidget(tree, "VerticalBox")
  P.colorBox:AddChildToVerticalBox(P.sliderBox)
  P.sliders = {}
  for _, ch in ipairs({ "R", "G", "B" }) do
    local row = newWidget(tree, "HorizontalBox")
    P.sliderBox:AddChildToVerticalBox(row):SetPadding({ Left = 2, Top = 1, Right = 2, Bottom = 1 })
    local lab = newText(tree, ch, 9, C.dim, true)
    local ls = row:AddChildToHorizontalBox(lab)
    ls:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }); ls:SetVerticalAlignment(2)
    local sl = newWidget(tree, "Slider")             -- 0..1, shown as 0..255
    local ss = row:AddChildToHorizontalBox(sl)
    ss:SetSize({ Value = 1, SizeRule = 1 }); ss:SetVerticalAlignment(2)
    local val = newText(tree, "255", 9, C.dim, false)
    local vs = row:AddChildToHorizontalBox(val)
    vs:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 }); vs:SetVerticalAlignment(2)
    P.sliders[#P.sliders + 1] = { w = sl, val = val, last = nil }
  end

  -- right under the Night skiing switch if its row can be found, else at the end of the Edit tab
  local slot
  pcall(function()
    local rows = w.OptionRows
    for i = 1, #rows do
      if rows[i].GlossaryTermKey:ToString() == "nightskiing" then
        local row = rows[i].Row
        local parent = valid(row) and row:GetParent() or nil
        if valid(parent) and parent:GetClass():GetFName():ToString() == "VerticalBox" then
          local at = parent:GetChildIndex(row)
          if at >= 0 then slot = parent:InsertChildAt(at + 1, root) end
        end
      end
    end
  end)
  if not slot then slot = box:AddChild(root) end
  pcall(function() slot:SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 6 }) end)
  P.owner, P.root, P.key, P.ctx, P.plan, P.trail = w, root, nil, nil, nil, nil
  log("added to the trail panel")
  return true
end

local function note(text, color)
  P.note:SetText(FText(text or ""))
  P.note:SetColorAndOpacity({ SpecifiedColor = color or C.dim, ColorUseRule = 0 })
end

local function disableAll(msg, color)
  for _, st in ipairs(STYLES) do setButton(P.styleButtons[st], nil, C.off, false) end
  setButton(P.main, "Install trail lights", C.off, false)
  P.removeBtn.w:SetVisibility(1)
  P.colorBox:SetVisibility(1)
  P.plan = nil
  note(msg, color)
end

local function setSliders(hex)                     -- show a color on the sliders without it counting as a change
  local r, g, b = 255, 232, 171                     -- warm white, roughly
  if hex and hex ~= PARTY then r, g, b = hexRGB(hex) end
  for i, v in ipairs({ r, g, b }) do
    local s = P.sliders[i]
    s.w:SetValue(v / 255)
    s.last = s.w:GetValue()
    s.val:SetText(FText(tostring(v)))
  end
end

refreshColor = function()
  local ours = P.ctx and P.ctx.ours or {}
  if #ours == 0 then P.colorBox:SetVisibility(1); P.customOpen = false; return end
  P.colorBox:SetVisibility(0)
  local hex = lightsHex(ours)
  P.color, P.colorSaved = hex, hex
  P.colorTitle:SetText(FText("Light color: " .. colorName(hex)))
  local isPreset = false
  for _, c in ipairs(P.swatches) do
    local on = (c.hex == hex)
    if on then isPreset = true end
    c.label:SetText(FText(on and "\u{2022}" or " "))   -- a dot on the chosen one
    c.enabled = true
  end
  local party = (hex == PARTY)
  local custom = not isPreset and not party
  setButton(P.customBtn, custom and ("Custom: " .. hex) or "Custom color", (P.customOpen or custom) and C.on or C.off, true)
  setButton(P.partyBtn, party and "Party: on" or "Party", party and C.on or C.off, true)
  P.sliderBox:SetVisibility(P.customOpen and 0 or 1)
  setSliders(hex)
end

-- remeasure = true: the trail changed (or another one is shown); false: only the style changed
refresh = function(remeasure)
  if remeasure or not P.ctx then
    P.ctx, P.trail = nil, nil
    local name = ""
    pcall(function() name = P.owner.TrailNameLabel:GetText():ToString() end)
    local t, err = M.trailByName(name)
    P.root:SetVisibility((t and t.shape == 1) and 1 or 0)   -- bowls: no trail lights section at all
    if t and t.shape == 1 then P.plan = nil; return end
    if not t then disableAll(err or "Finish the trail first.") return end
    local ctx, cerr = M.prepare(t)
    if not ctx then disableAll(cerr, C.warn) return end
    P.ctx, P.trail = ctx, t
  end
  local ctx, t = P.ctx, P.trail
  local style = P.styleOf[t.id] or "uniform"
  for _, st in ipairs(STYLES) do setButton(P.styleButtons[st], nil, st == style and C.on or C.off, true) end
  local p = M.plan(ctx, style)
  P.plan = p
  local n = #p.towers
  P.removeBtn.w:SetVisibility(p.removeCount > 0 and 0 or 1)
  setButton(P.removeBtn, string.format("Remove (%s)", money(p.refund)), C.red, p.removeCount > 0)
  local each = string.format("%d Tower Light%s", n, n == 1 and "" or "s")
  local spacing = p.spacing and string.format(", every %d m", math.floor(p.spacing / 100 + 0.5)) or ""
  if p.same then
    setButton(P.main, "Installed (" .. STYLE_LABEL[style] .. ")", C.off, false)
    note(each .. spacing .. ". Pick another style to change them." .. (t.night and "" or " Night skiing is off above."), C.ok)
  elseif n == 0 then
    setButton(P.main, "Install trail lights", C.off, false)
    note("No room for lights along this trail's edges.", C.warn)
  elseif p.removeCount > 0 then
    setButton(P.main, string.format("Switch to %s  %s", STYLE_LABEL[style], money(p.net)), C.on, true)
    note(string.format("Replaces this trail's %d lights with %s%s (old ones sold back for %s).", p.removeCount, each,
      spacing, money(p.refund)))
  else
    setButton(P.main, string.format("Install trail lights  %s", money(p.net)), C.on, true)
    note(string.format("Places %s%s (%s each)%s.", each, spacing, money(p.cost),
      CFG.ENABLE_NIGHT and " and turns Night skiing on" or ""))
  end
  if P.msg then note(P.msg, C.warn); P.msg = nil end
  if p.dark and n > 0 then P.note:SetText(FText(P.note:GetText():ToString() .. " Parts too far from the edges stay dark.")) end
  refreshColor()
end

local function panelShown(w)
  if not (valid(w) and w:IsVisible()) then return false end
  local ok, v = pcall(function() return w.EditTabContent:IsVisible() end)
  return ok and v
end

local frame = 0
local function pollSliders()
  if not (P.customOpen and P.sliders and P.ctx and P.ctx.ours and #P.ctx.ours > 0) then return end
  local changed = false
  for _, s in ipairs(P.sliders) do
    local v = s.w:GetValue()
    if s.last == nil then s.last = v end
    if math.abs(v - s.last) > 0.001 then
      s.last = v; changed = true
      s.val:SetText(FText(tostring(math.floor(v * 255 + 0.5))))
    end
  end
  if changed then P.slideAt = frame end
  if P.slideAt then
    local function hexNow()
      local c = {}
      for i, s in ipairs(P.sliders) do c[i] = math.floor(s.last * 255 + 0.5) end
      return string.format("#%02X%02X%02X", c[1], c[2], c[3])
    end
    if frame - P.slideAt > 20 then                 -- let go: save it in the names
      P.slideAt = nil
      pickColor(hexNow(), true)
      P.colorTitle:SetText(FText("Light color: " .. colorName(P.color)))
      for _, c in ipairs(P.swatches) do c.label:SetText(FText(c.hex == P.color and "\u{2022}" or " ")) end
      setButton(P.customBtn, "Custom: " .. P.color, C.on, true)
    elseif frame % 4 == 0 then                     -- dragging: show it
      pickColor(hexNow(), false)
    end
  end
end

function M.poll()                                  -- every frame: a click lasts one frame
  if M.stopped then return end
  frame = frame + 1
  if M.job then
    local ok, err = pcall(M.stepJob)
    if not ok then log("job: " .. tostring(err)); M.job = nil; P.key = nil end
  end
  local okp, perr = pcall(M.partyStep)
  if not okp and frame % 600 == 0 then log("party: " .. tostring(perr)) end
  if not panelShown(P.owner) or not P.controls then return end
  if M.job then                                    -- busy: show how far it is, take no clicks
    for _, d in ipairs(P.controls) do d.enabled = false; d.was = false end
    if frame % 5 == 0 and valid(P.main.w) then
      P.main.label:SetText(FText(M.jobProgress() or ""))
      P.main.w:SetBackgroundColor(C.off)
    end
    return
  end
  pcall(pollSliders)
  for _, c in ipairs(P.controls) do
    if valid(c.w) then
      local p = c.w:IsPressed()
      if c.was and not p and c.w:IsHovered() and c.enabled then
        for _, d in ipairs(P.controls) do d.enabled = false end   -- one action per click, until re-planned
        local ok, err = pcall(c.fn)
        if not ok then log("click: " .. tostring(err)) end
        c.was = false
        return
      end
      c.was = p
    end
  end
end

local bgTick = 0
function M.background()                            -- 4 times a second
  if M.stopped then return end
  bgTick = bgTick + 1
  if bgTick % 20 == 0 and not P.slideAt then       -- every 5 s (not mid-drag): saved colors back on lights
    local ok, err = pcall(M.repaintAll)
    if not ok then log("repaint: " .. tostring(err)) end
  end
  if bgTick % 20 == 10 and not M.job then
    local ok, err = pcall(M.cleanupElsewhere)
    if not ok then log("cleanup: " .. tostring(err)) end
  end
  local w = P.owner
  if not valid(w) then
    P.owner = nil
    if bgTick % 4 ~= 0 then return end             -- looking for the panel: about once a second
    local r = refs()
    if not valid(r.world) then return end
    w = findIn("TrailEditWidget", r.world)          -- the resort's panel
    if not valid(w) then return end
    if not inject(w) then return end
  end
  if not panelShown(w) then P.key = nil; return end
  if M.job then return end                         -- re-plan once the lights are in
  local key = ""
  pcall(function() key = w.TrailNameLabel:GetText():ToString() .. "|" .. w.LengthLabel:GetText():ToString() end)
  if key ~= P.key then                             -- another trail, or this one changed or was just lit
    P.key = key
    local ok, err = pcall(refresh, true)
    if not ok then
      log("refresh: " .. tostring(err))
      pcall(disableAll, "Something went wrong (see UE4SS.log).", C.warn)
    end
  end
end

if not M.started then
  M.started = true
  LoopInGameThreadAfterFrames(1, guarded("poll", function() M.poll() end))
  LoopInGameThreadAfterFrames(15, guarded("background", function() M.background() end))
  log("loaded " .. M.VERSION .. " - open a trail's panel, Edit tab: \"Trail lights\"")
end

-- Z's Mod Loader live switching (its Mod Manager can turn mods on and off while the game runs): say we're on at
-- startup; on unload stop working, take the Trail lights section out of the panel and clear the flag. Lights already
-- placed stay: they're ordinary buildings, saved with the resort. Without that loader (plain UE4SS) this only sets
-- an unused shared variable.
local ENABLED_KEY = "SkiEOMods.enabled.AutoTrailLights"
local function setEnabledFlag(on)
  if on then pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, true) end) return end
  if not pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, nil) end) then
    pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, false) end)
  end
end
if ModRef then
  setEnabledFlag(true)
  pcall(function()
    ModRef.OnUnload = function()
      M.stopped = true
      if M.job then log("switched off while placing lights: stopped there"); M.job = nil end
      pcall(function()
        local root = M.P and M.P.root
        if root and root:IsValid() then root:RemoveFromParent() end
      end)
      if M.P then M.P.owner, M.P.root, M.P.key = nil, nil, nil end
      setEnabledFlag(false)
      log("switched off")
    end
  end)
end

return M
