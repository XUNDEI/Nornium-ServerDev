local NetCmdController = require "Framework.Common.NetCmdController"
local BackpackSystem = BaseClass("BackpackSystem", NetCmdController)
local MessageManager = require "Framework.Updater.MessageManager"
local Client = require "Network.Client"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"

local ErrorCode = 
{
    ResultType = 
    {
        OK = 0,
        NO_ITEM = 1,
        INVALID_COUNT = 2,
    }
    ,
    ReplaceWeaponResultType =
    {
        OK = 0;
        NO_CHARACTER = 1;
        NO_ITEM = 2;
        INVALID_ITEM = 3; 
    }
}
---------------------------------------------------------
---数据处理
BackpackSystem.BagInfo = {}
BackpackSystem.NtfBagInfo = {}

--根据指定类型获取道具(不能查找武器/装备)
function BackpackSystem:GetAllItemByMainType(mainType)
    local result = {}
    local d_bag_item = require "ClientDatas.d_bag_item"
    local d_bag_item_weapon = require "ClientDatas.d_bag_item_weapon"
    local d_bag_item_equip = require "ClientDatas.d_bag_item_equip"
    for itemId, v in pairs(self.BagInfo) do 
        local config = d_bag_item[itemId]
        if not config then
            config = d_bag_item_weapon[itemId]
        end
        if not config then
            config = d_bag_item_equip[itemId]
        end
        if config and config.itemType == mainType then
            for _, itemInfo in pairs(v) do 
                itemInfo.config = config
                table.insert(result, itemInfo)
            end
        end
    end
    return result
end

--根据指定类型获取道具(不能查找武器/装备)
function BackpackSystem:GetAllItemByType(mainType, subType)
    local result = {}
    local d_bag_item = require "ClientDatas.d_bag_item"
    local d_bag_item_weapon = require "ClientDatas.d_bag_item_weapon"
    local d_bag_item_equip = require "ClientDatas.d_bag_item_equip"
    for itemId, v in pairs(self.BagInfo) do 
        local config = d_bag_item[itemId]
        if not config then
            config = d_bag_item_weapon[itemId]
        end
        if not config then
            config = d_bag_item_equip[itemId]
        end
        if config and config.itemType == mainType and config.subType == subType then
            for _, itemInfo in pairs(v) do 
                itemInfo.config = config
                table.insert(result, itemInfo)
            end
        end
    end
    return result
end

function BackpackSystem:GetItemCount(itemId)
    local count = 0
    local itemInfo = self.BagInfo[itemId]
    if itemInfo then
        for _, v in pairs(itemInfo) do
            --print("===item:" .. tostring(table.dump(v, false, 10)))
            count = count + v.count
        end
    end
    return count
end

function BackpackSystem:AddItemCount(itemId, addCount)
    local _itemInfo = self.BagInfo[itemId]
    if _itemInfo then
        for k, itemInfo in pairs(_itemInfo) do 
            if itemInfo.item_id == itemId then
                local leftCount = itemInfo.count + addCount
                if leftCount < 0 then
                    table.remove(self.BagInfo[itemId], k)
                    addCount = leftCount
                elseif leftCount == 0 then
                    table.remove(self.BagInfo[itemId], k)
                    return true
                else
                    itemInfo.count = leftCount
                    return true
                end
            end
        end
    else
        return false
    end
    return false
end

function BackpackSystem:GetItemByUUID(uuid)
    for _, v in pairs(self.BagInfo) do 
        for _, itemInfo in pairs(v) do
            if itemInfo.item_uuid == uuid then
                return itemInfo
            end
        end
    end
end

--缓存升级/突破的武器/装备uuid
function BackpackSystem:CacheWeaponOrEquipInfo(item_uuid, item_id, exp, breakTimes)
    self.CachedItemUuid = item_uuid
    self.CachedItemId = item_id
    self.CachedItemExp = exp
    self.CachedItemBreakTimes = breakTimes
end

--缓存替换的武器/装备
function BackpackSystem:CacheReplaceWeaponOrEquip(character_id, replace_weapon)
    self.CachedCharacterId = character_id
    self.CachedReplaceWeaponOrEquipInfo = replace_weapon
end

--缓存精炼的武器
function BackpackSystem:CacheRefineWeapons(refined_item_id, refined_item_uuid, stuff_item_uuid)
    self.CachedRefinedItemId = refined_item_id
    self.CachedRefinedItemUuId = refined_item_uuid
    self.CachedStuffItemUuid = stuff_item_uuid
end


--缓存使用的道具
function BackpackSystem:CachedUseItem(item_data, bShowNotify)
    self.CachedItemData = self.CachedItemData or {}
    item_data.bShow = bShowNotify
    table.insert(self.CachedItemData, item_data)
end

--缓存融合/分解/锻造的物品
function BackpackSystem:CacheChangeItem(msg)
    self.CachedChangedItemsInfo = msg
end

---------------------------------------------------------
---协议处理
function BackpackSystem:OnNetCmd_Res_Bag(result, msgId, parsed_msg)
    --LOG_INFO("==服务器下发背包数据:" .. tostring(result))
    if result == 0 then
        --优化数据存储结构
        self.BagInfo = {}
        for _, v in pairs(self.NtfBagInfo) do
            if not self.BagInfo[v.item_id] then
                self.BagInfo[v.item_id] = {}
            end
            table.insert(self.BagInfo[v.item_id], v)
        end
        self.NtfBagInfo = {}
        --print("====背包数据:" .. tostring(table.dump(self.BagInfo, false, 10)))
        MessageManager:GetInstance():Broadcast("OnMsg_Bag_Init")
    end
end

function BackpackSystem:OnNetCmd_Ntf_Bag_Info(result, msgId, parsed_msg)
    if result == 0 and
        parsed_msg and 
        parsed_msg.ntf_bag_info and 
        parsed_msg.ntf_bag_info.bag_info and 
        parsed_msg.ntf_bag_info.bag_info.item_infos then

        for _, v in pairs(parsed_msg.ntf_bag_info.bag_info.item_infos) do
            table.insert(self.NtfBagInfo, v)
        end
        --print("====背包数据:" .. tostring(table.dump(self.BagInfo, false, 10)))
        --MessageManager:GetInstance():Broadcast("OnMsg_Ntf_Bag_Info")
    end
end

function BackpackSystem:OnNetCmd_Res_Player(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK and
        parsed_msg and 
        parsed_msg.res_player and 
        parsed_msg.res_player.player_info then

        self.PlayerInfo = parsed_msg.res_player.player_info
        for index, value in ipairs(self.PlayerInfo.blueprint_ids) do
            self.PlayerInfo.blueprint_ids[index] = { blueprintId = value, isNew = false }
        end

        for index, value in ipairs(self.PlayerInfo.arm_blueprint_ids) do
            self.PlayerInfo.arm_blueprint_ids[index] = { blueprintId = value, isNew = false }
        end
    end
end

function BackpackSystem:OnNetCmd_Res_Use_Item(result, msgId, parsed_msg)
    -- print("======OnNetCmd_Res_Use_Item.result:" .. tostring(result))
    -- NO_ITEM       = 1;
    -- INVALID_ITEM  = 2;
    -- INVALID_COUNT = 3;
    if result == ErrorCode.ResultType.OK then
        local UIUtils = require "_Game.Utils.UIUtils"
        local itemInfo = self.CachedItemData[1] or nil
        if itemInfo then
            if itemInfo.config.itemType == UIUtils.ItemMainType.TempProp then
                if itemInfo.config.subType == UIUtils.ItemTempPropType.BluePrint then
                    for _, blueprintId in ipairs(itemInfo.config.subParam) do
                        table.insert(self.PlayerInfo.blueprint_ids, { blueprintId = blueprintId, isNew = true })
                    end
                elseif itemInfo.config.subType == UIUtils.ItemTempPropType.ForgeBP then
                    for _, blueprintId in ipairs(itemInfo.config.subParam) do
                        table.insert(self.PlayerInfo.arm_blueprint_ids, { blueprintId = blueprintId, isNew = true })
                    end
                end
            end
            --判断是否是皮肤卡
            if itemInfo.config.itemType == UIUtils.ItemMainType.Skin then
                for i = 1, #itemInfo.config.subParam do
                    local skinId = itemInfo.config.subParam[i]
                    local config = require('ClientDatas.d_char_clothes')[skinId]
                    if config then
                        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(config.charBelong)
                        if charInfo then
                            if config.dressType == 1 then
                                table.insert(charInfo.own_character_skin_ids, skinId)
                            elseif config.dressType == 2 then
                                table.insert(charInfo.own_mecha_skin_ids, skinId)
                            elseif config.dressType == 3 then
                                table.insert(charInfo.own_city_skin_ids, skinId)
                            end
                        end
                    end 
                end
            end
            --判断是角色卡
            if itemInfo.config.itemType == UIUtils.ItemMainType.TempProp then
                if itemInfo.config.subType == UIUtils.ItemTempPropType.CharCard then
                    local charId = tonumber(itemInfo.config.subParam[1] or 0)
                    -- print("--------解锁角色:" .. tostring(charId))
                    if charId > 0 then
                        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId) 
                        if charInfo then
                            local d_char_clothes = require('ClientDatas.d_char_clothes')
                           
                            --遍历所有皮肤卡
                            local skinsInfos = self:GetAllItemByMainType(UIUtils.ItemMainType.Skin)
                            for _, skinInfo in pairs(skinsInfos) do
                                local bCanUse = false
                                print('---skinId:' .. tostring(skinInfo.item_id))
                                if skinInfo.config.subType == UIUtils.ESkinSubType.Char then
                                    local charSkinId = tonumber(skinInfo.config.subParam[1])
                                    local citySkinId = tonumber(skinInfo.config.subParam[2])
                                    if charSkinId and charSkinId > 0 and citySkinId and citySkinId > 0 then
                                        local charSkinConfig = d_char_clothes[charSkinId]
                                        local citySkinConfig = d_char_clothes[citySkinId]
                                        -- print("--------->charSkinConfig.charBelong:" .. tostring(charSkinConfig.charBelong) .. ",citySkinConfig.charBelong:" .. tostring(citySkinConfig.charBelong))
                                        if tonumber(charSkinConfig.charBelong) == tonumber(charId) and tonumber(citySkinConfig.charBelong) == tonumber(charId) then
                                            local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(charSkinConfig.charBelong, 0, charSkinId)
                                            if hasChar and not skinIsUnlock then 
                                                local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(citySkinConfig.charBelong, 2, citySkinId)
                                                if hasChar and not skinIsUnlock then
                                                    bCanUse = true
                                                else
                                                    -- LOG_ERROR('---使用道具失败item_id：' .. tostring(skinInfo.item_id) .. ',主城角色皮肤:' .. tostring(citySkinId) .. ',主城角色:' .. tostring(citySkinConfig.charBelong))
                                                    -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                                end
                                            else
                                                -- LOG_ERROR('---使用道具失败item_id：' .. tostring(skinInfo.item_id) .. ',战斗角色皮肤:' .. tostring(charSkinId) .. ',战斗角色:' .. tostring(charSkinConfig.charBelong))
                                                -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                            end
                                        end
                                    end
                                elseif skinInfo.config.subType == UIUtils.ESkinSubType.Mecha then
                                    local mechaSkinId = tonumber(skinInfo.config.subParam[1])
                                    if mechaSkinId and mechaSkinId > 0 then
                                        local mechaSkinConfig = d_char_clothes[mechaSkinId]
                                        -- print("--------->mechaSkinConfig.charBelong:" .. tostring(mechaSkinConfig.charBelong))
                                        if tonumber(mechaSkinConfig.charBelong) == tonumber(charId) then
                                            local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(mechaSkinConfig.charBelong, 1, mechaSkinId)
                                            if hasChar and not skinIsUnlock then
                                                bCanUse = true
                                            else
                                                -- LOG_ERROR('---使用道具失败item_id：' .. tostring(skinInfo.item_id) .. ',机甲皮肤:' .. tostring(mechaSkinId) .. ',机甲角色:' .. tostring(mechaSkinConfig.charBelong))
                                                -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                            end
                                        end
                                    end
                                end
                                if bCanUse then
                                    self:CachedUseItem(skinInfo, false)
                                    -- LOG_ERROR('---使用道具皮肤卡：' .. tostring(skinInfo.item_id) .. ',count:' .. tostring(skinInfo.count))
                                    local msg = {}
                                    msg.item_uuid = skinInfo.item_uuid
                                    msg.count = skinInfo.count
                                    Client.send("req_use_item", msg)
                                else
                                    --LOG_ERROR('---使用道具失败：' .. tostring(skinInfo.item_id))
                                end
                            end
                        else
                            -->UIUtils.ShowNotify(nil, '-->你已有此角色')
                        end
                    end
                end
            end
            --删除道具
            if itemInfo and itemInfo.count > 0 then
                if itemInfo.item_id and itemInfo.item_id > 0 then
                    self:AddItemCount(itemInfo.item_id, -itemInfo.count)
                end
            end
            MessageManager:GetInstance():Broadcast("OnMsg_Bag_Use_Item_Success", itemInfo)
        end
    end
    table.remove(self.CachedItemData, 1)
end

function BackpackSystem:OnNetCmd_Ntf_Item_Info(result, msgId, parsed_msg)
    -- LOG_INFO("===OnNetCmd_Ntf_Item_Info:" .. tostring(result))
    if parsed_msg then
        -- print("=====>>" .. tostring(table.dump(parsed_msg, false, 10)))
    end
    if result == 0 and
        parsed_msg and 
        parsed_msg.ntf_item_info and 
        parsed_msg.ntf_item_info.changed_item_infos then
        
        local UIUtils = require('_Game.Utils.UIUtils')
        local hasExpChanged = false
        for _, changedItemInfo in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
            local cCount = changedItemInfo.count
            local _itemInfo = self.BagInfo[changedItemInfo.item_id]

            --如果是武器或者装备已装备在身上的不用加到背包里
            local bEquipped = false
            if changedItemInfo.item_extra then
                if changedItemInfo.item_extra == 'weapon_info' then
                    local charInfos = CharacterSystem:GetInstance().CharacterInfo
                    for _, charInfo in ipairs(charInfos) do
                        if charInfo.weapon_info.item_uuid == changedItemInfo.item_uuid then
                            bEquipped = true
                            charInfo.weapon_info.weapon_info = changedItemInfo.weapon_info
                            break
                        end
                    end
                elseif changedItemInfo.item_extra == 'arm_info' then
                    local charInfos = CharacterSystem:GetInstance().CharacterInfo
                    for _, charInfo in ipairs(charInfos) do
                        for _, arm_info in ipairs(charInfo.arm_infos) do
                            if arm_info.item_uuid == changedItemInfo.item_uuid then
                                bEquipped = true
                                arm_info.arm_info = changedItemInfo.arm_info
                                break
                            end
                        end
                    end
                end
            end

            if not bEquipped then
                if _itemInfo then
                    local findItem = false
                    for k, itemInfo in pairs(_itemInfo) do
                        if itemInfo.item_uuid == changedItemInfo.item_uuid then
                            cCount = itemInfo.count + cCount
                            itemInfo.count = cCount
                            if cCount <= 0 then
                                table.remove(self.BagInfo[changedItemInfo.item_id], k)
                            end
                            findItem = true
                            --武器/装备属性改变
                            if cCount >= 1 and changedItemInfo.count == 0 then
                                local newItem = DeepCopy(changedItemInfo)
                                newItem.count = cCount     --默认个数为1
                                self.BagInfo[changedItemInfo.item_id][k] = newItem
                                break
                            end
                        end
                    end
                    --新增加的
                    if not findItem then
                        local newItem = DeepCopy(changedItemInfo)
                        table.insert(self.BagInfo[changedItemInfo.item_id], newItem)
                    end
                else
                    if not self.BagInfo[changedItemInfo.item_id] then
                        self.BagInfo[changedItemInfo.item_id] = {}
                    end
                    local newItem = DeepCopy(changedItemInfo)
                    table.insert(self.BagInfo[changedItemInfo.item_id], newItem)
                end
            end
            if changedItemInfo.item_id == 9004 then
                hasExpChanged = true
            end
            if changedItemInfo.count > 0 then
                local config = UIUtils.GetItemConfigById(changedItemInfo.item_id)
                if config then
                    local d_char_clothes = require('ClientDatas.d_char_clothes')
                    if config.itemType == UIUtils.ItemMainType.TempProp then
                        if config.subType == UIUtils.ItemTempPropType.CharCard then
                            local charId = config.subParam[1] or 0 
                            if charId > 0 then
                                changedItemInfo.config = config
                                local msg = {}
                                msg.item_uuid = changedItemInfo.item_uuid
                                msg.count = changedItemInfo.count
                                BackpackSystem:GetInstance():CachedUseItem(changedItemInfo)
                                Client.send("req_use_item", msg)
                            end
                        end
                    elseif config.itemType == UIUtils.ItemMainType.Skin then
                        local bCanUse = false
                        if config.subType == UIUtils.ESkinSubType.Char then
                            local charSkinId = tonumber(config.subParam[1])
                            local citySkinId = tonumber(config.subParam[2])
                            if charSkinId and charSkinId > 0 and citySkinId and citySkinId > 0 then
                                local charSkinConfig = d_char_clothes[charSkinId]
                                local citySkinConfig = d_char_clothes[citySkinId]
                                local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(charSkinConfig.charBelong, 0, charSkinId)
                                if hasChar and not skinIsUnlock then 
                                    local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(citySkinConfig.charBelong, 2, citySkinId)
                                    if hasChar and not skinIsUnlock then
                                        bCanUse = true
                                    else
                                        -- LOG_ERROR('---使用道具失败item_id：' .. tostring(changedItemInfo.item_id) .. ',主城角色皮肤:' .. tostring(citySkinId) .. ',主城角色:' .. tostring(citySkinConfig.charBelong))
                                        -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                    end
                                else
                                    -- LOG_ERROR('---使用道具失败item_id：' .. tostring(changedItemInfo.item_id) .. ',战斗角色皮肤:' .. tostring(charSkinId) .. ',战斗角色:' .. tostring(charSkinConfig.charBelong))
                                    -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                end
                            end
                        elseif config.subType == UIUtils.ESkinSubType.Mecha then
                            local mechaSkinId = tonumber(config.subParam[1])
                            if mechaSkinId and mechaSkinId > 0 then
                                local mechaSkinConfig = d_char_clothes[mechaSkinId]
                                local hasChar, skinIsUnlock = UIUtils.CharSkinIsUnlock(mechaSkinConfig.charBelong, 1, mechaSkinId)
                                if hasChar and not skinIsUnlock then
                                    bCanUse = true
                                else
                                    -- LOG_ERROR('---使用道具失败item_id：' .. tostring(changedItemInfo.item_id) .. ',机甲皮肤:' .. tostring(mechaSkinId) .. ',机甲角色:' .. tostring(mechaSkinConfig.charBelong))
                                    -- LOG_ERROR('---hasChar:' .. tostring(hasChar) .. ',skinIsUnlock:' .. tostring(skinIsUnlock))
                                end
                            end
                        end
                        if bCanUse then
                            changedItemInfo.config = config
                            self:CachedUseItem(changedItemInfo, false)
    
                            local msg = {}
                            msg.item_uuid = changedItemInfo.item_uuid
                            msg.count = changedItemInfo.count
                            Client.send("req_use_item", msg)
                        else
                            -- LOG_ERROR('---使用道具失败：' .. tostring(changedItemInfo.item_id))
                        end
                        
                    -- elseif config.itemType == UIUtils.ItemMainType.TempProp then
                    --     if config.subType == UIUtils.ItemTempPropType.BluePrint then
                    --         changedItemInfo.config = config
                    --         self:CachedUseItem(changedItemInfo, changedItemInfo.count)
    
                    --         local msg = {}
                    --         msg.item_uuid = changedItemInfo.item_uuid
                    --         msg.count = changedItemInfo.count
                    --         Client.send("req_use_item", msg)
                    --     elseif config.subType == UIUtils.ItemTempPropType.ForgeBP then
                    --         changedItemInfo.config = config
                    --         self:CachedUseItem(changedItemInfo, changedItemInfo.count)
    
                    --         local msg = {}
                    --         msg.item_uuid = changedItemInfo.item_uuid
                    --         msg.count = changedItemInfo.count
                    --         Client.send("req_use_item", msg)
                    --     end
                    end
                end
            end
        end
        --经验值处理
        if hasExpChanged then
            local PlayerSystem = require "Module.Player.PlayerSystem"
            local UIUtils = require('_Game.Utils.UIUtils')
            local oldLevel = PlayerSystem:GetInstance().Level
            local newLevel = UIUtils.GetPlayerLevel()
            PlayerSystem:GetInstance().Level = newLevel

            MessageManager:GetInstance():Broadcast("OnMsg_Player_Exp_Changed")
            if oldLevel < newLevel then
                MessageManager:GetInstance():Broadcast("OnMsg_Player_LevelUp", oldLevel, newLevel)
            end
        end

        MessageManager:GetInstance():Broadcast("OnMsg_Ntf_Item_Info", parsed_msg.ntf_item_info.changed_item_infos)
    end
end

function BackpackSystem:OnNetCmd_Res_Weapon_Level_Up(result, msgId, parsed_msg)
    -- LOG_INFO("===Res_Weapon_Level_Up:" .. tostring(result))
    if parsed_msg then
        -- print("=====>>" .. tostring(table.dump(parsed_msg, false, 10)))
        if self.CachedItemUuid and self.CachedItemUuid > 0 then
            local itemInfo = self:GetItemByUUID(self.CachedItemUuid)
            if itemInfo then --背包武器/装备
                itemInfo.weapon_info.exp = self.CachedItemExp
            else --角色武器/装备
                local charInfos = CharacterSystem:GetInstance().CharacterInfo
                for _, charInfo in ipairs(charInfos) do
                    if charInfo.weapon_info.item_uuid == self.CachedItemUuid then
                        charInfo.weapon_info.weapon_info.exp = self.CachedItemExp
                        break
                    end
                end
            end
            MessageManager:GetInstance():Broadcast("OnMsg_Req_Strengthen_Weapon_Success")
            self.CachedItemUuid = 0
            self.CachedItemExp = 0
        end
    end
end

function BackpackSystem:OnNetCmd_Res_Weapon_Level_Break(result, msgId, parsed_msg)
    -- LOG_INFO("===Res_Weapon_Level_Break:" .. tostring(result))
    if parsed_msg then
        -- print("=====>>" .. tostring(table.dump(parsed_msg, false, 10)))
        if self.CachedItemUuid and self.CachedItemUuid > 0 then
            local itemInfo = self:GetItemByUUID(self.CachedItemUuid)
            if itemInfo then --背包武器/装备
                itemInfo.weapon_info.break_times = self.CachedItemBreakTimes
            else --角色武器/装备
                local charInfos = CharacterSystem:GetInstance().CharacterInfo
                for _, charInfo in ipairs(charInfos) do
                    if charInfo.weapon_info.item_uuid == self.CachedItemUuid then
                        charInfo.weapon_info.weapon_info.break_times = self.CachedItemBreakTimes
                        break
                    end
                end
            end
            MessageManager:GetInstance():Broadcast("OnMsg_Req_Strengthen_Weapon_Success")
            self.CachedItemUuid = 0
            self.CachedItemBreakTimes = 0
        end
    end
end

function BackpackSystem:OnNetCmd_Res_Weapon_Refine(result, msgId, parsed_msg)
    -- LOG_INFO("===Res_Weapon_Refine:" .. tostring(result))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Strengthen_Weapon_Success")
    end
end

function BackpackSystem:OnNetCmd_Res_Arm_Level_Up(result, msgId, parsed_msg)
    -- LOG_INFO("===Res_Equip_Level_Up:" .. tostring(result))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        if self.CachedItemUuid and self.CachedItemUuid > 0 then
            local itemInfo = self:GetItemByUUID(self.CachedItemUuid)
            if itemInfo then --角色武器/装备
                itemInfo.arm_info.exp = self.CachedItemExp
            else --角色武器/装备
                local charInfos = CharacterSystem:GetInstance().CharacterInfo
                for _, charInfo in ipairs(charInfos) do
                    for _, arm_info in ipairs(charInfo.arm_infos) do
                        if arm_info.item_uuid == self.CachedItemUuid then
                            arm_info.arm_info.exp = self.CachedItemExp
                            break
                        end
                    end
                end
            end
            self.CachedItemUuid = 0
            self.CachedItemExp = 0
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Strengthen_Equip_Success")
    end
end

function BackpackSystem:OnNetCmd_Res_Arm_Level_Break(result, msgId, parsed_msg)
    -- LOG_INFO("===Res_Equip_Level_Break:" .. tostring(result))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        if self.CachedItemUuid and self.CachedItemUuid > 0 then
            local itemInfo = self:GetItemByUUID(self.CachedItemUuid)
            if itemInfo then --角色武器/装备
                itemInfo.arm_info.break_times = self.CachedItemBreakTimes
            else --角色武器/装备
                local charInfos = CharacterSystem:GetInstance().CharacterInfo
                for _, charInfo in ipairs(charInfos) do
                    for _, arm_info in ipairs(charInfo.arm_infos) do
                        if arm_info.item_uuid == self.CachedItemUuid then
                            arm_info.arm_info.break_times = self.CachedItemBreakTimes
                            break
                        end
                    end
                end
            end
            self.CachedItemUuid = 0
            self.CachedItemBreakTimes = 0
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Strengthen_Equip_Success")
    end
end

function BackpackSystem:OnNetCmd_Res_Character_Equip_Weapon(result, msgId, parsed_msg)
    -- LOG_INFO("==Res_Character_Equip_Weapon:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.CachedCharacterId)
        local old_weapon_data = charInfo.weapon_info
        charInfo.weapon_info = self.CachedReplaceWeaponOrEquipInfo
        for index, value in ipairs(self.BagInfo[self.CachedReplaceWeaponOrEquipInfo.item_id]) do
            if value.item_uuid == self.CachedReplaceWeaponOrEquipInfo.item_uuid then
                table.remove(self.BagInfo[self.CachedReplaceWeaponOrEquipInfo.item_id], index)
                break
            end
        end
        if not self.BagInfo[old_weapon_data.item_id] then self.BagInfo[old_weapon_data.item_id] = {} end
        table.insert(self.BagInfo[old_weapon_data.item_id], old_weapon_data)
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Swap_Weapon")
    end
end

function BackpackSystem:OnNetCmd_Res_Character_Equip_Arm(result, msgId, parsed_msg)
    -- LOG_INFO("==Res_Character_Equip_Arm:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(parsed_msg.req_data.character_id)
        for _, v in pairs(self.BagInfo) do
            for index, itemInfo in pairs(v) do
                if itemInfo.item_uuid == parsed_msg.req_data.item_uuid then
                    for i, arm_info in ipairs(charInfo.arm_infos) do
                        --装备中的装备放入背包
                        if arm_info.config.subType == itemInfo.config.subType then
                            if not self.BagInfo[arm_info.item_id] then self.BagInfo[arm_info.item_id] = {} end
                            table.insert(self.BagInfo[arm_info.item_id], arm_info)
                            table.remove(charInfo.arm_infos, i)
                            break
                        end
                    end
                    table.insert(charInfo.arm_infos, itemInfo)
                    table.remove(self.BagInfo[itemInfo.item_id], index)
                    break
                    break
                end
            end
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Equip_Arm")
    end
end

function BackpackSystem:OnNetCmd_Res_Character_Unequip_Arm(result, msgId, parsed_msg)
    -- LOG_INFO("==Res_Character_Unequip_Arm:" .. tostring(result) .. ",msg:" .. tostring(table.dump(parsed_msg or {}, false, 10)))
    if result == ErrorCode.ReplaceWeaponResultType.OK then
        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.CachedCharacterId)
        for index, arm_info in pairs(charInfo.arm_infos) do
            if arm_info.item_uuid == parsed_msg.req_data.item_uuid then
                if not self.BagInfo[arm_info.item_id] then self.BagInfo[arm_info.item_id] = {} end
                table.insert(self.BagInfo[arm_info.item_id], arm_info)
                charInfo.arm_infos[index] = nil
                break
            end
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Req_Character_Equip_Arm")
    end
end

function BackpackSystem:OnNetCmd_Res_Item_Synthetic(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        MessageManager:GetInstance():Broadcast("OnMsg_Bag_Get_New_Item")
        MessageManager:GetInstance():Broadcast("OnMsg_Item_Synthetic", self.CachedChangedItemsInfo)
        self.CachedChangedItemsInfo = nil
    end
end

function BackpackSystem:OnNetCmd_Res_Item_Decompose(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        MessageManager:GetInstance():Broadcast("OnMsg_Bag_Get_New_Item")
        MessageManager:GetInstance():Broadcast("OnMsg_Item_Decompose", self.CachedChangedItemsInfo)
        self.CachedChangedItemsInfo = nil
    end
end

function BackpackSystem:OnNetCmd_Res_Arm_Forge(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        MessageManager:GetInstance():Broadcast("OnMsg_Bag_Get_New_Item")
        MessageManager:GetInstance():Broadcast("OnMsg_Item_Forge", self.CachedChangedItemsInfo)
        self.CachedChangedItemsInfo = nil
    end
end

function BackpackSystem:OnNetCmd_Res_Item_Lock(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        local itemInfo = self:GetItemByUUID(parsed_msg.req_data.item_uuid)
        if not itemInfo then
            for _, character_info in ipairs(CharacterSystem:GetInstance().CharacterInfo) do
                if character_info.weapon_info.item_uuid == parsed_msg.req_data.item_uuid then
                    character_info.weapon_info.weapon_info.locked = true
                    MessageManager:GetInstance():Broadcast("OnMsg_Item_Lock")
                    return
                end

                for _, arm_info in ipairs(character_info.arm_infos) do
                    if arm_info.item_uuid == parsed_msg.req_data.item_uuid then
                        arm_info.arm_info.locked = true
                        MessageManager:GetInstance():Broadcast("OnMsg_Item_Unlock")
                        return
                    end
                end
            end
        else
            itemInfo[itemInfo.item_extra].locked = true
            MessageManager:GetInstance():Broadcast("OnMsg_Item_Lock", true)
        end
    end
end

function BackpackSystem:OnNetCmd_Res_Item_Unlock(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        local itemInfo = self:GetItemByUUID(parsed_msg.req_data.item_uuid)
        if not itemInfo then
            for _, character_info in ipairs(CharacterSystem:GetInstance().CharacterInfo) do
                if character_info.weapon_info.item_uuid == parsed_msg.req_data.item_uuid then
                    character_info.weapon_info.weapon_info.locked = false
                    print(character_info.weapon_info.locked)
                    MessageManager:GetInstance():Broadcast("OnMsg_Item_Unlock")
                    return
                end

                for _, arm_info in ipairs(character_info.arm_infos) do
                    if arm_info.item_uuid == parsed_msg.req_data.item_uuid then
                        arm_info.arm_info.locked = false
                        MessageManager:GetInstance():Broadcast("OnMsg_Item_Unlock")
                        return
                    end
                end
            end
        else
            itemInfo[itemInfo.item_extra].locked = false
            MessageManager:GetInstance():Broadcast("OnMsg_Item_Unlock", false)
        end
    end
end

return BackpackSystem
