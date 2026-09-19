
require "Global"
require "UnLua"

local Database = require "_Game.Utils.Database"
local UIUtils = require "_Game.Utils.UIUtils"

---@type BP_PlayerController_City_UniverseBridge_C
local M = Class()

function M:Initialize()

end

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)

    self:AddSkipButton()
end

function M:ReceiveEndPlay()
    UIManager:GetInstance():OnEndPlay()
end

function M:AddSkipButton()
    local widgetClass = LoadObject('/Game/_Game/Blueprints/UI/UI_Menu/UI_Skip.UI_Skip_C')
    ---@type UI_Skip_C
    local skipUI = NewObject(widgetClass)
    UIManager:GetInstance():AddUI(skipUI)

    skipUI.SkipBtn.Text:SetText(Database.L10n(99300001))

    skipUI.SkipBtn.SKIP.OnClicked:Add(skipUI.SkipBtn.SKIP, function()
        self:OnSequenceEnd()
    end)
    self.Btn_Skip = skipUI
end

function M:OnPlaySequenceEnd()
    if self.Btn_Skip then
        UIManager:GetInstance():RemoveUI(self.Btn_Skip)
    end
end

return M
