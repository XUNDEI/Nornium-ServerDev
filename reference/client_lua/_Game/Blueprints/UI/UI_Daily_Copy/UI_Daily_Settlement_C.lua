--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Daily_Settlement_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self.SweepUI = {}
    NetworkMessageManager:GetInstance():AddListener("res_daily_level_sweep", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener("res_complete_daily_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener("res_daily_level_sweep", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
end

function M:Tick(MyGeometry, deltaTime)
    if self.bIsTimeBack then
        self.TimeCal = self.TimeCal + deltaTime
        if self.TimeCal >= 1.0 then
            self.TimeCal = 0
            self:OnTimeBack()
        end
    end
    if self.StartInitAnimation then
        self.PastTime = self.PastTime + deltaTime
        --延时0.5s 列表的item可能还没初始化完
        if self.PastTime > 0.05 then
            local realTime = self.PastTime - 1.5
            local curTime = self.ItemAnimationTime + (self.IntiAnimationIndex - 1) / 7 * self.ItemAnimationTime + (self.IntiAnimationIndex - 1) % 7 * self.ItemAnimationTime
            if realTime > curTime then
                local widgets = self.UI_Success_Settlement.ItemList:GetDisplayedEntryWidgets()
                if self.IntiAnimationIndex <= widgets:Length() then
                    local ui = widgets:Get(self.IntiAnimationIndex)
                    if ui then
                        ui:PlayAnimationForward(ui.Fly, 1, false)
                    end
                end
                self.IntiAnimationIndex = self.IntiAnimationIndex + 1
            end
        end
    end
end

function M:OnTimeBack()
    self.LeftTime = self.LeftTime - 1
    if self.LeftTime < 0 then
        self.bIsTimeBack = false
        self.TimeCal = 0

        if not self.FightResult then
            local msg = { result = false }
            NetworkMessageManager:GetInstance():AddListener("res_complete_daily_level_fight", self)
            Client.send("req_complete_daily_level_fight", msg)
        else
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance.BackFromFight = true
            gameInstance.ToCityFromFightArgString = 'UI_Daily_Copy'
            gameInstance.fightRestart = false
            gameInstance:LoadBackLevel()
        end
    else
        self.UI_Fail_Settlement.TimeText:SetText(tostring(self.LeftTime) .. 's')
    end
end

function M:RefreshUI(fight_result, changed_item_infos)
    self.FightResult = fight_result
    if fight_result then
        self.UI_Success_Settlement.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
            self:BP_OnEntryInitialized(item, widget)
        end)
        self.UI_Success_Settlement.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
            self:BP_OnItemClicked(item)
        end)

        
        self.UI_Success_Settlement:PlayAnimationForward(self.UI_Success_Settlement.start, 1, false)

        --门票-1
        if not BackpackSystem:GetInstance():AddItemCount(UIUtils.EItemId.DailyCopyTicket, -1) then
            BackpackSystem:GetInstance():AddItemCount(UIUtils.EItemId.DailyCopySweep, -1)
        end

        self.changed_item_infos = changed_item_infos or {}
        self.UI_Success_Settlement:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.UI_Fail_Settlement:SetVisibility(UE.ESlateVisibility.Hidden)

        self.UI_Success_Settlement.Btn_Use.OnGHSClicked:Add(self, self.OnClicked_Btn_Use)
        self.UI_Success_Settlement.Btn_ReStart.OnGHSClicked:Add(self, self.Restart)
        self.UI_Success_Settlement.Btn_Cancel.OnGHSClicked:Add(self, self.OnClicked_Btn_Cancel)

        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        self.ItemDataSource = {}
        for i = 1, #self.changed_item_infos do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = changed_item_infos[i].item_id
            table.insert(self.ItemDataSource, ItemData)
        end
        self.UI_Success_Settlement.ItemList:BP_SetListItems(self.ItemDataSource)

        --刷新购买扫荡卷次数
        self.UI_Success_Settlement.Text_NeedGold:SetText('')
        --刷新扫荡卷个数
        local skip_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
        local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
        local skipAvailable = skip_count > 0
        local ticketAvailable = ticket_count > 0
        local restartAvailable = skipAvailable or ticketAvailable
        self.UI_Success_Settlement.Text_NeedGold_1:SetText('1')
        self.UI_Success_Settlement.Text_HaveGold_1:SetText('/' .. tostring(skip_count))
        if not restartAvailable then
            self.UI_Success_Settlement.Img_Bg:SetVisibility(UE.ESlateVisibility.Visible)
            self.UI_Success_Settlement.Img_Bg.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Btn_Bg)
        end
        self.UI_Success_Settlement.Bottom:SetVisibility(restartAvailable and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.UI_Success_Settlement.Panel_Null:SetVisibility(not restartAvailable and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

        self.UI_Success_Settlement.Btn_Use:SetIsEnabled(skipAvailable)
        --扫荡卷 图片
        local iconPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201001_png.Icon_mini_1201001_png'
        local skipRes = LoadObject(iconPath)
        if skipRes then
            self.UI_Success_Settlement.Image_6:SetBrushFromAtlasInterface(skipRes)
        end
        --再次挑战 门票图片
        iconPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201003_png.Icon_mini_1201003_png'
        local ticketRes = LoadObject(iconPath)
        self.UI_Success_Settlement.Text_NeedGold_2:SetText('1')
        if ticketAvailable then
            if ticketRes then
                self.UI_Success_Settlement.Image_9:SetBrushFromAtlasInterface(ticketRes)
            end
            self.UI_Success_Settlement.Text_HaveGold_2:SetText('/' .. tostring(ticket_count))
        else
            if skipAvailable then
                if skipRes then
                    self.UI_Success_Settlement.Image_9:SetBrushFromAtlasInterface(skipRes)
                end
                self.UI_Success_Settlement.Text_HaveGold_2:SetText('/' .. tostring(skip_count))
            end
        end

        if #self.ItemDataSource > 0 then
            self.PastTime = 0
            self.IntiAnimationIndex = 1
            self.StartInitAnimation = true
        end
    else
        self.UI_Fail_Settlement:PlayAnimationForward(self.UI_Fail_Settlement.vfxIn, 1, false)
        self.UI_Success_Settlement:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Fail_Settlement:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

        self.UI_Fail_Settlement.Btn_Purchase_1.OnClicked:Add(self, self.OnClicked_Btn_Purchase)
        self.UI_Fail_Settlement.Btn_Start.OnClicked:Add(self, self.OnClicked_Btn_Start)

        --倒计时
        self.LeftTime = 15
        self.TimeCal = 0
        self.bIsTimeBack = true
    end
end

function M:BP_OnEntryInitialized(item, widget)
    local itemConfig = UIUtils.GetItemConfigById(item.ItemId)
    local data = {}
    data.config = itemConfig
    widget.index = item.index
    widget.item_data = itemConfig
    if itemConfig then
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end
        
        --类型
        --icon
        if itemConfig.iconPath and itemConfig.iconPath ~= '' then
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.Visible)
            local strArr = string.split(itemConfig.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        else
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
        widget.Text_Count:SetText(self.changed_item_infos[item.Index].count)
    end
    widget.ItemList:SetRenderOpacity(0)
    --点击事件
    widget.ItemList:SetVisibility(UE.ESlateVisibility.Visible)
end

function M:BP_OnItemClicked(item)
    print('-----------------clicked' .. tostring(item.ItemId))
    UIUtils.ShowItemInfo(item.ItemId, self.changed_item_infos[item.Index].count)
end


function M:OnClicked_Btn_Use()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    Client.send("req_daily_level_sweep", gameInstance.fightMsg)
    print('---------------------->>>OnClicked_Btn_Use')
end

function M:Restart()
    local skipCount = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
    local ticketCount = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
    if ticketCount == 0 and skipCount == 0 then
        UIManager:GetInstance():Notify(Database.L10n(284))
        return
    end

    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    gameInstance.BackFromFight = true
    if gameInstance.fightType ~= gameInstance.FIGHT_STATE.CharTrainCopy then
        gameInstance.ToCityFromFightArgString = 'LoadFightBefore'
    end
   
    gameInstance.fightCanBack = false
    gameInstance:LoadBackLevel()
end

function M:OnClicked_Btn_Cancel()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.BackFromFight = true
    gameInstance.ToCityFromFightArgString = 'UI_Daily_Copy'
    gameInstance:LoadBackLevel()
end

function M:res_complete_daily_level_fight(result, msgId, parsed_msg)
    if result == 0 then
        --门票-1
        if not BackpackSystem:GetInstance():AddItemCount(UIUtils.EItemId.DailyCopyTicket, -1) then
            BackpackSystem:GetInstance():AddItemCount(UIUtils.EItemId.DailyCopySweep, -1)
        end

        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
        gameInstance.fightCanBack = false 
        gameInstance.fightRestart = false
        gameInstance:LoadBackLevel()
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
        gameInstance.fightCanBack = false 
        gameInstance.fightRestart = false
        gameInstance:LoadBackLevel()
    end
end

function M:res_daily_level_sweep(result, msgId, parsed_msg)
    if result == 0 then
        local ui_settlement = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Sweep_Settlement')
        ui_settlement:SetBackUI(self, self.changedItemInfos)

        BackpackSystem:GetInstance():AddItemCount(UIUtils.EItemId.DailyCopySweep, -1)
    
        --刷新扫荡卷个数
        -- local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
        -- self.UI_Success_Settlement.Text_NeedGold_1:SetText('1')
        -- self.UI_Success_Settlement.Text_HaveGold_1:SetText('/' .. tostring(ticket_count))

        -- self.UI_Success_Settlement.Btn_Use:SetIsEnabled(ticket_count > 0)

        --刷新扫荡卷个数
        local skip_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
        local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
        local skipAvailable = skip_count > 0
        local ticketAvailable = ticket_count > 0
        local restartAvailable = skipAvailable or ticketAvailable
        self.UI_Success_Settlement.Text_NeedGold_1:SetText('1')
        self.UI_Success_Settlement.Text_HaveGold_1:SetText('/' .. tostring(skip_count))
        if not restartAvailable then
            self.UI_Success_Settlement.Img_Bg:SetVisibility(UE.ESlateVisibility.Visible)
            self.UI_Success_Settlement.Img_Bg.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Btn_Bg)
        end
        self.UI_Success_Settlement.Bottom:SetVisibility(restartAvailable and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.UI_Success_Settlement.Panel_Null:SetVisibility(not restartAvailable and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

        self.UI_Success_Settlement.Btn_Use:SetIsEnabled(skipAvailable)

    elseif result == 1 then
        UIManager:GetInstance():Notify(Database.L10n(284))
    else
        LOG_WARN("Res Daily Level Sweep Error Code:", result)
    end
end

function M:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_item_info and parsed_msg.ntf_item_info.changed_item_infos then
            self.changedItemInfos = {}
            self.changedItemInfos = parsed_msg.ntf_item_info.changed_item_infos
        end
    end
end

--取消挑战
function M:OnClicked_Btn_Purchase()
    if not self.FightResult then
        self.UI_Fail_Settlement:PlayAnimationForward(self.UI_Fail_Settlement.vfxExit, 1, false)
        local msg = { result = false }
        NetworkMessageManager:GetInstance():AddListener("res_complete_daily_level_fight", self)
        Client.send("req_complete_daily_level_fight", msg)
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Daily_Copy'
        gameInstance.fightRestart = false
        gameInstance:LoadBackLevel()
    end
end

--重新开始
function M:OnClicked_Btn_Start()
    self.UI_Fail_Settlement:PlayAnimationForward(self.UI_Fail_Settlement.vfxExit, 1, false)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.BackFromFight = true
    if gameInstance.fightType ~= gameInstance.FIGHT_STATE.CharTrainCopy then
        gameInstance.ToCityFromFightArgString = 'LoadFightBefore'
    end
    gameInstance.fightCanBack = false
    gameInstance.fightRestart = true
    gameInstance:LoadBackLevel()
end

function M:OnClicked_Btn_Bg()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.BackFromFight = true
    gameInstance.fightRestart = false
    gameInstance.ToCityFromFightArgString = 'UI_Daily_Copy'
    gameInstance:LoadBackLevel()
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:IA_Back()
    if self.FightResult then
        self:OnClicked_Btn_Cancel()
    else
        self:OnClicked_Btn_Purchase()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)

return M
