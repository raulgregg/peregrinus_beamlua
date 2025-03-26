setTimeOfDay("16:00");
be:queueAllObjectLua('ai.driveUsingPath({wpTargetList = {"DecalRoad47366_75", "DecalRoad47366_69", "DecalRoad47366_62", "DecalRoad47366_52", "DecalRoad47366_45", "DecalRoad47366_32", "DecalRoad47366_25", "DecalRoad47366_18", "DecalRoad47366_13", "DecalRoad47366_7", "DecalRoad47366_3", "DecalRoad47366_101", "DecalRoad47366_95", "DecalRoad47366_87", "DecalRoad47366_82", "DecalRoad47366_75"}, noOfLaps = 4, aggression = 0.5})'); be:queueAllObjectLua('ai.setAvoidCars("on")'); be:queueAllObjectLua('ai.driveInLane("off")'); be:queueAllObjectLua('ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05})')



be:queueAllObjectLua('ai.setAggression(0.7)');

be:queueAllObjectLua('ai.driveInLane("on")'); 
be:queueAllObjectLua('ai.setAggression(math.random(70,90)/100)');
be:queueAllObjectLua('ai.setAvoidCars("on")'); 
be:queueAllObjectLua('ai.setParameters({lookAheadKv = math.random(40,70)/100, driveStyle = "default", awarenessForceCoef = math.random(5,20)/100, turnForceCoef = 2, planErrorSmoothing = false, springForceIntegratorDispLim = 0.1, edgeDist = -0.5})'); 

