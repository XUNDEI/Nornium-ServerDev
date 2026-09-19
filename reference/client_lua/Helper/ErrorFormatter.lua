local Protos = require("Helper.Protos")
local Database = require("_Game.Utils.Database")
local pb = require "pb"
local pbmsg = require "Helper.pbmsg"

local ErrorFormatter = {}

local ERROR_MSG = {
    res_player = {
        PLAYER_LOADED = "PLAYER_LOADED",
    },
    res_register = {
        TIME_NOT_ALLOWED = Database.L10n(83100005),
        ACCOUNT_NAME_EXISTS = Database.L10n(83100003),
    },
    res_change_player_sequence_name = {
        INVALID_NAME = "INVALID_NAME",
    },
    res_login = {
        CHANNEL_MISMATCH = "CHANNEL_MISMATCH",
        NO_ACCOUNT = Database.L10n(83100006),
        PASSWORD_NOT_MATCH = Database.L10n(83100002),
        SURE_AGENT_FAILED = 'SURE_AGENT_FAILED',
        UPDATE_DB_FAILED = 'UPDATE_DB_FAILED',
        CODE_NOT_MATCH = 'CODE_NOT_MATCH',
        BAN_ACCOUNT = Database.L10n(518),
    },
    res_use_item = {
        NO_ITEM = "NO_ITEM",
        INVALID_ITEM = "INVALID_ITEM",
        INVALID_COUNT = "INVALID_COUNT",
    },
    res_character_skill_level_up = {
        NO_CHARACTER = "NO_CHARACTER",
        NO_SKILL = "NO_SKILL",
        MAX_LEVEL = "MAX_LEVEL",
    },
    res_universe = {
        EMPTY_UNIVERSE = '', -- skip
    },
    res_main_pos_shop_buy = {
        RES_NOT_ENOUGH = Database.L10n(275),
    },
    res_main_pos_shop_refresh = {
        RES_NOT_ENOUGH = Database.L10n(283),
    },
    res_player_universe_growth = {
        RES_NOT_ENOUGH = Database.L10n(275),
    },
    res_new_universe = {
        NO_CHARACTER = Database.L10n(464),
        SERVER_ERROR_MISSING_REQ_DATA = Database.L10n(464),
    },
    res_use_gift_code = {
        INVALID_CODE = Database.L10n(492),
        CODE_NOT_OPEN = Database.L10n(492),
        CODE_CLOSED = Database.L10n(493),
        GROUP_USED = Database.L10n(495),
        CODE_USED_UP = Database.L10n(494),
    }
}

local msg_details
local inited = false
local function lazy_init()
    if inited then return end
    for msg_name, proto in pairs(ERROR_MSG) do
        local _, msg_type = pbmsg.get_msg_id_and_msg_type(msg_name)
        if not msg_type then
            LOG_FORMAT_ERROR("msg_type not found, msg_name=%s", tostring(msg_name))
            return
        end
        local result_type = string.format("ghs.%s.ResultType", msg_type)
        local new_proto = {}
        for k, v in pairs(proto) do
            local new_k = pb.enum(result_type, k) or pb.enum("ghs.ServerError", k)
            if type(new_k) ~= "number" then
                LOG_FORMAT_ERROR("error key not exists, k=%s", tostring(k))
                return
            end
            LOG_DEBUG(result_type, k, new_k)
            new_proto[new_k] = v
        end
        ERROR_MSG[msg_name] = new_proto
    end
    local GlobalConfig = require('GlobalConfig')
    msg_details = GlobalConfig.HOST:find("192.168.0.") or GlobalConfig.HOST:find("nat.syhlgame.cn")
    inited = true
end

local function FormatError(msgName, result, parsed_msg)
    lazy_init()
    local msg = ERROR_MSG[msgName] and ERROR_MSG[msgName][result]

    if not msg then
        if not msg_details then
            local cmd = pbmsg.get_msg_id_and_msg_type(msgName)
            msg = string.format("cmd:%d code:%d", cmd, result)
        else
            msg = string.format("%s returns error code %d", msgName, result)
        end
    elseif msgName == 'res_login' and result == 8 then
        local leftTime = parsed_msg.res_login.ban_end_seconds - os.time()
        local datetime = require("_Game.Utils.datetime")
        msg = string.format(msg, datetime.format_time(leftTime))
    end
    
    return msg
end

ErrorFormatter.FormatError = FormatError

return ErrorFormatter
