require "fetch"

Instance.properties = properties({
	{ name="Length", type="Enum", items={"30 seconds", "60 seconds", "90 seconds", "120 seconds", "150 seconds", "180 seconds"}, value="60 seconds" },
})

Instance.countdown = 0

function Instance:onInit()
	local button_img = getEditor():createNewFromFile(self:getObjectKit(), "Static2DTexture", getLocalFolder() .. "StartTwitchCommercial_Button.png")
	self:addCast(button_img)
end

function Instance:onCountdown()

	self.countdown = self.countdown - 1
	if (self.countdown <= 0) then
		getAnimator():stopTimer(self, self.onCountdown)
		print("And we're back...", 323)
	else
		print("Commercial break ending in " .. tostring(self.countdown) .. " seconds", 323)
	end

end

function Instance:onRun()
	
	self.host = getNetwork():getHost("api.twitch.tv")
	if (not self.host.twitch:isUserLoggedIn()) then
		return
	end

	local time_secs = self.properties:find("Length"):getValueIndex() * 30
	local id = self.host.twitch:getUserInfo().id

	fetch(self, self.host, "/helix/channels/commercial", {
		headers = { "Content-Type: application/json" },
		body = json.encode({
			broadcaster_id=id,
			length=time_secs
		})
		
	}):next(jsonify):next(function(obj)

		if (obj["data"]) then
			if (obj["data"][1].length) then
				self.countdown = obj["data"][1].length
				getAnimator():createTimer(self, self.onCountdown, seconds(1), true)
			end
		end

	end):catch(function(resp)

		if (type(resp) == "HTTPRequest") then
			local obj = json.decode(resp:getResponseAsText())
			if (obj and obj.message) then
				print(obj.message)
			end
		end

	end)

end