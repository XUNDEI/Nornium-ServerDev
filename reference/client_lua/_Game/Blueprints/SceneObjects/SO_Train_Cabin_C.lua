--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_Train_Cabin_C
local M = UnLua.Class()

local UIUtils = require('_Game.Utils.UIUtils')
local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local GachaSystem = require('Module.Gacha.GachaSystem')
local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')
local screen = require("Helper.Screen")

local EGachaItemType = 
{
    Weapon = 10, 
    Char = 1, 
    Build = 93, 
}

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
    self.BoxCollision.OnComponentBeginOverlap:Add(self, self.OnBoxCollisionOverlapStart)
    self.BoxCollision.OnComponentEndOverlap:Add(self, self.OnBoxCollisionOverlapEnd)

    self.bIsOpened = false

    self.CabinStartSequencePath = '/Game/_Game/Characters/perform/Cabin_Drawcards_start.Cabin_Drawcards_start'
    self.CabinEndSequencePath = '/Game/_Game/Characters/perform/Cabin_Drawcards_end.Cabin_Drawcards_end'

    self.CacheCharActor = {}
    self.CurActorQueue = {}
end

function M:ReceiveEndPlay()
    if self.CabinOpenLevelSequenceActor and UE.UKismetSystemLibrary.IsValid(self.CabinOpenLevelSequenceActor) then
        self.CabinOpenLevelSequenceActor:K2_DestroyActor()
    end
    self.CabinOpenLevelSequenceActor = nil 
    if self.CabinCloseLevelSequenceActor and UE.UKismetSystemLibrary.IsValid(self.CabinCloseLevelSequenceActor) then
        self.CabinCloseLevelSequenceActor:K2_DestroyActor()
    end
    self.CabinCloseLevelSequenceActor = nil
    if self.CharSequenceActor and UE.UKismetSystemLibrary.IsValid(self.CharSequenceActor) then
        self.CharSequenceActor:K2_DestroyActor()
    end
    self.CharSequenceActor = nil

    self.CurActorQueue = {}
    if self.CacheCharActor then
        for _, v in pairs(self.CacheCharActor) do
            v:K2_DestroyActor()
        end
        self.CacheCharActor = {}
    end
end

function M:OnBoxCollisionOverlapStart(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    if not self.GachaItemInfo then return end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                if not self.bIsOpened and not self.bIsPlayAnimation then
                    UIManager:GetInstance():ClearInteractOption()
                    UIManager:GetInstance():AddInteractOption(self, 436, function()
                        self:OnInteract()
                    end)
                    UIManager:GetInstance():AddInteractOption(self, 437, function()
                        self:OnInteractAll()
                    end)
                else
                    -- if self.bCanDing then
                    --     UIManager:GetInstance():AddInteractOption(self, 226, function()
                    --         self:OnClick_Ding()
                    --     end)
                    -- end
                end
            end
        end
    end
end

function M:OnBoxCollisionOverlapEnd(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    if not self.GachaItemInfo then return end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                if not self.bIsOpened and not self.bIsPlayAnimation then
                    UIManager:GetInstance():RemoveInteractOptionByObject(self)
                end
            end
        end
    end
end

function M:OnInteract()
    -- print('------onInteract:' .. tostring(self.Pos))
    self:OpenAnimStart(0)
end

function M:OnInteractAll()
    MessageManager:GetInstance():Broadcast('OnMsg_OpenAllCabin')
end


function M:OpenAnimStart(duration)
    -- print('-------OpenAnimStart"' .. tostring(duration))
    self.bIsPlayAnimation = true
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    if self.DoStartTimerHandler then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self.DoStartTimerHandler)
        self.DoStartTimerHandler = nil
    end
    if duration > 0 then
        self.DoStartTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.OnOpenAnimStartFinish }, 
            duration, 
            false
        )
    else
        self:OnOpenAnimStartFinish()
    end
end

function M:OnOpenAnimStartFinish()
    --播放角色模型
    if self.CharSequencePath ~= '' and self.ItemConfig ~= nil then
        self:PlaySequenceLoop(self.CharSequencePath, self.ItemConfig)
    end

    self.DoStartTimerHandler = nil
    self:PlaySequenceOpen(function() 
        local ui = self.Widget:GetWidget()
        if ui then
            -- ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
        self.bIsPlayAnimation = false
        self.bIsOpened = true
        MessageManager:GetInstance():Broadcast('OnMsg_SO_TrainCabin_Opened', self.GachaItemInfo.Item_Index, self.GachaItemInfo.bCanDing)
    end)
end

function M:OpenAnimEnd(duration)
    self.bIsPlayAnimation = true
    if self.DoEndTimerHandler then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self.DoEndTimerHandler)
        self.DoEndTimerHandler = nil
    end
    if duration > 0 then
        self.DoEndTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.OnOpenAnimEndFinish }, 
            duration, 
            false
        )
    else
        self:OnOpenAnimEndFinish()
    end
end

function M:OnOpenAnimEndFinish()
    self.DoEndTimerHandler = nil
    self:PlaySequenceClose(function() 
        local ui = self.Widget:GetWidget()
        if ui then
            -- ui:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        self.bIsOpened = false
        self.bIsPlayAnimation = false
        self.GachaId = 0
        self.GachaItemInfo = nil
        if self.CharSequenceActor then
            self.CharSequenceActor.SequencePlayer:GoToEndAndStop()
            self:ClearCacheCharActor()
        end
    end)
end

function M:ReplayStart(gachaId, itemInfo)
    self.bIsPlayAnimation = true
    self:PlaySequenceClose(function() 
        self.bIsOpened = false
        self.bIsPlayAnimation = false
        self.GachaId = 0
        self.GachaItemInfo = nil
        self:SetGachaItemInfo(gachaId, itemInfo)
        self.bIsPlayAnimation = true
        self:OnOpenAnimStartFinish()
    end)
end

--奖励道具
function M:RefreshRewardInfo(ui, itemType, rarity)
    local gachaTokenConfig = nil 
    local d_gacha_token = require('ClientDatas.d_gacha_token')
    for _, config in pairs(d_gacha_token) do
        if config.itemType == itemType and config.rarity == rarity then
            gachaTokenConfig = config
        end
    end
    -- print("----------->gachaTokenConfig:" .. tostring(table.dump(gachaTokenConfig, nil, 10)))
    if gachaTokenConfig then
        local gachaCoin = UIUtils.ECurrencyId.GachaCoinHigh
        local gachaCoinNum = gachaTokenConfig.goldenToken or 0
        if gachaTokenConfig.silverToken > 0 then
            gachaCoin = UIUtils.ECurrencyId.GachaCoinLow
            gachaCoinNum = gachaTokenConfig.silverToken
        end
        if self.LastGachCoin ~= gachaCoin then
            local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', gachaCoin, gachaCoin)
            local image = LoadObject(iconResPath)
            if image then
                ui.Img_Coin:SetBrushFromAtlasInterface(image)
            end
        end
       
        ui.Text_CoinNum:SetText(gachaCoinNum)
        -- ui.Panel_Coin:SetRenderOpacity(1)
        -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        ui:Coin_Visable(true)
    else
        -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.Hidden)
        ui:Coin_Visable(false)
    end
end

function M:OnClick_Ding()
    pring("-------------->ding")
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    GachaSystem:GetInstance():ReqGachaDing(self.GachaId, self.GachaItemInfo.Item_Index)
end

function M:SetGachaItemInfo(gachaId, itemInfo)
    self.GachaId = gachaId
    self.GachaItemInfo = itemInfo
    self:ClearCacheCharActor()
    self.CharSequencePath = ''
    --设置材质颜色
    self:SetColor(self.GachaItemInfo and (self.GachaItemInfo.gacha_item_rarity) or -1)
    self:SetIsChar(self.GachaItemInfo and (self.GachaItemInfo.gacha_item_type == EGachaItemType.Char) or false)
    if self.GachaItemInfo then
        local gachaItemConfig = Database.Query('d_gacha_item', self.GachaItemInfo.gacha_item_id)
        if gachaItemConfig and gachaItemConfig.itemid then
            --头顶上的widget
            local ui = self.Widget:GetWidget()
            if ui then
                -- print("------icon:" .. tostring(gachaItemConfig.showImage))
                if gachaItemConfig.showImage ~= '' then
                    local itemImg = LoadObject(gachaItemConfig.showImage)
                    if itemImg then
                        if UE.UGameplayStatics.ObjectIsA(itemImg, UE.UTexture2D) then
                            ui.Image_item:SetBrushFromTexture(itemImg)
                        else
                            ui.Image_item:SetBrushFromAtlasInterface(itemImg)
                        end
                    end
                end
                
                if self.GachaItemInfo.gacha_item_type == EGachaItemType.Char then --角色
                    -- print("-------->抽中角色")
                    self.Seat:SetVisibility(true, false)
                    self.Box:SetVisibility(false, false)
                    self.UI_Item:SetHiddenInGame(true, false)
                    self.UI_Item:GetWidget().Panel_Bg:SetRenderScale(UE.FVector2D(1, 1))
                    
                    local itemConfig = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
                    if itemConfig then
                        ui.Name:SetText(Database.L10n(itemConfig.itemName))
                        --命质
                        local charId = itemConfig.subParam[1]
                        if charId and charId > 0 then
                            local charConfig = Database.Query('d_character', charId)
                            if charConfig and charConfig.element then
                                local iconPath = string.format("/Game/_Game/TP_New/Gacha/Frames/gacha_element_%s_png.gacha_element_%s_png", charConfig.element, charConfig.element)
                                local iconObj = LoadObject(iconPath)
                                if iconObj then
                                    -- ui.Image_Icon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                                    ui.Image_Icon:SetBrushFromAtlasInterface(iconObj)
                                end
                            end
                            local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
                            ui.New:SetVisibility(charInfo and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
                            if charInfo then
                                --计算分解材料
                                if charConfig and charConfig.inbornItem then
                                    local inbornItemCount = UIUtils.GetItemCount(charConfig.inbornItem)
                                    if charInfo.talent_ids then
                                        for _, talentId in ipairs(charInfo.talent_ids) do
                                            local talentConfig = UIUtils.GetTalentConfig(talentId, charId)
                                            if talentConfig and talentConfig.openNeed and talentConfig.openNeedPrice then
                                                if talentConfig.openNeed == UIUtils.EOpenNeedType.CostItem and talentConfig.openNeedPrice[1] == charConfig.inbornItem then
                                                    inbornItemCount = inbornItemCount + 1
                                                end
                                            end
                                        end
                                    end
                                    --满命表
                                    local itemType = inbornItemCount >= 6 and 2 or 1
                                    self:RefreshRewardInfo(ui, itemType, self.GachaItemInfo.gacha_item_rarity)
                                    if inbornItemCount >= 6 then
                                        self:Convert(2)
                                    else
                                        self:Convert(0)
                                    end
                                end
                            else
                                self:Convert(-1)
                                -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.Hidden)
                                ui:Coin_Visable(false)
                            end
                        else
                            self:Convert(-1)
                            ui.New:SetVisibility(UE.ESlateVisibility.Hidden)
                            -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.Hidden)
                            ui:Coin_Visable(false)
                        end
                       
                        local skinId = itemConfig.subParam[2]
                        if skinId and skinId > 0 then
                            skinId = skinId - 1000000
                            local config = require('ClientDatas.d_char_clothes')[skinId]
                            --播放sequence
                            if gachaItemConfig.sequencePath ~= '' and config then
                                self.CharSequencePath = gachaItemConfig.sequencePath
                                self.ItemConfig = config
                                -- self:PlaySequenceLoop(gachaItemConfig.sequencePath, config)
                            end
                        end
                    else
                        self:Convert(-1)
                        ui.New:SetVisibility(UE.ESlateVisibility.Hidden)
                        -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.Hidden)
                        ui:Coin_Visable(false)
                    end
                    --if gachaItemConfig.sequencePath ~= '' then
                        -- self:PlaySequenceLoop(gachaItemConfig.sequencePath)
                        --self.CharSequencePath = gachaItemConfig.sequencePath
                    --end
                elseif self.GachaItemInfo.gacha_item_type == EGachaItemType.Build then --建筑
                    -- print("-------->抽中建筑")
                    local itemConfig = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
                    if itemConfig then
                        local charId = itemConfig.subParam[1]
                        if charId and charId > 0 then
                            local charConfig = Database.Query('d_character', charId)
                            if charConfig and charConfig.idolProfile and charConfig.idolProfile ~= '' then
                                local sprite_path = string.format('/Game/_Game/TP_New/Gacha/Frames/gacha_%s_png.gacha_%s_png', charConfig.idolProfile, charConfig.idolProfile)
                                local sprite_object = UE.UObject.Load(sprite_path)
                                if sprite_object then
                                    local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
                                    ui.Image_Icon:SetBrush(icon_sprite)
                                end 
                            end
                        end
                        ui.Name:SetText(Database.L10n(itemConfig.itemName))
                    end
                    self.Seat:SetVisibility(false, false)
                    self.Box:SetVisibility(true, false)
                    self.UI_Item:SetHiddenInGame(false, false)
                    self.UI_Item:GetWidget().Panel_Bg:SetRenderScale(UE.FVector2D(1, 1))
                    self:RefreshItemUI(self.UI_Item:GetWidget(), gachaItemConfig.itemid)
                    
                    -- ui.Image_Icon:SetVisibility(UE.ESlateVisibility.Hidden)
                    --家具是否已经有了
                    local itemCount = UIUtils.GetItemCount(gachaItemConfig.itemid)
                    print("-------->道具:" .. tostring(gachaItemConfig.itemid) .. ",count:" .. tostring(itemCount))
                    if itemCount >= 1 then
                        self:RefreshRewardInfo(ui, 4, self.GachaItemInfo.gacha_item_rarity)
                        self:Convert(1)
                    else
                        self:Convert(-1)
                        -- ui.Panel_Coin:SetVisibility(UE.ESlateVisibility.Hidden)
                        ui:Coin_Visable(false)
                    end
                    --新获取道具
                    ui.New:SetVisibility(itemCount >= 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
                elseif self.GachaItemInfo.gacha_item_type == EGachaItemType.Weapon then --武器
                    -- print("-------->抽中武器")
                    self.Seat:SetVisibility(false, false)
                    self.Box:SetVisibility(true, false)
                    self.UI_Item:SetHiddenInGame(false, false)
                    self.UI_Item:GetWidget().Panel_Bg:SetRenderScale(UE.FVector2D(1, 1))
                    self:RefreshItemUI(self.UI_Item:GetWidget(), gachaItemConfig.itemid)
                    local itemCount = UIUtils.GetItemCount(gachaItemConfig.itemid)

                    local hasWeapon = CharacterSystem:GetInstance():HasWeaponInAllCharacter(gachaItemConfig.itemid)
                    local isNew = not hasWeapon and (itemCount <= 0)
                    --新获取道具
                    ui.New:SetVisibility(isNew and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
                    self:Convert(-1)
                    local itemConfig = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
                    if itemConfig then
                        ui.Name:SetText(Database.L10n(itemConfig.itemName))
                        --武器类型
                        -- ui.Image_Icon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                        local icon = LoadObject(string.format('/Game/_Game/TP_New/Gacha/Frames/gacha_weapons_%s_png.gacha_weapons_%s_png', itemConfig.subType, itemConfig.subType))
                        ui.Image_Icon:SetBrushFromAtlasInterface(icon)
                    end

                    --武器每次都给
                    self:RefreshRewardInfo(ui, 3, self.GachaItemInfo.gacha_item_rarity)
                end
                ui:Star(self.GachaItemInfo.gacha_item_rarity)
            end
        end
    end
end

function M:RefreshItemUI(itemUI, itemId)
    if itemUI then
        local itemConfig = UIUtils.GetItemConfigById(itemId)
        if itemConfig then
            --稀有度背景图片
            -- if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            --     local strArr = string.split(itemConfig.rarityPath, '/')
            --     local littePath = strArr[#strArr]
            --     local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            --     local itemRarityPic = LoadObject(rarityPath)
            --     if itemRarityPic then
            --         itemUI.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            --     end
            -- end

            if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                local strArr = string.split(itemConfig.iconPath, '/')
                local littePath = strArr[#strArr]
                local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                -- print('---iconResPath:' .. tostring(iconResPath))
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    itemUI.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
                end
            end
        end
    end
end

--开门动画
function M:PlaySequenceOpen(callback)
    if self.CabinOpenLevelSequenceActor then
        self.CabinOpenLevelSequenceActor:K2_DestroyActor()
        self.CabinOpenLevelSequenceActor = nil 
    end
    if not self.CabinOpenLevelSequenceActor then
        local levelSequence = LoadObject(self.CabinStartSequencePath)

        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(self.CabinStartSequencePath))
            return 
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.CabinOpenLevelSequenceActor = sequenceActor

        self.CabinOpenLevelSequenceActor:AddBindingByTag("MainObj", self, false)
        
        self.CabinOpenLevelSequenceActor:K2_AttachToActor(self, "",
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            false)
    end

    if self.CabinOpenLevelSequenceActor and self.CabinOpenLevelSequenceActor.SequencePlayer then
        self.CabinOpenLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        self.CabinOpenLevelSequenceActor.SequencePlayer.OnFinished:Add(self, function()
            self.CabinOpenLevelSequenceActor.SequencePlayer.OnFinished:Clear()
            if callback then
                callback(self)
            end
        end)
        self.CabinOpenLevelSequenceActor.SequencePlayer:Play()
    end
end

--关门动画
function M:PlaySequenceClose(callback)
    if self.CharSequenceActor then
        self.CharSequenceActor.SequencePlayer:GoToEndAndStop()
        self:ClearCacheCharActor()
    end
    if self.CabinCloseLevelSequenceActor then
        self.CabinCloseLevelSequenceActor:K2_DestroyActor()
        self.CabinCloseLevelSequenceActor = nil 
    end

    if not self.CabinCloseLevelSequenceActor then
        local levelSequence = LoadObject(self.CabinEndSequencePath)

        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(self.CabinEndSequencePath))
            return 
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.CabinCloseLevelSequenceActor = sequenceActor
        self.CabinCloseLevelSequenceActor:AddBindingByTag("MainObj", self, false)
        
        self.CabinCloseLevelSequenceActor:K2_AttachToActor(self, "",
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            false)
    end

    if self.CabinCloseLevelSequenceActor and self.CabinCloseLevelSequenceActor.SequencePlayer then
        self.CabinCloseLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        self.CabinCloseLevelSequenceActor.SequencePlayer.OnFinished:Add(self, function()
            self.CabinCloseLevelSequenceActor.SequencePlayer.OnFinished:Clear()

            if self.CharSequenceActor and UE.UKismetSystemLibrary.IsValid(self.CharSequenceActor) then
                self.CharSequenceActor:K2_DestroyActor()
            end
            self.CharSequenceActor = nil
            if self.CurActorQueue then
                for _, v in pairs(self.CurActorQueue) do
                    v:SetActorHiddenInGame(true, false)
                end
            end

            if callback then
                callback(self)
            end
        end)
        self.CabinCloseLevelSequenceActor.SequencePlayer:Play()
    end
end

--角色循环动画
function M:PlaySequenceLoop(sequencePath, config)
    -- print('--------PlaySequenceLoop:' .. tostring(sequencePath))
    local levelSequence = LoadObject(sequencePath)
    if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(sequencePath))
        return 
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    if not self.CharSequenceActor then
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.CharSequenceActor = sequenceActor
        
       
        -- self.CharSequenceActor:K2_AttachToActor(self, "",
        --     UE.EAttachmentRule.KeepWorld,
        --     UE.EAttachmentRule.KeepWorld,
        --     UE.EAttachmentRule.KeepWorld,
        --     false)
    else
        self.CharSequenceActor.SequencePlayer:GoToEndAndStop()
        self.CharSequenceActor:SetSequence(levelSequence)
    end
    if self.CharSequenceActor and self.CharSequenceActor.SequencePlayer then
        self.CharSequenceActor:AddBindingByTag("CabinObj", self, false)
        -- print("---------" .. config.modelF)
        -- print("---------" .. config.modelHair)
        -- print("---------" .. config.modelFace)
        --身体
        if config.modelF and config.modelF ~= '' then
            local skeletonActor = self.CacheCharActor[config.modelF]
            if not skeletonActor then
                skeletonActor = self:GetWorld():SpawnActor(UE.LoadClass("Class '/Script/Engine.SkeletalMeshActor'"))
                self.CacheCharActor[config.modelF] = skeletonActor
            end
            local newMesh = LoadObject(config.modelF)
            if newMesh and skeletonActor then
                skeletonActor:SetActorHiddenInGame(false, false)
                skeletonActor.SkeletalMeshComponent:SetSkeletalMeshAsset(newMesh, false)
                self.CharSequenceActor:AddBindingByTag("MainObj", skeletonActor, false)
                self.CurActorQueue[config.modelF] = skeletonActor
                -- local mats = newMesh:GetMaterials()
                -- for i = 1, mats:Length() do
                --     local mi = mats:Get(i).MaterialInterface
                --     skeletonActor.SkeletalMeshComponent:CreateDynamicMaterialInstance(i - 1, mi)
                -- end
            end
        end
        --头发
        if config.modelHair and config.modelHair ~= '' then
            local skeletonActor = self.CacheCharActor[config.modelHair]
            if not skeletonActor then
                skeletonActor = self:GetWorld():SpawnActor(UE.LoadClass("Class '/Script/Engine.SkeletalMeshActor'"))
                self.CacheCharActor[config.modelHair] = skeletonActor
            end
            local newMesh = LoadObject(config.modelHair)
            if newMesh and skeletonActor then
                skeletonActor:SetActorHiddenInGame(false, false)
                skeletonActor.SkeletalMeshComponent:SetSkeletalMeshAsset(newMesh, false)
                self.CharSequenceActor:AddBindingByTag("HairObj", skeletonActor, false)
                self.CurActorQueue[config.modelHair] = skeletonActor
            end
        end
        --脸
        if config.modelFace and config.modelFace ~= '' then
            local skeletonActor = self.CacheCharActor[config.modelFace]
            if not skeletonActor then
                skeletonActor = self:GetWorld():SpawnActor(UE.LoadClass("Class '/Script/Engine.SkeletalMeshActor'"))
                self.CacheCharActor[config.modelFace] = skeletonActor
            end
            local newMesh = LoadObject(config.modelFace)
            if newMesh then
                skeletonActor:SetActorHiddenInGame(false, false)
                skeletonActor.SkeletalMeshComponent:SetSkeletalMeshAsset(newMesh, false)
                self.CharSequenceActor:AddBindingByTag("FaceObj", skeletonActor, false)
                self.CurActorQueue[config.modelFace] = skeletonActor
            end
        end
       
        self.CharSequenceActor.SequencePlayer:PlayLooping(-1)
        -- self.CharSequenceActor:K2_AttachToActor(self, "",
        --     UE.EAttachmentRule.KeepWorld,
        --     UE.EAttachmentRule.KeepWorld,
        --     UE.EAttachmentRule.KeepWorld,
        --     false)
    end
end

function M:ClearCacheCharActor()
    for _, v in pairs(self.CurActorQueue) do
        v:SetActorHiddenInGame(true, false)
    end
    self.CurActorQueue = {}
end
return M
