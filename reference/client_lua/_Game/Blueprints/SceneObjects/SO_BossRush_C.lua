--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_BossRush_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    if not M.UI_BossRush_Main then
        M.UI_BossRush_Main = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_Main.UI_BossRush_Main_C')
        M.UI_BossRush_MainRef = UnLua.Ref(M.UI_BossRush_Main)
    end

    self.Overridden.ReceiveBeginPlay(self)
end

M["On Overlap"] = function(self)
    UIManager:GetInstance():ClearInteractOption()
    UIManager:GetInstance():AddInteractOption(self, 268, function()
        self:OnClicked_OptionItem()
    end)
end

M["End Overlap"] = function(self)
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnClicked_OptionItem(Item, Index)
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9027) then
        local bossRushUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_Main)
    
        UIManager:GetInstance():AddUI(bossRushUI)
    
        bossRushUI:Setup()
    end 
end

return M
