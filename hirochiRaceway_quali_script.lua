
setTimeOfDay("7:00");
-- set for all cars at same time
be:queueAllObjectLua('ai.driveUsingPath({wpTargetList = {"hr_start","quickrace_wp6","hr_bridge6","hr_bridge5","quickrace_wp4","quickrace_wp11","hr_start"}, raceMode = "on", avoidCars = "on", noOfLaps = 4, aggression = 1.5, safetyDistance = 0.2, lateralOffsetRange = 1, lateralOffsetScale = 0.8, shortestPathBias = 0.5})'); be:queueAllObjectLua('ai.driveInLane("off")');

-- set for each car individually during Qualifiers

-- PIT 1 -- 1 Lap Hood Camera
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit1"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 1, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 1
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit1"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 2
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit2"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 3
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit3"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 4
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit4"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 5
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit5"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 6
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit6"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 7
ai.driveUsingPath({wpTargetList = {
"hr_pit_exit",
"quickrace_wp6",
"hr_bridge6",
"hr_bridge5",
"quickrace_wp4",
"quickrace_wp11",
"hr_start",
"quickrace_wp6",
"hr_bridge6",
"hr_bridge5",
"quickrace_wp4",
"quickrace_wp11",
"hr_start",
"quickrace_wp6",
"hr_bridge6",
"hr_bridge5",
"quickrace_wp4",
"quickrace_wp11",
"hr_start",
"quickrace_wp6",
"hr_bridge6",
"hr_bridge5",
"quickrace_wp4",
"hr_pit_entry",
"hr_pit",
"hr_pit7"
},
raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
ai.driveInLane("off");
ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- PIT 8
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit8"
    }, 
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "hr_pit_entry",
    "hr_pit",
    "hr_pit7"
    }, 
    wpSpeeds = {hr_pit_exit = 5, hr_pit_entry = 5, hr_pit = 5, hr_pit7 = 5},
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
ai.driveInLane("off");
ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});


be:queueAllObjectLua('ai.setSafetyDistance(0.1)');
be:queueAllObjectLua('ai.setLateralOffsetRange(0.9)');
be:queueAllObjectLua('ai.setLateralOffsetScale(0.9)');
be:queueAllObjectLua('ai.setShortestPathBias(0.9)');

be:queueAllObjectLua('ai.setAggression(0.7)');

be:queueAllObjectLua('ai.driveInLane("off")'); 
be:queueAllObjectLua('ai.setAggression(math.random(70,90)/100)');
be:queueAllObjectLua('ai.setAvoidCars("on")'); 
be:queueAllObjectLua('ai.setParameters({lookAheadKv = math.random(40,70)/100, driveStyle = "default", awarenessForceCoef = math.random(5,20)/100, turnForceCoef = 2, planErrorSmoothing = false, springForceIntegratorDispLim = 0.1, edgeDist = -0.5})'); 



be:queueAllObjectLua('ai.setAggression(math.random(70,90)/100)');

ai.driveUsingPath({wpTargetList = {
"startGrid_WP"
}, wpSpeeds = {}, noOfLaps = 1, aggression = 0.2});