require "UnLua"
local Client = require "Network.Client"
local hex_grid = require "Helper.hex_grid"
local Database = require "_Game.Utils.Database"
local UIUtils = require "_Game.Utils.UIUtils"

---@type BP_GameMode_City_C
local M = UnLua.Class()

function M:Initialize(Initializer)
    self.planetNum = 0
    self.planetId = 0
end

function M:SpawnActors()
    --刚进入游戏时生成主控角色的判断条件
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    if saveGameSpeak.StoryFinished then
        self.Overridden.SpawnActors(self)
    elseif playerController.LoadStateTreeAfterEnterGameEnd then
        self.Overridden.SpawnActors(self)
    -- elseif gameInstance.BackFromFight then
    --     self.Overridden.SpawnActors(self)
    end
end

function M:OnSpawnActorsEnd()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if self.Player then
        local curCharacterId = gameInstance:GetPlayerCharacterIdInCity()
        local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(curCharacterId)
        if savedCityCharId > 0 and (savedCityCharId ~= defaultCityCharId) then
            gameInstance:ChangeDress()
        end
        self.DressCharId = savedCityCharId <= 0 and defaultCityCharId or savedCityCharId
    end
end


function M:ChangeCharacter(id)
    local modelPath = Database.Query("d_character", id).cityModelPath
    local strArr = string.split(modelPath, '/')
    local path = string.format("'/Game/_Game/Blueprints/Players/%s.%s_C'", modelPath, strArr[2]) 
    local playerClass = LoadClass(path)

    local oldCharacter = UE.UGameplayStatics.GetPlayerController(self, 0):K2_GetPawn()
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(0, 0, 0),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    if oldCharacter then
        trans = oldCharacter:GetTransform() 
    end
    local newCharacter = self:GetWorld():SpawnActor(playerClass,
        trans, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    gameInstance.Walk = false
    UE.UGameplayStatics.GetPlayerController(self, 0):Possess(newCharacter)
    if oldCharacter then
        oldCharacter:K2_DestroyActor()
    end
end

function M:ChangePlayerCharacterInCity(character_id)
    self.Overridden.ChangePlayerCharacterInCity(self, character_id)
    if self.Player then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(character_id)
        if savedCityCharId > 0 and (savedCityCharId ~= defaultCityCharId) then
            local config = Database.Query("d_char_clothes", savedCityCharId)
            if config and config.modelF ~= '' then
                local newMesh = LoadObject(config.modelF)
                if newMesh then
                    if character_id == 10601 then
                        self.Player.SkeletalMesh:SetSkeletalMeshAsset(newMesh)
                        local mats = newMesh:GetMaterials()
                        for i = 1, mats:Length() do
                            local mi = mats:Get(i).MaterialInterface
                            self.Player.SkeletalMesh:CreateDynamicMaterialInstance(i - 1, mi)
                        end
                    else
                        self.Player.Mesh:SetSkeletalMeshAsset(newMesh)
                    end
                end
            end
        end
        self.DressCharId = savedCityCharId <= 0 and defaultCityCharId or savedCityCharId
    end
end

function M:ChangeDress()
    --print("===self.Player:" .. tostring(self.Player) .. ",self.DressCharId:" .. tostring(self.DressCharId))
   
    if self.Player then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local curCharacterId = gameInstance:GetPlayerCharacterIdInCity()
        local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(curCharacterId)
        --print("-->>changeDress:" .. tostring(savedCityCharId) .. ",defualtCharid:" .. tostring(defaultCityCharId))
        if savedCityCharId > 0 and (savedCityCharId ~= self.DressCharId) then
            local config = Database.Query("d_char_clothes", savedCityCharId)
            if config and config.modelF ~= '' then
                local newMesh = LoadObject(config.modelF)
                if newMesh then
                    if curCharacterId == 10601 then
                        self.Player.SkeletalMesh:SetSkeletalMeshAsset(newMesh)
                        local mats = newMesh:GetMaterials()
                        for i = 1, mats:Length() do
                            local mi = mats:Get(i).MaterialInterface
                            self.Player.SkeletalMesh:CreateDynamicMaterialInstance(i - 1, mi)
                        end
                    else
                        self.Player.Mesh:SetSkeletalMeshAsset(newMesh)
                    end
                end
            end
        end
        self.DressCharId = savedCityCharId <= 0 and defaultCityCharId or savedCityCharId
    end 
end

---------------------------Cmd---------------------------
function M:OnGHSCMD(msg)
    LOG_INFO("===请求GM命令:" .. tostring(msg))
    local array = string.split(msg, ' ')
    if array[1] == 'add_item' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'change_character' then
        self:ChangeCharacter(tonumber(array[2]))
    elseif array[1] == 'showchar' then
        print('===========showchar')
        MessageManager:GetInstance():Broadcast("showchar")
    elseif array[1] == 'add_character' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'openstory' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:OpenStory(tonumber(array[2]))
    elseif array[1] == 'opentoturial' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ShowTutorial(tonumber(array[2]), array[3])
    elseif array[1] == 'ShowAllUI' then
        local bVisible = tonumber(array[2]) == 1
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if bVisible then
            gameInstance:ShowAllUI()
        else
            gameInstance:HideAllUI()
        end
    elseif array[1] == 'statree' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
        saveGameSpeak.StoryFinished = false
        saveGameSpeak.PlotIndex = tonumber(array[2])
        gameInstance:SaveSaveGameSpeak()

        gameInstance:ReturnToLoginMap()
    elseif array[1] == 'loading2' then
        UE.UGameplayStatics.GetGameInstance(self):AddUMG("UI_Loading2", nil, 1)
    elseif array[1] == 'add_plot_completed_mission' then
        local d_task_story = require('ClientDatas.d_task_story')
        for i = 2, #array do
            local mission_id = tonumber(array[i] or -1)
            if mission_id then
                if not d_task_story[mission_id] then
                    LOG_ERROR('-------错误id:' .. tostring(mission_id) .. ' is not in d_task_story')
                    return  
                end
            end
        end
        Client.send("req_gm_cmd", { cmd = msg })
       
    elseif array[1] == 'plot_index' then
        if array[2] then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local SaveGameSpeak = gameInstance:LoadSaveGameSpeak()
            SaveGameSpeak.PlotIndex = tonumber(array[2])
            gameInstance:SaveSaveGameSpeak()
        else
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local SaveGameSpeak = gameInstance:LoadSaveGameSpeak()
            print("---------------plot index:" .. SaveGameSpeak.PlotIndex)
        end
    elseif array[1] == 'complete_plot_mission' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local msg = { mission_id = tonumber(array[2]) }
        local PlotSystem = require "Module.Plot.PlotSystem"
        PlotSystem:GetInstance():ReqCompletePlotMission(msg)
        gameInstance.req_data.req_complete_plot_mission = msg
    elseif array[1] == 'load_plot' then
        local msg = { cmd = msg }
        Client.send("req_gm_cmd", msg)
    elseif array[1] == 'play_plot_node' then
        local msg = { cmd = msg }
        Client.send("req_gm_cmd", msg)
    elseif array[1] == 'clear_savegame_mission_info' then
        local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        if saveGameSpeak then
            saveGameSpeak.MissionInfo = ''
        end
        self.GameInstance:SaveSaveGameSpeak()
    -- elseif array[1] == 'change_server_time' then
    --     local time = UIUtils.ParseTimeStr(array[2] .. ' ' .. array[3])
    --     local msg = { cmd = 'change_server_time ' .. tostring(time) }
    --     Client.send("req_gm_cmd", msg)
    elseif array[1] == 'add_month_card' then
        local msg = { cmd = 'add_month_card' }
        Client.send("req_gm_cmd", msg)
    elseif array[1] == 'set_next_map_data_id' then
        local msg = { cmd = "set_next_map_data_id "..array[2] }
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'showfocus' then
        LOG_INFO("show")
        UE.UGHSFunctionLibrary.DebugFocus()
    else
        local type = array[1]
        table.remove(array, 1)
        UE.UGameplayStatics.GetGameInstance(self):OnMessage(type, array)
    end
    self.Overridden.OnGHSCMD(self, msg)
end

return M
