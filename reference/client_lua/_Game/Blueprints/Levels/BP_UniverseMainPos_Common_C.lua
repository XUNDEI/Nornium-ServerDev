--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"
-- local BP_Univers_ViceMode = UE.UClass.Load("/Game/_Game/Blueprints/Levels/BP_Univers_ViceMode.BP_Univers_ViceMode_C")

---@type BP_UniverseMainPos_Common_C
local M = UnLua.Class()

function M:Initialize(Initializer)
    self.place_card_infos = {}
    self.card_models = {}
end

function M:Init(index, type_id, pos_id, showViceModel)
    self.Index = index
    self.TypeId = type_id
    self.PosId = pos_id
    self:RefreshMainPos()
    if showViceModel then
        self:SpawnViceModel()
    end
    -- self:RefreshCardModel()
end

function M:RefreshMainPos()
    if self.TypeId ~= 0 then
        --static mesh
        -- local model_path = "/Game/_Game/3DRES/scene/SRPG/mainPos/%s"
        -- local model_name = Database.Query('d_srpg_main_pos_base', self.TypeId).posModel
        -- if model_name ~= "" then
        --     model_path = string.format(model_path, model_name)
        --     local meshObject = LoadObject(model_path)
        --     if meshObject then
        --         self.StaticMesh:SetStaticMesh(meshObject)
        --     end
        -- else
        self.StaticMesh:SetHiddenInGame(true, false)
        -- end
        --niagara
        local niagara_path = "/Game/_Game/3DRES/Effect/NiagaraSystem/Sence/Changjing/%s.%s"
        local niagara_name = Database.Query('d_srpg_main_pos_base', self.TypeId).posEffect
        if niagara_name ~= "" then
            niagara_path = string.format(niagara_path, niagara_name, niagara_name)
            local niagara = LoadObject(niagara_path)
            if niagara then
                self.Niagara:SetAsset(niagara, true)
            end
        end
        --name
        local widgets = self:K2_GetComponentsByClass(UE.UWidgetComponent)
        local widget_num = widgets:Length()
        for j = 1, widget_num do
            local widgetObject = widgets[j]:GetUserWidgetObject()
            local UI_Com_NPC = widgetObject:Cast(UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Com_NPC.UI_Com_NPC_C"))
            if UI_Com_NPC then
                local nameId = Database.Query('d_srpg_main_pos_base', self.TypeId).nameId
                UI_Com_NPC:UpdateText(Database.L10n(nameId))
                break
            end
        end
    end
end

function M:SpawnViceModel()
    if self.ViceMode == nil then
        local vice_models = Database.Query('d_srpg_main_pos_base', self.TypeId).vicePosMods
        local model_num = #vice_models
        local index = math.random(model_num)
        local model_id = vice_models[index]
        local ViceMode_path = string.format("/Game/_Game/Blueprints/Levels/SRPG/Mods/BP_ViceMode%d.BP_ViceMode%d_C", model_id,
            model_id)
        -- local ViceMode_path = string.format('/Game/_Game/Blueprints/Levels/SRPG/Mods/BP_T1.BP_T1_C')
        local vice_class = UE.UClass.Load(ViceMode_path)
        if vice_class then
            local location = self.SC_StayPos:K2_GetComponentLocation()
            local transform = UE.UKismetMathLibrary.MakeTransform(location, UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))
            local vice_model = self:GetWorld():SpawnActor(vice_class, transform,
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
            vice_model:SetActorScale3D(self:GetActorScale3D())
            self.ViceMode = vice_model
            if vice_model then
                self.VicePoses = vice_model.VicePoses
            end
        end
    end
end

function M:RefreshCardModel()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.place_card_infos = gameInstance.mainPosInfos[self.PosId].card_in_place
end

function M:SetPlanetVisibility(visible)
    if visible then
        self.StaticMesh:SetHiddenInGame(false, false)
        self.Niagara:SetHiddenInGame(false, false)
        -- self.ViceMode:SetActorHiddenInGame(false)
        local player_controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        for _, explore_irem in pairs(player_controller.ExploreMainPosItems) do
            explore_irem:SetActorHiddenInGame(false)
        end
        for _, card_model in ipairs(self.card_models) do
            card_model:SetActorHiddenInGame(false)
        end
        for _, card_model in pairs(self.VicePoses) do
            card_model:SetActorHiddenInGame(false)
        end
    else
        self.StaticMesh:SetHiddenInGame(true, false)
        self.Niagara:SetHiddenInGame(true, false)
        -- self.ViceMode:SetActorHiddenInGame(true)
        local player_controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        for _, explore_irem in pairs(player_controller.ExploreMainPosItems) do
            explore_irem:SetActorHiddenInGame(true)
        end
        for _, card_model in ipairs(self.card_models) do
            card_model:SetActorHiddenInGame(true)
        end
        for _, card_model in pairs(self.VicePoses) do
            card_model:SetActorHiddenInGame(true)
        end
    end
end

-- function M:ReceiveBeginPlay()
-- end

-- function M:ReceiveEndPlay()
-- end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
