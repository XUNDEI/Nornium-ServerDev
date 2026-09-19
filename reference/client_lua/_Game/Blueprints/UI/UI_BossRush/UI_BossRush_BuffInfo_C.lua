local Database = require("_Game.Utils.Database")

---@type UI_BossRush_BuffInfo_C
local M = UnLua.Class()

function M:Setup(id)
    local config = Database.Query("d_bossrush_buff", id)

    self.Name:SetText(Database.L10n(config.name))
    self.Desc:SetText(Database.L10n(config.desc))
end

return M
