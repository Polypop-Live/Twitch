
Instance.properties = properties({
	{ name="Threshold", type="Int", range={min=1}, units="bits", value=500, onUpdate="onThresholdUpdate" },
	{ name="onCheer", type="Alert", args={ user_name="[user_name]", profile_url="[profile_url]", chat_message="[chat_message]", bits_used=0 } }
})

function Instance:onThresholdUpdate()
	self.name = "Cheer Alert (" .. tostring(self.properties.Threshold) .. ")"
end

function Instance:onInit()
	self:onThresholdUpdate()
end

function Instance:onSimulateAlert(alert)
	
	if (alert == self.properties.onCheer) then

		local testuser = "testuser" .. tostring(math.random(100,1000))
		local min = self.Threshold - 100
		if (min<1) then
			min = 1
		end
		local testBits = math.random(min,self.Threshold+1000)
		print("(Test) User " .. testuser .. " cheered " .. tostring(testBits) .. " bits", 213)
		if (testBits > self.Threshold) then
			local test_profile_url = "https://upload.wikimedia.org/wikipedia/commons/e/ed/Ara_macao_-on_a_small_bicycle-8.jpg"
			self.onCheer:raise({user_name=testuser, profile_url=test_profile_url, chat_message="This is the user's chat message", bits_used=testBits })
		end
	end

end