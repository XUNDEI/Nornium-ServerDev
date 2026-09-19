local Database = {}

local prefix = "ClientDatas."

local proxies = {}

function Database.Query(tableName, key)
    local path = prefix .. tableName

    if not proxies[path] then
        local table = require(path)
        if table then
            proxies[path] = tableex.read_only(table)
        end
    end

    local proxy = proxies[path]

    if not proxy then
        LOG_ERROR(string.format("table %s does not exist!", tableName))
        return nil
    end

    local entry
    if type(key) == "number" then
        entry = proxy[key]
    elseif type(key) == "function" then
        for _, v in pairs(proxy) do
            if key(v) then
                entry = v
            end
        end
    end

    if not entry then
        if type(key) == "number" then
            LOG_WARN(string.format("table %s does not contain key %s!", tableName, key))
        elseif type(key) == "function" then
            LOG_WARN(string.format("table %s does not have entry meet cretia!", tableName))
        end
    end

    return entry
end

function Database.L10n(key)
    if key == 0 then
        return ""
    end
    -- stub 理论上应该根据当前locale查不同的表
    local entry = Database.Query("d_word_cn", key)

    if not entry then
        LOG_WARN_TRACKBACK("key", key, "未被本地化")
    end
    return entry and entry.text or "看到这个说明没本地化"
end

return Database