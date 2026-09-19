local Protos = require("Helper.Protos")
local NetworkMessageListener = require("Module.NetworkMessageListener")

local PickUpModel = require("Module.Progress.PickUpModel")

---@class PickUpController : NetworkMessageListener
---@field model PickUpModel
---@field GetInstance fun():PickUpController
local PickUpController = BaseClass("PickUpController", NetworkMessageListener)

---{{{protos
PickUpController.__listened_network_messages = {
    Protos.RES_LOGIN,
}

---@param self PickUpController
---@param parsed_msg ResLoginMessage
PickUpController[Protos.RES_LOGIN] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.accountId = parsed_msg.res_login.account_id
        self:Load()
    end
end
---}}}

function PickUpController:__init()
    self.model = PickUpModel.New()

    self.items = {}
end

function PickUpController:Load()
    ---@type SG_SaveGame_Universe_C
    local saveGame
    if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_PickUp_" .. self.accountId, 0) then
        saveGame = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_PickUp_" .. self.accountId, 0)
    else
        saveGame = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load('/Game/_Game/Blueprints/Game/SG_SaveGame_PickUp.SG_SaveGame_PickUp_C'))
    end

    self.model.saveGame = saveGame
    self.model.saveGameRef = UnLua.Ref(saveGame)
end

function PickUpController:Save()
    if self.model.saveGame then
        UE.UGameplayStatics.SaveGameToSlot(self.model.saveGame, "SG_SaveGame_PickUp_" .. self.accountId, 0)
    end
end

function PickUpController:CreatePickUp(configId, item)
    self.items[configId] = item
end

function PickUpController:IsPicked(configId)
    return self.model:IsPicked(configId)
end

function PickUpController:PickUp(configId)
    LOG_INFO("pick", configId)
    self.model.saveGame.PickedIds:AddUnique(configId)
    self:Save()

    self.items[configId]:Update()
end

return PickUpController
