local NetCmdController = require "Framework.Common.NetCmdController"
local M = BaseClass("BuildSystem", NetCmdController)
local Client = require "Network.Client"
local Questsystem = require("Module.Quest.QuestSystem")
local UIUtils = require("_Game.Utils.UIUtils")

function M:ClearCache()
    self.CachedInteractBuildId = 0
end

----------------------------------------------------------------------
--请求指定id的建筑物个数
function M:GetBuildCount(itemId)
    local result = 0
    if self.BuildInfo then
        for _, build in pairs(self.BuildInfo) do 
            if build.item_id == itemId then
                result = result + 1
            end
        end
    end
    return result
end

function M:GetBuildClothSkinId(itemId)
    if self.BuildInfo then
        for _, build in pairs(self.BuildInfo) do
            if build.item_id == itemId then
                return build.skinId
            end
        end
    end
    return 0
end


----------------------------------------------------------------------
--请求建筑信息
function M:ReqHome()
    
end 

--请求建筑信息返回
function M:OnNetCmd_Res_Home(result, msgId, parsed_msg)
    if result == 0 then
        self.BuildInfo = parsed_msg.res_home.home_info.home_furniture_infos
        self.BuildInteractInfo = parsed_msg.res_home.home_info.home_furniture_interact_info
        self:ParseBuildInfo()
    end
end

--请求开始建造
function M:ReqBuildHome(info)
    self.CachedInteractBuildId = 0
    if '' ~= info and self.BuildInfo ~= info then
        self.CachedBuildInfo = info
        Client.send('req_build_home', {
            home_furniture_infos = info
        })
    end
end

--请求开始建造返回
function M:OnNetCmd_Res_Build_Home(result, msgId, parsed_msg)
    if result == 0 then
        self.BuildInfo = self.CachedBuildInfo
        self:ParseBuildInfo()
        -- self.CachedBuildInfo = nil
        local QuestSystem = require "Module.Quest.QuestSystem"
        for _, v in pairs(self.BuildInfo) do
            QuestSystem:GetInstance():OnMsg_BuildCreate(v.item_id)
        end
        MessageManager:GetInstance():Broadcast('OnResBuildHome')
    end
end

function M:ParseBuildInfo()
    for _, v in pairs(self.BuildInfo) do
        if v.block == '' then
            v.posIndex = 0
            v.skinId = 0
        else
            print('----str:' .. tostring(v.blob))
            local rapidjson = require "rapidjson"
            local json = rapidjson.decode(v.blob)
            v.posIndex = json.posIndex
            v.skinId = json.skinId
        end
    end
end

----------------------------------------------------------------------
---请求家具交互
function M:ReqBuildInteract(buildId)
  
    local d_com_params = require('ClientDatas.d_com_params')
    local allCount = tonumber(d_com_params[25].value2)
    if self.BuildInteractInfo then
        if self.BuildInteractInfo.last_refresh_seconds > 0 then
            local UIUtils = require('_Game.Utils.UIUtils')
            local time = UIUtils.get_daily_refresh(self.BuildInteractInfo.last_refresh_seconds)
            if time > 0 then --可以刷新了
                self.BuildInteractInfo.received_furniture_coin_from_interact = 0
            end
        end

        if self.BuildInteractInfo.received_furniture_coin_from_interact < allCount then
            self.CachedInteractBuildId = buildId
            local msg = {
                item_id = buildId,
            }
            local isInSend = self:ReqMsgIsInSendCache('req_receive_furniture_coin_from_interact', msg)
            if not isInSend then
                Client.send('req_receive_furniture_coin_from_interact', msg)
                return true
            end
        end
    end
    return false
end

--请求家具交互返回
function M:OnNetCmd_Res_Receive_Furniture_Coin_From_Interact(result, msgId, parsed_msg)
    if result == 0 then
        if self.BuildInteractInfo then
            local d_com_params = require('ClientDatas.d_com_params')
            local getMaxCount = tonumber(d_com_params[25].value2)

            local Database = require("_Game.Utils.Database")
            local addCount = Database.Query('d_bag_item_furniture', self.CachedInteractBuildId).tokenInteract
            local allCoinCount = self.BuildInteractInfo.received_furniture_coin_from_interact + addCount
            self.BuildInteractInfo.received_furniture_coin_from_interact = math.min(allCoinCount, getMaxCount)

            local realAddCount = addCount 
            local offsetCount = math.abs(allCoinCount - self.BuildInteractInfo.received_furniture_coin_from_interact)
            realAddCount = realAddCount - offsetCount
            --弹框
            -- local rewardList = {}
            -- table.insert(rewardList, {
            --     itemId = UIUtils.ECurrencyId.PalacePoints,
            --     count = addCount,
            -- })
            -- local PlayerSystem = require('Module.Player.PlayerSystem')
            -- UIUtils.ShowGetRewardCommonUI(PlayerSystem:GetInstance().GameInstance, rewardList)
            MessageManager:GetInstance():Broadcast('OnMsg_BuildCoin', realAddCount)
        end
       
    end
    self.CachedInteractBuildId = 0
end

--获取今日获得金币
function M:GetBuildCoinCount()
    if self.BuildInteractInfo then
        return self.BuildInteractInfo.received_furniture_coin_from_interact or 0
    end
    return 0
end
----------------------------------------------------------------------
---缓存模型
function M:GetCharacterMeshFromCache(world, path)
    if not self.CachedActor then
        self.CachedActor = {}
    end
    if not self.CachedActor[path] then
        self.CachedActor[path] = world:SpawnActor(UE.LoadClass(path))
    end
    local actor = self.CachedActor[path]
    actor:SetActorHiddenInGame(false)
    return actor
end

function M:CacheCharacterMesh(actor)
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(0, 0, -5000),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    actor:SetActorHiddenInGame(true)
    actor:K2_SetActorTransform(trans, false, nil, false)
end

function M:ClearAllCachedCharacterMesh()
    if self.CachedActor then
        for _, actor in pairs(self.CachedActor) do
            if UE.UGameplayStatics.IsValid(actor) then
                actor:K2_DestroyActor()
            end
        end 
    end
    self.CachedActor = {}
end

return M
