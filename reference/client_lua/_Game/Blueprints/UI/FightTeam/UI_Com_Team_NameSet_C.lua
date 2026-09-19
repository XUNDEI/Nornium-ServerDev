local Database = require("_Game.Utils.Database")
--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"
local NameUtil = require("_Game.Utils.NameUtil")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Com_Team_NameSet_C
local UI_Com_Team_NameSet_C = Class()

UI_Com_Team_NameSet_C.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(UI_Com_Team_NameSet_C)

--构造函数
function UI_Com_Team_NameSet_C:Construct()
    self:InitData()
    self:InitUI()
end 

function UI_Com_Team_NameSet_C:Destruct()
end

function UI_Com_Team_NameSet_C:InitUI()
    self.CancelButton.OnGHSClicked:Clear()
    self.CancelButton.OnGHSClicked:Add(self, self.OnClicked_CancelButton)

    self.OKButton.OnGHSClicked:Clear()
    self.OKButton.OnGHSClicked:Add(self, self.OnClicked_OKButton)

    self.TeamNameEdit.OnTextChanged:Clear()
    self.TeamNameEdit.OnTextChanged:Add(self, self.OnTextChanged_TeamNameEdit)

    --self.Tips:SetText("")
end

function UI_Com_Team_NameSet_C:InitData()
    --self.IsValidStringTip = "支持中文、英文、数字，不支持符号"
    --self.IsEmptyStringTip = "名字不能为空"
end

function UI_Com_Team_NameSet_C:SetBackUI(ui)
    self.BackUI = ui
end

function UI_Com_Team_NameSet_C:SetTeamName(TeamName)
    self.TeamNameEdit:SetText(TeamName)
    self.OKButton:SetIsEnabled(true)
end

function UI_Com_Team_NameSet_C:IsValidString(s)
    if not s or type(s) ~= 'string' or s == "" then 
        return true
    end
    local invalid_str = "。（）@’‘【】&！、《》/？…"
    for i = 1, utf8.len(s) do
        local char = utf8.sub(s, i, i + 1)
        local c = string.byte(char, 1)
        if c >= 0x00 and c <= 0x7F then
            if string.find(char, "[^A-Za-z0-9]") ~= nil then
                return false
            end
        elseif string.find(invalid_str, char, 1, true) ~= nil then
            return false
        end
    end
    return true
end
--------------------------------------------
---
function UI_Com_Team_NameSet_C:OnClicked_CancelButton()
    if self.BackUI then
        self.BackUI:SetAllChairListCollision(true)
    end
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(UI_Com_Team_NameSet_C, InputAssets.IA_Back, UE.ETriggerEvent.Completed, UI_Com_Team_NameSet_C.OnClicked_CancelButton)

function UI_Com_Team_NameSet_C:OnTextChanged_TeamNameEdit()
    self.OKButton:SetIsEnabled(self.TeamNameEdit:GetText() ~= "")
end

function UI_Com_Team_NameSet_C:OnClicked_OKButton()
    --判断文字内容
    local Text = self.TeamNameEdit:GetText()

    local meetCriteria, warning = NameUtil.MeetCriteria(Text, {
        { NameUtil.LengthLimit, 8 },
        { NameUtil.NoSpace },
        { NameUtil.NoFilterWord },
    })

    if not meetCriteria then
        UIManager:GetInstance():Notify(Database.L10n(warning))
    else
        --self.Tips:SetText("")
        --TODO 保存当前队伍名字
        if self.BackUI then
            self.BackUI:SetAllChairListCollision(true)
            self.BackUI:ChangeTeamName(Text)
            self.BackUI = nil
        end

        UIManager:GetInstance():RemoveUI(self)
    end
end

return UI_Com_Team_NameSet_C