local PlayerSystem = require("Module.Player.PlayerSystem")
local datetime = require("_Game.Utils.datetime")

---@type SO_DailyCopyEntry_1_C
local M = UnLua.Class()

local SHOW_DAYS = {
    {
        1, 3, 5, 7
    },
    {
        2, 4, 6, 7
    }
}

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
end

function M:ReceiveTick()
    local utc = PlayerSystem:GetInstance():GetServerTime()
    local time = utc - 4 * 60 * 60
    local weekday = datetime.get_week(time)

    local show = table.indexof(SHOW_DAYS[self.Args], weekday)
    show = true
    self.BP_Interactive.ChildActor:SetActorEnableCollision(show and true)

    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BP_NPC_Daily" .. self.Args)
    for i = 1, actors:Num() do
        actors[i]:SetActorHiddenInGame(not show)
    end
end

function M:OnEvent_OverlapStart()
    local wordId = self.OptionItemWordIndex:Get(1)
    UIManager:GetInstance():ClearInteractOption()
    local index = UIManager:GetInstance().layers.Options:GetChildrenCount()
    UIManager:GetInstance():AddInteractOption(self, wordId, function()
        local widget = UIManager:GetInstance().layers.Options:GetChildAt(index)
        self:OnClickItem(widget, index)
    end)
end

function M:OnEvent_OverlapEnd()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnClickItem(widget, index)
    self.Overridden.OnClickItem(self, widget, index)
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OnMessage('UI_Daily_Copy', self.Args)
end

return M