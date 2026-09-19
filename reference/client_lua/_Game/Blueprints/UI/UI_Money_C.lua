--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local MessageManager = require "Framework.Updater.MessageManager"

---@type UI_Money_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self:InitUI()
    self:InitData()
    self:RefreshUI()
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:OnMsg_Ntf_Item_Info()
    self:RefreshUI()
end
function M:InitUI()
    self.Btn_Icon1.OnGHSClicked:Add(self, self.OnClicked_Btn_Icon1)
    self.Btn_Icon2.OnGHSClicked:Add(self, self.OnClicked_Btn_Icon2)
    self.Btn_Icon3.OnGHSClicked:Add(self, self.OnClicked_Btn_Icon3)

    self.Btn_Currency1.OnGHSClicked:Add(self, self.OnClicked_Btn_Currency1)
    self.Btn_Currency2.OnGHSClicked:Add(self, self.OnClicked_Btn_Currency2)
    self.Btn_Currency3.OnGHSClicked:Add(self, self.OnClicked_Btn_Currency3)
end

function M:InitData()
    self.CurrencyData = { UIUtils.ECurrencyId.Gold, UIUtils.ECurrencyId.Diamond }
end

function M:RefreshUI()
    for i = 1, 3 do
        local ui = self.HorizontalBox:GetChildAt(i - 1)
        if ui then
            local currency_id = self.CurrencyData[i]
            if currency_id then
                ui:SetVisibility(UE.ESlateVisibility.Visible)
                self['TextCurrency' .. i]:SetText(UIUtils.GetItemCount(currency_id))
                local strIcon = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', currency_id, currency_id)
                local iconObject = LoadObject(strIcon)
                if iconObject then
                    self['iconCurrency' .. i]:SetBrushFromAtlasInterface(iconObject)
                end
                --按钮的显影
                local showExchangeBtn = false
                if currency_id == UIUtils.ECurrencyId.Diamond or 
                    currency_id == UIUtils.ECurrencyId.NolenLens or 
                    currency_id == UIUtils.EGachaTicket.GachaTickLimit or 
                    currency_id == UIUtils.EGachaTicket.GachaTickNormal then
                    showExchangeBtn = true
                end
                self['Btn_Currency' .. i]:SetVisibility(showExchangeBtn and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
            else
                ui:SetVisibility(UE.ESlateVisibility.Collapsed)
            end
        end
    end
end

function M:RefreshData(currencyData)
    if currencyData then
        self.CurrencyData = currencyData
    end
    self:RefreshUI()
end

function M:ExchangeCurrency(currencyId)
    if currencyId == UIUtils.ECurrencyId.Diamond then --钻石
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:AddUMG('UI_SwapMoney_C')
        if ui then
            local price = require('ClientDatas.d_gacha_params')[7].value2
            ui:RefreshMoney(currencyId, UIUtils.ECurrencyId.NolenLens, 1, price)
        end
    elseif currencyId == UIUtils.ECurrencyId.NolenLens then --充值币 直接跳转充值界面
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9029) then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            ---@type UI_TopUp_Shop_C
            local ui = gameInstance:AddUMG('UI_TopUp_Shop')
            ui.TopUp:SetIsCheckedAndFireEvent(true)
        end
    elseif currencyId == UIUtils.EGachaTicket.GachaTickLimit or --直接跳转商城
        currencyId == UIUtils.EGachaTicket.GachaTickNormal then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9029) then
            local ui = gameInstance:GetUMG('UI_TopUp_Shop')
            if ui and ui.ShowExchange then
                ui:ShowExchange()
            end
        end
    end
end

-------------------------------------------------------
-- ui event
function M:OnClicked_Btn_Icon1()
    UIUtils.ShowItemInfo(self.CurrencyData[1], 0)
end

function M:OnClicked_Btn_Icon2()
    UIUtils.ShowItemInfo(self.CurrencyData[2], 0)
end

function M:OnClicked_Btn_Icon3()
    UIUtils.ShowItemInfo(self.CurrencyData[3], 0)
end

function M:OnClicked_Btn_Currency1()
    local currencyId = self.CurrencyData[1]
    if currencyId and currencyId > 0 then
        self:ExchangeCurrency(currencyId)
    end
end

function M:OnClicked_Btn_Currency2()
    local currencyId = self.CurrencyData[2]
    if currencyId and currencyId > 0 then
        self:ExchangeCurrency(currencyId)
    end
end

function M:OnClicked_Btn_Currency3()
    local currencyId = self.CurrencyData[3]
    if currencyId and currencyId > 0 then
        self:ExchangeCurrency(currencyId)
    end
end

return M
