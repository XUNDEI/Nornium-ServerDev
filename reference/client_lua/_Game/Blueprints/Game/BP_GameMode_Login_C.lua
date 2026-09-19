require "UnLua"

---@type BP_GameMode_City_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    self.LevelName = "City1BusinessCenter"
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:AddSubLevelName(self.LevelName)
    --强制关闭socket连接
    local Client = require "Network.Client"
    if Client then
        Client:close()
    end
end 

function M:ReceiveEndPlay()
end


return M