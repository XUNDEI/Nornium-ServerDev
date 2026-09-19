local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local HardLevelSystem = require "Module.HardLevel.HardLevelSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_ChallengeFightResult_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitUI()
    self:InitData()
end

function M:Destruct()
    self.TimeCal = 0
    self.bIsTimeBack = false
end

function M:Tick(MyGeometry, deltaTime)
    if self.bIsTimeBack then
        self.TimeCal = self.TimeCal + deltaTime
        if self.TimeCal >= 1.0 then
            self.TimeCal = 0
            self:OnTimeBack()
        end
    end
end

function M:InitUI()
    self.UI_ChallengeSuccess.Btn_Cancel.OnGHSClicked:Add(self, self.OnClicked_Btn_Cancel)
    self.UI_ChallengeSuccess.Btn_Restart:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.UI_ChallengeSuccess.Btn_Next.OnGHSClicked:Add(self, self.OnClicked_Btn_Next)

    self.UI_ChallengeSuccess.ListView_Reward.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.UI_ChallengeSuccess.ListView_Reward.BP_OnItemClicked:Clear()
    self.UI_ChallengeSuccess.ListView_Reward.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.UI_Fail_Settlement.Btn_Purchase_1.OnGHSClicked:Add(self, self.OnClicked_Btn_Cancel)
    self.UI_Fail_Settlement.Btn_Start:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.UI_Fail_Settlement.Restart:SetVisibility(UE.ESlateVisibility.Collapsed)

    --提示文字隐藏
    self.UI_Fail_Settlement.cost_3:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:InitData()
    self.TimeHandler = nil
end

function M:RefreshUI(fight_result, changed_item_infos)
    print("===挑战结果:" .. tostring(fight_result))
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)

    if fight_result then
        self.UI_ChallengeSuccess:PlayAnimationForward(self.UI_ChallengeSuccess.start, 1, false)
        
        self.changed_item_infos = changed_item_infos or {}
        self.UI_ChallengeSuccess:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.UI_Fail_Settlement:SetVisibility(UE.ESlateVisibility.Hidden)

        local challengeLevelId = HardLevelSystem:GetInstance().CachedHardLevelFightId
        print("====challengeLevelId:" .. tostring(challengeLevelId))
        local config = Database.Query('d_levels_challenge', challengeLevelId)
        local fightLevel = gameMode.FightLevel


        --reward
        self.UI_ChallengeSuccess.ListView_Reward:ClearListItems()
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        self.ItemDataSource = {}
       
        if #self.changed_item_infos > 0 then
            self.UI_ChallengeSuccess.Middle:SetVisibility(UE.ESlateVisibility.Visible)
            for i = 1, #self.changed_item_infos do
                local ItemData = NewObject(ItemClass)
                ItemData.Index = i
                ItemData.ItemId = changed_item_infos[i].item_id
                table.insert(self.ItemDataSource, ItemData)
            end
            self.UI_ChallengeSuccess.ListView_Reward:BP_SetListItems(self.ItemDataSource)
        else
            self.UI_ChallengeSuccess.Middle:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        
        if gameInstance.fightMsg and gameInstance.fightMsg.fight_level_id and gameInstance.fightMsg.fight_level_id >= 9 then
            self.UI_ChallengeSuccess.Btn_Next:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
    else
        self.UI_ChallengeSuccess:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Fail_Settlement:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.UI_Fail_Settlement.TimeText:SetText('15s')
        self.UI_Fail_Settlement.TextBlock_Restart:SetText("")

        self.LeftTime = 15
        self.TimeCal = 0
        self.bIsTimeBack = true
    end
end

function M:OnTimeBack()
    self.LeftTime = self.LeftTime - 1
    if self.LeftTime < 0 then
        self.bIsTimeBack = false
        self.TimeCal = 0

        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
        gameInstance.fightCanBack = true
        gameInstance:LoadBackLevel()
        
    else
        self.UI_Fail_Settlement.TimeText:SetText(tostring(self.LeftTime) .. 's')
    end
end


function M:LoadFightLevel(path)
    local classPath = path
    if not string.endswith(classPath, "_C'") then
        local sub = string.sub(classPath, 1, -2) .. "_C'"
        classPath = sub
    end
    local lvClass = UE.UClass.Load(classPath)
    return lvClass
end


function M:BP_OnEntryInitialized(item, widget)
    local itemConfig = UIUtils.GetItemConfigById(item.ItemId)
    local data = {}
    data.config = itemConfig
    widget.index = item.Index
    widget.item_data = itemConfig
    widget.ItemPanel:SetRenderOpacity(1)
    if itemConfig then
        widget.TextName:SetText(Database.L10n(itemConfig.itemName))
        widget.TextNum:SetText(self.changed_item_infos[item.Index].count)
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
    end
end

function M:BP_OnItemClicked(item)
    UIUtils.ShowItemInfo(item.ItemId, self.changed_item_infos[item.Index].count)
    
    -- local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Backpack/UI_ItemDetail.UI_ItemDetail_C")
    -- local ui = UE.UWidgetBlueprintLibrary.Create(self, widget_class)
    -- if ui then
    --     local itemConfig = UIUtils.GetItemConfigById(item.ItemId)
    --     local item_data = {}
    --     item_data.item_id = item.ItemId
    --     item_data.config = itemConfig
    --     item_data.count = UIUtils.GetItemCount(item.ItemId)
    --     ui:RefreshUI(item_data, nil)

    --     ui:AddToViewport()
    -- end
end

function M:OnClicked_Btn_Cancel()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
    gameInstance.BackFromFight = true
    gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
    gameInstance.fightCanBack = false
    gameInstance:LoadBackLevel()
end

function M:OnClicked_Btn_Restart()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.BackFromFight = true
    gameInstance.ToCityFromFightArgString = 'LoadFightBefore'
    gameInstance.fightCanBack = true
    gameInstance:LoadBackLevel()
end

function M:OnClicked_Btn_Next()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if gameInstance.fightType == gameInstance.FIGHT_STATE.ChallengeCopy then
        local challengeLevelId = HardLevelSystem:GetInstance():GetNextLevel()
        if challengeLevelId > 0 then
            local config = Database.Query('d_levels_challenge', challengeLevelId)
            if config then
                gameInstance.LevelClass = self:LoadFightLevel(config.path)
                gameInstance.fightMsg = 
                { 
                    activity_id = 1,
                    fight_level_id = challengeLevelId
                }
               
                --gameInstance.fightType = gameInstance.FIGHT_STATE.ChallengeCopy
                gameInstance.BackFromFight = true
                gameInstance.ToCityFromFightArgString = 'LoadFightBefore'
                gameInstance.fightCanBack = true
                gameInstance:LoadBackLevel()
                return
            end
        end
    else

    end
    
    gameInstance.BackFromFight = false
    gameInstance:LoadBackLevel()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Cancel)

return M