local InputUtils = require "_Game.Utils.Input.InputUtils"

---@class UIManager
---@field platform string
local InputSettingManager = BaseClass("InputSettingManager", Singleton)

function InputSettingManager:__init()
    self.platform = InputUtils.Platform.PC
end

function InputSettingManager:IsAssignable(Key, Platform)
end

return InputSettingManager
