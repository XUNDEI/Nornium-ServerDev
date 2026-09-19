--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_shop_type = require("ClientDatas.d_shop_type")
local ShopSystem = require "Module.ShopSystem.ShopSystem"
local PlayerSystem = require('Module.Player.PlayerSystem')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Shop_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    --生成器
    self.ItemList.BP_OnEntryInitialized:Clear()
    self.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ItemList.BP_OnItemClicked:Clear()
    self.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.GHSSlider.OnGHSValueChanged:Add(self, self.OnSlider_Value_Changed)
    self.BtnMinus.OnGHSClicked:Add(self, self.OnClicked_Minus)
    self.BtnAdd.OnGHSClicked:Add(self, self.OnClicked_Add)

    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    self.GHSButtonRefresh.OnGHSClicked:Add(self, self.OnClicked_Btn_Refresh)
    self.GHSButtonPurchase.OnGHSClicked:Add(self, self.OnClicked_Btn_Purchase)

    -- self.Level.OnGHSClicked:Add(self, self.OnClicked_Level)

    self.SelectedItemIndex = 1
    self.purchase_num = 0
    self.count = 0
    self.price = 0
    self.timestamp = 0

    MessageManager:GetInstance():AddListener("OnMsg_Shop_Refresh", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
    -- MessageManager:GetInstance():AddListener('OnMsg_Player_Receive_Level_Award', self)
end

function M:Destruct()
    if self.NPC then
        self.NPC:K2_DestroyActor()
    end
    MessageManager:GetInstance():RemoveListener("OnMsg_Shop_Refresh", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    -- MessageManager:GetInstance():RemoveListener('OnMsg_Player_Receive_Level_Award', self)

end

function M:InitUIEx(args)
    self.ShopType = tonumber(args)
    self:InitUI()
end

function M:InitUI()
    local ItemDataSource = {}
    if self.ShopType then
        self.shop_info = ShopSystem:GetInstance().ShopInfo[self.ShopType]
        if self.shop_info then
            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            for i, item_info in ipairs(self.shop_info.shop_item_infos) do
                local ItemData = NewObject(ItemClass)
                ItemData.Index = i
                ItemData.ItemId = item_info.shop_item_id
                table.insert(ItemDataSource, ItemData)
            end
        end
    end
    self.ItemList:ClearListItems()
    self.ItemList:BP_SetListItems(ItemDataSource)

    self.shop_type_info = d_shop_type[self.ShopType]
    if self.shop_type_info then
        local shopBG = LoadObject(self.shop_type_info.shopBG)
        if shopBG then
            self.ImageBG:SetBrushFromTexture(shopBG)
        end

        if self.shop_info.manual_refresh_times < self.shop_type_info.refreshTimes then
            if self.shop_info.manual_refresh_times + 1 >= #self.shop_type_info.refreshPrice then
                self.TextRefreshPrice:SetText(self.shop_type_info.refreshPrice[#self.shop_type_info.refreshPrice])
            else
                self.TextRefreshPrice:SetText(self.shop_type_info.refreshPrice[self.shop_info.manual_refresh_times + 1])
            end
            self.GHSButtonRefresh:SetVisibility(UE.ESlateVisibility.Visible)
        else
            self.GHSButtonRefresh:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        self.TextSaler:SetText(Database.L10n(self.shop_type_info.npcName))
        self.TextSale:SetText(Database.L10n(self.shop_type_info.npcSpeak))
        self:RefreshTimeStamp()

        local currency_data = self.shop_type_info.moneyType
        self.UI_Money:RefreshData(currency_data)

        self.Text_Title:SetText(Database.L10n(self.shop_type_info.shopName))
        self.Text_RoleTitle:SetText(Database.L10n(self.shop_type_info.npcTitle))
    end

    if self.NPC then
        return 
    end

    if self.ShopType == 101 then
        local path = string.format("'/Game/_Game/Blueprints/NPCs/BP_NPC_Shop_101.BP_NPC_Shop_101_C'") 
        local playerClass = LoadClass(path)
        local trans = UE.UKismetMathLibrary.MakeTransform(
            UE.FVector(400, 350, 100),
            UE.FRotator(0, 0, 0),
            UE.FVector(1, 1, 1))
        self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
        self.RefreshBorder:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif self.ShopType == 102 then
        local path = string.format("'/Game/_Game/Blueprints/NPCs/BP_NPC_Shop_102.BP_NPC_Shop_102_C'") 
        local playerClass = LoadClass(path)
        local trans = UE.UKismetMathLibrary.MakeTransform(
            UE.FVector(400, 350, 100),
            UE.FRotator(0, 0, 0),
            UE.FVector(1, 1, 1))
        self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
        self.RefreshBorder:SetVisibility(UE.ESlateVisibility.Visible)
    end

    --奖励按钮
    -- local haveReward, _ = PlayerSystem:GetInstance():HavePlayerLevelAward()
    -- self.Level:SetVisibility(haveReward and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.timestamp ~= 0 then
        local str_time = ''
        
        local time = os.time()
        local time = self.timestamp - time
        local day = math.floor(time / 86400)
        local hour = math.floor((time - day * 86400) / 3600)
        if day > 0 then
            str_time = string.format("%d天", day)
        end
        if hour < 10 then
            str_time = str_time .. string.format("0%d", hour)
        else
            str_time = str_time .. string.format("%d", hour)
        end
        local minute = math.floor((time - day * 86400 - hour * 3600) / 60)
        if minute < 10 then
            str_time = str_time .. string.format(":0%d", minute)
        else
            str_time = str_time .. string.format(":%d", minute)
        end
        local second = time - day * 86400 - hour * 3600 - minute * 60
        if second < 10 then
            str_time = str_time .. string.format(":0%d", second)
        else
            str_time = str_time .. string.format(":%d", second)
        end
        if day <= 0 and hour <= 0 and minute <= 0 and second <= 0 then
            self:RefreshTimeStamp()
        end
        self.TextTime:SetText(str_time)
    end
end

function M:RefreshTimeStamp()
    if self.shop_type_info then
        local time = os.date("*t", self.shop_info.last_auto_refresh_seconds)
        if #self.shop_type_info.dayRefresh > 0 then
            local bTomorrow = true
            for _, day_info in ipairs(self.shop_type_info.dayRefresh) do
                local timestamp = os.time({ year = time.year, month = time.month, day = time.day, hour = day_info, min = 0, sec = 0 })
                if self.shop_info.last_auto_refresh_seconds < timestamp then
                    self.timestamp = timestamp
                    bTomorrow = false
                    break
                end
            end
            if bTomorrow then
                for _, day_info in ipairs(self.shop_type_info.dayRefresh) do
                    local timestamp = os.time({ year = time.year, month = time.month, day = time.day + 1, hour = day_info, min = 0, sec = 0 })
                    if self.shop_info.last_auto_refresh_seconds < timestamp then
                        self.timestamp = timestamp
                        break
                    end
                end
            end
        elseif #self.shop_type_info.weekRefresh > 0 then
            --每周自动刷新
        elseif #self.shop_type_info.monthRefresh > 0 then
            local bNextMonth = true
            for _, day in ipairs(self.shop_type_info.monthRefresh) do
                local timestamp = os.time({ year = time.year, month = time.month, day = day, hour = 0, min = 0, sec = 0 })
                if self.shop_info.last_auto_refresh_seconds < timestamp then
                    self.timestamp = timestamp
                    bNextMonth = false
                    break
                end
            end
            if bNextMonth then
                for _, day in ipairs(self.shop_type_info.monthRefresh) do
                    local timestamp = os.time({ year = time.year, month = time.month + 1, day = day, hour = 0, min = 0, sec = 0 })
                    if self.shop_info.last_auto_refresh_seconds < timestamp then
                        self.timestamp = timestamp
                        bNextMonth = false
                        break
                    end
                end
            end
        end
    end

    -- if self.timestamp ~= 0 then
    --     self.RefreshBorder:SetVisibility(UE.ESlateVisibility.Visible)
    -- else
    --     self.RefreshBorder:SetVisibility(UE.ESlateVisibility.Hidden)
    -- end
end

function M:BP_OnEntryInitialized(item, widget)
    local shop_item_info = self.shop_info.shop_item_infos[item.Index].shop_config
    if shop_item_info then
        widget.Index = item.Index
        widget.ItemId = item.ItemId
        local bag_item_info
        if shop_item_info.itemType == UIUtils.ItemMainType.Weapon then
            bag_item_info = Database.Query("d_bag_item_weapon", shop_item_info.goodsId)
        elseif shop_item_info.itemType == UIUtils.ItemMainType.Equip then
            bag_item_info = Database.Query("d_bag_item_equip", shop_item_info.goodsId)
        else
            bag_item_info = Database.Query("d_bag_item", shop_item_info.goodsId)
        end
        if bag_item_info then
            widget.TextName:SetText(Database.L10n(bag_item_info.itemName))

            --稀有度背景图片
            if bag_item_info.rarityPath and bag_item_info.rarityPath ~= '' then
                local strArr = string.split(bag_item_info.rarityPath, '/')
                local littePath = strArr[#strArr]
                local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                local itemRarityPic = LoadObject(rarityPath)
                if itemRarityPic then
                    widget.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end

            --icon
            if bag_item_info.iconPath and bag_item_info.iconPath ~= '' then
                local strArr = string.split(bag_item_info.iconPath, '/')
                local littePath = strArr[#strArr]
                local iconResPath = string.format('/Game/_Game/%s.%s', bag_item_info.iconPath, littePath)
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    widget.icon_res:SetBrushFromAtlasInterface(iconRes)
                end
            end
        end

        --货币图片
        local iconObject = LoadObject(string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', shop_item_info.moneyType, shop_item_info.moneyType))
        widget.ImageCurrency:SetBrushFromAtlasInterface(iconObject)

        --折扣
        local discount = self.shop_info.shop_item_infos[widget.Index].discount
        widget.DiscountPricePanel:SetVisibility(discount > 0 and discount < 100 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.PricePanel:SetVisibility(discount == 100 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.DiscountPanel:SetVisibility(discount > 0 and discount < 100 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        if discount > 0 and discount < 100 then
            widget.TextDiscount:SetText('-' .. 100 - discount)
            widget.TextOriginPrice:SetText(shop_item_info.money)
            widget.TextDiscountPrice:SetText(math.floor(shop_item_info.money * discount / 100))
        else
            widget.TextPrice:SetText(shop_item_info.money)
        end

        --选中
        if self.SelectedItemIndex == item.Index then 
            widget.ImageBG:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageBGSelected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self:RefreshSidebar()
        else
            widget.ImageBG:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            widget.ImageBGSelected:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        --限购
        widget.TextNum:SetText('x' .. shop_item_info.sellNum)
        widget.LimitationPanel:SetVisibility(shop_item_info.limitPrice > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        if shop_item_info.limitPrice > 0 then
            local str_limit = string.format("%d/%d", self.shop_info.shop_item_infos[widget.Index].purchase_times, shop_item_info.limitPrice)
            widget.TextLimit:SetText(str_limit)
            if shop_item_info.limitType == 1 then --次数限购
                widget.TextLimitType:SetText(Database.L10n(824000001))
            elseif shop_item_info.limitType == 2 then --每日限购
                widget.TextLimitType:SetText(Database.L10n(824000002))
            elseif shop_item_info.limitType == 3 then --每周限购
                widget.TextLimitType:SetText(Database.L10n(824000003))
            elseif shop_item_info.limitType == 4 then --每月限购
                widget.TextLimitType:SetText(Database.L10n(824000004))
            end

            if self.shop_info.shop_item_infos[widget.Index].shop_config.limitPrice - self.shop_info.shop_item_infos[widget.Index].purchase_times == 0 then
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
        end
    end
end

function M:BP_OnItemClicked(item)
    if self.SelectedItemIndex == item.Index then return end
    local lastIndex = self.SelectedItemIndex
    self.SelectedItemIndex = item.Index
    local widgets = self.ItemList:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == lastIndex or widget.Index == item.Index then
            widget.ImageBG:SetVisibility(self.SelectedItemIndex == widget.Index and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
            widget.ImageBGSelected:SetVisibility(self.SelectedItemIndex == widget.Index and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        end
    end
    self:RefreshSidebar()
end

function M:GetItemBuyCount(index)
    local shop_item_info = self.shop_info.shop_item_infos[index]
    local hasGold = UIUtils.GetItemCount(shop_item_info.shop_config.moneyType)
    local price = shop_item_info.discount == 0 and shop_item_info.shop_config.money or
        math.floor(shop_item_info.shop_config.money * shop_item_info.discount / 100)
    local maxCount = Database.Query("d_com_params", 15)["value2"]
    if shop_item_info.shop_config.limitPrice == 0 then--无限购
        if math.floor(hasGold / price) < maxCount then
            return math.floor(hasGold / price)
        else
            return maxCount
        end
    else--限购
        local maxBuyCount = math.floor(hasGold / price)
        local limitCount = shop_item_info.shop_config.limitPrice - shop_item_info.purchase_times
        --最小购买数为1
        return UE.UKismetMathLibrary.Clamp(maxBuyCount, 1, limitCount)
    end
end

function M:RefreshSidebar()
    local data = {}
    local shop_item_info = self.shop_info.shop_item_infos[self.SelectedItemIndex]

    local bag_item_info
    if shop_item_info.shop_config.itemType == UIUtils.ItemMainType.Weapon then
        bag_item_info = Database.Query("d_bag_item_weapon", shop_item_info.shop_config.goodsId)
    elseif shop_item_info.shop_config.itemType == UIUtils.ItemMainType.Equip then
        bag_item_info = Database.Query("d_bag_item_equip", shop_item_info.shop_config.goodsId)
    else
        bag_item_info = Database.Query("d_bag_item", shop_item_info.shop_config.goodsId)
    end

    
    data.config = bag_item_info or shop_item_info.config
    data.item_id = data.config.id
    data.count = bag_item_info and UIUtils.GetItemCount(bag_item_info.id) or 0 --shop_item_info.count
    self.UI_Com_ItemBox:RefreshUI(data, false)
    if bag_item_info then
        if shop_item_info.shop_config.itemType == UIUtils.ItemMainType.Weapon then
            local weaponSkillDesc = UIUtils.GetWeaponSkillDesc(data.item_id, 0)
            self.TextDesc:SetText(weaponSkillDesc)
        else
            self.TextDesc:SetText(Database.L10n(bag_item_info.effectDesc))
        end
    end

    local iconObject = LoadObject(string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png',
        shop_item_info.shop_config.moneyType, shop_item_info.shop_config.moneyType))
    self.ImageCurrency:SetBrushFromAtlasInterface(iconObject)

    -- 判断没有限购的情况
    if shop_item_info.shop_config.limitPrice == 0 or shop_item_info.shop_config.limitPrice > shop_item_info.purchase_times then
        self.price = shop_item_info.discount == 0 and shop_item_info.shop_config.money or
            math.floor(shop_item_info.shop_config.money * shop_item_info.discount / 100)
        local maxBuyCount, limitCount = self:GetItemBuyCount(self.SelectedItemIndex)
        self.count = self:GetItemBuyCount(self.SelectedItemIndex)

        local hasGold = UIUtils.GetItemCount(shop_item_info.shop_config.moneyType)
        local price = shop_item_info.discount == 0 and shop_item_info.shop_config.money or
            math.floor(shop_item_info.shop_config.money * shop_item_info.discount / 100)
        if self.count > 0 and hasGold >= price then
            self.GHSSlider:SetMaxValue(600 * self.count)
            self.GHSSlider:SetStepSize(600)
            self.GHSSlider:SetValue(self.GHSSlider.MaxValue * 1 / self.count)
            self.GHSSlider:SetVisibility(UE.ESlateVisibility.Visible)
            self:RefreshCostInfo(1)
            self.Text_Num:SetText(1)
            self.BtnMinus:SetVisibility(UE.ESlateVisibility.Visible)
            self.BtnAdd:SetVisibility(UE.ESlateVisibility.Visible)
            self.Text_NeedGold:SetText(string.format(
                '<span color="#FFFFFFFF">%d</>', self.price))
        else
            self.count = 1
            self.GHSSlider:SetValue(self.GHSSlider.MaxValue)
            self.GHSSlider:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            self.ProgressBar:SetPercent(1)
            self.Text_Num:SetText(1)
            --self.Text_NeedGold:SetText(self.price)
            self.Text_NeedGold:SetText(string.format(
                '<span color="#de5d24">%d</>', self.price))
            self.purchase_num = 1
            self.GHSButtonPurchase:SetRenderOpacity(0.5)
            self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            self.BtnMinus:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            self.BtnAdd:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        end
    else
        self.GHSSlider:SetValue(0)
        self:RefreshCostInfo(0)
        self.Text_Num:SetText(0)
        self.BtnMinus:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        self.BtnAdd:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end
end

function M:RefreshCostInfo(pruchase_num)
    local percent = pruchase_num / self.count
    self.ProgressBar:SetPercent(percent)
    self.Text_Num:SetText(pruchase_num)
    self.Text_NeedGold:SetText(pruchase_num * self.price)
    self.purchase_num = pruchase_num
    if self.purchase_num <= 0 then
        self.GHSButtonPurchase:SetRenderOpacity(0.5)
        self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    else
        self.GHSButtonPurchase:SetRenderOpacity(1)
        self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:OnSlider_Value_Changed(target, value)
    if value then
        local pruchase_num = math.floor(value / self.GHSSlider.MaxValue * self.count)
        self:RefreshCostInfo(pruchase_num)
    end
end

function M:OnClicked_Minus()
    if self.purchase_num > 0 then
        self.purchase_num = self.purchase_num - 1
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue * self.purchase_num / self.count)
       
        local percent = self.purchase_num / self.count
        self.ProgressBar:SetPercent(percent)
        self.Text_Num:SetText(self.purchase_num)
        self.Text_NeedGold:SetText(self.purchase_num * self.price)
        if self.purchase_num <= 0 then
            self.GHSButtonPurchase:SetRenderOpacity(0.5)
            self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        else
            self.GHSButtonPurchase:SetRenderOpacity(1)
            self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end
end

function M:OnClicked_Add()
    if self.purchase_num < self.count then
        self.purchase_num = self.purchase_num + 1
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue * self.purchase_num / self.count)

        local percent = self.purchase_num / self.count
        self.ProgressBar:SetPercent(percent)
        self.Text_Num:SetText(self.purchase_num)
        self.Text_NeedGold:SetText(self.purchase_num * self.price)
        if self.purchase_num <= 0 then
            self.GHSButtonPurchase:SetRenderOpacity(0.5)
            self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        else
            self.GHSButtonPurchase:SetRenderOpacity(1)
            self.GHSButtonPurchase:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end
end

function M:OnClicked_Btn_Refresh()
    if self.shop_info.manual_refresh_times < self.shop_type_info.refreshTimes then
        if self.ShopType then
            local msg = { shop_id = self.ShopType }
            Client.send("req_shop_refresh", msg)
        end
    else
        UIManager:GetInstance():ShowConfirm({
            notice = Database.L10n(242),
            showCancel = false,
        })
    end
end

function M:OnClicked_Btn_Purchase()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    if self.ShopType then
        local msg = {}
        msg.shop_id = self.ShopType
        msg.shop_item_id = self.shop_info.shop_item_infos[self.SelectedItemIndex].shop_item_id
        msg.shop_item_count = self.purchase_num
        msg.last_auto_refresh_seconds = self.shop_info.last_auto_refresh_seconds
        ShopSystem:GetInstance():CachedPurchaseItems(msg.shop_id, msg.shop_item_id, msg.shop_item_count)
        Client.send("req_shop_buy", msg)
    end
end

--领取玩家等级奖励
-- function M:OnClicked_Level()
--     local haveReward, curLv = PlayerSystem:GetInstance():HavePlayerLevelAward()
--     if haveReward then
--         PlayerSystem:GetInstance():ReqPlayerReceiveLevelAward(curLv)
--     end
-- end

function M:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 then
        self:RefreshSidebar()
        if parsed_msg and parsed_msg.ntf_item_info and parsed_msg.ntf_item_info.changed_item_infos then
          
            local shop_item_info = self.shop_info.shop_item_infos[self.SelectedItemIndex].shop_config

            local bag_item_info
            if shop_item_info.itemType == UIUtils.ItemMainType.Weapon then
                bag_item_info = Database.Query("d_bag_item_weapon", shop_item_info.goodsId)
            elseif shop_item_info.itemType == UIUtils.ItemMainType.Equip then
                bag_item_info = Database.Query("d_bag_item_equip", shop_item_info.goodsId)
            else
                bag_item_info = Database.Query("d_bag_item", shop_item_info.goodsId)
            end

            local isUse = true
            local itemList = {}
            if bag_item_info then
                for _, changed_item_info in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
                    if changed_item_info.count > 0 then
                        isUse = false
                    end
                    if changed_item_info.item_id == bag_item_info.id then
                        table.insert(itemList, { item_id = changed_item_info.item_id, count = changed_item_info.count })
                    end
                end
            end 
            if #itemList > 0 and not isUse then
                self.UI_GetItem_Notice = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
                self.UI_GetItem_Notice:RefreshUI(itemList)
            end
        end
    end
end

-- function M:OnMsg_Player_Receive_Level_Award(rewardList)
--     --奖励按钮
--     local haveReward, _ = PlayerSystem:GetInstance():HavePlayerLevelAward()
--     self.Level:SetVisibility(haveReward and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

--     local info = {}
--     for _, v in pairs(rewardList) do
--         table.insert(info, {
--             itemId = v.item_id,
--             count = v.count,
--         })
--     end
--     UIUtils.ShowGetRewardCommonUI(self, info)
-- end 

function M:OnClick_Image_Mask(MyGeometry, MouseEvent)
    if self.UI_GetItem_Notice then
        UIManager:GetInstance():RemoveUI(self.UI_GetItem_Notice)
    end
end

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.quit, function()
        UIManager:GetInstance():RemoveUI(self)
        -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        -- gameInstance:RemoveUMG('UI_Shop')
    end)
    self:PlayAnimationReverse(self.quit, 1, false)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnMsg_Shop_Refresh()
    self:InitUI()
    self:RefreshSidebar()
end

return M
