
setTimeOfDay("7:30");
be:queueAllObjectLua('ai.driveUsingPath({wpTargetList = {"wp48","wp50","wp76","wp121","wp122","wp67","wp65","wp64","wp131","wp54","wpPere6","wp85","wp86","wp88","wp91","wpPere7","wp93","wp39","wp42","wp43","wpPere5","wpPere1","wp178","wp126","a_south_1water_a18","a_south_1water_a12","a_south_1water_a5","a_south_1water_a2","wpPere2","a_south_water_c3","wpPere3","a_e_straight_d2","a_e_straight_d10","wp70","wp30","DR60066_4","wp31","wp51","wp128","wp48"}, noOfLaps = 4, aggression = 1})'); be:queueAllObjectLua('ai.setAvoidCars("off")'); be:queueAllObjectLua('ai.driveInLane("off")'); be:queueAllObjectLua('ai.setParameters({turnForceCoef = 1.5, springForceIntegratorDispLim = 0.05})');

ai.driveUsingPath({wpTargetList = {
"wp48",
"wp50",
"wp76",
"wp121",
"wp122",
"wp67",
"wp65",
"wp64",
"wp131",
"wp54",
"wpPere6",
"wp85",
"wp86",
"wp88",
"autojunction_681",
"wpPere7",
"wp93",
"wp39",
"wp42",
"wp43",
"wpPere5",
"DR39109_5",
"autojunction_111",
"wp126",
"a_south_1water_a18",
"a_south_1water_a12",
"a_south_1water_a5",
"a_south_1water_a2",
"wpPere2",
"a_south_water_c3",
"wpPere3",
"a_e_straight_d2",
"a_e_straight_d10",
"wp70",
"wp30",
"DR39771_3",
"wp31",
"wp51",
"wp128"
}, wpSpeeds = {wp50 = 28, wp76 = 28, wp121 = 18, wp122 = 18, wp67 = 11, wp65 = 11, wp64 = 12.5, wp131 = 12.5, wp54 = 28, wpPere6 = 15, wp85 = 11, wp86 = 12.5, wp88 = 12.5, wpPere7 = 12.5, wp93 = 11, wp42 = 25, wp43 = 11, wpPere5 = 11, wpPere1 = 28, wp126 = 28, a_south_1water_a2 = 18, wpPere2 = 11, wpPere3 = 11,a_e_straight_d10 = 18, wp70 = 11, wp30 = 11, DR397771_3 = 16, wp31 = 11}, noOfLaps = 4, aggression = 1});


be:queueAllObjectLua('ai.setAggression(0.7)');
be:queueAllObjectLua('ai.driveInLane("on")'); 
be:queueAllObjectLua('ai.setAggression(math.random(70,90)/100)');
be:queueAllObjectLua('ai.setAvoidCars("off")'); 
be:queueAllObjectLua('ai.setParameters({lookAheadKv = math.random(40,70)/100, driveStyle = "default", awarenessForceCoef = math.random(5,20)/100, turnForceCoef = 2, planErrorSmoothing = false, springForceIntegratorDispLim = 0.1, edgeDist = -0.5})'); 


ai.driveUsingPath({wpTargetList = {
"startGrid_WP"
}, wpSpeeds = {}, noOfLaps = 1, aggression = 0.2});