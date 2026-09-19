local Database = require "_Game.Utils.Database"
local SrpgController = require("Module.Srpg.SrpgController")
local hex_grid = require "Helper.hex_grid"
local SrpgModel = require("Module.Srpg.SrpgModel")
local GlobalConfig = require("GlobalConfig")

---@type BP_Map_Planet_C
local M = UnLua.Class()

local ICON_PATH = '/Game/_Game/TP_New/Universe_res/Frames/%s_png.%s_png'

function M:Initialize()
    if not M.BP_GHSFunctionLibraryRef then
        ---@type BP_GHSFunctionLibrary_C
        M.BP_GHSFunctionLibrary = LoadClass("/Game/_Game/Blueprints/Game/BP_GHSFunctionLibrary.BP_GHSFunctionLibrary_C")
        M.BP_GHSFunctionLibraryRef = UnLua.Ref(M.BP_GHSFunctionLibrary)
    end
end

function M:IsVisible()
    return self.mainPosInfo.state > 0
end

function M:IsReachable()
    return self.mainPosInfo.state > 1
end

function M:IsExplored()
    return self.mainPosInfo.state > 2
end

---@param mainPosInfo MainPosInfo
function M:UpdateMapPlanet(mainPosInfo)
    self.mainPosInfo = mainPosInfo

    self.mainPosConfig = Database.Query('d_srpg_main_pos_base', mainPosInfo.main_pos_id)
    self.showUI = self.mainPosConfig.isUIVisiable == 1

    self:UpdateEffects()
    self:SetUIZoomLevel(1.0)

    self:SetActorHiddenInGame(not self:IsVisible())
end

local MATERIAL_PATH = '/Game/_Game/3DRES/Effect/NiagaraSystem/Sence/INDICATOR/Indicator/%s.%s'

function M:UpdateEffects()
    self.Overridden.UpdateEffects(self)

    local effect = self.EF_map_planet_shubiao_zjd

    effect:SetVariableLinearColor("Color", M.BP_GHSFunctionLibrary.HexToColor(self.mainPosConfig.indicatorColor))
    effect:SetVariableMaterial("Material", LoadObject(string.format(MATERIAL_PATH, self.mainPosConfig.indicatorEffect, self.mainPosConfig.indicatorEffect)))
    
    ---@type UI_PointIcon_C
    local iconWidget = self.IconWidget:GetWidget()

    iconWidget.Boss:SetVisibility(UE.ESlateVisibility.Collapsed)

    ---@type BossInfo[]
    local bossInfo = SrpgController:GetInstance():GetBossInfo()
    for _, info in ipairs(bossInfo) do
        if info.hex.q == self.mainPosInfo.hex.q and info.hex.r == self.mainPosInfo.hex.r then
            iconWidget.Boss:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end

    iconWidget.Char:SetVisibility(hex_grid.equal(SrpgController:GetInstance():GetPlayerHex(), self.mainPosInfo.hex) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    ---@type UI_PointName_C
    local pointName = self.NameWidget:GetUserWidgetObject()
    -- pointName.pos_lock:SetVisibility((mainPosInfo.main_pos_card_pos_info and #mainPosInfo.main_pos_card_pos_info.card_locked_index > 0)
    --     and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    pointName.pos_lock:SetVisibility(UE.ESlateVisibility.Hidden)
        
    local name = Database.L10n(self.mainPosConfig.nameId)
    -- if self.placedCardId then
    --     local cardData = Database.Query("d_srpg_card_base", self.placedCardId)
    --     name = Database.L10n(cardData.nameId)
    -- end
    pointName:InitUI(name)
    pointName.name_panel:SetVisibility(not(self.mainPosConfig.type == 0) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    pointName.pos_icon:SetBrushFromAtlasInterface(LoadObject(string.format(ICON_PATH, self.mainPosConfig.posGraph, self.mainPosConfig.posGraph)))

    pointName.Hp:SetVisibility(hex_grid.equal(self.mainPosInfo.hex, SrpgController:GetInstance():GetBaseHex())
        and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    pointName.HpText:SetText(tostring(SrpgController:GetInstance():GetHp()))

    ---@type UI_PointLock_C
    local lock = self.LockWidget:GetUserWidgetObject()
    -- lock.Lock:SetVisibility((mainPosInfo.main_pos_card_pos_info and #mainPosInfo.main_pos_card_pos_info.card_locked_index > 0)
    --     and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    lock.Lock:SetVisibility(UE.ESlateVisibility.Hidden)

    ---@type UI_PointFrame_C
    local frame = self.FrameWidget:GetUserWidgetObject()
    -- frame.Frame:SetVisibility(SrpgController:GetInstance():GetPlayerHex() == self.PosId and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    frame.Frame:SetVisibility(UE.ESlateVisibility.Collapsed)

    local hasEmptySlot = false
    for _, info in pairs(self.mainPosInfo.main_pos_attach_infos) do
        if info.main_pos_attach_extra == SrpgModel.AttachType.Card then
            if info.main_pos_card_pos_info.card_id == 0 then
                hasEmptySlot = true
            end
        end
    end
    self.NG_UI_Tips:SetVisibility(hasEmptySlot, true)

    self.IconWidget:GetUserWidgetObject():SetRenderTransformPivot(UE.FVector2D(0.5, 1.0))

    self:SetColor(UE.UGHSFunctionLibrary.HexToColor(self.mainPosConfig.lineColor))
end

function M:OnBtnClicked_Event()
    self.Overridden.OnBtnClicked_Event(self)

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    playerController.BP_PlayerController_UniverseMenu.UI_Menu:RefreshInfoBoard(self.mainPosInfo)
end

function M:SetUIVisibility(Visible)
    self.EF_map_planet_shubiao_zjd:SetVisibility(Visible, true)
end

---@param widgetComponent UWidgetComponent
local function SetWidgetScale(widgetComponent, scale)
    local widget = widgetComponent:GetUserWidgetObject()
    widget:SetRenderScale(UE.UKismetMathLibrary.Vector2D_One() * scale)
end

function M:HideAllUI()
    self.showUI = false
    self:SetUIZoomLevel(self.scale)
end

function M:ResetUI()
    self.showUI = self.mainPosConfig.isUIVisiable == 1
    self:SetUIZoomLevel(self.scale)
end

function M:SetUIZoomLevel(scale)
    self.scale = scale
    local isMiniMap = scale < GlobalConfig.DetailThreshold
    self.EF_map_planet_shubiao_zjd:SetVisibility(isMiniMap and self.showUI, true)
    self.NameWidget:SetVisibility(not isMiniMap and self.showUI, true)
    self.FrameWidget:SetVisibility(isMiniMap and self.showUI, true)
    self.LockWidget:SetVisibility(isMiniMap and self.showUI, true)

    SetWidgetScale(self.IconWidget, scale)
    SetWidgetScale(self.LockWidget, scale)
    SetWidgetScale(self.NameWidget, scale)
    SetWidgetScale(self.FrameWidget, scale)
end

return M
