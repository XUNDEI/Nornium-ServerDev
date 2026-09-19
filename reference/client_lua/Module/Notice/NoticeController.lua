local PlayerSystem = require("Module.Player.PlayerSystem")
local datetime = require("_Game.Utils.datetime")
local Singleton = require "Framework.Common.Singleton"
---@class NoticeController : Singleton
---@field GetInstance fun():NoticeController
---@field gameInstance BP_GameInstance_C
local NoticeController = BaseClass("NoticeController", Singleton)

function NoticeController:__init()
    self.lastUpdate = 0

    self.banners = {}
end

function NoticeController:SetGameInstance(gameInstance)
    ---@type BP_GameInstance_C
    self.gameInstance = gameInstance
end

local POLL_INTREVAL = 30
function NoticeController:Update(deltaTime)
    local now = PlayerSystem:GetInstance():GetServerTime()

    if now - self.lastUpdate >= POLL_INTREVAL and not self.updating then
        self.updating = true
        self.gameInstance:GMHttpPost("/client/marquee/list", {}, function(res, status, responseString, msg)
            self:UpdateBanner(res, status, responseString, msg)
        end)
    end

    for id, bannerInfo in pairs(self.banners) do
        if bannerInfo.show and bannerInfo.startTime <= now and now < bannerInfo.endTime and now - bannerInfo.lastShowTime >= bannerInfo.interval then
            UIManager:GetInstance():RequestShowBanner(bannerInfo.text)
            bannerInfo.lastShowTime = now
        end
    end
end

function NoticeController:UpdateBanner(res, status, responseString, msg)
    self.lastUpdate = PlayerSystem:GetInstance():GetServerTime()
    self.updating = false

    if not res then
        LOG_INFO("找不到公告")
        return
    elseif msg.code ~= 0 then
        LOG_INFO("公告错误 " .. msg.code)
        return
    end

    if msg.data then
        local ids = {}
        for _, bannerInfo in ipairs(msg.data) do
            local banner = {
                interval = bannerInfo.intervalTime,
                text = bannerInfo.text,
                startTime = datetime.str_to_time(bannerInfo.startAt),
                endTime = datetime.str_to_time(bannerInfo.endAt),
                show = bannerInfo.isUse == "yes",
                lastShowTime = self.banners[bannerInfo.id] and self.banners[bannerInfo.id].lastShowTime or 0,
            }
            self.banners[bannerInfo.id] = banner

            table.insert(ids, bannerInfo.id)
        end

        for k, v in pairs(self.banners) do
            if not table.indexof(ids, k) then
                self.banners[k] = nil
            end
        end
    else
        self.banners = {}
    end
end

return NoticeController
