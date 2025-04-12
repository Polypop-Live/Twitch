
function Instance:onInit()
	local button_img = getEditor():createNewFromFile(self:getObjectKit(), "Static2DTexture", getLocalFolder() .. "EditTwitchStreamInfo_Button.png")
	self:addCast(button_img)
end

function Instance:onRun()

	self.host = getNetwork():getHost("api.twitch.tv")
	if (not self.host.twitch:isUserLoggedIn()) then
		return
	end

	local login = self.host.twitch:getUserInfo().login:lower()
	openWebLink("https://dashboard.twitch.tv/u/" .. login .. "/stream-manager")
end