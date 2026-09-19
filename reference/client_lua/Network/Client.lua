local socket = require "socket"
local pb = require "pb"
local pbmsg = require "Helper.pbmsg"
local crypt = require "crypt"

local client
local clients
local connect = {}
local readbuff
local msg_listener = {}
local connect_listener
local CLIENT_STATUS = {
    IDLE = 1,
    CONNECTING = 2,
    CONNECTED = 3,
    CONNECT_FAILED = 4,
    CONNECT_TIMEOUT = 5,
    DISCONNECT = 6,
}
local client_status = CLIENT_STATUS.IDLE
local CONNECT_TIMEOUT = 10
local ping_elapsed = 0
local connect_elapsed = 0
local last_connect_elapsed = -1
local ping_last_time = 0

local send_caches = {}

local M = {}
M.c_no = 0
M.s_no = 0
M.init_msg_key = "kueisoon"
M.msg_key = nil

local is_waiting_msg_key = false

local no_log_cmds
local function no_log_cmd(cmd)
    for _, v in ipairs(no_log_cmds) do
        if v == cmd then
            return true
        end
    end
    return false
end

local no_crypt_cmds
local function no_crypt_cmd(cmd)
    for _, v in ipairs(no_crypt_cmds) do
        if v == cmd then
            return true
        end
    end
    return false
end

M.init = function()
    local filepath = UE.FPaths.Combine(UE.FPaths.ProjectContentDir(), "Script/Helper/proto.pb")
    local protoContent = UE.FFileHelper.LoadFileToArray(filepath)
    pb.load(protoContent)
    pb.option "enum_as_value"
    no_log_cmds = {
        pbmsg.get_msg_id_and_msg_type("req_ping"),
        pbmsg.get_msg_id_and_msg_type("res_ping"),
        pbmsg.get_msg_id_and_msg_type("ntf_server_time"),
    }
    no_crypt_cmds = {
        pbmsg.get_msg_id_and_msg_type("req_ping"),
        pbmsg.get_msg_id_and_msg_type("res_ping"),
        pbmsg.get_msg_id_and_msg_type("ntf_server_time"),
        pbmsg.get_msg_id_and_msg_type("ntf_msg_key"),
    }
end

local function str_unpack(msgstr, len)
    local result = msgstr:byte(1)<<8|msgstr:byte(2)
    local cmd = msgstr:byte(3)<<8|msgstr:byte(4)
    local c_no = msgstr:byte(5)<<8|msgstr:byte(6)
    local s_no = msgstr:byte(7)<<8|msgstr:byte(8)
    local isok, decoded = true, msgstr:sub(9, -1)
    if len > 4+8 and not no_crypt_cmd(cmd) then
        isok, decoded = pcall(crypt.desdecode, M.msg_key, decoded)
        if not isok then return false, decoded end
    end
    local msg
    if len > 4+8 then
        msg = pb.decode("ghs.Msg", decoded)
    end
    return true, result, cmd, c_no, s_no, msg
end

local function str_pack(cmd, c_no, s_no, sub_msg)
    local _, field_name = pbmsg.get_msg_name_and_field_name(cmd)
    local isok, body, msg = true
    if sub_msg then
        msg = {}
        msg[field_name] = sub_msg
        msg["sub_msg"] = field_name
        body = pb.encode("ghs.Msg", msg)
        if not no_crypt_cmd(cmd) then
            isok, body = pcall(crypt.desencode, M.msg_key, body)
            if not isok then return false, body end
        end
    else
        body = ""
    end
    local size = string.len(body) + 6 + 4
    local buff = string.format("%c%c%c%c%c%c%c%c%c%c", size>>24&255, size>>16&255, size>>8&255, size&255,
    cmd>>8&255, cmd&255,
    c_no>>8&255, c_no&255, s_no>>8&255, s_no&255)..body
    -- local buff = string.pack(">I2I2", size, cmd)..body
    return true, buff, msg
end

local function process_msg(msg_size, msgstr)
    local isok, result, cmd, c_no, s_no, msg = str_unpack(msgstr, msg_size)
    if not isok then
        LOG_ERROR("str_unpack failed: "..result)
        return
    end
    local cmd_name, field_name = pbmsg.get_msg_name_and_field_name(cmd)
    if not no_log_cmd(cmd) then
        LOG_INFO(field_name)
    end
    if M.ENABLE_LOG and LOG_LEVEL <= 1 then
        if cmd_name ~= 'ResPing' and cmd_name ~= "NtfMsgKey"  and field_name ~= 'ntf_server_time' then
            local log = "->recv "..result.." ["..cmd_name.."] {"..require "serpent".block(msg).."}"
            if result == 0 then
                LOG_VERBOSE(log)
            else
                LOG_WARN(log)
            end
        end
    end

    M.s_no = s_no

    if field_name == "ntf_msg_key" then
        local isok, msg_key = pcall(crypt.desdecode, M.init_msg_key, msg.ntf_msg_key.msg_key)
        if not isok then
            LOG_ERROR("desdecode failed: "..msg.ntf_msg_key.msg_key)
            return
        end
        M.msg_key = msg_key
        is_waiting_msg_key = false
        client_status = CLIENT_STATUS.CONNECTED
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return
    end

    local send_cache = send_caches[1]
    if send_cache then
        local req_name = field_name:gsub("res_", "req_")
        if req_name == send_cache.msg_name then
            -- 兼容改版前的协议
            if msg then
                msg.req_data = send_cache.msg
            else
                msg = {req_data = send_cache.msg}
            end
            table.remove(send_caches, 1)
        end
    end
    local listener = msg_listener[field_name]
    if listener then
        -- 兼容改版前的协议
        msg = msg or {}
        listener.callback(listener.self_obj, result, cmd, msg, table.unpack(listener.args))
    elseif field_name == "res_ping" then
        ping_last_time = os.time()
    end
end

local function process_buff(readbuff)
    while true do
        -- local size = #readbuff
        -- if size < 4 then
        --     return readbuff
        -- end
        if not readbuff:byte(4) then
            return readbuff
        end
        local msg_size = readbuff:byte(1)<<24|readbuff:byte(2)<<16|readbuff:byte(3)<<8|readbuff:byte(4)
        -- LOG_INFO("process_buff size", s, readbuff:byte(s), #readbuff)
        -- if size < s then
        --     return readbuff
        -- end
        if not readbuff:byte(msg_size) then
            return readbuff
        end
        -- LOG_INFO("process_buff read", s)
        local msgstr = readbuff:sub(4+1, msg_size)
        readbuff = readbuff:sub(msg_size+1, -1)
        process_msg(msg_size, msgstr)
    end
end

M.init_with_socket_object = function(socket_object)
    M.socket_object = socket_object
end

M.on_socket_object_disconnect_ = function(ConnectionId)
    LOG_WARN("on_socket_object_disconnect_")
    M.pending_disconnect = true
end

M.on_socket_object_connect_ = function(ConnectionId)
    LOG_WARN("on_socket_object_connect_")
    M.pending_connect = true
end

M.on_socket_object_msg_ = function(ConnectionId, Message)
    LOG_WARN("on_socket_object_msg_")
end

M.on_socket_object_disconnect = function(ConnectionId)
    -- LOG_INFO("on_socket_object_disconnect")
    M.pending_disconnect = true
end

M.on_socket_object_connect = function(ConnectionId)
    -- LOG_INFO("on_socket_object_connect")
    M.pending_connect = true
end

M.on_socket_object_msg = function(ConnectionId, Message)
    Message = UE.UGHSSocketConnection.BytesToString(Message)
    -- LOG_INFO("on_socket_object_msg", string.len(Message))
    M.pending_buff = M.pending_buff..Message
end

M.isconnected = function()
    return client ~= nil and client_status == CLIENT_STATUS.CONNECTED 
end

M.need_connect = function()
    return client == nil or client_status ~= CLIENT_STATUS.CONNECTED and client_status ~= CLIENT_STATUS.CONNECTING
end

M.waiting_res = function()
    if not M.isconnected() then return nil end
    if #send_caches > 0 then return send_caches[1].msg_name end
    return nil
end

M.get_send_caches = function()
    return send_caches
end

M.get_host_type = function(ip)
    local R = {ERROR = 0, IPV4 = 1, IPV6 = 2, STRING = 3}
    if type(ip) ~= "string" then return R.ERROR end

    -- check for format 1.11.111.111 for ipv4
    local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
    if #chunks == 4 then
        for _,v in pairs(chunks) do
            if tonumber(v) > 255 then return R.STRING end
        end
        return R.IPV4
    end

    -- check for ipv6 format, should be 8 'chunks' of numbers/letters
    -- without leading/trailing chars
    -- or fewer than 8 chunks, but with only one `::` group
    local chunks = {ip:match("^"..(("([a-fA-F0-9]*):"):rep(8):gsub(":$","$")))}
    if #chunks == 8
    or #chunks < 8 and ip:match('::') and not ip:gsub("::","",1):match('::') then
        for _,v in pairs(chunks) do
            if #v > 0 and tonumber(v, 16) > 65535 then return R.STRING end
        end
        return R.IPV6
    end

    return R.STRING
end

M.connect = function(host, port, is_reconnect)
    LOG_INFO_TRACKBACK("=====client_status:", tostring(client_status))
    if client_status == CLIENT_STATUS.CONNECTED or client_status == CLIENT_STATUS.CONNECTING then
        return false
    end
    if M.get_host_type(host) == 3 then
        local resolved
        connect.ip, resolved = socket.dns.toip(host)
        if connect.ip == nil then
            LOG_ERROR("dns toip failed: "..resolved)
            return false
        end
        LOG_INFO("dns toip: "..connect.ip)
        LOG_INFO(table.dump(resolved))
    else
        connect.ip = host
    end
    connect.host = host
    connect.port = port
    client_status = CLIENT_STATUS.CONNECTING
    is_waiting_msg_key = false
    M.msg_key = nil
    connect_elapsed = 0
    last_connect_elapsed = -1
    connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
    -- client = socket.tcp4()
    M.pending_connect = false
    M.pending_disconnect = false
    M.pending_buff = ""
    M.socket_id = M.socket_object:Connect(connect.ip, port,
    M.on_socket_object_disconnect_, M.on_socket_object_connect_, M.on_socket_object_msg_)
    LOG_INFO("socket_id: ", M.socket_id)
    client = {
        connect = function(self, host, port)
            local is_connected = M.pending_connect -- M.socket_object:isConnected(M.socket_id)
            if is_connected then
                return 1, "already connected"
            end
            if M.pending_disconnect then
                return 0, "closed"
            end
            return 0, "timeout"
        end,
        close = function(self)
            return M.socket_object:Disconnect(M.socket_id)
        end,
        settimeout = function(self, timeout)
        end,
        receive = function(self, pattern)
            if M.pending_disconnect and M.pending_buff == "" then
                return nil, "closed"
            end
            local body, status, partial = M.pending_buff, "", nil
            M.pending_buff = ""
            return body, status, partial
        end,
        send = function(self, data)
            if M.pending_disconnect then
                return false
            end
            local buff = UE.UGHSSocketConnection.StringToBytes(data)
            return M.socket_object:SendData(M.socket_id, buff)
        end
    }
    clients = {client}
    if not is_reconnect then
        send_caches = {}
    end
    return true
end

M.recv = function()
    if not client then
        return false, "no client"
    end
    -- local readable, _, err = socket.select(clients, nil, 0)
    -- if err then
    --     -- LOG_INFO("select error: ", err)
    --     if err == "closed" or err == "Socket is not connected" then
    --         LOG_INFO("recv socket closed ... status = "..err)
    --         client:close()
    --         client = nil
    --         clients = nil
    --         readbuff = nil
    --         client_status = CLIENT_STATUS.DISCONNECT
    --         connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
    --         return false, err
    --     end
    --     if err == "timeout" then
    --         return true
    --     end
    --     LOG_INFO("select error: ", err)
    --     client:close()
    --     client = nil
    --     clients = nil
    --     readbuff = nil
    --     client_status = CLIENT_STATUS.DISCONNECT
    --     connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
    --     return false, err
    -- end
    -- if #readable == 0 then
    --     -- LOG_INFO("select not readable: ")
    --     return true
    -- end
    -- client:settimeout(0)
    client:settimeout(0.005)
    local body, status, partial = client:receive("*a")
    if status == "closed" or status == "Socket is not connected" then
        LOG_INFO("recv socket closed ... status = "..status)
        client:close()
        client = nil
        clients = nil
        readbuff = nil
        client_status = CLIENT_STATUS.DISCONNECT
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return false, status
    end
    if (body and string.len(body) == 0) or (partial and string.len(partial) == 0) then
        return false, status
    end
    if body and partial then
        body = body..partial
    end
    local recvstr = body or partial
    readbuff = readbuff..recvstr
    readbuff = process_buff(readbuff)
    if not readbuff then
        LOG_INFO("process buff failed")
        client:close()
        client = nil
        clients = nil
        readbuff = nil
        client_status = CLIENT_STATUS.DISCONNECT
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return false, "readbuff is nil"
    end
    return true
end

-- TODO: 需要考虑连发情况
M.send = function(msg_name, msg, wait_res, show_wait_delay)
    --print("===socket send:" .. tostring(msg_name) .. ",time:" .. tostring(os.clock() * 10000))
    if not client then
        client_status = CLIENT_STATUS.DISCONNECT
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return false
    end
    if wait_res then
        local waiting_msg_name = M.waiting_res()
        if waiting_msg_name then
            LOG_INFO("waiting_res %s, sending %s", waiting_msg_name, msg_name)
            return false
        end
    end

    local cmd, cmd_name = pbmsg.get_msg_id_and_msg_type(msg_name)
    local isok, buff, parsed_msg = str_pack(cmd, M.c_no + 1, M.s_no, msg)
    if not isok then
        LOG_ERROR("str_pack failed: "..buff)
        return false
    end
    if not no_log_cmd(cmd) then
        LOG_INFO(msg_name)
        if M.ENABLE_LOG and LOG_LEVEL <= 1 then
            if cmd_name ~= 'ReqPing' then
                if parsed_msg then
                    LOG_VERBOSE("->send ".." ["..cmd_name.."] {"..require "serpent".block(parsed_msg).."}")
                else
                    LOG_VERBOSE("->send ".." ["..cmd_name.."]")
                end
            end
        end
    end

    local time = client:send(buff)
    if not time then
        --发送不出去
        client:close()
        client = nil
        clients = nil
        client_status = CLIENT_STATUS.IDLE
        connect_listener.callback(connect_listener.self_obj, CLIENT_STATUS.DISCONNECT, table.unpack(connect_listener.args))
        return false
    end
    M.c_no = M.c_no + 1
    if msg_name ~= "req_ping" then
        local cache = {
            msg_name = msg_name,
            c_no = M.c_no,
            s_no = M.s_no,
            msg = msg,
            time = os.time(),
            show_wait_delay = show_wait_delay,
        }
        if msg_name == "req_relogin" then
            table.insert(send_caches, 1, cache)
        else
            table.insert(send_caches, cache)
        end
    end
    return true
end

M.close = function()
    send_caches = {}
    if not client then
        return false, "no client"
    end
    LOG_INFO_TRACKBACK("close socket closed ...")
    client:close()
    client = nil
    clients = nil
    readbuff = nil
    client_status = CLIENT_STATUS.IDLE
    return true
end

M.register_msg = function(msg_name, callback, self_obj, ...)
    msg_listener[msg_name] = {
        callback = callback,
        self_obj = self_obj,
        args = table.pack(...)
    }
end

M.register_connect = function(callback, self_obj, ...)
    connect_listener = {
        callback = callback,
        self_obj = self_obj,
        args = table.pack(...)
    }
end

M.update = function(deltatime)
    if M.tick_for_reconnect then
        M.tick_for_reconnect_elapsed = M.tick_for_reconnect_elapsed or 0
        M.tick_for_reconnect_elapsed = M.tick_for_reconnect_elapsed + deltatime
        if M.tick_for_reconnect_elapsed >= 2 then
            M.tick_for_reconnect_elapsed = 0
            M.tick_for_reconnect()
        end
    end
    if client_status == CLIENT_STATUS.CONNECTING then
        if is_waiting_msg_key then
            local isok, status = M.recv()
            if not isok then
                return
            end
            if not is_waiting_msg_key then
                return
            end
            connect_elapsed = connect_elapsed + deltatime
            if connect_elapsed >= CONNECT_TIMEOUT then
                LOG_FORMAT_INFO("CONNECTING waiting socket closed ... status=%s, time=%f", "waiting", connect_elapsed)
                client:close()
                client = nil
                clients = nil
                client_status = CLIENT_STATUS.CONNECT_TIMEOUT
                connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
            end
            return
        end
        -- if UE.UGameplayStatics.GetPlatformName() == "Windows" then
        --     client:settimeout(0.005)
        -- else
        --     client:settimeout(0)
        -- end
        client:settimeout(0.005)
        ping_last_time = os.time()
        local succ, status = client:connect(connect.ip, connect.port)
        if succ == 1 or status == "already connected" then
            LOG_INFO(succ, status)
            is_waiting_msg_key = true
            readbuff = ""
            -- ping_elapsed = 0
            -- ping_last_time = os.time()
            -- client_status = CLIENT_STATUS.CONNECTED
            -- connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        else
            if status == "Invalid argument" or status == "timeout" or status == "Operation already in progress" then
                if connect_elapsed >= last_connect_elapsed then
                    LOG_INFO(succ, status, "connecting")
                    last_connect_elapsed = last_connect_elapsed + 1
                end
                connect_elapsed = connect_elapsed + deltatime
                if connect_elapsed >= CONNECT_TIMEOUT then
                    LOG_FORMAT_INFO("CONNECTING socket closed ... status=%s, time=%f", status, connect_elapsed)
                    client:close()
                    client = nil
                    clients = nil
                    client_status = CLIENT_STATUS.CONNECT_TIMEOUT
                    connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
                end
                return
            end
            LOG_INFO("CONNECTING socket closed ... status = "..status)
            client:close()
            client = nil
            clients = nil
            client_status = CLIENT_STATUS.CONNECT_FAILED
            connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        end
        return
    end
    if client_status == CLIENT_STATUS.CONNECTED then
        ping_elapsed = ping_elapsed + deltatime
       
        if ping_elapsed >= 15 then
            ping_elapsed = 0
            M.send("req_ping")
        end
        local isok, status = M.recv()
        if not isok then
            return
        end

        --timeout server ping loop 120 and not receive server disconnect
        if M.pingTimeOffset ~= os.time() - ping_last_time then
            M.pingTimeOffset = os.time() - ping_last_time
            --print("======>>pingTimeOffset:" .. tostring(M.pingTimeOffset))
        end
       
        if ping_last_time > 0 and M.pingTimeOffset >= 125 then
            print("====ping is time out 125")
            client:close()
            client = nil
            client_status = CLIENT_STATUS.IDLE
            connect_listener.callback(connect_listener.self_obj, CLIENT_STATUS.DISCONNECT, table.unpack(connect_listener.args))
            return
        end

        return
    end
    if client_status == CLIENT_STATUS.CONNECT_TIMEOUT then
        client_status = CLIENT_STATUS.IDLE
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return
    end
    if client_status == CLIENT_STATUS.CONNECT_FAILED then
        client_status = CLIENT_STATUS.IDLE
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return
    end
    if client_status == CLIENT_STATUS.DISCONNECT then
        client_status = CLIENT_STATUS.IDLE
        connect_listener.callback(connect_listener.self_obj, client_status, table.unpack(connect_listener.args))
        return
    end
end

M.debug = function()
    LOG_INFO(string.format("send_caches len %d", #send_caches))
    if send_caches[1] then
        LOG_INFO(table.dump(send_caches, false, 10))
    end
end

M.CLIENT_STATUS = CLIENT_STATUS
M.ENABLE_LOG = true

return M