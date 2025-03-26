local edgeDist = math.random(0, 5)/100 * -1.00;
local springForceIntegratorDispLim = math.random(5, 25)/100;
local turnForceCoef = math.random(8, 10)/100;
local awareness = math.random(90,150)/1000;

local riskTable = {};
riskTable['a-walker'] = math.random(66,76)/100 + 0;
riskTable['a-pamilekunayo'] = math.random(52,62)/100 + 0;
riskTable['c-dargan'] = math.random(52,65)/100 + 0;
riskTable['c-falloone'] = math.random(78,81)/100 + 0;
riskTable['d-obrien'] = math.random(70,77)/100 + 0;
riskTable['d-vitello'] = math.random(58,67)/100 + 0;
riskTable['e-brooks'] = math.random(69,79)/100 + 0;
riskTable['g-alencar'] = math.random(55,65)/100 + 0;
riskTable['j-janus'] = math.random(67,76)/100 + 0;
riskTable['j-fraga'] = math.random(62,73)/100 + 0;
riskTable['l-balkaran'] = math.random(58,65)/100 + 0;
riskTable['n-hill'] = math.random(80,90)/100 + 0;
riskTable['p-vaz'] = math.random(60,75)/100 + 0;
riskTable['p-frolov'] = math.random(71,76)/100 + 0;
riskTable['q-li'] = math.random(75,80)/100 + 0;
riskTable['r-cabral'] = math.random(79,91)/100 + 0;
riskTable['s-puma'] = math.random(79,83)/100 + 0;
riskTable['s-grehan'] = math.random(64,72)/100 + 0;
riskTable['t-muneyaki'] = math.random(64,71)/100 + 0;
riskTable['t-abarquero'] = math.random(64,74)/100 + 0;
riskTable['v-ogurtsov'] = math.random(53,62)/100 + 0;
riskTable['z-galanoglou'] = math.random(70,83)/100 + 0;

local visionTable = {};
visionTable['a-walker'] = math.random(73.2,83.2)/100;
visionTable['a-pamilekunayo'] = math.random(71,81)/100;
visionTable['c-dargan'] = math.random(67.9,80.9)/100;
visionTable['c-falloone'] = math.random(77,80)/100;
visionTable['d-obrien'] = math.random(75,82)/100;
visionTable['d-vitello'] = math.random(72.6,81.6)/100;
visionTable['e-brooks'] = math.random(74.9,84.9)/100;
visionTable['g-alencar'] = math.random(71.1,81.1)/100;
visionTable['j-janus'] = math.random(75.4,84.4)/100;
visionTable['j-fraga'] = math.random(71.7,82.7)/100;
visionTable['l-balkaran'] = math.random(73.5,80.5)/100;
visionTable['n-hill'] = math.random(76.1,86.1)/100;
visionTable['p-vaz'] = math.random(67.8,82.8)/100;
visionTable['p-frolov'] = math.random(74.3,79.3)/100;
visionTable['q-li'] = math.random(76.7,81.7)/100;
visionTable['r-cabral'] = math.random(74.7,86.7)/100;
visionTable['s-puma'] = math.random(77.4,81.4)/100;
visionTable['s-grehan'] = math.random(74.5,82.5)/100;
visionTable['t-muneyaki'] = math.random(73,80)/100;
visionTable['t-abarquero'] = math.random(72.8,82.8)/100;
visionTable['v-ogurtsov'] = math.random(72.7,81.7)/100;
visionTable['z-galanoglou'] = math.random(69.8,82.8)/100;

local function lavaTrigger(data)
    if data.event == "enter" then
        veh = be:getObjectByID(data.subjectID)
        tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = riskTable[driver]
                local vision = visionTable[driver]
                if not risk then
                    print("Error with data. Please double check")
                    print(driver)
                else
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. ', planErrorSmoothing = false})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awareness .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "default", turnForceCoef = ' .. turnForceCoef .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForceIntegratorDispLim .. ', edgeDist = '.. edgeDist ..'})')
                    print(string.upper(driver) .. ': RISK: ' .. risk .. '|| VISION: ' .. vision .. '|| AWARENESS: ' .. awareness)
                end 
            end
        end
    end
end
return lavaTrigger