--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--
local MissionListController = require("_Game.Blueprints.UI.MissionList.MissionListController")
-- local OverviewController = require("_Game.Blueprints.UI.UI_Overview.OverviewController")
local Database = require("_Game.Utils.Database")
local SrpgController = require("Module.Srpg.SrpgController")

require "UnLua"

---@type UI_Com_Currency_C
local UI_Com_Currency_C = Class()

--function UI_Com_Currency_C:Initialize(Initializer)
--end

--function UI_Com_Currency_C:PreConstruct(IsDesignTime)
--end

function UI_Com_Currency_C:Construct()
    self.Mission.OnClicked:Add(self, UI_Com_Currency_C.OpenMissionList)
    self.Overview.OnClicked:Add(self, UI_Com_Currency_C.OpenOverview)
    MessageManager:GetInstance():AddListener("refresh_currency", self)
end

function UI_Com_Currency_C:Destruct()
    MessageManager:GetInstance():RemoveListener("refresh_currency", self)
end

--function UI_Com_Currency_C:Tick(MyGeometry, InDeltaTime)
--end

function UI_Com_Currency_C:OpenOverview()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_UniverseMenu.UI_Menu.UI_MenuCardArray.Button_FoldCard.OnClicked:Broadcast()

    -- self.overviewController = OverviewController.New(self.RootCanvas)

    -- self.overviewController:SetUp()
end

function UI_Com_Currency_C:OpenMissionList()
    self.missionListController = MissionListController.New(self.RootCanvas)

    self.missionListController:SetUp()
end

function UI_Com_Currency_C:refresh_currency()
    self:UpdateCurrencyData()
end

function UI_Com_Currency_C:UpdateCurrencyData()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.resUniverse then
        local cur_hp = gameInstance.resUniverse.res_universe.universe_info.cur_hp or 0
        local max_hp = gameInstance.resUniverse.res_universe.universe_info.max_hp or 0

        if gameInstance.resUniverse.res_universe.universe_info.boss_info then
            local bossId = gameInstance.resUniverse.res_universe.universe_info.boss_info.boss_id
            local bossInfo = Database.Query("d_srpg_level_boss", bossId)
            local max_turn = #bossInfo.path
            local cur_turn = gameInstance.resUniverse.res_universe.universe_info.turn or 0
            self.Turn_Text:SetText(math.floor(cur_turn) .. "/" .. math.floor(max_turn))
        end

        local goods1 = SrpgController:GetInstance():GetResource(1)
        local goods2 = SrpgController:GetInstance():GetResource(2)
        local goods3 = SrpgController:GetInstance():GetResource(3)
        local goods4 = SrpgController:GetInstance():GetResource(4)
        self.Hp_Text:SetText(math.floor(cur_hp) .. "/" .. math.floor(max_hp))
        self.Step_Text:SetText(math.floor(goods4))
        self.good_text_1:SetText(math.floor(goods1))
        self.addition_1:SetText("+" .. math.floor(gameInstance.add_goods[1]))
        self.good_text_2:SetText(math.floor(goods2))
        self.addition_2:SetText("+" .. math.floor(gameInstance.add_goods[2]))
        self.good_text_3:SetText(math.floor(goods3))
        self.addition_3:SetText("+" .. math.floor(gameInstance.add_goods[3]))
    end
end

return UI_Com_Currency_C
