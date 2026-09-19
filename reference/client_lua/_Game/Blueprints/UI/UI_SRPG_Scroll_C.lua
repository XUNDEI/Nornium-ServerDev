--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--
local DataBase = require("_Game.Utils.Database")

---@type UI_SRPG_Scroll_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.Overridden.Construct(self)
    self.TextBlock_96:SetText(DataBase.L10n(118000035))

    self.ButtonTitle:SetText(DataBase.L10n(118000036))

    self.BackBtn.OnClicked:Add(self.BackBtn, function()
        ---@type BP_GameMode_Universe_C
        local gameMode = UE.UGameplayStatics.GetGameMode(self)

        local baseMainPos

        for i = 1, gameMode.MainPoses:Length() do
            local pos_data = DataBase.Query('d_srpg_main_pos_base', gameMode.MainPoses:Get(i).TypeId)
            if pos_data.mainPosType == 1 then
                baseMainPos = gameMode.MainPoses:Get(i)
            end
        end
        if baseMainPos then
            UE.UGameplayStatics.GetPlayerController(self, 0):MoveToMainPos(baseMainPos)
        end
    end)

    self:UpdateBackBtn()
end

function M:UpdateBackBtn()
    ---@type BP_GameMode_Universe_C
    local gameMode = UE.UGameplayStatics.GetGameMode(self)

    local baseMainPos

    for i = 1, gameMode.MainPoses:Length() do
        local pos_data = DataBase.Query('d_srpg_main_pos_base', gameMode.MainPoses:Get(i).TypeId)
        if pos_data.mainPosType == 1 then
            baseMainPos = gameMode.MainPoses:Get(i)
        end
    end
    
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    self.BackBtn:SetIsEnabled(playerController.CurMainPos ~= baseMainPos)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
