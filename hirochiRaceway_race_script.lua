
setTimeOfDay("7:00");
-- set for all cars at same time
be:queueAllObjectLua('ai.driveUsingPath({wpTargetList = {"hr_start","quickrace_wp6","hr_bridge6","hr_bridge5","quickrace_wp4","quickrace_wp11","hr_start"}, raceMode = "on", avoidCars = "on", noOfLaps = 4, aggression = 2, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6})'); be:queueAllObjectLua('ai.driveInLane("off")') be:queueAllObjectLua('ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05})');

-- set for each car individually during Warmp Up Lap
/* 
    GROUP 3
        Warm Lap Time Start: 06:45
        Race Start Time: 08:08
        Race End Time: 11:01

    GROUP 2
        Warm Lap Time Start: 06:45
        Race Start Time: 08:09
        Race End Time: 11:02

    GROUP 1
        Warm Lap Time Start: 06:45
        Race Start Time: 08:14
        Race End Time: 11:11
*/
-- PIT 1
ai.driveUsingPath({wpTargetList = {
    "hr_pit_exit",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "wpGrid2"
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
    "wpGrid2"
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
    "wpGrid3"
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
    "wpGrid3"
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
    "wpGrid4"
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
    "wpGrid4"
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
    "wpGrid5"
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
    "wpGrid5"
    },
    raceMode = "on", avoidCars = "on", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6});
    ai.driveInLane("off");
    ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});

-- RACE
ai.driveUsingPath({wpTargetList = {
    "hr_start",
    "quickrace_wp6",
    "hr_bridge6",
    "hr_bridge5",
    "quickrace_wp4",
    "quickrace_wp11",
    "hr_start"
}, raceMode = "on", avoidCars = "on", noOfLaps = 4, aggression = 2, safetyDistance = 0.2, lateralOffsetRange = 0.4, lateralOffsetScale = 0.5, shortestPathBias = 0.6}); 
ai.driveInLane("off"); 
ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05});
