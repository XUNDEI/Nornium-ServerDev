local UIUtils = require "_Game.Utils.UIUtils"

---@type BP_FingerPosRecorder_C
local M = UnLua.Class()

function M:GetPointerPos()
    if UIUtils.IsAndroidOrIOS() then
        return self.FingerLastPos:Find(UE.ETouchIndex.Touch1)
    else
        return self.FingerLastPos:Find(UE.ETouchIndex.CursorPointerIndex)
    end
end

return M
