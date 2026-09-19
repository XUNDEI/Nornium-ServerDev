local Client = require "Network.Client"
local Database = require("_Game.Utils.Database")
local UIUtils = require "_Game.Utils.UIUtils"
local BP_GameInstance_C = require "_Game.Blueprints.Game.BP_GameInstance_C"

---@type SrpgController
local SrpgController = require("Module.Srpg.SrpgController")
local CharacterSystem = require("Module.CharacterSystem.CharacterSystem")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SRPG_Start_C
local M = UnLua.Class()

local MapSizeMap = {
    Small = 1,
    Medium = 2,
    Big = 3,
}

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
    UE.UGameplayStatics.GetGameInstance(self):ShowTopUI(true)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

function M:Construct()
    MessageManager:GetInstance():AddListener(BP_GameInstance_C.TeamListUpdated, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(BP_GameInstance_C.TeamListUpdated, self)
end

M[BP_GameInstance_C.TeamListUpdated] = function(self)
    self:UpdateTeam()
end

local ICON_NAME = "BtnSelect_%d"

function M:InitUIEx()
    self:InitUI()
end

function M:InitUI()
    if self.inited then
        return
    end
    self:LoadOptions()

    self.characterIds = {}

    self.AddDifficulty.OnClicked:Add(self.AddDifficulty, function()
        self:ChangeDifficulty(1)
        self:UpdateDifficulty()
    end)
    self.ReduceDifficulty.OnClicked:Add(self.ReduceDifficulty, function()
        self:ChangeDifficulty(-1)
        self:UpdateDifficulty()
    end)

    for name, mapSize in pairs(MapSizeMap) do
        if self.mapSize == mapSize then
            self[name]:SetIsCheckedAndFireEvent(true)
        end
        self[name].OnCheckStateChanged:Add(self[name], function()
            self.mapSize = mapSize
        end)
    end

    for i = 1, 3 do
        local iconName = string.format(ICON_NAME, i)
        self[iconName].OnClicked:Add(self[iconName], function()
            self:OpenTeamList()
        end)
    end

    self.Btn_Start.OnClicked:Add(self.Btn_Start, function()
        self:SaveOptions()
        self:Start()
    end)

    self.Exit.OnClicked:Add(self.Exit, function()
        self:Close()
    end)

    self.inited = true
    
    self:SetupTeam()
    self:UpdateDifficulty()

    --临时频闭大型和小型，弹框
    self.Img_Big_Temp.OnMouseButtonDownEvent:Bind(self, function()
        UIUtils.ShowNotify(self, Database.L10n(50500))
        return UE.UWidgetBlueprintLibrary.Handled()
    end)
    self.Img_Small_Temp.OnMouseButtonDownEvent:Bind(self, function()
        UIUtils.ShowNotify(self, Database.L10n(50500))
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    self.PrevMap.OnClicked:Add(self.PrevMap, function()
        UIUtils.ShowNotify(self, Database.L10n(50500))
    end)

    self.NextMap.OnClicked:Add(self.PrevMap, function()
        UIUtils.ShowNotify(self, Database.L10n(50500))
    end)
end

function M:LoadOptions()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    SrpgController:GetInstance():Load(gameInstance.account_id)
    
    local saveGame = SrpgController:GetInstance().model.saveGame

    self.difficulty = saveGame.LastDifficulty
    self.planetId = saveGame.LastPlanetId
    self.mapSize = saveGame.LastMapSize
    self.team = saveGame.LastTeam
end

function M:SaveOptions()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    SrpgController:GetInstance():Load(gameInstance.account_id)

    local saveGame = SrpgController:GetInstance().model.saveGame

    saveGame.LastDifficulty = self.difficulty
    saveGame.LastPlanetId = self.planetId
    saveGame.LastMapSize = self.mapSize

    SrpgController:GetInstance():Save(gameInstance.account_id)
end

function M:ChangeDifficulty(delta)
    LOG_INFO(self.difficulty, delta)
    self.difficulty = math.min(math.max(1, self.difficulty + delta), 8)
end

function M:OpenTeamList()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.IsSpecialTeamInfo = true
    gameInstance.fightCanBack = true
    gameInstance:ShowTopUI(false)

    ---@type BP_PlayerController_City_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_City_UniverseBridge:LoadFightBefore(false, false)
end

function M:UpdateDifficulty()
    local difficultyText = Database.L10n(Database.Query("d_srpg_map_level", self.difficulty).txtId)
    if self.difficulty <= 3 then
        self.DifficultyText:SetText(difficultyText)
    else
        self.DifficultyText:SetText(difficultyText .. tostring(self.difficulty - 3))
    end

    local difficultyDesc = string.format(Database.L10n(461), Database.Query("d_srpg_map_level", self.difficulty).proposeLevel)

    self.DifficultyDesc:SetText(difficultyDesc)
end

function M:SetupTeam()
    ---@type SG_TeamList_C
    local teamList = UE.UGameplayStatics.GetGameInstance(self):LoadTeamList()

    ---@type FST_TeamInfo
    local teamInfo = teamList.SpecialTeamInfo:Get(1)
    for i = 1, self.team:Length() do
        teamInfo.RoleList:Set(i, self.team:Get(i))
    end
    for i = self.team:Length() + 1, 3 do
        teamInfo.RoleList:Set(i, 0)
    end

    UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
end

local CHARACTER_ICON_NAME = "character_%d"

function M:UpdateTeam()
    ---@type SG_TeamList_C
    local teamList = UE.UGameplayStatics.GetGameInstance(self):LoadTeamList()

    ---@type FST_TeamInfo
    local teamInfo = teamList.SpecialTeamInfo:Get(1)

    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    SrpgController:GetInstance():Load(gameInstance.account_id)
    
    local saveGame = SrpgController:GetInstance().model.saveGame

    for index, id in pairs(teamInfo.RoleList) do
        saveGame.LastTeam:Set(index, id)
    end

    SrpgController:GetInstance():Save(gameInstance.account_id)

    self.team = saveGame.LastTeam

    for index, id in pairs(self.team) do
        ---@type UImage
        local iconWidget = self[string.format(CHARACTER_ICON_NAME, index)]
        iconWidget:SetVisibility(id <= 0 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
        if id > 0 then
            local characterInfo = Database.Query("d_character", id)
            local headPath = UIUtils.GetCharacterIdolIcon(id, characterInfo.headRes)
            local iconTexture = LoadObject(headPath)
            if iconTexture then
                iconWidget:SetBrushFromAtlasInterface(iconTexture)
            end
        end
    end
end

function M:Start()
    ---@type ReqNewUniverse
    local msg = {}
    msg.difficulty_value = self.difficulty
    msg.main_planet_id = self.planetId

    msg.map_type = self.mapSize

    msg.character_ids = {}

    for index, id in pairs(self.team) do
        msg.character_ids[index] = id
    end
    
    Client.send("req_new_universe", msg)
end

return M
