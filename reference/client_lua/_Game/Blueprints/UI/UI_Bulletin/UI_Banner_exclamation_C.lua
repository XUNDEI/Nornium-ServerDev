---@type UI_Banner_exclamation_C
local M = UnLua.Class()

local MIN_LIFETIME = 3
function M:Tick(MyGeometry, InDeltaTime)
    self.lifeTime = self.lifeTime + InDeltaTime
    local pos = self.Text.Slot:GetPosition()
    pos.X = pos.X - self.ScrollSpeed * InDeltaTime

    self.Text.Slot:SetPosition(pos)

    local size = self.Text:GetDesiredSize().X
    if pos.X <= -size and self.lifeTime > MIN_LIFETIME then
        UIManager:GetInstance():RemoveBanner()
    end
end

function M:Show(text)
    self.lifeTime = 0
    self.Text:SetText(text)
end

return M
