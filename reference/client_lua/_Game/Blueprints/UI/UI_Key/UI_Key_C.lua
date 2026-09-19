local InputUtils = require "_Game.Utils.Input.InputUtils"
local BP_GameInstance_C = require "_Game.Blueprints.Game.BP_GameInstance_C"

---@type UI_Key_C
local M = UnLua.Class()

function M:Construct()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.platform = gameInstance.LastInputControllerType

    self:UpdateKeyImage()

    MessageManager:GetInstance():AddListener(BP_GameInstance_C.ControllerPlatformChanged, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(BP_GameInstance_C.ControllerPlatformChanged, self)
end

local GAMEPAD_MAPPING_PREFIX = "GamePad"

function M:UpdateKeyImage()
    -- 设置了mappingname的是UI上显示用的，否则是设置里的
    if self.MappingName ~= "" then
        local mappingName = self.MappingName
        if self.platform ~= InputUtils.Platform.PC then
            mappingName = GAMEPAD_MAPPING_PREFIX .. mappingName
        end
        local Mapping = InputUtils.GetMapping(self, mappingName)

        self:ShowKey(Mapping.CurrentKey)
    else
        if self.Key then
            self:ShowKey(self.Key)
        end
    end
end

---@param self UI_Key_C
M[BP_GameInstance_C.ControllerPlatformChanged] = function(self, Platform)
    if self.MappingName ~= "" then
        self.platform = Platform
    elseif self.platform ~= InputUtils.Platform.PC and Platform ~= InputUtils.Platform.PC then
        self.platform = Platform
    end
    self:UpdateKeyImage()
end

--- 设置那边会用到的显示按键
---@param Key FKey
function M:ShowKey(Key)
    self.Key = Key
    local keyAsset = InputUtils.GetKeyAsset(Key, self.platform)

    self.Img:SetBrushFromAtlasInterface(keyAsset)
    self.Img:SetVisibility(keyAsset and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
end

return M
