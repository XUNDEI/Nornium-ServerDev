local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local QuestSystem = require "Module.Quest.QuestSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Login_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Construct()
    self:InitUI()
    self:InitData()
    self.Overridden.Construct(self)
end

function M:Destruct()
   
end

function M:InitUI()
    self.Btn_Cancel.OnGHSClicked:Add(self, self.OnClicked_Btn_Cancel)
end

function M:InitData()

end

function M:RefreshUI(id)
    local d_SystemDescription = require('ClientDatas.d_SystemDescription')
    local config = d_SystemDescription[id]
    if config and config.text > 0 then
        self.ScrollBox_Tips:ClearChildren()
        local str = Database.L10n(config.text)
        local strArr = string.split(str, '|')
        for _, strValue in ipairs(strArr) do 
            local valueArr = string.split(strValue, '$')
            local subItem = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/Common/UI_SystemDes_Item.UI_SystemDes_Item_C'))
            subItem.Text_Title:SetText(valueArr[1] or '')
            subItem.Text_Content:SetText(valueArr[2] or '')
            self.ScrollBox_Tips:AddChild(subItem)
        end
    end
end

function M:OnClicked_Btn_Cancel()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Cancel)

return M