---@type BP_LevelSequenceDirector_C
local M = UnLua.Class()

---@param Player AActor
---@param Target AActor
function M:Loop(startFrame, endFrame)
    print("-------->loop:" .. tostring(startFrame) .. ",end:" .. tostring(endFrame) .. ",levelsequence:" .. tostring(self:GetName()))
    if self.Player then
        
        -- if not self.lastStartFrame then self.lastStartFrame = 0 end
        -- if not self.lastEndFrame then self.lastEndFrame = 0 end
        -- if self.lastStartFrame ~= startFrame and self.lastEndFrame ~= endFrame then
        --     self.lastStartFrame = startFrame
        --     self.lastEndFrame = endFrame

            -- self.Player:SetPlayRate(1)
            self.Player:SetFrameRange(startFrame, endFrame - startFrame, 0)
            self.Player:PlayLooping(-1)

            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            if gameInstance and not string.contains(self:GetName(), "Cam_") then
                gameInstance:OnMessage('AnimationLooping', 1)
            end
        -- end
    end
end

function M:Dialog(id)
    print("-------->Dialog:" .. tostring(id))
    if self.Player then
        -- if not self.lastDialogId then self.LastDialogId = 0 end
        -- if self.LastDialogId ~= id then
        --     self.LastDialogId = id

            -- self.Player:SetPlayRate(1)
            
        -- end
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance then
        gameInstance:OnMessage('AnimationDialog', id)
    end
end

return M
