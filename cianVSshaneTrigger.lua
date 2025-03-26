local springForceIntegratorDispLim = math.random(3, 5)/100;
local turnForceCoef = math.random(10, 14)/100;
-- Ultra-aggressive distance parameters
local awareness = math.random(50,100)/1000  -- 0.05-0.10 (quicker reactions)
local safetyDistance = math.random(1,15)/100  -- 0.00-0.15 (cars will tailgate)
local lateralOffsetRange = math.random(70,100)/100  -- 0.9-1.0 (use full track width)
local lateralOffsetScale = math.random(80,90)/100  -- 0.9-1.0 (max lateral commitment)
local shortestPathBias = math.random(80,100)/100  -- 0.05-0.20 (ignore racing line)

local raceRiskTable = {};
raceRiskTable['c-falloone'] = math.random(798,878)/1000;
raceRiskTable['s-grehan'] = math.random(693,907)/1000;


local raceVisionTable = {};
raceVisionTable['c-falloone'] = math.random(779,809)/1000;
raceVisionTable['s-grehan'] = math.random(757,837)/1000;

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