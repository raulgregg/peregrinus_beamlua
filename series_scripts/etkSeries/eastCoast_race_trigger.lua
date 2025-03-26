local springForceIntegratorDispLim = math.random(5, 25)/100;
local turnForceCoef = math.random(8, 10)/100;
local awareness = math.random(90,150)/1000;

local raceRiskTable = {};
raceRiskTable['a-walker'] = math.random(669,769)/1000 + 0.01;
raceRiskTable['a-pamilekunayo'] = math.random(521,621)/1000 + 0.15;
raceRiskTable['c-dargan'] = math.random(522,652)/1000 + 0.12;
raceRiskTable['c-falloone'] = math.random(782,812)/1000 + 0;
raceRiskTable['d-obrien'] = math.random(713,783)/1000 + 0.01;
raceRiskTable['d-vitello'] = math.random(582,672)/1000 + 0.09;
raceRiskTable['e-brooks'] = math.random(692,792)/1000 + 0.09;
raceRiskTable['g-alencar'] = math.random(573,673)/1000 + 0.09;
raceRiskTable['j-janus'] = math.random(666,756)/1000 + 0.12;
raceRiskTable['j-fraga'] = math.random(627,737)/1000 + 0.06;
raceRiskTable['l-balkaran'] = math.random(589,659)/1000 + 0.06;
raceRiskTable['n-hill'] = math.random(807,907)/1000 + 0;
raceRiskTable['p-vaz'] = math.random(599,749)/1000 + 0.06;
raceRiskTable['p-frolov'] = math.random(711,761)/1000 + 0.02;
raceRiskTable['q-li'] = math.random(745,795)/1000 + 0.01;
raceRiskTable['r-cabral'] = math.random(795,915)/1000 + 0.03;
raceRiskTable['s-puma'] = math.random(801,841)/1000 + 0;
raceRiskTable['s-grehan'] = math.random(640,720)/1000 + 0.02;
raceRiskTable['t-muneyaki'] = math.random(644,714)/1000 + 0.03;
raceRiskTable['t-abarquero'] = math.random(642,742)/1000 + 0.03;
raceRiskTable['v-ogurtsov'] = math.random(530,620)/1000 + 0.12;
raceRiskTable['z-galanoglou'] = math.random(702,832)/1000 + 0.02;


local raceVisionTable = {};
raceVisionTable['a-walker'] = math.random(73.2,83.2)/100;
raceVisionTable['a-pamilekunayo'] = math.random(71,81)/100;
raceVisionTable['c-dargan'] = math.random(67.9,80.9)/100;
raceVisionTable['c-falloone'] = math.random(77,80)/100;
raceVisionTable['d-obrien'] = math.random(75,82)/100;
raceVisionTable['d-vitello'] = math.random(72.6,81.6)/100;
raceVisionTable['e-brooks'] = math.random(74.9,84.9)/100;
raceVisionTable['g-alencar'] = math.random(71.1,81.1)/100;
raceVisionTable['j-janus'] = math.random(75.4,84.4)/100;
raceVisionTable['j-fraga'] = math.random(71.7,82.7)/100;
raceVisionTable['l-balkaran'] = math.random(73.5,80.5)/100;
raceVisionTable['n-hill'] = math.random(76.1,86.1)/100;
raceVisionTable['p-vaz'] = math.random(67.8,82.8)/100;
raceVisionTable['p-frolov'] = math.random(74.3,79.3)/100;
raceVisionTable['q-li'] = math.random(76.7,81.7)/100;
raceVisionTable['r-cabral'] = math.random(74.7,86.7)/100;
raceVisionTable['s-puma'] = math.random(77.4,81.4)/100;
raceVisionTable['s-grehan'] = math.random(74.5,82.5)/100;
raceVisionTable['t-muneyaki'] = math.random(73,80)/100;
raceVisionTable['t-abarquero'] = math.random(72.8,82.8)/100;
raceVisionTable['v-ogurtsov'] = math.random(72.7,81.7)/100;
raceVisionTable['z-galanoglou'] = math.random(69.8,82.8)/100;


local function lavaTrigger(data)
    if data.event == "enter" then
        veh = be:getObjectByID(data.subjectID)
        tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = raceRiskTable[driver]
                local vision = raceVisionTable[driver]
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