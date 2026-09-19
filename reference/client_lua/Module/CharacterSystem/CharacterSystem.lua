local NetCmdController = require "Framework.Common.NetCmdController"
local CharacterSystem = BaseClass("CharacterSystem", NetCmdController)
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"

local ErrorCode = 
{
    LevelUpResultType = 
    {
        OK = 0,
        NO_CHARACTER = 1,
        MAX_LEVEL = 2,
        INVALID_ITEM = 3,
        INVALID_COUNT = 4,
        RES_NOT_ENOUGH = 5,
    },
    LevelBreakResultType = {
        OK = 0,
        NO_CHARACTER = 1,
        MAX_LEVEL_BREAK = 2,
        STUFF_NOT_ENOUGH = 3,
    },
    SwapWeapon = {
        OK = 0;
        NO_CHARACTER = 1;
        INVALID_ITEM = 3;
    },
    SkillLvUpResultType = {
        OK = 0;
        NO_CHARACTER = 1;
        NO_SKILL = 2;
        MAX_LEVEL = 3;
        INVALID_ITEM = 4;
        INVALID_COUNT = 5;
        RES_NOT_ENOUGH = 6;
    },
    UnlockTalent = {
        OK                     = 0;
        NO_CHARACTER           = 1;
        TALENT_UNLOCKED        = 2;
        INVALID_TALENT_ID      = 3;
        PRE_TALENT_LOCKED      = 4;
        CHECK_CONDITION_FAILED = 5;
        STUFF_NOT_ENOUGH       = 6;
    },
    CharacterChangeSkinType = {
        OK           = 0;
        NO_CHARACTER = 1;
        NO_CHANGE    = 2;
        NO_SKIN      = 3;
    }
}

CharacterSystem.CharacterInfo = {}

function CharacterSystem:GetCharacterInfoById(id)
    for _, v in pairs(self.CharacterInfo) do
        if v.character_id == id then
            return v
        end
    end
    return nil
end

function CharacterSystem:CacheCharacterInfo(character_id, exp, breakTimes)
    self.CachedCharacterId = character_id
    self.CachedCharacterExp = exp
    self.CachedCharacterBreakTimes = breakTimes
end

--缓存交换的武器的角色信息
function CharacterSystem:CacheSwapWeapon(character_id, swap_character_id)
    self.CachedCharacterId = character_id
    self.CachedSwapCharacterId = swap_character_id
end

--缓存交换的装备的角色信息
function CharacterSystem:CacheSwapArm(character_id, swap_character_id, item_slot)
    self.CachedCharacterId = character_id
    self.CachedSwapCharacterId = swap_character_id
    self.CachedItemSlot = item_slot
end

--技能升级
function CharacterSystem:CacheSkillInfo(characterId, skillId, skillLv)
    self.CahcedSkillCharacterId = characterId
    self.CahcedSkillId = skillId
    self.CahcedSkillLv = skillLv
end

--天赋激活
function CharacterSystem:CacheTalentInfo(characterId, talentId, materialList, currencyList)
    self.CachedTalentCharId = characterId
    self.CachedTalentId = talentId
    self.CachedMaterialList = materialList 
    self.CachedCurrencyList = currencyList
end

--皮肤 
function CharacterSystem:CacheSkinInfo(characterId, charSkinId, mechaSkinId, cityCharSkinId)
    self.CachedSkinCharId = characterId
    self.CachedSkinCharSkinId = charSkinId
    self.CachedSkinMechaSkinId = mechaSkinId
    self.CachedSkinCityCharSkinId = cityCharSkinId
end

function CharacterSystem:SetGameInstance(gameInstance)
    self.GameInstance = gameInstance
end

---------------------------------------------------------
---协议处理
function CharacterSystem:OnNetCmd_Res_Character_List(result, msgId, parsed_msg)
    LOG_INFO("==服务器下发角色数据:" .. tostring(result))
    if result == 0 and 
        parsed_msg and 
        parsed_msg.res_character_list and 
        parsed_msg.res_character_list.character_list_info and 
        parsed_msg.res_character_list.character_list_info.character_infos then

        self.CharacterInfo = parsed_msg.res_character_list.character_list_info.character_infos

        --print("===>characterList:" .. tostring(table.dump(parsed_msg, false, 10)))
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_List_Success")
    end
end

function CharacterSystem:OnNetCmd_Ntf_Character_Info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_character_info and parsed_msg.ntf_character_info.changed_character_infos then
            for _, changed_character_info in ipairs(parsed_msg.ntf_character_info.changed_character_infos) do
                local charInfo = self:GetCharacterInfoById(changed_character_info.character_id)
                if charInfo then
                    LOG_ERROR('===>>已有此角色:' .. tostring(changed_character_info.character_id))
                    for idx, v in pairs(self.CharacterInfo) do
                        if v.character_id == changed_character_info.character_id then
                            self.CharacterInfo[idx] = changed_character_info
                            break
                        end
                    end
                else
                    table.insert(self.CharacterInfo, changed_character_info)
                end
            end
        end
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Level_Up(result, msgId, parsed_msg)
    LOG_INFO("==升级:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    print("===exp:" .. tostring(self.CachedCharacterExp))
    if result == ErrorCode.LevelUpResultType.OK then
        --Client.send("req_character_list")
        for _, v in pairs(self.CharacterInfo) do
            if v.character_id == self.CachedCharacterId then
                v.exp = self.CachedCharacterExp
                break
            end
        end
        self.CachedCharacterId = 0 
        self.CachedCharacterExp = 0
        self.CachedCharacterBreakTimes = 0
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Level_Up_Success")
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Level_Break(result, msgId, parsed_msg)
    LOG_INFO("==突破:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    print("===breatimes:" .. tostring(self.CachedCharacterBreakTimes))
    if result == ErrorCode.LevelBreakResultType.OK then
        --Client.send("req_character_list")
        for _, v in pairs(self.CharacterInfo) do
            if v.character_id == self.CachedCharacterId then
                v.break_times = self.CachedCharacterBreakTimes
                break
            end
        end
        self.CacheCharacterId = 0 
        self.CachedCharacterExp = 0
        self.CachedCharacterBreakTimes = 0
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Level_Break_Success")
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Swap_Weapon(result, msgId, parsed_msg)
    LOG_INFO("==交换:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.SwapWeapon.OK then
        local character_info = self:GetCharacterInfoById(self.CachedCharacterId)
        local swap_character_info = self:GetCharacterInfoById(self.CachedSwapCharacterId)
        local swap_weapon = swap_character_info.weapon_info
        swap_character_info.weapon_info = character_info.weapon_info
        character_info.weapon_info = swap_weapon
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Swap_Weapon")
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Swap_Arm(result, msgId, parsed_msg)
    LOG_INFO("==交换:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.SwapWeapon.OK then
        local character_info = self:GetCharacterInfoById(self.CachedCharacterId)
        local swap_character_info = self:GetCharacterInfoById(self.CachedSwapCharacterId)
        local swap_arm = {}
        local swap_index = {}
        for index, arm_info in pairs(swap_character_info.arm_infos) do
            if arm_info.config.subType == self.CachedItemSlot then
                swap_index = index
                swap_arm = arm_info
                break
            end
        end

        local find = false
        for index, arm_info in pairs(character_info.arm_infos) do
            if arm_info.config.subType == self.CachedItemSlot then
                swap_character_info.arm_infos[swap_index] = arm_info
                character_info.arm_infos[index] = swap_arm
                find = true
                break
            end
        end
        if not find then
            swap_character_info.arm_infos[swap_index] = nil
            table.insert(character_info.arm_infos, swap_arm)
        end
        
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Swap_Arm")
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Skill_Level_Up(result, msgId, parsed_msg)
    LOG_INFO("==技能升级:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.SkillLvUpResultType.OK then
        local character_info = self:GetCharacterInfoById(self.CahcedSkillCharacterId)
        local haveSkill = false
        for idx, skills in ipairs(character_info.skill_infos) do
            if skills.skill_id == self.CahcedSkillId then
                skills.skill_level = self.CahcedSkillLv
                haveSkill = true
                break
            end
        end
        if not haveSkill then
            table.insert(character_info.skill_infos, {
                ['skill_id'] = self.CahcedSkillId,
                ['skill_level'] = self.CahcedSkillLv
            })
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Skill_Level_Up_Success", {
            character_id = self.CahcedSkillCharacterId, 
            skill_id = self.CahcedSkillId, 
            skill_level = self.CahcedSkillLv
        })
    end
end

function CharacterSystem:OnNetCmd_Res_Character_Unlock_Talent(result, msgId, parsed_msg)
    LOG_INFO("==天赋激活:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.UnlockTalent.OK then
        local character_info = self:GetCharacterInfoById(self.CachedTalentCharId)
        table.insert(character_info.talent_ids, self.CachedTalentId)
        local BackpackSystem = require("Module.Backpack.BackpackSystem")
        --消耗的材料处理
        if self.CachedMaterialList then
            for _, v in pairs(self.CachedMaterialList) do 
                BackpackSystem:GetInstance():AddItemCount(v.item_id, -v.count)
            end
        end 
        if self.CachedCurrencyList then
            for _, v in pairs(self.CachedCurrencyList) do 
                BackpackSystem:GetInstance():AddItemCount(v.item_id, -v.count)
            end
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Talent_Active_Success")
    end
    self.CachedTalentCharId = 0
end

--角色/机甲皮肤
function CharacterSystem:OnNetCmd_Res_Character_Change_Skin(result, msgId, parsed_msg)
    if result == ErrorCode.CharacterChangeSkinType.OK then
        for _, v in pairs(self.CharacterInfo) do
            if v.character_id == self.CachedSkinCharId then
                v.character_skin_id = self.CachedSkinCharSkinId
                v.mecha_skin_id     = self.CachedSkinMechaSkinId
                v.city_skin_id      = self.CachedSkinCityCharSkinId
                break
            end
        end

        self.CachedSkinCharId = 0
        self.CachedSkinCharSkinId = 0
        self.CachedSkinMechaSkinId = 0
        self.CachedSkinCityCharSkinId = 0
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Character_Change_Skin_Success")
    elseif result == ErrorCode.CharacterChangeSkinType.NO_CHARACTER then
        print('----------没有这个角色')
    elseif result == ErrorCode.CharacterChangeSkinType.NO_CHANGE then
        print('----------没有改变')
    elseif result == ErrorCode.CharacterChangeSkinType.NO_SKIN then
        print('----------没有皮肤')
    end
end 

---------------------------------------------------------
---数据处理
function CharacterSystem:GetCharacterInfoByWeaponUUID(uuid)
    for _, v in pairs(self.CharacterInfo) do
        if v.weapon_info and v.weapon_info.item_uuid == uuid then
            return v
        end
    end
    return nil
end

function CharacterSystem:GetCharacterInfoByEquipUUID(uuid)
    for _, v in pairs(self.CharacterInfo) do
        if v.arm_infos then
            for _, armInfo in pairs(v.arm_infos) do 
                if armInfo.uuid == uuid then
                    return v
                end
            end
        end
    end
    return nil
end

--满命判断
function CharacterSystem:GetCharacterTalentCount(id)
    local UIUtils = require '_Game.Utils.UIUtils'
    local bFull = false
    for _, character_info in pairs(self.CharacterInfo) do
        if character_info.character_id == id then
            local charConfig = require('ClientDatas.d_character')[id]
            if charConfig then
                local inborn_item_id = charConfig.inbornItem
                local count = UIUtils.GetItemCount(charConfig.inbornItem)
                local talent_ids = character_info.talent_ids
                for index, talent_id in ipairs(talent_ids) do
                    local talent_data = require('ClientDatas.d_character_inborn')[talent_id]
                    if not talent_data then
                        return bFull
                    end
                    if talent_data.openNeed == 50004 and talent_data.openNeedPrice[1] == inborn_item_id then
                        count = count + 1
                    end
                end
                bFull = count + 1 >= 7
                return bFull
            else
                LOG_ERROR('d_character cant find' .. id)
            end
        end
    end
    return bFull
end

--使用角色卡判定
function CharacterSystem:UsePlayerSkin(itemid)
    local UIUtils = require '_Game.Utils.UIUtils'
    local itemConfig = UIUtils.GetItemConfigById(itemid)
    if itemConfig then
        local charId = itemConfig.subParam[1] --角色id的
        local skinItemId = itemConfig.subParam[2] --皮肤道具id
        local charInfo = self:GetCharacterInfoById(charId)
        if charInfo then
            local SkinItemConfig = UIUtils.GetItemConfigById(skinItemId)
            if SkinItemConfig and SkinItemConfig.itemType == UIUtils.ItemMainType.Skin then
                for _, skinId in pairs(SkinItemConfig.subParam) do
                    local skinConfig = require('ClientDatas.d_char_clothes')[skinId]
                    if skinConfig then
                        if skinConfig.dressType == 1 then
                            local hasSkin = false
                            for _, sid in pairs(charInfo.own_character_skin_ids) do
                                if sid == skinId then
                                    hasSkin = true
                                    break
                                end
                            end
                            if not hasSkin then
                                table.insert(charInfo.own_character_skin_ids, skinId)
                            end
                        elseif skinConfig.dressType == 2 then
                            local hasSkin = false
                            for _, sid in pairs(charInfo.own_mecha_skin_ids) do
                                if sid == skinId then
                                    hasSkin = true
                                    break
                                end
                            end
                            if not hasSkin then
                                table.insert(charInfo.own_mecha_skin_ids, skinId)
                            end
                        elseif skinConfig.dressType == 3 then
                            local hasSkin = false
                            for _, sid in pairs(charInfo.own_city_skin_ids) do
                                if sid == skinId then
                                    hasSkin = true
                                    break
                                end
                            end
                            if not hasSkin then
                                table.insert(charInfo.own_city_skin_ids, skinId)
                            end
                        end
                    end
                end
            end
        end
    end
end

--使用涂装道具判定
function CharacterSystem:UseSkinItem(itemid)
    local UIUtils = require '_Game.Utils.UIUtils'
    local SkinItemConfig = UIUtils.GetItemConfigById(itemid)
    if SkinItemConfig and SkinItemConfig.itemType == UIUtils.ItemMainType.Skin then
        for _, skinId in pairs(SkinItemConfig.subParam) do
            local skinConfig = require('ClientDatas.d_char_clothes')[skinId]
            if skinConfig then
                local charId = skinConfig.charBelong
                local charInfo = self:GetCharacterInfoById(charId)
                if charInfo then
                    if skinConfig.dressType == 1 then
                        local hasSkin = false
                        for _, sid in pairs(charInfo.own_character_skin_ids) do
                            if sid == skinId then
                                hasSkin = true
                                break
                            end
                        end
                        if not hasSkin then
                            table.insert(charInfo.own_character_skin_ids, skinId)
                        end
                    elseif skinConfig.dressType == 2 then
                        local hasSkin = false
                        for _, sid in pairs(charInfo.own_mecha_skin_ids) do
                            if sid == skinId then
                                hasSkin = true
                                break
                            end
                        end
                        if not hasSkin then
                            table.insert(charInfo.own_mecha_skin_ids, skinId)
                        end
                    elseif skinConfig.dressType == 3 then
                        local hasSkin = false
                        for _, sid in pairs(charInfo.own_city_skin_ids) do
                            if sid == skinId then
                                hasSkin = true
                                break
                            end
                        end
                        if not hasSkin then
                            table.insert(charInfo.own_city_skin_ids, skinId)
                        end
                    end
                end
            end
        end
    end
end

--判断是否有指定武器id在角色身上装备中
function CharacterSystem:HasWeaponInAllCharacter(weapon_id)
    for _, v in pairs(self.CharacterInfo) do
        if v.weapon_info and v.weapon_info.item_id == weapon_id then
            return true
        end
    end
    return false
end

return CharacterSystem
