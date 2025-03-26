local edgeDist = math.random(0, 5)/100 * -1
local springForceIntegratorDispLim = math.random(1, 5)/100
local turnForceCoef = math.random(80, 100)/100
local bonus = math.random(0, 10)/100

local tbl2 = {};
local tbl3 = {};
local tbl4 = {};
tbl2['a-walker'] = math.random(70,80)/100 + 0.03;
tbl2['a-pamilekunayo'] = math.random(57,66)/100 + 0.12;
tbl2['c-dargan'] = math.random(57,70)/100 + 0.12;
tbl2['c-falloone'] = math.random(79,82)/100 + 0.01;
tbl2['d-obrien'] = math.random(74,81)/100 + 0.01;
tbl2['d-vitello'] = math.random(65,73)/100 + 0.09;
tbl2['e-brooks'] = math.random(74,81)/100 + 0.02;
tbl2['g-alencar'] = math.random(62,70)/100 + 0.09;
tbl2['j-janus'] = math.random(71,79)/100 + 0.03;
tbl2['j-fraga'] = math.random(65,76)/100 + 0.02;
tbl2['l-balkaran'] = math.random(63,70)/100 + 0.06;
tbl2['n-hill'] = math.random(80,90)/100 + 0;
tbl2['p-vaz'] = math.random(65,78)/100 + 0.06;
tbl2['p-frolov'] = math.random(74,79)/100 + 0.02;
tbl2['q-li'] = math.random(76,82)/100 + 0.01;
tbl2['r-cabral'] = math.random(81,92)/100 + 0;
tbl2['s-puma'] = math.random(82,86)/100 + 0;
tbl2['s-grehan'] = math.random(66,74)/100 + 0.09;
tbl2['t-muneyaki'] = math.random(67,76)/100 + 0.12;
tbl2['t-abarquero'] = math.random(67,77)/100 + 0.03;
tbl2['v-ogurtsov'] = math.random(60,66)/100 + 0.15;
tbl2['z-galanoglou'] = math.random(75,86)/100 + 0.06;
tbl3['a-walker'] = math.random(73.2,83.2)/100;
tbl3['a-pamilekunayo'] = math.random(70.9,79.9)/100;
tbl3['c-dargan'] = math.random(68.2,81.2)/100;
tbl3['c-falloone'] = math.random(76.9,79.9)/100;
tbl3['d-obrien'] = math.random(74.7,81.7)/100;
tbl3['d-vitello'] = math.random(70.8,78.8)/100;
tbl3['e-brooks'] = math.random(74.7,81.7)/100;
tbl3['g-alencar'] = math.random(71.2,79.2)/100;
tbl3['j-janus'] = math.random(75.4,83.4)/100;
tbl3['j-fraga'] = math.random(71.1,82.1)/100;
tbl3['l-balkaran'] = math.random(73.3,80.3)/100;
tbl3['n-hill'] = math.random(76,86)/100;
tbl3['p-vaz'] = math.random(68.5,81.5)/100;
tbl3['p-frolov'] = math.random(74,79)/100;
tbl3['q-li'] = math.random(75.4,81.4)/100;
tbl3['r-cabral'] = math.random(74.3,85.3)/100;
tbl3['s-puma'] = math.random(77.1,81.1)/100;
tbl3['s-grehan'] = math.random(75,83)/100;
tbl3['t-muneyaki'] = math.random(71.7,80.7)/100;
tbl3['t-abarquero'] = math.random(72.9,82.9)/100;
tbl3['v-ogurtsov'] = math.random(73.2,79.2)/100;
tbl3['z-galanoglou'] = math.random(71.2,82.2)/100;
tbl3['prgnus'] = math.random(60,60)/100;
tbl4['a-walker'] = math.random(90,150)/1000;
tbl4['a-pamilekunayo'] = math.random(90,150)/1000;
tbl4['c-dargan'] = math.random(90,150)/1000;
tbl4['c-falloone'] = math.random(90,150)/1000;
tbl4['d-obrien'] = math.random(90,150)/1000;
tbl4['d-vitello'] = math.random(90,150)/1000;
tbl4['e-brooks'] = math.random(90,150)/1000;
tbl4['g-alencar'] = math.random(90,150)/1000;
tbl4['j-janus'] = math.random(90,150)/1000;
tbl4['j-fraga'] = math.random(90,150)/1000;
tbl4['l-balkaran'] = math.random(90,150)/1000;
tbl4['n-hill'] = math.random(90,150)/1000;
tbl4['p-vaz'] = math.random(90,150)/1000;
tbl4['p-frolov'] = math.random(90,150)/1000;
tbl4['q-li'] = math.random(90,150)/1000;
tbl4['r-cabral'] = math.random(90,150)/1000;
tbl4['s-puma'] = math.random(90,150)/1000;
tbl4['s-grehan'] = math.random(90,150)/1000;
tbl4['t-muneyaki'] = math.random(90,150)/1000;
tbl4['t-abarquero'] = math.random(90,150)/1000;
tbl4['v-ogurtsov'] = math.random(90,150)/1000;
tbl4['z-galanoglou'] = math.random(90,150)/1000;
tbl4['prgnus'] = math.random(90,150)/1000;

local function lavaTrigger(data)
    if data.event == "enter" then
        veh = be:getObjectByID(data.subjectID)
        tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'licenseName' then
                local driver = string.lower(v)
                local risk = tbl2[driver]
                local vision = tbl3[driver]
                local awareness = tbl4[driver]
                if not risk then
                    print("Error with data. Please double check")
                    print(driver)
                else
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. ' + ' .. bonus .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. '})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awareness .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "default", turnForceCoef = ' .. turnForceCoef .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForceIntegratorDispLim .. ', edgeDist = '.. edgeDist ..'})')
                    print(string.upper(driver) .. ': RISK: ' .. risk .. '; VISION: ' .. vision .. '; AWARENESS ' .. awareness)
                end 
            end
        end
    end
end
return lavaTrigger