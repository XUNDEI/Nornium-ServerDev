require "UnLua"
require "Common.TableUtil"

local UIUtils = require("_Game.Utils.UIUtils")
local AttributeConfig = require("ClientDatas.d_attributes")
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local ListItemDataPath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'

---@type UI_CharaterSystem_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

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
    --退出按钮
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)

    --生成器
    self.ListView.BP_OnEntryInitialized:Clear()
    self.ListView.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ListView.BP_OnItemClicked:Clear()
    self.ListView.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
end

function M:SetBackUI(beforeUI, roleData)
    self.BackUI = beforeUI
    self.CharacterInfo = roleData
    self:RefreshUI()
end

function M:RefreshUI()
    local ItemSourcePath = "'/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_ListRoleData.BP_ListRoleData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)

    self.ItemDataSource = {}

    local allAttr, baseAttr, attrEx = UIUtils.GetCharacterAllAttr(self.CharacterInfo.character_id, true)
    --修正要显示的属性(合并和显示的)
    self.AtrributeData = {}
    for k, v in pairs(allAttr) do
        local attrConfig = AttributeConfig[k]
        print('---atrr:' .. tostring(attrConfig.attribute) .. ', value:' .. tostring(v))
        if (attrConfig.showType == 1) or (attrConfig.showType == 2 and v > 0.00000001) then
            local attrInfo = {
                attrId = k,
                allAttrValue = v,
                baseAttrValue = baseAttr[k] or 0,
                attrExValue = attrEx[k] or 0,
                config = attrConfig
            }
            table.insert(self.AtrributeData, attrInfo)
        end
    end
    if #self.AtrributeData > 2 then
        table.sort(self.AtrributeData, function(a, b)
            return a.config.showOrder < b.config.showOrder
        end)
    end

    for idx, attrInfo in ipairs(self.AtrributeData) do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = idx
        ItemData.ItemId = attrInfo.atrrId
        table.insert(self.ItemDataSource, ItemData)
    end

    self.ListView:ClearListItems()
    self.ListView:BP_SetListItems(self.ItemDataSource)
end

----------------------------------------------------------------------
---ui event
function M:BP_OnEntryInitialized(item, widget)
    local baseAttrInfo = self.AtrributeData[item.Index]
    --背景图片
    widget.Img_Bg:SetVisibility((item.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", baseAttrInfo.config.attrIcon, baseAttrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        widget.Img_PropertyType:SetBrushFromAtlasInterface(iconObj)
    end

    --属性名字
    widget.Text_PropertyTypeName:SetText(Database.L10n(baseAttrInfo.config.attrName))
    local isHundred = false
    if baseAttrInfo.config.types == UIUtils.AttributeType.OverAHundred or 
        baseAttrInfo.config.types == UIUtils.AttributeType.InAHundred then
        isHundred = true
    end
    --all property
    local allValue = isHundred and string.format("%.1f", baseAttrInfo.allAttrValue * 100) or string.format("%d", math.modf(baseAttrInfo.allAttrValue))
    widget.Text_AllProperty:SetText(isHundred and (allValue .. '%') or allValue)
    --base property
    local baseValue = isHundred and string.format("%.1f", baseAttrInfo.baseAttrValue * 100) or string.format("%d", math.modf(baseAttrInfo.baseAttrValue))
    widget.Text_BaseProperty:SetText(isHundred and (baseValue .. '%') or baseValue)
    --add property
    local exValue = isHundred and string.format("%.1f", baseAttrInfo.attrExValue * 100) or string.format("%d", math.modf(baseAttrInfo.attrExValue))
    widget.Text_AddProperty:SetText("+" .. (isHundred and (exValue .. '%') or exValue))
end

function M:BP_OnItemClicked(item)

end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.BackUI = nil
    end
end


InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

return M
