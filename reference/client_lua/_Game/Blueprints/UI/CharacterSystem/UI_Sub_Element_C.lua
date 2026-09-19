require "UnLua"
require "Common.TableUtil"

local UIUtils = require('_Game.Utils.UIUtils')
local Database = require "_Game.Utils.Database"

---@type UI_CharaterSystem_C
local M = Class()

--构造函数
function M:Construct()
    self:InitData()
    self:InitUI()
end

function M:Destruct()
   
end

function M:InitData()

end

function M:InitUI()
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
end

function M:SetBackUI(beforeLv, charInfo)
    self.BackUI = beforeLv

    local curElementId = charInfo.config.element
    local relativeElementId = UIUtils.EElementRelation[curElementId]
    local name = Database.L10n(UIUtils.EElementWord[curElementId])
    local relativeName = Database.L10n(UIUtils.EElementWord[relativeElementId])
    self.Text_CurTypeName:SetText(string.format('<span color="#%s">%s</>', UIUtils.EElementColor[curElementId], name))
    self.Text_RelativeTypeName:SetText(string.format('<span color="#%s">%s</>', UIUtils.EElementColor[relativeElementId], relativeName))
    
    local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/element_%s_s_png.element_%s_s_png", curElementId, curElementId)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.Image_135:SetBrushFromAtlasInterface(iconObj)
    end

    local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/element_%s_s_png.element_%s_s_png", relativeElementId, relativeElementId)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.Image_18:SetBrushFromAtlasInterface(iconObj)
    end
end 

----------------------------------------------------------------------
---ui event
function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.BackUI = nil
    end
end

return M