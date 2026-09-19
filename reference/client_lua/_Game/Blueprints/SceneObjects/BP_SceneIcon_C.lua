--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local d_npc_icon = require("ClientDatas.d_npc_icon")

---@type BP_SceneIcon_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
function M:ReceiveBeginPlay()
    if self.TypeId ~= 0 then
        local icon_info = d_npc_icon[self.TypeId]
        local widgetObject = self.Widget:GetUserWidgetObject()
        if UE.UKismetSystemLibrary.IsValid(widgetObject) then
            local widget = widgetObject:Cast(UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Scene_NPCIcon.UI_Scene_NPCIcon_C"))
            if widget then
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s', icon_info.pathIcon))
                if itemRarityPic then
                    widget.Image_84:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
        end
    end
end

-- function M:UserConstructionScript()
-- end

-- function M:ReceiveBeginPlay()
-- end

-- function M:ReceiveEndPlay()
-- end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
