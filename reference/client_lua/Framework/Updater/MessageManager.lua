-- 绑定普通事件用的Messenger

local Messenger = require "Framework.Common.Messenger"

local MessageManager = BaseClass("MessageManager", Singleton)

function MessageManager:__init()
    self.messenger = Messenger.New()
end

function MessageManager:AddListener(MessageName, Callback)
    self.messenger:AddListener(MessageName, Callback)
end

function MessageManager:Broadcast(MessageName, ...)
    return self.messenger:Broadcast(MessageName, ...)
end

---@param CallbackOrThis function | table @如果传过来一个function，就直接用作callback，如果传进来的是一个table/userdata，则默认其实现了名为MessageName的方法并自动生成一个绑定了self的callback
function MessageManager:AddListener(MessageName, CallbackOrThis)
    local Callback
    if type(CallbackOrThis) == "function" then
        Callback = CallbackOrThis
    else
        local boundFunction = CallbackOrThis["__" .. MessageName]
        if boundFunction then
            LOG_WARN(CallbackOrThis, "already bound", MessageName)
            return
        end
        local targetFunction = CallbackOrThis[MessageName]
        if not targetFunction or type(targetFunction) ~= "function" then
            LOG_WARN(CallbackOrThis, "did not implement", MessageName)
        end
        Callback = BindCallback(CallbackOrThis, targetFunction)
        CallbackOrThis["__" .. MessageName] = Callback
    end

    self.messenger:AddListener(MessageName, Callback)
end

function MessageManager:RemoveListener(MessageName, CallbackOrThis)
    local Callback
    if type(CallbackOrThis) == "function" then
        Callback = CallbackOrThis
    else
        local targetFunction = CallbackOrThis["__" .. MessageName]
        if not targetFunction or type(targetFunction) ~= "function" then
            LOG_WARN(CallbackOrThis, "did not bind", MessageName)
        end
        Callback = targetFunction
    end

    self.messenger:RemoveListener(MessageName, Callback)
end

-- 析构函数
function MessageManager:__delete()
    self.messenger = nil
end

return MessageManager
