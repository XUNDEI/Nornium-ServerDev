local NetCmdController = require "Framework.Common.NetCmdController"
local PlotSystem = require("Module.Plot.PlotSystem")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local UIUtils = require '_Game.Utils.UIUtils'
local Database = require '_Game.Utils.Database'
local PlayerSystem = require("Module.Player.PlayerSystem")
local d_activity = require("ClientDatas.d_activity")
local datetime = require("_Game.Utils.datetime")

local ActivitySystem = BaseClass("ActivitySystem", NetCmdController)

ActivitySystem.ActivityListInfo = {}
ActivitySystem.LastActivitySignId = nil

--请求活动列表数据
function ActivitySystem:OnNetCmd_Res_Activity_List(result, msgId, parsed_msg)
    print("====OnNetCmd_Req_Activity_List:" .. tostring(result))
    print('===msg:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        for _, v in pairs(parsed_msg.res_activity_list.activity_list_info.activity_infos) do 
            ActivitySystem.ActivityListInfo[v.activity_id] = v
        end
    end
end

--活动列表数据服务器通知
function ActivitySystem:OnNetCmd_Ntf_Activity_List(result, msgId, parsed_msg)
    print("====OnNetCmd_Ntf_Activity_List:" .. tostring(result))
    print('===msg:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        for activityId, _ in pairs(parsed_msg.ntf_activity_list.removed_activity_ids) do
            if ActivitySystem.ActivityFightInfo[activityId] then   
                ActivitySystem.ActivityListInfo = nil
            end
        end
        for _, v in pairs(parsed_msg.ntf_activity_list.changed_activity_infos) do
            ActivitySystem.ActivityFightInfo[v.activity_id] = v
        end
    end
end

function ActivitySystem:ReqActivitySign(activityId)
    ActivitySystem.LastActivitySignId = activityId
    local msg = {
        activity_id = activityId,
    }
    Client.send('req_activity_sign', msg)
end

function ActivitySystem:OnNetCmd_Res_Activity_Sign(result, msgId, parsed_msg)
    print("====OnNetCmd_Ntf_Activity_List:" .. tostring(result))
    print('===msg:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        if ActivitySystem.LastActivitySignId and ActivitySystem.LastActivitySignId > 0 then
            local singActivity = ActivitySystem.ActivityListInfo[ActivitySystem.LastActivitySignId]
            singActivity.activity_sign_in_info.sign_in_times = singActivity.activity_sign_in_info.sign_in_times + 1
            singActivity.activity_sign_in_info.last_sign_in_seconds = parsed_msg.res_activity_sign.last_sign_in_seconds

            MessageManager:GetInstance():Broadcast("OnMsg_Res_Activity_Sign")
        end
    end
end

function ActivitySystem:ActivityRewardAvailable(id)
    ---@type ActivityInfo
    local activityInfo = ActivitySystem.ActivityListInfo[id]

    local activityConfig = Database.Query("d_activity", id)

    if activityConfig.eventType ~= 1 then
        return false
    end

    if activityInfo.activity_sign_in_info.last_sign_in_seconds == 0 then
        return true
    end

    -- local lastSignTime = activityInfo.activity_sign_in_info.last_sign_in_seconds - 4 * 60 * 60
    -- local time = PlayerSystem:GetInstance():GetServerTime() - 4 * 60 * 60

    -- return math.floor(time / 86400) > math.floor(lastSignTime / 86400)
    local refreshTime = UIUtils.get_daily_refresh(activityInfo.activity_sign_in_info.last_sign_in_seconds)
    return refreshTime > 0
end

function ActivitySystem:AnyRewardAvailable()
    for id, _ in ipairs(ActivitySystem.ActivityListInfo) do
        if self:ActivityRewardAvailable(id) then
            return true
        end
    end

    return false
end

function ActivitySystem:GetServerActivityInfo(activityId)
    for id, info in ipairs(ActivitySystem.ActivityListInfo) do
        if activityId == id then
            return info
        end
    end
end

function ActivitySystem:GetActivity()
    local res = {}
    local lv = PlayerSystem:GetInstance().Level
    local time = PlayerSystem:GetInstance():GetServerTime()
    for _, activityConfig in ipairs(d_activity) do
        local lvCriteria = lv >= activityConfig.levelRequire
        local keyCriteria = activityConfig.keyRequire == 0 or PlotSystem:GetInstance():IsHasKey(activityConfig.keyRequire)
        local timeCriteria = datetime.str_to_time(activityConfig.showTime) <= time and time < datetime.str_to_time(activityConfig.closeTime)

        if lvCriteria and keyCriteria and timeCriteria then
            table.insert(res, activityConfig.id)
        end
    end

    return res
end

return ActivitySystem
