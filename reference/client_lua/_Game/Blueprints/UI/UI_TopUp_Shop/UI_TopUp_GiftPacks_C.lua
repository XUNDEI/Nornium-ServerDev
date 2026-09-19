--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_TopUp_GiftPacks_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxquit, 1, false)
    self.ImageBG:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
end

InputUtils.RegisterMouseEvent(M)
InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.ItemList.BP_OnEntryInitialized:Clear()
    self.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.ItemList.BP_OnItemClicked:Clear()
    self.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.ImageBG.OnMouseButtonDownEvent:Unbind()
    self.ImageBG.OnMouseButtonDownEvent:Bind(self, function()
        self:OnClicked_Exit()
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    self.OKButton.OnGHSClicked:Add(self, self.OnClick_OK)
end

function M:RefreshUI(item_data)
    self.ItemData = item_data
    if item_data and item_data.config then
        self.TextName:SetText(Database.L10n(item_data.config.goodsName))
        local num = string.format("%.2f", self.ItemData.config.price[1] / 10000)
        self.TextPrice:SetText(num)
        if item_data.config.goodsPath ~= "" then
            local itemPic = LoadObject(string.format('/Game/_Game/%s', item_data.config.goodsPath))
            if itemPic then
                self.Icon:SetBrushFromAtlasInterface(itemPic)
            end
        end

        if item_data.config.limitTimes > 0 then
            if item_data.config.limitType == 1 then --次数限购
                self.TextLimitType:SetText(Database.L10n(824000001))
            elseif item_data.config.limitType == 2 then --每日限购
                self.TextLimitType:SetText(Database.L10n(824000002))
            elseif item_data.config.limitType == 3 then --每周限购
                self.TextLimitType:SetText(Database.L10n(824000003))
            elseif item_data.config.limitType == 4 then --每月限购
                self.TextLimitType:SetText(Database.L10n(824000004))
            end
        end

        local str_limit = string.format("%d/%d", self.ItemData.purchase_times or 0, self.ItemData.config.limitTimes)
        self.TextLimit_3:SetText(str_limit)

        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local item_num = #item_data.config.goods / 3
        local ItemDataSource = {}
        for i = 1, item_num do
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = item_data.config.goods[i * 3 - 2]
            table.insert(ItemDataSource, ItemData)
        end
        self.ItemList:ClearListItems()
        self.ItemList:BP_SetListItems(ItemDataSource)
    end
    self:PlayAnimationForward(self.vfxin, 1, false)
end

function M:BP_OnEntryInitialized(item, widget)
    local itemConfig = Database.Query("d_bag_item", item.ItemId)
    widget.ItemPanel:SetRenderOpacity(1)
    if itemConfig then
        widget.TextName:SetText(Database.L10n(itemConfig.itemName))
        widget.TextNum:SetText(self.ItemData.config.goods[item.Index * 3])
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if itemConfig.iconPath and itemConfig.iconPath ~= '' then
            local strArr = string.split(itemConfig.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end

        widget.Img_bg.OnMouseButtonDownEvent:Unbind()
        widget.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(item.ItemId)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)
    end
end

function M:BP_OnItemClicked(item)
end

function M:OnClick_OK()
    local msg = {}
    msg.mall_id = self.ItemData.mall_id
    msg.mall_item_id = self.ItemData.mall_item_id
    msg.mall_item_count = 1
    msg.last_auto_refresh_seconds = self.ItemData.last_auto_refresh_seconds
    msg.steam_id = self.ItemData.steam_id
    msg.steam_current_game_language = self.ItemData.steam_current_game_language
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    msg.access_token = gameInstance.key
    Client.send("req_mall_buy", msg)
    UIManager:GetInstance():RemoveUI(self)
    print("======点击购买:" .. tostring(msg))
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_TopUp_Shop')
    if ui and UE.UKismetSystemLibrary.IsValid(ui) then
        ui.WaitPanel:SetVisibility(UE.ESlateVisibility.Visible)
        print("======WaitPanel SetVisibility Visible")
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
