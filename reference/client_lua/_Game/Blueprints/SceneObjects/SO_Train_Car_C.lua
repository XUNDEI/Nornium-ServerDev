--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_Train_Car_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
   
    self.CarArrivalSequence = '/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/SQ_Train_Arrival.SQ_Train_Arrival'
    self.CarLeaveSequence = '/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/SQ_Train_Leave.SQ_Train_Leave'
end

function M:ReceiveEndPlay()
    if self.ArrivalSequenceActor and UE.UKismetSystemLibrary.IsValid(self.ArrivalSequenceActor) then
        self.ArrivalSequenceActor:K2_DestroyActor()
    end
    self.ArrivalSequenceActor = nil
    if self.LeaveSequenceActor and UE.UKismetSystemLibrary.IsValid(self.LeaveSequenceActor) then
        self.LeaveSequenceActor:K2_DestroyActor()
    end
    self.LeaveSequenceActor = nil
end

function M:PlayCarArrival(callback)
    -- print('----car:' .. self.Tags:Get(1) .. ", arrival")
    if not self.ArrivalSequenceActor then
        local levelSequence = LoadObject(self.CarArrivalSequence)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(self.CabinStartSequencePath))
            return 
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.ArrivalSequenceActor = sequenceActor
        self.ArrivalSequenceActor:AddBindingByTag("MainObj", self, false)

        self.ArrivalSequenceActor:K2_AttachToActor(self, "",
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            false)
    end

    if self.ArrivalSequenceActor and self.ArrivalSequenceActor.SequencePlayer then
        self.ArrivalSequenceActor.SequencePlayer.OnFinished:Clear()
        self.ArrivalSequenceActor.SequencePlayer.OnFinished:Add(self, function()
            self.ArrivalSequenceActor.SequencePlayer.OnFinished:Clear()
            if callback then
                callback(self)
            end
        end)
        self.ArrivalSequenceActor.SequencePlayer:Play()
    end
end

function M:PlayCarLeave(callback)
    -- print('----car:' .. self.Tags:Get(1) .. ", leave")
    if not self.LeaveSequenceActor then
        local levelSequence = LoadObject(self.CarLeaveSequence)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(self.CabinStartSequencePath))
            return 
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.LeaveSequenceActor = sequenceActor
        self.LeaveSequenceActor:AddBindingByTag("MainObj", self, false)
        self.LeaveSequenceActor:K2_AttachToActor(self, "",
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            false)
    end

    if self.LeaveSequenceActor and self.LeaveSequenceActor.SequencePlayer then
        self.LeaveSequenceActor.SequencePlayer.OnFinished:Clear()
        self.LeaveSequenceActor.SequencePlayer.OnFinished:Add(self, function()
            self.LeaveSequenceActor.SequencePlayer.OnFinished:Clear()
            if callback then
                callback(self)
            end
        end)
        self.LeaveSequenceActor.SequencePlayer:Play()
    end
end

return M
