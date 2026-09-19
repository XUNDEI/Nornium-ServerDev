local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local NetCmdController = require "Framework.Common.NetCmdController"
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local UIUtils = require '_Game.Utils.UIUtils'
local Database = require '_Game.Utils.Database'


local PlayerSystem = BaseClass("PlayerSystem", NetCmdController)

PlayerSystem.Level = 1
PlayerSystem.server_seconds = os.time()
PlayerSystem.seconds_offset = 0
PlayerSystem.server_time_offset = 0

function PlayerSystem:SetGameInstance(gameInstance)
    self.GameInstance = gameInstance
end

---服务器时间通知
function PlayerSystem:OnNetCmd_Ntf_Server_Time(result, msgId, parsed_msg)
    if result == 0 then
        local currentSeconds = math.modf(UE.UGameplayStatics.GetRealTimeSeconds(self.GameInstance))
        --上一次服务器时间 - 服务器时间
        PlayerSystem.server_seconds = parsed_msg.ntf_server_time.server_seconds
        PlayerSystem.seconds_offset = PlayerSystem.server_seconds - currentSeconds
    end
end

function PlayerSystem:OnNetCmd_Res_Player(result, msgId, parsed_msg)
    if result == 0 then
        --print("===res_player:" .. tostring(table.dump(parsed_msg, nil, 10)))
        ---@type PlayerInfo
        self.PlayerInfo = parsed_msg.res_player.player_info
        
        local UIUtils = require('_Game.Utils.UIUtils')
        self.Level = UIUtils.GetPlayerLevel()
    end
end

----------------------------------------------------------------------
--拾取道具信息
function PlayerSystem:GetPickingInfos()
    return self.PlayerInfo and self.PlayerInfo.player_picking_infos or nil
end

function PlayerSystem:GetPickInfo(itemId)
    if self.PlayerInfo and self.PlayerInfo.player_picking_infos then
        for _, pickInfo in pairs(self.PlayerInfo.player_picking_infos) do 
            if pickInfo.picking_id == itemId then
                return pickInfo
            end
        end
    end
    return nil
end

function PlayerSystem:GetSrpgGrowthExp()
    return BackpackSystem:GetInstance():GetItemCount(9003)
end

function PlayerSystem:GetSpendSrpgGrowthPoints()
    local res = 0
    for _, info in pairs(self.PlayerInfo.player_universe_growth_node_infos) do
        res = res + Database.Query("d_srpg_growth", info.node_id).cost * info.node_rank
    end

    return res
end

function PlayerSystem:GetSrpgGrowthLevel()
    local exp = self:GetSrpgGrowthExp()

    local levels = require("ClientDatas.d_srpg_exp")

    local level = 1

    for _, info in ipairs(levels) do
        if exp >= info.exp then
            exp = exp - info.exp
            level = level + 1
        else
            break
        end
    end

    return level, exp
end

function PlayerSystem:GetSrpgGrowthPoints()
    local level = self:GetSrpgGrowthLevel()
    return level - self:GetSpendSrpgGrowthPoints()
end

function PlayerSystem:LevelUpSrpgGrowthNode(nodeId)
    if self.PlayerInfo then
        local nodeIndex = table.first(self.PlayerInfo.player_universe_growth_node_infos, function(info)
            return info.node_id == nodeId
        end)
        if nodeIndex then
            local nodeInfo = self.PlayerInfo.player_universe_growth_node_infos[nodeIndex]
            local nodeConfig = Database.Query("d_srpg_growth", nodeInfo.node_id)

            if nodeInfo.node_rank < nodeConfig.level then
                nodeInfo.node_rank = nodeInfo.node_rank + 1
            end
        else
            table.insert(self.PlayerInfo.player_universe_growth_node_infos, {
                node_id = nodeId,
                node_rank = 1,
            })
        end
    end
end

function PlayerSystem:ResetSrpgGrowth()
    if self.PlayerInfo then
        self.PlayerInfo.player_universe_growth_node_infos = {}
    end
end

function PlayerSystem:GetSrpgGrowthNodeLevel(nodeId)
    if self.PlayerInfo then
        for _, info in pairs(self.PlayerInfo.player_universe_growth_node_infos) do
            if info.node_id == nodeId then
                return info.node_rank
            end
        end
    end
end

function PlayerSystem:GetPlayerName()
    return self.PlayerInfo.player_name
end

function PlayerSystem:GetUID()
    return self.PlayerInfo.player_id
end

function PlayerSystem:GetAvatar()
    return self.PlayerInfo.avatar_id
end

--请求拾取道具
function PlayerSystem:ReqPicking(itemId, itemActor)
    self.CachedPickingItemId = itemId
    self.CachedItemActor = itemActor
    local msg = {
        picking_id = itemId
    }
    Client.send('req_player_picking', msg)
end

--拾取道具返回
function PlayerSystem:OnNetCmd_Res_Player_Picking(result, msgId, parsed_msg)
    if result == 0 then
        if self.PlayerInfo and self.PlayerInfo.player_picking_infos then
            table.insert(self.PlayerInfo.player_picking_infos, {
                picking_id = self.CachedPickingItemId,
                picking_seconds = os.time()
            })
            local rewardList = {}
            local config = require('ClientDatas.d_com_picking')[self.CachedPickingItemId]
            for i = 1, #config.reward, 3 do 
                local itemId = config.reward[i]
                local count = config.reward[i + 2]
                table.insert(rewardList, {
                    itemId = itemId,
                    count = count,
                })
            end
            MessageManager:GetInstance():Broadcast('OnPickSuccess', rewardList)
            if self.CachedItemActor then
                self.CachedItemActor:Update()
                self.CachedPickingItemId = nil
                self.CachedItemActor = nil
            end
        end 
    end
end
--
----------------------------------------------------------------------
---领取玩家等级奖励
function PlayerSystem:ReqPlayerReceiveLevelAward(lv)
    self.CachedPlayerReceiveLevel = lv
    local msg = {
        level = lv,
    }
    
    NetworkMessageManager:GetInstance():AddListener('ntf_item_info', self)
    Client.send('req_player_receive_level_award', msg)
end


--领取玩家等级奖励
function PlayerSystem:OnNetCmd_Res_Player_Receive_Level_Award(result, msgId, parsed_msg)
    NetworkMessageManager:GetInstance():RemoveListener('ntf_item_info', self)
    if result == 0 then
        if self.PlayerInfo and self.PlayerInfo.received_level_awards and self.CachedPlayerReceiveLevel > 0 then 
            self.PlayerInfo.received_level_awards[self.CachedPlayerReceiveLevel] = true
            if self.changed_item_infos then
                MessageManager:GetInstance():Broadcast("OnMsg_Player_Receive_Level_Award", self.changed_item_infos)
            end
        end
    end
end

--判定是否有玩家奖励可领取
function PlayerSystem:HavePlayerLevelAward()
    if self.PlayerInfo and self.PlayerInfo.received_level_awards then
        --获取最低的可激活的等级
        for curLv = 1, self.Level do
            if not self.PlayerInfo.received_level_awards[curLv] then 
                return true, curLv
            end
        end
        return not self.PlayerInfo.received_level_awards[self.Level]
    end
    return false, 1
end

function PlayerSystem:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 and
        parsed_msg and 
        parsed_msg.ntf_item_info and 
        parsed_msg.ntf_item_info.changed_item_infos then
        self.changed_item_infos = parsed_msg.ntf_item_info.changed_item_infos    
    end
end

function PlayerSystem:OnNetCmd_Ntf_Server_Time_Offset(result, msgId, parsed_msg)
    if result == 0 then
        --print("-----时间:" .. tostring(parsed_msg.ntf_server_time_offset.offset))
        self.server_time_offset = parsed_msg.ntf_server_time_offset.offset
    end
end

function PlayerSystem:GetServerTime()
    if PlayerSystem.seconds_offset <= 0 then
        return os.time()
    end
    local currentSeconds = math.modf(UE.UGameplayStatics.GetRealTimeSeconds(self.GameInstance)) 
    return currentSeconds + PlayerSystem.seconds_offset
end

function PlayerSystem:OnNetCmd_Res_Record_Player_Transform_In_Scene(result, msgId, parsed_msg)
    if result == 0 then
        local find = false
        for i, player_transform_in_scene in ipairs(self.PlayerInfo.player_transform_in_scenes) do
            if player_transform_in_scene.scene_id == parsed_msg.req_data.player_transform_in_scene.scene_id then
                find = true
                self.PlayerInfo.player_transform_in_scenes[i] = parsed_msg.req_data.player_transform_in_scene
            end
        end

        if not find then
            table.insert(self.PlayerInfo.player_transform_in_scenes, parsed_msg.req_data.player_transform_in_scene)
        end
    end
end

function PlayerSystem:OnNetCmd_Res_Remove_Player_Transform_In_Scene(result, msgId, parsed_msg)
    if result == 0 then
        for _, scene_id in ipairs(parsed_msg.req_data.scene_ids) do
            for i, player_transform_in_scene in ipairs(self.PlayerInfo.player_transform_in_scenes) do
                if player_transform_in_scene.scene_id == scene_id then
                    table.remove(self.PlayerInfo.player_transform_in_scenes, i)
                    break
                end
            end
        end
    end
end

return PlayerSystem
