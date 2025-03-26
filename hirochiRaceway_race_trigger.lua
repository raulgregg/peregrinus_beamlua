local trackName = "Hirochi Raceway"
local springForceIntegratorDispLim = math.random(15, 20)/100;
local turnForceCoef = math.random(10, 14)/100;
-- Ultra-aggressive distance parameters
local awareness = math.random(50,100)/1000  -- 0.05-0.10 (quicker reactions)
local safetyDistance = math.random(0,15)/100  -- 0.00-0.15 (cars will tailgate)
local lateralOffsetRange = math.random(90,100)/100  -- 0.9-1.0 (use full track width)
local lateralOffsetScale = math.random(90,100)/100  -- 0.9-1.0 (max lateral commitment)
local shortestPathBias = math.random(5,20)/100  -- 0.05-0.20 (ignore racing line)

-- Aggression multiplier system
local aggressionBoost = 1.2  -- Additional aggression multiplier

-- Apply aggressive modifiers
lateralOffsetRange = math.min(1.0, lateralOffsetRange * aggressionBoost)
lateralOffsetScale = math.min(1.0, lateralOffsetScale * aggressionBoost)
safetyDistance = math.max(0.05, safetyDistance / aggressionBoost)

local raceRiskTable = {};
raceRiskTable['a-walker'] = math.random(716,938)/1000;
raceRiskTable['a-pamilekunayo'] = math.random(573,1033)/1000;
raceRiskTable['c-dargan'] = math.random(528,992)/1000;
raceRiskTable['c-falloone'] = math.random(798,878)/1000;
raceRiskTable['d-obrien'] = math.random(748,890)/1000;
raceRiskTable['d-vitello'] = math.random(615,961)/1000;
raceRiskTable['e-brooks'] = math.random(736,964)/1000;
raceRiskTable['g-alencar'] = math.random(619,971)/1000;
raceRiskTable['j-janus'] = math.random(721,979)/1000;
raceRiskTable['j-fraga'] = math.random(678,908)/1000;
raceRiskTable['l-balkaran'] = math.random(608,926)/1000;
raceRiskTable['n-hill'] = math.random(799,983)/1000;
raceRiskTable['p-vaz'] = math.random(613,1015)/1000;
raceRiskTable['p-frolov'] = math.random(756,908)/1000;
raceRiskTable['q-li'] = math.random(787,885)/1000;
raceRiskTable['r-cabral'] = math.random(796,1010)/1000;
raceRiskTable['s-puma'] = math.random(840,908)/1000;
raceRiskTable['s-grehan'] = math.random(693,907)/1000;
raceRiskTable['t-muneyaki'] = math.random(672,966)/1000;
raceRiskTable['t-abarquero'] = math.random(698,908)/1000;
raceRiskTable['v-ogurtsov'] = math.random(579,1005)/1000;
raceRiskTable['z-galanoglou'] = math.random(717,1037)/1000;


local raceVisionTable = {};
raceVisionTable['a-walker'] = math.random(75,84)/100;
raceVisionTable['a-pamilekunayo'] = math.random(72.1,82.1)/100;
raceVisionTable['c-dargan'] = math.random(67.6,81.6)/100;
raceVisionTable['c-falloone'] = math.random(77.9,80.9)/100;
raceVisionTable['d-obrien'] = math.random(76.1,83.1)/100;
raceVisionTable['d-vitello'] = math.random(73.6,82.6)/100;
raceVisionTable['e-brooks'] = math.random(74.6,84.6)/100;
raceVisionTable['g-alencar'] = math.random(72.4,82.4)/100;
raceVisionTable['j-janus'] = math.random(75.3,84.3)/100;
raceVisionTable['j-fraga'] = math.random(72.4,83.4)/100;
raceVisionTable['l-balkaran'] = math.random(74.2,83.2)/100;
raceVisionTable['n-hill'] = math.random(76.4,84.4)/100;
raceVisionTable['p-vaz'] = math.random(69.5,82.5)/100;
raceVisionTable['p-frolov'] = math.random(76,81)/100;
raceVisionTable['q-li'] = math.random(77.7,82.7)/100;
raceVisionTable['r-cabral'] = math.random(72.8,84.8)/100;
raceVisionTable['s-puma'] = math.random(78.1,82.1)/100;
raceVisionTable['s-grehan'] = math.random(75.7,83.7)/100;
raceVisionTable['t-muneyaki'] = math.random(74.1,84.1)/100;
raceVisionTable['t-abarquero'] = math.random(73.8,83.8)/100;
raceVisionTable['v-ogurtsov'] = math.random(73.6,82.6)/100;
raceVisionTable['z-galanoglou'] = math.random(73.5,82.5)/100;

local function updateDriverPersonality(data)
    if data.event == "enter" then
        local veh = be:getObjectByID(data.subjectID)
        local tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = raceRiskTable[driver]
                local vision = raceVisionTable[driver]
                if not risk then
                    print("Error with data. Please double check")
                    print(driver)
                else
                    -- Set AI parameters
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setSafetyDistance(' .. safetyDistance .. '); ai.setShortestPathBias(' .. shortestPathBias .. ')')
                    veh:queueLuaCommand('ai.setLateralOffsetRange(' .. lateralOffsetRange .. '); ai.setLateralOffsetScale(' .. lateralOffsetScale .. ')')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. ', planErrorSmoothing = false})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awareness .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "default", turnForceCoef = ' .. turnForceCoef .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForceIntegratorDispLim .. '})')
                    print(string.upper(driver) .. ': RISK: ' .. risk .. ' || VISION: ' .. vision .. ' || AWARENESS: ' .. awareness .. ' || SAFETY DISTANCE: ' .. safetyDistance .. ' || OFFSET RANGE: ' .. lateralOffsetRange .. ' || OFFSET SCALE: ' .. lateralOffsetScale .. ' || SHORTEST PATH BIAS: ' .. shortestPathBias)
                end 
            end
        end
    end
end
return updateDriverPersonality