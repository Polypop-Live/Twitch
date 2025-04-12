
Instance.properties = properties({
	{ name="Title", type="Text", value="PolyPop Reward", onUpdate="onPropertyUpdate" },
	{ name="Cost", type="Int", range={min=1}, value=1000, onUpdate="onPropertyUpdate" },
	{ name="BackgroundColor", type="Vector4", ui={color=true}, value=rgba(220,12,91), onUpdate="onPropertyUpdate" },
	{ name="Enabled", type="Bool", value=true, onUpdate="onPropertyUpdate" },
	{ name="onRedeemed", type="Alert", args={ user_name="[user_name]", profile_url="[profile_url]", user_input="[user_input]", reward_name="[reward_name]" } },
})

function Instance:onInit(constructor_type)

	if (constructor_type == "Default") then

		-- Find a unique name
		local name = self.properties.Title
		local num = 2
		while self:getParent().properties.AppChannelPoints:getKit():findObjectByName(name) do
			name = self.properties.Title .. " " .. tostring(num)
			num = num + 1
		end
		self.properties.Title = name
	end

	self:setName(self.properties.Title)
	self:getParent():addEventListener("onLoginInStatusUpdate", self, self.onLoginInStatusUpdate)

	self:onLoginInStatusUpdate()
end

function Instance:onLoginInStatusUpdate()

	if (self:getParent():isLoggedIn()) then
		-- Wait a little in case prior sessions haven't quite deleted yet 
		getAnimator():createTimer(self, function(self)
			self:getParent():createAppCustomReward(self, self.properties.Title, self.properties.Cost)
		end, seconds(2))
	end

end

function Instance:setID(id)
	self.id = id
	self:onUpdateTimer()
end

function Instance:onDelete()
	if (self.id and self:getParent()) then
		self:getParent():deleteAppCustomReward(self.id)
	end
end

function Instance:onPropertyUpdate()

	self:setName(self.properties.Title)

	if (not self.id) then
		return
	end

	getAnimator():stopTimer(self, self.onUpdateTimer)
	getAnimator():createTimer(self, self.onUpdateTimer, seconds(0.25))

end

function Instance:onUpdateTimer()

	self:getParent():updateAppCustomReward(self.id, {
		is_enabled = self.properties.Enabled,
		cost = self.properties.Cost,
		title = self.properties.Title,
		background_color = tohex(self.properties.BackgroundColor)
	})

end

function Instance:onSimulateAlert(alert)
	
	if (alert == self.properties.onRedeemed) then

		local testuser = "testuser" .. tostring(math.random(100,1000))
		print("(Test) User " .. testuser .. " redeemed channel points", 213)
		local test_profile_url = "https://upload.wikimedia.org/wikipedia/commons/e/ed/Ara_macao_-on_a_small_bicycle-8.jpg"
		self.onRedeemed:raise({user_name=testuser, profile_url=test_profile_url, user_input="This is the user's redemption message", reward_name=self.properties.Title })
	end

end