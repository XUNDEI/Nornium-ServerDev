local M = {}

M.DeploymentName = nil
M.DeploymentUrl = nil
M.PlatformName = nil

M.initialized = false
M.remote_version = nil
M.remote_release_version = nil
M.local_version = nil
M.chunk_mounted = false

M._no_cache_build = false

M.init = function(DeploymentName, DeploymentUrl)
    if M.initialized then return end
    local PlatformName = UE.UGameplayStatics.GetPlatformName()
    UE.UChunkCore.InitChunkCore(PlatformName)
    M.DeploymentName = DeploymentName
    M.DeploymentUrl = DeploymentUrl
    M.PlatformName = PlatformName
    M.initialized = true
end

M.get_local_version = function(DefaultLocalVersion)
    if M.local_version then return M.local_version end
    local result = UE.UChunkCore.LoadCachedBuild(M.DeploymentName)
    if not result then
        M.local_version = DefaultLocalVersion or ""
        M._no_cache_build = true
    else
        M.local_version = UE.UChunkCore.GetContentBuildId()
    end
    return M.local_version
end

M.check_version = function(OnComplete)
    if not M.initialized then
        error("not initialized")
    end
    M.remote_version = nil
    M.remote_release_version = nil
    local origin_url = string.format("%s/Version-%s.txt", M.DeploymentUrl, M.PlatformName)
    M._check_version(OnComplete, origin_url, 0)
end

M._check_version = function(OnComplete, origin_url, try_times)
    local url = origin_url
    if try_times == 0 and url:find("update/PatchingGHSCDN") then
        url = url:gsub("http[s]?://[^/]+", "http://nat.syhlgame.cn:10081")
    else
        url = string.format("%s?r=%d", url, os.time())
    end
    LOG_INFO("check_version url:", url)

    UE.UHTTPRequestClient.SetTimeoutDuration(10)
    UE.UHTTPRequestClient.MakeAHttpRequest(UE.EMethod.GET, url, {}, {}, "", function(_, Status, ResponseString)
        if Status ~= 200 then
            if try_times == 0 then
                M._check_version(OnComplete, origin_url, try_times+1)
            else
                OnComplete(false, ResponseString)
            end
        else
            local s = ResponseString:gsub("%s+$", "")
            local arr = s:split(" ")
            M.remote_version = arr[1]
            M.remote_release_version = arr[2]
            M.partial_size = tonumber(arr[3])
            M.patch_size = tonumber(arr[4])
            LOG_INFO("check_version res:", s)
            LOG_INFO("check_version remote version:", M.remote_version, M.remote_release_version)
            if not M.remote_version or not M.partial_size or not M.patch_size then
                OnComplete(false, ResponseString)
                return
            end
            M._on_check_version(OnComplete, ResponseString)
        end
    end)
end

M.need_update_version = function()
    return true
    -- if M._no_cache_build then
    --     return true
    -- end
    -- return M.local_version ~= M.remote_version
end

M.need_update_chunks = function()
    local total_size = UE.UChunkCore.GetChunksSizeForDownload({0, 1})
    if total_size > 0 then
        return true
    end
    return false
end

M.get_size_for_download = function()
    if M._no_cache_build then
        return M.partial_size + M.patch_size
    end
    local total_size = UE.UChunkCore.GetChunksSizeForDownload({0, 1})
    return total_size
end

M.get_tmp_size = function()
    if M._no_cache_build then
        return 0
    end
    local total_size = UE.UChunkCore.GetChunksTmpSize({0, 1})
    return total_size
end

-- will auto mount chunks after update
M.update_version = function(WorldContextObject, OnComplete)
    if not M.initialized then
        error("not initialized")
    end
    if not M.remote_version then
        error("not check_version")
    end
    M._on_update_build_complete = OnComplete
    local gameInstance = UE.UGameplayStatics.GetGameInstance(WorldContextObject)
    gameInstance:UpdateBuild(M.DeploymentName, M.remote_version, M.remote_release_version)
end

M.mount_chunks = function(gameInstance, OnComplete)
    if not M.initialized then
        error("not initialized")
    end
    if not M.remote_version then
        error("not check_version")
    end
    if M.remote_version ~= M.local_version then
        error("not update_version")
    end
    M._on_mount_chunks_complete = OnComplete
    gameInstance:MountChunks({0, 1})
end

M.get_progress = function()
    return UE.UChunkCore.GetLoadingStats()
end

M.is_chunk_cached = function(chunk_id)
    local chunk_status = UE.UChunkCore.GetChunkStatus(chunk_id)
    return chunk_status == UE.EChunkCoreStatus.Mounted or chunk_status == UE.EChunkCoreStatus.Cached
end

M._on_check_version = function(OnComplete, ResponseString)
    M.local_version = M.get_local_version()
    LOG_INFO("_on_check_version local version:", M.local_version)
    OnComplete(true, ResponseString)
end

M._on_update_build = function(gameInstance, WasSuccessful)
    local OnComplete = M._on_update_build_complete
    if not WasSuccessful then
        OnComplete(false, "UpdateBuild failed")
    else
        M.local_version = M.remote_version
        M._no_cache_build = false
        OnComplete(true)
        -- M._on_mount_chunks_complete = OnComplete
        -- gameInstance:MountChunks({0, 1})
    end
end

M._on_mount_chunks = function(gameInstance, WasSuccessful)
    local OnComplete = M._on_mount_chunks_complete
    LOG_INFO(WasSuccessful)
    if not WasSuccessful then
        OnComplete(false, "MountChunks failed")
    else
        M.chunk_mounted = true
        OnComplete(true)
    end
end

return M