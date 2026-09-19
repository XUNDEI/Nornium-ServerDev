local Database = require("_Game.Utils.Database")

local GlobalConfig = {
    ExtraSpaceX = Database.Query("d_srpg_global_config", 500000001).values[1],
    ExtraSpaceY = Database.Query("d_srpg_global_config", 500000001).values[2],
    MapItemDistance = Database.Query("d_srpg_global_config", 500000002).values[1],
    RandomOffestX = Database.Query("d_srpg_global_config", 500000003).values[1],
    RandomOffestY = Database.Query("d_srpg_global_config", 500000003).values[2],
    RandomOffestZ = Database.Query("d_srpg_global_config", 500000003).values[3],
    UniverseScale = Database.Query("d_srpg_global_config", 500000004).values[1],
    ScaleMin = Database.Query("d_srpg_global_config", 500000005).values[1] / 100,
    ScaleMax = Database.Query("d_srpg_global_config", 500000005).values[2] / 100,
    DetailThreshold = Database.Query("d_srpg_global_config", 500000006).values[1] / 100,
    ScaleStep = Database.Query("d_srpg_global_config", 500000007).values[1] / 100,
    MapModelScale = 1 / Database.Query("d_srpg_global_config", 500000008).values[1],
    MapShipScale = 1 / Database.Query("d_srpg_global_config", 500000009).values[1],
    MainPosInteractDistance = Database.Query("d_srpg_global_config", 500000021).values[1],
    CardInteractDistance = Database.Query("d_srpg_global_config", 500000022).values[1],
    ExploreOptionInteractDistance = Database.Query("d_srpg_global_config", 500000023).values[1],
    RandomOptionInteractDistance = Database.Query("d_srpg_global_config", 500000024).values[1],
    -- ?????????????????????
    ChangeCharacterBasePrice = Database.Query("d_srpg_global_config", 600000001).values[3],
    ChangeCharacterExtraPrice = Database.Query("d_srpg_global_config", 600000001).values[3],
    SrpgQuitOptions = Database.Query("d_srpg_global_config", 600000013).values,
}

local dynamic_load_lua = function(name)
    local names = string.split(name, ".")
    local save_dir = UE.UBlueprintPathsLibrary.ProjectSavedDir()
    table.insert(names, 1, save_dir)
    local filename = UE.UBlueprintPathsLibrary.Combine(names)..".lua"
    local f = io.open(filename, "rb")
    if not f then
        local status, t = pcall(require, name)
        if not status then
            local err = t
            UnLua.LogError(string.format("failed to load data %s, loader call failed, err is %s", name, err))
            return t
        end
        package.loaded[name] = nil
        return t
    end
    local source = f:read "*a"
    f:close()
    local loader, err = load(source)
    if not loader then
        UnLua.LogError("failed to load data file, loader is nil", name, err)
        return
    end
    local t = loader()
    if not t then
        UnLua.LogError("failed to load data file, return nil", name)
        return
    end
    UnLua.Log("loaded data file", name)

    -- local status, t = pcall(require, name)
    -- if not status then
    --     local err = t
    --     UnLua.LogWarn(string.format("failed to load data %s, loader call failed, err is %s", name, err))
    --     local names = string.split(name, ".")
    --     local save_dir = UE.UBlueprintPathsLibrary.ProjectSavedDir()
    --     table.insert(names, 1, save_dir)
    --     local filename = UE.UBlueprintPathsLibrary.Combine(names)..".lua"
    --     local f = io.open(filename, "rb")
    --     if not f then
    --         return
    --     end
    --     local source = f:read "*a"
    --     f:close()
    --     local loader, err = load(source)
    --     if not loader then
    --         UnLua.LogError("failed to load data file, loader is nil", name, err)
    --         return
    --     end
    --     local t = loader()
    --     if not t then
    --         UnLua.LogError("failed to load data file, return nil", name)
    --         return
    --     end
    --     UnLua.Log("loaded data file", name)
    --     return t
    -- end
    -- package.loaded[name] = nil
    return t
end

local channel_t = dynamic_load_lua("channel")
local channel, port, host, gm_port
if channel_t then
    channel, port, host, gm_port = table.unpack(channel_t)
end
if not channel then
    channel = "develop"
end
if not port then
    port = 8001
end
if not host then
    host = "192.168.0.201"
end
if not gm_port then
    gm_port = 8088
end
-- host = "game1.nornium.com"
-- channel = "cb3"
-- port = 8101
-- gm_port = 8089
GlobalConfig.Channel = channel
GlobalConfig.HOST = host
GlobalConfig.PORT = port
GlobalConfig.GM_HOST = string.format("http://%s:%d", host, gm_port)

local version_t = dynamic_load_lua("version")
local version, version_channel, local_build
if version_t then
    version, version_channel, local_build = table.unpack(version_t)
end
if not version then
    GlobalConfig.UpdateDeploymentName = "PatchingTestLocal"
    GlobalConfig.UpdateDeploymentUrl = "http://127.0.0.1:10081/update/Update"
    version = "1.0.0"
    GlobalConfig.local_build = true
else
    GlobalConfig.UpdateDeploymentName = "PatchingGHSLive"
    GlobalConfig.UpdateDeploymentUrl = "http://nat.syhlgame.cn:10081/update/PatchingGHSCDN/cb4_alpha_3_steam"
    GlobalConfig.local_build = local_build
end
GlobalConfig.Version = version
GlobalConfig.VersionChannel = version_channel

return GlobalConfig
