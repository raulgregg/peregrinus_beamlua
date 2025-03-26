ai.driveUsingPath({wpTargetList = {
    "lakeFarsoe_wp1",
    "lakeFarsoe_wp2",
    "lakeFarsoe_wp3",
    "lakeFarsoe_wp4",
    "lakeFarsoe_wp5",
    "lakeFarsoe_wp6",
    "lakeFarsoe_wp7",
    "lakeFarsoe_wp8",
    "lakeFarsoe_wp9",
    "lakeFarsoe_wp10",
    "lakeFarsoe_wp1"
    }, 
    raceMode = "on", avoidCars = "off", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.8, lateralOffsetScale = 0.9, shortestPathBias = 0.9});
    ai.driveInLane("off");
    ai.setParameters({lookAheadKv = 0.9, planErrorSmoothing = false, turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05, awarenessForceCoef =  math.random(90,150)/1000, driveStyle = "default"})






be:queueAllObjectLua('ai.driveUsingPath({wpTargetList = {"lakeFaroe_wp1","lakeFaroe_wp2","lakeFaroe_wp3","lakeFaroe_wp4","lakeFaroe_wp5","lakeFaroe_wp6","lakeFaroe_wp7","lakeFaroe_wp8","lakeFaroe_wp9","lakeFaroe_wp10","lakeFaroe_wp1"}, raceMode = "on", avoidCars = "off", noOfLaps = 2, aggression = 0.8, safetyDistance = 0.2, lateralOffsetRange = 0.8, lateralOffsetScale = 0.9, shortestPathBias = 0.9})');
be:queueAllObjectLua('ai.setParameters({lookAheadKv = 0.9, planErrorSmoothing = false, turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05, awarenessForceCoef =  math.random(90,150)/1000, driveStyle = "default"})');
be:queueAllObjectLua('ai.driveInLane("off");');