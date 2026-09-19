require "UnLua"
local Client = require "Network.Client"

---@type BP_GameMode_Speak_C
local M = UnLua.Class()

---------------------------Cmd---------------------------
function M:OnGHSCMD(msg)
    LOG_INFO("===请求GM命令:" .. tostring(msg))
    local array = string.split(msg, ' ')
    if array[1] == 'add_item' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'change_character' then
        self:ChangeCharacter(tonumber(array[2]))
    elseif array[1] == 'showchar' then
        print('===========showchar')
        MessageManager:GetInstance():Broadcast("showchar")
    elseif array[1] == 'add_character' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'openstory' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:OpenStory(tonumber(array[2]))
    elseif array[1] == 'opentoturial' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ShowTutorial(tonumber(array[2]), array[3])
    else
        self:GHSCMDLogParamNotFound(array[1])
    end
    self.Overridden.OnGHSCMD(self, msg)
end

return M