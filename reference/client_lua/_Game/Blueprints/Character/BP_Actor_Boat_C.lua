--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--
local SrpgController = require("Module.Srpg.SrpgController")

---@type BP_Actor_Boat_C
local M = UnLua.Class()

function M:OnLoadFightAttribute()
    if SrpgController:GetInstance():GetCurrentFightInfo() then
        self:InitAttributeSet("CurrentSP", SrpgController:GetInstance():GetBoatEnergy())
    end
end

return M
