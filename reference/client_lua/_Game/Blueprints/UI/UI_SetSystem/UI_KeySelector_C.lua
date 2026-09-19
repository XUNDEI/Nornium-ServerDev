local InputUtils = require "_Game.Utils.Input.InputUtils"
local Database = require("_Game.Utils.Database")

---@type UI_KeySelector_C
local M = UnLua.Class()

M.ChangeMapping = "UI_KeySelector_C.ChangeMapping"

function M:Construct()
    self.InputKeySelector.OnIsSelectingKeyChanged:Add(self, self.OnIsSelectingKeyChanged)
    self.InputKeySelector.OnKeySelected:Add(self, self.OnKeySelected)

    MessageManager:GetInstance():AddListener(M.ChangeMapping, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(M.ChangeMapping, self)
end

M[M.ChangeMapping] = function(self, MappingName, Key)
    if self.MappingName == MappingName then
        self:BindKey(Key)
    end
end

function M:OnIsSelectingKeyChanged()
    if self.InputKeySelector:GetIsSelectingKey() then
        self.Key:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Key:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
end

---@param InputChord FInputChord
function M:OnKeySelected(InputChord)
    local key = InputChord.Key

    local mapping = InputUtils.GetMapping(self, self.MappingName)
    
    -- 相同说明我们在初始化，别管了
    if mapping.CurrentKey == key then
        return
    end

    if not InputUtils.IsKeyAssignable(key) then
        UIManager:GetInstance():ShowNotification(Database.L10n(373))

        self:Reset()

        return
    end

    local count, existMappingNames = InputUtils.FindConflictMapping(self, key)

    for _, existMappingName in pairs(existMappingNames) do
        local conflictContext = InputUtils.FindDefineMappingContext(existMappingName)
        local selfContext = InputUtils.FindDefineMappingContext(self.MappingName)

        local conflictMapping = InputUtils.GetMapping(self, existMappingName)

        -- 同一IMC下，可以交换按键设置
        if selfContext == conflictContext then
            local notice = string.format(Database.L10n(371), Database.L10n(tonumber(conflictMapping.DisplayName)), Database.L10n(tonumber(mapping.DisplayName)))
            
            local keyName = key.KeyName
            local confirm = function()
                if not UE.UKismetSystemLibrary.IsValid(self) then return end
                local oldKey = mapping.CurrentKey

                self:BindKey(UE.EKeys[keyName])
    
                MessageManager:GetInstance():Broadcast(M.ChangeMapping, existMappingName, oldKey)
            end

            local cancel = function()
                self:Reset()
            end
            UIManager:GetInstance():ShowConfirm({
                notice = notice,
                confirm = confirm,
                cancel = cancel,
                showCancel = true,
            })
            -- 此时也不会有其他冲突，直接返回
            return
        -- 两个IMC并无冲突
        elseif InputUtils.IsCompatible(selfContext, conflictContext) then
            self:BindKey(key)
        else
            local notice = string.format(Database.L10n(374), Database.L10n(InputUtils.MappingContextType[conflictContext]), Database.L10n(tonumber(conflictMapping.DisplayName)))
            UIManager:GetInstance():ShowNotification(notice)
            self:Reset()
            return
        end
    end

    if count == 0 then
        self:BindKey(key)
    end
end

---@param Name string
function M:Init(Name, platform)
    self.MappingName = Name
    self.platform = platform
    self.Key.platform = platform

    local mapping = InputUtils.GetMapping(self, self.MappingName)

    self.Name:SetText(Database.L10n(tonumber(mapping.DisplayName)))

    self.InputKeySelector:SetAllowGamepadKeys(platform ~= InputUtils.Platform.PC)

    self:Reset()
end

function M:Reset()
    local mapping = InputUtils.GetMapping(self, self.MappingName)

    self:ShowKey(mapping.CurrentKey)
end

function M:BindKey(Key)
    self:ShowKey(Key)

    InputUtils.SaveMapping(self, self.MappingName, Key)
end

---@param Key FKey
function M:ShowKey(Key)
    local InputChord = UE.FInputChord()

    InputChord.Key = Key

    self.InputKeySelector:SetSelectedKey(InputChord)

    self.Key:ShowKey(Key)
end

return M
