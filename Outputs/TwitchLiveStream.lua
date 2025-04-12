require "fetch"
require "../hosts"

Instance.properties = properties({
	{ name="Server", type="Enum" },
	{ name="LiveStream", type="ObjectSet", ui={readonly=true} },
})

Instance.host = nil
Instance.serverURLs = {}

Instance.max_video_bitrate = 6000
Instance.max_audio_bitrate = 160
Instance.keyint = 2
Instance.x264opts = "scenecut=0"

function Instance:onInit(constructor_type)
	
	local button_img = getEditor():createNewFromFile(self:getObjectKit(), "Static2DTexture", getLocalFolder() .. "Twitch_Button.png")
	self:addCast(button_img)

	if (constructor_type == "Default") then
		getEditor():createUIX(self.properties.LiveStream:getKit(), "core-app:Live Stream")
	end

	self.host = getNetwork():getHost(twitch_api)
	self:addCast(self.host)
	self:reqestIngests()

end

function Instance:onPostInit()
	local ls = self.properties.LiveStream:getKit():getObjectByIndex(1)
	ls:setOutput(self)
end

function Instance:reqestIngests()

	local ing_host = getNetwork():getHost("ingest.twitch.tv")
	ing_host:setRateLimiterMode("TimeWindowWithSteadyState", "Global")
	ing_host:setAsAuthorized(true)
	
	self.serverURLs = {}

	fetch(self, ing_host, "/ingests"):next(jsonify):next(function(obj)
	
		local tblInjests = obj["ingests"]

		local tblServers = {}
		table.insert(tblServers, "Auto")
		for i=1,#tblInjests do
			if (tblInjests[i]["availability"]~=0.0) then
				table.insert(tblServers, tblInjests[i]["name"])
				table.insert(self.serverURLs, tblInjests[i]["url_template"])
				if (#self.serverURLs==1) then
					table.insert(self.serverURLs, tblInjests[i]["url_template"])
				end
			end
		end
		self.properties:find("Server"):setElements(tblServers)	
	
	end):catch(function(error)

		local obj = json.decodeFile(getLocalFolder() .. "Servers.json")
		local jServers = obj["servers"]
		
		local tblServers = {}
		for i=1,#jServers do
			table.insert(tblServers, jServers[i]["name"])
			table.insert(self.serverURLs, jServers[i]["url"])
		end
		self.properties:find("Server"):setElements(tblServers)

	end)

end

function toURL(url, stream_key)
	
	if (url == "" or stream_key == "") then
		return nil
	end

	local chars = url:len()
	if (url:find("{stream_key}")) then
		return url:gsub("{stream_key}", stream_key)
	elseif (url:sub(chars, chars)== '/') then
		return url .. stream_key
	else
		return url .. "/" .. stream_key
	end

end

function Instance:requestURL(caller, call_back)

	-- Still awating servers
	if (#self.serverURLs == 0) then
		log("Error: No Twitch servers found")
		call_back(caller, nil)
		return
	end

	local i = self.properties:find("Server"):getValueIndex()
	local url = self.serverURLs[i]

	if (not self.host.twitch:isUserLoggedIn()) then
		log("Error: Not logged in")
		call_back(caller, nil)
		return
	end

	print("Connecting to Twitch...")

	local userinfo = self.host.twitch:getUserInfo()

	-- Query channel name
	self.host.twitch:twitchGetChannelInformation(userinfo.id):next(function(obj)

		local stream_name = obj["data"][1].title
		if (stream_name=="") then
			stream_name = "[Untitled Stream]"
		end

		return stream_name

	end):next(function(stream_name)
	
		-- Query stream key
		self.host.twitch:twitchGetStreamKey(userinfo.id):next(function(obj)
			call_back(caller, toURL(url, obj["data"][1].stream_key), stream_name)
		end)

	end):catch(function()
		call_back(caller, nil)
	end)

end

