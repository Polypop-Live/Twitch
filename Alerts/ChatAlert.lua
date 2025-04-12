
Instance.properties = properties({
	{ name="Command", type="Text", value="!my_keyword", onUpdate="onCommandUpdate" },
	{ name="Privilege", type="Enum", items={"anyone", "moderator", "founder", "subscriber", "vip", "admin", "broadcaster", "specific user"}, onUpdate="onPrivilegeUpdate" },
	{ name="User", type="Text", ui={dynamic_text=true} },
	{ name="onCommand", type="Alert", args={ user_name="[user_name]", profile_url="[profile_url]", msg="[msg]" } }
})

function Instance:onCommandUpdate()
	self.name = self.properties.Command
end

function Instance:onInit()
	self:onCommandUpdate()
	self:onPrivilegeUpdate()
end

function Instance:onPrivilegeUpdate()

	if (self.properties.Privilege == "specific user") then
		getUI():setUIProperty({{obj=self.properties:find("User"), visible=true}})
	else
		getUI():setUIProperty({{obj=self.properties:find("User"), visible=false}})
	end

end

function Instance:onSimulateAlert(alert)
	
	if (alert == self.properties.onCommand) then

		local testuser = "testuser" .. tostring(math.random(100,1000))
		print("(Test) User " .. testuser .. " wrote \"" .. self.properties.Command .. "\" into the chat", 213)
		local test_profile_url = "https://upload.wikimedia.org/wikipedia/commons/e/ed/Ara_macao_-on_a_small_bicycle-8.jpg"
		self.onCommand:raise({user_name=testuser, profile_url=test_profile_url, msg="This is the message that follows the command" })
	end

end