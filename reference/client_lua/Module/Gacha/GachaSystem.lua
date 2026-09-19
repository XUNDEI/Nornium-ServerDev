local NetCmdController = require "Framework.Common.NetCmdController"
local M = BaseClass("GachaSystem", NetCmdController)
local Client = require "Network.Client"

function M:GetGachaInfoByPoolId(poolId)
    if self.GachaInfo and self.GachaInfo.gacha_list_infos then
        return DeepCopy(self.GachaInfo.gacha_list_infos[poolId])
    end
    return nil
end

function M:IsFinished(poolId)
    local config = require('ClientDatas.d_gacha_list')[poolId]
    if config and self.GachaInfo and
        self.GachaInfo.finished_type_ids then
        local gachaType = config.gachaType
        for _, v in pairs(self.GachaInfo.finished_type_ids) do
            if v == gachaType then
                return true
            end
        end
    end

    return false
end

function M:GetGachaTypeInfoByPoolId(poolId)
    local config = require('ClientDatas.d_gacha_list')[poolId]
    local gachaType = config.gachaType == 0 and 3 or config.gachaType
    if self.GachaInfo and self.GachaInfo.gacha_type_infos[gachaType] then
        return DeepCopy(self.GachaInfo.gacha_type_infos[gachaType])
    end
    return nil
end

function M:IsFreeForFirstGacha()
    local UIUtils = require('_Game.Utils.UIUtils')
    local gachaType = UIUtils.EGachaPoolType.Normal 
    if self.GachaInfo and self.GachaInfo.gacha_type_infos[gachaType] then
        local typeInfos = self.GachaInfo.gacha_type_infos[gachaType]
        if typeInfos then
            local time = self:get_daily_refresh(typeInfos.free_seconds)
            if time > 0 then
                return true
            end
        end
    end
    return false
end

function M:get_daily_refresh(pre_time)
    local PlayerSystem = require('Module.Player.PlayerSystem')
    local now = PlayerSystem:GetInstance():GetServerTime()
    local temp_date = os.date("*t", now)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time and now >= temp_time then
        return temp_time
    end
    -- last day
    local last_date = os.date("*t", now)
    last_date.hour = 0
    last_date.min = 0
    last_date.sec = 0
    local last_time = os.time(last_date) - 1
    local temp_date = os.date("*t", last_time)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time then
        return temp_time
    end
    return 0
end

--判断指定池中道具是否可ding
function M:IsCanDing(gachaId, gachaItemInfo)
    local UIUtils = require "_Game.Utils.UIUtils"
    local config = require('ClientDatas.d_gacha_list')[gachaId]
    if not config or (config.gachaType ~= UIUtils.EGachaPoolType.CharPool and config.gachaType ~= UIUtils.EGachaPoolType.WeaponPool) then
        return false
    end
    if gachaItemInfo and not gachaItemInfo.ding and --还没叮过
        gachaItemInfo.pool_index == 1 then --是6星
        return true
    end
    return false
end

--获取还有多少可以叮的
function M:GetDingCount(poolId)
    local canDingAllCount = 0
    local gachaListInfos = self.GachaInfo.gacha_list_infos[poolId]
    if gachaListInfos then
        for _, v in pairs(gachaListInfos.gacha_pending_record_infos) do
            if v.bCanDing then canDingAllCount = canDingAllCount + 1 end
        end
    end
    return canDingAllCount 
end

function M:GetLastGachaCreateInfo()
    local UIUtils = require('_Game.Utils.UIUtils')
    if self.GachaInfo and self.GachaInfo.gacha_list_infos then
        for gachaId, gachaList in pairs(self.GachaInfo.gacha_list_infos) do
            local config = require('ClientDatas.d_gacha_list')[gachaId]
            -- if config and (config.gachaType == UIUtils.EGachaPoolType.CharPool or config.gachaType == UIUtils.EGachaPoolType.WeaponPool) then
            if config then
                if gachaList.gacha_pending_record_infos and
                    table.count(gachaList.gacha_pending_record_infos) > 0 then
                    return gachaId, DeepCopy(gachaList.gacha_pending_record_infos), config.gachaType
                end
            end
        end
    end
    return 0, nil, 0
end

function M:GetGachaParamsById(id)
    local d_gacah_params = require('ClientDatas.d_gacha_params')
    for _, v in pairs(d_gacah_params) do
        if v.id == id then
            return v 
        end
    end
    return nil
end

----------------------------------------------------------------------
--扭蛋信息
function M:OnNetCmd_Res_Gacha(result, msgId, parsed_msg)
    -- print('--->Res_Gacha:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        self.GachaInfo = {}
        local info = parsed_msg.res_gacha.gacha_info
        self.GachaInfo.finished_type_ids = info.finished_type_ids
        self.GachaInfo.sit_character_ids = info.sit_character_ids
        self.GachaInfo.gacha_list_infos = {}
        for _, v in pairs(info.gacha_list_infos) do
            self.GachaInfo.gacha_list_infos[v.list_id] = v
            for index, info in ipairs(v.gacha_pending_record_infos) do
                info.Item_Index = index
                info.GachaId = v.list_id 
                info.bCanDing = self:IsCanDing(v.list_id, info)
            end
        end
        self.GachaInfo.gacha_type_infos = {}
        for _, v in pairs(info.gacha_type_infos) do
            self.GachaInfo.gacha_type_infos[v.type_id] = v
        end
    end
end

function M:ReqGachaCreate(id, times)
    --提交上次抽奖结果,防止意外
    local UIUtils = require('_Game.Utils.UIUtils')
    if self.GachaInfo.gacha_list_infos then
        for _, v in pairs(self.GachaInfo.gacha_list_infos) do
            if v.gacha_pending_record_infos and table.count(v.gacha_pending_record_infos) > 0 then
                local config = require('ClientDatas.d_gacha_list')[v.list_id]
                --新手池不用管
                if config and config.gachaType ~= UIUtils.EGachaPoolType.NewPlayer then
                    self:ReqGachaConfirm(v.list_id, table.count(v.gacha_pending_record_infos))
                end
            end
        end
    end
    local msg = {
        list_id = id,
        times = times,
    }
    self.CachedReqGachaCreateMsg = msg
    Client.send('req_gacha_create', msg)
end

function M:OnNetCmd_Res_Gacha_Create(result, msgId, parsed_msg)
    -- print('--->Res_Gacha_Create:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        local poolId = self.CachedReqGachaCreateMsg and self.CachedReqGachaCreateMsg.list_id or 0
       
        local UIUtils = require('_Game.Utils.UIUtils')
        local config = require('ClientDatas.d_gacha_list')[poolId]

        if not self.GachaInfo.gacha_list_infos[poolId] then
            self.GachaInfo.gacha_list_infos[poolId] = {
                list_id = poolId,
                gacha_pending_record_infos = {},
            }
        end
        local poolType = config.gachaType == 0 and 3 or config.gachaType
        if not self.GachaInfo.gacha_type_infos[poolType] then
            self.GachaInfo.gacha_type_infos[poolType] = {
                choose_times = 0,
                free_seconds = 0,
                gacha_record_infos = {} --[[table: 0000076D4A35B590]],
                no_5p_times = 0,
                no_up_times = 0,
                total_times = 0,
                type_id = poolType,
            }
        end

        self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos = parsed_msg.res_gacha_create.gacha_pending_record_infos
        --抽奖的总次数
        self.GachaInfo.gacha_type_infos[poolType].total_times = self.GachaInfo.gacha_type_infos[poolType].total_times + parsed_msg.req_data.times
    
        --判断是否抽到up
        local bGetUp = false
        local upIndex = 1
        for idx, v in ipairs(parsed_msg.res_gacha_create.gacha_pending_record_infos) do
            v.bCanDing = false
            v.Item_Index = idx
            if v.pool_index == 0 then
                bGetUp = true
                upIndex = idx
                --break
            end
        end
        --重置no_up_times
        if bGetUp then
            self.GachaInfo.gacha_type_infos[poolType].no_up_times = parsed_msg.req_data.times - upIndex
        else
            self.GachaInfo.gacha_type_infos[poolType].no_up_times = self.GachaInfo.gacha_type_infos[poolType].no_up_times + parsed_msg.req_data.times
        end

        --常驻池立即提交
        if config and config.gachaType == UIUtils.EGachaPoolType.Normal then
            -- self:ReqGachaConfirm(poolId, parsed_msg.req_data.times)
            --判断单抽，是否免费次数
            if parsed_msg.req_data.times == 1 then
                if self:IsFreeForFirstGacha() then
                    if self.GachaInfo and self.GachaInfo.gacha_type_infos[UIUtils.EGachaPoolType.Normal] then
                        local PlayerSystem = require('Module.Player.PlayerSystem')
                        local now = PlayerSystem:GetInstance():GetServerTime()
                        self.GachaInfo.gacha_type_infos[UIUtils.EGachaPoolType.Normal].free_seconds = now
                    end
                end
            end
        end

        --up池
        if config.gachaType == UIUtils.EGachaPoolType.CharPool or 
            config.gachaType == UIUtils.EGachaPoolType.WeaponPool then
            local canDingAllCount = 0
            for idx, v in ipairs(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) do
                v.Item_Index = idx
                --判定是否有叮的
                v.bCanDing = self:IsCanDing(poolId, v)
                if v.bCanDing then canDingAllCount = canDingAllCount + 1 end
            end
        end
        MessageManager:GetInstance():Broadcast('OnMsg_Gacha_Create', poolId)
    end
end

function M:ReqGachaConfirm(id, times)
    self.LastGachaTimes = times
    local msg = {}
    msg.list_id = id
    Client.send('req_gacha_confirm', msg)
end

function M:OnNetCmd_Res_Gacha_Confirm(result, msgId, parsed_msg)
    -- print('--->Res_Gacha_Confirm:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        local poolId = parsed_msg.req_data.list_id
        if self.GachaInfo.gacha_list_infos[poolId] and 
            self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos and
            table.count(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) > 0 then
            local config = require('ClientDatas.d_gacha_list')[poolId]
            local gachaType = config.gachaType == 0 and 3 or config.gachaType
            -- print('--->gacha_pending_record_infos:' .. tostring(table.dump(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos, nil, 10)))
            for _, v in ipairs(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) do
                --额外处理角色皮肤bug
                if v.gacha_item_type == 1 then
                    local gachaConfig = require('ClientDatas.d_gacha_item')[v.gacha_item_id]
                    if gachaConfig then
                        local Charactersystem = require('Module.CharacterSystem.CharacterSystem')
                        Charactersystem:GetInstance():UsePlayerSkin(gachaConfig.itemid)
                    end
                end
                table.insert(self.GachaInfo.gacha_type_infos[gachaType].gacha_record_infos, v)
            end
            self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos = {}
        end
        local UIUtils = require('_Game.Utils.UIUtils')
        --如果是新手池
        local config = require('ClientDatas.d_gacha_list')[poolId]
        if config and config.gachaType == UIUtils.EGachaPoolType.NewPlayer or config.gachaType == UIUtils.EGachaPoolType.Study then
            table.insert(self.GachaInfo.finished_type_ids, config.gachaType)
            MessageManager:GetInstance():Broadcast("OnGachaFinished", poolId, config.gachaType)
        end
        MessageManager:GetInstance():Broadcast('OnMsg_Gacha', self.LastGachaTimes)
    end
end

function M:ReqGachaDing(id, item_index)
    local msg = {
        list_id = id,
        item_index = item_index - 1,
    }
    self.LastGachaDingReq = msg
    Client.send('req_gacha_ding', msg)
end

function M:OnNetCmd_Res_Gacha_Ding(result, msgId, parsed_msg)
    -- print('--->Res_Gacha_Ding:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        local poolId = self.LastGachaDingReq.list_id
        local itemIndex = self.LastGachaDingReq.item_index + 1
        if parsed_msg and parsed_msg.res_gacha_ding then
            local gachaInfo = parsed_msg.res_gacha_ding.gacha_record_info
            gachaInfo.Item_Index = itemIndex
            gachaInfo.bCanDing = false
            if self.GachaInfo.gacha_list_infos[poolId] and 
                self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos and
                table.count(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) > 0 then
                for idx, v in pairs(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) do
                    if v.Item_Index == itemIndex then
                        self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos[idx] = gachaInfo
                        break
                    end
                end
                
            end
            MessageManager:GetInstance():Broadcast('OnMsg_GachaDing', poolId, gachaInfo)
        end
    end
end

--客户端取消叮
function M:OnDingCancel(poolId, item_index)
    if self.GachaInfo.gacha_list_infos[poolId] and 
        self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos and
        table.count(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) > 0 then
        for idx, v in pairs(self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos) do
            if v.Item_Index == item_index then
                self.GachaInfo.gacha_list_infos[poolId].gacha_pending_record_infos[idx].bCanDing = false
                break
            end
        end
    end
end

function M:ReqGachaChooseCard(id, item_index)
    local msg = {
        list_id = id,
        item_index = item_index - 1,
    }
    Client.send('req_gacha_choose_card', msg)
end

function M:OnNetCmd_Res_Gacha_Choose_Card(result, msgId, parsed_msg)
    if result == 0 then
        local poolId = parsed_msg.req_data.list_id
        local itemIndex = parsed_msg.req_data.item_index + 1
        local config = require('ClientDatas.d_gacha_list')[poolId]
        local gachaType = config.gachaType
        self.GachaInfo.gacha_type_infos[gachaType].choose_times = 1
    end
end

return M
