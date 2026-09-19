local Database = require("_Game.Utils.Database")
local NameUtil = require("_Game.Utils.NameUtil")
local Protos = require("Helper.Protos")
local Client = require "Network.Client"
local PlayerSystem = require "Module.Player.PlayerSystem"
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Name_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()  
    self.determine.OnClicked:Add(self, self.Confirm)
    self.Name.OnTextChanged:Add(self, function()
        self.determine:SetIsEnabled(self.Name:GetText() ~= "")
    end)

    self.determine:SetIsEnabled(self.Name:GetText() ~= "")

    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHANGE_PLAYER_NAME, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHANGE_PLAYER_SEQUENCE_NAME, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHANGE_PLAYER_NAME, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHANGE_PLAYER_SEQUENCE_NAME, self)
end

function M:Confirm()
    local Text = self.Name:GetText()

    local meetCriteria, warning = NameUtil.MeetCriteria(Text, {
        { NameUtil.LengthLimit, 8 },
        { NameUtil.NoSpace },
        { NameUtil.NoFilterWord },
    })

    if not meetCriteria then
        UIManager:GetInstance():Notify(Database.L10n(warning))
    else
        Client.send(Protos.REQ_CHANGE_PLAYER_SEQUENCE_NAME, { player_sequence_name = Text })
        Client.send(Protos.REQ_CHANGE_PLAYER_NAME, { player_name = Text })
    end
end

---@param self UI_Name_C
---@param parsed_msg ResChangePlayerSequenceNameMessage
M[Protos.RES_CHANGE_PLAYER_SEQUENCE_NAME] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        PlayerSystem:GetInstance().PlayerInfo.player_sequence_name = self.Name:GetText()
    end
end

---@param self UI_Name_C
---@param parsed_msg ResChangePlayerSequenceNameMessage
M[Protos.RES_CHANGE_PLAYER_NAME] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        PlayerSystem:GetInstance().PlayerInfo.player_name = self.Name:GetText()
    end
end

return M
