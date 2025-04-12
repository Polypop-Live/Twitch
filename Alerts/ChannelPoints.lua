
Instance.properties = properties({
	{ name="CustomReward", type="Enum", onUpdate="onCustomRewardUpdate" },
	{ name="RefreshList", type="MetaProperty", onUpdate="onLoginStatusUpdate" },
	{ name="onRedeemed", type="Alert", args={ user_name="[user_name]", profile_url="[profile_url]", user_input="[user_input]", reward_name="[reward_name]" } },
})

function Instance:onCustomRewardUpdate()
	if (self.properties.CustomReward == "") then
		self.name = "Custom Reward"
	else
		self.name = self.properties.CustomReward
	end
end

function Instance:onInit()
	self:getParent():addEventListener("onLoginInStatusUpdate", self, self.onLoginStatusUpdate)
	self:getParent():addEventListener("onCustomRewardsUpdate", self, self.onCustomRewardsUpdate)
	self:onLoginStatusUpdate()
end

function Instance:onLoginStatusUpdate()
	if (self:getParent():isLoggedIn()) then
		self:getParent():updateCustomRewards()
	end
end

function Instance:onCustomRewardsUpdate()
	self.properties:find("CustomReward"):setElements(self:getParent():getCustomRewards())
end

function Instance:onSimulateAlert(alert)
	
	if (alert == self.properties.onRedeemed) then

		local testuser = "testuser" .. tostring(math.random(100,1000))
		print("(Test) User " .. testuser .. " redeemed channel points", 213)
		local test_profile_url = "https://upload.wikimedia.org/wikipedia/commons/e/ed/Ara_macao_-on_a_small_bicycle-8.jpg"
		self.onRedeemed:raise({user_name=testuser, profile_url=test_profile_url, user_input="This is the user's redemption message", reward_name=self.name })
	end

end