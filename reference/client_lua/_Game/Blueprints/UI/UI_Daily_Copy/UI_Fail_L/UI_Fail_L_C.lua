--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Fail_L_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}
function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.Close)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.Image_83.OnMouseButtonDownEvent:Bind(self, function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:LoadBackLevel()
        self:Close()
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    self:PlayAnimationForward(self.vfxIn, 1, false)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
