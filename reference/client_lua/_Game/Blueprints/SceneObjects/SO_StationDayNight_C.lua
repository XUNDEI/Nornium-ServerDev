--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_StationDayNight_C
local M = UnLua.Class()

function M:OnOverlap()
    self.DayLevelScene = UE.UGameplayStatics.GetStreamingLevel(self, 'City1Hotel_Day')
    self.NightLevelScene = UE.UGameplayStatics.GetStreamingLevel(self, 'City1Hotel_Night')
    UIManager:GetInstance():ClearInteractOption()
    UIManager:GetInstance():AddInteractOption(self, 466, function()
        self:OnClicked_Day()
    end)
    UIManager:GetInstance():AddInteractOption(self, 465, function()
        self:OnClicked_Night()
    end)
end

function M:EndOverlap()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnClicked_Day()
    -- UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:GetIsBuildOpenDay() then return end
    gameInstance:SaveIsBuildOpenDay(true)
    if not self.DayLevelScene or not self.DayLevelScene:IsLevelLoaded() then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        coroutine.resume(coroutine.create(function()
            gameInstance.LoadStreamLevelCoroutine(self, "City1Hotel_Day", true, true)
        end))
        self.DayLevelScene = UE.UGameplayStatics.GetStreamingLevel(self, "City1Hotel_Day")
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:StreamLevelSetShouldBeVisible("City1Hotel_Day", true)
    if self.NightLevelScene and self.NightLevelScene:IsLevelLoaded() and self.NightLevelScene:IsLevelVisible() then
        gameInstance:StreamLevelSetShouldBeVisible("City1Hotel_Night", false)
    end
end

function M:OnClicked_Night()
    -- UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if not gameInstance:GetIsBuildOpenDay() then return end
    gameInstance:SaveIsBuildOpenDay(false)
    if self.DayLevelScene and self.DayLevelScene:IsLevelLoaded() and self.DayLevelScene:IsLevelVisible() then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:StreamLevelSetShouldBeVisible("City1Hotel_Day", false)
    end
    if not self.NightLevelScene or not self.NightLevelScene:IsLevelLoaded() then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        coroutine.resume(coroutine.create(function()
            gameInstance.LoadStreamLevelCoroutine(self, "City1Hotel_Night", true, true)
            gameInstance:StreamLevelSetShouldBeVisible("City1Hotel_Night", true)
            self.NightLevelScene = UE.UGameplayStatics.GetStreamingLevel(self, "City1Hotel_Night")
        end))
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:StreamLevelSetShouldBeVisible("City1Hotel_Night", true)
    end
end

return M