require "UnLua"
local Client = require "Network.Client"

local M = Class()

function M:ReceiveBeginPlay()
    Client.init_with_socket_object(self)
end

function M:OnConnected(ConnectionId)
    Client.on_socket_object_connect(ConnectionId)
end

function M:OnDisconnected(ConnectionId)
    Client.on_socket_object_disconnect(ConnectionId)
end

function M:OnMessageReceived(ConnectionId, Message)
    Client.on_socket_object_msg(ConnectionId, Message)
end

return M
