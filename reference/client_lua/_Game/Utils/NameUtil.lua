local NameUtil = {}

NameUtil.d_word_shield = require("ClientDatas.d_word_shield")

function NameUtil.IsValidAccountName(str)
    return string.match(str, "^[A-Za-z0-9_]*$") and true
end

function NameUtil.IsValidPassword(str)
    return string.match(str, [[^[A-Za-z0-9_!@#$%^&*()_+-={}|:;"'<>,.?/\]*$]]) and true
end

-- 这俩提示文本不一样
function NameUtil.AccountLength(str)
    local length = string.len(str)
    return 6 <= length and length <= 20
end

function NameUtil.PasswordLength(str)
    local length = string.len(str)
    return 6 <= length and length <= 20
end

function NameUtil.NoSpace(str)
    return not string.find(str, " ")
end

function NameUtil.NoFilterWord(str)
    for _, word in ipairs(NameUtil.d_word_shield) do
        if string.find(str, word.shield, 1, true) then
            LOG_INFO(word.shield)
            return false
        end
    end
    return true
end

local function get_utf8_ascii_len(s)
    local ascii_count = 0
    local other_count = 0
    for p, c in utf8.codes(s) do
        if c < 128 then
            ascii_count = ascii_count + 1
        else
            other_count = other_count + 1
        end
    end
    return math.ceil(other_count + ascii_count / 2)
end

function NameUtil.LengthLimit(length, str)
    return get_utf8_ascii_len(str) <= length
end

local WORDS = {
    [NameUtil.NoSpace] = 473,
    [NameUtil.NoFilterWord] = 475,
    [NameUtil.LengthLimit] = 474,
    [NameUtil.IsValidAccountName] = 83100008,
    [NameUtil.IsValidPassword] = 473,
    [NameUtil.AccountLength] = 83100009,
    [NameUtil.PasswordLength] = 83100010,
}

function NameUtil.MeetCriteria(str, predictors)
    for _, predictor in ipairs(predictors) do
        local args = ConcatSafePack(SafePack(table.unpack(predictor)), SafePack(str))
        local status, resultOrError = pcall(SafeUnpack(args))
        if not status then
            LOG_ERROR(resultOrError)
        else
            if not resultOrError then
                return false, WORDS[predictor[1]]
            end
        end
    end

    return true
end

return NameUtil
