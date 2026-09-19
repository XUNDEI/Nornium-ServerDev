local UIUtils = require "_Game.Utils.UIUtils"
local Protos = require("Helper.Protos")
local GlobalConfig = require "GlobalConfig"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()
local SrpgController = require "Module.Srpg.SrpgController"
local Client = require "Network.Client"

---@type UI_character_exchange_C
local M = UnLua.Class()

function M:Initialize()
    if not M.BP_GHSFunctionLibraryRef then
        M.BP_GHSFunctionLibrary = LoadClass("/Game/_Game/Blueprints/Game/BP_GHSFunctionLibrary.BP_GHSFunctionLibrary_C")
        M.BP_GHSFunctionLibraryRef = UnLua.Ref(M.BP_GHSFunctionLibrary)
        M.CHARACTER_ICON = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_character_icon.UI_character_icon_C')
        M.CHARACTER_ICONRef = UnLua.Ref(M.CHARACTER_ICON)
    end
end

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_UNIVERSE_CHANGE_CHARACTER, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_UNIVERSE_CHANGE_CHARACTER, self)
end

---@param self UI_character_exchange_C
---@param parsed_msg ResUniverseChangeCharacterMessage
M[Protos.RES_UNIVERSE_CHANGE_CHARACTER] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

        ---@type SG_TeamList_C
        local teams = gameInstance:LoadTeamList()

        if not teams then
            return
        end
        
        ---@type FST_TeamInfo
        local team
        ---@param value FST_TeamInfo
        for key, value in pairs(teams.SpecialTeamInfo) do
            -- if value.bIsSelected then
                team = value.RoleList
            -- end
            break
        end

        if not team then
            return
        end

        team[self.selectedCharacterIndex] = self.targetCharacterId
        gameInstance:SaveTeamList()

        SrpgController:GetInstance():ChangeCharacter(self.selectedCharacterIndex, self.targetCharacterId)

        playerController.BP_PlayerController_UniverseMenu.UI_Menu:UpdateHp()

        MessageManager:Broadcast('OnMsg_Change_Character')
        
        self:Close()
    end
end

function M:Close()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_UniverseMenu.UI_Menu:CloseChangeCharacter()
end

function M:Init()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    self.selectedCharacterIndex = playerController.BP_PlayerController_UniverseMenu.UI_Menu.selectedCharacterIndex

    self.characterIds = {}
    
    for index, value in ipairs(SrpgController:GetInstance():GetCharacterFightData()) do
        self.characterIds[index] = value.character_id
    end

    self.Modal.OnClicked:Clear()
    self.Modal.OnClicked:Add(self, function()
        self:Close()
    end)

    local substitutionCost = Database.Query("d_srpg_map_base", SrpgController:GetInstance().model.mapId).substitutionCost

    self.price = substitutionCost[2]

    self.Cost:SetText(tostring(self.price))
    if SrpgController:GetInstance():GetResource(substitutionCost[1]) >= self.price then
        self.Cost:SetColorAndOpacity(M.BP_GHSFunctionLibrary.HexToSlateColor("#ecf1ff"))
    else
        self.Cost:SetColorAndOpacity(M.BP_GHSFunctionLibrary.HexToSlateColor("#FF0000FF"))
    end

    self.targetCharacterId = nil

    ---@type CharacterInfo[]
    local characters = CharacterSystem:GetInstance().CharacterInfo
    local checkboxGroup = playerController.BP_PlayerController_UniverseMenu.UI_Menu.UI_character_exchange.CharacterIconGroup
    checkboxGroup:ResetToggleState()

    self.CharacterIcons:ClearChildren()
    for i, characterInfo in ipairs(characters) do
        ---@type UI_character_icon_C
        local characterIcon = NewObject(M.CHARACTER_ICON)

        self.CharacterIcons:AddChild(characterIcon)

        ---@type UUniformGridSlot
        local slot = characterIcon.Slot
        slot:SetHorizontalAlignment(UE.EHorizontalAlignment.HAlign_Center)
        slot:SetVerticalAlignment(UE.EVerticalAlignment.VAlign_Center)
        slot:SetColumn(math.floor((i - 1) / 2))
        slot:SetRow((i - 1) % 2)

        characterIcon.characterId = characterInfo.character_id

        local headRes = Database.Query("d_character", characterInfo.character_id).headRes

        --头像
        local HeadPath = UIUtils.GetCharacterIdolIcon(characterInfo.character_id, headRes)
        local iconTexture = LoadObject(HeadPath)
        if iconTexture then
            characterIcon.Icon:SetBrushFromAtlasInterface(iconTexture)
        end

        characterIcon.CharacterCheckbox.CheckBoxGroup = checkboxGroup

        characterIcon.CharacterCheckbox.OnCheckStateChanged:Add(characterIcon, function(_, isOn)
            if isOn then
                self.targetCharacterId = characterInfo.character_id
            else
                if self.targetCharacterId == characterInfo.character_id then
                    self.targetCharacterId = nil
                end
            end

            self:UpdateConfirmButton()
        end)

        local available = not table.indexof(self.characterIds, characterInfo.character_id)

        characterIcon.hp:SetVisibility(available and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        characterIcon.CharacterCheckbox:SetIsEnabled(available)
    end

    self.Confirm.OnClicked:Clear()
    self.Confirm.OnClicked:Add(self.Confirm, function()
        ---@type ReqUniverseChangeCharacter
        local msg = {}
        msg.character_id = self.targetCharacterId
        msg.character_index = self.selectedCharacterIndex - 1
        Client.send(Protos.REQ_UNIVERSE_CHANGE_CHARACTER, msg)
    end)

    self:UpdateConfirmButton()
end

function M:UpdateConfirmButton()
    local substitutionCost = Database.Query("d_srpg_map_base", SrpgController:GetInstance().model.mapId).substitutionCost

    local affordable = SrpgController:GetInstance():GetResource(substitutionCost[1]) >= substitutionCost[2]
    local selected = self.targetCharacterId and true or false
    self.Confirm:SetIsEnabled(affordable and selected)
end

function M:Show()
    self:Init()

    self:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

return M
