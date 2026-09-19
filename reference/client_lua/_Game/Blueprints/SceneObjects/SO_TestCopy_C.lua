--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_TestCopy_C
local M = UnLua.Class()

local UIUtils = require('_Game.Utils.UIUtils')

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
    self.BP_Interactive.ChildActor.Lua_OnOverlap:Add(self, self.OnOverlap)
    self.BP_Interactive.ChildActor.LUa_EndOverLap:Add(self, self.EndOverLap)

    self.OptionItemList = {}

    self.AllLevelInfo = self:GetAllLevelConfig()
end

function M:ReceiveEndPlay()

end

function M:ClearAllOption()
    if self.OptionItemList then
        UIManager:GetInstance():RemoveInteractOptionByObject(self)
        self.OptionItemList = {}
    end
end

function M:OnOverlap()
    UIManager:GetInstance():ClearInteractOption()
    for i, config in ipairs(self.AllLevelInfo) do
        local item = UIManager:GetInstance():AddInteractOption(config.levelName, function()
            self:OnOptionItemClicked(nil, i)
        end)
        table.insert(self.OptionItemList, item)
    end
end

function M:EndOverLap()
    self:ClearAllOption()
end


function M:OnOptionItemClicked(option, index)
    self:ClearAllOption()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local config = self.AllLevelInfo[index + 1]
    if config then
        local player = playerController:K2_GetPawn()
        if player then
            gameInstance.PlayerInCity = player:GetTransform()
        end
        gameInstance:OpenTempCopy(config.id)
    end
end

function M:GetAllLevelConfig()
    local result = {}
    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    for _, v in pairs(d_levels_challenge) do 
        if v.levelTypes == UIUtils.ECopyType.ECopyType_BaseTeach then
            table.insert(result, v)
        end
    end
    if table.count(result) > 1 then
        table.sort(result, function(a, b) 
            return a.id < b.id
        end)
    end
    return result
end

return M
