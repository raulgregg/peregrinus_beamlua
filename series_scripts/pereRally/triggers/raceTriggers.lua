package.path = package.path .. "\\pereRally\\?.lua"

local dataTables = require("vehicle.pereRally.dataTables")
local driverTables = require("vehicle.pereRally.driverTables")

local time = os.time()
local is_training = 1
local run = 1

local raw_map_name = core_levels.getLevelName(getMissionFilename());
local map_name = raw_map_name:gsub("_", " "):gsub("(%a)(%a*)", function(first, rest)
    return first:upper()..rest:lower()
end)

local function updateDriverPersonality(data)
    if data.triggerName then
        -- Extract series name from triggerName
        series_name = data.triggerName:match("^([^_]+)")
        -- Extract checkpoint number from triggerName
        checkpoint = tonumber(data.triggerName:match("_trigger(%d+)$"))
        -- Extract and format track class from triggerName
        local class_part = data.triggerName:match("_([^_]+)_trigger")
        track_class = class_part:gsub("([%l])(%u)", "%1 %2")  -- Split before uppercase preceded by lowercase
                                :gsub("^(%u)", " %1"):gsub("%s+", " "):gsub("^%s", "")  -- Cleanup spaces
                                :gsub("Class%s+A", "Class A")  -- Special case normalization
    end
    if data.event == "enter" then
        driverTables.refreshRandomValues()
        local veh = be:getObjectByID(data.subjectID)
        local tbl1 = core_vehicle_manager.getVehicleData(data.subjectID)
        for k, v in pairs(tbl1['config']) do 
            if k == 'partConfigFilename' then
                local driver = v
                local vehicleData = driverTables.vehicleByPath[driver]  -- Get vehicle data
                local multiplier = dataTables.checkpointMultipliers.getMultiplier(
                    map_name, 
                    series_name, 
                    track_class, 
                    checkpoint
                )
                local risk          = driverTables.randomized.risk[driver] * multiplier
                local vision       = driverTables.randomized.vision[driver]
                local awareness    = driverTables.randomized.awareness[driver]
                local safetyDistance = driverTables.randomized.safetyDistance[driver]
                local lateralOffsetRange = driverTables.randomized.lateralOffsetRange[driver]
                local lateralOffsetScale = driverTables.randomized.lateralOffsetScale[driver]
                local shortestPathBias = driverTables.randomized.shortestPathBias[driver]
                local springForce   = driverTables.randomized.springForce[driver]
                local turnForce     = driverTables.randomized.turnForce[driver]
                local awarenessForce = driverTables.randomized.awarenessForce[driver]
                local driveStyle = dataTables.driveStyleLookup.getDriveStyle(
                    map_name,
                    series_name, 
                    track_class,
                    checkpoint
                )                
                local str = driver
                local base = str:match(".*/pereRally_(.-)%..*$")
                local stage_class, namePart = base:match("([^_]+)_(.*)")
                local driver_name = namePart:gsub("(%u)(%l*)", function(first, rest) return " " .. first:upper() .. rest:lower() end)
                                            :gsub("^%s+", "")
                                            :gsub("%s+", " ")
                                            :gsub("(%a)(%a*)", function(first, rest) return first:upper() .. rest:lower() end)
                if not risk then
                    print('Error with data. Please double check driver')
                    print(driver)
                else
                    veh:queueLuaCommand('ai.setAggression(' .. risk .. '); ai.driveInLane("off"); ai.setAvoidCars("on")')
                    veh:queueLuaCommand('ai.setSafetyDistance(' .. safetyDistance .. '); ai.setShortestPathBias(' .. shortestPathBias .. ')')
                    veh:queueLuaCommand('ai.setLateralOffsetRange(' .. lateralOffsetRange .. '); ai.setLateralOffsetScale(' .. lateralOffsetScale .. ')')
                    veh:queueLuaCommand('ai.setParameters({lookAheadKv = ' .. vision .. ', planErrorSmoothing = false})')
                    veh:queueLuaCommand('ai.setParameters({awarenessForceCoef = ' .. awarenessForce .. '})')
                    veh:queueLuaCommand('ai.setParameters({driveStyle = "' .. driveStyle ..'", turnForceCoef = ' .. turnForce .. ', planErrorSmoothing = false, springForceIntegratorDispLim = ' .. springForce .. '})')
                    veh:queueLuaCommand('ai.logDriverDataToCsv('..time..',"'..driver_name..'","'..series_name..'","'..raw_map_name..'","'..stage_class..'",'..run.. ','..is_training..','..checkpoint..','..multiplier..','..risk..','..vision..','..awareness..','..safetyDistance..','..lateralOffsetRange..','..lateralOffsetScale..','..shortestPathBias..','..turnForce..','..springForce..')')
                    print(risk..','..vision..','..awareness..','..safetyDistance..','..lateralOffsetRange..','..lateralOffsetScale..','..shortestPathBias..','..turnForce..','..springForce)
                end 
            end
        end
    end
end
return updateDriverPersonality