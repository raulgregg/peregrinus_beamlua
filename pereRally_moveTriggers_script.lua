trajectory = "inbound"

local triggerTable = {};
triggerTable['trigger1'] = 74195;
triggerTable['trigger2'] = 74196;
triggerTable['trigger3'] = 74197;
triggerTable['trigger4'] = 74198;
triggerTable['trigger5'] = 74199;
triggerTable['trigger6'] = 74200;
triggerTable['trigger7'] = 74201;
triggerTable['trigger8'] = 74202;


local positionTable = {};
positionTable['trigger1'] = 126.404;
positionTable['trigger2'] = 128.047;
positionTable['trigger3'] = 129.123;
positionTable['trigger4'] = 126.006;
positionTable['trigger5'] = 126.167;
positionTable['trigger6'] = 129.133;
positionTable['trigger7'] = 128.011;
positionTable['trigger8'] = 127.387;

local trajectoryTable = {};
trajectoryTable['trigger1'] = "outbound";
trajectoryTable['trigger2'] = "outbound";
trajectoryTable['trigger3'] = "outbound";
trajectoryTable['trigger4'] = "outbound";
trajectoryTable['trigger5'] = "inbound";
trajectoryTable['trigger6'] = "inbound";
trajectoryTable['trigger7'] = "inbound";
trajectoryTable['trigger8'] = "inbound";

local function updateTriggerPosition(data)
    if data.event == "enter" then
        for k, v in pairs(triggerTable) do
            trigger = k
            obj = scenetree.findObjectById(v)
            pos = obj:getPosition()
            if trajectoryTable[trigger] == trajectory then 
                pos.z = positionTable[trigger] + 50
                obj:setPosition(pos)
            else 
                pos.z = positionTable[trigger]
                obj:setPosition(pos)
            print("Trigger ".. k .. " for trajectory" .. trajectory .. " updated")
            end
        end
    end
end
return updateTriggerPosition