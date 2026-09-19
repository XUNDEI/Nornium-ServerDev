local Database = require("_Game.Utils.Database")
local UIUtils = require("_Game.Utils.UIUtils")

---@type UI_Activity_StarGift_C : UI_Activity_Base
local M = UnLua.Class("_Game.Blueprints.UI.UI_Activity.UI_Activity_Base")

function M:RefreshUI()
    self.activityId = 6
    self.Super.RefreshUI(self)

    self.Btn_Go.OnClicked:Clear()
    self.Btn_Go.OnClicked:Add(self, function()
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        if playerController then
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = gameMode:BPI_GetPlayer()
            if player then
                player:ChangeCamera(true)
            end
        end
        -- UIUtils.ShowNotify(self, Database.L10n(50500))
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9024, "") then
            --判断是否在地铁
            local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
            if pc then
                if pc.LoadStationScene then--
                    if pc.bIsInStationScene then --已经在地图中
                        gameInstance:RemoveTopUI(false)
                        gameInstance:RemoveTopUI(false)
                        gameInstance:ShowTopUI(true)
                        local ui = gameInstance:GetUMG('UI_TrainStation')
                        if ui then
                            ui:OnClicked_UI_MenuButton()
                        end
                    else --不在地图,提示信息
                        UIUtils.ShowComNotice(Database.L10n(438), self, function() 
                            gameInstance:RemoveTopUI(false)
                            local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
                            playerController:LoadStationScene(true)
                        end, function() end)
                    end
                else --不在主城地图
                    UIUtils.ShowComNotice(Database.L10n(448), self, function()
                    end, function() end)
                end
            end
        end
    end)
end

return M
