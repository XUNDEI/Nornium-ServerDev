---@class PickUpModel
---@field pickedItems number[]
---@field saveGame SG_SaveGame_PickUp_C
local PickUpModel = BaseClass("PickUpModel")

function PickUpModel:__init()
    self.pickedItems = {}
end

function PickUpModel:Init()
end

function PickUpModel:IsPicked(configId)
    return self.saveGame.PickedIds:Contains(configId)
end

return PickUpModel
