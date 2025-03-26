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
local speedBoost = 1.0 + (aggressionBoost * 0.3)  -- Up to +30% speed

-- Apply aggressive modifiers
lateralOffsetRange = math.min(1.0, lateralOffsetRange * aggressionBoost)
lateralOffsetScale = math.min(1.0, lateralOffsetScale * aggressionBoost)
safetyDistance = math.max(0.0, safetyDistance / aggressionBoost)

local qualiRiskTable = {};
qualiRiskTable['a-walker'] = 0.822;
qualiRiskTable['a-pamilekunayo'] = 0.803;
qualiRiskTable['c-dargan'] = 0.76;
qualiRiskTable['c-falloone'] = 0.838;
qualiRiskTable['d-obrien'] = 0.804;
qualiRiskTable['d-vitello'] = 0.808;
qualiRiskTable['e-brooks'] = 0.85;
qualiRiskTable['g-alencar'] = 0.795;
qualiRiskTable['j-janus'] = 0.858;
qualiRiskTable['j-fraga'] = 0.793;
qualiRiskTable['l-balkaran'] = 0.767;
qualiRiskTable['n-hill'] = 0.877;
qualiRiskTable['p-vaz'] = 0.814;
qualiRiskTable['p-frolov'] = 0.818;
qualiRiskTable['q-li'] = 0.81;
qualiRiskTable['r-cabral'] = 0.903;
qualiRiskTable['s-puma'] = 0.852;
qualiRiskTable['s-grehan'] = 0.804;
qualiRiskTable['t-muneyaki'] = 0.812;
qualiRiskTable['t-abarquero'] = 0.803;
qualiRiskTable['v-ogurtsov'] = 0.792;
qualiRiskTable['z-galanoglou'] = 0.884;

local qualiVisionTable = {};
qualiVisionTable['a-walker'] = 0.77;
qualiVisionTable['a-pamilekunayo'] = 0.741;
qualiVisionTable['c-dargan'] = 0.736;
qualiVisionTable['c-falloone'] = 0.789;
qualiVisionTable['d-obrien'] = 0.781;
qualiVisionTable['d-vitello'] = 0.756;
qualiVisionTable['e-brooks'] = 0.766;
qualiVisionTable['g-alencar'] = 0.754;
qualiVisionTable['j-janus'] = 0.763;
qualiVisionTable['j-fraga'] = 0.764;
qualiVisionTable['l-balkaran'] = 0.752;
qualiVisionTable['n-hill'] = 0.774;
qualiVisionTable['p-vaz'] = 0.745;
qualiVisionTable['p-frolov'] = 0.78;
qualiVisionTable['q-li'] = 0.787;
qualiVisionTable['r-cabral'] = 0.768;
qualiVisionTable['s-puma'] = 0.791;
qualiVisionTable['s-grehan'] = 0.767;
qualiVisionTable['t-muneyaki'] = 0.761;
qualiVisionTable['t-abarquero'] = 0.768;
qualiVisionTable['v-ogurtsov'] = 0.746;
qualiVisionTable['z-galanoglou'] = 0.755;

local function updateDriverPersonality(data)
    if data.event == "enter" then
        local veh = be:getObjectByID(data.subjectID)
        local tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = qualiRiskTable[driver]
                local vision = qualiVisionTable[driver]
                if not risk then
                    print("Error with data. Please double check")
                    print(driver)
                else
                    -- Log data to CSV
                    veh:queueLuaCommand('ai.logDriverDataToCsv("' .. trackName .. '","' .. driver .. '",' .. risk .. ',' .. vision .. ',' .. awareness .. ',' .. safetyDistance .. ',' .. lateralOffsetRange .. ',' .. lateralOffsetScale .. ',' .. shortestPathBias .. ',' .. turnForceCoef .. ',' .. springForceIntegratorDispLim ..')')

                    -- Set AI parameters
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setSafetyDistance(' .. safetyDistance .. '); ai.setShortestPathBias(' .. shortestPathBias .. ')')
                    veh:queueLuaCommand('ai.setLateralOffsetRange(' .. lateralOffsetRange .. '); ai.setLateralOffsetScale(' .. lateralOffsetScale .. ')')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. ', planErrorSmoothing = false})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awareness .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "default", turnForceCoef = ' .. turnForceCoef .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForceIntegratorDispLim .. '})')
                    print(string.upper(driver) .. ': RISK: ' .. risk .. ' || VISION: ' .. vision .. ' || AWARENESS: ' .. awareness .. ' || SAFETY DISTANCE: ' .. safetyDistance)
                end 
            end
        end
    end
end
return updateDriverPersonality