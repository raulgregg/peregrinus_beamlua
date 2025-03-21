-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- [[ STORE FREQUENTLY USED FUNCTIONS IN UPVALUES ]] --
local buffer = require("string.buffer")
local max = math.max
local min = math.min
local sin = math.sin
local asin = math.asin
local pi = math.pi
local abs = math.abs
local sqrt = math.sqrt
local floor = math.floor
local tableInsert = table.insert
local tableRemove = table.remove
local tableConcat = table.concat
local strFormat = string.format
---------------------------------
local scriptai = nil

local M = {}
local E = setmetatable({}, {__newindex = function(t, key, val) log('E', 'ai.lua', 'Tried to insert new elements into token empty table') end})

M.mode = 'disabled' -- this is the main mode
M.manualTargetName = nil
M.debugMode = 'off'
M.speedMode = nil
M.routeSpeed = nil
M.extAggression = 0.3
M.cutOffDrivability = 0
M.driveInLaneFlag = 'off'

-- [[ Simulation time step]] --
local dt

-- [[ ENVIRONMENT VARIABLES ]] --
local g = obj:getGravity() -- standard gravity is negative
local gravityDir = vec3(0, 0, sign2(g))
g = max(1e-30, abs(g)) -- prevent divivion by 0 gravity
local gravityVec = gravityDir * g
----------------------------------

-- [[ PERFORMANCE RELATED ]] --
local aggression = 1
local aggressionMode
local trajMethod = 'spring' --('spring' for default spring method or 'springDampers' for new physical system with springs and dampers)
--------------------------------------------------------------------------

-- [[ AI DATA: POSITION, CONTROL, STATE ]] --
local ai = {
  pos = obj:getFrontPosition(),
  dirVec = obj:getDirectionVector(),
  prevDirVec = obj:getDirectionVector(),
  upVec = obj:getDirectionVectorUp(),
  rightVec = vec3(),
  width = nil,
  length = nil,
  wheelBase = nil,
  currentSegment = {},
  vel = vec3(obj:getSmoothRefVelocityXYZ()),
  speed = vec3(obj:getSmoothRefVelocityXYZ()):length(),
}

local targetSpeedDifSmoother = nil
local aiDeviation = 0
local aiDeviationSmoother = newTemporalSmoothing(1)
local smoothTcs = newTemporalSmoothingNonLinear(0.1, 0.9)
local throttleSmoother = newTemporalSmoothing(1e30, 0.2)
local aiCannotMoveTime = 0
local aiForceGoFrontTime = 0
local staticFrictionCoef = 1

local twt = {
  state = 0,
  dirState = {0, 0}, -- direction, steer
  posTable = {vec3(), vec3(), vec3(), vec3()},
  dirTable = {vec3(), vec3(), vec3(), vec3()},
  minRay = "",
  rayMins = {math.huge, math.huge, math.huge, math.huge, math.huge, math.huge, math.huge, math.huge}, --clockwise beginning from corner front left
  minRayCoefs = {0, 0, 0, 0, 0, 0, 0, 0}, -- clockwise as above
  blueNoiseCoefs = {0, 0, 0, 0, 0, 0, 0, 0},
  biasedCoefs = {0, 0, 0, 0, 0, 0, 0, 0},
  blueNoiseRR = 0,
  sampleCounter = 0, -- for starting scan, to give some time for precision
  targetSpeed = 0,
  OBBinRange = {},
  RRT = {1,1,1,2,1,2,2,2,2,2,2,3,2,3,3,3,3,3,3,4,3,4,4,4,4,4,4,1,4,1,1,1},
  speedSmoother = newTemporalSmoothingNonLinear(1000, 0.25),
  steerSmoother = newTemporalSmoothingNonLinear(2)
}

twt.reset = function()
  twt.state = 0
  twt.dirState[1], twt.dirState[2] = 0, 0
  twt.minRay = nil
  for i = 1, #twt.rayMins do twt.rayMins[i] = math.huge end
  for i = 1, #twt.blueNoiseCoefs do twt.blueNoiseCoefs[i] = 0 end
  twt.sampleCounter = 0
  twt.targetSpeed = 0
  twt.speedSmoother:set(0)
  twt.steerSmoother:set(0)
end

local forces = {}
local velocities = {}
local lastCommand = {steering = 0, throttle = 0, brake = 0, parkingbrake = 0}

local driveInLaneFlag = false
local internalState = 'onroad'

local restoreGearboxMode = false
local validateInput = nop
------------------------------

-- [[ CRASH DETECTION ]] --
local crash = {time = 0, manoeuvre = 0, dir = nil, pos = {}}

local recover = {
  recoverOnCrash = false,
  recoverTimer = 0,
  _recoverOnCrash = false
}

-- [[ OPPONENT DATA ]] --
local player
local chaseData

-- [[ SETTINGS, PARAMETERS, AUXILIARY DATA ]] --
local mapData -- map data including node connections (edges and edge data), node positions and node radii
local signalsData -- traffic intersection and signals data
local currentRoute
local MIN_PLAN_COUNT = 3
local targetWPName

local wpList
local manualPath
local speedProfile
local race, noOfLaps
local parameters

local targetObjectSelectionMode

local edgeDict

local scriptData
------------------------------

-- [[ TRAFFIC ]] --
local trafficTable = {}
local trafficStates = {}
local radiusFilter = 200 -- searching radius for traffic vehicles
local filtered = false    -- TrafficFilter on or off (true/false)
local intersection = true -- check for intersection between ai and other vehicle
local vdraw = false       -- draw debuf spheres to show traffic vehicles in trafficTable
local distAhead = 40     -- minimum Ahead distance for searching traffic vehicle

local avoidCars = 'on'

M.extAvoidCars = 'auto'

local changePlanTimer = 0

-----------------------

-- [[ HEAVY DEBUG MODE ]] --
local trajecRec = {last = 0}
local routeRec = {last = 0}
local labelRenderDistance = 10
-- local newPositionsDebug = {} -- for debug purposes
local misc = {logData = nop}
local debugSpots = {}
local candidatePaths

local trafficPathState = {}
------------------------------

local function aistatus(status, category)
  guihooks.trigger("AIStatusChange", {status=status, category=category})
end

local function getState()
  return M
end

local function drawOBB(c, x, y, z, col)
  -- c: center point
  -- x: front vec
  -- y: left vec
  -- z: up vec

  local debugDrawer = obj.debugDrawProxy
  col = col or color(255, 0, 0, 255)

  local p1 = c - x + y - z -- RLD
  local p2 = c - x - y - z -- RRD
  local p3 = c - x - y + z -- RRU
  local p4 = c - x + y + z -- RLU
  local p5 = c + x + y - z -- FLD
  local p6 = c + x - y - z -- FRD
  local p7 = c + x - y + z -- FRU
  local p8 = c + x + y + z -- FLU

  -- rear face
  debugDrawer:drawCylinder(p1, p2, 0.02, col)
  debugDrawer:drawCylinder(p2, p3, 0.02, col)
  debugDrawer:drawCylinder(p3, p4, 0.02, col)
  debugDrawer:drawCylinder(p4, p1, 0.02, col)

  -- front face
  debugDrawer:drawCylinder(p5, p6, 0.02, col)
  debugDrawer:drawCylinder(p6, p7, 0.02, col)
  debugDrawer:drawCylinder(p7, p8, 0.02, col)
  debugDrawer:drawCylinder(p8, p5, 0.02, col)

  -- left face
  debugDrawer:drawCylinder(p1, p5, 0.02, col)
  debugDrawer:drawCylinder(p4, p8, 0.02, col)

  -- right face
  debugDrawer:drawCylinder(p2, p6, 0.02, col)
  debugDrawer:drawCylinder(p3, p7, 0.02, col)
end

local function stateChanged()
  if playerInfo.anyPlayerSeated then
    guihooks.trigger("AIStateChange", getState())
  end
end

local function setSpeed(speed)
  if type(speed) ~= 'number' then M.routeSpeed = nil else M.routeSpeed = speed end
end

local function setSpeedMode(speedMode)
  if speedMode == 'set' or speedMode == 'limit' or speedMode == 'legal' or speedMode == 'off' then
    M.speedMode = speedMode
  else
    M.speedMode = nil
  end
end

local function resetSpeedModeAndValue()
  M.speedMode = nil -- maybe this should be 'off'
  M.routeSpeed = nil
end

local function setAggressionInternal(v)
  aggression = v or M.extAggression
end

local function setAggressionExternal(v)
  M.extAggression = v or M.extAggression
  setAggressionInternal()
  stateChanged()
end

local function setAggressionMode(aggrmode)
  if aggrmode == 'rubberBand' then
    aggressionMode = aggrmode
  else
    aggressionMode = nil
    setAggressionInternal()
  end
end

local function resetAggression()
  setAggressionInternal()
end

local function resetInternalStates()
  trafficStates.block = {timer = 0, coef = 0, timerLimit = 6, block = false}
  trafficStates.side = {timer = 0, cTimer = 0, side = 1, displacement = 0, timerLimit = 6}
  trafficStates.action = {hornTimer = -1, hornTimerLimit = 1, forcedStop = false}
  trafficStates.intersection = {timer = 0, turn = 0, block = false}

  chaseData = {playerState = nil, playerStoppedTimer = 0, playerRoad = nil}

  if electrics.values.horn == 1 then electrics.horn(false) end
  if electrics.values.signal_left_input or electrics.values.signal_right_input then electrics.set_warn_signal(false) end

  trafficPathState = {}
end
resetInternalStates()

local function resetParameters()
  -- parameters are used for finer AI control
  parameters = {
    turnForceCoef = 2, -- coefficient for curve spring forces
    awarenessForceCoef = 0.25, -- coefficient for vehicle awareness displacement
    edgeDist = 0, -- minimum distance from the edge of the road
    trafficWaitTime = 2, -- traffic delay after stopping at intersection
    enableElectrics = true, -- allows the ai to automatically use electrics such as hazard lights (especially for traffic)
    driveStyle = 'default',
    staticFrictionCoefMult = 0.95,
    lookAheadKv = 0.6,
    applyWidthMarginOffset = true,
    planErrorSmoothing = true,
    springForceIntegratorDispLim = 0.1, -- node displacement force magnitude limit
    understeerThrottleControl = 'on', -- anything other than an 'off' value will keep this active
    oversteerThrottleControl = 'on', -- anything other than an 'off' value will keep this active
    throttleTcs = 'on' -- anything other than an 'off' value will keep this active
  }
end
resetParameters()

local function setParameters(data)
  tableMerge(parameters, data)
end

local function setTargetObjectID(id)
  M.targetObjectID = M.targetObjectID ~= objectId and id or -1
  if M.targetObjectID ~= -1 then targetObjectSelectionMode = 'manual' end
end

local function calculateWheelBase()
  local avgWheelNodePos, numOfWheels = vec3(), 0
  for _, wheel in pairs(wheels.wheels) do
    -- obj:getNodePosition is the pos vector of query node (wheel.node1) relative to ref node in world coordinates
    avgWheelNodePos:setAdd(obj:getNodePosition(wheel.node1))
    numOfWheels = numOfWheels + 1
  end
  if numOfWheels == 0 then return 0 end

  avgWheelNodePos:setScaled(1 / numOfWheels)

  local dirVec = obj:getDirectionVector()
  local avgFrontWheelPos, frontWheelCount = vec3(), 0
  local avgBackWheelPos, backWheelCount = vec3(), 0
  for _, wheel in pairs(wheels.wheels) do
    local wheelPos = obj:getNodePosition(wheel.node1)
    if wheelPos:dot(dirVec) > avgWheelNodePos:dot(dirVec) then
      avgFrontWheelPos:setAdd(wheelPos)
      frontWheelCount = frontWheelCount + 1
    else
      avgBackWheelPos:setAdd(wheelPos)
      backWheelCount = backWheelCount + 1
    end
  end

  avgFrontWheelPos:setScaled(1 / frontWheelCount)
  avgBackWheelPos:setScaled(1 / backWheelCount)

  return avgFrontWheelPos:distance(avgBackWheelPos)
end

local function updatePlayerData()
  mapmgr.getObjects()
  if mapmgr.objects[M.targetObjectID] and targetObjectSelectionMode == 'manual' then
    player = mapmgr.objects[M.targetObjectID]
  elseif tableSize(mapmgr.objects) == 2 then
    if player ~= nil then
      player = mapmgr.objects[player.id]
    else
      for k, v in pairs(mapmgr.objects) do
        if k ~= objectId then
          M.targetObjectID = k
          player = v
          break
        end
      end
      targetObjectSelectionMode = 'auto'
    end
  else
    if player ~= nil and player.active == true then
      player = mapmgr.objects[player.id]
    else
      for k, v in pairs(mapmgr.objects) do
        if k ~= objectId and v.active == true then
          M.targetObjectID = k
          player = v
          break
        end
      end
      targetObjectSelectionMode = 'targetActive'
    end
  end
end

local function driveCar(steering, throttle, brake, parkingbrake)
  input.event("steering", steering, "FILTER_AI", nil, nil, nil, "ai")
  input.event("throttle", throttle, "FILTER_AI", nil, nil, nil, "ai")
  input.event("brake", brake, "FILTER_AI", nil, nil, nil, "ai")
  input.event("parkingbrake", parkingbrake, "FILTER_AI", nil, nil, nil, "ai")

  lastCommand.steering = steering
  lastCommand.throttle = throttle
  lastCommand.brake = brake
  lastCommand.parkingbrake = parkingbrake
end

local function getObjectBoundingBox(id)
  local x = obj:getObjectDirectionVector(id)
  local z = obj:getObjectDirectionVectorUp(id)
  local y = z:cross(x)
  y:setScaled(obj:getObjectInitialWidth(id) * 0.5 / max(y:length(), 1e-30))
  x:setScaled(obj:getObjectInitialLength(id) * 0.5)
  z:setScaled(obj:getObjectInitialHeight(id) * 0.5)
  return obj:getObjectCenterPosition(id), x, y, z
end

local function populateOBBinRange(range)
  range = range * range
  local i = 0
  for id in pairs(mapmgr.getObjects()) do
    if id ~= objectId then
      local pos = obj:getObjectCenterPosition(id)
      if pos:squaredDistance(ai.pos) < range then
        twt.OBBinRange[i+1] = pos

        -- Get bounding box direction vectors
        twt.OBBinRange[i+2] = obj:getObjectDirectionVector(id) -- x
        twt.OBBinRange[i+4] = obj:getObjectDirectionVectorUp(id) -- z
        twt.OBBinRange[i+3] = twt.OBBinRange[i+3] or vec3()
        twt.OBBinRange[i+3]:setCross(twt.OBBinRange[i+4], twt.OBBinRange[i+2]); twt.OBBinRange[i+3]:normalize() -- y (left)

        -- Scale bounding box direction vectors to vehicle diamensions
        twt.OBBinRange[i+3]:setScaled(obj:getObjectInitialWidth(id) * 0.5)
        twt.OBBinRange[i+2]:setScaled(obj:getObjectInitialLength(id) * 0.5)
        twt.OBBinRange[i+4]:setScaled(obj:getObjectInitialHeight(id) * 0.5)
        i = i + 4
      end
    end
  end
  twt.OBBinRange.n = i
end

local function castRay(rpos, rdir, rayDist)
  for i = 1, twt.OBBinRange.n, 4 do
    local minHit, maxHit = intersectsRay_OBB(rpos, rdir, twt.OBBinRange[i], twt.OBBinRange[i+1], twt.OBBinRange[i+2], twt.OBBinRange[i+3])
    if maxHit > 0 then
      rayDist = min(rayDist, max(minHit, 0))
    end
  end
  return obj:castRayStatic(rpos, rdir, rayDist)
end

local function driveToTarget(targetPos, throttle, brake, targetSpeed)
  if not targetPos then return end

  local plan = currentRoute and currentRoute.plan
  targetSpeed = targetSpeed or plan and plan.targetSpeed
  if not targetSpeed then return end

  local targetVec = targetPos - ai.pos; targetVec:normalize()
  local dirAngle = asin(ai.rightVec:dot(targetVec))

  -- oversteer
  local throttleOverCoef = 1
  if ai.speed > 1 then
    local rightVel = ai.rightVec:dot(ai.vel)
    if rightVel * ai.rightVec:dot(targetPos - ai.pos) > 0 then
      local rotVel = min(1, (ai.prevDirVec:projectToOriginPlane(ai.upVec):normalized()):distance(ai.dirVec) * dt * 10000)
      throttleOverCoef = max(0, 1 - abs(rightVel * ai.speed * 0.05) * min(1, dirAngle * dirAngle * ai.speed * 6) * rotVel)
    end
  end

  local dirVel = ai.vel:dot(ai.dirVec)
  local absAiSpeed = abs(dirVel)
  local throttleUnderCoef = 1
  local brakeCoef = 1

  if plan and plan[3] and dirVel > 3 then
    local p1, p2 = plan[1].pos, plan[2].pos
    local p2p1DirVec = p2 - p1; p2p1DirVec:normalize()

    local tp2 = (plan.targetSeg or 0) > 1 and targetPos or plan[3].pos
    local targetSide = (tp2 - p2):dot(p2p1DirVec:cross(ai.upVec))

    local outDeviation = aiDeviationSmoother:value() - aiDeviation * sign(targetSide)
    outDeviation = sign(outDeviation) * min(1, abs(outDeviation))
    aiDeviationSmoother:set(outDeviation)
    aiDeviationSmoother:getUncapped(0, dt)

    if outDeviation > 0 and absAiSpeed > 3 then
      local steerCoef = outDeviation * absAiSpeed * absAiSpeed * min(1, dirAngle * dirAngle * 4)
      local understeerCoef = max(0, steerCoef) * min(1, abs(ai.vel:dot(p2p1DirVec) * 3))
      local noUndersteerCoef = max(0, 1 - understeerCoef)
      throttleUnderCoef = noUndersteerCoef
      brakeCoef = min(brakeCoef, max(0, 1 - understeerCoef * understeerCoef))
    end
  else
    aiDeviationSmoother:set(0)
  end

  -- wheel speed
  local throttleTcsCoef = 1
  if absAiSpeed > 0.05 then
    if sensors.gz <= 0.1 then
      local totalSlip = 0
      local propSlip = 0
      local totalDownForce = 0
      local lwheels = wheels.wheels
      for i = 0, tableSizeC(lwheels) - 1 do
        local wd = lwheels[i]
        if not wd.isBroken then
          local lastSlip = wd.lastSlip
          local downForce = wd.downForceRaw
          totalSlip = totalSlip + lastSlip * downForce
          totalDownForce = totalDownForce + downForce
          if wd.isPropulsed then
            propSlip = max(propSlip, lastSlip)
          end
        end
      end

      absAiSpeed = max(absAiSpeed, 3)

      totalSlip = totalSlip * 4 / (totalDownForce + 1e-25)

      -- abs
      brakeCoef = brakeCoef * square(max(0, absAiSpeed - totalSlip) / absAiSpeed)

      -- tcs
      propSlip = propSlip * (parameters.driveStyle == 'offRoad' and 0.25 or 1)
      local tcsCoef = max(0, absAiSpeed - propSlip * propSlip) / absAiSpeed
      throttleTcsCoef = min(tcsCoef, smoothTcs:get(tcsCoef, dt))
    else
      brakeCoef = 0
      throttleTcsCoef = 0
    end
  end

  local throttleCoef = 1
  if parameters.oversteerThrottleControl ~= 'off' then
    throttleCoef = throttleCoef * throttleOverCoef
  end
  if parameters.understeerThrottleControl ~= 'off' then
    throttleCoef = throttleCoef * throttleUnderCoef
  end
  if parameters.throttleTcs ~= 'off' then
    throttleCoef = throttleCoef * throttleTcsCoef
  end

  local dirTarget = ai.dirVec:dot(targetVec)
  local dirTargetAxis = ai.rightVec:dot(targetVec)

  if crash.manoeuvre == 1 and dirTarget < ai.dirVec:dot(crash.dir) then
    driveCar(-sign(dirAngle), brake * brakeCoef, throttle * throttleCoef, 0)
    return
  else
    crash.manoeuvre = 0
  end

  if parameters.driveStyle == 'offRoad' then
    brakeCoef = 1
    throttleCoef = sqrt(throttleCoef)
  end

  aiForceGoFrontTime = max(0, aiForceGoFrontTime - dt)
  if twt.state == 1 and aiCannotMoveTime > 1 and aiForceGoFrontTime == 0 then
    twt.state = 0
    aiCannotMoveTime = 0
    aiForceGoFrontTime = 2
  end

  if aiForceGoFrontTime > 0 and dirTarget < 0 then
    dirTarget = -dirTarget
    dirAngle = -dirAngle
  end

  if currentRoute and (dirTarget < 0 or (twt.state == 1 and dirTarget < 0.866)) then   -- TODO: Improve entry condition when twt.state == 1
    local helperVec = 0.35 * ai.upVec -- auxiliary vector
    twt.posTable[2]:setAdd2(ai.pos, helperVec)
    helperVec:setScaled2(ai.dirVec, -0.05 * ai.length)
    twt.posTable[2]:setAdd(helperVec)
    helperVec:setScaled2(ai.rightVec, 0.5 * (0.7 * ai.width)) -- lateral translation
    twt.posTable[2]:setAdd(helperVec) -- front right corner pos
    helperVec:setScaled(-2)
    twt.posTable[1]:setAdd2(twt.posTable[2], helperVec) -- front left corner pos
    helperVec:setScaled2(ai.dirVec, -0.9 * ai.length) -- longitudinal translation
    twt.posTable[3]:setAdd2(twt.posTable[2], helperVec) -- back right corner pos
    twt.posTable[4]:setAdd2(twt.posTable[1], helperVec) -- back left corner pos

    twt.dirTable[1]:setScaled2(ai.rightVec, -1)
    twt.dirTable[2]:set(ai.dirVec)
    twt.dirTable[3]:set(ai.rightVec)
    twt.dirTable[4]:setScaled2(ai.dirVec, -1)

    local sizeRatio = ai.length/ai.width
    local blueNoiseRange = 6 + 2 * sizeRatio
    local rayDist = 4 * ai.wheelBase -- TODO: Optimize rayDist. Higher is better for more open spaces but w performance hit
    populateOBBinRange(rayDist)
    local tmpVec = vec3()
    local RRPicks = max(1, min(floor(150 * dt + 0.5), 8)) -- x * dt where x/fps is the numer of samples
    for k = 1, RRPicks do --the ray cast loop: each iteration scans one area and casts on the minimum
      local i = 0
      local blueIndex = twt.blueNoiseRR * blueNoiseRange
      if blueIndex < 3 then
        i = floor(1 + blueIndex)
      elseif blueIndex < 6 then
        i = floor(1 + blueIndex) + 1
      elseif blueIndex < 6 + sizeRatio then
        i = 4
      else
        i = 8
      end

      local j = i * 4
      tmpVec:setLerp(twt.posTable[twt.RRT[j-3]], twt.posTable[twt.RRT[j-2]], twt.biasedCoefs[i])
      helperVec:setLerp(twt.dirTable[twt.RRT[j-1]], twt.dirTable[twt.RRT[j]], twt.biasedCoefs[i]) -- LERP corner direction
      helperVec:normalize()
      local rayLen = castRay(tmpVec, helperVec, min(twt.rayMins[i], rayDist))
      if twt.rayMins[i] > rayLen or rayLen == rayDist then
        twt.minRayCoefs[i] = twt.biasedCoefs[i]
        twt.rayMins[i] = rayLen
      else
        tmpVec:setLerp(twt.posTable[twt.RRT[j-3]], twt.posTable[twt.RRT[j-2]], twt.minRayCoefs[i])
        helperVec:setLerp(twt.dirTable[twt.RRT[j-1]], twt.dirTable[twt.RRT[j]], twt.minRayCoefs[i]) -- LERP corner direction
        helperVec:normalize()
        twt.rayMins[i] = castRay(tmpVec, helperVec, min(max(2 * twt.rayMins[i], 0.02), rayDist))
      end
      twt.blueNoiseRR = getBlueNoise1d(twt.blueNoiseRR)
      twt.blueNoiseCoefs[i] = getBlueNoise1d(twt.blueNoiseCoefs[i])
      local criticality = 2 * twt.rayMins[i] / (twt.rayMins[i] + rayDist) + 0.25
      twt.biasedCoefs[i] = biasGainFun(twt.blueNoiseCoefs[i], twt.minRayCoefs[i], criticality)
    end
    local minRayDist = min(twt.rayMins[1], twt.rayMins[2], twt.rayMins[3], twt.rayMins[4], twt.rayMins[5], twt.rayMins[6], twt.rayMins[7], twt.rayMins[8])

    twt.sampleCounter = twt.sampleCounter + 1
    if twt.state == 0 then
      if twt.sampleCounter * dt > max(0.5, min(50 * dt, 2.5)) and ai.speed <= 0.5 then -- TODO: Optimize sample count condition
        twt.state = 1
      else
        local speed = max(0, ai.speed - 0.25)
        local throttle = max(0, -sign(speed * dirVel)) * 0.3
        local brake = max(0, sign(speed * dirVel)) * 0.3
        driveCar(0, throttle, brake, 0)
      end
    end

    if twt.state == 1 then  -- start driving
      if twt.targetSpeed < 0.66 or twt.minRay == "S" then -- TODO: Some branches may be consolidated
        if minRayDist == twt.rayMins[7] then
          twt.dirState[1] = 1
          twt.dirState[2] = sign2(dirTargetAxis)
          twt.minRay = "BL"
        elseif minRayDist == twt.rayMins[5] then
          twt.dirState[1] = 1
          twt.dirState[2] = sign2(dirTargetAxis)
          twt.minRay = "BR"
        elseif minRayDist == twt.rayMins[1] then
          twt.dirState[1] = -1
          twt.dirState[2] = -sign2(dirTargetAxis)
          twt.minRay = "FL"
          if twt.dirState[2] == 1 and twt.rayMins[8] < 0.4 and twt.targetSpeed < 0.6 then twt.dirState[2] = 0 end
        elseif minRayDist == twt.rayMins[3] then
          twt.dirState[1] = -1
          twt.dirState[2] = -sign2(dirTargetAxis)
          if twt.dirState[2] == -1 and twt.rayMins[4] < 0.4 and twt.targetSpeed < 0.6 then twt.dirState[2] = 0 end
          twt.minRay = "FR"
        elseif minRayDist == twt.rayMins[6] then
          twt.dirState[1] = 1
          twt.dirState[2] = sign2(dirTargetAxis)
          twt.minRay = "B"
        elseif minRayDist == min(twt.rayMins[4], twt.rayMins[8]) then
          local sideRuler = 0
          local minSide =  minRayDist == twt.rayMins[8] and "L" or "R"
          if minSide == "L" then
            sideRuler = ai.length * (1 - twt.minRayCoefs[8])
          else
            sideRuler = ai.length * twt.minRayCoefs[4]
          end
          twt.dirState[2] = 0
          if sideRuler < twt.rayMins[6] and dirTarget < 0 then --TODO : test this
            twt.dirState[1] = -1
          elseif (ai.length - sideRuler) < twt.rayMins[2] then
            twt.dirState[1] = 1
            if minSide == "L" then
              twt.dirState[2] = 1
            else
              twt.dirState[2] = -1
            end
          end
          twt.minRay = "S"
        else
          twt.dirState[1] = -1
          twt.dirState[2] = -sign2(dirTargetAxis)
          twt.minRay = "F"
        end
      end

      local threshold = min(ai.speed - 0.1, 0.66)
      local dirCoef, minDist = 1, nil --TODO: what is car is trapped/sandwiched?
      if twt.dirState[1] == -1 then -- reverse
        dirCoef = min(1.2 - dirTarget, 1) -- dirTarget -> targetSpeed modulation
        if twt.dirState[2] == -1 then -- steer left
          minDist = min(twt.rayMins[4], twt.rayMins[6], twt.rayMins[7])
        elseif twt.dirState[2] == 1 then -- steer right
          minDist = min(twt.rayMins[5], twt.rayMins[6], twt.rayMins[8])
        else -- no steering
          minDist = twt.rayMins[6]
          if twt.minRay ~= "S" then
            threshold = twt.rayMins[2] -- possibly max(threshold, twt.rayMins[2])
          end
        end
      else -- forward
        if twt.dirState[2] == -1 then
          minDist = min(twt.rayMins[1], twt.rayMins[2], twt.rayMins[8])
        elseif twt.dirState[2] == 1 then
          minDist = min(twt.rayMins[2], twt.rayMins[3], twt.rayMins[4])
        else
          minDist = twt.rayMins[2]
        end
      end

      local targetSpeed = sqrt(2 * g * min(aggression, staticFrictionCoef) * max(0, minDist - threshold) * dirCoef)
      twt.targetSpeed = max(min(twt.speedSmoother:get(targetSpeed, dt), min(6, aggression * 6)), 0.3)
      local speedDif = twt.targetSpeed - twt.dirState[1] * sign2(dirVel) * ai.speed
      local steering = twt.steerSmoother:get(twt.dirState[2], dt)
      local pbrake = 0 -- * clamp(sign2(0.83 + ai.upVec:dot(gravityDir)), 0, 1) -- >= 10 deg
      local throttle, brake = 0, 0
      if twt.dirState[1] == -1 then
        throttle = clamp(-speedDif * 0.4, 0, 0.4)
        brake = clamp(speedDif * 0.2, 0, 1)
      elseif twt.dirState[1] == 1 then
        throttle = clamp(speedDif * 0.2, 0, 1)
        brake = clamp(-speedDif * 0.4, 0, 0.4)
      end
      driveCar(steering, throttle, brake, pbrake)
    end
  else
    twt.reset()

    local pbrake
    if ai.vel:dot(ai.dirVec) < 0 and ai.speed > 0.1 then
      if ai.speed < 0.15 and targetSpeed <= 1e-5 then
        pbrake = 1
      else
        pbrake = 0
      end
      throttle = 0.5 * throttleCoef
      brake = 0
    else
      if (ai.speed > 4 and ai.speed < 30 and abs(dirAngle) > 0.97 and brake == 0) or (ai.speed < 0.15 and targetSpeed <= 1e-5) then
        pbrake = 1
      else
        pbrake = 0
      end
      throttle = throttle * throttleCoef
      brake = brake * brakeCoef
    end

    local aggSq = square(aggression + max(0, -(ai.dirVec:dot(gravityDir))))
    local rate = max(throttleSmoother[throttleSmoother:value() < throttle], 10 * aggSq * aggSq)
    throttle = throttleSmoother:getWithRateUncapped(throttle, dt, rate)

    driveCar(dirAngle, throttle, brake, pbrake)
  end
end

local function posOnPlan(pos, plan, dist)
  if not plan then return end
  dist = dist or 4
  dist = dist * dist
  local bestSeg, bestXnorm
  for i = 1, #plan-2 do
    local p0, p1 = plan[i].pos, plan[i+1].pos
    local xnorm1 = pos:xnormOnLine(p0, p1)
    if xnorm1 > 0 then
      local p2 = plan[i+2].pos
      local xnorm2 = pos:xnormOnLine(p1, p2)
      if xnorm1 < 1 then -- contained in segment i
        if xnorm2 > 0 then -- also partly contained in segment i+1
          local sqDistFromP1 = pos:squaredDistance(p1)
          if sqDistFromP1 <= dist then
            bestSeg = i
            bestXnorm = 1
            break -- break inside conditional
          end
        else
          local sqDistFromLine = pos:squaredDistance(p0 + (p1 - p0) * xnorm1)
          if sqDistFromLine <= dist then
            bestSeg = i
            bestXnorm = xnorm1
          end
          break -- break should be outside above conditional
        end
      elseif xnorm2 < 0 then
        local sqDistFromP1 = pos:squaredDistance(p1)
        if sqDistFromP1 <= dist then
          bestSeg = i
          bestXnorm = 1
        end
        break -- break outside conditional
      end
    else
      break
    end
  end

  return bestSeg, bestXnorm
end

local function aiPosOnPlan(plan)
  local planCount = plan.planCount
  local aiSeg = 1
  local aiXnormOnSeg = 0
  for i = 1, planCount-1 do
    local p0Pos, p1Pos = plan[i].pos, plan[i+1].pos
    local xnorm = ai.pos:xnormOnLine(p0Pos, p1Pos)
    if xnorm < 1 then
      if i < planCount - 2 then
        local nextXnorm = ai.pos:xnormOnLine(p1Pos, plan[i+2].pos)
        if nextXnorm >= 0 then
          local p1Radius = plan[i+1].radiusOrig
          if ai.pos:squaredDistance(linePointFromXnorm(p1Pos, plan[i+2].pos, nextXnorm)) <
              square(ai.width + lerp(p1Radius, plan[i+2].radiusOrig, min(1, nextXnorm))) then
            aiXnormOnSeg = nextXnorm
            aiSeg = i + 1
            break
          end
        end
      end
      aiXnormOnSeg = xnorm
      aiSeg = i
      break
    end
  end

  local disp = 0
  if aiSeg > 1 then
    local sumLen = 0
    disp = aiSeg - 1
    for i = 1, disp do
      sumLen = sumLen + plan[i].length
    end

    for i = 1, plan.planCount do
      plan[i] = plan[i+disp]
      if disp > 0 and i + disp > plan.planCount then
        velocities[i] = vec3(0,0,0)
      else
        velocities[i] = velocities[i+disp]
      end
    end

    plan.planCount = plan.planCount - disp
    plan.planLen = max(0, plan.planLen - sumLen)
    plan.stopSeg = plan.stopSeg and max(1, plan.stopSeg - disp)
  end

  plan.aiXnormOnSeg = aiXnormOnSeg
  plan.aiSeg = aiSeg - disp
end

-- returns the node index
local function getLastNodeWithinDistance(plan, dist)
  dist = dist - plan[1].length * (1 - plan.aiXnormOnSeg)
  if dist < 0 then
    return 1
  end

  local planSeg = plan.planCount
  for i = 2, plan.planCount-1 do
    dist = dist - plan[i].length
    if dist < 0 then
      planSeg = i
      break
    end
  end

  return planSeg
end

-- IMPORTANT - CUSTOM CODE BELOW ---
local function calculateTarget(plan)
  aiPosOnPlan(plan)

  -- Base target length calculation
  local baseTargetLength = max(ai.speed * parameters.lookAheadKv * 1.3, 6.0)

  -- Adjust targetLength based on traffic density and AI's speed
  local trafficDensity = #trafficTable  -- Number of vehicles in the traffic table
  local speedFactor = clamp(ai.speed / 30, 0.5, 2)  -- Normalize speed factor between 0.5 and 2
  local trafficFactor = 1 - (clamp(trafficDensity, 0, 5) * 0.1)  -- Reduce target length

  -- Calculate dynamic targetLength
  local targetLength = baseTargetLength * speedFactor * trafficFactor

  local overtakeBonus = aggression * 2.5 -- Aggression scales planning distance
  -- Ensure the target length is not too short or too long
  targetLength = clamp(targetLength + overtakeBonus, 6.0, 40)  -- Clamp between 6m and 40m

  -- Function to calculate local traffic density near a plan node
  local function getLocalTrafficDensity(nodePos, radius)
    local density = 0
    for _, vehicle in ipairs(trafficTable) do
      if vehicle.pos:distance(nodePos) <= radius then
        density = density + 1
      end
    end
    return density
  end

  -- Function to calculate curvature between two segments
  local function calculateCurvature(pos1, pos2, pos3)
    local vec1 = pos2 - pos1
    local vec2 = pos3 - pos2
    local cross = vec1:cross(vec2)
    local curvature = cross:length() / (vec1:length() * vec2:length() + 1e-30)  -- Avoid division by zero
    return curvature
  end

  local function getCurvatureFactor(curvature)
    -- Define curvature thresholds and scaling factors
    local straightThreshold = 0.05  -- Curvature below this is considered a straight
    local moderateThreshold = 0.2   -- Curvature below this is considered a moderate turn
    local sharpThreshold = 0.5      -- Curvature above this is considered a sharp turn

    -- Define scaling factors for each curvature range
    local straightFactor = 1.0      -- No adjustment on straights
    local moderateFactor = 5        -- Gentle adjustment on moderate turns
    local sharpFactor = 20          -- Aggressive adjustment on sharp turns

    -- Piecewise function to calculate curvature factor
    local factor
    if curvature < straightThreshold then
      -- Straight section: no adjustment
      factor = straightFactor
    elseif curvature < moderateThreshold then
      -- Moderate turn: gentle adjustment
      factor = 1 / (1 + curvature * moderateFactor)
    else
      -- Sharp turn: aggressive adjustment
      factor = 1 / (1 + curvature * sharpFactor)
    end

    -- Clamp the factor to ensure it stays within reasonable bounds
    return clamp(factor, 0.5, 1)
  end

  -- Adjust targetLength based on the AI's position along the current segment (if there are enough plan nodes)
  if plan.planCount >= 3 then
    local xnorm = clamp(plan.aiXnormOnSeg, 0, 1)  -- Normalized position along the current segment
    local remainingDistanceCurrentSeg = plan[1].length * (1 - xnorm)  -- Remaining distance in the current segment
    local weightedNextSegLength = plan[2].length * xnorm  -- Weighted contribution of the next segment

    -- Calculate curvature for the current and next segments
    local curvatureCurrent = calculateCurvature(plan[1].pos, plan[2].pos, plan[3].pos)
    local curvatureNext = calculateCurvature(plan[2].pos, plan[3].pos, plan[4] and plan[4].pos or plan[3].pos)

    -- Get curvature factors for current and next segments
    local curvatureFactorCurrent = getCurvatureFactor(curvatureCurrent)
    local curvatureFactorNext = getCurvatureFactor(curvatureNext)

    -- Apply curvature factors to remaining distance and weighted next segment length
    remainingDistanceCurrentSeg = remainingDistanceCurrentSeg * curvatureFactorCurrent
    weightedNextSegLength = weightedNextSegLength * curvatureFactorNext

    -- Update targetLength to account for the current and next segment
    targetLength = max(targetLength, remainingDistanceCurrentSeg, weightedNextSegLength)

    -- Optional: Add a buffer for smoother transitions between segments
    local transitionBuffer = 2.0  -- Add a small buffer to smooth transitions
    targetLength = targetLength + transitionBuffer
  end

  --- IMPORTANT - CUSTOM CODE ABOVE ---

  local remainder = targetLength

  local targetPos = vec3(plan[plan.planCount].pos)
  local targetSeg = max(1, plan.planCount-1)
  local prevPos = linePointFromXnorm(plan[1].pos, plan[2].pos, plan.aiXnormOnSeg) -- ai.pos

  local segVec, segLen = vec3(), nil
  for i = 2, plan.planCount do
    local pos = plan[i].pos

    segVec:setSub2(pos, prevPos)
    segLen = segLen or segVec:length()

    if remainder <= segLen then
      targetSeg = i - 1
      targetPos:setScaled2(segVec, remainder / (segLen + 1e-30)); targetPos:setAdd(prevPos)

      -- smooth target
      local xnorm = clamp(targetPos:xnormOnLine(prevPos, pos), 0, 1)
      local lp_n1n2 = linePointFromXnorm(prevPos, pos, xnorm * 0.5 + 0.25)
      if xnorm <= 0.5 then
        if i >= 3 then
          targetPos = linePointFromXnorm(linePointFromXnorm(plan[i-2].pos, prevPos, xnorm * 0.5 + 0.75), lp_n1n2, xnorm + 0.5)
        end
      else
        if i <= plan.planCount - 2 then
          targetPos = linePointFromXnorm(lp_n1n2, linePointFromXnorm(pos, plan[i+1].pos, xnorm * 0.5 - 0.25), xnorm - 0.5)
        end
      end
      break
    end

    prevPos = pos
    remainder = remainder - segLen
    segLen = plan[i].length
  end

  plan.targetPos = targetPos
  plan.targetSeg = targetSeg
end

local function targetsCompatible(baseRoute, newRoute)
  local baseTvec = baseRoute.plan.targetPos - ai.pos
  local newTvec = newRoute.plan.targetPos - ai.pos
  if ai.speed < 2 then return true end
  if newTvec:dot(ai.dirVec) * baseTvec:dot(ai.dirVec) <= 0 then return false end
  local baseTargetRight = baseTvec:cross(ai.upVec); baseTargetRight:normalize()
  return abs(newTvec:normalized():dot(baseTargetRight)) * ai.speed < 2
end

local function getMinPlanLen(limLow, speed, accelg)
  -- given current speed, distance required to come to a stop if I can decelerate at 0.2g
  limLow = limLow or 150
  speed = speed or ai.speed
  accelg = max(0.2, accelg or 0.2)
  return min(550, max(limLow, 0.5 * speed * speed / (accelg * g)))
end

local function pickAiWp(wp1, wp2, dirVec)
  dirVec = dirVec or ai.dirVec
  local vec1 = mapData.positions[wp1] - ai.pos
  local vec2 = mapData.positions[wp2] - ai.pos
  local dot1 = vec1:dot(dirVec)
  local dot2 = vec2:dot(dirVec)
  if (dot1 * dot2) <= 0 then
    if dot1 < 0 then
      return wp2, wp1
    end
  else
    if vec2:squaredLength() < vec1:squaredLength() then
      return wp2, wp1
    end
  end
  return wp1, wp2
end

local function pathExtend(path, newPath)
  if newPath == nil then return end
  local pathCount = #path
  if path[pathCount] ~= newPath[1] then return end
  pathCount = pathCount - 1
  for i = 2, #newPath do
    path[pathCount+i] = newPath[i]
  end
end

-- http://cnx.org/contents/--TzKjCB@8/Projectile-motion-on-an-inclin
local function projectileSqSpeedToRangeRatio(pos1, pos2, pos3)
  local sinTheta = (pos2.z - pos1.z) / pos1:distance(pos2)
  local sinAlpha = (pos3.z - pos2.z) / pos2:distance(pos3)
  local cosAlphaSquared = max(1 - sinAlpha * sinAlpha, 0)
  local cosTheta = sqrt(max(1 - sinTheta * sinTheta, 0)) -- in the interval theta = {-pi/2, pi/2} cosTheta is always positive
  return 0.5 * g * cosAlphaSquared / max(cosTheta * (sinTheta*sqrt(cosAlphaSquared) - cosTheta*sinAlpha), 0)
end

local function getPathLen(path, startIdx, stopIdx)
  if not path then return end
  startIdx = startIdx or 1
  stopIdx = stopIdx or #path
  local positions = mapData.positions
  local pathLen = 0
  for i = startIdx+1, stopIdx do
    pathLen = pathLen + positions[path[i-1]]:distance(positions[path[i]])
  end

  return pathLen
end

local function getPathBBox(path, startIdx, stopIdx)
  if not path then return end
  startIdx = startIdx or 1
  stopIdx = stopIdx or #path

  local positions = mapData.positions
  local p = positions[path[startIdx]]
  local v = positions[path[stopIdx]] + p; v:setScaled(0.5)
  local r = getPathLen(path, startIdx, stopIdx) * 0.5

  return {v.x - r, v.y - r, v.x + r, v.y + r}, v, r
end

local function waypointInPath(path, waypoint, startIdx, stopIdx)
  if not path or not waypoint then return end
  startIdx = startIdx or 1
  stopIdx = stopIdx or #path
  for i = startIdx, stopIdx do
    if path[i] == waypoint then
      return i
    end
  end
end

local function getPlanLen(plan, from, to)
  from = max(1, from or 1)
  to = min(plan.planCount-1, to or math.huge)
  local planLen = 0
  for i = from, to do
    planLen = planLen + plan[i].length
  end

  return planLen
end

local function abortUpcommingLaneChange()
  if not currentRoute then return end
  if currentRoute.laneChanges[1] then
    currentRoute.laneChanges[1].side = 0
  end
  local lastPlanPidx = currentRoute.plan[currentRoute.plan.planCount].pathidx
  for _, lc in ipairs(currentRoute.laneChanges) do
    if lc.pathIdx <= lastPlanPidx then
      lc.side = 0
    end
  end
end

local function updatePlanLen(plan, j, k)
  -- bulk recalculation of plan edge lengths and length of entire plan
  -- j: index of earliest node position that has changed
  -- k: index of latest node position that has changed
  j = max((j or 1) - 1, 1)
  k = min(k or plan.planCount, plan.planCount-1)

  local planLen = plan.planLen
  for i = j, k do
    local edgeLen = plan[i+1].pos:distance(plan[i].pos)
    planLen = planLen - plan[i].length + edgeLen
    plan[i].length = edgeLen
  end
  plan.planLen = planLen
end

-- expand lane lateral limits of this plan node to the lane range limits
local function openLaneToLaneRange(planNode)
  local roadHalfWidth = planNode.radiusOrig * planNode.chordLength
  planNode.laneLimLeft = linearScale(planNode.rangeLeft, 0, 1, -roadHalfWidth, roadHalfWidth)
  planNode.laneLimRight = linearScale(planNode.rangeRight, 0, 1, -roadHalfWidth, roadHalfWidth)
  planNode.lanesOpen = true
end

-- expand lane lateral limits to the lane range for all nodes up to and including idx
local function openPlanLanesToLaneRange(plan, idx)
  plan = plan or (currentRoute and currentRoute.plan)
  if not plan then return end
  for i = 1, min(plan.planCount, idx) do
    openLaneToLaneRange(plan[i])
  end
end

local function laneChange(plan, dist, signedDisp)
  if not plan and currentRoute then plan = currentRoute.plan end
  if not plan then return end

  -- Apply node displacement
  local invDist = 1 / (dist + 1e-30)
  local curDist, normalDispVec = 0, vec3()
  for i = 2, plan.planCount do
    openLaneToLaneRange(plan[i])
    curDist = curDist + plan[i-1].length
    plan[i].lateralXnorm = clamp(plan[i].lateralXnorm + signedDisp * min(curDist * invDist, 1), plan[i].laneLimLeft, plan[i].laneLimRight)
    normalDispVec:setScaled2(plan[i].normal, plan[i].lateralXnorm)
    plan[i].pos:setAdd2(plan[i].posOrig, normalDispVec)

    -- Recalculate vec and dirVec
    plan[i].vec:setSub2(plan[i-1].pos, plan[i].pos); plan[i].vec.z = 0
    plan[i].dirVec:set(plan[i].vec)
    plan[i].dirVec:normalize()
  end

  updatePlanLen(plan)

  --[[ For debugging
  table.clear(newPositionsDebug)
  for i = 1, #newPositions do
    newPositionsDebug[i] = vec3(newPositions[i])
  end
  --]]
end

local function setStopPoint(plan, dist, args)
  if not plan and currentRoute then
    plan = currentRoute.plan
  end
  if not plan then return end

  if not dist then -- clear stop segment
    plan.stopSeg = nil
    return
  end

  if (args or E).avoidJunction and currentRoute.path then -- prevents stopping directly in junctions
    -- this code is temporary, and inefficient...
    local seg
    while true do
      seg = getLastNodeWithinDistance(plan, dist)
      local nid = currentRoute.path[plan[seg].pathidx]
      if seg < plan.planCount - 1 and tableSize(mapData.graph[nid]) > 2 and plan[seg].pos:squaredDistance(mapData.positions[nid]) <= square(mapData.radius[nid]) then
        dist = dist + 20
      else
        break
      end
    end
    plan.stopSeg = seg
  else
    plan.stopSeg = getLastNodeWithinDistance(plan, dist)
  end
end

local function numOfLanesFromRadius(rad1, rad2)
  return max(1, math.floor(min(rad1, rad2 or math.huge) * 2 / 3.61 + 0.5)) -- math.floor(min(rad1, rad2) / 2.7) + 1
end

local laneStringBuffer = buffer.new()
local function flipLanes(lanes)
  -- ex. '--+++' becomes '---++'
  for i = #lanes, 1, -1 do
    laneStringBuffer:put(lanes:byte(i) == 43 and '-' or lanes:byte(i) == 45 and '+' or '0')
  end
  return laneStringBuffer:get()
end

-- returns the number of lanes in a given direction
local function numOfLanesInDirection(lanes, dir)
  -- lanes: a lane string
  -- dir: '+' or '-'
  dir = dir == '+' and 43 or dir == '-' and 45
  local lanesN = 0
  for i = 1, #lanes, 1 do
    if lanes:byte(i) == dir then
      lanesN = lanesN + 1
    end
  end
  return lanesN
end

-- Returns the lane configuration of an edge as traversed in the fromNode -> toNode direction
-- if an edge does not have lane data they are deduced from the node radii
local function getEdgeLaneConfig(fromNode, toNode)
  local lanes
  local edge = mapData.graph[fromNode][toNode]
  if edge.lanes then
    lanes = edge.lanes
  else -- make up some lane data in case they don't exist
    if edge.oneWay then
      local numOfLanes = numOfLanesFromRadius(mapData.radius[fromNode], mapData.radius[toNode])
      lanes = string.rep("+", numOfLanes)
    else
      local numOfLanes = max(1, math.floor(numOfLanesFromRadius(mapData.radius[fromNode], mapData.radius[toNode]) * 0.5))
      if mapmgr.rules.rightHandDrive then
        lanes = string.rep("+", numOfLanes)..string.rep("-", numOfLanes)
      else
        lanes = string.rep("-", numOfLanes)..string.rep("+", numOfLanes)
      end
    end
  end

  return edge.inNode == fromNode and lanes or flipLanes(lanes) -- flip lanes string based on inNode data
end

-- Calculate the edge incident on wp2 which is most similar to the edge wp1->wp2
local function roadNaturalContinuation(wp1, wp2)
  local inLaneConfig = getEdgeLaneConfig(wp1, wp2)
  local inRadiuswp2, inRadiuswp1 = mapData:getEdgeRadii(wp2, wp1)
  local inEdgeDir = vec3(); inEdgeDir:setSub2(mapData:getEdgePositions(wp2, wp1)); inEdgeDir:normalize()
  local laneFlow = mapData.graph[wp1][wp2].drivability * 4 * min(inRadiuswp2, inRadiuswp1) / #inLaneConfig
  local inLaneCount = numOfLanesInDirection(inLaneConfig, '+')
  local inFwdFlow = inLaneCount * laneFlow
  local inLaneCountOpposite = (#inLaneConfig - inLaneCount)
  local inBackFlow = inLaneCountOpposite * laneFlow
  local outEdgeDir, maxOutflow, minNode = vec3(), 0, nil
  for k, v in pairs(mapData.graph[wp2]) do
    if k ~= wp1 then
      local outLaneConfig = getEdgeLaneConfig(wp2, k)
      local numOfOutLanes = numOfLanesInDirection(outLaneConfig, '+')
      outEdgeDir:setSub2(mapData:getEdgePositions(k, wp2)); outEdgeDir:normalize()
      local dirCoef = 0.5 * max(0, 1 + outEdgeDir:dot(inEdgeDir))
      local outLaneCountOpposite = (#outLaneConfig - numOfOutLanes)
      local outRadiuswp2, outRadiusk = mapData:getEdgeRadii(wp2, k)
      if numOfOutLanes == inLaneCount and  outLaneCountOpposite == inLaneCountOpposite then
        laneFlow = mapData.graph[wp2][k].drivability * 4 * 0.5 * (inRadiuswp2 + outRadiuswp2) / #outLaneConfig
      else
        laneFlow = mapData.graph[wp2][k].drivability * 4 * min(outRadiuswp2, outRadiusk)/ #outLaneConfig
      end
      local outFwdFlow = min(inFwdFlow, numOfOutLanes * laneFlow)
      local outBackFlow = min(inBackFlow, outLaneCountOpposite * laneFlow)
      local outflow = outFwdFlow * (1 + outBackFlow) * dirCoef

      if outflow > maxOutflow then
        maxOutflow = outflow
        minNode = k
      end
    end
  end

  return minNode
end


-- returns the lane indices of the left most and right most lanes in the direction of travel
local function laneRangeIdx(laneConfig)
  local numOfLanes = #laneConfig
  local leftIdx, rightIdx = 1, numOfLanes
  for i = 1, numOfLanes do
    if laneConfig:byte(i) == 43 then -- "+"
      leftIdx = i
      break
    end
  end

  for i = numOfLanes, 1, -1 do
    if laneConfig:byte(i) == 43 then -- "+"
      rightIdx = i
      break
    end
  end

  return leftIdx, rightIdx, numOfLanes
end

-- returns the lane lateral xnorm limits (boundaries in [0, 1] range 0 being the left boundary)
-- of the left most and right most lanes in the direction of travel and the number of lanes in that range.
-- This range might include lanes in the opposite direction if they are interleaved with lanes in the direction of travel
-- ex. '--++-++' the left most lane is lane 3, the right most lane is lane 7. The range is from lane 3 to lane 7 inclusive.
local function laneRange(laneConfig)
  local leftLim, rightLim, numOfLanes = laneRangeIdx(laneConfig)
  return (leftLim - 1) / numOfLanes, rightLim / numOfLanes, rightLim - leftLim + 1
end

-- Splits the lane string into three parts 1:leftIdx-1, leftIdx:rightIdx, rightIdx+1:numOfLanes and returns the three strings
-- leftIdx is the indice of the left most lane in the direction of travel
-- rightIdx is the indice of the right most lane in the direction of travel
-- therefore leftIdx:rightIdx is the lane string from the left most to the right most lane in the direction of travel
local function splitLaneRange(laneConfig)
  local leftIdx, rightIdx, numOfLanes = laneRangeIdx(laneConfig)
  --leftIdx = leftIdx
  --rightIdx = rightIdx

  return laneConfig:sub(1, leftIdx-1), laneConfig:sub(leftIdx, rightIdx), laneConfig:sub(rightIdx+1, numOfLanes)
end

-- Lateral xnorm limits ([0, 1]) of the left most and right most lanes from "lane" in the direction of "lane"
local function getLaneRangeFromLane(laneConfig, lane)
  -- laneConfig: a string representing lane configuration ex. "-a-a+a+a"
  -- lane: the lane number (1 to n) counting from left to right in the direction of travel
  local numOfLanes = #laneConfig
  local leftIdx, rightIdx = lane, lane
  -- search left
  for i = lane-1, 1, -1 do
    if laneConfig:byte(i) == 43 then -- "+"
      leftIdx = i
    else
      break
    end
  end

  -- search right
  for i = lane+1, numOfLanes do
    if laneConfig:byte(i) == 43 then -- "+"
      rightIdx = i
    else
      break
    end
  end

  return (leftIdx-1) / numOfLanes, rightIdx / numOfLanes, leftIdx, rightIdx
end

-- Calculates the composite lane configuration coming into newNode
-- and adjusted lateral position, lane limits and lane range of the last plan node.
local function processNodeIncommingLanes(newNode, planNode)
  local leftRange, centerRange, rightRange = splitLaneRange(newNode.inEdgeLanes)
  local latXnorm = planNode.lateralXnorm
  local laneLimLeft = planNode.laneLimLeft
  local laneLimRight = planNode.laneLimRight
  local halfWidth = planNode.radiusOrig * planNode.chordLength
  local numOfOutLanes = numOfLanesInDirection(newNode.outEdgeLanes, "+")
  local numOfInLanes = numOfLanesInDirection(newNode.inEdgeLanes, "+")
  local defaultLaneWidth = min(2 * halfWidth / (#newNode.inEdgeLanes), 3.45)
  local inEdgeDrivabilityInv = 1 / ((newNode.inEdgedrivability or 1) + 1e-30)
  if not planNode.rangeLeft then planNode.rangeLeft, planNode.rangeRight = laneRange(newNode.inEdgeLanes) end
  local rangeLeft = linearScale(planNode.rangeLeft or 0, 0, 1, -halfWidth, halfWidth)
  local rangeRight = linearScale(planNode.rangeRight or 1, 0, 1, -halfWidth, halfWidth)

  for nodeId, edgeData in pairs(mapData.graph[newNode.name]) do
    if nodeId ~= newNode.nextNodeInPath and nodeId ~= newNode.prevNodeInPath then -- and not mapmgr.signalsData.nodes[newNode.name]
      local lanes = getEdgeLaneConfig(nodeId, newNode.name)
      local thisEdgeInLanes = numOfLanesInDirection(lanes, '+')
      if thisEdgeInLanes > 0 then -- TODO: Should also possibly include traffic light data
        local nodePos = mapData.positions[nodeId]
        local dirRatio = max(0, (mapData.positions[newNode.nextNodeInPath or newNode.name] - newNode.posOrig):normalized():dot((newNode.posOrig - nodePos):normalized()))
        local drivabilityRatio = min(1, edgeData.drivability * inEdgeDrivabilityInv)
        thisEdgeInLanes = math.floor(thisEdgeInLanes * dirRatio * drivabilityRatio + 0.5)

        if thisEdgeInLanes > 0 then
          if newNode.inEdgeNormal:dot(nodePos) < newNode.inEdgeNormal:dot(newNode.posOrig) then -- coming into newNode from the left
            numOfInLanes = numOfInLanes + thisEdgeInLanes
            centerRange = string.rep("+", thisEdgeInLanes)..centerRange
            local radius = thisEdgeInLanes * defaultLaneWidth * 0.5
            latXnorm = latXnorm + radius
            laneLimLeft = laneLimLeft + radius
            laneLimRight = laneLimRight + radius
            halfWidth = halfWidth + radius
            rangeLeft = rangeLeft - radius
            rangeRight = rangeRight + radius -- TODO: is this correct?
          elseif numOfInLanes < numOfOutLanes then
            local capInLanes = min(numOfInLanes + thisEdgeInLanes, numOfOutLanes)
            thisEdgeInLanes = capInLanes - numOfInLanes
            numOfInLanes = capInLanes
            local radius = thisEdgeInLanes * defaultLaneWidth * 0.5
            centerRange = centerRange..string.rep("+", thisEdgeInLanes)
            latXnorm = latXnorm - radius
            laneLimLeft = laneLimLeft - radius
            laneLimRight = laneLimRight - radius
            halfWidth = halfWidth + radius
            rangeLeft = rangeLeft - radius
            rangeRight = rangeRight + radius
          end
        end
      end
    end
  end

  return leftRange..centerRange..rightRange, latXnorm, laneLimLeft, laneLimRight, rangeLeft, rangeRight, halfWidth
end

-- Calculate the most appropriate lane of laneConfig
local function getBestLane(laneConfig, nodeLatPos, laneLeftLimLatPos, laneRightLimLatPos, plan, newNode)
  -- nodeLatPos, laneLeftLimLatPos, laneRightLimLatPos are in the [0, 1] interval
  local laneWidth = laneRightLimLatPos - laneLeftLimLatPos
  local numOfLanes = max(1, #laneConfig)
  local bestError = math.huge
  local bestLane, newLaneLimLeft, newLaneLimRight
  local planPos, dirVec
  if plan then
    planPos = plan[plan.planCount].pos
    dirVec = plan[plan.planCount].pos - plan[max(1, plan.planCount-1)].pos; dirVec:normalize()
  else
    planPos = vec3()
    dirVec = planPos
    newNode = {}
    newNode.posOrig = planPos
    newNode.radiusOrig = 0
    newNode.chordLength = 0
    newNode.normal = planPos
    newNode.outEdgeLanes = laneConfig
  end
  if #newNode.outEdgeLanes == #laneConfig then -- TODO: this might not be correct
    dirVec:set(0, 0, 0)
  end
  local newNodeWidthVec = newNode.radiusOrig * newNode.chordLength * newNode.normal
  for i = 1, numOfLanes do -- traverse lanes in laneConfig
    local thisLaneLimLeft, thisLaneLimRight = (i - 1) / numOfLanes, i / numOfLanes
    local thisLaneLatPos = (thisLaneLimRight + thisLaneLimLeft) * 0.5
    local laneDir = (newNode.posOrig + (thisLaneLatPos * 2 - 1) * newNodeWidthVec) - planPos; laneDir:normalize()

    local colinearityError = 1 - max(0, dirVec:dot(laneDir))
    local distError = abs(thisLaneLatPos - nodeLatPos)
    local overlapError = laneWidth - max(0, min(thisLaneLimRight, laneRightLimLatPos) - max(thisLaneLimLeft, laneLeftLimLatPos))
    local directionError = laneConfig:byte(i) == 43 and 0 or 1
    local totalError = distError + overlapError * 10 + directionError * 100 + (numOfLanes - i) * 0.1 + colinearityError * 3

    if totalError < bestError then
      bestError = totalError
      bestLane = i
      newLaneLimLeft = thisLaneLimLeft
      newLaneLimRight = thisLaneLimRight
    end
  end

  return bestLane, newLaneLimLeft, newLaneLimRight -- lateral positions are in the [0, 1] interval
end

local function getPathNodePosition(route, i)
  local path = route.path
  local wp1 = path[i-1] or route.plan[1].wp
  local wp2 = path[i]
  local wp3 = path[i+1]
  --dump('---- > in', i, path[i])
  if not wp1 and not wp3 then
    --dump('!!!!!!!!!!!!!!', path, objectId)
    return mapData.positions[wp2]:copy()
  elseif not wp1 then
    local wp2Pos = mapData:getEdgePositions(wp2, wp3)
    return wp2Pos:copy()
  elseif not wp3 then
    local _, wp2Pos = mapData:getEdgePositions(wp1, wp2)
    return wp2Pos:copy()
  else
    local e1P1, e1P2 = mapData:getEdgePositions(wp1, wp2)
    local e2P1, e2P2 = mapData:getEdgePositions(wp2, wp3)
    --dump(wp1, wp2, wp3, e1P2:squaredDistance(e2P1))
    if e1P2:squaredDistance(e2P1) < 0.005 then
      --dump('b0')
      return (e1P2 + e2P1) * 0.5
    else
      local e1Xnorm, e2Xnorm = closestLinePoints(e1P1, e1P2, e2P1, e2P2)
      local e2Xnorm2 = closestLinePoints(e2P1, e2P2, e1P1, e1P2)
      local _, e1R2 = mapData:getEdgeRadii(wp1, wp2)
      local e2R1 = mapData:getEdgeRadii(wp2, wp3)
      if (e1Xnorm == 0 and e2Xnorm2 == 0) then -- segments are parallel
        --dump('b1')
        return (e1P2 + e2P1) * 0.5
      elseif e1Xnorm >= 0 and e1Xnorm <= 1 + e1R2/e1P2:distance(e1P1) and e2Xnorm >= -e2R1/e2P1:distance(e2P2) and e2Xnorm <= 1 then
        --dump('b2', 'e1Xnorm = ', e1Xnorm, 'e2Xnorm = ', e2Xnorm)
        local p1 = linePointFromXnorm(e1P1, e1P2, e1Xnorm)
        local p2 = linePointFromXnorm(e2P1, e2P2, e2Xnorm)
        p1:setAdd(p2); p1:setScaled(0.5)
        return p1
      elseif e1Xnorm >= 0 and e1Xnorm <= 1 + e1R2/e1P2:distance(e1P1) then
        --dump('b3', 'e1Xnorm = ', e1Xnorm, 'e2Xnorm = ', e2Xnorm)
        local segLen = e1P2:distance(e1P1)
        return linePointFromXnorm(e1P1, e1P2, max(e1Xnorm, 1 - e1R2/segLen))
      elseif e2Xnorm >= -e2R1/e2P1:distance(e2P2) and e2Xnorm <= 1 then
        --dump('b4', 'e1Xnorm = ', e1Xnorm, 'e2Xnorm = ', e2Xnorm)
        local segLen = e2P1:distance(e2P2)
        return linePointFromXnorm(e2P1, e2P2, min(e2Xnorm, e2R1/segLen))
      else
        --dump('b5')
        local p1 = linePointFromXnorm(e1P1, e1P2, e1Xnorm)
        local p2 = linePointFromXnorm(e2P1, e2P2, e2Xnorm)
        p1:setAdd(p2); p1:setScaled(0.5)
        local avgPoint = (e1P2 + e2P1) * 0.5
        local avgPointToP1Line = p1 - avgPoint
        local newPoint = avgPoint + max(0, min(1, (e1R2 + e2R1) * 0.5 / avgPointToP1Line:length())) * avgPointToP1Line
        return newPoint
      end
    end
  end
end

local function getPathNodeRadius(path, i)
  if not path[i-1] and not path[i+1] then
    return mapData.radius[path[i]]
  elseif not path[i-1] then
    local wp1Rad = mapData:getEdgeRadii(path[i], path[i+1])
    return wp1Rad
  elseif not path[i+1] then
    local _, wp2Rad = mapData:getEdgeRadii(path[i-1], path[i])
    return wp2Rad
  else
    local wp1Pos, wp2Pos = mapData:getEdgePositions(path[i-1], path[i])
    local wp3Pos, wp4Pos = mapData:getEdgePositions(path[i], path[i+1])
    local e1Xnorm, e2Xnorm = closestLineSegmentPoints(wp1Pos, wp2Pos, wp3Pos, wp4Pos)
    local wp1Rad, wp2Rad = mapData:getEdgeRadii(path[i-1], path[i])
    local wp3Rad, wp4Rad = mapData:getEdgeRadii(path[i], path[i+1])
    local r1 = wp1Rad + (wp2Rad - wp1Rad) * e1Xnorm
    local r2 = wp3Rad + (wp4Rad - wp3Rad) * e2Xnorm
    return (r1 + r2) * 0.5
  end
end

local function buildNextRoute(route)
  local plan, path = route.plan, route.path
  local planCount = plan.planCount
  local nextPathIdx = (plan[planCount].pathidx or 0) + 1 -- if the first plan node is the ai.pos it does not have a pathidx value yet

  if race == true and noOfLaps and noOfLaps > 1 and not path[nextPathIdx] then -- in case the path loops
    local loopPathId
    local pathCount = #path
    local lastWayPoint = path[pathCount]
    for i = 1, pathCount do
      if lastWayPoint == path[i] then
        loopPathId = i
        break
      end
    end
    nextPathIdx = 1 + loopPathId -- nextPathIdx % #path
    noOfLaps = noOfLaps - 1
  end

  local newNodeName = path[nextPathIdx]
  if not newNodeName then return end
  local graph = mapData.graph
  if not graph[newNodeName] then return end

  -- gather information about new node
  local tmpPos = getPathNodePosition(route, nextPathIdx)
  local newNode = {
    name = newNodeName,
    posOrig = tmpPos,
    pos = tmpPos:copy(),
    radiusOrig = getPathNodeRadius(path, nextPathIdx),
    biNormal = -mapmgr.surfaceNormalBelow(mapData.positions[newNodeName], mapData.radius[newNodeName] * 0.5),
    prevNodeInPath = path[nextPathIdx-1],
    inEdgeDrivability = nil,
    inEdgeLanes = nil, -- lanes going into the node along the path
    inEdgeSpeedLimit = nil,
    nextNodeInPath = path[nextPathIdx+1],
    outEdgeLanes = nil, -- lanes coming out of the node along the path
    outEdgeSpeedLimit = nil,
  }

  if newNode.prevNodeInPath then
    newNode.prevNodePos = mapData.positions[newNode.prevNodeInPath]
    local link = graph[newNode.prevNodeInPath][newNode.name]
    if link then
      newNode.inEdgeLanes = getEdgeLaneConfig(newNode.prevNodeInPath, newNode.name)
      newNode.inEdgeSpeedLimit = link.speedLimit
      newNode.inEdgeDrivability = link.drivability
    end
  else -- if previous plan node is the ai.pos then
    newNode.prevNodePos = vec3(plan[1].posOrig)
    if planCount == 1 and plan[1].wp then -- check whether information is available
      --newNode.inEdgeLanes = plan[1].lanes -- TODO: use plan[1].wp to get lane configuration instead of saving the lane configuration in plan[1].lanes?
      newNode.prevNodeInPath = plan[1].wp
      newNode.inEdgeLanes = getEdgeLaneConfig(newNode.prevNodeInPath, newNode.name)
      newNode.inEdgeDrivability = graph[newNode.prevNodeInPath][newNode.name].drivability
    end
  end

  -- if there is no nextNodeInPath can we deduce it by elimination?
  -- we need to see if there is a unique node towards which we can lawfully drive
  if not newNode.nextNodeInPath then
    local nextPosibleNode = nil
    for k, v in pairs(graph[newNode.name]) do
      if k ~= newNode.prevNodeInPath then
        if numOfLanesInDirection(getEdgeLaneConfig(newNode.name, k), '+') > 0 then
          if nextPosibleNode then
            nextPosibleNode = nil
            break
          else
            nextPosibleNode = k
          end
        end
      end
    end
    newNode.nextNodeInPath = nextPosibleNode
  end

  if newNode.nextNodeInPath then
    local link = graph[newNode.name][newNode.nextNodeInPath]
    if link then
      newNode.outEdgeLanes = getEdgeLaneConfig(newNode.name, newNode.nextNodeInPath)
      newNode.outEdgeSpeedLimit = link.speedLimit
    end
  else
    if M.mode ~= 'traffic' then
      newNode.outEdgeLanes = newNode.inEdgeLanes
      newNode.outEdgeSpeedLimit = newNode.inEdgeSpeedLimit
    else
      return
    end
  end

  if newNode.outEdgeLanes and not newNode.inEdgeLanes then
    newNode.inEdgeLanes = newNode.outEdgeLanes
  end

  -- Adjust last plan node normal given information about node to be inserted:
  -- The normal of the node that is currently the last in the plan may need to be updated
  -- either because the path has been extended (where previously it was the last node in the path)
  -- or because the path has changed from this node forwards
  if planCount > 1 then
    if plan[planCount].wayPointAhead ~= path[nextPathIdx] then
      local norm1 = plan[planCount].biNormal:cross(plan[planCount].posOrig - plan[planCount-1].posOrig); norm1:normalize()
      local norm2 = plan[planCount].biNormal:cross(newNode.posOrig - plan[planCount].posOrig); norm2:normalize()
      plan[planCount].normal:setAdd2(norm1, norm2)
      local tmp = plan[planCount].normal:length()
      plan[planCount].normal:setScaled(1 / (tmp + 1e-30))
      plan[planCount].chordLength = min(2 / tmp, (1 - norm1:dot(norm2) * 0.5) * tmp) -- 2 / tmp == cos(x/2) : x is angle between norm1, norm2
    end
  else
    plan[planCount].normal:setSub2(newNode.posOrig, plan[planCount].posOrig)
    plan[planCount].normal:setCross(plan[planCount].biNormal, plan[planCount].normal)
    plan[planCount].normal:normalize()
  end

  -- Calculate normal of node to be inserted into the plan
  -- This normal is calculated from the normals of the two path edges incident on it
  newNode.inEdgeNormal = vec3()
  if newNode.prevNodeInPath then -- TODO: why not check for newNode.prevNodePos?
    local wp1Pos, wp2Pos = mapData:getEdgePositions(newNode.prevNodeInPath, newNode.name)
    newNode.inEdgeNormal:setSub2(wp2Pos, wp1Pos)
    newNode.inEdgeNormal:setCross(newNode.biNormal, newNode.inEdgeNormal)
    newNode.inEdgeNormal:normalize()
  end

  newNode.outEdgeNormal = vec3()
  if newNode.nextNodeInPath then
    local wp1Pos, wp2Pos = mapData:getEdgePositions(newNode.name, newNode.nextNodeInPath)
    newNode.outEdgeNormal:setSub2(wp2Pos, wp1Pos)
    newNode.outEdgeNormal:setCross(newNode.biNormal, newNode.outEdgeNormal)
    newNode.outEdgeNormal:normalize()
  end

  newNode.normal = newNode.inEdgeNormal + newNode.outEdgeNormal
  local tmp = newNode.normal:length()
  newNode.normal:setScaled(1 / (tmp + 1e-30))
  newNode.chordLength = min(2 / tmp, (1 - newNode.inEdgeNormal:dot(newNode.outEdgeNormal) * 0.5) * tmp) -- new node road width multiplier

  local newNodeLaneLimLeft = 0
  local newNodeLaneLimRight = 1
  local newNodeRangeLeft = 0
  local newNodeRangeRight = 1
  local newNodeRangeLaneCount = 1
  local rangeBestLane = 0
  local bestLane
  local newNodeLaneConfig
  local newNodeRangeLeftIdx -- index of left most lane in range
  local newNodeRangeRightIdx -- index of right most lane in range

  if driveInLaneFlag and newNode.inEdgeLanes then
    -- Consider lanes comming into newNode, scale/translate planNode lateral position and lane limits and add them to the in lane configuration as appropriate
    local inLaneConfig, planNodeLatPos, planNodelaneLimLeft, planNodelaneLimRight, planNodeRangeLeft, planNodeRangeRight, planNodeHalfWidth = processNodeIncommingLanes(newNode, plan[planCount]) -- lateral coordinates in [-r, r]

    -- Calculate lateral xnorm ranges of lanes in the direction of travel (in [0, 1])
    local outRangeLeft, outRangeRight, outRangeLaneCount = laneRange(newNode.outEdgeLanes)
    local inRangeLeft, inRangeRight, inRangeLaneCount = laneRange(inLaneConfig)

    -- Decide on the lane configuration of newNode: --> Retain the narrowest range
    local newNodeLaneConfigOrig
    if (inRangeRight - inRangeLeft) * outRangeLaneCount < (outRangeRight - outRangeLeft) * inRangeLaneCount then
      newNodeLaneConfig, newNodeRangeLeft, newNodeRangeRight, newNodeRangeLaneCount = inLaneConfig, inRangeLeft, inRangeRight, inRangeLaneCount
      newNodeLaneConfigOrig = newNode.inEdgeLanes
    else
      newNodeLaneConfig, newNodeRangeLeft, newNodeRangeRight, newNodeRangeLaneCount = newNode.outEdgeLanes, outRangeLeft, outRangeRight, outRangeLaneCount
      newNodeLaneConfigOrig = newNode.outEdgeLanes
    end

    local planNodeLatPosNrmd = linearScale(planNodeLatPos, planNodeRangeLeft, planNodeRangeRight, newNodeRangeLeft, newNodeRangeRight) -- TODO: lateralXnorm might be outside [inRangeLeft, inRangeRight]
    local planNodeLaneLimLeftNrmd = linearScale(planNodelaneLimLeft, planNodeRangeLeft, planNodeRangeRight, newNodeRangeLeft, newNodeRangeRight)
    local planNodeLaneLimRightNrmd = linearScale(planNodelaneLimRight, planNodeRangeLeft, planNodeRangeRight, newNodeRangeLeft, newNodeRangeRight)

    -- Calculate the most appropriate lane out of newNodeLaneConfig. This will be where to position the new node lateraly along the normal of newNode.
    bestLane, newNodeLaneLimLeft, newNodeLaneLimRight = getBestLane(newNodeLaneConfig, planNodeLatPosNrmd, planNodeLaneLimLeftNrmd, planNodeLaneLimRightNrmd, plan, newNode) -- lateral coordinates in [0, 1]

    -- Calculate the lane range (i.e. lateral limits of left most and right most lanes traveling in the same direction as bestLane, starting from bestLane)
    local rangeLeft, rangeRight = newNodeRangeLeft, newNodeRangeRight
    newNodeRangeLeft, newNodeRangeRight, newNodeRangeLeftIdx, newNodeRangeRightIdx = getLaneRangeFromLane(newNodeLaneConfig, bestLane) -- lateral coordinates in [0, 1]

    local rangeLeftOrig, rangeRightOrig = laneRange(newNodeLaneConfigOrig) -- Will this work when the lane config is not monotonic?
    newNodeRangeLeft = linearScale(newNodeRangeLeft, rangeLeft, rangeRight, rangeLeftOrig, rangeRightOrig)
    newNodeRangeRight = linearScale(newNodeRangeRight, rangeLeft, rangeRight, rangeLeftOrig, rangeRightOrig)
    --newNodeLaneLimLeft = linearScale(newNodeRangeLeft + (bestLane - newNodeRangeLeftIdx) * laneWidth, 0, 1, -roadHalfWidth, roadHalfWidth)
    --newNodeLaneLimRight = linearScale(newNodeRangeLeft + (bestLane - newNodeRangeLeftIdx) + 1) * laneWidth, 0, 1, -roadHalfWidth, roadHalfWidth)
    newNodeLaneLimLeft = linearScale(newNodeLaneLimLeft, rangeLeft, rangeRight, rangeLeftOrig, rangeRightOrig)
    newNodeLaneLimRight = linearScale(newNodeLaneLimRight, rangeLeft, rangeRight, rangeLeftOrig, rangeRightOrig)
  end

  newNode.pos:setAdd(((newNodeLaneLimLeft + newNodeLaneLimRight) - 1) * newNode.radiusOrig * newNode.chordLength * newNode.normal)

  newNode.inEdgeNormal:setSub2(newNode.pos, plan[planCount].pos)
  newNode.inEdgeNormal:setCross(newNode.biNormal, newNode.inEdgeNormal)
  newNode.inEdgeNormal:normalize()
  newNode.normal = newNode.inEdgeNormal + newNode.outEdgeNormal

  local tmp = newNode.normal:length()
  newNode.normal:setScaled(1 / (tmp + 1e-30))
  newNode.chordLength = min(2 / tmp, (1 - newNode.inEdgeNormal:dot(newNode.outEdgeNormal) * 0.5) * tmp)
  local newNodeHalfWidth = newNode.radiusOrig * newNode.chordLength

  local newNodeLatPos
  if newNodeLaneConfig and #newNodeLaneConfig > 1 and newNode.nextNodeInPath and newNode.prevNodeInPath then -- TODO: error hits if the nextNode/prevNode conditions are not here
    local laneWidth = 2 * newNode.radiusOrig * (newNodeRangeRight - newNodeRangeLeft) / newNodeRangeLaneCount -- lane width not including chordLength
    local turnDir = (mapData.positions[newNode.nextNodeInPath] - newNode.posOrig) + (mapData.positions[newNode.prevNodeInPath] - newNode.posOrig)
    -- keep inside lanes narrower
    if turnDir:dot(newNode.normal) < 0 then
      newNodeLaneLimLeft = linearScale(newNodeRangeLeft, 0, 1, -newNodeHalfWidth, newNodeHalfWidth) + (bestLane - newNodeRangeLeftIdx) * laneWidth
      --[[ tighter outside left turns
      newNodeLaneLimLeft = -newNodeHalfWidth + (bestLane - 1) * laneWidth
      newNodeRangeLeft = min(newNodeRangeLeft, linearScale(-newNodeHalfWidth + (newNodeRangeLeftIdx - 1) * laneWidth, -newNodeHalfWidth, newNodeHalfWidth, 0, 1))
      --]]
      newNodeLaneLimRight = newNodeLaneLimLeft + laneWidth
      newNodeLatPos = (newNodeLaneLimLeft + newNodeLaneLimRight) * 0.5
      if bestLane == #newNodeLaneConfig then newNodeLaneLimRight = newNodeHalfWidth end -- give remaining space on the right to the right most lane
    else
      newNodeLaneLimRight = linearScale(newNodeRangeRight, 0, 1, -newNodeHalfWidth, newNodeHalfWidth) - (newNodeRangeRightIdx - bestLane) * laneWidth
      newNodeLaneLimLeft = newNodeLaneLimRight - laneWidth
      newNodeLatPos = (newNodeLaneLimLeft + newNodeLaneLimRight) * 0.5
      if bestLane == 1 then newNodeLaneLimLeft = -newNodeHalfWidth end -- give remaining space on the left to left most lane
    end
  else
    -- Transform newNode lateral position and lane limits from [0, 1] to [-r, r] using the recalculated newNodeHalfWidth
    newNodeLaneLimLeft = linearScale(newNodeLaneLimLeft, 0, 1, -newNodeHalfWidth, newNodeHalfWidth)
    newNodeLaneLimRight = linearScale(newNodeLaneLimRight, 0, 1, -newNodeHalfWidth, newNodeHalfWidth)
    newNodeLatPos = (newNodeLaneLimLeft + newNodeLaneLimRight) * 0.5
  end

  newNode.pos = newNode.posOrig + newNodeLatPos * newNode.normal

  local lastPlanPos = plan[planCount] and plan[planCount].pos or ai.pos
  local vec = lastPlanPos - newNode.pos; vec.z = 0

  return {
    posOrig = newNode.posOrig,
    pos = newNode.pos,
    vec = vec,
    dirVec = vec:normalized(),
    turnDir = vec3(0,0,0),
    biNormal = newNode.biNormal,
    normal = newNode.normal,
    radiusOrig = newNode.radiusOrig,
    manSpeed = speedProfile and speedProfile[newNode.name],
    pathidx = nextPathIdx,
    chordLength = newNode.chordLength,
    widthMarginOffset = 0,
    wayPointAhead = newNode.nextNodeInPath,
    laneLimLeft = newNodeLaneLimLeft, -- lateral coordinate of current lane left limit [-hW, hW]
    laneLimRight = newNodeLaneLimRight, -- lateral coordinate of current lane right limit [-hW, hW]
    curvature = 0,
    lateralXnorm = newNodeLatPos, -- lateral coordinate of pos [-hW, hW]
    legalSpeed = nil,
    speed = nil,
    inLaneConfig = newNode.inEdgeLanes, -- lane configuration of incoming edge to node
    rangeLeft = newNodeRangeLeft, -- lateral coordinate [0, 1] of the left hand side limit of the left most lane in the direction of travel
    rangeRight = newNodeRangeRight, -- lateral coordinate [0, 1] of the right hand side limit of the right most lane in the direction of travel
    rangeLaneCount = newNodeRangeLaneCount, -- number of contiguous lanes in the direction of travel counting from the current lane
    rangeBestLane = bestLane and newNodeRangeLeftIdx and (bestLane - newNodeRangeLeftIdx) or rangeBestLane, -- 0 indexed
    trafficSqVel = math.huge
  }
end

local function mergePathPrefix(source, dest, srcStart)
  srcStart = srcStart or 1
  local sourceCount = #source
  local dict = table.new(0, sourceCount-(srcStart-1))
  for i = srcStart, sourceCount do
    dict[source[i]] = i
  end

  local destCount = #dest
  for i = destCount, 1, -1 do
    local srci = dict[dest[i]]
    if srci ~= nil then
      local res = table.new(destCount, 0)
      local resi = 1
      for i1 = srcStart, srci - 1 do
        res[resi] = source[i1]
        resi = resi + 1
      end
      for i1 = i, destCount do
        res[resi] = dest[i1]
        resi = resi + 1
      end

      return res, srci
    end
  end

  return dest, 0
end

local function uniformPlanErrorDistribution(plan)
  if twt.state == 0 then
    local p1, p2 = plan[1].pos, plan[2].pos
    local dispVec = ai.pos - linePointFromXnorm(p1, p2, ai.pos:xnormOnLine(p1, p2)); dispVec:setScaled(min(1, 4 * dt))
    local dispVecDir = dispVec:normalized()

    local tmpVec = p2 - p1; tmpVec:setCross(tmpVec, ai.upVec); tmpVec:normalize()
    --aiDeviation = dispVec:dot(tmpVec)

    local j = 0
    local dTotal = 0
    for i = 1, plan.planCount-1 do
      tmpVec:setSub2(plan[i+1].pos, plan[i].pos)
      if math.abs(dispVecDir:dot(tmpVec)) > 0.5 * plan[i].length then
        break
      end
      j = i
      dTotal = dTotal + plan[i].length
    end

    local sumLen = 0
    for i = j, 1, -1 do
      local n = plan[i]
      sumLen = sumLen + plan[i].length

      local lateralXnorm = n.lateralXnorm or 0
      local newLateralXnorm = clamp(lateralXnorm + ((dispVec):dot(n.normal) * sumLen / dTotal), n.laneLimLeft or -math.huge, n.laneLimRight or math.huge)
      tmpVec:setScaled2(n.normal, newLateralXnorm - lateralXnorm)
      n.pos:setAdd(tmpVec)
      n.lateralXnorm = newLateralXnorm

      plan[i+1].vec:setSub2(plan[i].pos, plan[i+1].pos); plan[i+1].vec.z = 0
      plan[i+1].dirVec:setScaled2(plan[i+1].vec, 1 / plan[i+1].vec:lengthGuarded())
    end

    updatePlanLen(plan, 1, j)
  end
end

local function createNewRoute(path)
  return {
    path = path,
    plan = table.new(15, 10),
    laneChanges = {}, -- array: in the array each lane change is a dict with an idx key (path index at which lane change occurs) and a side key (direction of lane change)
    lastLaneChangeIdx = 1, -- path node up to which we have checked for a posible lane change
    pathLength = {0} -- distance from beggining of path to node at index i
  }
end

local function isVehicleStopped(v)
  if v.isParked then
    return true
  elseif v.states.ignitionLevel == 0 or v.states.ignitionLevel == 1 then
    return true
  elseif v.states.hazard_enabled == 1 and v.vel:squaredLength() < 9 then
    return true
  end
  return false
end

local function inCurvature(v1, v2)
  --[[
    Given three points A, B, C (with AB being the vector from A to B), the curvature (= 1 / radius)
    of the circle going through them is:

    curvature = 2 * (AB x BC) / ( |AB| * |BC| * |CA| ) =>
              = 2 * |AB| * |BC| * Sin(th) / ( |AB| * |BC| * |CA| ) =>
              = 2 * (+/-) * sqrt ( 1 - Cos^2(th) ) / |CA| =>
              = 2 * (+/-) sqrt [ ( 1 - Cos^2(th) ) / |CA|^2 ) ] -- This is an sqrt optimization step

    In the calculation below the (+/-) which indicates the turning direction (direction of AB x BC) has been dropped
  --]]

  -- v1 and v2 vector components
  local v1x, v1y, v1z, v2x, v2y, v2z = v1.x, v1.y, v1.z, v2.x, v2.y, v2.z

  local v1Sqlen, v2Sqlen = v1x * v1x + v1y * v1y + v1z * v1z, v2x * v2x + v2y * v2y + v2z * v2z
  local dot12 = v1x * v2x + v1y * v2y + v1z * v2z
  local cosSq = min(1, dot12 * dot12 / max(1e-30, v1Sqlen * v2Sqlen))

  if dot12 < 0 then -- angle between the two segments is > 180 deg
    local minDsq = min(v1Sqlen, v2Sqlen)
    local maxDsq = minDsq / max(1e-30, cosSq)
    if max(v1Sqlen, v2Sqlen) > (minDsq + maxDsq) * 0.5 then
      if v1Sqlen > v2Sqlen then
        -- swap v1 and v2
        v1x, v1y, v1z, v2x, v2y, v2z = v2x, v2y, v2z, v1x, v1y, v1z
        v1Sqlen, v2Sqlen = v2Sqlen, v1Sqlen
      end
      local s = sqrt(0.5 * (minDsq + maxDsq) / max(1e-30, v2Sqlen))
      v2x, v2y, v2z = s * v2x, s * v2y, s * v2z
    end
  end

  v2x, v2y, v2z = -v2x, -v2y, -v2z
  return 2 * sqrt((1 - cosSq) / max(1e-30, square(v1x - v2x) + square(v1y - v2y) + square(v1z - v2z)))
end

-- ********* FUNCTIONS FOR SPEED PROFILE GENERATION ********* --

-- Computes the acceleration budget based on the vehicle speed (x) to simulate more realistic real world driving behaviour
-- https://arxiv.org/pdf/1907.01747
local function speedBasedAccelBudget(x, a)
  x = max(0, x)
  a = a or 0

  local fx
  if 0 <= x and x < 5 then
    fx = 0.3 * x + 4
  elseif 5 <= x and x < 10 then
    fx = 5.5
  elseif 10 <= x and x < 15 then
    fx = -0.1 * x + 6.5
  elseif 15 <= x and x < 20 then
    fx = -0.15 * x + 7.25
  elseif 20 <= x and x < 25 then
    fx = -0.15 * x + 7.25
  elseif 25 <= x and x < 30 then
    fx = -0.1 * x + 6
  else
    fx = 3
  end

  return max(0, min(fx + a, staticFrictionCoef * g))
end

local speedProfileMode -- ('Back' for new backward method, 'ForwBack' for forward+Backward method)
local function setSpeedProfileMode(mode)
  if mode == 'Back' then
    speedProfileMode = 'Back'
  elseif mode == 'ForwBack' then
    speedProfileMode = 'ForwBack'
  else
    speedProfileMode = nil
  end
end

-- Compute maximum available longitudinal acceleration
local function acc_eval_1(speedSq, acc_max, curvature)
  local ax_max_tyre = acc_max -- has to be exctracted from ggv
  local ay_max_tyre = acc_max -- has to be exctracted from ggv
  local ay_used = speedSq * curvature
  return ax_max_tyre * max(0, 1 - ay_used / ay_max_tyre)
end

local function acc_eval_2(speedSq, acc_max, curvature)
  local ax_max_tyre = acc_max -- has to be exctracted from ggv
  local ay_max_tyre = acc_max -- has to be exctracted from ggv
  local ay_used = speedSq * curvature
  if ay_used < ay_max_tyre then
    return ax_max_tyre * sqrt(1 - square(ay_used/ay_max_tyre))
  else
    return 0
  end
end

local acc_eval = acc_eval_2 -- Default adherence constraint
-- set the index for adherence constraint, useful only for Back or ForwBack mode
local function setTractionModel(model_index)
  if model_index == 1 then
    acc_eval = acc_eval_1
  else
    acc_eval = acc_eval_2
  end
end

-- Compute forward pass (speed0 = starting velocity, model_index = index for adherence constraint)
local function solver_f_acc_profile(plan, speed0)
  plan[1].speed = speed0 or plan[1].speed
  local vx_possible_next

  for i = 1, plan.planCount-1 do
    local n1, n2 = plan[i], plan[i+1]

    if plan.stopSeg and plan.stopSeg <= i+1 then
      vx_possible_next = 0
    else
      local n1SpeedSq = n1.speed * n1.speed
      if min(n2.speed * n2.speed, n2.trafficSqVel) < n1SpeedSq then -- max velocity at i-1 is less than velocity at i (not a deceleration phase)
        vx_possible_next = min(n2.speed, sqrt(n2.trafficSqVel))
      else
        local ax_final = acc_eval(n1.speed * n1.speed, n1.acc_max, n1.curvature)
        vx_possible_next = n1.speed * n1.speed + 2 * ax_final * n1.length -- speed squared
        vx_possible_next = min(n2.speed, sqrt(min(n2.trafficSqVel, vx_possible_next)))
      end
    end

    n2.speed = n2.manSpeed or
               (M.speedMode == 'limit' and M.routeSpeed and min(M.routeSpeed, vx_possible_next)) or
               (M.speedMode == 'set' and M.routeSpeed) or
               vx_possible_next
  end
end

-- Compute backward pass (speed_end = final velocity, model_index = index for adherence constraint)
local function solver_b_acc_profile(plan)
  for i = plan.planCount, 2, -1 do
    local n1, n2 = plan[i-1], plan[i]
    local vx_possible_next
    if plan.stopSeg and plan.stopSeg <= i-1 then
      vx_possible_next = 0
    else
      local n2SpeedSq = n2.speed * n2.speed
      if min(n1.speed * n1.speed, n1.trafficSqVel) < n2SpeedSq then -- max velocity at i-1 is less than velocity at i (not a deceleration phase)
        vx_possible_next = min(n1.speed, sqrt(n1.trafficSqVel))
      else
        -- available longitudinal acceleration at node i
        local ax_possible_current = acc_eval(n2SpeedSq, n2.acc_max, n2.curvature)
        -- possible velocity at node i-1 given available longitudinal acceleration at node i
        vx_possible_next = n2SpeedSq + 2 * ax_possible_current * n1.length

        -- available longitudinal acceleration at node i-1 given velocity estimate at node i-1
        local ax_possible_next = acc_eval(vx_possible_next, n1.acc_max, n1.curvature)
        -- possible velocity at i-1 given available longitudinal acceleration at node i-1
        local vx_tmp = n2SpeedSq + 2 * ax_possible_next * n1.length

        if vx_possible_next > vx_tmp then
          -- available longitudinal acceleration at node i-1 given new velocity estimate at node i-1
          ax_possible_next = acc_eval(vx_tmp, n1.acc_max, n1.curvature)
          -- improve velocity estimate at i-1 given available longitudinal acceleration at node i-1
          vx_tmp = n2SpeedSq + 2 * ax_possible_next * n1.length
          -- keep the velocity that satisfies longitudinal acceleration constraints at node i-1 and node i
          vx_possible_next = min(vx_possible_next, vx_tmp)
        end

        vx_possible_next = min(n1.speed, sqrt(min(n1.trafficSqVel, vx_possible_next))) -- respect traffic speed
      end
    end

    n1.speed = n1.manSpeed or
               (M.speedMode == 'limit' and M.routeSpeed and min(M.routeSpeed, vx_possible_next)) or
               (M.speedMode == 'set' and M.routeSpeed) or
               vx_possible_next

    if M.speedMode == 'legal' then
      n2.legalSpeed = n2.legalSpeed or n2.speed
      local vx_possible_next_legal = sqrt(n2.legalSpeed * n2.legalSpeed + 2 * ((n1.acc_max + n2.acc_max) * 0.5) * n1.length)
      n1.legalSpeed = min(n1.speed, min(vx_possible_next_legal, (n1.roadSpeedLimit or math.huge)))
    end

    n1.trafficSqVel = math.huge
  end
end

local function setTrafficFilter(v)
  if v == true then
    filtered = true
  else
    filtered = false
  end
end
M.setTrafficFilter = setTrafficFilter

local function setVdraw(v)
  if v == true then
    vdraw = true
  else
    vdraw = false
  end
end
M.setVdraw = setVdraw

local function trafficFilter(index, route, radiusFilter, v, intersection, draw)
  local path = route.path
  --obj.debugDrawProxy:drawSphere(1, getPathNodePosition(route, index.start), color(255,255,255,160))
  if ai.pos:squaredDistance(v.posMiddle) < radiusFilter*radiusFilter then -- check if v is in radiusFilter
    for i = index.start, index.final, 1 do
      i = i-1
      local n1 = {}
      if i < index.start then
        n1 = {
          name = nil,
          posOrig = route.plan[1].posOrig, --mapData.positions[path[i]],
          radiusOrig = route.plan[1].radiusOrig, --mapData.radius[path[i]],
          biNormal = route.plan[1].biNormal,
        }
      else
        n1 = {
          name = path[i],
          posOrig = getPathNodePosition(route, i), --mapData.positions[path[i]],
          radiusOrig = getPathNodeRadius(path, i), --mapData.radius[path[i]],
          biNormal = -mapmgr.surfaceNormalBelow(mapData.positions[path[i]], mapData.radius[path[i]] * 0.5),
        }
      end
      local n2 = {
        name = path[i+1],
        posOrig = getPathNodePosition(route, i+1),
        radiusOrig = getPathNodeRadius(path, i+1), --mapData.radius[path[i+1]],
        biNormal = -mapmgr.surfaceNormalBelow(mapData.positions[path[i+1]], mapData.radius[path[i+1]] * 0.5),
      }
      local vec = vec3(); vec:setSub2(n1.posOrig, n2.posOrig); vec.z = 0; vec:normalized()
      n1.dirVec = vec:normalized()
      n2.dirVec = vec:normalized()
      n1.normal = vec3(); n1.normal:setCross(n1.dirVec, n1.biNormal)
      n2.normal = vec3(); n2.normal:setCross(n2.dirVec, n2.biNormal)
      --obj.debugDrawProxy:drawSphere(1, n1.posOrig, color(255,255,255,160))
      --obj.debugDrawProxy:drawSphere(1, n2.posOrig, color(255,255,255,160))

      local roadHalfWidth1, roadHalfWidth2 =  n1.radiusOrig * 1.05, n2.radiusOrig * 1.05
      local pos1Ext, pos2Ext = n1.posOrig - roadHalfWidth1 * n1.normal, n2.posOrig - roadHalfWidth2 * n2.normal
      local pos1Int, pos2Int = n1.posOrig + roadHalfWidth1 * n1.normal, n2.posOrig + roadHalfWidth2 * n2.normal
      local xnormFext = v.posFront:xnormOnLine(pos1Ext, pos2Ext)
      local xnormFint = v.posFront:xnormOnLine(pos1Int, pos2Int)
      local xnormRext = v.posRear:xnormOnLine(pos1Ext, pos2Ext)
      local xnormRint = v.posRear:xnormOnLine(pos1Int, pos2Int)
      local ai2PlVec = v.posFront - ai.pos
      --obj.debugDrawProxy:drawSphere(2, pos1Ext, color(0,0,0,160))
      --obj.debugDrawProxy:drawSphere(2, pos2Ext, color(0,0,0,160))
      -- check if v-vehicle is in the current pFp-segment projection
      if (xnormFext > 0 and xnormFext < 1) or (xnormFint > 0 and xnormFint < 1) or (xnormRext > 0 and xnormRext < 1) or (xnormRint > 0 and xnormRint < 1) then
        if ai2PlVec:dot(v.dirVec) < 0 then -- check if v-vehicle is coming in opposite direction
          -- add it if it is not parallel to current pFp-segment
          if v.dirVec:dot(n1.dirVec) < 0.95 then -- do we need an abs here?
            if draw then obj.debugDrawProxy:drawSphere(2, v.posFront, color(255,0,0,160)) end
            return true
          else
            if intersection then
              -- add it if it is parallel to current pFp-segment but there is an intersection
              for j = i+1, index.start, -1 do
                if tableSize(mapData.graph[route.path[j]]) > 2 then
                  if draw then obj.debugDrawProxy:drawSphere(2, v.posFront, color(255,100,0,160)) end
                  return true
                end
              end
            end
          end
        else -- if ai2PlVec:dot(v.dirVec) > 0 then -> add v-vehicle if it is in front of us
          if draw then obj.debugDrawProxy:drawSphere(2, v.posFront, color(0,255,0,160)) end
          return true
        end
        return false
      elseif xnormFext < 0 or xnormFint < 0 then -- add v-vehicles if it is behind us or in an dead corner
        if v.posFront:squaredDistance(n1.posOrig) < 100*100 then
          if draw then obj.debugDrawProxy:drawSphere(2, v.posFront, color(0,0,255,160)) end
          return true
        end
      end
    end
  end
  return false
end


--local function pathFplan(plan, path, distAhead)
--  local pFp = {}
--  pFp[1] = plan[1]
--  local k = 2
--  for i = 1, plan.planCount-1 do
--    local val1 = plan[i].pathidx
--    local val2 = plan[i+1].pathidx
--    if val2 - val1 > 0 then
--      pFp[k] = plan[i]
--      pFp.planCount = k
--      k = k + 1
--    end
--  end
--  pFp[k] = plan[plan.planCount]
--  local dist = plan.planLen
--  pFp.planCount = k
--  while dist < distAhead do
--    k = k + 1
--    local n = buildNextRoute(pFp, path)
--    if n then
--      pFp[k] = n
--      dist = dist + pFp[k].posOrig:distance(pFp[k-1].posOrig)
--      pFp.planCount = k
--    else
--      break
--    end
--  end
--  return pFp
--end


local function planAhead(route, baseRoute)
  if not route then return end

  if not route.path then
    route = createNewRoute(route)
  end

  local plan = route.plan

  if baseRoute and not plan[1] then
    -- merge from base plan
    local bsrPlan = baseRoute.plan
    if bsrPlan[2] then
      local commonPathEnd
      route.path, commonPathEnd = mergePathPrefix(baseRoute.path, route.path, bsrPlan[2].pathidx)
      route.lastLaneChangeIdx = 2
      table.clear(route.laneChanges)
      route.pathLength = {0}
      if commonPathEnd >= 1 then
        local refpathidx = bsrPlan[2].pathidx - 1
        local planLen, planCount = 0, 0
        for i = 1, #bsrPlan do
          local n = bsrPlan[i]
          if n.pathidx > commonPathEnd then break end
          planLen = planLen + (n.length or 0)
          planCount = i

          plan[i] = {
            posOrig = vec3(n.posOrig),
            pos = vec3(n.pos),
            vec = vec3(n.vec),
            dirVec = vec3(n.dirVec),
            turnDir = vec3(n.turnDir),
            biNormal = vec3(n.biNormal),
            normal = vec3(n.normal),
            radiusOrig = n.radiusOrig,
            pathidx = max(1, n.pathidx-refpathidx),
            roadSpeedLimit = n.roadSpeedLimit,
            chordLength = n.chordLength,
            widthMarginOffset = n.widthMarginOffset,
            wayPointAhead = n.wayPointAhead,
            length = n.length,
            curvature = n.curvature,
            lateralXnorm = n.lateralXnorm,
            laneLimLeft = n.laneLimLeft,
            laneLimRight = n.laneLimRight,
            legalSpeed = nil,
            speed = nil,
            rangeLeft = n.rangeLeft,
            rangeRight = n.rangeRight,
            rangeLaneCount = n.rangeLaneCount,
            rangeBestLane = n.rangeBestLane,
            trafficSqVel = math.huge
          }
        end
        plan.planLen = planLen
        plan.planCount = planCount
        if plan[bsrPlan.targetSeg+1] then
          plan.targetSeg = bsrPlan.targetSeg
          plan.targetPos = vec3(bsrPlan.targetPos)
          plan.aiSeg = bsrPlan.aiSeg
          plan.aiXnormOnSeg = bsrPlan.aiXnormOnSeg
        end
      end
    end
  end

  if not plan[1] then
    local posOrig = vec3(ai.pos)
    local radiusOrig = 2
    local normal = vec3(0, 0, 0)
    local latXnorm = 0
    local rangeLeft, rangeRight, rangeBestLane = 0, 1, 0
    local laneLimLeft, laneLimRight = -ai.width * 0.5, ai.width * 0.5
    local biNormal = mapmgr.surfaceNormalBelow(ai.pos, ai.width * 0.5); biNormal:setScaled(-1)
    local wp, lanes, roadSpeedLimit
    if ai.currentSegment[1] and ai.currentSegment[2] then
      local wp1 = route.path[1]
      local wp2
      if wp1 == ai.currentSegment[1] then
        wp2 = ai.currentSegment[2]
      elseif wp1 == ai.currentSegment[2] then
        wp2 = ai.currentSegment[1]
      end
      if wp2 and route.path[2] ~= wp2 then
        -- local pos1 = mapData.positions[wp1]
        -- local pos2 = mapData.positions[wp2]
        local pos1, pos2 = mapData:getEdgePositions(wp1, wp2)
        local xnorm = ai.pos:xnormOnLine(pos2, pos1)
        if xnorm >= 0 and xnorm <= 1 then
          local rad1, rad2 = mapData:getEdgeRadii(wp1, wp2)
          local rad = lerp(rad2, rad1, xnorm)
          posOrig = linePointFromXnorm(pos2, pos1, xnorm)
          normal:setCross(biNormal, pos1 - pos2); normal:normalize()
          radiusOrig = rad
          wp = wp2
          roadSpeedLimit = mapData.graph[wp1][wp2].speedLimit
          latXnorm = ai.pos:xnormOnLine(posOrig, posOrig + normal)
          laneLimLeft = latXnorm - ai.width * 0.5 -- TODO: rethink the limits here
          laneLimRight = latXnorm + ai.width * 0.5
          if driveInLaneFlag then
            lanes = getEdgeLaneConfig(wp2, wp1)
            rangeLeft, rangeRight = laneRange(lanes)

            local normalizedLatXnorm = (latXnorm / radiusOrig + 1) * 0.5
            local normalizedLaneLimLeft = (laneLimLeft / radiusOrig + 1) * 0.5
            local normalizedLaneLimRight = (laneLimRight / radiusOrig + 1) * 0.5

            local bestLane
            bestLane, normalizedLaneLimLeft, normalizedLaneLimRight = getBestLane(lanes, normalizedLatXnorm, normalizedLaneLimLeft, normalizedLaneLimRight)

            local _, _, rangeLeftIdx, rangeRightIdx = getLaneRangeFromLane(lanes, bestLane)
            rangeBestLane = bestLane - rangeLeftIdx -- bestLane - rangeRightIdx

            laneLimLeft = (normalizedLaneLimLeft * 2 - 1) * radiusOrig
            laneLimRight = (normalizedLaneLimRight * 2 - 1) * radiusOrig
            latXnorm = (laneLimLeft + laneLimRight) * 0.5
          end
        end
      end
    end

    local rangeLaneCount = lanes and numOfLanesInDirection(lanes, "+") or 1 -- numOfLanesFromRadius(radiusOrig)
    local vec = vec3(-8 * ai.dirVec.x, -8 * ai.dirVec.y, 0)

    plan[1] = {
      posOrig = posOrig,
      pos = vec3(ai.pos),
      vec = vec,
      dirVec = vec:normalized(),
      turnDir = vec3(0,0,0),
      biNormal = biNormal,
      normal = normal,
      radiusOrig = radiusOrig,
      widthMarginOffset = 0,
      length = 0,
      curvature = 0,
      chordLength = 1,
      lateralXnorm = latXnorm,
      laneLimLeft = laneLimLeft,
      laneLimRight = laneLimRight,
      rangeLeft = rangeLeft,
      rangeRight = rangeRight,
      rangeLaneCount = rangeLaneCount,
      rangeBestLane = rangeBestLane,
      pathidx = nil,
      roadSpeedLimit = roadSpeedLimit,
      legalSpeed = nil,
      speed = nil,
      wp = wp,
      trafficSqVel = math.huge
    }

    plan.planCount = 1
    plan.planLen = 0
    plan.aiXnormOnSeg = 0
  end

  local minPlanLen
  if M.mode == 'traffic' then
    minPlanLen = getMinPlanLen(20, ai.speed, 0.2 * staticFrictionCoef) -- 0.25 * min(aggression, staticFrictionCoef)
  else
    minPlanLen = getMinPlanLen(40)
  end

  while not plan[MIN_PLAN_COUNT] or (plan.planLen - (plan.aiXnormOnSeg or 0) * plan[1].length) < minPlanLen do -- TODO: (plan.planLen < minPlanLen and (not plan.stopSeg or (plan.stopSeg+1) == plan.planCount))
    local n = buildNextRoute(route)
    if not n then break end
    plan.planCount = plan.planCount + 1
    plan[plan.planCount] = n
    plan[plan.planCount-1].length = n.pos:distance(plan[plan.planCount-1].pos)
    plan.planLen = plan.planLen + plan[plan.planCount-1].length
  end

  if not plan[2] then return end
  if not plan[1].pathidx then
    plan[1].pathidx = plan[2].pathidx
    plan[1].roadSpeedLimit = plan[2].roadSpeedLimit
  end

  -- Calculate the length of the path at each path node one segment per call of planAhead
  if not route.pathLength[#route.path] then
    local n = #route.pathLength
    table.insert(
      route.pathLength,
      mapData.positions[route.path[n+1]]:distance(mapData.positions[route.path[max(1, n)]]) + route.pathLength[n]
    )
  end

  -- check path node at lastLaneChangeIdx for a possible lane change
  if route.lastLaneChangeIdx < #route.path then
    local wp1, wp2
    if route.lastLaneChangeIdx == 1 then
      wp2 = route.path[route.lastLaneChangeIdx]
      if plan[1].wp and (plan[1].wp ~= wp2) then
        wp1 = plan[1].wp
      else
        --wp1 not found: safeguard
        route.lastLaneChangeIdx = 2
        wp1, wp2 = route.path[route.lastLaneChangeIdx-1], route.path[route.lastLaneChangeIdx]
      end
    else
      wp1, wp2 = route.path[route.lastLaneChangeIdx-1], route.path[route.lastLaneChangeIdx]
    end
    if route.lastLaneChangeIdx < #route.path then
      if numOfLanesInDirection(getEdgeLaneConfig(wp1, wp2), '+') > 1 then
        local minNode = roadNaturalContinuation(wp1, wp2)
        local wp3 = route.path[route.lastLaneChangeIdx+1]
        if minNode and minNode ~= wp3 then -- road natural continuation at wp2 is not in our path
          local minNodePos, wp2Pos_2 = mapData:getEdgePositions(minNode, wp2)
          local minNodeEdgeVec = minNodePos - wp2Pos_2
          local wp1Pos, wp2Pos_1 = mapData:getEdgePositions(wp1, wp2)
          local wp1TOwp2EdgeVec = wp2Pos_1 - wp1Pos
          if minNodeEdgeVec:dot(wp1TOwp2EdgeVec) > 0 then -- road natural continuation is up to 90 deg
            local edgeNormal = gravityDir:cross(minNodePos - wp2Pos_2):normalized()
            local wp3Pos = mapData:getEdgePositions(wp3, wp2)
            local side = sign2(edgeNormal:dot(wp3Pos) - edgeNormal:dot(minNodePos))
            table.insert(route.laneChanges, {pathIdx = route.lastLaneChangeIdx, side = side, alternate = minNode})
          end
        end
      end
      route.lastLaneChangeIdx = route.lastLaneChangeIdx + 1
    end
  end

  local distOnPlan = 0
  for i = 1, plan.planCount-1 do
    local segLenSq = plan[i].posOrig:squaredDistance(plan[i+1].posOrig)
    local xSq = square(distOnPlan)
    if min(segLenSq, square(plan[i].length)) > square(min(220, (25e-8 * xSq + 1e-5) * xSq + 6)) and distOnPlan < 550 then
      local n1, n2 = plan[i], plan[i+1]

      local posOrig = n1.posOrig + n2.posOrig; posOrig:setScaled(0.5)
      local radiusOrig = (n1.radiusOrig + n2.radiusOrig) * 0.5 -- TODO: this might be inacurate since posOrig might not be halfway between n1.posOrig and n2.posOrig

      local biNormal = mapmgr.surfaceNormalBelow(posOrig, radiusOrig * 0.5); biNormal:setScaled(-1)

      -- Interpolated normals
      local normal = vec3()
      if segLenSq > square(2 * radiusOrig + n1.radiusOrig + n2.radiusOrig) then
        -- calculate normal from the direction vector of edge (i, i+1)
        normal:setSub2(plan[i+1].pos, plan[i].pos)
        normal:setCross(biNormal, normal)
        normal:normalize()
      else
        -- calculate from adjacent normals
        local norm1 = plan[i].normal:cross(biNormal)
        norm1:setCross(biNormal, norm1); norm1:normalize()
        local norm2 = plan[i+1].normal:cross(biNormal)
        norm2:setCross(biNormal, norm2); norm2:normalize()
        normal:setAdd2(norm1, norm2)
        normal:setScaled(1 / (normal:length() + 1e-30))
      end

      local pos = n1.pos + n2.pos; pos:setScaled(0.5)
      local vec = n1.pos - pos; vec.z = 0
      local dirVec = vec:normalized()

      local _, t2 = closestLinePoints(pos, pos + normal, n1.posOrig, n2.posOrig)
      posOrig = linePointFromXnorm(n1.posOrig, n2.posOrig, t2)
      local edgeNormal = biNormal:cross(n2.posOrig - n1.posOrig); edgeNormal:normalize()
      local _, t2 = closestLinePoints(posOrig, posOrig + normal, plan[i].posOrig + plan[i].radiusOrig * edgeNormal, plan[i+1].posOrig + plan[i+1].radiusOrig * edgeNormal)
      local limPos = linePointFromXnorm(plan[i].posOrig + plan[i].radiusOrig * edgeNormal, plan[i+1].posOrig + plan[i+1].radiusOrig * edgeNormal, max(0, min(1, t2)))
      local roadHalfWidth = posOrig:distance(limPos)
      local lateralXnorm = pos:xnormOnLine(posOrig, limPos) * roadHalfWidth -- [-r, r]
      local chordLength = roadHalfWidth / radiusOrig

      n1.length = n1.length * 0.5

      n2.vec:set(vec)
      n2.dirVec:set(dirVec)

      --local laneLimLeft = (n1.laneLimLeft / (n1.radiusOrig * n1.chordLength) + n2.laneLimLeft / (n2.radiusOrig * n2.chordLength)) * 0.5 * roadHalfWidth
      --local laneLimRight = (n1.laneLimRight / (n1.radiusOrig * n1.chordLength) + n2.laneLimRight / (n2.radiusOrig * n2.chordLength)) * 0.5 * roadHalfWidth

      local rangeLeft = (n1.rangeLeft + n2.rangeLeft) * 0.5 -- lane range left boundary lateral coordinate in [0, 1]. 0 is left road boundary: always 0 when driveInLane is off
      local rangeRight = (n1.rangeRight + n2.rangeRight) * 0.5 -- lane range right boundary lateral coordinate in [0, 1]. 1 is right road boundary: always 1 when driveInLane is off
      local rangeLaneCount = (n1.rangeLaneCount + n2.rangeLaneCount) * 0.5 -- number of lanes in the range: always 1 when driveInLane is off

      local laneWidth = (rangeRight - rangeLeft) / rangeLaneCount -- self explanatory: entire width of the road when driveInLane is off i.e. 1
      local rangeBestLane = (n1.rangeBestLane + n2.rangeBestLane) * 0.5 -- best lane in the range: only one lane to pick from when driveInLane is off

      local laneLimLeft = linearScale(rangeLeft + rangeBestLane * laneWidth, 0, 1, -roadHalfWidth, roadHalfWidth) -- lateral coordinate of left boundary of lane rescaled to the road half width
      local laneLimRight = linearScale(rangeLeft + (rangeBestLane + 1) * laneWidth, 0, 1, -roadHalfWidth, roadHalfWidth) -- lateral coordinate of right boundary of lane rescaled to the road half width

      local roadSpeedLimit
      if n2.pathidx > 1 then
        roadSpeedLimit = mapData.graph[route.path[n2.pathidx]][route.path[n2.pathidx-1]].speedLimit
      else
        roadSpeedLimit = n2.roadSpeedLimit
      end

      if plan.stopSeg and plan.stopSeg >= i + 1 then
        plan.stopSeg = plan.stopSeg + 1
      end

      local manSpeed
      if n1.manSpeed and n2.manSpeed then
        manSpeed = (n1.manSpeed + n2.manSpeed) * 0.5
      end

      tableInsert(plan, i+1, {
        posOrig = posOrig,
        pos = pos,
        vec = vec,
        dirVec = dirVec,
        turnDir = vec3(0, 0, 0),
        biNormal = biNormal,
        normal = normal,
        radiusOrig = radiusOrig,
        pathidx = n2.pathidx,
        roadSpeedLimit = roadSpeedLimit,
        chordLength = chordLength,
        widthMarginOffset = (n1.widthMarginOffset + n2.widthMarginOffset) * 0.5,
        laneLimLeft = laneLimLeft,
        laneLimRight = laneLimRight,
        rangeLeft = rangeLeft,
        rangeRight = rangeRight,
        rangeLaneCount = rangeLaneCount,
        rangeBestLane = rangeBestLane, -- 0 Indexed
        length = n1.length,
        curvature = 0,
        lateralXnorm = lateralXnorm,
        legalSpeed = nil,
        manSpeed = manSpeed,
        speed = nil,
        trafficSqVel = math.huge
      })

      if n1.lanesOpen and n2.lanesOpen then
        openLaneToLaneRange(plan[i+1])
      end

      plan.planCount = plan.planCount + 1
      break
    end
    distOnPlan = distOnPlan + sqrt(segLenSq)
  end
  distOnPlan = nil

  if plan.targetSeg == nil then
    calculateTarget(plan)
  end

  for i = 0, plan.planCount do
    if forces[i] then
      forces[i]:set(0,0,0)
    else
      forces[i] = vec3(0,0,0)
      velocities[i] = vec3(0,0,0)
    end
  end

  -- calculate spring forces
  local nforce = vec3()

  if trajMethod == 'spring' then
    for i = 1, plan.planCount-1 do
      local n1 = plan[i]
      local v1 = n1.dirVec
      local v2 = plan[i+1].dirVec

      n1.turnDir:setSub2(v1, v2); n1.turnDir:normalize()
      nforce:setScaled2(n1.turnDir, (1-twt.state) * max(1 - v1:dot(v2), 0) * parameters.turnForceCoef)

      forces[i+1]:setSub(nforce)
      forces[i-1]:setSub(nforce)
      nforce:setScaled(2)
      forces[i]:setAdd(nforce)
    end
  elseif trajMethod == 'springDampers' then
    local dforce = vec3()
    local stiff = 400
    local damper = 2
    for i = 1, plan.planCount-1 do
      local n1 = plan[i]
      local v1 = n1.dirVec
      local v2 = plan[i+1].dirVec

      n1.turnDir:setSub2(v1, v2); n1.turnDir:normalize()
      nforce:setScaled2(n1.turnDir, (1-twt.state) * max(1 - v1:dot(v2), 0) * parameters.turnForceCoef)

      nforce:setScaled2(n1.turnDir, (1-twt.state) * max(1 - v1:dot(v2), 0) * parameters.turnForceCoef * stiff)
      dforce = -1*(((1*velocities[i]-velocities[i-1]) - (velocities[i+1]-velocities[i]))* parameters.turnForceCoef * damper/4)
      dforce:setScaled2(n1.turnDir, n1.turnDir:dot(dforce))
      nforce:setAdd(dforce)

      forces[i+1]:setSub(nforce)
      forces[i-1]:setSub(nforce)
      nforce:setScaled(2)
      forces[i]:setAdd(nforce)
    end

    for i = 1, plan.planCount-1 do
      forces[i] = forces[i] - velocities[i] * parameters.turnForceCoef * damper
      velocities[i] = velocities[i] + forces[i]*dt
      forces[i] = velocities[i]*dt
    end
  end

  -- other vehicle awareness
  plan.trafficMinProjSpeed = math.huge

  table.clear(trafficTable)
  local trafficTableLen = 0


  --*** computing path indexes (start/final) for trafficFilter****
  local indexes = {start = plan[1].pathidx , final = plan[plan.planCount].pathidx}
  if filtered then
    local dist = plan.planLen
    while dist < distAhead or indexes.final < indexes.start + 1 do
      indexes.final = indexes.final + 1
      if route.path[indexes.final] then
        dist = dist + mapData.positions[route.path[indexes.final-1]]:distance(mapData.positions[route.path[indexes.final]])
      else
        indexes.final = indexes.final - 1
        break
      end
    end
  end
  --*************
  for plID, v in pairs(mapmgr.getObjects()) do
    if plID ~= objectId and (M.mode ~= 'chase' or plID ~= player.id or chaseData.playerState == 'stopped') then
      v.targetType = (player and plID == player.id) and M.mode
      if avoidCars == 'on' or v.targetType == 'follow' then
        v.length = obj:getObjectInitialLength(plID) + 0.3
        v.width = obj:getObjectInitialWidth(plID)
        local posFront = obj:getObjectFrontPosition(plID)
        local dirVec = v.dirVec
        v.posFront = dirVec * 0.3 + posFront
        v.posRear = dirVec * (-v.length) + posFront
        v.posMiddle = (v.posFront + v.posRear) * 0.5
        if not filtered or (filtered and trafficFilter(indexes, route, radiusFilter, v, intersection, vdraw)) then
          table.insert(trafficTable, v)
          trafficTableLen = trafficTableLen + 1
        end
      end
    end
  end

  local openPlanLanesIdx = 0
  if trafficTableLen > 0 then
    local fl, rl, fr, rr
    local lenVec = ai.dirVec * ai.length
    local midPos = ai.pos - lenVec * 0.5
    --local planPos = linePointFromXnorm(plan[1].pos, plan[2].pos, plan.aiXnormOnSeg or 0)
    --midPos = linePointFromXnorm(planPos, planPos - lenVec, midPos:xnormOnLine(planPos, planPos - lenVec)) -- offset as next plan node
    local dispLeft, dispRight = 0, 0

    for _, v in ipairs(trafficTable) do -- side avoidance loop
      local xnorm = v.posFront:xnormOnLine(midPos + lenVec, midPos - lenVec)
      if ai.speed > 1 and v.vel:dot(ai.dirVec) > 0 and xnorm > 0 and xnorm < 1 and abs(v.posFront.z - ai.pos.z) < 4 then
        fl = fl or midPos - ai.rightVec * ai.width * 0.5 + lenVec
        rl = rl or fl - lenVec * 2
        fr = fr or midPos + ai.rightVec * ai.width * 0.5 + lenVec
        rr = rr or fr - lenVec * 2

        local posF = v.posFront
        local rightVec = v.dirVec:cross(v.dirVecUp)
        local posL = posF - rightVec * (v.width * 0.5 + 0.1)
        local posR = posF + rightVec * (v.width * 0.5 + 0.1)

        local xnorm1, xnorm2 = closestLinePoints(posF, posR, rl, fl)
        local xnorm3, xnorm4 = closestLinePoints(posF, posL, rr, fr)

        if xnorm1 > 0 and xnorm1 < 1 and xnorm2 > 0 and xnorm2 < 1 then -- ai left side
          dispLeft = max(dispLeft, linePointFromXnorm(posF, posR, xnorm1):squaredDistance(posR))
        elseif xnorm3 > 0 and xnorm3 < 1 and xnorm4 > 0 and xnorm4 < 1 then -- ai right side
          dispRight = max(dispRight, linePointFromXnorm(posF, posL, xnorm3):squaredDistance(posL))
        end
      end
    end

    --if fl then
      --local cornerColor = color(255, 128, 0, 160)
      --obj.debugDrawProxy:drawSphere(0.2, fl, cornerColor)
      --obj.debugDrawProxy:drawSphere(0.2, rl, cornerColor)
      --obj.debugDrawProxy:drawSphere(0.2, fr, cornerColor)
      --obj.debugDrawProxy:drawSphere(0.2, rr, cornerColor)
      --local sideColor = color(clamp(sqrt(dispLeft) * 255, 0, 255), 0, clamp(sqrt(dispRight) * 255, 0, 255), 160)
      --obj.debugDrawProxy:drawSphere(0.4, midPos + vec3(0,0,2), sideColor)
    --end

    if dispLeft > 0 or dispRight > 0 then
      local sideDisp = sqrt(dispLeft) - sqrt(dispRight)
      sideDisp = min(dt * parameters.awarenessForceCoef * 10, abs(sideDisp)) * sign2(sideDisp) -- limited displacement per frame
      -- maybe needs some smoother to prevent left / right "bouncing"
      local curDist = 0
      local lastPlanIdx = 2
      local targetDist = square(ai.speed) / (2 * g * aggression) + max(30, ai.speed * 3) -- longer adjustment at higher speeds

      local tmpVec = vec3()
      for i = 2, plan.planCount - 1 do
        openLaneToLaneRange(plan[i])
        plan[i].lateralXnorm = clamp(plan[i].lateralXnorm + sideDisp * (targetDist - curDist) / targetDist, plan[i].laneLimLeft, plan[i].laneLimRight)
        tmpVec:setScaled2(plan[i].normal, plan[i].lateralXnorm)
        plan[i].pos:setAdd2(plan[i].posOrig, tmpVec)

        curDist = curDist + plan[i - 1].length
        lastPlanIdx = i

        plan[i].vec:setSub2(plan[i-1].pos, plan[i].pos); plan[i].vec.z = 0
        plan[i].dirVec:set(plan[i].vec)
        plan[i].dirVec:normalize()

        if curDist > targetDist then break end
      end

      updatePlanLen(plan, 2, lastPlanIdx + 1)
    end

    local trafficMinSpeedSq = math.huge
    local distanceT = 0
    local minTrafficDir = 1
    local nDir, forceVec = vec3(), vec3()
    nDir:setSub2(plan[2].pos, plan[1].pos); nDir:setScaled(1 / (plan[1].length + 1e-30))
    local aiPathVel = ai.vel:dot(nDir)
    local aiPathVelInv = 1 / abs(aiPathVel + 1e-30)
    local inMultipleLanes = plan[2].laneLimRight - plan[2].laneLimLeft > 3.45 * 1.5 -- one and a half lanes
    for i = 2, plan.planCount-1 do
      local arrivalT = distanceT * aiPathVelInv
      local n1, n2 = plan[i], plan[i+1]
      local n1pos, n2pos = n1.pos, n2.pos
      nDir:setSub2(n2pos, n1pos); nDir:setScaled(1 / (n1.length + 1e-30))
      n1.trafficSqVel = math.huge

      for j = trafficTableLen, 1, -1 do
        local v = trafficTable[j]
        local plPosFront, plPosRear, plWidth = v.posFront, v.posRear, v.width
        local ai2PlVec = plPosFront - ai.pos
        local ai2PlDir = ai2PlVec:dot(ai.dirVec)

        if ai2PlDir > 0 then
          local velDisp = arrivalT * v.vel
          plPosFront = plPosFront + velDisp
          plPosRear = plPosRear + velDisp
        end

        local extVec = 0.5 * max(ai.width, plWidth) * nDir
        local n1ext, n2ext = n1pos - extVec, n2pos + extVec
        local rnorm, vnorm = closestLinePoints(n1ext, n2ext, plPosFront, plPosRear)

        local minSqDist = math.huge
        if rnorm > 0 and rnorm < 1 and vnorm > 0 and vnorm < 1 then
          minSqDist = 0
        else
          local rlen = n1.length + plWidth
          local xnorm = plPosFront:xnormOnLine(n1ext, n2ext) * rlen
          local v1 = vec3()
          if xnorm > 0 and xnorm < rlen then
            v1:setScaled2(nDir, xnorm); v1:setAdd(n1ext)
            minSqDist = min(minSqDist, v1:squaredDistance(plPosFront))
          end

          xnorm = plPosRear:xnormOnLine(n1ext, n2ext) * rlen
          if xnorm > 0 and xnorm < rlen then
            v1:setScaled2(nDir, xnorm); v1:setAdd(n1ext)
            minSqDist = min(minSqDist, v1:squaredDistance(plPosRear))
          end

          rlen = v.length + ai.width
          v1:setSub2(n1ext, plPosRear)
          local v1dot = v1:dot(v.dirVec)
          if v1dot > 0 and v1dot < rlen then
            minSqDist = min(minSqDist, v1:squaredDistance(v1dot * v.dirVec))
          end

          v1:setSub2(n2ext, plPosRear)
          v1dot = v1:dot(v.dirVec)
          if v1dot > 0 and v1dot < rlen then
            minSqDist = min(minSqDist, v1:squaredDistance(v1dot * v.dirVec))
          end
        end

        local limWidth = v.targetType == 'follow' and 2 * max(n1.radiusOrig, n2.radiusOrig) or plWidth

        if minSqDist < square((ai.width + limWidth) * 0.8) then
          local velProjOnSeg = max(0, v.vel:dot(nDir))

          local vehicleIsStopped = isVehicleStopped(v)

          if vehicleIsStopped then
            local distToParked = 0
            for ii = 2, i do
              distToParked = distToParked + plan[ii].length
            end
            if distToParked < 25 then
              openPlanLanesIdx = max(openPlanLanesIdx, i)
            end
          end
          if not plan.stopSeg and v.targetType ~= 'follow' then -- apply side forces to avoid vehicles
            local side1 = sign(n1.normal:dot(v.posMiddle) - n1.normal:dot(n1.pos))
            local side2 = sign(n2.normal:dot(v.posMiddle) - n2.normal:dot(n2.pos))

            if not v.sideDir then
              v.sideDir = side1 -- save the avoidance direction once to compare it with all of the subsequent plan nodes
            end

            if v.sideDir == side1 and inMultipleLanes then -- calculate force coef only if the avoidance side matches the initial value
              local forceCoef = trafficStates.side.side *
                                parameters.awarenessForceCoef *
                                max(0, ai.speed - velProjOnSeg, -sign(nDir:dot(v.dirVec)) * trafficStates.side.cTimer) /
                                ((1 + minSqDist) * (1 + distanceT * min(0.1, 1 / (2 * max(0, aiPathVel - v.vel:dot(nDir)) + 1e-30))))

              forceVec:setScaled2(n1.normal, side1 * forceCoef)
              forces[i]:setSub(forceVec)

              forceVec:setScaled2(n1.normal, side2 * forceCoef)
              forces[i+1]:setSub(forceVec)
            end
          end

          if M.mode ~= 'flee' and M.mode ~= 'random' and (M.mode ~= 'manual' or not race or (n1.laneLimRight - n1.laneLimLeft) <= ai.width + plWidth) then
            -- sets a minimum speed due to other vehicle velocity projection on plan segment
            -- only sets it if ai mode is valid; or if mode is "manual" but there is not enough space to pass

            if minSqDist < square((ai.width + limWidth) * 0.51)  then
              -- obj.debugDrawProxy:drawSphere(0.25, v.posFront, color(0,0,255,255))
              -- obj.debugDrawProxy:drawSphere(0.25, plPosFront, color(0,0,255,255))
              if not vehicleIsStopped then
                table.remove(trafficTable, j)
                trafficTableLen = trafficTableLen - 1
              end
              plan.trafficMinProjSpeed = min(plan.trafficMinProjSpeed, velProjOnSeg)

              n1.trafficSqVel = min(n1.trafficSqVel, velProjOnSeg * velProjOnSeg)
              trafficMinSpeedSq = min(trafficMinSpeedSq, v.vel:squaredLength())
              minTrafficDir = min(minTrafficDir, v.dirVec:dot(nDir))
            end

            if i == 2 and minSqDist < square((ai.width + limWidth) * 0.6) and ai2PlDir > 0 and v.vel:dot(ai.rightVec) * ai2PlVec:dot(ai.rightVec) < 0 then
              n1.trafficSqVel = max(0, n1.trafficSqVel - abs(1 - v.vel:dot(ai.dirVec)) * (v.vel:length()))
            end
          end
        end
      end

      distanceT = distanceT + n1.length

      if trafficTableLen < 1 then
        break
      end
    end

    -- this code was supposed to keep the vehicle stopped until the intersection was clear
    -- not working as intended, different solution needed
    --if trafficStates.intersection.timer < parameters.trafficWaitTime and plan.trafficMinProjSpeed < 3 then
      --trafficStates.intersection.timer = 0 -- reset the intersection waiting timer
    --end

    trafficStates.block.block = max(trafficMinSpeedSq, ai.speed*ai.speed) < 1 and (minTrafficDir < -0.7 or trafficStates.intersection.block)

    plan[1].trafficSqVel = plan[2].trafficSqVel

    if openPlanLanesIdx > 0 and plan[openPlanLanesIdx].length < ai.length * 1.5 then openPlanLanesIdx = openPlanLanesIdx + 1 end
    openPlanLanesToLaneRange(plan, openPlanLanesIdx)
  end

  -- spring force integrator

  --local aiWidthMargin
  --if trafficStates.action.forcedStop then
    --aiWidthMargin = ai.width * 0.35
  --else
    --aiWidthMargin = ai.width * (0.35 + 0.3 / (1 + trafficStates.side.cTimer * 0.1)) + parameters.edgeDist
  --end
  local aiWidthMargin = ai.width * 0.5 -- TODO

  -- remove lane change if vehicle has gone past it
  while route.laneChanges[1] and plan[2].pathidx > route.laneChanges[1].pathIdx do
    electrics.stop_turn_signal()
    table.remove(route.laneChanges, 1)
  end

  local skipLast = 1
  local lastNodeLatXnorm, lastNodeLimLeft, lastNodeLimRight
  if route.laneChanges[1] and math.floor(plan[2].rangeLaneCount + 0.5) > 1 and route.laneChanges[1].side ~= 0 then
    local exitNodeIdx = route.laneChanges[1].pathIdx
    local distToExit
    if plan[plan.planCount].pathidx > exitNodeIdx then
      distToExit = ai.pos:distance(mapData.positions[route.path[exitNodeIdx]])
    else
      distToExit = plan.planLen + max(0, route.pathLength[route.laneChanges[1].pathIdx] - route.pathLength[plan[plan.planCount].pathidx])
    end
    if distToExit < min(600, max(15, ai.speed * ai.speed * 0.7)) or route.laneChanges[1].commit then
      route.laneChanges[1].commit = true
      local side = route.laneChanges[1].side
      if side < 0 then
        if (electrics.values.turnsignal or -1) >= 0 then electrics.toggle_left_signal() end
      else
        if (electrics.values.turnsignal or 1) <= 0 then electrics.toggle_right_signal() end
      end
      skipLast = 0
      lastNodeLatXnorm = plan[plan.planCount].lateralXnorm
      lastNodeLimLeft = plan[plan.planCount].laneLimLeft
      lastNodeLimRight = plan[plan.planCount].laneLimRight
      local planDist = 0
      local sideForceCoeff = 2.5 * side * dt / distToExit
      local planExitIdx = plan.planCount
      if plan[plan.planCount].pathidx >= exitNodeIdx then -- if last plan node is at or past the path exit node
        planExitIdx = 1
        for i = plan.planCount, 3, -1 do
          if plan[i].pathidx == exitNodeIdx then -- if this plan node is at the exit node
            if i == plan.planCount then -- if it is also the last plan node
              local n = plan[i]
              local roadHalfWidth = n.radiusOrig * n.chordLength
              local laneWidth = n.laneLimRight - n.laneLimLeft
              if side < 0 then -- Left exit
                -- sets right limit to the right limit of the left most lane
                n.laneLimRight = max(n.laneLimLeft + ai.width, (2 * n.rangeLeft - 1) * roadHalfWidth + laneWidth) -- TODO: does This preserve the property of laneLimRight > laneLimLeft
              else -- Right exit
                -- sets left limit to the left limit of the right most lane
                n.laneLimLeft = min(n.laneLimRight - ai.width, (2 * n.rangeRight - 1) * roadHalfWidth - laneWidth) -- same ass above
              end
              lastNodeLatXnorm = nil
            end
            planExitIdx = i
            break
          end
        end
      end

      -- Add lane change forces to all nodes up to the exit node
      for i = 3, planExitIdx do
        planDist = planDist + plan[i-1].length
        local n = plan[i]
        local roadHalfWidth = n.radiusOrig * n.chordLength
        local laneHalfWidth = roadHalfWidth * (n.rangeRight - n.rangeLeft) / n.rangeLaneCount
        if side < 0 then
          n.laneLimLeft = (2 * n.rangeLeft - 1) * roadHalfWidth -- open left lane limit to left range limit
          n.laneLimRight = max(n.laneLimLeft + ai.width, min(n.laneLimRight, n.lateralXnorm + laneHalfWidth))
          forces[i]:setAdd(planDist * sideForceCoeff * square(min(1, 0.25 * abs(n.lateralXnorm - n.laneLimLeft))) * n.normal)
        else
          n.laneLimRight = (2 * n.rangeRight - 1) * roadHalfWidth -- open right lane limit to right range limit
          n.laneLimLeft = min(n.laneLimRight - ai.width, max(n.laneLimLeft, n.lateralXnorm - laneHalfWidth))
          forces[i]:setAdd(planDist * sideForceCoeff * square(min(1, 0.25 * abs(n.laneLimRight - n.lateralXnorm))) * n.normal)
        end
      end

      for i = planExitIdx + 1, plan.planCount do
        planDist = max(0, planDist - plan[i-1].length)
        if planDist == 0 then break end
        local n = plan[i]
        if side < 0 then
          forces[i]:setAdd(planDist * sideForceCoeff * square(min(1, 0.25 * abs(n.lateralXnorm - n.laneLimLeft))) * n.normal)
        else
          forces[i]:setAdd(planDist * sideForceCoeff * square(min(1, 0.25 * abs(n.laneLimRight - n.lateralXnorm))) * n.normal)
        end
      end
    end
  end

  local tmpVec = vec3()
  for i = 2, plan.planCount-skipLast do
    local n = plan[i]
    local roadHalfWidth = n.radiusOrig * n.chordLength

    -- Apply a force towards the center of the lane when driving in lane
    local dispToLeftRange, dispToRightRange = 0, 0
    if driveInLaneFlag then
      local rangeLeft = (2 * n.rangeLeft - 1) * roadHalfWidth
      local rangeRight = (2 * n.rangeRight - 1) * roadHalfWidth
      local b = 0.5 * (n.laneLimRight - n.laneLimLeft) + 1e-30
      dispToLeftRange = 0.15 * min(1, max(0, b - (n.lateralXnorm - rangeLeft)) / b)
      dispToRightRange = 0.15 * min(1, max(0, b - (rangeRight - n.lateralXnorm)) / b)
    end

    local k = n.normal:dot(forces[i])
    local displacement = dispToLeftRange - dispToRightRange + sign(k) * min(abs(k), parameters.springForceIntegratorDispLim) -- displacement distance per frame (lower value means better stability)
    -- Prevents node displacement direction switching, improves on instabilities.
    displacement = displacement * max(0, sign2(displacement * (n.dispDir or 0)))
    n.dispDir = sign(displacement)

    local roadLimLeft = min(0, -roadHalfWidth + aiWidthMargin) -- should be non-positive
    local roadLimRight = max(0, roadHalfWidth - aiWidthMargin) -- should be non-negative

    local newLateralXnorm = clamp(n.lateralXnorm + displacement,
      max(n.laneLimLeft + ai.width * 0.4, roadLimLeft), min(n.laneLimRight - ai.width * 0.4, roadLimRight))

    tmpVec:setScaled2(n.normal, newLateralXnorm - n.lateralXnorm)
    n.pos:setAdd(tmpVec) -- remember that posOrig and pos are not alligned along the normal
    n.vec:setSub2(plan[i-1].pos, n.pos); n.vec.z = 0
    n.dirVec:set(n.vec); n.dirVec:normalize()

    n.lateralXnorm = newLateralXnorm
  end

  if lastNodeLatXnorm then
    local roadHalfWidth = plan[plan.planCount].radiusOrig * plan[plan.planCount].chordLength
    local rangeLeft, rangeRight = (2 * plan[plan.planCount].rangeLeft - 1) * roadHalfWidth, (2 * plan[plan.planCount].rangeRight - 1) * roadHalfWidth
    local latXnorm = clamp(plan[plan.planCount].lateralXnorm, rangeLeft, rangeRight)
    local disp = latXnorm - lastNodeLatXnorm
    plan[plan.planCount].laneLimLeft = max(rangeLeft, min(latXnorm, lastNodeLimLeft + disp))
    plan[plan.planCount].laneLimRight = min(rangeRight, max(latXnorm, lastNodeLimRight + disp))
  end

  updatePlanLen(plan, 2, plan.planCount)

  -- smoothly distribute error from planline onto the front segments
  if parameters.planErrorSmoothing and plan.targetPos and plan.targetSeg and plan.planCount > plan.targetSeg and twt.state == 0 then
    local dTotal = 0
    local sumLen = table.new(plan.targetSeg-1, 0)
    sumLen[1] = 0
    for i = 2, plan.targetSeg - 1  do
      sumLen[i] = dTotal
      dTotal = dTotal + plan[i].length
    end
    dTotal = max(1, dTotal + plan.targetPos:distance(plan[plan.targetSeg].pos))

    local p1, p2 = plan[1].pos, plan[2].pos
    local dispVec = ai.pos - linePointFromXnorm(p1, p2, ai.pos:xnormOnLine(p1, p2)); dispVec:setScaled(0.5 * dt)

    tmpVec:setSub2(p2, p1); tmpVec:setCross(tmpVec, ai.upVec); tmpVec:normalize()
    aiDeviation = dispVec:dot(tmpVec)

    local dispVecRatio = dispVec / dTotal
    for i = plan.targetSeg - 1, 1, -1 do
      local n = plan[i]

      dispVec:setScaled2(dispVecRatio, dTotal - sumLen[i])
      dispVec:setSub(dispVec:dot(n.biNormal) * n.biNormal)
      n.pos:setAdd(dispVec)

      local halfWidth = n.radiusOrig * n.chordLength
      tmpVec:setAdd2(n.posOrig, n.normal)
      n.lateralXnorm = clamp(n.pos:xnormOnLine(n.posOrig, tmpVec), -halfWidth, halfWidth)

      plan[i+1].vec:setSub2(plan[i].pos, plan[i+1].pos); plan[i+1].vec.z = 0
      plan[i+1].dirVec:setScaled2(plan[i+1].vec, 1 / plan[i+1].vec:lengthGuarded())
    end

    updatePlanLen(plan, 1, plan.targetSeg-1)
  end

  calculateTarget(plan)

  -- calculate plan node curvature
  local len, n3vec = 0, vec3()
  plan[1].curvature = plan[1].curvature or inCurvature(plan[1].vec, plan[2].vec)
  for i = 2, plan.planCount - 1 do
    local n1, n2 = plan[i], plan[i+1]

    n3vec:setSub2(n1.pos, plan[min(plan.planCount, i + 2)].pos); n3vec.z = 0
    local curvature = min(inCurvature(n1.vec, n2.vec), inCurvature(n1.vec, n3vec))

    if n1.curvature then
      -- calculate curvature temporal smoothing parameter (fast reacting, time dependent)
      local curvatureRateDt = min(25 + 0.000045 * len * len * len * len, 1000) * dt
      local alpha = curvatureRateDt / (1 + curvatureRateDt)
      n1.curvature = curvature + alpha * (n1.curvature - curvature)
    else
      n1.curvature = curvature
    end

    len = len + n1.length
  end

  -- Speed Planning --
  local totalAccel = min(aggression, staticFrictionCoef) * g

  local lastNode = plan[plan.planCount]
  if route.path[lastNode.pathidx+1] or (race and noOfLaps and noOfLaps > 1) then
    if plan.stopSeg and plan.stopSeg <= plan.planCount then
      lastNode.speed = 0
    else
      lastNode.speed = lastNode.manSpeed or sqrt(2 * 550 * totalAccel) -- shouldn't this be calculated based on the path length remaining?
    end
  else
    lastNode.speed = lastNode.manSpeed or 0
  end
  lastNode.roadSpeedLimit = plan[plan.planCount-1].roadSpeedLimit
  lastNode.legalSpeed = min(lastNode.roadSpeedLimit or math.huge, lastNode.speed)

  local gT = vec3()
  -- Use Backward or Forward + Backward algorithm
  if speedProfileMode then
    for i = 1, plan.planCount-1 do -- last point doesn't have curvature, so as speed for this point we can set lastNode.speed
      local n1, n2 = plan[i], plan[i+1]
      -- consider inclination
      gT:setSub2(n2.pos, n1.pos); gT:setScaled(gravityDir:dot(gT) / max(square(n1.length), 1e-30)) -- gravity vec parallel to road segment: positive when downhill
      local gN = gravityDir:distance(gT) -- gravity component normal to road segment
      n1.acc_max = totalAccel * gN
      n1.speed = sqrt(n1.acc_max / max(n1.curvature, 1e-30)) -- available centripetal acceleration * radius
    end
    plan[plan.planCount].acc_max = plan[plan.planCount-1].acc_max

    if speedProfileMode == 'ForwBack' then
      solver_f_acc_profile(plan)
    end

    solver_b_acc_profile(plan)
  else -- Use standard algotihm with curvature
    for i = plan.planCount-1, 1, -1 do
      local n1, n2 = plan[i], plan[i+1]

      -- consider inclination
      gT:setSub2(n2.pos, n1.pos); gT:setScaled(gravityDir:dot(gT) / max(square(n1.length), 1e-30)) -- gravity vec parallel to road segment: positive when downhill
      local gN = gravityDir:distance(gT) -- gravity component normal to road segment

      local curvature = max(n1.curvature, 1e-5)
      local turnSpeedSq = totalAccel * gN / curvature -- available centripetal acceleration * radius

      local n1SpeedSq
      if plan.stopSeg and plan.stopSeg <= i then
        n1SpeedSq = 0
      else -- speed limit imposed by other traffic vehicles and speed limit imposed by trajectory geometry (curvature and path length)
        -- https://physics.stackexchange.com/questions/312569/non-uniform-circular-motion-velocity-optimization
        n1SpeedSq = min(n1.trafficSqVel, turnSpeedSq * sin(min(asin(min(1, square(n2.speed) / turnSpeedSq)) + 2 * curvature * n1.length, pi * 0.5)))
      end

      n1.speed = n1.manSpeed or
                  (M.speedMode == 'limit' and M.routeSpeed and min(M.routeSpeed, sqrt(n1SpeedSq))) or
                  (M.speedMode == 'set' and M.routeSpeed) or
                  sqrt(n1SpeedSq)

      -- Speed envelope considering road speed limits
      if M.speedMode == 'legal' then
        n2.legalSpeed = n2.legalSpeed or n2.speed

        if plan.stopSeg and plan.stopSeg <= i then
          n1.legalSpeed = 0
        else -- speed limit imposed by other traffic vehicles and speed limit imposed by trajectory geometry (curvature and path length)
          local n1LegalSpeedSq = min(n1.trafficSqVel, turnSpeedSq * sin(min(asin(min(1, square(n2.legalSpeed) / turnSpeedSq)) + 2 * curvature * n1.length, pi * 0.5)))
          if n1.roadSpeedLimit then
            n1.legalSpeed = min(sqrt(n1LegalSpeedSq), n1.roadSpeedLimit * (1 + aggression * 2 - 0.6))
          else
            n1.legalSpeed = sqrt(n1LegalSpeedSq)
          end
        end
      end

      n1.trafficSqVel = math.huge
    end
  end

  plan.targetSpeed = plan[1].speed + max(0, plan.aiXnormOnSeg) * (plan[2].speed - plan[1].speed)
  if M.speedMode == 'legal' then
    plan.targetSpeedLegal = plan[1].legalSpeed + max(0, plan.aiXnormOnSeg) * (plan[2].legalSpeed - plan[1].legalSpeed)
  else
    plan.targetSpeedLegal = math.huge
  end

  return route
end

local function resetMapAndRoute()
  mapData = nil
  signalsData = nil
  currentRoute = nil
  race = nil
  noOfLaps = nil
  internalState = 'onroad'
  changePlanTimer = 0
  resetAggression()
  resetInternalStates()
  resetParameters()
end

local function getMapEdges(cutOffDrivability, node)
  -- creates a table (edgeDict) with map edges with drivability > cutOffDrivability
  if mapData ~= nil then
    local allSCC = mapData:scc(node) -- An array of dicts containing all strongly connected components reachable from 'node'.
    local maxSccLen = 0
    local sccIdx
    for i, scc in ipairs(allSCC) do
      -- finds the scc with the most nodes
      local sccLen = scc[0] -- position at which the number of nodes in currentSCC is stored
      if sccLen > maxSccLen then
        sccIdx = i
        maxSccLen = sccLen
      end
      scc[0] = nil
    end
    local currentSCC = allSCC[sccIdx]
    local keySet = {}
    local keySetLen = 0

    edgeDict = {}
    for nid, n in pairs(mapData.graph) do
      if currentSCC[nid] or not driveInLaneFlag then
        for lid, data in pairs(n) do
          if (currentSCC[lid] or not driveInLaneFlag) and (data.drivability > cutOffDrivability) then
            local inNode = data.inNode or nid
            local outNode = inNode == nid and lid or nid
            keySetLen = keySetLen + 1
            keySet[keySetLen] = {inNode, outNode}
            edgeDict[inNode..'\0'..outNode] = 1
            if not data.inNode or not driveInLaneFlag then
              edgeDict[outNode..'\0'..inNode] = 1
            end
          end
        end
      end
    end

    if keySetLen == 0 then return end
    local edge = keySet[math.random(keySetLen)]

    return edge[1], edge[2]
  end
end

local function newManualPath()
  local newRoute, n1, n2, dist
  local offRoad = false

  if manualPath then
    if currentRoute and currentRoute.path then
      pathExtend(currentRoute.path, manualPath)
    else
      newRoute = createNewRoute(manualPath)
      currentRoute = newRoute
    end
    manualPath = nil
  elseif wpList then
    if currentRoute and currentRoute.path then
      newRoute = {
        path = currentRoute.path,
        plan = currentRoute.plan,
        laneChanges = currentRoute.laneChanges,
        lastLaneChangeIdx = currentRoute.lastLaneChangeIdx,
        pathLength = currentRoute.pathLength
      }
    else
      n1, n2, dist = mapmgr.findClosestRoad(ai.pos)

      if n1 == nil or n2 == nil then
        guihooks.message("Could not find a road network, or closest road is too far", 5, "AI debug")
        log('D', "AI", "Could not find a road network, or closest road is too far")
        return
      end

      ai.currentSegment[1] = n1
      ai.currentSegment[2] = n2

      if dist > 2 * max(mapData.radius[n1], mapData.radius[n2]) then
        offRoad = true
        local vec1 = mapData.positions[n1] - ai.pos
        local vec2 = mapData.positions[n2] - ai.pos

        if ai.dirVec:dot(vec1) > 0 and ai.dirVec:dot(vec2) > 0 then
          if vec1:squaredLength() > vec2:squaredLength() then
            n1, n2 = n2, n1
          end
        elseif ai.dirVec:dot(mapData.positions[n2] - mapData.positions[n1]) > 0 then
          n1, n2 = n2, n1
        end
      elseif ai.dirVec:dot(mapData.positions[n2] - mapData.positions[n1]) > 0 then
        n1, n2 = n2, n1
      end

      newRoute = createNewRoute({n1})
    end

    for i = 0, #wpList-1 do
      local wp1 = wpList[i] or newRoute.path[#newRoute.path]
      local wp2 = wpList[i+1]
      local route = mapData:getPath(wp1, wp2, driveInLaneFlag and 1e4 or 1)
      local routeLen = #route
      if routeLen == 0 or (routeLen == 1 and wp2 ~= wp1) then
        guihooks.message("Path between waypoints '".. wp1 .."' - '".. wp2 .."' Not Found", 7, "AI debug")
        log('D', "AI", "Path between waypoints '".. wp1 .."' - '".. wp2 .."' Not Found")
        return
      end

      for j = 2, routeLen do
        tableInsert(newRoute.path, route[j])
      end
    end

    wpList = nil

    if not offRoad and newRoute.path[3] and newRoute.path[2] == n2 then
      tableRemove(newRoute.path, 1)
    end

    currentRoute = newRoute
  end
end

local function setScriptedPath(arg)
  mapmgr.setCustomMap(arg.mapData)
  mapData = mapmgr.mapData

  setParameters({driveStyle = arg.driveStyle or 'default',
                staticFrictionCoefMult = max(0.95, arg.staticFrictionCoefMult or 0.95),
                lookAheadKv = max(0.1, arg.lookAheadKv or parameters.lookAheadKv),
                planErrorSmoothing = false,
                applyWidthMarginOffset = false,
                springForceIntegratorDispLim = 0,
                turnForceCoef = 2})

  avoidCars = arg.avoidCars or 'off'

  setSpeed(arg.routeSpeed)
  setSpeedMode(arg.routeSpeedMode)
  setAggressionExternal(arg.aggression)

  if arg.speedProfile and next(arg.speedProfile) then
    speedProfile = arg.speedProfile
  end

  currentRoute = createNewRoute(arg.path) -- {path = arg.path, plan = {}}

  stateChanged()
end

local function validateUserInput(list)
  validateInput = nop
  list = list or wpList
  if not list then return end
  local isValid = list[1] and true or false
  for i = 1, #list do -- #wpList
    local nodeAlias = mapmgr.nodeAliases[list[i]]
    if nodeAlias then
      if mapData.graph[nodeAlias] then
        list[i] = nodeAlias
      else
        if isValid then
          guihooks.message("One or more of the waypoints were not found on the map. Check the game console for more info.", 6, "AI debug")
          log('D', "AI", "The waypoints with the following names could not be found on the Map")
          isValid = false
        end
        -- print(list[i])
      end
    end
  end

  return isValid
end

local function fleePlan()
  if aggressionMode == 'rubberBand' then
    setAggressionInternal(max(0.3, 0.95 - 0.0015 * player.pos:distance(ai.pos)))
  end

  -- extend the plan if possible and desirable
  if currentRoute and not currentRoute.plan.reRoute then
    local plan = currentRoute.plan
    if (ai.pos - player.pos):dot(ai.dirVec) >= 0 and not targetWPName and internalState ~= 'offroad' and plan.trafficMinProjSpeed > 3 then
      local path = currentRoute.path
      local pathCount = #path
      if pathCount >= 3 and plan[2].pathidx > pathCount * 0.7 then
        local cr1 = path[pathCount-1]
        local cr2 = path[pathCount]
        local dirVec = mapData.positions[cr2] - mapData.positions[cr1]
        dirVec:normalize()
        pathExtend(path, mapData:getFleePath(cr2, dirVec, player.pos, getMinPlanLen(), 0.01, 0.01))
        planAhead(currentRoute)
        return
      end
    end
  end

  if not currentRoute or changePlanTimer == 0 or currentRoute.plan.reRoute then
    local wp1, wp2 = mapmgr.findClosestRoad(ai.pos)
    if wp1 == nil or wp2 == nil then
      internalState = 'offroad'
      return
    else
      internalState = 'onroad'
    end

    ai.currentSegment[1] = wp1
    ai.currentSegment[2] = wp2

    local dirVec
    if currentRoute and currentRoute.plan.trafficMinProjSpeed < 3 then
      changePlanTimer = 5
      dirVec = -ai.dirVec
    else
      dirVec = ai.dirVec
    end

    local startnode = pickAiWp(wp1, wp2, dirVec)
    local path
    if not targetWPName then
      path = mapData:getFleePath(startnode, dirVec, player.pos, getMinPlanLen(), 0.01, 0.01)
    else -- flee to destination
      path = mapData:getPathAwayFrom(startnode, targetWPName, ai.pos, player.pos)
      if next(path) == nil then
        targetWPName = nil
      end
    end

    if not path[1] then
      internalState = 'offroad'
      return
    else
      internalState = 'onroad'
    end

    local route = planAhead(path, currentRoute)
    if route and route.plan then
      local tempPlan = route.plan
      if not currentRoute or changePlanTimer > 0 or tempPlan.targetSpeed >= min(ai.speed, currentRoute.plan.targetSpeed) and targetsCompatible(currentRoute, route) then
        currentRoute = route
        changePlanTimer = max(1, changePlanTimer)
        return
      elseif currentRoute.plan.reRoute then
        currentRoute = route
        changePlanTimer = max(1, changePlanTimer)
        return
      end
    end
  end

  planAhead(currentRoute)
end

local function chasePlan()
  local positions = mapData.positions
  local radii = mapData.radius

  chaseData.targetSpeed = nil

  local wp1, wp2, dist1 = mapmgr.findBestRoad(ai.pos, ai.dirVec)
  if wp1 == nil or wp2 == nil then
    internalState = 'offroad'
    return
  end

  local playerSpeed = player.vel:length()
  local playerVel = playerSpeed > 1 and player.vel or player.dirVec -- uses dirVec for very low speeds

  local plwp1, plwp2, dist2 = mapmgr.findBestRoad(player.pos, playerVel)
  if plwp1 == nil or plwp2 == nil then
    internalState = 'offroad'
    return
  end

  if ai.dirVec:dot(positions[wp2] - positions[wp1]) < 0 then wp1, wp2 = wp2, wp1 end
  -- wp2 is next node for ai to drive to

  ai.currentSegment[1] = wp1
  ai.currentSegment[2] = wp2

  if (playerVel / (playerSpeed + 1e-30)):dot(positions[plwp2] - positions[plwp1]) < 0 then plwp1, plwp2 = plwp2, plwp1 end
  -- plwp2 is next node that player is driving to

  if dist1 > max(radii[wp1], radii[wp2]) + ai.width and dist2 > max(radii[plwp1], radii[plwp2]) + obj:getObjectInitialWidth(player.id) then
    internalState = 'offroad'
    return
  end

  local playerNode = plwp2
  local aiPlDist = ai.pos:distance(player.pos) -- should this be a signed distance?
  local aiPosRear = ai.pos - ai.dirVec * ai.length
  local nearDist = max(ai.length + 8, chaseData.playerStoppedTimer) -- larger if player stopped for longer (anti softlock)
  local isAtPlayerSeg = (wp1 == playerNode or wp2 == playerNode)

  if aggressionMode == 'rubberBand' then
    if M.mode == 'follow' then
      setAggressionInternal(min(0.75, 0.3 + 0.0025 * aiPlDist))
    else
      setAggressionInternal(min(0.95, 0.8 + 0.0015 * aiPlDist))
    end
  end

  -- consider calculating the aggression value but then passing it through a smoother so that transitions between chase mode and follow mode are smooth

  if playerSpeed < 1 then
    chaseData.playerStoppedTimer = chaseData.playerStoppedTimer + dt
  else
    chaseData.playerStoppedTimer = 0
  end

  if chaseData.playerStoppedTimer > 5 and aiPlDist < max(nearDist, square(ai.speed) / (2 * g * aggression)) then -- within braking distance to player
    chaseData.playerState = 'stopped'

    if ai.speed < 0.3 and aiPlDist < nearDist then
      -- do not plan new route if stopped near player
      currentRoute = nil
      internalState = 'onroad'
      return
    end
  else
    chaseData.playerState = nil
  end

  if chaseData.driveAhead and ai.speed >= 10 then -- unset this flag if the ai reached a minimum speed
    chaseData.driveAhead = false
  end

  if M.mode == 'follow' and ai.speed < 0.3 and isAtPlayerSeg and aiPlDist < nearDist then
    -- do not plan new route if ai reached player
    currentRoute = nil
    internalState = 'onroad'
    return
  end

  if currentRoute then
    local curPlan = currentRoute.plan
    local playerNodeInPath = waypointInPath(currentRoute.path, playerNode, curPlan[2].pathidx) or false

    local planVec = curPlan[2].pos - curPlan[1].pos
    local playerIncoming = playerSpeed >= 3 and playerNode == wp1 and aiPlDist < max(ai.speed, playerSpeed) and playerVel:dot(planVec) < 0 -- player is driving towards or past ai on the ai segment
    local playerBehind = playerSpeed >= 3 and planVec:dot(playerVel) > 0 and ai.dirVec:dot(aiPosRear - player.pos) > 0 -- player got passed by ai
    local playerOtherWay = not playerNodeInPath and planVec:dot(positions[playerNode] - ai.pos) < 0 and (playerSpeed < 3 or playerVel:dot(player.pos - ai.pos) > 0) -- player is driving other way from ai

    local route
    if not playerNodeInPath and not chaseData.driveAhead and (ai.speed < 3 or ai.dirVec:dot(player.pos - ai.pos) > 0) then -- prevents ai from cancelling its current route if it should slow down to turn around
      local path = mapData:getChasePath(wp1, wp2, plwp1, plwp2, ai.pos, ai.vel, player.pos, player.vel, driveInLaneFlag and 1e4 or 1)

      route = planAhead(path, currentRoute) -- ignore current route if path should go other way
      if route and route.plan then --and tempPlan.targetSpeed >= min(ai.speed, curPlan.targetSpeed) and (tempPlan.targetPos-curPlan.targetPos):dot(ai.dirVec) >= 0 then
        currentRoute = route
      end
    end

    local pathLen = getPathLen(currentRoute.path, playerNodeInPath or math.huge) -- curPlan[2].pathidx
    local playerMinPlanLen = getMinPlanLen(0, playerSpeed)
    if M.mode == 'chase' and pathLen < playerMinPlanLen then -- ai chase path should be extended
      local pathCount = #currentRoute.path
      local fleePath = mapData:getFleePath(currentRoute.path[pathCount], playerVel, player.pos, playerMinPlanLen, 0, 0)
      if fleePath[2] ~= wp1 and fleePath[2] ~= wp2 and fleePath[2] ~= currentRoute.path[pathCount - 1] then -- only extend the path if it does not do a u-turn
        pathExtend(currentRoute.path, fleePath)
      end
    end

    if not route then
      planAhead(currentRoute)
    end

    local targetSpeed

    if M.mode == 'chase' then
      local brakeDist = square(ai.speed) / (2 * g * aggression)
      local relSpeed = playerVel:dot(ai.dirVec)
      local crashSpeed = 10 -- minimum relative crash speed
      if aiPlDist < max(brakeDist, nearDist) and ai.dirVec:dot(aiPosRear - player.pos) < 0 then
        targetSpeed = max(crashSpeed, relSpeed + crashSpeed)
        chaseData.targetSpeed = targetSpeed
      end
    end

    if not chaseData.driveAhead then
      if playerIncoming or playerOtherWay then -- come to a stop, then plan to turn around
        targetSpeed = 0
      elseif playerBehind then -- match the player speed based on distance
        targetSpeed = clamp(playerSpeed * (1 - aiPlDist / 120), 5, max(5, curPlan[2].speed))
      end
    end
    curPlan.targetSpeed = targetSpeed or curPlan.targetSpeed

    if M.mode == 'chase' then
      internalState = 'onroad'

      if playerIncoming then -- player is head on versus ai
        internalState = 'tail'
      elseif aiPlDist < 25 and ai.dirVec:dot((ai.pos - ai.dirVec * ai.length) - player.pos) < 0 then -- player is near ai, but ai path does a u-turn
        local uTurn = false
        for i, p in ipairs(currentRoute.path) do -- detect path u-turn
          if p == playerNode then break end
          if i > 2 and ai.dirVec:dot(positions[p] - positions[currentRoute.path[i - 1]]) < 0 then
            uTurn = true
            break
          end
        end
        if uTurn then
          -- cast a ray to see if ai can directly attack player without hitting a barrier
          if obj:castRayStatic(ai.pos + ai.upVec * 0.5, (ai.pos - player.pos) / (aiPlDist + 1e-30), aiPlDist) >= aiPlDist then
            internalState = 'tail'
            if isAtPlayerSeg then -- important to reset the route here
              currentRoute = nil
              return
            end
          end
        end
      end
      if not playerIncoming and (plwp2 == currentRoute.path[curPlan[2].pathidx] or plwp2 == currentRoute.path[curPlan[2].pathidx + 1]) then -- player is matching ai target node
        local playerNodePos1 = positions[plwp2]
        local segDir = playerNodePos1 - positions[plwp1]
        local targetLineDir = vec3(-segDir.y, segDir.x, 0); targetLineDir:normalize()
        local xnorm1 = closestLinePoints(playerNodePos1, playerNodePos1 + targetLineDir, player.pos, player.pos + player.dirVec)
        local xnorm2 = closestLinePoints(playerNodePos1, playerNodePos1 + targetLineDir, ai.pos, ai.pos + ai.dirVec)
        -- player xnorm and ai xnorm get interpolated here
        local tarPos = playerNodePos1 + targetLineDir * clamp(lerp(xnorm1, xnorm2, 0.5), -radii[plwp2], radii[plwp2])

        local p2Target = tarPos - player.pos; p2Target:normalize()
        local plVel2Target = playerSpeed > 0.1 and player.vel:dot(p2Target) or 0
        local plTimeToTarget = tarPos:distance(player.pos) / (plVel2Target + 1e-30)

        local aiVel2Target = ai.speed > 0.1 and ai.vel:dot((tarPos - ai.pos):normalized()) or 0
        local aiTimeToTarget = tarPos:distance(ai.pos) / (aiVel2Target + 1e-30)

        if aiTimeToTarget < plTimeToTarget and not playerBehind then
          internalState = 'tail'
        end
      end
    end

    if chaseData.playerState == 'stopped' then
      currentRoute.plan.targetSpeed = 0
    end
  else
    local path
    if M.mode == 'chase' and ai.dirVec:dot(playerVel) > 0 and ai.dirVec:dot(aiPosRear - player.pos) > 0 then
      path = mapData:getFleePath(wp2, playerVel, player.pos, getMinPlanLen(100, ai.speed), 0, 0)
      chaseData.driveAhead = true
    else
      path = mapData:getChasePath(wp1, wp2, plwp1, plwp2, ai.pos, ai.vel, player.pos, player.vel, driveInLaneFlag and 1e4 or 1)
      chaseData.driveAhead = false
    end

    local route = planAhead(path)
    if route and route.plan then
      currentRoute = route
    end
  end
end

M.pullOver = false
local function setPullOver(val)
  M.pullOver = val
end

local function trafficActions()
  if not currentRoute then return end
  local path, plan = currentRoute.path, currentRoute.plan

  -- horn
  if parameters.enableElectrics and trafficStates.action.hornTimer == 0 then
    electrics.horn(true)
    trafficStates.action.hornTimerLimit = max(0.1, math.random())
  end
  if trafficStates.action.hornTimer >= trafficStates.action.hornTimerLimit then
    electrics.horn(false)
    trafficStates.action.hornTimer = -1
  end

  if trafficStates.action.hornTimer >= 0 then
    trafficStates.action.hornTimer = trafficStates.action.hornTimer + dt
  end

  local pullOver = false
  pullOver = M.pullOver

  -- hazard lights
  if beamstate.damage >= 1000 then
    if recover.recoverOnCrash then
      recover._recoverOnCrash = true
    else
      if electrics.values.signal_left_input == 0 and electrics.values.signal_right_input == 0 then
        electrics.set_warn_signal(1)
      end
      pullOver = true
    end
  end

  -- pull over
  local minSirenSqDist = math.huge
  local nearestPoliceId

  for plID, v in pairs(mapmgr.getObjects()) do
    if plID ~= objectId and v.states then
      if v.states.lightbar == 2 or (v.states.lightbar == 1 and v.vel:squaredLength() >= 100) then
        local posFront = obj:getObjectFrontPosition(plID)
        minSirenSqDist = min(minSirenSqDist, posFront:squaredDistance(ai.pos))
        nearestPoliceId = plID
      end
    end
  end
  if minSirenSqDist <= 10000 then
    pullOver = true
    trafficStates.action.nearestPoliceId = nearestPoliceId
  end

  if trafficStates.action.nearestPoliceId then
    local police = mapmgr.objects[trafficStates.action.nearestPoliceId]
    if police and police.states and police.states.lightbar then
      if ai.speed < 10 and ai.pos:squaredDistance(police.pos) < 400 and (ai.pos - police.pos):normalized():dot(police.dirVec) > 0.94 then
        pullOver = true -- vehicle stays pulled over in this case, and other traffic may keep driving
      end
    end
  end

  if pullOver and not trafficStates.action.forcedStop and ai.speed >= 3 then
    local brakeDist = square(ai.speed) / (2 * g * aggression)
    local dist = max(10, brakeDist)
    local idx = getLastNodeWithinDistance(plan, dist)
    local n = plan[idx]
    local side = mapmgr.rules.rightHandDrive and -1 or 1
    local disp = n.pos:distance(n.posOrig + n.normal * side * (n.radiusOrig * n.chordLength - ai.width * 0.5))
    trafficStates.side.displacement = disp
    --dist = dist + disp * 4 -- arbitrary extra distance?

    laneChange(plan, max(10, dist - 20), disp * side)
    setStopPoint(plan, dist, {avoidJunction = true})
    trafficStates.action.forcedStop = true
    trafficStates.side.side = mapmgr.rules.rightHandDrive and -1 or 1
  end

  if not pullOver and trafficStates.action.forcedStop then
    --laneChange(plan, 40, -trafficStates.side.displacement) -- this is no longer needed?
    setStopPoint()
    trafficStates.action.forcedStop = false
    trafficStates.action.nearestPoliceId = nil
  end

  if trafficStates.action.forcedStop and ai.speed < min(plan.targetSpeed or 0, 1) then -- instant plan stop
    setStopPoint(plan, 0)
  end

  -- Search for controlled (traffic light or stop sign) or uncontrolled (right of way) intersections along the path
  local tSi = trafficStates.intersection
  if not tSi.node then
    tSi.block = false

    tSi.startIdx = tSi.startIdx or (plan[1].wp and plan[1].pathidx-1 or plan[1].pathidx)
    for i = tSi.startIdx, #path - 1 do -- TODO: would searching up to min(#path-1, plan[plan.planCount].pathIdx) work to distribute the load over more frames work?
      local nid1, nid2 = path[i], path[i + 1]
      if not nid1 then
        nid1 = plan[1].wp -- just in case the ai is at the very start of the plan
      end

      if nid1 and nid2 then
        -- if trafficStates.intersection.prevNode == nid1 then break end -- vehicle is still within previous intersection

        local n1Pos, n2Pos = mapData.positions[nid1], mapData.positions[nid2]

        -- Controlled intersection (traffic light or stop sign)
        if signalsData and signalsData[nid1] and signalsData[nid1][nid2] then -- nodes from current path match the signals dict
            -- TODO: check the array for the ideal signal to use
            -- lane check as well, if applicable
          local bestSignal = signalsData[nid1][nid2][1]

          local nDir = n2Pos - n1Pos
          nDir.z = 0
          nDir:normalize()

          table.clear(tSi)
          tSi.node = nid1
          tSi.nextNode = nid2
          tSi.nodeIdx = 1
          tSi.pos = bestSignal.pos
          tSi.dir = nDir
          tSi.action = bestSignal.action
          tSi.block = false
        end

        -- detect uncontrolled intersection or set the turn direction for an already detected controlled intersection
        if not tSi.turnDir and tableSize(mapData.graph[nid1]) > 2 then -- why the trafficStates.intersection.turnDir check?
          -- we should try to get the effective curvature of the path after this point to determine turn signals

          -- Get Direction Vector of edge exiting nid1
          local linkDir = vec3(); linkDir:setSub2(mapData:getEdgePositions(nid2, nid1))
          linkDir.z = 0
          linkDir:normalize()

          -- Get path Direction Vector to nid1
          local prevNode = path[i-1] or plan[1].wp
          local nDir = vec3()
          local drivability = 1
          if mapData.graph[nid1][prevNode] then
            nDir:setSub2(mapData:getEdgePositions(nid1, prevNode))
            nDir.z = 0
            nDir:normalize()
            drivability = mapData.graph[nid1][prevNode].drivability
          else
            prevNode = nil
            nDir:set(ai.dirVec)
          end

          -- Give way if the direction change at nid1 is greater than 45 deg and less than 135 deg
          -- or if the current path edge leading to nid1 has drivability lower than other roads incident on nid1
          local giveWay = abs(nDir:dot(linkDir)) < 0.707
          if not giveWay and drivability < 1 then
            for _, edgeData in pairs(mapData.graph[nid1]) do
              if edgeData.drivability > drivability then
                giveWay = true
                break
              end
            end
          end

          if giveWay then
            -- Checks implicitly if this is a traffic signal or stop sign intersection (i.e node is populated)
            if not tSi.node then

              local fourthNode -- the fourth node in a T-junction (the other three nodes being prevNode, nid1, nid2)
              -- the prevNode check is to make sure one of the three roads of the T-Junction is the one the vehicle is comming from
              if prevNode and tableSize(mapData.graph[nid1]) == 3 then
                for k, v in pairs(mapData.graph[nid1]) do
                  if k ~= prevNode and k ~= nid2 then
                    fourthNode = k
                  end
                end
              end

              -- Checks if the vehicle has right of way in this T-junction
              if not (fourthNode and roadNaturalContinuation(fourthNode, nid1) ~= nid2 and gravityDir:cross(nDir):dot(linkDir) > 0) then
                local pos = n1Pos - nDir * (max(3, mapData.radius[nid1]) + 2)
                --local startIdx = tSi.startIdx
                table.clear(tSi)
                tSi.node = nid1
                tSi.nextNode = nid2
                tSi.turnNode = nid1
                tSi.turnDir = linkDir
                tSi.pos = pos
                tSi.dir = nDir
                tSi.action = 3
                tSi.block = false
              end
            else -- set turn direction for controlled intersection
              tSi.turnNode = nid1
              tSi.turnDir = linkDir
            end
          end
        end
      end
      tSi.startIdx = i + 1

      if tSi.node then

        tSi.turn = 0
        tSi.timer = 0
        if tSi.turnDir then
          if abs(tSi.dir:dot(tSi.turnDir)) < 0.707 then
            tSi.turn = -sign2(tSi.dir:cross(gravityDir):dot(tSi.turnDir))
          end
        end

        break
      end
    end
  end

  -- Manage stopping at found intersections
  if tSi.node and not trafficStates.action.forcedStop then
    local signalsRef = tSi.nodeIdx and signalsData[tSi.node][tSi.nextNode][tSi.nodeIdx]
    if signalsRef then
      tSi.action = signalsRef.action or 0 -- get action from referenced table
    else
      tSi.action = tSi.action or 0 -- default action ("go")
    end

    --local sColor = tSi.action == 0 and color(0,255,0,160) or color(255,255,0,160)
    --obj.debugDrawProxy:drawSphere(1, tSi.pos, sColor)
    --obj.debugDrawProxy:drawText(tSi.pos + vec3(0, 0, 1), color(0,0,0,255), tostring(tSi.turn))

    local stopSeg
    local brakeDist = square(ai.speed) / (2 * g * staticFrictionCoef * min(1, aggression * 1.3))
    local distSq = ai.pos:squaredDistance(tSi.pos)

    if not tSi.proximity then -- checks if intersection was reached (needs improvement)
      tSi.proximity = distSq <= 400
    end

    if ((tSi.pos + tSi.dir * 4) - ai.pos):dot(tSi.dir) >= 0 then -- vehicle position is at the stop pos (with extra distance, to be safe)
      if tSi.action == 3 or tSi.action == 2 or (tSi.action == 1 and (square(brakeDist) < distSq or tSi.commitStopOnYellow)) then -- red light or other stop condition
        local bestDist = 100
        for i = 1, #plan - 1 do -- get best plan node to set as a stopping point
          -- currently checks every frame due to plan segment updates
          -- positional check is used due to issues with using plan.pathidx or complex intersections
          -- it would be great to improve this in the future
          local dist = plan[i].pos:squaredDistance(tSi.pos)
          if dist < bestDist then
            bestDist = dist
            stopSeg = i
          end
        end
        if stopSeg and tSi.action == 1 then
          tSi.commitStopOnYellow = true
        end
      end

      if tSi.action == 3 or tSi.action == 2 then
        if stopSeg and stopSeg <= 2 and ai.speed <= 1 then -- stopped at stopping point
          tSi.timer = tSi.timer + dt
          -- if on an uncontrolled intersection, check if there are any vehicles around. if there aren't then continue.
          if tSi.action == 3 then
            local vehicleInRange = false
            local vPosF = vec3()
            local aiCenterPos = getObjectBoundingBox(objectId)
            for vId, v in pairs(mapmgr.getObjects()) do
              if vId ~= objectId then
                local vC, vX = getObjectBoundingBox(vId)
                vPosF:setAdd2(vC, vX)
                local trajDirVec = currentRoute.plan[2].dirVec
                -- condition 1: v-velocity dependent radius semi-circle centered at aiCenterPos directed in ai.dirVec
                -- condition 2: v-velocity dependent semi-circle centered at aiCenterPos directed in first plan segment direction (note plan[2].dirVec points towards plan[1].pos)
                if not isVehicleStopped(v) and (ai.dirVec:dot(vPosF) >= ai.dirVec:dot(aiCenterPos) or trajDirVec:dot(vPosF) <= trajDirVec:dot(aiCenterPos)) and
                aiCenterPos:squaredDistance(vPosF) < square(min(60, max(30, v.vel:squaredLength() / (g * staticFrictionCoef)))) then
                  vehicleInRange = true
                  break
                end
              end
            end
            if not vehicleInRange then
              tSi.timer = parameters.trafficWaitTime
            end
          end
        end

        if tSi.timer >= parameters.trafficWaitTime then
          if tSi.action == 2 then
            -- Turn on red allowed (right turn for RHT (LHD) and left turn for LHT (RHD) allowed after stopping and intersection is clear)
            if mapmgr.rules.turnOnRed and tSi.turn == (mapmgr.rules.rightHandDrive and -1 or 1) then
              tSi.nodeIdx = nil
              tSi.action = 0
            end
          else
            tSi.nodeIdx = nil
            tSi.action = 0
          end
        end
      end
    else
      if tSi.proximity then
        tSi.nodeIdx = nil
        tSi.action = 0
        if distSq > 400 then -- assumes that vehicle has cleared the intersection (20 m away from the signal point)
          -- temp data until next intersection search
          -- resync startIdx if it has fallen behind by the time the intersection is cleared.
          local startIdx = tSi.startIdx
          if plan[1].pathidx < plan[2].pathidx then -- plan[1] node is on a different path index than the node ahead of it
            -- skip path node if it is behind vehicle
            startIdx = max(startIdx, plan[1].pathidx)
          else
            startIdx = max(startIdx, plan[1].pathidx-1)
          end
          table.clear(tSi)
          tSi.timer = 0
          tSi.turn = 0
          tSi.block = false
          --tSi.prevNode = tSi.node
          tSi.startIdx = startIdx
        end
      end
    end

    plan.stopSeg = stopSeg

    if parameters.enableElectrics and tSi.turnNode and ai.pos:squaredDistance(mapData.positions[tSi.turnNode]) < square(max(20, brakeDist * 1.2)) then -- approaching intersection
      if tSi.turn < 0 and electrics.values.turnsignal >= 0 then
        electrics.toggle_left_signal()
      elseif tSi.turn > 0 and electrics.values.turnsignal <= 0 then
        electrics.toggle_right_signal()
      end
    end
  end
end

local function trafficPlan()
  if trafficStates.block.block then
    trafficStates.block.timer = trafficStates.block.timer + dt
  else
    trafficStates.block.timer = trafficStates.block.timer * 0.8
    trafficStates.block.hornFlag = false
  end

  if currentRoute and currentRoute.path[1] and not currentRoute.plan.reRoute and trafficStates.block.timer <= trafficStates.block.timerLimit then
    local plan = currentRoute.plan
    local path = currentRoute.path
    if (internalState ~= 'offroad' and plan.planLen + getPathLen(path, plan[plan.planCount].pathidx) < getMinPlanLen()) or not path[plan[plan.planCount].pathidx+2] then
      local pathCount = #path

      local newPath
      newPath = mapData:getPathTWithState(path[pathCount], mapData.positions[path[pathCount]], getMinPlanLen(), trafficPathState[1] and trafficPathState or ai.dirVec)
      table.clear(trafficPathState)
      for i, v in ipairs(newPath) do trafficPathState[i] = v end

      pathExtend(path, newPath)
    end
  else
    local wp1, wp2 = mapmgr.findBestRoad(ai.pos, ai.dirVec)

    if wp1 == nil or wp2 == nil then
      guihooks.message("Could not find a road network, or closest road is too far", 5, "AI debug")
      currentRoute = nil
      internalState = 'offroad'
      changePlanTimer = 0
      driveCar(0, 0, 0, 1)
      return
    end

    local radius = mapData.radius
    local position = mapData.positions
    local graph = mapData.graph

    local dirVec
    if trafficStates.block.timer > trafficStates.block.timerLimit and not graph[wp1][wp2].oneWay and (radius[wp1] + radius[wp2]) * 0.5 > ai.length then
      dirVec = -ai.dirVec -- tries to plan reverse direction
    else
      dirVec = ai.dirVec
    end

    wp1, wp2 = pickAiWp(wp1, wp2, dirVec)

    local path
    path = mapData:getPathTWithState(wp1, ai.pos, getMinPlanLen(), ai.dirVec)
    table.clear(trafficPathState)
    for i, v in ipairs(path) do trafficPathState[i] = v end

    if path[2] == wp2 and path[3] then
      local xnorm = ai.pos:xnormOnLine(position[wp1], position[wp1])
      if xnorm >= 0 and xnorm <= 1 and (position[wp2] - position[wp1]):dot(ai.dirVec) < 0 then
        -- vehicle is within the first path segment but facing the wrong way
        table.remove(path, 1)
      end
    end
    ai.currentSegment[1] = wp1
    ai.currentSegment[2] = wp2

    if path and path[1] then
      local route = planAhead(path, currentRoute)

      if route and route.plan then
        trafficStates.block.timerLimit = max(1, parameters.trafficWaitTime * 2)

        table.clear(trafficStates.intersection)
        trafficStates.intersection.timer = 0
        trafficStates.intersection.turn = 0
        trafficStates.intersection.block = false

        if trafficStates.block.timer > trafficStates.block.timerLimit and trafficStates.action.hornTimer == -1 then
          trafficStates.block.timer = 0
          if not trafficStates.block.hornFlag then
            trafficStates.action.hornTimer = 0 -- activates horn
            trafficStates.block.hornFlag = true -- prevents horn from triggering again while stopped
          end

          currentRoute = route
          return
        elseif not currentRoute then
          currentRoute = route
          return
        elseif route.plan.targetSpeed >= min(currentRoute.plan.targetSpeed, ai.speed) and targetsCompatible(currentRoute, route) then
          currentRoute = route
          return
        end
      end
    end
  end

  trafficActions()
  planAhead(currentRoute)
end

local function warningAIDisabled(message)
  guihooks.message(message, 5, "AI debug")
  M.mode = 'disabled'
  M.updateGFX = nop
  resetMapAndRoute()
  stateChanged()
end

local function targetFollowControl(targetSpeed, distLim) -- throttle and brake control for ai directly going to player
  -- distLim: Minimum distance allowed
  if not targetSpeed then
    if not player or not player.pos then return 0, 0, 0 end
    local plC, plX, plY, plZ = getObjectBoundingBox(player.id)
    local ai2PlDirVec = plC - ai.pos; ai2PlDirVec:normalize()
    local minHit = intersectsRay_OBB(ai.pos, ai2PlDirVec, plC, plX, plY, plZ)
    local plSpeedFromAI = player.vel:dot(ai2PlDirVec)
    local ai2PlDist = max(0, minHit - (distLim or 3))
    targetSpeed = sqrt(max(0, abs(plSpeedFromAI) * plSpeedFromAI + 2 * g * min(aggression, staticFrictionCoef) * ai2PlDist))
  end
  local speedDif = targetSpeed - ai.speed

  return clamp(speedDif, 0, 1), clamp(-speedDif, 0, 1), targetSpeed
end

local function drivabilityChangeReroute()
  -- Description: handle changes in edge drivabilities
  -- This function compares the current ai path for collisions with the drivability change set
  -- if there is an edge along the current path that had its drivability decreased
  -- a flag is raised (currentRoute.plan.reRoute) then handled by the appropriate planner

  if currentRoute ~= nil then
    -- changeSet format: {nodeA1, nodeB1, driv1, nodeA2, nodeB2, driv2, ...}
    local changeSet = mapmgr.changeSet
    local changeSetCount = #changeSet
    local changeSetDict = table.new(0, 2 * (changeSetCount / 3))

    -- populate the changeSetDict with the changeSet nodes
    for i = 1, changeSetCount, 3 do
      if changeSet[i+2] < 0 then
        changeSetDict[changeSet[i]] = true
        changeSetDict[changeSet[i+1]] = true
      end
    end

    local path = currentRoute.path
    local nodeCollisionIdx
    for i = currentRoute.plan[2].pathidx, #path do
      if changeSetDict[path[i]] then
        -- if there is a collision continue with a thorough check (edges against edges)
        nodeCollisionIdx = i
        break
      end
    end

    if nodeCollisionIdx then
      table.clear(changeSetDict)
      local edgeTab = {'','\0',''}
      -- populate the changeSetDict with changeSet edges
      for i = 1, changeSetCount, 3 do
        if changeSet[i+2] < 0 then
          local nodeA, nodeB = changeSet[i], changeSet[i+1]
          edgeTab[1] = nodeA < nodeB and nodeA or nodeB
          edgeTab[3] = nodeA == edgeTab[1] and nodeB or nodeA
          changeSetDict[tableConcat(edgeTab)] = true
        end
      end

      local edgeCollisionIdx
      -- compare path edges with changeSetDict edges starting with the earliest edge containing the initialy detected node collision
      for i = max(currentRoute.plan[2].pathidx, nodeCollisionIdx - 1), #path-1 do
        local nodeA, nodeB = path[i], path[i+1]
        edgeTab[1] = nodeA < nodeB and nodeA or nodeB
        edgeTab[3] = nodeA == edgeTab[1] and nodeB or nodeA
        if changeSetDict[tableConcat(edgeTab)] then
          edgeCollisionIdx = i
          currentRoute.plan.reRoute = edgeCollisionIdx
          break
        end
      end

      -- if edgeCollisionIdx then
      --   -- find closest possible diversion point from edgeCollisionIdx
      --   local graph = mapData.graph
      --   for i = edgeCollisionIdx, currentRoute.plan[2].pathidx, -1 do
      --     local node = path[i]
      --     if tableSize(graph[node]) > 2 then

      --     end
      --   end
      --   dump(objectId, edgeCollisionIdx, path[edgeCollisionIdx], path[edgeCollisionIdx+1])
      -- end
    end
  end
end

local function getSafeTeleportPosRot()
  if currentRoute and currentRoute.path and currentRoute.path[2] then
    local pathIdx = #currentRoute.path
    local node = currentRoute.path[pathIdx]
    local pos = mapData.positions[node]

    local node2 = currentRoute.path[pathIdx-1]
    local pos2 = mapData.positions[node2]

    local dir = (pos - pos2):normalized()
    local up = mapmgr.surfaceNormalBelow(pos)
    local rot = quatFromDir(-dir:cross(up):cross(up), up) -- minus sign is due to convention used by safeTeleport

    if not mapData.graph[node][node2].oneway then
      -- if not a one way road shift the position to the right by half the road radius (ie. 1/4 of the width)
      pos = pos + dir:cross(up):normalized() * (mapData.radius[node] * 0.5)
    end

    return pos, rot
  end
end

M.updateGFX = nop
local function updateGFX(dtGFX)
  dt = dtGFX

  if mapData ~= mapmgr.mapData then
    currentRoute = nil
  end

  if mapmgr.changeSet then
    drivabilityChangeReroute()
    mapmgr.changeSet = nil
  end

  mapData = mapmgr.mapData
  signalsData = mapmgr.signalsData

  if mapData == nil then return end

  ai.pos:set(obj:getFrontPosition())
  ai.pos.z = max(ai.pos.z - 1, obj:getSurfaceHeightBelow(ai.pos))
  ai.prevDirVec:set(ai.dirVec)
  ai.dirVec:set(obj:getDirectionVectorXYZ())
  ai.upVec:set(obj:getDirectionVectorUpXYZ())
  ai.rightVec:setCross(ai.dirVec, ai.upVec); ai.rightVec:normalize()
  ai.vel:set(obj:getSmoothRefVelocityXYZ())
  ai.speed = ai.vel:length()
  ai.width = ai.width or obj:getInitialWidth()
  ai.length = ai.length or obj:getInitialLength()
  staticFrictionCoef = parameters.staticFrictionCoefMult * obj:getStaticFrictionCoef() -- depends on ground model, tire and tire load

  misc.logData()

  if lastCommand.throttle > 0.5 and ai.speed < 1 then
    aiCannotMoveTime = aiCannotMoveTime + dt
  else
    aiCannotMoveTime = 0
  end

  if ai.speed < 3 then
    trafficStates.side.cTimer = trafficStates.side.cTimer + dt
    trafficStates.side.timer = (trafficStates.side.timer + dt) % (2 * trafficStates.side.timerLimit)
    trafficStates.side.side = sign2(trafficStates.side.timerLimit - trafficStates.side.timer)
  else
    trafficStates.side.cTimer = max(0, trafficStates.side.cTimer - dt)
    trafficStates.side.timer = 0
    trafficStates.side.side = 1
  end

  if recover.recoverOnCrash then
    if ai.speed < 3 then
      recover.recoverTimer = recover.recoverTimer + dt
    else
      recover.recoverTimer = max(0, recover.recoverTimer - 5 * dt)
    end
    if recover._recoverOnCrash or recover.recoverTimer > 60 then
      recover._recoverOnCrash = false
      recover.recoverTimer = 0
      local pos, rot = getSafeTeleportPosRot()
      if pos then
        obj:queueGameEngineLua(
          "map.safeTeleport(" .. obj:getId() .. ", " .. pos.x .. ", " .. pos.y .. ", " .. pos.z .. ", " .. rot.x .. ", " .. rot.y .. ", " .. rot.z .. ", " .. rot.w .. ", nil, nil, true, true, true)"
        )
        return
      end
    end
  end

  changePlanTimer = max(0, changePlanTimer - dt)

  -- local wp1, wp2 = mapmgr.findClosestRoad(ai.pos)
  -- if (mapData.positions[wp2] - mapData.positions[wp1]):dot(ai.dirVec) > 0 then
  --   wp1, wp2 = wp2, wp1
  -- end
  -- ai.currentSegment = {wp1, wp2}
  ai.currentSegment[1] = nil
  ai.currentSegment[2] = nil

  ------------------ RANDOM MODE ----------------
  if M.mode == 'random' then
    local route
    if not currentRoute or currentRoute.plan.reRoute or currentRoute.plan.planLen + getPathLen(currentRoute.path, currentRoute.plan[currentRoute.plan.planCount].pathidx) < getMinPlanLen() then
      local wp1, wp2 = mapmgr.findClosestRoad(ai.pos)
      if wp1 == nil or wp2 == nil then
        warningAIDisabled("Could not find a road network, or closest road is too far")
        return
      end
      ai.currentSegment[1] = wp1
      ai.currentSegment[2] = wp2

      if internalState == 'offroad' then
        local vec1 = mapData.positions[wp1] - ai.pos
        local vec2 = mapData.positions[wp2] - ai.pos
        if ai.dirVec:dot(vec1) > 0 and ai.dirVec:dot(vec2) > 0 then
          if vec1:squaredLength() > vec2:squaredLength() then
            wp1, wp2 = wp2, wp1
          end
        elseif ai.dirVec:dot(mapData.positions[wp2] - mapData.positions[wp1]) > 0 then
          wp1, wp2 = wp2, wp1
        end
      elseif ai.dirVec:dot(mapData.positions[wp2] - mapData.positions[wp1]) > 0 then
        wp1, wp2 = wp2, wp1
      end

      local path = mapData:getRandomPath(wp1, wp2, driveInLaneFlag and 1e4 or 1)

      if path and path[1] then
        local route = planAhead(path, currentRoute)
        if route and route.plan then
          if not currentRoute then
            currentRoute = route
          else
            local curPlanIdx = currentRoute.plan[2].pathidx
            local curPathCount = #currentRoute.path
            if curPlanIdx >= curPathCount * 0.9 or (targetsCompatible(currentRoute, route) and route.plan.targetSpeed >= ai.speed) then
              currentRoute = route
            end
          end
        end
      end
    end

    if currentRoute ~= route then
      planAhead(currentRoute)
    end

  ------------------ TRAFFIC MODE ----------------
  elseif M.mode == 'traffic' then
    trafficPlan()

  ------------------ MANUAL MODE ----------------
  elseif M.mode == 'manual' then
    if validateInput(wpList or manualPath) then
      newManualPath()
    elseif scriptData then
      setScriptedPath(scriptData)
      scriptData = nil
    end

    if aggressionMode == 'rubberBand' then
      updatePlayerData()
      if player ~= nil then
        if (ai.pos - player.pos):dot(ai.dirVec) > 0 then
          setAggressionInternal(max(min(0.1 + max((150 - player.pos:distance(ai.pos))/150, 0), M.extAggression), 0.5))
        else
          setAggressionInternal()
        end
      end
    end

    planAhead(currentRoute)

  ------------------ SPAN MODE ------------------
  elseif M.mode == 'span' then
    if currentRoute == nil then
      local positions = mapData.positions
      local wpAft, wpFore = mapmgr.findClosestRoad(ai.pos)
      if not (wpAft and wpFore) then
        warningAIDisabled("Could not find a road network, or closest road is too far")
        return
      end
      if ai.dirVec:dot(positions[wpFore] - positions[wpAft]) < 0 then wpAft, wpFore = wpFore, wpAft end

      ai.currentSegment[1] = wpFore
      ai.currentSegment[2] = wpAft

      local target, targetLink

      if not (edgeDict and edgeDict[1]) then
        -- creates the edgeDict and returns a random edge
        target, targetLink = getMapEdges(M.cutOffDrivability or 0, wpFore)
        if not target then
          warningAIDisabled("No available target with selected characteristics")
          return
        end
      end

      local path = {}
      while true do
        if not target then
          local maxDist = -math.huge
          local lim = 1
          repeat
            -- get most distant non walked edge
            for k, v in pairs(edgeDict) do
              if v <= lim then
                if lim > 1 then edgeDict[k] = 1 end
                local i = string.find(k, '\0')
                local n1id = string.sub(k, 1, i-1)
                local sqDist = positions[n1id]:squaredDistance(ai.pos)
                if sqDist > maxDist then
                  maxDist = sqDist
                  target = n1id
                  targetLink = string.sub(k, i+1, #k)
                end
              end
            end
            lim = math.huge -- if the first iteration does not produce a target
          until target
        end

        local nodeDegree = 1
        for lid, _ in pairs(mapData.graph[target]) do
          -- we're looking for neighboring nodes other than the targetLink
          if lid ~= targetLink then
            nodeDegree = nodeDegree + 1
          end
        end
        if nodeDegree == 1 then
          local key = target..'\0'..targetLink
          edgeDict[key] = edgeDict[key] + 1
        end

        path = mapData:spanMap(wpFore, wpAft, target, edgeDict, driveInLaneFlag and 1e7 or 1)

        if not path[2] and wpFore ~= target then
          -- remove edge from edgeDict list and get a new target (while loop will iterate again)
          edgeDict[target..'\0'..targetLink] = nil
          edgeDict[targetLink..'\0'..target] = nil
          target = nil
          if next(edgeDict) == nil then
            warningAIDisabled("Could not find a path to any of the possible targets")
            return
          end
        elseif not path[1] then
          warningAIDisabled("No Route Found")
          return
        else
          -- insert the second edge node in newRoute if it is not already contained
          local pathCount = #path
          if path[pathCount-1] ~= targetLink then path[pathCount+1] = targetLink end
          break
        end
      end

      local route = planAhead(path)
      if not route then return end
      currentRoute = route
    else
      planAhead(currentRoute)
    end

  ------------------ FLEE MODE ------------------
  elseif M.mode == 'flee' then
    updatePlayerData()
    if player then
      if validateInput() then
        targetWPName = wpList[1]
        wpList = nil
      end

      fleePlan()

      if internalState == 'offroad' then
        local targetPos = ai.pos + (ai.pos - player.pos) * 100
        local targetSpeed = math.huge
        driveToTarget(targetPos, 1, 0, targetSpeed)
        return
      end
    else
      -- guihooks.message("No vehicle to Flee from", 5, "AI debug") -- TODO: this freezes the up because it runs on the gfx step
      return
    end

  ------------------ CHASE MODE ------------------
  elseif M.mode == 'chase' or M.mode == 'follow' then
    updatePlayerData()
    if player then
      chasePlan()

      if internalState == 'tail' then
        --internalState = 'onroad'
        --currentRoute = nil
        local plai = player.pos - ai.pos
        local relvel = ai.vel:dot(plai) - player.vel:dot(plai)

        local throttle, brake, targetSpeed = targetFollowControl(chaseData.targetSpeed or math.huge)
        if relvel > 0 then
          driveToTarget(player.pos + (plai:length() / (relvel + 1e-30)) * player.vel, throttle, brake, targetSpeed)
        else
          driveToTarget(player.pos, throttle, brake, targetSpeed)
        end
        return
      elseif internalState == 'offroad' then
        local throttle, brake, targetSpeed = targetFollowControl(M.mode == 'chase' and math.huge)
        driveToTarget(player.pos, throttle, brake, targetSpeed)
        return
      elseif currentRoute == nil then
        driveCar(0, 0, 0, 1)
        return
      end

    else
      -- guihooks.message("No vehicle to Chase", 5, "AI debug")
      return
    end

  ------------------ STOP MODE ------------------
  elseif M.mode == 'stop' then
    if currentRoute then
      planAhead(currentRoute)
      local targetSpeed = max(0, ai.speed - sqrt(max(0, square(staticFrictionCoef * g) - square(sensors.gx2))) * dt)
      currentRoute.plan.targetSpeed = min(currentRoute.plan.targetSpeed, targetSpeed)
    elseif ai.vel:dot(ai.dirVec) > 0 then
      driveCar(0, 0, 0.5, 0)
    else
      driveCar(0, 1, 0, 0)
    end
    if ai.speed < 0.08 then
      driveCar(0, 0, 0, 1)
      M.mode = 'disabled'
      M.manualTargetName = nil
      M.updateGFX = nop
      resetMapAndRoute()
      stateChanged()
      if controller.mainController and restoreGearboxMode then
        controller.mainController.setGearboxMode('realistic')
      end
      return
    end
  end
  -----------------------------------------------

  if currentRoute then
    local plan = currentRoute.plan
    local targetPos = plan.targetPos
    local aiSeg = plan.aiSeg

    -- cleanup path if it has gotten too long
    if not race and plan[aiSeg].pathidx >= 10 and currentRoute.path[20] then
      local path = currentRoute.path
      local k = plan[aiSeg].pathidx - 2
      for i = 1, #path do
        path[i] = path[k+i]
      end
      for i = 1, plan.planCount do
        plan[i].pathidx = plan[i].pathidx - k
      end
      -- sync lane change indices
      currentRoute.lastLaneChangeIdx = currentRoute.lastLaneChangeIdx - k
      for _, v in ipairs(currentRoute.laneChanges) do
        v.pathIdx = v.pathIdx - k
      end
      local pathDistK = currentRoute.pathLength[k+1]
      for i = 1, #currentRoute.pathLength do
        currentRoute.pathLength[i] = currentRoute.pathLength[k+i] and currentRoute.pathLength[k+i] - pathDistK or nil
      end
      -- sync trafficState intersection search index
      if trafficStates and trafficStates.intersection and trafficStates.intersection.startIdx then
        trafficStates.intersection.startIdx = trafficStates.intersection.startIdx - k
        -- if trafficStates.intersection.startIdx < 1 then
        --   trafficStates.intersection.startIdx = nil
        -- end
      end
    end

    local targetSpeed = plan.targetSpeed

    if ai.upVec:dot(gravityDir) >= -0.2588 then -- vehicle upside down
      driveCar(0, 0, 0, 0)
      return
    end

    local lowTargetSpeedVal = 0.24
    if not plan[aiSeg+2] and ((targetSpeed < lowTargetSpeedVal and ai.speed < 0.15) or (targetPos - ai.pos):dot(ai.dirVec) < 0) then
      if M.mode == 'span' then
        local path = currentRoute.path
        for i = 1, #path - 1 do
          local key = path[i]..'\0'..path[i+1]
          -- in case we have gone over an edge that is not in the edgeDict list
          edgeDict[key] = edgeDict[key] and (edgeDict[key] * 20)
        end
      end

      driveCar(0, 0, 0, 1)
      aistatus('route done', 'route')
      guihooks.message("Route done", 5, "AI debug")
      currentRoute = nil
      return
    end

    -- come off controls when close to intermediate node with zero speed (ex. intersection), arcade autobrake takes over
    if (plan[aiSeg+1].speed == 0 and plan[aiSeg+2]) and ai.speed < 0.15 then
      driveCar(0, 0, 0, 0)
      return
    end

    if electrics.values.ignitionLevel == 3 then
      if ai.speed < 1.5 then
        driveCar(0, 0, 0, 1)
      end
      return
    end

    if not (trafficStates.intersection.action == 3 or trafficStates.intersection.action == 2) and
    not controller.isFrozen and ai.speed < 0.1 and targetSpeed > 0.5 and (lastCommand.throttle ~= 0 or lastCommand.brake ~= 0) and twt.state == 0 then
      if crash.time == 0 then
        crash.pos = ai.pos:copy()
      end
      crash.time = crash.time + dt
      if crash.time > 1 then
        local diff = ai.pos:squaredDistance(crash.pos)
        if  diff < 0.1*0.1 then
          if recover.recoverOnCrash then
            recover._recoverOnCrash = true
            crash.time = 0
          else
            crash.dir = vec3(ai.dirVec)
            crash.manoeuvre = 1
          end
        else
          crash.time = 0
        end
      end
    end

    --if not controller.isFrozen and ai.speed < 0.1 and targetSpeed > 0.5 and (lastCommand.throttle ~= 0 or lastCommand.brake ~= 0) and twt.state == 0 then
    --  crash.time = crash.time + dt
    --  if crash.time > 1 then
    --    if recover.recoverOnCrash then
    --      recover._recoverOnCrash = true
    --      crash.time = 0
    --    else
    --      crash.dir = vec3(ai.dirVec)
    --      crash.manoeuvre = 1
    --    end
    --  end
    --else
    --  crash.time = 0
    --end


    -- Throttle and Brake control
    local speedDif = targetSpeed - ai.speed
    local rate = targetSpeedDifSmoother[speedDif > 0 and targetSpeedDifSmoother.state >= 0 and speedDif >= targetSpeedDifSmoother.state]
    speedDif = targetSpeedDifSmoother:getWithRate(speedDif, dt, rate)

    local legalSpeedDif = plan.targetSpeedLegal - ai.speed
    local lowSpeedDif = min(speedDif - clamp((ai.speed - 2) * 0.5, 0, 1), legalSpeedDif) * 0.5
    local lowTargSpeedConstBrake = lowTargetSpeedVal - targetSpeed -- apply constant brake below some targetSpeed

    local throttle = clamp(lowSpeedDif, 0, 1) * sign(max(0, -lowTargSpeedConstBrake)) -- throttle not enganged for targetSpeed < 0.26

    local brakeLimLow = sign(max(0, lowTargSpeedConstBrake)) * 0.5
    local brake = clamp(-speedDif, brakeLimLow, 1) * sign(max(0, (electrics.values.smoothShiftLogicAV or 0) - 3)) -- arcade autobrake comes in at |smoothShiftLogicAV| < 5

    driveToTarget(targetPos, throttle, brake)
  end
end

local function debugDraw(focusPos)
  local debugDrawer = obj.debugDrawProxy

  if M.mode == 'script' and scriptai ~= nil then
    scriptai.debugDraw()
  end

  if currentRoute then
    local plan = currentRoute.plan
    local targetPos = plan.targetPos
    local targetSpeed = plan.targetSpeed

    if targetPos then
      debugDrawer:drawSphere(0.25, targetPos, color(255,0,0,255))

      local aiSeg = plan.aiSeg
      local shadowPos = currentRoute.plan[aiSeg].pos + plan.aiXnormOnSeg * (plan[aiSeg+1].pos - plan[aiSeg].pos)
      local blue = color(0,0,255,255)
      debugDrawer:drawSphere(0.25, shadowPos, blue)

      for vehId in pairs(mapmgr.getObjects()) do
        if vehId ~= objectId then
          debugDrawer:drawSphere(0.25, obj:getObjectFrontPosition(vehId), blue)
        end
      end

      if player then
        debugDrawer:drawSphere(0.3, player.pos, color(0,255,0,255))
      end
    end

    if M.debugMode == 'target' then
      if mapData and mapData.graph and currentRoute.path then
        local p = mapData.positions[currentRoute.path[#currentRoute.path]]
        debugDrawer:drawSphere(4, p, color(255,0,0,100))
        debugDrawer:drawText(p + vec3(0, 0, 4), color(0,0,0,255), 'Destination')
      end

    elseif M.debugMode == 'route' then
      local maxCount = 700
      local last = routeRec.last
      local count = min(#routeRec, maxCount)
      if count == 0 or routeRec[last]:squaredDistance(ai.pos) > (7 * 7) then
        last = 1 + last % maxCount
        routeRec[last] = vec3(ai.pos)
        count = min(count+1, maxCount)
        routeRec.last = last
      end

      local tmpVec = vec3(0.7, ai.width, 0.7)
      local black = color(0, 0, 0, 128)
      for i = 1, count-1 do
        debugDrawer:drawSquarePrism(routeRec[1+(last+i-1)%count], routeRec[1+(last+i)%count], tmpVec, tmpVec, black)
      end

      if currentRoute.plan[1].pathidx then
        local positions = mapData.positions
        local path = currentRoute.path
        tmpVec:setAdd(vec3(0, ai.width, 0))
        local transparentRed = color(255, 0, 0, 120)
        for i = currentRoute.plan[1].pathidx, #path - 1 do
          debugDrawer:drawSquarePrism(positions[path[i]], positions[path[i+1]], tmpVec, tmpVec, transparentRed)
        end
      end

      -- Draw candidate paths if available
      if candidatePaths and candidatePaths[1] then
        local winner = candidatePaths.winner
        local source = candidatePaths[1][1] -- all paths have the same source node
        debugDrawer:drawSphere(2, mapData.positions[source], color(0, 0, 0, 255))
        for i = 1, #candidatePaths do
          local thisPath = candidatePaths[i]
          local thisPathCount = #thisPath
          local thisScore = candidatePaths[i].score
          for i = 1, thisPathCount-1 do
            debugDrawer:drawCylinder(mapData.positions[thisPath[i]], mapData.positions[thisPath[i+1]], 0.5, jetColor(thisScore, 200))
          end
          local thisPathLastNode = thisPath[thisPathCount]
          debugDrawer:drawSphere(4, mapData.positions[thisPathLastNode], jetColor(thisScore, 255))
          if thisPathLastNode == winner then
            debugDrawer:drawCylinder(mapData.positions[thisPathLastNode], mapData.positions[thisPathLastNode] + vec3(0, 0, 8), 2, color(0, 0, 0, 255))
          end
          local txt = thisPathLastNode.." -> "..strFormat("%0.4f", thisScore)
          debugDrawer:drawText(mapData.positions[thisPathLastNode] + vec3(0, 0, 2), color(0, 0, 0, 255), txt)
        end
      else
        -- Mark destination node in current path
        if currentRoute.path then
          local p = mapData.positions[currentRoute.path[#currentRoute.path]]
          debugDrawer:drawSphere(4, p, color(255, 0, 0, 100))
          debugDrawer:drawText(p + vec3(0, 0, 4), color(0, 0, 0, 255), 'Destination')
        end
      end

    elseif M.debugMode == 'speeds' then
      -- Debug Throttle brake application
      local maxCount = 175
      local count = min(#trajecRec, maxCount)
      local last = trajecRec.last
      if count == 0 or trajecRec[last][1]:squaredDistance(ai.pos) > (0.2 * 0.2) then
        last = 1 + last % maxCount
        trajecRec[last] = {vec3(ai.pos), ai.speed, targetSpeed, lastCommand.brake, lastCommand.throttle}
        count = min(count+1, maxCount)
        trajecRec.last = last
      end

      local tmpVec1 = vec3(0.7, ai.width, 0.7)
      for i = 1, count-1 do
        local n = trajecRec[1 + (last + i) % count]
        debugDrawer:drawSquarePrism(trajecRec[1 + (last + i - 1) % count][1], n[1], tmpVec1, tmpVec1, color(255 * sqrt(abs(n[4])), 255 * sqrt(n[5]), 0, 100))
      end

      local prevEntry
      local zOffSet = vec3(0, 0, 0.4)
      local yellow, blue = color(255,255,0,200), color(0,0,255,200)
      local tmpVec2 = vec3()
      for i = 1, count-1 do
        local v = trajecRec[1 + (last + i - 1) % count]
        if prevEntry then
          -- actuall speed
          tmpVec1:set(0, 0, prevEntry[2] * 0.2)
          tmpVec2:set(0, 0, v[2] * 0.2)
          debugDrawer:drawCylinder(prevEntry[1] + tmpVec1, v[1] + tmpVec2, 0.02, yellow)

          -- target speed
          tmpVec1:set(0, 0, prevEntry[3] * 0.2)
          tmpVec2:set(0, 0, v[3] * 0.2)
          debugDrawer:drawCylinder(prevEntry[1] + tmpVec1, v[1] + tmpVec2, 0.02, blue)
        end

        tmpVec1:set(0, 0, v[3] * 0.2)
        debugDrawer:drawCylinder(v[1], v[1] + tmpVec1, 0.01, blue)

        if focusPos:squaredDistance(v[1]) < labelRenderDistance * labelRenderDistance then
          tmpVec1:set(0, 0, v[2] * 0.2)
          debugDrawer:drawText(v[1] + tmpVec1 + zOffSet, yellow, strFormat("%2.0f", v[2]*3.6).." kph")

          tmpVec1:set(0, 0, v[3] * 0.2)
          debugDrawer:drawText(v[1] + tmpVec1 + zOffSet, blue, strFormat("%2.0f", v[3]*3.6).." kph")
        end
        prevEntry = v
      end

      -- Planned speeds
      if plan[1] then
        local red = color(255,0,0,200) -- getContrastColor(objectId)
        local black = color(0, 0, 0, 255)
        local green = color(0, 255, 0, 200)
        local prevSpeed = -1
        local prevLegalSpeed = -1
        local prevPoint = plan[1].pos
        local prevPoint_ = plan[1].pos
        local tmpVec = vec3()
        for i = 1, #plan do
          local n = plan[i]

          local speed = (n.speed >= 0 and n.speed) or prevSpeed
          tmpVec:set(0, 0, speed * 0.2)
          local p1 = n.pos + tmpVec
          debugDrawer:drawCylinder(n.pos, p1, 0.03, red)
          debugDrawer:drawCylinder(prevPoint, p1, 0.05, red)
          debugDrawer:drawText(p1, black, strFormat("%2.0f", speed*3.6).." kph")
          prevSpeed = speed
          prevPoint = p1

          if M.speedMode == 'legal' then
            local legalSpeed = (n.legalSpeed >= 0 and n.legalSpeed) or prevLegalSpeed
            tmpVec:set(0, 0, legalSpeed * 0.2)
            local p1_ = n.pos + tmpVec
            debugDrawer:drawCylinder(n.pos, p1_, 0.03, green)
            debugDrawer:drawCylinder(prevPoint_, p1_, 0.05, green)
            debugDrawer:drawText(p1_, black, strFormat("%2.0f", legalSpeed*3.6).." kph")
            prevLegalSpeed = legalSpeed
            prevPoint_ = p1_
          end

          --[[
          if traffic and traffic[i] then
            for _, data in ipairs(traffic[i]) do
              local plPosOnPlan = linePointFromXnorm(n.pos, plan[i+1].pos, data[2])
              debugDrawer:drawSphere(0.25, plPosOnPlan, color(0,255,0,100))
            end
          end
          --]]
        end

        ---[[ Debug road width and lane limits
        local prevPointOrig = plan[1].posOrig
        local tmpVec = vec3(1, 1, 1)
        local tmpVec1 = vec3(0.5, 0.5, 0.5)
        --if filtered then
        --  local pFp = pathFplan(plan, currentRoute.path, distAhead)
        --  for i = 1, #pFp do
        --    local n = pFp[i]
        --    local roadHalfWidth = n.radiusOrig * n.chordLength
        --    local rangeLeft = linearScale(0*n.rangeLeft, 0, 1, -roadHalfWidth, roadHalfWidth)
        --    local rangeRight = linearScale(1*n.rangeRight, 0, 1, -roadHalfWidth, roadHalfWidth)
        --    debugDrawer:drawSquarePrism(n.posOrig - roadHalfWidth * n.normal, n.posOrig + roadHalfWidth * n.normal, tmpVec1*2, tmpVec1*2, color(255,0,255,120))
        --    --debugDrawer:drawSphere(2, n.posOrig, color(255,0,255,120))
        --  end
        --end
        for i = 1, #plan do
          local n = plan[i]
          local p1Orig = n.posOrig - n.biNormal
          debugDrawer:drawCylinder(n.posOrig, p1Orig, 0.03, black)
          debugDrawer:drawCylinder(p1Orig, p1Orig + n.normal, 0.03, black)
          debugDrawer:drawCylinder(prevPointOrig, p1Orig, 0.03, black)
          local roadHalfWidth = n.radiusOrig * n.chordLength
          --debugDrawer:drawCylinder(n.posOrig, p1Orig, roadHalfWidth, color(255, 0, 0, 40))
          if n.laneLimLeft and n.laneLimRight then -- You need to uncomment the appropriate code in planAhead force integrator loop for this to work
            debugDrawer:drawSquarePrism(n.pos - (n.lateralXnorm - n.laneLimLeft) * n.normal, n.pos + (n.laneLimRight - n.lateralXnorm) * n.normal, tmpVec, tmpVec, color(0,0,255,120))
          end
          if n.rangeLeft and n.rangeRight then
            local rangeLeft = linearScale(n.rangeLeft, 0, 1, -roadHalfWidth, roadHalfWidth)
            local rangeRight = linearScale(n.rangeRight, 0, 1, -roadHalfWidth, roadHalfWidth)
            debugDrawer:drawSquarePrism(n.posOrig + rangeLeft * n.normal, n.posOrig + rangeRight * n.normal, tmpVec1, tmpVec1, color(255,0,0,120))
          end
          prevPointOrig = p1Orig
        end
        --]]

        --[[ Debug lane change. You need to uncomment upvalue newPositionsDebug for this to work
        if newPositionsDebug[1] then
          local green = color(0,255,0,200)
          local prevPoint = newPositionsDebug[1]
          for i = 1, #newPositionsDebug do
            local pos = newPositionsDebug[i]
            local p1 = pos + vec3(0, 0, 2)
            debugDrawer:drawCylinder(pos, p1, 0.03, green)
            debugDrawer:drawCylinder(prevPoint, p1, 0.05, green)
            prevPoint = p1
          end
        end
        --]]

        for i = max(1, plan[1].pathidx-2), #currentRoute.path-2 do
          local wp1 = currentRoute.path[i]
          local wp2 = currentRoute.path[i+1]
          if tableSize(mapData.graph[wp2]) > 2 then
            local minNode = roadNaturalContinuation(wp1, wp2)
            if minNode and minNode ~= currentRoute.path[i+2] then
              debugDrawer:drawCylinder(mapData.positions[wp2], mapData.positions[minNode], 0.2, black)
            end
          end
        end
      end

      -- Player segment visual debug for chase / follow mode
      -- if chaseData.playerRoad then
      --   local col1, col2
      --   if internalState == 'tail' then
      --     col1 = color(0,0,0,200)
      --     col2 = color(0,0,0,200)
      --   else
      --     col1 = color(255,0,0,100)
      --     col2 = color(0,0,255,100)
      --   end
      --   local plwp1 = chaseData.playerRoad[1]
      --   debugDrawer:drawSphere(2, mapData.positions[plwp1], col1)
      --   local plwp2 = chaseData.playerRoad[2]
      --   debugDrawer:drawSphere(2, mapData.positions[plwp2], col2)
      -- end

    elseif M.debugMode == 'trajectory' then
      -- Debug Curvatures
      -- local plan = currentRoute.plan
      -- if plan ~= nil then
      --   local prevPoint = plan[1].pos
      --   for i = 1, #plan do
      --     local p = plan[i].pos
      --     local v = plan[i].curvature or 1e-10
      --     local scaledV = abs(1000 * v)
      --     debugDrawer:drawCylinder(p, p + vec3(0, 0, scaledV), 0.06, color(abs(min(sign(v),0))*255,max(sign(v),0)*255,0,200))
      --     debugDrawer:drawText(p + vec3(0, 0, scaledV), color(0,0,0,255), strFormat("%5.4e", v))
      --     debugDrawer:drawCylinder(prevPoint, p + vec3(0, 0, scaledV), 0.06, col)
      --     prevPoint = p + vec3(0, 0, scaledV)
      --   end
      -- end

      -- Debug Planned Speeds
      if plan[1] then
        local col = getContrastColor(objectId)
        local prevPoint = plan[1].pos
        local prevSpeed = -1
        local drawLen = 0
        for i = 1, #plan do
          local n = plan[i]
          local p = n.pos
          local v = (n.speed >= 0 and n.speed) or prevSpeed
          local p1 = p + vec3(0, 0, v*0.2)
          --debugDrawer:drawLine(p + vec3(0, 0, v*0.2), (n.pos + n.turnDir) + vec3(0, 0, v*0.2), col)
          debugDrawer:drawCylinder(p, p1, 0.03, col)
          debugDrawer:drawCylinder(prevPoint, p1, 0.05, col)
          debugDrawer:drawText(p1, color(0,0,0,255), strFormat("%2.0f", v*3.6) .. " kph")
          prevPoint = p1
          prevSpeed = v
          drawLen = drawLen + n.vec:length()
          if drawLen > 80 then break end
        end
      end

      -- Debug Throttle brake application
      local maxCount = 175
      local count = min(#trajecRec, maxCount)
      local last = trajecRec.last
      if count == 0 or trajecRec[last][1]:squaredDistance(ai.pos) > (0.25 * 0.25) then
        last = 1 + last % maxCount
        trajecRec[last] = {vec3(ai.pos), lastCommand.throttle, lastCommand.brake}
        count = min(count+1, maxCount)
        trajecRec.last = last
      end

      local tmpVec = vec3(0.7, ai.width, 0.7)
      for i = 1, count-1 do
        local n = trajecRec[1+(last+i)%count]
        debugDrawer:drawSquarePrism(trajecRec[1+(last+i-1)%count][1], n[1], tmpVec, tmpVec, color(255 * sqrt(abs(n[3])), 255 * sqrt(n[2]), 0, 100))
      end
    elseif false and M.debugMode == 'rays' then
      local aiScanLength = ai.length * 0.9 --small adjustments for origins to be a bit inside the car
      local aiScanWidth = ai.width * 0.7
      local shiftHorizontalVec = (aiScanWidth * 0.5) * ai.rightVec --creation of horizontal helper vector
      local shiftVerticalVec = -0.05 * ai.length * ai.dirVec --creation of vertical helper vector
      local shiftPerpendicularVec = 0.35 * ai.upVec
      local aiPosElevatedR = ai.pos:copy() --creation of FR corner vector
      aiPosElevatedR:setAdd(shiftHorizontalVec)
      aiPosElevatedR:setAdd(shiftVerticalVec)
      aiPosElevatedR:setAdd(shiftPerpendicularVec) -- elevation, this should work only on flat inclination for now
      local aiPosElevatedL = aiPosElevatedR:copy() --creation of FL corner vector
      shiftHorizontalVec:setScaled(-2)
      aiPosElevatedL:setAdd(shiftHorizontalVec)
      local aiPosBackElevatedL = aiPosElevatedL:copy() --creation of BR corner vector
      shiftVerticalVec:setScaled(aiScanLength * 20/ai.length)
      aiPosBackElevatedL:setAdd(shiftVerticalVec)
      local aiPosBackElevatedR = aiPosElevatedR:copy() --creation of BL corner vector
      aiPosBackElevatedR:setAdd(shiftVerticalVec)

      local rayDist = 4 * ai.wheelBase -- TODO: Optimize rayDist. Higher is better for more open spaces but w performance hit
      populateOBBinRange(rayDist)
      local tmpVec = vec3()
      local helperVec = vec3()
      local rounds = twt.idx - 1
      dump("rounds in debug", rounds)

      for i = twt.idx, rounds do --the ray cast loop: each iteration scans one corner and one side
        i = i % 8 + 1
        local j = i * 4
        tmpVec:setLerp(twt.posTable[twt.RRT[j-3]], twt.posTable[twt.RRT[j-2]], twt.blueNoiseCoef)
        helperVec:setLerp(twt.dirTable[twt.RRT[j-1]], twt.dirTable[twt.RRT[j]], twt.blueNoiseCoef) -- LERP corner direction
        helperVec:normalize()
        local rayLen = castRay(tmpVec, helperVec, min(twt.rayMins[i], rayDist))

        local shiftVec = helperVec * rayLen
        local rayHitPos = tmpVec + shiftVec
        debugDrawer:drawCylinder(tmpVec, rayHitPos, 0.02, color(255,255,255,255))

        if twt.rayMins[i] > rayLen then -- odd index is corners
          twt.minRayCoefs[i] = twt.blueNoiseCoef
          twt.rayMins[i] = rayLen
        else
          tmpVec:setLerp(twt.posTable[twt.RRT[j-3]], twt.posTable[twt.RRT[j-2]], twt.minRayCoefs[i])
          helperVec:setLerp(twt.dirTable[twt.RRT[j-1]], twt.dirTable[twt.RRT[j]], twt.minRayCoefs[i]) -- LERP corner direction
          helperVec:normalize()
          twt.rayMins[i] = castRay(tmpVec, helperVec, min(2 * twt.rayMins[i], rayDist))
        end
      end

      -- debugDrawer:drawSphere(0.3, ai.pos, color(255,255,0,255))
      -- dump(obj)
      -- local test = obj:getCornerPosition(0)
      -- local test2 = obj:getCornerPosition(1)
      -- local test3 = obj:getCornerPosition(2)
      -- local test4 = obj:getCornerPosition(3)
      -- local frontPos = obj:getFrontPosition()

      -- dump(test)
      -- debugDrawer:drawSphere(0.1, frontPos, color(255,255,0,255))
      -- debugDrawer:drawSphere(0.3, test2, color(255,0,0,255))
      -- debugDrawer:drawSphere(0.3, test3, color(255,0,0,255))
      -- debugDrawer:drawSphere(0.3, test4, color(255,0,0,255))
      -- debugDrawer:drawSphere(0.3, test, color(255,0,0,255))
      -- local test2 = obj:getFrontPositionRelative()
      -- dump(test2)
      -- debugDrawer:drawSphere(0.3, ai.wheelBase[2], color(255,255,0,255))
      -- ray origins
      -- debugDrawer:drawSphere(0.1, ai.pos, color(0,0,0,255))
      debugDrawer:drawSphere(0.1, twt.posTable[1], color(255,255,255,255))
      debugDrawer:drawSphere(0.1, twt.posTable[2], color(255,255,255,255))
      debugDrawer:drawSphere(0.1, twt.posTable[3], color(255,255,255,255))
      debugDrawer:drawSphere(0.1, twt.posTable[4], color(255,255,255,255))

      for _, d in pairs(debugSpots) do
        debugDrawer:drawSphere(0.2, d[1], d[2])
      end
    end
  end

  if false then
    local c, x, y, z = getObjectBoundingBox(objectId) -- center, front vec, left vec, up vec
    local col = color(255, 0, 0, 255)
    drawOBB(c, x, y, z, col)
  end

  --[[
  if true then
    -- Draw vehicle ref node, wheel hub positions and wheel contact points (estimates) with ground
    local refNodePos = obj:getPosition()
    debugDrawer:drawSphere(0.1, refNodePos, color(255,0,0,255))
    for _, wheel in pairs(wheels.wheels) do
      local wheelRadius = wheel.radius
      local wheelPosAbsolute = refNodePos + obj:getNodePosition(wheel.node1)
      debugDrawer:drawSphere(0.1, wheelPosAbsolute, color(255,0,0,255))
      local contactPointPos = wheelPosAbsolute - obj:getDirectionVectorUp() * wheelRadius
      debugDrawer:drawSphere(0.1, contactPointPos, color(255,0,0,255))
    end

    -- vehicle frontPos
    local vehFrontPos = obj:getFrontPosition()
    debugDrawer:drawSphere(0.1, obj:getFrontPosition(), color(255, 255, 255, 255))
    -- vehicle frontPos
    debugDrawer:drawSphere(0.1, vehFrontPos:z0(), color(0, 255, 255, 255))

    -- calculated spawn pos (from script front pos)
    debugDrawer:drawSphere(0.1, vec3(736.8858419,102.6078886,0.1169999319), color(0, 0, 255, 255))

    -- script first pos (ground truth)
    debugDrawer:drawSphere(0.1, vec3(734.9434413112983, 102.21897064457461, 1.0), color(255, 0, 255, 255))

    -- Draw world reference Frame
    debugDrawer:drawSphere(0.1, vec3(0, 0, 0), color(0, 255, 0, 255)) -- World 0
    debugDrawer:drawCylinder(vec3(0, 0, 0), 5 * vec3(1, 0, 0), 0.05, color(0, 255, 0, 255)) -- x (green)
    debugDrawer:drawCylinder(vec3(0, 0, 0), 5 * vec3(0, 1, 0), 0.05, color(255, 0, 0, 255)) -- y (red)
    debugDrawer:drawCylinder(vec3(0, 0, 0), 5 * vec3(0, 0, 1), 0.05, color(0, 0, 255, 255)) -- z (blue)
  end
  --]]
end

local function setAvoidCars(v)
  M.extAvoidCars = v
  if M.extAvoidCars == 'off' or M.extAvoidCars == 'on' then
    avoidCars = M.extAvoidCars
  else
    avoidCars = M.mode == 'manual' and 'off' or 'on'
  end
  stateChanged()
end

local function driveInLane(v)
  if v == 'on' then
    M.driveInLaneFlag = 'on'
    driveInLaneFlag = true
  else
    M.driveInLaneFlag = 'off'
    driveInLaneFlag = false
  end
  stateChanged()
end

local function setMode(mode)
  if tableSizeC(wheels.wheels) == 0 then return end
  if mode ~= nil then
    if M.mode ~= mode then -- new AI mode is not the same as the old one
      obj:queueGameEngineLua('onAiModeChange('..objectId..', "'..mode..'")')
    end
    M.mode = mode
  end

  if M.extAvoidCars == 'off' or M.extAvoidCars == 'on' then
    avoidCars = M.extAvoidCars
  else
    avoidCars = (M.mode == 'manual' and 'off' or 'on')
  end

  if M.mode ~= 'script' then
    if M.mode ~= 'disabled' and M.mode ~= 'stop' then
      resetMapAndRoute()

      mapmgr.requestMap()
      M.updateGFX = updateGFX
      targetSpeedDifSmoother = newTemporalSmoothingNonLinear(1e300, 4, vec3(obj:getSmoothRefVelocityXYZ()):length())

      if controller.mainController then
        if electrics.values.gearboxMode == 'realistic' then
          restoreGearboxMode = true
        end
        controller.mainController.setGearboxMode('arcade')
      end

      ai.wheelBase = calculateWheelBase()

      if M.mode == 'flee' or M.mode == 'chase' or M.mode == 'follow' then
        setAggressionMode('rubberBand')
      end

      if M.mode == 'traffic' then
        setSpeedMode('legal')
        driveInLane('on')
        setTractionModel(1)
        setSpeedProfileMode('Back')
        obj:setSelfCollisionMode(2)
        obj:setAerodynamicsMode(2)
      else
        setTractionModel(2)
        obj:setSelfCollisionMode(1)
        obj:setAerodynamicsMode(1)
      end
    end

    if M.mode == 'disabled' then
      driveCar(0, 0, 0, 0)
      M.updateGFX = nop
      currentRoute = nil
      if controller.mainController and restoreGearboxMode then
        controller.mainController.setGearboxMode('realistic')
      end
    end

    stateChanged()
    sounds.updateObjType()
  end

  trajecRec = {last = 0}
  routeRec = {last = 0}
end

local function setRecoverOnCrash(val)
  recover.recoverOnCrash = val
end

local function toggleTrafficMode()
  if M.mode == "traffic" then
    setMode("disabled")
    setRecoverOnCrash(false)
  else
    setMode("traffic")
    setRecoverOnCrash(true)
  end
end

local function reset() -- called when the user pressed I
  M.manualTargetName = nil
  resetInternalStates()

  throttleSmoother:set(0)
  smoothTcs:set(1)

  if M.mode ~= 'disabled' then
    driveCar(0, 0, 0, 0)
    setMode() -- some scenarios don't work if this is changed to setMode('disabled')
  end
  stateChanged()
end

local function resetLearning()
end

local function setVehicleDebugMode(newMode)
  tableMerge(M, newMode)
  if M.debugMode ~= 'trajectory' then
    trajecRec = {last = 0}
  end
  if M.debugMode ~= 'route' then
    routeRec = {last = 0}
  end
  if M.debugMode ~= 'speeds' then
    trajecRec = {last = 0}
  end
  if M.debugMode ~= 'rays' then
    trajecRec = {last = 0}
  end
  if M.debugMode ~= 'off' then
    M.debugDraw = debugDraw
  else
    M.debugDraw = nop
  end
end

local function setState(newState)
  if tableSizeC(wheels.wheels) == 0 then return end

  if newState.mode and newState.mode ~= M.mode then -- new AI mode is not the same as the old one
    obj:queueGameEngineLua('onAiModeChange('..objectId..', "'..newState.mode..'")')
  end

  local mode = M.mode
  tableMerge(M, newState)
  setAggressionExternal(M.extAggression)

  -- after a reload (cntr-R) vehicle should be left with handbrake engaged if ai is disabled
  -- preserve initial state of vehicle controls (handbrake engaged) if current mode and new mode are both 'disabled'
  if not (mode == 'disabled' and M.mode == 'disabled') then
    setMode()
  end

  setVehicleDebugMode(M)
  setTargetObjectID(M.targetObjectID)
  stateChanged()
end

local function setTarget(wp)
  M.manualTargetName = wp
  validateInput = validateUserInput
  wpList = {wp}
end

local function setPath(path)
  manualPath = path
  validateInput = validateUserInput
end


-- IMPORTANT - CUSTOM PART
-- Default safety distance multiplier
local function setSafetyDistance(v)
  if type(v) == "number" and v >= 0 then
    M.safetyDistance = v
    -- print("Safety distance set to: " .. v)
  else
    print("Invalid safety distance. Please provide a number >= 0.")
  end
  stateChanged()
end

-- Default lateral offset range (40% of track width)
local function setLateralOffsetRange(v)
  if type(v) == "number" and v >= 0 and v <= 1 then
    M.lateralOffsetRange = v
    -- print("Lateral offset range set to: " .. v)
  else
    print("Invalid lateral offset range. Please provide a number between 0 and 1.")
  end
  stateChanged()
end

-- Default lateral offset scale for overtaking (30% of track width)
local function setLateralOffsetScale(v)
  if type(v) == "number" and v >= 0 and v <= 1 then
    M.lateralOffsetScale = v
    -- print("Lateral offset scale set to: " .. v)
  else
    print("Invalid lateral offset scale. Please provide a number between 0 and 1.")
  end
  stateChanged()
end

-- Bias towards the shortest path (0 = no bias, 1 = always shortest path)
local function setShortestPathBias(v)
  if type(v) == "number" and v >= 0 and v <= 1 then
    M.shortestPathBias = v
    -- print("Shortest path bias set to: " .. v)
  else
    print("Invalid shortest path bias. Please provide a number between 0 and 1.")
  end
  stateChanged()
end

local function shouldAbortOvertake(vehicle, targetPos)
  -- Original check
  local basicCheck = vehicle.pos:distance(targetPos) < (ai.speed * 0.8)
  
  -- New: Dynamic time-to-collision calculation
  local relativeVel = vehicle.vel - ai.vel
  local closingSpeed = relativeVel:dot((vehicle.pos - ai.pos):normalized())
  local ttc = ai.pos:distance(vehicle.pos) / math.max(math.abs(closingSpeed), 1e-5)
  
  -- Combine checks with priority on TTC
  return ttc < 2.5 or basicCheck  -- Abort if collision within 2.5 seconds
end

-- Add to state table
local overtakeCommitment = {
  targetVehicle = nil,
  startTime = 0,
  originalSpeed = nil,
  laneOffset = 0
}

function beginOvertake(vehicle)
  overtakeCommitment.targetVehicle = vehicle
  overtakeCommitment.startTime = os.clock()
  overtakeCommitment.laneOffset = math.random(-1, 1) * M.lateralOffsetRange * M.lateralOffsetScale
end

function shouldContinueOvertake()
  if os.clock() - overtakeCommitment.startTime > 4.0 then  -- Max 4 second commitment
      return false
  end
  return overtakeCommitment.targetVehicle ~= nil
end

-- setting default values
M.safetyDistance = 0.5         -- Baseline following distance
M.lateralOffsetRange = 0.4     -- Max % of track width available for movement
M.lateralOffsetScale = 0.3     -- % of available range to use for overtaking
M.shortestPathBias = 0.7       -- Default path adherence

local function racingBehavior(route, baseRoute)
  if avoidCars ~= 'on' then
      print("Racing behavior inactive: avoidCars not enabled")
      return
  end

  -- Validate required parameters
  if not route or not route.plan or #route.plan < 2 then
      print("Invalid route plan for racing behavior")
      return
  end

  -- Get current racing parameters from shared state
  local safetyDistance = M.safetyDistance or 0.5
  local lateralOffsetRange = M.lateralOffsetRange or 0.4
  local lateralOffsetScale = M.lateralOffsetScale or 0.3
  local shortestPathBias = M.shortestPathBias or 0.7
  local aggression = M.aggression or 0.3

  -- Initialize plan if needed
  if not route.plan then
      route.plan = {}
      print("Initialized empty racing plan")
  end

  local plan = route.plan
  local aiSpeed = ai.speed or 0
  local currentTime = os.clock()

  -- Overtake commitment management
  if overtakeCommitment.targetVehicle then
      -- Check overtake completion or timeout
      local timeElapsed = currentTime - overtakeCommitment.startTime
      local vehicleDist = overtakeCommitment.targetVehicle.pos:distance(ai.pos)
      
      -- Calculate relative position
      local dirToVehicle = overtakeCommitment.targetVehicle.pos - ai.pos
      local isAhead = dirToVehicle:dot(ai.dirVec) > 0

      if timeElapsed > 4.0 or vehicleDist > 15 or not isAhead then
          -- End commitment
          if overtakeCommitment.originalSpeed then
              ai.setRouteSpeed(overtakeCommitment.originalSpeed)
          end
          overtakeCommitment.targetVehicle = nil
          print("Overtake completed or aborted")
      else
          -- Maintain boost
          ai.setRouteSpeed(overtakeCommitment.originalSpeed * 1.25)
      end
  end

  -- Enhanced overtaking logic
  for i = 1, #plan - 1 do
      local currentNode = plan[i]

      -- Calculate track width
      local trackWidth = (currentNode.radiusOrig or 1.5) * (currentNode.chordLength or 3.0) * 2

      -- Process traffic
      for _, vehicle in ipairs(trafficTable) do
          -- Calculate relative metrics
          local vehicleSpeed = vehicle.vel and vehicle.vel:length() or 0
          local relativeSpeed = aiSpeed - vehicleSpeed
          local dirToVehicle = vehicle.pos - currentNode.pos
          local distanceToVehicle = vehicle.pos:distance(currentNode.pos)
          local alignment = dirToVehicle:normalized():dot(currentNode.dirVec or dirToVehicle:normalized())

          -- Overtaking conditions
          if not overtakeCommitment.targetVehicle and 
             relativeSpeed > 2.5 and 
             alignment > 0.8 and 
             distanceToVehicle < 15 then

              print(string.format("Initiating overtake @ %.1fm (Δspeed: %.1f)", 
                  distanceToVehicle, relativeSpeed))

              -- Store original speed
              overtakeCommitment.originalSpeed = ai.routeSpeed or aiSpeed
              
              -- Calculate lateral offset
              local side = math.random() > 0.5 and 1 or -1
              local maxAllowedOffset = trackWidth * lateralOffsetRange
              local appliedOffset = maxAllowedOffset * lateralOffsetScale * side

              -- Apply persistent offset
              overtakeCommitment.laneOffset = appliedOffset
              overtakeCommitment.targetVehicle = vehicle
              overtakeCommitment.startTime = currentTime

              -- Apply initial speed boost
              local speedBoost = 1.0 + (aggression * 0.4)
              ai.setRouteSpeed(aiSpeed * speedBoost)
          end

          -- Apply lane offset during commitment
          if overtakeCommitment.targetVehicle and vehicle == overtakeCommitment.targetVehicle then
              currentNode.lateralXnorm = clamp(
                  (currentNode.lateralXnorm or 0) + overtakeCommitment.laneOffset,
                  -trackWidth,
                  trackWidth
              )
              
              -- Add progressive speed boost
              local progress = (currentTime - overtakeCommitment.startTime) / 4.0
              local dynamicBoost = 1.0 + (aggression * 0.4 * (1 - progress))
              ai.setRouteSpeed(overtakeCommitment.originalSpeed * dynamicBoost)
          end
      end
  end

  -- Collision safety check
  if overtakeCommitment.targetVehicle then
      local closingSpeed = (overtakeCommitment.targetVehicle.vel - ai.vel):dot(ai.dirVec)
      local ttc = ai.pos:distance(overtakeCommitment.targetVehicle.pos) / math.max(math.abs(closingSpeed), 1e-5)
      
      if ttc < 1.5 then  -- Abort if collision within 1.5 seconds
          print("Aborting overtake due to imminent collision")
          ai.setRouteSpeed(overtakeCommitment.originalSpeed)
          overtakeCommitment.targetVehicle = nil
      end
  end
end

-- IMPORTANT - END OF CUSTOM PART

local function driveUsingPath(arg)
  --[[
  Drives AI vehicles using specified pathfinding parameters. At least one path definition argument must be provided.

  === Core Path Definitions (Choose One) ===
  * path:         (table) Predefined sequence of waypoint names to follow in exact order
                  Example: path = {'wp1', 'wp2', 'wp3'}

  * wpTargetList: (table) Successive waypoints with automatic pathfinding between them
                  Example: wpTargetList = {'start', 'finish'}

  * script:       (table) Direct position-based path with custom coordinates
                  Example: script = {{x=10,y=20,z=0}, {x=15,y=25,z=0,v=12}}

  === Speed Control Parameters ===
  * wpSpeeds:     (table) Waypoint-specific speed targets (m/s) override other speed settings
                  Example: wpSpeeds = {wp1=15, wp2=25}

  * routeSpeed:   (number) Base speed for entire route (requires routeSpeedMode)
  * routeSpeedMode: (string) Speed enforcement strategy:
                  - 'limit': Don't exceed routeSpeed
                  - 'set': Maintain exact routeSpeed

  === Racing/Overtaking Parameters ===
  * raceMode:     (string) 'on' enables competitive racing behavior (default: 'off')
  * aggression:   (number 0.3-1) Driver assertiveness (0.3=normal, 1=max performance)
  * safetyDistance: (number 0-1) Following distance (0=close, 1=conservative) Default: 0.5

  * lateralOffsetRange: (number 0-1) Maximum lateral movement allowance as % of track width
                      Default: 0.4 (40% of track width available)
  * lateralOffsetScale: (number 0-1) Aggressiveness of lateral movement usage 
                      Default: 0.3 (uses 30% of available offset range)
                      Combined Effect: Actual offset = trackWidth × Range × Scale

  * shortestPathBias: (number 0-1) Pathfinding preference (0=explore alternatives, 1=strict shortest path)
                    Default: 0.7

  === Traffic Management ===
  * avoidCars:    (string) 'on' enables collision avoidance (default: 'off')
  * driveInLane:  (string) 'on' enforces legal lane discipline (default: 'off')

  === Advanced Controls ===
  * noOfLaps:     (number) Repeat path iterations for closed circuits

  === Example Configurations ===
  -- Basic racing setup with overtaking:
  ai.driveUsingPath{
    wpTargetList = {'start', 'lap_marker'},
    raceMode = 'on',
    avoidCars = 'on',
    routeSpeed = 45,
    routeSpeedMode = 'limit',
    aggression = 0.7,
    safetyDistance = 0.3,
    lateralOffsetRange = 0.6,  -- 60% of track width available
    lateralOffsetScale = 0.8,  -- Use 80% of available width
    shortestPathBias = 0.4,
    noOfLaps = 3
  }

  -- Scripted path with waypoint speeds:
  ai.driveUsingPath{
    script = {
      {x=10, y=20, z=0, v=15},
      {x=30, y=40, z=0, v=25}
    },
    driveInLane = 'on',
    routeSpeedMode = 'set'
  }

  -- Urban driving with collision prevention:
  ai.driveUsingPath{
    path = {'market_street', 'central_park', 'downtown'},
    driveInLane = 'on',
    avoidCars = 'on',
    routeSpeed = 25,
    aggression = 0.4,
    safetyDistance = 0.7
  }
  --]]

  -- Validate input arguments
  if (arg.wpTargetList == nil and arg.path == nil and arg.script == nil) or
    (type(arg.wpTargetList) ~= 'table' and type(arg.path) ~= 'table' and type(arg.script) ~= 'table') or
    (arg.wpSpeeds ~= nil and type(arg.wpSpeeds) ~= 'table') or
    (arg.noOfLaps ~= nil and type(arg.noOfLaps) ~= 'number') or
    (arg.routeSpeed ~= nil and type(arg.routeSpeed) ~= 'number') or
    (arg.routeSpeedMode ~= nil and type(arg.routeSpeedMode) ~= 'string') or
    (arg.driveInLane ~= nil and type(arg.driveInLane) ~= 'string') or
    (arg.aggression ~= nil and type(arg.aggression) ~= 'number') or
    (arg.raceMode ~= nil and type(arg.raceMode) ~= 'string') or
    (arg.safetyDistance ~= nil and type(arg.safetyDistance) ~= 'number') or
    (arg.lateralOffsetRange ~= nil and type(arg.lateralOffsetRange) ~= 'number') or
    (arg.lateralOffsetScale ~= nil and type(arg.lateralOffsetScale) ~= 'number') or
    (arg.shortestPathBias ~= nil and type(arg.shortestPathBias) ~= 'number')
  then
    return
  end

  -- Update parameters in the M table
  M.raceMode = arg.raceMode or 'off'  -- Default to 'off' only if not provided
  M.safetyDistance = arg.safetyDistance or 0.5
  M.lateralOffsetRange = arg.lateralOffsetRange or 0.4
  M.lateralOffsetScale = arg.lateralOffsetScale or 0.3
  M.shortestPathBias = arg.shortestPathBias or 0.7

  -- Debug statement for raceMode
  if arg.raceMode == 'on' and arg.avoidCars == 'on' then
    print("Race mode is ON. Racing behavior is active.")

    -- Initialize currentRoute only when raceMode is 'on'
    currentRoute = {
      path = arg.wpTargetList,  -- Use the provided waypoints
      plan = {}  -- Initialize an empty plan
    }

    -- Enable racing behavior
    racingBehavior(currentRoute, baseRoute)
  else
    print("Race mode is OFF. Default behavior is active.")  -- Debug statement
  end

  if arg.script then
    -- Set vehicle position and orientation at the start of the path
    -- Get initial position and orientation of vehicle at start of path (possibly time offset and/or time delayed)
    local script = arg.script
    local dir, up, pos
    if script[1].dir then
      -- vehicle initial orientation vectors exist

      dir = vec3(script[1].dir)
      up = vec3(script[1].up or mapmgr.surfaceNormalBelow(vec3(script[1])))

      local frontPosRelOrig = obj:getOriginalFrontPositionRelative() -- original relative front position in the vehicle coordinate system (left, back, up)
      local vx = dir * -frontPosRelOrig.y
      local vz = up * frontPosRelOrig.z
      local vy = dir:cross(up) * -frontPosRelOrig.x
      pos = vec3(script[1]) - vx - vz - vy
      local dH = require('scriptai').wheelToGroundDist(pos, dir, up)
      pos:setAdd(dH * up)
    else
      -- vehicle initial orientation vectors don't exist
      -- estimate vehicle orientation vectors from path and ground normal

      local p1 = vec3(script[1])
      local p1z0 = p1:z0()
      local scriptPosi = vec3()
      local k
      for i = 2, #script do
        scriptPosi:set(script[i].x, script[i].y, 0)
        if p1z0:squaredDistance(scriptPosi) > 0.2 * 0.2 then
          k = i
          break
        end
      end

      if k then
        local p2 = vec3(script[k])
        dir = p2 - p1; dir:normalize()
        up = mapmgr.surfaceNormalBelow(p1)

        local frontPosRelOrig = obj:getOriginalFrontPositionRelative() -- original relative front position in the vehicle coordinate system (left, back, up)
        local vx = dir * -frontPosRelOrig.y
        local vz = up * frontPosRelOrig.z
        local vy = dir:cross(up) * -frontPosRelOrig.x
        pos = p1 - vx - vz - vy
        local dH = require('scriptai').wheelToGroundDist(pos, dir, up)
        pos:setAdd(dH * up)
      end
    end

    if dir then
      local rot = quatFromDir(dir:cross(up):cross(up), up)
      obj:queueGameEngineLua(
        "be:getObjectByID(" .. objectId .. "):resetBrokenFlexMesh();" ..
        "vehicleSetPositionRotation(" .. objectId .. "," .. pos.x .. "," .. pos.y .. "," .. pos.z .. "," .. rot.x .. "," .. rot.y .. "," .. rot.z .. "," .. rot.w .. ")"
      )

      mapmgr.setCustomMap() -- nils mapmgr.mapData
      M.mode = 'manual'
      stateChanged()

      local pathMap = require('graphpath').newGraphpath()
      local path = {}
      local radius = obj:getInitialWidth()
      local outNode, outPos
      local speedProfile = {}
      for i = 1, #arg.script - 1 do
        local inNode = 'wp_'..tostring(i)
        outNode = 'wp_'..tostring(i+1)
        local inPos = vec3(arg.script[i].x, arg.script[i].y, arg.script[i].z)
        outPos = vec3(arg.script[i+1].x, arg.script[i+1].y, arg.script[i+1].z)
        pathMap:uniEdge(inNode, outNode, inPos:distance(outPos), 1, 100, nil, false)
        pathMap:setPointPositionRadius(inNode, inPos, radius)
        table.insert(path, inNode)
        speedProfile[inNode] = arg.script[i].v
      end
      pathMap:setPointPositionRadius(outNode, outPos, radius)
      table.insert(path, 'wp_'..tostring(#arg.script))
      speedProfile[outNode] = arg.script[#arg.script].v

      scriptData = deepcopy(arg)
      scriptData.mapData = pathMap
      scriptData.path = path
      scriptData.speedProfile = speedProfile
    end
  else
    setState({mode = 'manual'})

    setParameters({
      driveStyle = arg.driveStyle or 'default',
      staticFrictionCoefMult = max(0.95, arg.staticFrictionCoefMult or 0.95),
      lookAheadKv = max(0.1, arg.lookAheadKv or parameters.lookAheadKv),
      understeerThrottleControl = arg.understeerThrottleControl,
      oversteerThrottleControl = arg.oversteerThrottleControl,
      throttleTcs = arg.throttleTcs
    })

    noOfLaps = arg.noOfLaps and max(arg.noOfLaps, 1) or 1
    wpList = arg.wpTargetList
    manualPath = arg.path
    validateInput = validateUserInput
    avoidCars = arg.avoidCars or 'off'

    if noOfLaps > 1 and wpList[2] and wpList[1] == wpList[#wpList] then
      race = true
    end

    speedProfile = arg.wpSpeeds or {}
    setSpeed(arg.routeSpeed)
    setSpeedMode(arg.routeSpeedMode)
    setSafetyDistance(arg.safetyDistance)
    setLateralOffsetRange(arg.lateralOffsetRange)
    setLateralOffsetScale(arg.lateralOffsetScale)
    setShortestPathBias(arg.shortestPathBias)

    driveInLane(arg.driveInLane)

    setAggressionExternal(arg.aggression)
    stateChanged()
  end
end

local function spanMap(cutOffDrivability)
  M.cutOffDrivability = cutOffDrivability or 0
  setState({mode = 'span'})
  stateChanged()
end

local function setCutOffDrivability(drivability)
  M.cutOffDrivability = drivability or 0
  stateChanged()
end

local function onDeserialized(v)
  setState(v)
  stateChanged()
end

local function dumpCurrentRoute()
  dump(currentRoute)
end

local function getParameters()
  return parameters
end

local function startRecording(recordSpeed)
  M.mode = 'script'
  scriptai = require("scriptai")
  scriptai.startRecording(recordSpeed)
  M.updateGFX = scriptai.updateGFX
end

local function stopRecording()
  M.mode = 'disabled'
  scriptai = require("scriptai")
  local script = scriptai.stopRecording()
  M.updateGFX = scriptai.updateGFX
  return script
end

local function startFollowing(...)
  local script = ...
  if script.path then
    script = script.path
  end
  if script[1] and script[1].v then
    driveUsingPath({script = script})
  else
    M.mode = 'script'
    scriptai = require("scriptai")
    scriptai.startFollowing(...)
    M.updateGFX = scriptai.updateGFX
  end
end

local function scriptStop(...)
  M.mode = 'disabled'
  scriptai = require("scriptai")
  scriptai.scriptStop(...)
  M.updateGFX = scriptai.updateGFX
end

local function scriptState()
  scriptai = require("scriptai")
  return scriptai.scriptState()
end

local function setScriptDebugMode(mode)
  scriptai = require("scriptai")
  if mode == nil or mode == 'off' then
    M.debugMode = 'all'
    M.debugDraw = nop
    return
  end

  M.debugDraw = debugDraw
  scriptai.debugMode = mode
end

local function isDriving()
  return M.updateGFX == updateGFX or (scriptai ~= nil and scriptai.isDriving())
end

local function logDataTocsv()
  if not misc.csvFile then
    print('Started Logging Data')
    misc.csvFile = require('csvlib').newCSV("time", "posX", "posY", "posZ", "speed", "ax", "throttle", "brake", "steering")
    misc.time = 0
  else
    misc.time = misc.time + dt
  end
  misc.csvFile:add(misc.time, ai.pos.x, ai.pos.y, ai.pos.z, ai.speed, -sensors.gy, lastCommand.throttle, lastCommand.brake, lastCommand.steering)
end

local function writeCsvFile(name)
  if misc.csvFile then
    print('Writing Data to CSV.')
    misc.csvFile:write(name)
    misc.csvFile = nil
    misc.time = nil
    print('Done')
  else
    print('No data to write')
  end
end

local function startStopDataLog(name)
  if misc.logData == nop then
    print('Initialized Data Log')
    misc.logData = logDataTocsv
  else
    print('Stopped Logging Data')
    misc.logData = nop
    writeCsvFile(name)
  end
end

local function logDriverDataToCsv(time, driver, series_name, map_name, stage_class, run, checkpoint, multiplier, risk, vision, awareness, safetyDistance, lateralOffsetRange, lateralOffsetScale, shortestPathBias, turnForceCoef, springForceIntegratorDispLim)
  local fileName = "/csvData/".. driver .. ".csv"
  local nextRowNumber = 1  -- Default to 1 if the file doesn't exist

  -- Validate input parameters
  if not time then
    print("Error: Missing or invalid parameter 'time'")
    return
  end
  if not driver then
    print("Error: Missing or invalid parameter 'driver'")
    return
  end
  if not series_name then
    print("Error: Missing or invalid parameter 'series_name'")
    return
  end
  if not map_name then
    print("Error: Missing or invalid parameter 'map_name'")
    return
  end
  if not stage_class then
    print("Error: Missing or invalid parameter 'stage_class'")
    return
  end
  if not run then
    print("Error: Missing or invalid parameter 'run'")
    return
  end
  if not checkpoint then
    print("Error: Missing or invalid parameter 'checkpoint'")
    return
  end
  if not multiplier then
    print("Error: Missing or invalid parameter 'driver'")
    return
  end
  if not risk then
      print("Error: Missing or invalid parameter 'risk'")
      return
  end
  if not vision then
      print("Error: Missing or invalid parameter 'vision'")
      return
  end
  if not awareness then
      print("Error: Missing or invalid parameter 'awareness'")
      return
  end
  if not safetyDistance then
      print("Error: Missing or invalid parameter 'safetyDistance'")
      return
  end
  if not lateralOffsetRange then
      print("Error: Missing or invalid parameter 'lateralOffsetRange'")
      return
  end
  if not lateralOffsetScale then
      print("Error: Missing or invalid parameter 'lateralOffsetScale'")
      return
  end
  if not shortestPathBias then
      print("Error: Missing or invalid parameter 'shortestPathBias'")
      return
  end
  if not turnForceCoef then
      print("Error: Missing or invalid parameter 'turnForceCoef'")
      return
  end
  if not springForceIntegratorDispLim then
      print("Error: Missing or invalid parameter 'springForceIntegratorDispLim'")
      return
  end

  -- Check if the CSV file exists
  local file = io.open(fileName, "r")
  if file then
      -- File exists, read the last row number
      local lastLine
      for line in file:lines() do
          lastLine = line
      end
      file:close()

      if lastLine then
          -- Extract the number from the last line
          local lastNumber = tonumber(lastLine:match("^(%d+),"))
          if lastNumber then
              nextRowNumber = lastNumber + 1
          end
      end
  end

  -- Initialize or append to the CSV file
  if not misc.csvFile then
      -- Create a new CSV file with headers if it doesn't exist
      misc.csvFile = require('csvlib').newCSV("number", "time", "driver", "series_name", "map_name", "stage_class", "run", "checkpoint", "multiplier", "risk", "vision", "awareness", "safetyDistance", "lateralOffsetRange", "lateralOffsetScale", "shortestPathBias", "turnForceCoef", "springForceIntegratorDispLim")
  end

  -- Append the new data
  misc.csvFile:add(nextRowNumber, time, driver, series_name, map_name, stage_class, run, checkpoint, multiplier, risk, vision, awareness, safetyDistance, lateralOffsetRange, lateralOffsetScale, shortestPathBias, turnForceCoef, springForceIntegratorDispLim)

  -- Write the data to the CSV file
  misc.csvFile:write(fileName)
  -- print("Data successfully written to " .. fileName .. " for driver: " .. driver)
end

local function readCSVData(filename, separator)
  -- Set a default separator if none is provided
  separator = separator or ","

  -- Open the CSV file for reading
  local csvFile = io.open(filename, "r")
  if not csvFile then
      return "Error: Could not open file " .. filename
  end

  -- Read the header (first row) of the CSV file
  local header = csvFile:read()
  if not header then
      csvFile:close()
      return "Error: CSV file is empty or has no header"
  end

  -- Convert the header string into a table
  local headerTable = {}
  for field in string.gmatch(header, "[^" .. separator .. "]+") do
      table.insert(headerTable, field)
  end

  -- Print the header
  print("Header: " .. table.concat(headerTable, ", "))

  -- Read and process each row of the CSV file
  local rowIndex = 1
  while true do
      local row = csvFile:read()
      if not row then break end  -- Exit the loop if there are no more rows

      -- Convert the row string into a table
      local rowData = {}
      for field in string.gmatch(row, "[^" .. separator .. "]+") do
          table.insert(rowData, field)
      end

      -- Debugging: Print the raw row data
      print("Raw Row " .. rowIndex .. ": " .. table.concat(rowData, ", "))

      -- Map row data to header fields
      local rowMapped = {}
      for i, fieldName in ipairs(headerTable) do
          rowMapped[fieldName] = rowData[i] or "nil"  -- Use "nil" as a placeholder for missing values
      end

      -- Print or process the row data
      print(string.format(
          "Row %d: number=%s, driver=%s, map_name=%s, stage_class=%s, run=%s, checkpoint=%s, multiplier=%s, risk=%s, vision=%s, awareness=%s, safetyDistance=%s, lateralOffsetRange=%s, lateralOffsetScale=%s, shortestPathBias=%s, turnForceCoef=%s, springForceIntegratorDispLim=%s",
          rowIndex,
          rowMapped["number"], rowMapped["driver"], rowMapped["map_name"], rowMapped["stage_class"], rowMapped["run"], rowMapped["checkpoint"], rowMapped["multiplier"], rowMapped["risk"], rowMapped["vision"], rowMapped["awareness"], rowMapped["safetyDistance"], rowMapped["lateralOffsetRange"], rowMapped["lateralOffsetScale"], rowMapped["shortestPathBias"], rowMapped["turnForceCoef"], rowMapped["springForceIntegratorDispLim"]
      ))

      rowIndex = rowIndex + 1
  end

  -- Close the CSV file
  csvFile:close()

  -- Return a success message
  return "CSV file processed successfully"
end

local function readCSVforTrigger(filename, separator)
  separator = separator or ","
  local csvFile = io.open(filename, "r")
  if not csvFile then
      return nil, "Error: Could not open file " .. filename
  end

  local header = csvFile:read()
  if not header then
      csvFile:close()
      return nil, "Error: CSV file is empty or has no header"
  end

  local headerTable = {}
  for field in string.gmatch(header, "[^" .. separator .. "]+") do
      table.insert(headerTable, field:gsub("^%s*(.-)%s*$", "%1"))
  end

  local driverData = {}
  local paramMap = {
      risk = {'risk_min', 'risk_max'},
      vision = {'vision_min', 'vision_max'},
      awareness = {'awareness_min', 'awareness_max'},
      safetyDistance = {'safetyDistance_min', 'safetyDistance_max'},
      lateralOffsetRange = {'lateraloffsetrange_min', 'lateraloffsetrange_max'},
      lateralOffsetScale = {'lateraloffsetscale_min', 'lateraloffsetscale_max'},
      shortestPathBias = {'shortestpathbias_min', 'shortestpathbias_max'}
  }

  local rowIndex = 1
  while true do
      local row = csvFile:read()
      if not row then break end

      local rowData = {}
      for field in string.gmatch(row, "[^" .. separator .. "]+") do
          table.insert(rowData, field:gsub("^%s*(.-)%s*$", "%1"))
      end

      local rowMapped = {}
      for i, fieldName in ipairs(headerTable) do
          rowMapped[fieldName] = rowData[i] or "nil"
      end

      local carFilename = rowMapped['car_filename']
      if carFilename and carFilename ~= "nil" then
          driverData[carFilename] = {}
          for param, keys in pairs(paramMap) do
              local minVal = tonumber(rowMapped[keys[1]])
              local maxVal = tonumber(rowMapped[keys[2]])
              if minVal and maxVal then
                  driverData[carFilename][param] = { min = minVal, max = maxVal }
              else
                  print(string.format("Warning: Invalid min/max for %s in row %d", param, rowIndex))
              end
          end
      else
          print(string.format("Warning: Missing car_filename in row %d", rowIndex))
      end
      rowIndex = rowIndex + 1
  end

  csvFile:close()
  return driverData
end

-- public interface
M.driveInLane = driveInLane
M.stateChanged = stateChanged
M.reset = reset
M.setMode = setMode
M.toggleTrafficMode = toggleTrafficMode
M.setAvoidCars = setAvoidCars
M.setSafetyDistance = setSafetyDistance
M.setLateralOffsetRange = setLateralOffsetRange
M.setLateralOffsetScale =setLateralOffsetScale
M.setShortestPathBias = setShortestPathBias
M.setTarget = setTarget
M.setPath = setPath
M.setSpeed = setSpeed
M.setSpeedMode = setSpeedMode
M.setParameters = setParameters
M.getParameters = getParameters
M.setVehicleDebugMode = setVehicleDebugMode
M.setState = setState
M.getState = getState
M.debugDraw = nop
M.driveUsingPath = driveUsingPath
M.setAggressionMode = setAggressionMode
M.setAggression = setAggressionExternal
M.onDeserialized = onDeserialized
M.setTargetObjectID = setTargetObjectID
M.laneChange = laneChange
M.setStopPoint = setStopPoint
M.dumpCurrentRoute = dumpCurrentRoute
M.spanMap = spanMap
M.setCutOffDrivability = setCutOffDrivability
M.resetLearning = resetLearning
M.isDriving = isDriving
M.startStopDataLog = startStopDataLog
M.setRecoverOnCrash = setRecoverOnCrash
M.getEdgeLaneConfig = getEdgeLaneConfig
M.setPullOver = setPullOver
M.roadNaturalContinuation = roadNaturalContinuation -- for debugging
M.logDriverDataToCsv = logDriverDataToCsv
M.readCSVData = readCSVData
M.readCSVforTrigger = readCSVforTrigger

-- scriptai
M.startRecording = startRecording
M.stopRecording = stopRecording
M.startFollowing = startFollowing
M.stopFollowing = scriptStop
M.scriptStop = scriptStop
M.scriptState = scriptState
M.setScriptDebugMode = setScriptDebugMode
M.setTractionModel = setTractionModel
M.setSpeedProfileMode = setSpeedProfileMode
return M
