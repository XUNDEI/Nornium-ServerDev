--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require '_Game.Utils.Database'
local d_shop_type = require("ClientDatas.d_shop_type")
local MallSystem = require "Module.ShopSystem.MallSystem"
local PlayerSystem = require("Module.Player.PlayerSystem")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local MallType = 
{
    GiftPacks = 103,
    DressUp = 104,
    Furniture = 105,
    LowClassExchange = 106,
    HighClassExchange = 107,
    TopUp = 201,
    MonthCard = 202,
    Passport = 203,
}

local LimitType = 
{
    LimitLess  = 0,
    TimeLimit  = 1,
    DayLimit   = 2,
    WeekLimit  = 3,
    MonthLimit = 4,
}

local NoticeType = 
{
    NotHasChar = 458,
    FullChar = 459,
    MonthCardLimit = 491,
    BuildNotHasChar = 501,
    FullCharSkin = 503,
}

---@type UI_TopUp_Shop_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

-- function M:Initialize(Initializer)
--     print(self.ImageBG)
-- end

-- function M:PreConstruct(IsDesignTime)
--     print(self.ImageBG)
-- end

function M:Construct()
    --Top Up
    self.UI_TopUp_Panel.ItemList.BP_OnEntryInitialized:Clear()
    self.UI_TopUp_Panel.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnTopUpEntryInitialized(item, widget)
    end)
    self.UI_TopUp_Panel.ItemList.BP_OnItemClicked:Clear()
    self.UI_TopUp_Panel.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnTopUpItemClicked(item)
    end)


    --Other mall
    self.UI_GiftPacks_Panel.ItemList.BP_OnEntryInitialized:Clear()
    self.UI_GiftPacks_Panel.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnOtherEntryInitialized(item, widget)
    end)
    self.UI_GiftPacks_Panel.ItemList.BP_OnItemClicked:Clear()
    self.UI_GiftPacks_Panel.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnOtherItemClicked(item)
    end)

    self.PastTime = 0
    self.MallType = MallType.GiftPacks
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    self.Btn_AddUp.OnGHSClicked:Add(self, self.OnClicked_AddUp)
    self.UI_TopUp_MonthCard.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn)
    self:InitData()
    self:InitUI()

    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Mall_Info", self)
    MessageManager:GetInstance():AddListener("OnMsg_Res_Mall_Buy", self)
    MessageManager:GetInstance():AddListener("OnMsg_Res_Finish_Order", self)
end

function M:Destruct()
    if self.NPC then
        self.NPC:K2_DestroyActor()
    end
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Mall_Info", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Res_Mall_Buy", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Res_Finish_Order", self)
end

function M:InitData()
    self.mall_infos = {}
    for _, mall_info in ipairs(MallSystem:GetInstance().MallInfo.mall_infos) do
        local new_mall_info = {}
        local new_mall_item_infos = {}
        new_mall_info.last_auto_refresh_seconds = mall_info.last_auto_refresh_seconds
        new_mall_info.mall_id = mall_info.mall_id
        new_mall_info.mall_purchase_limit_infos = {}
        for _, mall_item in ipairs(mall_info.mall_item_infos) do
            local config = Database.Query("d_mall", mall_item.mall_item_id)
            if config and config.show == 1 then
                if config.shopType == MallType.TopUp
                    or config.shopType == MallType.MonthCard
                    or config.shopType == MallType.Passport then
                    table.insert(new_mall_item_infos, mall_item)
                else
                    --要进行显示时间判断 showTime和removeTime之间可以进行显示 onSaleTime和removeTime之间可以进行购买
                    if config.showTime ~= '' and config.removeTime ~= '' then
                        local showTimeStr = config.showTime
                        local year, month, day, hour, min, sec = string.match(showTimeStr, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                        local showTimestamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec) })
                        year, month, day, hour, min, sec = string.match(config.removeTime, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                        local removeTimestamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec) })
                        local utc = PlayerSystem:GetInstance():GetServerTime()
                        if showTimestamp < utc and utc < removeTimestamp then
                            table.insert(new_mall_item_infos, mall_item)
                        end
                    end
                end
            end
        end
        
        for _, mall_purchase_limit_info in ipairs(mall_info.mall_purchase_limit_infos) do
            --已售罄的物品信息补充到当前显示物品中
            new_mall_info.mall_purchase_limit_infos[mall_purchase_limit_info.mall_item_id] = mall_purchase_limit_info
            local find = false
            for index, value in ipairs(new_mall_item_infos) do
                if mall_purchase_limit_info.mall_item_id == value.mall_item_id then
                    find = true
                end
            end
            if not find then
                local mall_item = {}
                mall_item.mall_item_id = mall_purchase_limit_info.mall_item_id
                local config = Database.Query("d_mall", mall_purchase_limit_info.mall_item_id)
                if config and config.show == 1 then
                    table.insert(new_mall_item_infos, mall_item)
                end
            end
        end

        for _, mall_item in ipairs(new_mall_item_infos) do
            local config = Database.Query("d_mall", mall_item.mall_item_id)
            if config then
                local purchase_times = 0
                if new_mall_info.mall_purchase_limit_infos[config.id] then
                    purchase_times = new_mall_info.mall_purchase_limit_infos[config.id].purchase_times
                end
                local isSoldOut = config.limitTimes > 0 and config.limitTimes - purchase_times <= 0
                mall_item.isSoldOut = isSoldOut
                mall_item.order = config.order
            end
        end

        table.sort(new_mall_item_infos, function(a, b)
            if a.isSoldOut ~= b.isSoldOut then
                if a.isSoldOut then
                    return false
                else
                    return true
                end
            else
                if a.order ~= b.order then
                    return a.order < b.order
                else
                    return a.mall_item_id < b.mall_item_id
                end
            end
        end)

        new_mall_info.mall_item_infos = new_mall_item_infos
        self.mall_infos[mall_info.mall_id] = new_mall_info
    end
end

function M:Tick(MyGeometry, InDeltaTime)
    --监视当前物品的上下架时间是否有变化
    if not self.PastTime then
        return
    end
    self.PastTime = self.PastTime + InDeltaTime
    if self.PastTime > 1 then
        self.PastTime = 0
        local mall_info = self.mall_infos[self.MallType]
        local need_refresh = false
        for _, mall_item in ipairs(mall_info.mall_item_infos) do
            local config = Database.Query("d_mall", mall_item.mall_item_id)
            if config.showTime ~= '' and config.removeTime ~= '' then
                local showTimeStr = config.showTime
                local year, month, day, hour, min, sec = string.match(showTimeStr, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                local showTimestamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec) })
                year, month, day, hour, min, sec = string.match(config.removeTime, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                local removeTimestamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec) })
                local utc = PlayerSystem:GetInstance():GetServerTime()
                if utc > removeTimestamp then
                    need_refresh = true
                end
            end
        end

        if need_refresh then
            self:InitData()
            self:RefreshCurrentPanel()
        end
    end
end

function M:InitUI()
    local shop_type_info = d_shop_type[self.MallType]
    local path = string.format("'/Game/_Game/Blueprints/NPCs/BP_NPC_Mall.BP_NPC_Mall_C'") 
    local playerClass = LoadClass(path)
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(400, 350, 100),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    self.TextSaler:SetText(Database.L10n(shop_type_info.npcName))
    self.TextSale:SetText(Database.L10n(shop_type_info.npcSpeak))
    
    self.GiftPacks.OnCheckStateChanged:Add(self, function(_, isOn) 
        if not isOn then return end
        self:TabSelected(MallType.GiftPacks)
    end)
    self.DressUp.OnCheckStateChanged:Add(self, function(_, isOn) 
        if not isOn then return end
        self:TabSelected(MallType.DressUp)
    end)
    
    self.MonthCard.OnCheckStateChanged:Add(self, function(_, isOn) 
        if not isOn then return end
        self:TabSelected(MallType.MonthCard)
    end)
    
    self.ExchangeShop.OnCheckStateChanged:Add(self, function(_, isOn) 
        if not isOn then return end
        self:TabSelected(MallType.LowClassExchange)
    end)

    self.TopUp.OnCheckStateChanged:Add(self, function(_, isOn) 
        if not isOn then return end
        self:TabSelected(MallType.TopUp)
    end)
    self.GiftPacks:SetIsCheckedAndFireEvent(true)
    self:vfx_In()
end

function M:ShowExchange()
    self.ExchangeShop:SetIsCheckedAndFireEvent(true)
    self.UI_GiftPacks_Panel.CheckBoxMall2:SetIsCheckedAndFireEvent(true)
end

function M:RefreshTopUpPanel()
    local ItemDataSource = {}
    local mall_info = self.mall_infos[MallType.TopUp]
    if mall_info then
        local ItemSourcePath =
        '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        for i, mall_item_info in ipairs(mall_info.mall_item_infos) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = mall_item_info.mall_item_id
            table.insert(ItemDataSource, ItemData)
        end
    end
    self.UI_TopUp_Panel.ItemList:ClearListItems()
    self.UI_TopUp_Panel.ItemList:BP_SetListItems(ItemDataSource)
    self.UI_TopUp_Panel:vfx_Switch()
end

function M:RefreshOtherPanel()
    local ItemDataSource = {}
    if self.MallType then
        if self.MallType == MallType.DressUp then
            self.UI_GiftPacks_Panel.TextName:SetText(Database.L10n(484))
            self.UI_GiftPacks_Panel.Text_Main_Selected:SetText(Database.L10n(460))
            self.UI_GiftPacks_Panel.Text_Main:SetText(Database.L10n(460))
            self.UI_GiftPacks_Panel.Text_Main_Selected_1:SetText(Database.L10n(485))
            self.UI_GiftPacks_Panel.Text_Main_1:SetText(Database.L10n(485))
            self.UI_GiftPacks_Panel.ButtonTab:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.UI_GiftPacks_Panel.CheckBoxMall1.OnCheckStateChanged:Clear()
            self.UI_GiftPacks_Panel.CheckBoxMall2.OnCheckStateChanged:Clear()
            self.UI_GiftPacks_Panel.CheckBoxMall1.OnCheckStateChanged:Add(self, function(_, isOn) 
                if not isOn then return end
                self:ChangeMall(MallType.DressUp)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end)
            self.UI_GiftPacks_Panel.CheckBoxMall2.OnCheckStateChanged:Add(self, function(_, isOn)
                if not isOn then return end
                self:ChangeMall(MallType.Furniture)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end)
            if not self.UI_GiftPacks_Panel.CheckBoxMall1:IsChecked() then
                self.UI_GiftPacks_Panel.CheckBoxMall1:SetIsCheckedAndFireEvent(true)
            else
                self:ChangeMall(MallType.DressUp)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end
        elseif self.MallType == MallType.LowClassExchange then
            self.UI_GiftPacks_Panel.TextName:SetText(Database.L10n(486))
            self.UI_GiftPacks_Panel.Text_Main_Selected:SetText(Database.L10n(487))
            self.UI_GiftPacks_Panel.Text_Main:SetText(Database.L10n(487))
            self.UI_GiftPacks_Panel.Text_Main_Selected_1:SetText(Database.L10n(488))
            self.UI_GiftPacks_Panel.Text_Main_1:SetText(Database.L10n(488))
            self.UI_GiftPacks_Panel.ButtonTab:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.UI_GiftPacks_Panel.CheckBoxMall1.OnCheckStateChanged:Clear()
            self.UI_GiftPacks_Panel.CheckBoxMall2.OnCheckStateChanged:Clear()
            self.UI_GiftPacks_Panel.CheckBoxMall1.OnCheckStateChanged:Add(self, function(_, isOn)
                if not isOn then return end
                self:ChangeMall(MallType.LowClassExchange)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end)
            self.UI_GiftPacks_Panel.CheckBoxMall2.OnCheckStateChanged:Add(self, function(_, isOn)
                if not isOn then return end
                self:ChangeMall(MallType.HighClassExchange)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end)
            if not self.UI_GiftPacks_Panel.CheckBoxMall1:IsChecked() then
                self.UI_GiftPacks_Panel.CheckBoxMall1:SetIsCheckedAndFireEvent(true)
            else
                self:ChangeMall(MallType.LowClassExchange)
                self.UI_GiftPacks_Panel:vfx_Switch()
            end
        elseif self.MallType == MallType.GiftPacks then
            self.UI_GiftPacks_Panel.TextName:SetText(Database.L10n(490))
            self.UI_GiftPacks_Panel.ButtonTab:SetVisibility(UE.ESlateVisibility.Hidden)
            local mall_info = self.mall_infos[self.MallType]
            if mall_info then
                local ItemSourcePath =
                '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
                local ItemClass = UE.UClass.Load(ItemSourcePath)
                for i, mall_item_info in ipairs(mall_info.mall_item_infos) do
                    local ItemData = NewObject(ItemClass)
                    ItemData.Index = i
                    ItemData.ItemId = mall_item_info.mall_item_id
                    table.insert(ItemDataSource, ItemData)
                end
            end
            self.UI_GiftPacks_Panel.ItemList:ClearListItems()
            self.UI_GiftPacks_Panel.ItemList:BP_SetListItems(ItemDataSource)
            self.UI_GiftPacks_Panel:vfx_Switch()
        end
    end
end

function M:RefreshMonthCardPanel()
    --月卡购买次数
    local mall_infos = MallSystem:GetInstance().MallInfo
    local time = mall_infos.month_card_info.expire_seconds - PlayerSystem:GetInstance():GetServerTime()
    local day = math.floor(time / 24 / 60 / 60)
    local config = Database.Query("d_mall", 1007)
    local monthly_config = Database.Query("d_gacha_monthly_pass", 1007)
    if day > monthly_config.maxLasting then day = monthly_config.maxLasting end
    if day < 0 then day = 0 end
    self.UI_TopUp_MonthCard.TextDayCount:SetText(day)
    local num = string.format("%.2f", config.price[1] / 10000)
    self.UI_TopUp_MonthCard.TextPrice:SetText(num)

    if day >= (monthly_config.maxLasting - 30) then
        self.UI_TopUp_MonthCard.GHSButtonMonthCard.OnGHSClicked:Clear()
        self.UI_TopUp_MonthCard.GHSButtonMonthCard.OnGHSClicked:Add(self, function()
            UIUtils.ShowNotify(self, Database.L10n(NoticeType.MonthCardLimit))
            --点击保护
            self.UI_TopUp_MonthCard.GHSButtonMonthCard:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            coroutine.resume(coroutine.create(function()
                UE.UKismetSystemLibrary.Delay(self, 1.5)
                self.UI_TopUp_MonthCard.GHSButtonMonthCard:SetVisibility(UE.ESlateVisibility.Visible)
            end))
        end)
    else
        self.UI_TopUp_MonthCard.GHSButtonMonthCard.OnGHSClicked:Clear()
        self.UI_TopUp_MonthCard.GHSButtonMonthCard.OnGHSClicked:Add(self, self.OnClicked_MonthCard)
    end
end

function M:RefreshCurrentPanel()
    self:InitData()
    local ItemDataSource = {}
    if self.MallType then
        if self.MallType == MallType.DressUp then
            self:ChangeMall(MallType.DressUp)
        elseif self.MallType == MallType.Furniture then
            self:ChangeMall(MallType.Furniture)
        elseif self.MallType == MallType.LowClassExchange then
            self:ChangeMall(MallType.LowClassExchange)
        elseif self.MallType == MallType.HighClassExchange then
            self:ChangeMall(MallType.HighClassExchange)
        elseif self.MallType == MallType.GiftPacks then
            local mall_info = self.mall_infos[self.MallType]
            if mall_info then
                local ItemSourcePath =
                '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
                local ItemClass = UE.UClass.Load(ItemSourcePath)
                for i, mall_item_info in ipairs(mall_info.mall_item_infos) do
                    local ItemData = NewObject(ItemClass)
                    ItemData.Index = i
                    ItemData.ItemId = mall_item_info.mall_item_id
                    table.insert(ItemDataSource, ItemData)
                end
            end
            self.UI_GiftPacks_Panel.ItemList:ClearListItems()
            self.UI_GiftPacks_Panel.ItemList:BP_SetListItems(ItemDataSource)
        elseif self.MallType == MallType.MonthCard then
            self:RefreshMonthCardPanel()
        elseif self.MallType == MallType.TopUp then
            self:RefreshTopUpPanel()
        end
    end
end

function M:ChangeMall(type)
    self.MallType = type
    local shop_type_info = d_shop_type[type]
    local currency_data = shop_type_info.moneyType
    self.UI_Money:RefreshData(currency_data)
    local ItemDataSource = {}
    local mall_info = self.mall_infos[type]
    if mall_info then
        local ItemSourcePath =
        '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        for i, mall_item_info in ipairs(mall_info.mall_item_infos) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = mall_item_info.mall_item_id
            table.insert(ItemDataSource, ItemData)
        end
    end
    self.UI_GiftPacks_Panel.ItemList:ClearListItems()
    self.UI_GiftPacks_Panel.ItemList:BP_SetListItems(ItemDataSource)
end

function M:TabSelected(mall_type)
    self.MallType = mall_type
    local shop_type_info = d_shop_type[self.MallType]
    local currency_data = shop_type_info.moneyType
    self.UI_Money:RefreshData(currency_data)
    if mall_type == MallType.GiftPacks then
        self:RefreshOtherPanel()
        self.WidgetSwitcher:SetActiveWidgetIndex(1)
    elseif mall_type == MallType.DressUp then
        self:RefreshOtherPanel()
        self.WidgetSwitcher:SetActiveWidgetIndex(1)
    elseif mall_type == MallType.MonthCard then
        self:RefreshMonthCardPanel()
        self.WidgetSwitcher:SetActiveWidgetIndex(2)
    elseif mall_type == MallType.LowClassExchange then
        self:RefreshOtherPanel()
        self.WidgetSwitcher:SetActiveWidgetIndex(1)
    elseif mall_type == MallType.TopUp then
        self:RefreshTopUpPanel()
        self.WidgetSwitcher:SetActiveWidgetIndex(0)
    end
end

function M:BP_OnOtherEntryInitialized(item, widget)
    if item.ItemId ~= 0 then
        widget.ItemId = item.ItemId
        local config = Database.Query("d_mall", item.ItemId)
        if config then
            if config.shopType == MallType.GiftPacks then
                self:InitializedGiftPacksItem(widget, config)
            elseif config.shopType == MallType.DressUp or config.shopType == MallType.Furniture then
                self:InitializedDressUpItem(widget, config)
            elseif config.shopType == MallType.LowClassExchange or config.shopType == MallType.HighClassExchange then
                self:InitializedExchangeShopItem(widget, config)
            end
        end
    else
        widget.GiftPacks:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.DressUp:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ExchangeShop:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ImageBG_Null:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
end

function M:InitializedGiftPacksItem(widget, config)
    widget:SetVisibility(UE.ESlateVisibility.Visible)
    widget.GiftPacksTextName:SetText(Database.L10n(config.goodsName))

    if config.goodsPath ~= "" then
        local itemPic = LoadObject(string.format('/Game/_Game/%s', config.goodsPath))
        if itemPic then
            widget.Icon:SetBrushFromAtlasInterface(itemPic)
        end
    end

    if config.promoteValue > 0 then
        widget.DiscountPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        widget.TextDiscountNum:SetText(config.promoteValue)
    else
        widget.DiscountPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    widget.ImageCurrency:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.TextDollar:SetVisibility(UE.ESlateVisibility.Visible)

    --限购
    widget.LimitationPanel:SetVisibility(config.limitTimes > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    local purchase_times = 0
    if config.limitTimes > 0 then
        if config.limitType == 1 then --次数限购
            widget.TextLimitType:SetText(Database.L10n(824000001))
        elseif config.limitType == 2 then --每日限购
            widget.TextLimitType:SetText(Database.L10n(824000002))
        elseif config.limitType == 3 then --每周限购
            widget.TextLimitType:SetText(Database.L10n(824000003))
        elseif config.limitType == 4 then --每月限购
            widget.TextLimitType:SetText(Database.L10n(824000004))
        end

        local mall_info = self.mall_infos[self.MallType]
        if mall_info.mall_purchase_limit_infos[config.id] then
            purchase_times = mall_info.mall_purchase_limit_infos[config.id].purchase_times
        end

        local str_limit = string.format("%d/%d", purchase_times or 0, config.limitTimes)
        widget.TextLimit:SetText(str_limit)

        if config.limitTimes - purchase_times <= 0 then
            widget.ImageMask:SetVisibility(UE.ESlateVisibility.Visible)
            widget.SoldOutPanel:SetVisibility(UE.ESlateVisibility.Visible)
            widget.DiscountPanel:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.LimitationPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            widget.ImageMask:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.SoldOutPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        widget.ImageMask:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.SoldOutPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.LimitationPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    --折扣
    if config.discount then
        local discount = config.discount
        local isValidDiscount = discount > 0 and discount < 100
        widget.DiscountPricePanel:SetVisibility(isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.PricePanel:SetVisibility(not isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        if isValidDiscount then
            widget.TextDiscount:SetText('-' .. 100 - discount)
            local num = string.format("%.2f", config.price[1] / 10000)
            widget.TextOriginPrice:SetText(num)
            num = string.format("%.2f", config.price[1] / 10000 * discount / 100)
            widget.TextDiscountPrice:SetText(num)
        else
            local num = string.format("%.2f", config.price[1] / 10000)
            widget.TextPrice:SetText(num)
        end
    end

    widget.GiftPacks:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    widget.DressUp:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ExchangeShop:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ImageBG_Null:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:InitializedDressUpItem(widget, config)
    widget:SetVisibility(UE.ESlateVisibility.Visible)
    widget.GiftPacks:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.DressUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    widget.ExchangeShop:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ImageBG_Null:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.TextOverDue_2:SetText(Database.L10n(512))
    widget.canBuy = true

    local item_config
    if config.goods[1] then
        item_config = Database.Query("d_bag_item", config.goods[1])
    end
    if item_config then
        --稀有度背景图片
        widget.DressUpTextName:SetText(Database.L10n(item_config.itemName))
        if item_config.rarityPath and item_config.rarityPath ~= '' then
            local strArr = string.split(item_config.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if item_config.iconPath and item_config.iconPath ~= '' then
            local strArr = string.split(item_config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', item_config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end

        --货币图片
        local iconObject = LoadObject(string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', config.currency, config.currency))
        widget.ImageCurrency_2:SetBrushFromAtlasInterface(iconObject)

        --折扣
        local discount = config.discount
        local isValidDiscount = discount > 0 and discount < 100
        widget.DiscountPricePanel_2:SetVisibility(isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.PricePanel_2:SetVisibility(not isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.DiscountPanel_2:SetVisibility(isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        
        --货币是否足够
        local hasGold = UIUtils.GetItemCount(config.currency)
        if discount > 0 and discount < 100 then
            widget.TextDiscount_2:SetText('-' .. 100 - discount)
            widget.TextOriginPrice_2:SetText(config.priceShow[1])
            if hasGold >= config.price[1] then
                widget.TextDiscountPrice_2:SetText(string.format(
                    '<span color="#FFFFFFFF">%d</>', config.price[1]))
            else
                widget.TextDiscountPrice_2:SetText(string.format(
                    '<span color="#de5d24">%d</>', config.price[1]))
            end
        else
            if hasGold >= config.price[1] then
                widget.TextPrice_2:SetText(string.format(
                    '<span color="#FFFFFFFF">%d</>', config.price[1]))
            else
                widget.TextPrice_2:SetText(string.format(
                    '<span color="#de5d24">%d</>', config.price[1]))
            end
        end

        --限购
        widget.TextNum_2:SetText('x' .. config.goods[3])
        local purchase_times = 0
        widget.LimitationPanel_2:SetVisibility(config.limitTimes > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        if config.limitTimes > 0 then
            if config.limitType == 1 then --次数限购
                widget.TextLimitType_2:SetText(Database.L10n(824000001))
            elseif config.limitType == 2 then --每日限购
                widget.TextLimitType_2:SetText(Database.L10n(824000002))
            elseif config.limitType == 3 then --每周限购
                widget.TextLimitType_2:SetText(Database.L10n(824000003))
            elseif config.limitType == 4 then --每月限购
                widget.TextLimitType_2:SetText(Database.L10n(824000004))
            end

            local mall_info = self.mall_infos[self.MallType]
            if mall_info.mall_purchase_limit_infos[config.id] then
                purchase_times = mall_info.mall_purchase_limit_infos[config.id].purchase_times
            end

            local str_limit = string.format("%d/%d", purchase_times or 0, config.limitTimes)
            widget.TextLimit_2:SetText(str_limit)

            if config.limitTimes - purchase_times <= 0 then
                widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Visible)
                widget.SoldOutPanel_2:SetVisibility(UE.ESlateVisibility.Visible)
                widget.DiscountPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                widget.LimitationPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
            else
                widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Hidden)
                widget.SoldOutPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        else
            widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.SoldOutPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.LimitationPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        local hasAllGood = true 
        local isSoldOut = config.limitTimes > 0 and config.limitTimes - purchase_times <= 0
        if item_config.itemType == UIUtils.ItemMainType.Skin
            or item_config.itemType == UIUtils.ItemMainType.Build then
            local good_id = config.goods[1]
            local count = UIUtils.GetItemCount(good_id)
            if count == 0 then
                hasAllGood = false
            end

            if isSoldOut then
                --售罄
                widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            else
                if hasAllGood then
                    widget.canBuy = false
                    widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Visible)
                    widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Visible)
                    widget.DiscountPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget.LimitationPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                else
                    widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget:SetVisibility(UE.ESlateVisibility.Visible)
                end
            end
        end

        if item_config.itemType == UIUtils.ItemMainType.Skin then
            --皮肤 
            if not hasAllGood and not isSoldOut then
                --未售罄 且可以购买
                if #item_config.subParam > 0 then
                    --都是d_char_clothes中的
                    local skin_id = item_config.subParam[1]
                    local skin_info = Database.Query("d_char_clothes", skin_id)
                    if skin_info then
                        local character_id = skin_info.charBelong
                        local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
                        if not character_info then
                            --未拥有角色是不可购买
                            widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Visible)
                            widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Visible)
                            widget.DiscountPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                            widget.LimitationPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                            widget.TextOverDue_2:SetText(Database.L10n(489))
                        else
                            --有角色时判断涂装里的机甲是否已激活
                            hasAllGood = true
                            for _, item_skin_id in ipairs(item_config.subParam) do
                                local item_skin_info = Database.Query("d_char_clothes", item_skin_id)
                                local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1, item_skin_id)
                                if not isSkinUnlock then
                                    hasAllGood = false
                                    break
                                end 
                            end
                            if hasAllGood then
                                widget.canBuy = false
                                widget.ImageMask_2:SetVisibility(UE.ESlateVisibility.Visible)
                                widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Visible)
                                widget.DiscountPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                                widget.LimitationPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                            end
                        end
                    end
                end
            end
        elseif item_config.itemType == UIUtils.ItemMainType.Build then
            --没有对应角色时可以购买
        end
    end
end

function M:InitializedExchangeShopItem(widget, config)
    widget:SetVisibility(UE.ESlateVisibility.Visible)
    widget.GiftPacks:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.DressUp:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ExchangeShop:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    widget.ImageBG_Null:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.OverDuePanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.TextOverDue_2:SetText(Database.L10n(512))
    widget.canBuy = true

    local item_config
    if config.goods[1] then
        item_config = Database.Query("d_bag_item", config.goods[1])
        if not item_config then
            item_config = Database.Query("d_bag_item_weapon", config.goods[1])
        end
        if not item_config then
            item_config = Database.Query("d_bag_item_equip", config.goods[1])
        end
    end
    if item_config then
        --稀有度背景图片
        widget.ExchangeShopTextName:SetText(Database.L10n(item_config.itemName))
        if item_config.rarityPath and item_config.rarityPath ~= '' then
            local strArr = string.split(item_config.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.container_icon_res_3:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if item_config.iconPath and item_config.iconPath ~= '' then
            local strArr = string.split(item_config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', item_config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.icon_res_3:SetBrushFromAtlasInterface(iconRes)
            end
        end

        --货币图片
        local iconObject = LoadObject(string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', config.currency, config.currency))
        widget.ImageCurrency_3:SetBrushFromAtlasInterface(iconObject)

        --折扣
        local discount = config.discount
        local isValidDiscount = discount > 0 and discount < 100
        widget.DiscountPricePanel_3:SetVisibility(isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.PricePanel_3:SetVisibility(not isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.DiscountPanel_3:SetVisibility(isValidDiscount and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        
        --货币是否足够
        local hasGold = UIUtils.GetItemCount(config.currency)
        local price = 0
        if config.charge == 1 then
            price = string.format("%.2f", config.price[1] / 10000)
        else
            price = config.price[1]
        end
        if discount > 0 and discount < 100 then
            widget.TextDiscount_3:SetText('-' .. 100 - discount)
            widget.TextOriginPrice_3:SetText(config.priceShow[1])
            
            if hasGold >= config.price[1] then
                widget.TextDiscountPrice_3:SetText(string.format(
                    '<span color="#FFFFFFFF">%d</>', price))
            else
                widget.TextDiscountPrice_3:SetText(string.format(
                    '<span color="#de5d24">%d</>', price))
            end
        else
            if hasGold >= config.price[1] then
                widget.TextPrice_3:SetText(string.format(
                    '<span color="#FFFFFFFF">%d</>', price))
            else
                widget.TextPrice_3:SetText(string.format(
                    '<span color="#de5d24">%d</>', price))
            end
        end

        --限购
        widget.TextNum_3:SetText('x' .. config.goods[3])
        widget.LimitationPanel_3:SetVisibility(config.limitTimes > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        local purchase_times = 0
        if config.limitTimes > 0 then
            if config.limitType == 1 then --次数限购
                widget.TextLimitType_3:SetText(Database.L10n(824000001))
            elseif config.limitType == 2 then --每日限购
                widget.TextLimitType_3:SetText(Database.L10n(824000002))
            elseif config.limitType == 3 then --每周限购
                widget.TextLimitType_3:SetText(Database.L10n(824000003))
            elseif config.limitType == 4 then --每月限购
                widget.TextLimitType_3:SetText(Database.L10n(824000004))
            end

            local mall_info = self.mall_infos[self.MallType]
            if mall_info.mall_purchase_limit_infos[config.id] then
                purchase_times = mall_info.mall_purchase_limit_infos[config.id].purchase_times
            end

            local str_limit = string.format("%d/%d", purchase_times or 0, config.limitTimes)
            widget.TextLimit_3:SetText(str_limit)

            if config.limitTimes - purchase_times <= 0 then
                widget.ImageMask_3:SetVisibility(UE.ESlateVisibility.Visible)
                widget.SoldOutPanel_3:SetVisibility(UE.ESlateVisibility.Visible)
                widget.DiscountPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
                widget.LimitationPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
            else
                widget.ImageMask_3:SetVisibility(UE.ESlateVisibility.Hidden)
                widget.SoldOutPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        else
            widget.ImageMask_3:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.SoldOutPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.LimitationPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        if config.limitTimes - purchase_times > 0 then
            if config.goods[1] then
                if item_config.itemType == UIUtils.ItemMainType.TempProp and item_config.subType == UIUtils.ItemTempPropType.CharCard then
                    --如果是角色卡 只有没有满命的情况可以购买
                    local character_id = item_config.subParam[1]
                    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
                    local isFull = CharacterSystem:GetInstance():GetCharacterTalentCount(character_id)
                    local hasAllGood = true
                    if isFull then
                        --是否已拥有所有涂装
                        local good_id = config.goods[1]
                        local count = UIUtils.GetItemCount(good_id)
                        if count == 0 then
                            hasAllGood = false
                        end

                        if character_info then
                            --有角色时判断涂装里的机甲是否已激活
                            hasAllGood = true
                            local skin_id = item_config.subParam[2]
                            local skin_info = Database.Query("d_bag_item", skin_id)
                            if skin_info then
                                for _, item_skin_id in ipairs(skin_info.subParam) do
                                    local item_skin_info = Database.Query("d_char_clothes", item_skin_id)
                                    if item_skin_info.dressType == 4 then --套房皮肤
                                        local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1,
                                            item_skin_id - 1000000)
                                        if not isSkinUnlock then
                                            hasAllGood = false
                                            break
                                        end
                                    else
                                        local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1,
                                            item_skin_id)
                                        if not isSkinUnlock then
                                            hasAllGood = false
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if config.limitTimes > 0 and config.limitTimes - purchase_times <= 0 then
                        --售罄
                        widget.canBuy = false
                        widget.OverDuePanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
                        widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                    else
                        if isFull then
                            widget.TextOverDue_3:SetText(Database.L10n(517))
                        end
                        if hasAllGood and isFull then
                            widget.canBuy = false
                            widget.ImageMask_3:SetVisibility(UE.ESlateVisibility.Visible)
                            widget.OverDuePanel_3:SetVisibility(UE.ESlateVisibility.Visible)
                            widget.DiscountPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
                            widget.LimitationPanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
                            widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                        else
                            widget.OverDuePanel_3:SetVisibility(UE.ESlateVisibility.Hidden)
                        end
                    end
                end
            end
        end
    end
end

function M:BP_OnTopUpEntryInitialized(item, widget)
    local mall_info = self.mall_infos[self.MallType]
    local config = Database.Query("d_mall", item.ItemId)
    if config then
        widget.TextName:SetText(Database.L10n(config.goodsName))
        local num = string.format("%.2f", config.price[1] / 10000)
        widget.TextPrice:SetText(num)
        widget.TextDesc:SetVisibility(UE.ESlateVisibility.Hidden)

        local mall_purchase_limit_info = mall_info.mall_purchase_limit_infos[config.id]
        if mall_purchase_limit_info and mall_purchase_limit_info.purchase_times > 0 then
            --非首充
            if config.goodsPath ~= "" then
                local itemPic = LoadObject(string.format('/Game/_Game/%s', config.goodsPath))
                if itemPic then
                    widget.Icon:SetBrushFromAtlasInterface(itemPic)
                end
            end
            widget.TextDesc:SetText(Database.L10n(config.goodsDesc))
            widget.TextFirstDesc:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.TextDesc:SetVisibility(UE.ESlateVisibility.Visible)
            widget.FirstPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            --首充
            if config.firstGoodsPath ~= "" then
                local itemPic = LoadObject(string.format('/Game/_Game/%s', config.firstGoodsPath))
                if itemPic then
                    widget.Icon:SetBrushFromAtlasInterface(itemPic)
                end
            end
            widget.TextFirstDesc:SetText(Database.L10n(425 + item.index))
            widget.TextFirstDesc:SetVisibility(UE.ESlateVisibility.Visible)
            widget.TextDesc:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.FirstPanel:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end
end

function M:BP_OnTopUpItemClicked(item)
    local mall_info = self.mall_infos[self.MallType]
    local msg = {}
    if mall_info then
        msg.mall_id = mall_info.mall_id
        msg.mall_item_id = item.ItemId
        msg.mall_item_count = 1
        msg.last_auto_refresh_seconds = mall_info.last_auto_refresh_seconds
        local bSuccess, SteamId, CurrentGameLanguage = UE.UGameplayStatics.GetGameInstance(self):PreparePayWithSteam(0)
        if bSuccess then
            msg.steam_id = SteamId
            msg.steam_current_game_language = CurrentGameLanguage
        end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        msg.access_token = gameInstance.key
        Client.send("req_mall_buy", msg)
        self.WaitPanel:SetVisibility(UE.ESlateVisibility.Visible)

        self.ClickedItem = {}
        local config = Database.Query("d_mall", item.ItemId)
        local mall_purchase_limit_info = mall_info.mall_purchase_limit_infos[config.id]
        if mall_purchase_limit_info and mall_purchase_limit_info.purchase_times > 0 then
            --非首充
            local config = Database.Query("d_mall", item.ItemId)
            if config then
                local item_count = #config.goods / 3
                for i = 1, item_count do
                    table.insert(self.ClickedItem, { item_id = config.goods[i * 3 - 2], count = config.goods[i * 3] })
                end
            end
        else
            --首充
            local config = Database.Query("d_mall", item.ItemId)
            if config then
                local item_count = #config.firstGoods / 3
                for i = 1, item_count do
                    table.insert(self.ClickedItem, { item_id = config.firstGoods[i * 3 - 2], count = config.firstGoods[i * 3] })
                end
            end
        end
    end
end

function M:BP_OnOtherItemClicked(item)
    local item_data = {}
    local config = Database.Query("d_mall", item.ItemId)
    if config.goods[1] then
        local item_config
        if config.goods[1] then
            item_config = Database.Query("d_bag_item", config.goods[1])
            if not item_config then
                item_config = Database.Query("d_bag_item_weapon", config.goods[1])
            end
            if not item_config then
                item_config = Database.Query("d_bag_item_equip", config.goods[1])
            end
        end
        if item_config then
            local mall_info = self.mall_infos[self.MallType]
            local purchase_times = 0
            local maxBuyCount = 0
            local hasGold = UIUtils.GetItemCount(config.currency)
            local buyCount = math.floor(hasGold / config.price[1])
            if mall_info.mall_purchase_limit_infos[config.id] then
                purchase_times = mall_info.mall_purchase_limit_infos[config.id].purchase_times
            end

            if config.limitTimes > 0 then
                maxBuyCount = buyCount <= config.limitTimes - purchase_times and buyCount or config.limitTimes - purchase_times
                maxBuyCount = maxBuyCount == 0 and 1 or maxBuyCount
            else
                --不限购
                maxBuyCount = buyCount
            end
            maxBuyCount = maxBuyCount == 0 and 1 or maxBuyCount
            item_data.count = maxBuyCount
            item_data.config = config
            item_data.item_config = item_config
            item_data.purchase_times = purchase_times
            if config.limitTimes > 0 and config.limitTimes - purchase_times <= 0 then
                return
            end
            if mall_info then
                item_data.mall_id = mall_info.mall_id
                item_data.mall_item_id = item.ItemId
                item_data.mall_item_count = 1
                item_data.last_auto_refresh_seconds = mall_info.last_auto_refresh_seconds
                if config.charge == 1 then
                    local bSuccess, SteamId, CurrentGameLanguage = UE.UGameplayStatics.GetGameInstance(self):PreparePayWithSteam(0)
                    if bSuccess then
                        item_data.steam_id = SteamId
                        item_data.steam_current_game_language = CurrentGameLanguage
                    end
                end

                local can_buy = false
                
                if item_config.itemType == UIUtils.ItemMainType.Skin then
                    --如果是皮肤 没用有角色提示二次弹框警告
                    local count = UIUtils.GetItemCount(config.goods[1])
                    if count == 0 then
                        can_buy = true
                        if #item_config.subParam > 0 then
                            --都是d_char_clothes中的
                            local skin_id = item_config.subParam[1]
                            local skin_info = Database.Query("d_char_clothes", skin_id)
                            if skin_info then
                                local character_id = skin_info.charBelong
                                local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
                                if not character_info then
                                    --点击保护
                                    UIUtils.ShowNotify(self, Database.L10n(NoticeType.NotHasChar))
                                    local tagWidgets = self.UI_GiftPacks_Panel.ItemList:GetDisplayedEntryWidgets()
                                    for i = 1, tagWidgets:Length() do
                                        local widget = tagWidgets:Get(i)
                                        if widget.ItemId == item.ItemId then
                                            widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                                            coroutine.resume(coroutine.create(function()
                                                UE.UKismetSystemLibrary.Delay(self, 1.5)
                                                widget:SetVisibility(UE.ESlateVisibility.Visible)
                                            end))
                                            break
                                        end
                                    end
                                    return
                                end
                            end
                        end
                    end
                elseif item_config.itemType == UIUtils.ItemMainType.Build then
                    --没有对应角色时可以购买 但是要弹三级提示框
                    can_buy = true
                    local count = UIUtils.GetItemCount(config.goods[1])
                    if count == 0 then
                        if #item_config.subParam > 0 then
                            --都是d_char_clothes中的
                            local char_id = item_config.subParam[1]
                            if char_id then
                                local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(char_id)
                                if not character_info then
                                    item_data.noticeType = NoticeType.BuildNotHasChar
                                end
                            end
                        end
                    end
                elseif item_config.itemType == UIUtils.ItemMainType.TempProp and item_config.subType == UIUtils.ItemTempPropType.CharCard then
                    --如果是角色卡 只有没有满命的情况可以购买
                    local character_id = item_config.subParam[1]
                    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
                    local isFull = CharacterSystem:GetInstance():GetCharacterTalentCount(character_id)
                    local hasAllGood = true
                    if isFull then
                        --是否已拥有所有涂装
                        local good_id = config.goods[1]
                        local count = UIUtils.GetItemCount(good_id)
                        if count == 0 then
                            hasAllGood = false
                        end

                        --如果满命需要弹二级弹框
                        item_data.noticeType = NoticeType.FullCharSkin

                        if character_info then
                            --有角色时判断涂装里的机甲是否已激活
                            hasAllGood = true
                            local skin_id = item_config.subParam[2]
                            local skin_info = Database.Query("d_bag_item", skin_id)
                            if skin_info then
                                for _, item_skin_id in ipairs(skin_info.subParam) do
                                    local item_skin_info = Database.Query("d_char_clothes", item_skin_id)
                                    local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1,
                                        item_skin_id)
                                    if not isSkinUnlock then
                                        hasAllGood = false
                                        break
                                    end
                                end
                            end
                        end
                    end

                    if config.limitTimes > 0 and config.limitTimes - purchase_times <= 0 then
                        --售罄
                        can_buy = false
                    else
                        if hasAllGood and isFull then
                            can_buy = false
                        else
                            can_buy = true
                        end
                    end
                else
                    --未拥有的情况下可以直接买
                    can_buy = true
                end
                if self.MallType == MallType.GiftPacks then
                    local UI_TopUp_GiftPacks = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_TopUp_GiftPacks')
                    UI_TopUp_GiftPacks:RefreshUI(item_data)
                    self.ClickedItem = {}
                    local item_count = #config.goods / 3
                    for i = 1, item_count do
                        table.insert(self.ClickedItem, { item_id = config.goods[i * 3 - 2], count = config.goods[i * 3] })
                    end
                else
                    if can_buy then
                        self.ClickedItem = {}
                        table.insert(self.ClickedItem, { item_id = config.goods[1], count = config.goods[3] })
                        self.UI_Com_BuyWindow = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Com_BuyWindow')
                        self.UI_Com_BuyWindow:RefreshUI(item_data)
                    end
                end
            end
        end
    end
end

function M:OnMsg_Ntf_Mall_Info()
    self:RefreshCurrentPanel()
end

function M:OnMsg_Res_Mall_Buy(parsed_msg)
    self:RefreshCurrentPanel()
    self.WaitPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    if #self.ClickedItem > 0 then
        self.UI_GetItem_Notice = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
        for _, value in ipairs(self.ClickedItem) do
            value.count = value.count * parsed_msg.req_data.mall_item_count
        end
        self.UI_GetItem_Notice:RefreshUI(self.ClickedItem)
        self.ClickedItem = {}
    end
end

function M:OnMsg_Res_Finish_Order()
end

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:vfx_Out()
    self.Exit:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClicked_AddUp()
    local UI_AddUp = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_AddUp')
    --UI_AddUp:RefreshUI()
end

function M:OnClicked_MonthCard()
    local mall_info = self.mall_infos[self.MallType]
    local msg = {}
    if mall_info then
        msg.mall_id = mall_info.mall_id
        msg.mall_item_id = 1007
        msg.mall_item_count = 1
        msg.last_auto_refresh_seconds = mall_info.last_auto_refresh_seconds
        local bSuccess, SteamId, CurrentGameLanguage = UE.UGameplayStatics.GetGameInstance(self):PreparePayWithSteam(0)
        if bSuccess then
            msg.steam_id = SteamId
            msg.steam_current_game_language = CurrentGameLanguage
        end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        msg.access_token = gameInstance.key
        Client.send("req_mall_buy", msg)
        print("======点击购买:" .. tostring(msg))
        self.WaitPanel:SetVisibility(UE.ESlateVisibility.Visible)

        self.ClickedItem = {}
        local config = Database.Query("d_gacha_monthly_pass", 1007)
        if config then
            local item_count = #config.purchaseReward / 3
            for i = 1, item_count do
                table.insert(self.ClickedItem, { item_id = config.purchaseReward[i * 3 - 2], count = config.purchaseReward[i * 3] })
            end
        end
    end
end

function M:OnClicked_ExplainBtn()
    UIUtils.ShowSystemDes(1007)
end

return M
