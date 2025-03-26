ai.driveUsingPath(
    {wpTargetList = {
        "wp_test1",
        "wp_test2",
        "wp_test3"
    },
        raceMode = "off",
        avoidCars = "on",
        noOfLaps = 4,
        aggression = 1.5,
        safetyDistance = 0.2,
        lateralOffsetRange = 1,
        lateralOffsetScale = 0.8,
        shortestPathBias = 0.5
})




-----------------


ai.driveUsingPath({
    wpTargetList = {
        "DR19534_9",
        "DR19534_18",
        "DR19534_36",
        "quickrace_wp10",
        "wpForest2",
        "wpForestRoad1",
        "DR19543_49",
        "wpForest3",
        "DR19543_40",
        "wpForest4",
        "DR19543_2",
        "hr_bridge10",
        "hr_bridge11",
        "hr_bridge12",
        "awWWWWWW",
        "DR19127_6",
        "wpTruckParking4"
    }, 
    raceMode = "off",
    avoidCars = "on", driveInLane = "on", 
    aggression = 0.35, 
    safetyDistance = 0.5, lateralOffsetRange = 0.4, lateralOffsetScale = 0.8, shortestPathBias = 1,
    routeSpeed = 40,
    routeSpeedMode = 'limit',
    wpSpeeds = {DR19543_2 = 8, hr_bridge10 = 8, hr_bridge11 = 8, hr_bridge12 = 8, awWWWWWW = 5, DR19127_6 = 5, wpTruckParking4 = 5}
})

ai.driveUsingPath({
    wpTargetList = {
        "hr_bridge13",
        "awWWWWWW",
        "DR19127_6",
        "wpTruckParking4"
    }, 
    raceMode = "off",
    avoidCars = "on", driveInLane = "on", 
    aggression = 0.35, 
    safetyDistance = 0.5, lateralOffsetRange = 0.4, lateralOffsetScale = 0.8, shortestPathBias = 1,
    routeSpeed = 40,
    routeSpeedMode = 'limit'
})


ai.driveUsingPath({
    wpTargetList = {
        "DR19131_3",
        "wpTruckParkingAccess1",
        "wpTruckParking1"
    }, 
    raceMode = "off",
    avoidCars = "on", driveInLane = "on", 
    aggression = 0.35, 
    safetyDistance = 0.5, lateralOffsetRange = 0.4, lateralOffsetScale = 0.8, shortestPathBias = 1,
    routeSpeedMode = 'limit'
})

ai.driveUsingPath({
    wpTargetList = {
        "DR19132_8",
        "wpTruckParkingAccess2",
        "wpTruckParking2"
    }, 
    raceMode = "off",
    avoidCars = "on", driveInLane = "on", 
    aggression = 0.35, 
    safetyDistance = 0.5, lateralOffsetRange = 0.4, lateralOffsetScale = 0.8, shortestPathBias = 1,
    routeSpeedMode = 'limit'
})

ai.driveUsingPath({
    wpTargetList = {
        "DR19132_8",
        "DR19132_11",
        "wpTruckParking3"
    }, 
    raceMode = "off",
    avoidCars = "on", driveInLane = "on", 
    aggression = 0.35, 
    safetyDistance = 0.5, lateralOffsetRange = 0.4, lateralOffsetScale = 0.8, shortestPathBias = 1,
    routeSpeedMode = 'limit'
})