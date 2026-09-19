--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_Tree_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not controller.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitIsBlock = true
    end
    controller.BP_PlayerController_City_UniverseBridge.CanScale = false
end

function M:Destruct()
    if self.InitIsBlock then
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        if not controller.BP_PlayerController_City_UniverseBridge then
            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        end
        self.InitIsBlock = false
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
