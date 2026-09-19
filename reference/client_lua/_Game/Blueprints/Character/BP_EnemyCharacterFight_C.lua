--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local d_attributes = require "ClientDatas.d_attributes"
local d_monster = require "ClientDatas.d_monster"

---@type BP_EnemyCharacter_Fight_C
local M = UnLua.Class()

local function get_attribute_id_by_name(attribute_name)
    for i, v in pairs(d_attributes) do
        if v.attributeNameInFight == attribute_name then
            return i
        end
    end
end

function M:OnLoadFightAttribute()
    ---@type string
    local class_name = self:GetClass():GetName()
    class_name = string.sub(class_name, 1, -3)
    local monster_id = string.sub(class_name, string.len("BP_Enemy_")+1)
    monster_id = tonumber(monster_id)
    if not monster_id then
        LOG_ERROR(string.format("%s::OnLoadFightAttribute monster id is nil", class_name))
        return
    end
    local monster_level = self.CharacterLevel
    local monster_data
    for _, v in pairs(d_monster) do
        if v.Npcid == monster_id and v.Level == monster_level then
            monster_data = v
            break
        end
    end

    if not monster_data then
        LOG_ERROR(string.format("%s::OnLoadFightAttribute monster data is nil, monster id is %s", class_name, tostring(monster_id)))
        return
    end

    LOG_DEBUG("OnLoadFightAttribute", monster_id)

    local attrs = {}
    for attribute_name, attribute_value in pairs(monster_data) do
        local attribute_id = get_attribute_id_by_name(attribute_name)
        if attribute_id then
            attrs[attribute_id] = attribute_value
        end
    end

    -- init fight attributes
    print('==========战斗数值：')
    for i, v in pairs(attrs) do
        local attribute_data = d_attributes[i]
        print("===id:" .. tostring(i) .. ',name:' .. tostring(attribute_data.attributeNameInFight) .. ",v:" .. tostring(v))
        self:InitAttributeSet(attribute_data.attributeNameInFight, v)
    end

    -- fix cur hp
    local cur_value = self:GetHealth()
    local max_value = self:GetMaxHealth()
    if max_value < 1 then
        max_value = 1
        self:InitAttributeSet("HitPoint", max_value)
    end
    if cur_value <= 1 then
        cur_value = math.max(max_value--[[ * 0.01]], 1)
        self:InitAttributeSet("CurrentHealth", cur_value)
    elseif cur_value > max_value then
        self:InitAttributeSet("CurrentHealth", max_value)
    end

    -- fix cur mobility
    local cur_value = self:GetMobility()
    local max_value = self:GetMaxMobility()
    if cur_value > max_value then
        self:InitAttributeSet("CurrentMobility", max_value)
    end

    -- fix cur sp
    local cur_value = self:GetSP()
    local max_value = self:GetMaxSP()
    if cur_value > max_value then
        self:InitAttributeSet("CurrentSP", max_value)
    end

    -- fix cur burst
    local cur_value = self:GetBurst()
    local max_value = self:GetMaxBurst()
    if cur_value > max_value then
        self:InitAttributeSet("CurrentBurst", max_value)
    end
end

return M
