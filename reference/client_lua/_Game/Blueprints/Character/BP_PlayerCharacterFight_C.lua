--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local UIUtils = require "_Game.Utils.UIUtils"
local d_character = require "ClientDatas.d_character"
local d_attributes = require "ClientDatas.d_attributes"
local d_srpg_effect_buff = require "ClientDatas.d_srpg_effect_buff"
local d_srpg_temp_buff = require "ClientDatas.d_srpg_temp_buff"
local d_role_level = require "ClientDatas.d_role_level"
local d_srpg_card_base = require "ClientDatas.d_srpg_card_base"

---@type BP_PlayerCharacter_Fight_C
local M = UnLua.Class()

-- function M:Initialize(Initializer)
-- end

-- function M:UserConstructionScript()
-- end

-- function M:ReceiveBeginPlay()
--     self.Overridden.ReceiveBeginPlay(self)
--     if self.weapon_id and self.weapon_id > 0 then
--         self:RefreshRoleWeapon(self.weapon_id)
--     end
-- end

function M:OnPostBeginPlay()
    if self.weapon_id and self.weapon_id > 0 then
        self:RefreshRoleWeapon(self.weapon_id)
    end
end

-- function M:ReceiveEndPlay()
-- end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

local function get_universe_info(WorldContextObject)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(WorldContextObject)
    local universe_info = (gameInstance.resUniverse and gameInstance.resUniverse.res_universe) and gameInstance.resUniverse.res_universe.universe_info or nil
    if not universe_info then
        local SrpgController = require('Module.Srpg.SrpgController')
        universe_info = SrpgController:GetInstance():GetUniverseInfo()
    end
    return universe_info
end

local function get_character_fight_data(WorldContextObject, character_id)
    local universe_info = get_universe_info(WorldContextObject)
    if not universe_info then
        return
    end
    local character_fight_datas = universe_info.universe_fight_data and universe_info.universe_fight_data.character_fight_datas or nil
    if not character_fight_datas then
        return
    end
    for _, character_fight_data in ipairs(character_fight_datas) do
        if character_fight_data.character_id == character_id then
            return character_fight_data
        end
    end
end

local function get_attribute_id_by_name(attribute_name)
    for i, v in pairs(d_attributes) do
        if v.attributeNameInFight == attribute_name then
            return i
        end
    end
end

function M:RefreshRoleWeapon(item_id)
    local d_weapon = require("ClientDatas.d_weapon")
    local weaponConfig = d_weapon[item_id]
    if not weaponConfig then 
        LOG_ERROR('--->not this itemId:' .. tostring(item_id) .. " in d_weapon!!!")
        return 
    end
    local mainHandWeaponModelPath = weaponConfig.weaponModel1
    if mainHandWeaponModelPath == "" then
        return
    end
    local offHandWeaponModelPath = weaponConfig.weaponModel2

    if mainHandWeaponModelPath ~= "" then
        if not string.endswith(mainHandWeaponModelPath, "_C'") then
            local sub = string.sub(mainHandWeaponModelPath, 1, -2) .. "_C'"
            mainHandWeaponModelPath = sub
        end
    end

    if offHandWeaponModelPath ~= "" then
        if not string.endswith(offHandWeaponModelPath, "_C'") then
            local sub = string.sub(offHandWeaponModelPath, 1, -2) .. "_C'"
            offHandWeaponModelPath = sub
        end
    end

    local mainHandWeaponClass = UE.UClass.Load(mainHandWeaponModelPath) or nil
    local offHandWeaponClass = ('' ~= offHandWeaponModelPath) and UE.UClass.Load(offHandWeaponModelPath) or nil
    self.WeaponID = item_id
    self:UpdateAllWeapon(mainHandWeaponClass, offHandWeaponClass)
    --self:UpdateWeaponScaleAndOffset()
end

function M:UpdateWeaponScaleAndOffset()
    local class_name = self:GetClass():GetName()
    class_name = string.sub(class_name, 1, -3)
    local character_id
    for i, v in pairs(d_character) do
        if string.endswith(v.fightModelPath, class_name) then
            character_id = i
            break
        end
    end
    if character_id == nil then
        LOG_ERROR(class_name .. "::OnLoadFightAttribute " .. "id is nil")
        return
    end

    local d_character = require('ClientDatas.d_character')
    local config = d_character[character_id]
    if config and config.weaponModel and #config.weaponModel == 6 then
        local params = config.weaponModel
        local pos = UE.FVector(params[4] / 10000, params[5] / 10000, params[6] / 10000)
        local scale = UE.FVector(params[1] / 10000, params[2] / 10000, params[2] / 10000)
        for i = 1, self.WeaponActors:Length() do 
            local actor = self.WeaponActors:Get(i)
            actor:K2_SetActorRelativeLocation(pos, false, nil, false)
            actor:SetActorRelativeScale3D(scale)
        end
    end
end 

function M:InitCharacterSkill()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and playerController.BP_PlayerController_City_UniverseBridge then
        return
    end
    print('===================Possessed:' .. tostring(self.bInitSkillInfo))
    if self.bInitSkillInfo ~= nil and self.bInitSkillInfo then return end
    self.bInitSkillInfo = true 
    ---@type string
    local class_name = self:GetClass():GetName()
    class_name = string.sub(class_name, 1, -3)
    local character_id, character_data
    for i, v in pairs(d_character) do
        if string.endswith(v.fightModelPath, class_name) then
            character_id = i
            character_data = v
            break
        end
    end
    if character_id == nil then
        LOG_ERROR(class_name .. "::ReceivePossessed " .. "id is nil")
        return
    end
    LOG_DEBUG("ReceivePossessed", character_id)
    local character_info = nil
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        --判定当前角色id是否是固定的
        local teamList = gameInstance:LoadTeamList()
        if not teamList then
            teamList = gameInstance:CreateTeamList()
        end
        for i = 1, 3 do
            local trainCharId = teamList.TrainPos:Get(i)
            if trainCharId > 1 then 
                local d_character_trial = require('ClientDatas.d_character_trial')
                local config = d_character_trial[trainCharId]
                if config and config.roleTrialId and config.roleTrialId == character_id then
                    character_info = UIUtils.BuildCharInfo(config.roleTrialId, config.roleLevel, config.firstWeapon, config.roleSkill, config.roleInborn)
                end
            end
        end
    end
    if not character_info then
        character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    end
    if not character_info then
        return
    end
    --武器模型
    local weapon_info = character_info.weapon_info
    if weapon_info then
        self.weapon_id = weapon_info.item_id
    
        --武器精炼的技能效果
        local refineLv = weapon_info.weapon_info.refine_level
        local weaponSkillId = UIUtils.GetWeaponRefineSkill(self.weapon_id, refineLv)
        if weaponSkillId and weaponSkillId > 0 then
            --读取技能表
            local config = require("ClientDatas.d_skill")[weaponSkillId]
            if config and config.skillPath and config.skillPath ~= '' then
                local classPath = config.skillPath --"/Script/Engine.Blueprint'/Game/_Game/Blueprints/Players/GE_WeaponBuffTest_2.GE_WeaponBuffTest_2'"
                if classPath ~= "" then
                    if not string.endswith(classPath, "_C'") then
                        local sub = string.sub(classPath, 1, -2) .. "_C'"
                        classPath = sub
                    end
                    local skillClass = UE.UClass.Load(classPath)
                    if skillClass then
                        local skillParams1 = UIUtils.GetWeaponSkillParams(weaponSkillId, refineLv)
                        local skillParams2 = UIUtils.GetTalentSkillParamsEx(weaponSkillId, { refineLv + 1 })
                        local str = ''
                        for _, pStr in ipairs(skillParams2) do
                            str = str .. (str ~= '' and ',' or '') .. tostring(pStr)
                        end
                        print("=====>>>>>>>武器技能id:" .. tostring(weaponSkillId) .. ",str:" .. tostring(str))
                        -- self.WeaponSkill = str
                        self:OnWeaponSkillInit(skillClass, str)
                    end
                end
            end
        end
    end
    
    --装备符文
    local equipSkillList = UIUtils.GetCharacterEquipSkillList(character_id, character_info)
    if equipSkillList then
        for _, skillId in ipairs(equipSkillList) do
            --读取技能表
            local config = require("ClientDatas.d_skill")[skillId]
            if config and config.skillPath and config.skillPath ~= '' then
                local classPath = config.skillPath --"/Script/Engine.Blueprint'/Game/_Game/Blueprints/Players/GE_WeaponBuffTest_2.GE_WeaponBuffTest_2'"
                if classPath ~= "" then
                    if not string.endswith(classPath, "_C'") then
                        local sub = string.sub(classPath, 1, -2) .. "_C'"
                        classPath = sub
                    end
                    local skillClass = UE.UClass.Load(classPath)
                    if skillClass then
                        local skillParams = UIUtils.GetTalentSkillParamsEx(skillId, { 1 })
                        local str = ''
                        for _, pStr in ipairs(skillParams) do
                            str = str .. (str ~= '' and ',' or '') .. tostring(pStr)
                        end
                        print("=====>>>>>>>装备技能id:" .. tostring(skillId) .. ",str:" .. tostring(str))
                        self.EquipSkill:Add(skillId, str)
                        self.EquipGE:Add(skillClass)
                        self:OnEquipSkillInit(skillClass, config.rateShow)
                    end
                end
            end
        end
    end

    --天赋技能
    self.TalentSkill:Clear()
    self.TalentGE:Clear()
    local talentSkillList = UIUtils.GetTalentSkillInfo(character_id, character_info)
    if talentSkillList then
        for skillId, skillLvs in pairs(talentSkillList) do 
            local config = require("ClientDatas.d_skill")[skillId]
            if config and config.skillPath and config.skillPath ~= '' then
                local classPath = config.skillPath --"/Script/Engine.Blueprint'/Game/_Game/Blueprints/Players/GE_WeaponBuffTest_2.GE_WeaponBuffTest_2'"
                if classPath ~= "" then
                    if not string.endswith(classPath, "_C'") then
                        local sub = string.sub(classPath, 1, -2) .. "_C'"
                        classPath = sub
                    end
                    local skillClass = UE.UClass.Load(classPath)
                    if skillClass then
                        --技能等级参数
                        local skillParams = UIUtils.GetTalentSkillParamsEx(skillId, skillLvs)
                        local str = ''
                        for _, pStr in ipairs(skillParams) do
                            str = str .. (str ~= '' and ',' or '') .. tostring(pStr)
                        end
                        print("=====>>>>>>>天赋技能id:" .. tostring(skillId) .. ",str:" .. tostring(str))
                        self.TalentSkill:Add(skillId, str)
                        self.TalentGE:Add(skillClass)
                    end
                end
            end
        end
    end

    --角色技能
    local roleActiveSkillList = {}
    local d_skill = require("ClientDatas.d_skill")
    for _, v in pairs(d_skill) do
        if v.skillType == 1 then
            local bFind = v.belongCharId == character_id
            -- for _, rId in ipairs(v.belongCharId) do 
            --     if rId == character_id then
            --         bFind = true
            --         break
            --     end
            -- end
            if bFind then
                local lv = 1
                for _, skillInfo in ipairs(character_info.skill_infos) do
                    if skillInfo.skill_id == v.id then
                        lv = skillInfo.skill_level
                        break
                    end
                end

                local skillInfo = {
                    ['skill_id'] = v.id,
                    ['skill_level'] = lv,
                }
                table.insert(roleActiveSkillList, skillInfo)
            end
        end
    end

    for _, skillInfo in ipairs(roleActiveSkillList) do
        local skillId = skillInfo.skill_id
        local skillLv = skillInfo.skill_level
        local config = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
        if config then
            local str = ''
            for _, pStr in ipairs(config.clickDamage) do
                str = str .. (str ~= '' and ',' or '') .. tostring(pStr)
            end
            local str2 = ''
            for _, pStr in ipairs(config.pressDamage) do 
                str2 = str2 .. (str2 ~= '' and ',' or '') .. tostring(pStr)
            end
            str = str .. '|' .. str2
            print("=====>>>>>>>角色技能id:" .. tostring(skillId) .. ",str:" .. tostring(str))
            self.RoleSkill:Add(skillId, str)
        end
    end

    self:OnTalentSkillInit()

   
end

function M:OnLoadFightAttribute()
    ---@type string
    local class_name = self:GetClass():GetName()
    class_name = string.sub(class_name, 1, -3)
    local character_id, character_data
    for i, v in pairs(d_character) do
        if string.endswith(v.fightModelPath, class_name) then
            character_id = i
            character_data = v
            break
        end
    end
    if character_id == nil then
        LOG_ERROR(class_name .. "::OnLoadFightAttribute " .. "id is nil")
        return
    end
    LOG_DEBUG("OnLoadFightAttribute", character_id)
    local character_info = nil
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance and gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        --判定当前角色id是否是固定的
        local teamList = gameInstance:LoadTeamList()
        if not teamList then
            teamList = gameInstance:CreateTeamList()
        end
        for i = 1, 3 do
            local trainCharId = teamList.TrainPos:Get(i)
            if trainCharId > 1 then 
                local d_character_trial = require('ClientDatas.d_character_trial')
                local config = d_character_trial[trainCharId]
                if config and config.roleTrialId and config.roleTrialId == character_id then
                    character_info = UIUtils.BuildCharInfo(config.roleTrialId, config.roleLevel, config.firstWeapon, config.roleSkill, config.roleInborn)
                end
            end
        end
    end
    if not character_info then
        character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    end
    if not character_info then
        LOG_ERROR(character_id .. "::OnLoadFightAttribute " .. "not have this char")
        return
    end

    -- character
    local character_level = UIUtils.GetCharacterLevel(character_id, character_info.break_times, character_info.exp)
    print('------character_level:' .. tostring(character_level))
    self:SetCharacterLevel(character_level)
    local universe_info = get_universe_info(self)
    if universe_info then
        if universe_info.forever_buff_infos then
            for _, forever_buff_info in ipairs(universe_info.forever_buff_infos) do
                local buff_data = d_srpg_effect_buff[forever_buff_info.buff_id]
                if buff_data.buffType == 10 then
                    character_level = character_level + buff_data.buffValue[1]
                end
            end
        end
        if universe_info.realtime_buff_infos then
            for _, realtime_buff_info in ipairs(universe_info.realtime_buff_infos) do
                local temp_buff_data = d_srpg_temp_buff[realtime_buff_info.buff_id]
                for _, buff_id in ipairs(temp_buff_data.effectBuffID) do
                    local buff_data = d_srpg_card_base[buff_id]
                    if buff_data.buffType == 10 then
                        character_level = character_level + buff_data.buffValue[1]
                    end
                end
            end
        end
    end

    local max_level_in_fight = d_role_level[#d_role_level].id
    character_level = math.min(character_level, max_level_in_fight)
    
    local attrs = UIUtils.GetTempCharacterAllAttr(character_info)

    local cur_attribute_id = get_attribute_id_by_name("CurrentHealth")
    local HitPointAttrId = get_attribute_id_by_name("HitPoint")
    local character_fight_data = get_character_fight_data(self, character_id)
    if character_fight_data then
        if gameInstance.fightType == gameInstance.FIGHT_STATE.UNIVERSE then
            attrs[cur_attribute_id] = math.min(character_fight_data.cur_hp, attrs[HitPointAttrId])
        else
            attrs[cur_attribute_id] = attrs[HitPointAttrId]
        end
    else
        attrs[cur_attribute_id] = attrs[HitPointAttrId]
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
        cur_value = math.max(max_value * 0.01, 1)
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

    self:InitCharacterSkill()
end

return M
