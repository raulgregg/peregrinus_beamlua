local springForceIntegratorDispLim = math.random(5, 25)/100;
local turnForceCoef = math.random(8, 10)/100;
local awareness = math.random(90,150)/1000;

local qualiRiskTable = {};
qualiRiskTable['a-walker'] = 0.731;
qualiRiskTable['a-pamilekunayo'] = 0.601;
qualiRiskTable['c-dargan'] = 0.592;
qualiRiskTable['c-falloone'] = 0.802;
qualiRiskTable['d-obrien'] = 0.756;
qualiRiskTable['d-vitello'] = 0.659;
qualiRiskTable['e-brooks'] = 0.772;
qualiRiskTable['g-alencar'] = 0.629;
qualiRiskTable['j-janus'] = 0.75;
qualiRiskTable['j-fraga'] = 0.697;
qualiRiskTable['l-balkaran'] = 0.649;
qualiRiskTable['n-hill'] = 0.871;
qualiRiskTable['p-vaz'] = 0.68;
qualiRiskTable['p-frolov'] = 0.742;
qualiRiskTable['q-li'] = 0.791;
qualiRiskTable['r-cabral'] = 0.875;
qualiRiskTable['s-puma'] = 0.827;
qualiRiskTable['s-grehan'] = 0.713;
qualiRiskTable['t-muneyaki'] = 0.694;
qualiRiskTable['t-abarquero'] = 0.712;
qualiRiskTable['v-ogurtsov'] = 0.61;
qualiRiskTable['z-galanoglou'] = 0.77;


local qualiVisionTable = {};
qualiVisionTable['a-walker'] = 0.762;
qualiVisionTable['a-pamilekunayo'] = 0.73;
qualiVisionTable['c-dargan'] = 0.739;
qualiVisionTable['c-falloone'] = 0.78;
qualiVisionTable['d-obrien'] = 0.77;
qualiVisionTable['d-vitello'] = 0.746;
qualiVisionTable['e-brooks'] = 0.769;
qualiVisionTable['g-alencar'] = 0.741;
qualiVisionTable['j-janus'] = 0.764;
qualiVisionTable['j-fraga'] = 0.757;
qualiVisionTable['l-balkaran'] = 0.745;
qualiVisionTable['n-hill'] = 0.791;
qualiVisionTable['p-vaz'] = 0.748;
qualiVisionTable['p-frolov'] = 0.763;
qualiVisionTable['q-li'] = 0.777;
qualiVisionTable['r-cabral'] = 0.787;
qualiVisionTable['s-puma'] = 0.784;
qualiVisionTable['s-grehan'] = 0.755;
qualiVisionTable['t-muneyaki'] = 0.75;
qualiVisionTable['t-abarquero'] = 0.758;
qualiVisionTable['v-ogurtsov'] = 0.737;
qualiVisionTable['z-galanoglou'] = 0.758;


local function lavaTrigger(data)
    if data.event == "enter" then
        veh = be:getObjectByID(data.subjectID)
        tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = qualiRiskTable[driver]
                local vision = qualiVisionTable[driver]
                if not risk then
                    print("Error with data. Please double check")
                    print(driver)
                else
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. ', planErrorSmoothing = false})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awareness .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "default", turnForceCoef = ' .. turnForceCoef .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForceIntegratorDispLim .. '})')
                    print(string.upper(driver) .. ': RISK: ' .. risk .. '|| VISION: ' .. vision .. '|| AWARENESS: ' .. awareness)
                end 
            end
        end
    end
end
return lavaTrigger