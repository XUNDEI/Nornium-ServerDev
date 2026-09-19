local pb = require "pb"

local M = {}

M.get_msg_name_by_msg_id = function(msg_id)
    for name, number, _ in pb.fields("ghs.Msg") do
        if number == msg_id then
            return name
        end
    end
    return nil
end

M.get_msg_name_and_field_name = function(cmd)
    for name, number, type in pb.fields("ghs.Msg") do
        local _, basename = pb.type(type)
        if number == cmd then
            return basename, name
        end
    end
    return nil
end

M.get_msg_id_and_msg_name = function(sub_msg_type)
    for name, number, type in pb.fields("ghs.Msg") do
        local _, basename = pb.type(type)
        if basename == sub_msg_type then
            return number, name
        end
    end
    return -1, nil
end

M.get_msg_id_and_msg_type = function(sub_msg_name)
    for name, number, type in pb.fields("ghs.Msg") do
        local _, basename = pb.type(type)
        if name == sub_msg_name then
            return number, basename
        end
    end
    return -1, nil
end

return M