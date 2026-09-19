local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local MessageManager = require "Framework.Updater.MessageManager"

---@type UI_STT_Button_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
end

function M:OnClicked_Button(item)
    local msg = {}
    msg.task_id = item.TaskId
    MessageManager:GetInstance():Broadcast("OnMsg_STT_Button", msg)
end

function M:InitButton(item)
    item.Button.OnClicked:Add(self, function(self)
        self:OnClicked_Button(item)
    end)
end

--function M:PreConstruct(IsDesignTime)
--end

-- function M:Construct()
-- end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
