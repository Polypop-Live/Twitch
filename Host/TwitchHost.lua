require "util"
require "fetch"

client_id = "hawpk393w7ctms9j5ex5jie3142yy0"
client_secret = "lol no"
twitch_scope = "chat:read+channel:read:stream_key+user:read:email+channel:read:subscriptions+channel:read:redemptions+channel:manage:redemptions+bits:read+channel:edit:commercial+moderator:read:chatters+moderator:read:followers+moderation:read+channel:read:vips"

Instance.host = nil
Instance.isAuthenticating = false
Instance.access_token = ""
Instance.userinfo = {
	id = 0,
	login = nil,
	broadcaster_type = nil
}
-- Emitted when we have login details
Instance.emitStatusUpdate = event("onStatusUpdate")

function Instance:onInit()
	self.host = getNetwork():getHost("api.twitch.tv")
	self.host:setName("Twitch")
	self.host.twitch = self
	self.host:setRateLimiterMode("TimeWindowWithSteadyState", "Global")
	self.host:setRequiresAuthentication(true)
	self.host:addEventListener("onAuthenticateRequest()", self, self.onAuthenticateRequest)
	self.host:addEventListener("onUnauthorizedRequest()", self, self.onUnauthorizedRequest)
	self.host:addEventListener("onRequestOAuthToken()", self, self.onRequestOAuthToken)
	self.host:addEventListener("onRevokeOAuthToken()", self, self.onRevokeOAuthToken)

	self.id_host = getNetwork():getHost("id.twitch.tv")
	self.id_host:setRateLimiterMode("TimeWindowWithSteadyState", "Global")
	self.id_host:setAsAuthorized(true)

	local cached_scope = self.host:readHostCache("scope", "")
	if (cached_scope == twitch_scope) then
		self.access_token = self.host:readHostCache("access_token", "")
	end
		
	if (self.access_token ~= "") then
		self:setAsAuthorized(true)
	else
		self:setAsAuthorized(false)
	end

	local button_img = getEditor():createNewFromFile(self:getObjectKit(), "Static2DTexture", getLocalFolder() .. "TwitchSignIn.png")
	self:addCast(button_img)

end

function Instance:updateUtilities()

	local utilStreamInfo = self:getObjectKit():findObjectByName("Edit Twitch Stream Info")
	local utilStartCommercial = self:getObjectKit():findObjectByName("Start Twitch Commercial")

	if (self:isUserLoggedIn()) then

		if (not utilStreamInfo) then
			getEditor():createUIX(self:getObjectKit(), "Edit Twitch Stream Info")
		end
		if (not utilStartCommercial and self:getUserInfo().broadcaster_type ~= "") then
			getEditor():createUIX(self:getObjectKit(), "Start Twitch Commercial")
		end
	
	else
		if (not self.isAuthenticating) then
			if (utilStreamInfo) then
				getEditor():removeFromLibrary(utilStreamInfo)
			end
			if (utilStartCommercial) then
				getEditor():removeFromLibrary(utilStartCommercial)
			end
		end
	end

end


function Instance:getUserInfo()
	return self.userinfo
end

function Instance:isUserLoggedIn()
	if (self.userinfo.id == 0) then
		return false
	else
		return true
	end
end

function Instance:setAsAuthorized(bAuthorized)
	self.host:setAsAuthorized(bAuthorized)
	
	if (not bAuthorized) then
		self:_EventSubReset()
		self:_ChatReset()
		self.userinfo.id = 0
		self.userinfo.login = nil
		self:emitStatusUpdate()
		self:updateUtilities()	
	else

		fetch(self, self.host, "/helix/users"):next(jsonify):next(
			function(obj)
				self.userinfo.id = obj["data"][1].id
				self.userinfo.login = obj["data"][1].login
				self.userinfo.broadcaster_type = obj["data"][1].broadcaster_type
				self:emitStatusUpdate()
				self:updateUtilities()	
			end
		)

	end

end

function Instance:onAuthenticateRequest(http)

	if (not self.host:isAuthorized()) then
		http:setAuthenticated(false)
		return
	end
	
--	http:clearRequestHeaders()
	http:addRequestHeader("Client-ID: " .. client_id)
	http:addRequestHeader("Authorization: Bearer " .. self.access_token)
	http:setAuthenticated(true)
end

function Instance:tryRefreshToken()
	
	if (self.isAuthenticating) then
		return
	end

	local refresh_token = self.host:readHostCache("refresh_token", "")
	if (refresh_token) then
		log("[OAuth] Refreshing Token")
		self.isAuthenticating = true

		-- Refresh token
		fetch(self, self.id_host, "/oauth2/token", {
			form = {
				client_id = client_id,
				client_secret = client_secret,
				grant_type = "refresh_token",
				refresh_token = refresh_token
			}
		}):next(jsonify):next(function(obj)
			self:onOAuthToken(obj)
		end)		

	end

	self:setAsAuthorized(false)

end

function Instance:onUnauthorizedRequest()
	self:tryRefreshToken()
end

function Instance:onRequestOAuthToken()

	self.isAuthenticating = true

	local strState = generateGUID()
	local strURL = "https://id.twitch.tv/oauth2/authorize?client_id=" .. client_id .. "&redirect_uri=http://localhost:46500&state=" .. strState .. "&response_type=code&scope=" .. twitch_scope .. "&force_verify=true"

	self.host:enableLoopBackServer(46500, self, self.onLoopBackResponse)
	openWebLink(strURL)

end

function readLocalFile(filename)
	local f = io.open(getLocalFolder() .. filename, "r")
	if (io.type(f)=="file") then
		local data = f:read("*all")
		f:close()
		return data
	end
	return ""
end

function Instance:onLoopBackResponse(target, body)

	local tblTarget = split(target, "?")
	local tblParams = queryStringToTable(tblTarget[2])
	if (type(tblParams["code"]) == "string") then

		fetch(self, self.id_host, "/oauth2/token", {
			form = {
				code = tblParams["code"],
				client_id = client_id,
				client_secret = client_secret,
				redirect_uri = "http://localhost:46500",
				grant_type = "authorization_code"
			}
		}):next(jsonify):next(function(obj)
			self:onOAuthToken(obj, true)
		end):catch(function(obj)
			self:onOAuthToken(nil, true)
		end)

	else
		self:onOAuthToken(nil, true)
	end

end

function Instance:onOAuthToken(obj, close_loopback)

	self.isAuthenticating = false

	if (obj and type(obj["access_token"]) == "string") then

		self.access_token = obj["access_token"]
		self.host:writeHostCache("access_token", self.access_token)
		self.host:writeHostCache("scope", twitch_scope)

		if (type(obj["refresh_token"]) == "string") then
			self.host:writeHostCache("refresh_token", obj["refresh_token"])
		end

		log("[OAuth] Token acquired")
		self:setAsAuthorized(true)

		if (close_loopback) then
			self.host:setLoopBackServerResponse(readLocalFile("success.html"))
			self.host:disableLoopBackServer()
		end

	else
		if (close_loopback) then
			self.host:setLoopBackServerResponse(readLocalFile("error.html"))
			self.host:disableLoopBackServer()
		end
	end

end

function Instance:onRevokeOAuthToken()

	fetch(self, self.id_host, "/oauth2/revoke", {
		body="client_id=" .. client_id .. "&token=" .. self.access_token
	}):next(function(resp)
		log("[OAuth] Token revoked")
	end)

	self:setAsAuthorized(false)
	self.host:deleteHostCache()

end

--------------------------------------------------------------------------------
-- EventSub stuff (replaces PubSub)
--------------------------------------------------------------------------------

Instance.tblEventSubs = {}
Instance.eventSubWebSocket = nil
Instance.eventSubSessionID = nil
Instance.eventSubReconnectURL = nil
Instance.eventSubKeepAliveTime = 0

-- Subscription types to event handlers mapping
function Instance:eventSubListen(subscriptionType, inst, fn)

    -- Skip if already listening
    if self.tblEventSubs[subscriptionType] then
        return
    end

    self.tblEventSubs[subscriptionType] = { inst=inst, fn=fn }

    if not self.eventSubWebSocket then
        self:_EventSubConnect()
    elseif self.eventSubWebSocket:isConnected() and self.eventSubSessionID then
        self:_EventSubSubscribe(subscriptionType)
    end
end

function Instance:eventSubUnlistenAll()
    if self.eventSubWebSocket and self.eventSubWebSocket:isConnected() then
        for subscriptionType, _ in pairs(self.tblEventSubs) do
            -- No need to explicitly unsubscribe since the connection closing will clear all subscriptions
            -- EventSub subscriptions are tied to the session
            log("[EventSub] Unsubscribing from: " .. subscriptionType)
            --self:_EventSubUnsubscribe(subscriptionType)
        end
    end

    self.tblEventSubs = {}
    self:_EventSubReset()
end

function Instance:_EventSubConnect()
    log("[EventSub] Opening WebSocket connection")
    
    local url = "wss://eventsub.wss.twitch.tv/ws"
    -- Use reconnect URL if available during reconnection
    if self.eventSubReconnectURL then
        url = self.eventSubReconnectURL
        log("[EventSub] Using reconnect URL: " .. url)
    end
    
    self.eventSubWebSocket = self.host:openWebSocket(url)
    self.eventSubWebSocket:setAutoReconnect(false)  -- Manual reconnect to handle reconnection URLs
    self.eventSubWebSocket:addEventListener("onConnected", self, self._onEventSubConnected)
    self.eventSubWebSocket:addEventListener("onDisconnected", self, self._onEventSubDisconnected)
    self.eventSubWebSocket:addEventListener("onMessage", self, self._onEventSubMessage)
end

function Instance:_onEventSubConnected()
    log("[EventSub] WebSocket connected")
    -- Wait for the welcome message, which will trigger subscriptions
end

function Instance:_EventSubProcessWelcome(payload)
    self.eventSubSessionID = payload.session.id
    self.eventSubKeepAliveTime = payload.session.keepalive_timeout_seconds
    log("[EventSub] Session established with ID: " .. self.eventSubSessionID)
    log("[EventSub] Keep-alive timeout: " .. self.eventSubKeepAliveTime .. " seconds")
    
    -- Create timer for session monitoring
    self:_EventSubCreateKeepAliveTimer()
    
    -- Subscribe to all topics
    for subscriptionType, _ in pairs(self.tblEventSubs) do
        self:_EventSubSubscribe(subscriptionType)
    end
end

function Instance:_EventSubProcessReconnect(payload)
    self.eventSubReconnectURL = payload.session.reconnect_url
    log("[EventSub] Reconnect URL received: " .. self.eventSubReconnectURL)
end

function Instance:_EventSubProcessNotification(payload)
    local subscriptionType = payload.subscription.type
    log("[EventSub] Received notification for: " .. subscriptionType)
    
    local subInfo = self.tblEventSubs[subscriptionType]
    if subInfo then
        -- Call the registered handler
        subInfo.fn(subInfo.inst, payload.event)
    end
end

function Instance:_EventSubSubscribe(subscriptionType)
    if not self.eventSubSessionID or not self:isUserLoggedIn() then
        log("[EventSub] Cannot subscribe - no session ID or not logged in")
        return
    end
    
    log("[EventSub] Subscribing to: " .. subscriptionType)
    
    local condition = {
        broadcaster_user_id = self.userinfo.id
    }
    
    local subVersion = "1"

    -- Some subscription types need specific condition parameters
    if subscriptionType == "channel.raid" then
        condition = {
            to_broadcaster_user_id = self.userinfo.id
        }
    elseif subscriptionType == "channel.follow" then
        subVersion = "2"
        condition = {
            broadcaster_user_id = self.userinfo.id,
            moderator_user_id = self.userinfo.id
        }
    end
    
    -- Create subscription using EventSub API
    fetch(self, self.host, "/helix/eventsub/subscriptions", {
        method = "POST",
        headers = { "Content-Type: application/json" },
        body = json.encode({
            type = subscriptionType,
            version = subVersion,
            condition = condition,
            transport = {
                method = "websocket",
                session_id = self.eventSubSessionID
            }
        })
    }):next(jsonify):next(function(obj)
        if obj.data and #obj.data > 0 then
            log("[EventSub] Successfully subscribed to: " .. subscriptionType)
            self.tblEventSubs[subscriptionType].id = obj.data[1].id
        else
            log("[EventSub] Failed to subscribe to: " .. subscriptionType)
            if obj.error then
                log("[EventSub] Error: " .. obj.error .. " - " .. obj.message)
            end
        end
    end):catch(function(error)
        log("[EventSub] Subscription error: " .. tostring(error))
    end)
end

function Instance:_EventSubUnsubscribe(subscriptionType)
    if not self.tblEventSubs[subscriptionType].id or not self.eventSubSessionID or not self:isUserLoggedIn() then
        log("[EventSub] Cannot unsubscribe - no session ID or not logged in")
        return
    end
    
    log("[EventSub] Unsubscribing to: " .. subscriptionType)
   
    -- Create subscription using EventSub API
    fetch(self, self.host, "/helix/eventsub/subscriptions?id=" .. self.tblEventSubs[subscriptionType].id, {
        method = "DELETE",
    }):catch(function(error)
        log("[EventSub] Unsubscription error: " .. tostring(error))
    end)

    self.tblEventSubs[subscriptionType].id = nil

end

function Instance:_EventSubCreateKeepAliveTimer()
    -- Set timer to reconnect if we don't receive a keep-alive in time
    local timeout = self.eventSubKeepAliveTime + 10 -- Add buffer
    getAnimator():createTimer(self, self._EventSubKeepAliveTimeout, seconds(timeout))
end

function Instance:_EventSubKeepAliveTimeout()
    log("[EventSub] Keep-alive timeout, reconnecting")
    self:_EventSubReconnect()
end

function Instance:_EventSubReconnect()
    if self.eventSubWebSocket and self.eventSubWebSocket:isConnected() then
        self.eventSubWebSocket:disconnect()
    end
    
    getAnimator():createTimer(self, function()
        self:_EventSubConnect()
    end, seconds(1))
end

function Instance:_onEventSubMessage(msg)
    local obj = json.decode(msg)
    
    if obj.metadata and obj.metadata.message_type then
        local messageType = obj.metadata.message_type
        
        -- Reset keep-alive timer on any message
        getAnimator():stopTimer(self, self._EventSubKeepAliveTimeout)
        
        if messageType == "session_welcome" then
            self:_EventSubProcessWelcome(obj.payload)
        elseif messageType == "session_keepalive" then
            self:_EventSubCreateKeepAliveTimer()
        elseif messageType == "session_reconnect" then
            self:_EventSubProcessReconnect(obj.payload)
            self:_EventSubReconnect()
        elseif messageType == "notification" then
            self:_EventSubProcessNotification(obj.payload)
        elseif messageType == "revocation" then
            log("[EventSub] Subscription revoked: " .. obj.payload.subscription.type)
            -- Could resubscribe here if needed
        end
    end
end

function Instance:_onEventSubDisconnected()
    log("[EventSub] WebSocket disconnected")
    getAnimator():stopTimer(self, self._EventSubKeepAliveTimeout)
    
    -- Attempt to reconnect using the reconnect URL if we have one
    getAnimator():createTimer(self, function()
        self:_EventSubConnect()
    end, seconds(1))
end

function Instance:_EventSubReset()
    if exists(self.eventSubWebSocket) then
        log("[EventSub] Closing WebSocket")
        self.eventSubWebSocket:removeEventListener("onConnected", self, self._onEventSubConnected)
        self.eventSubWebSocket:removeEventListener("onDisconnected", self, self._onEventSubDisconnected)
        self.eventSubWebSocket:removeEventListener("onMessage", self, self._onEventSubMessage)
        self.eventSubWebSocket:disconnect()
        getAnimator():stopTimer(self, self._EventSubKeepAliveTimeout)
    end
    
    self.eventSubWebSocket = nil
    self.eventSubSessionID = nil
    self.tblEventSubs = {}
    -- Keep the reconnect URL in case we need it for reconnections
end

--------------------------------------------------------------------------------
-- Chat stuff
--------------------------------------------------------------------------------

Instance.tblChat = {}
Instance.chatWebSocket = nil
Instance.chatAuthorized = false

function Instance:_ChatConnect()

	log("[Chat] Opening websocket")
	self.chatWebSocket = self.host:openWebSocket("wss://irc-ws.chat.twitch.tv")
	self.chatWebSocket:setAutoReconnect(true)
	self.chatWebSocket:addEventListener("onConnected", self, self._onChatConnected)
	self.chatWebSocket:addEventListener("onDisconnected", self, self._onChatDisconnected)
	self.chatWebSocket:addEventListener("onMessage", self, self._onChatMessage)

end

function Instance:connectToChat(inst, fn)

	if (not self.chatWebSocket) then
		self:_ChatConnect()
	end

	self.tblChat[inst] = fn

end

function Instance:disconnectFromChat(inst)
	self.tblChat[inst] = nil
	if (#self.tblChat == 0) then
		self:_ChatReset()
	end
end

function Instance:_onChatDisconnected()
	log("[Chat] Disconnected")
	self.chatAuthorized = false
	getAnimator():stopTimer(self, self._ChatOnPingServer)
	getAnimator():stopTimer(self, self._ChatOnNoPongResponse)
end

function Instance:_onChatConnected()
	log("[Chat] Websocket connected")
	self.chatWebSocket:send("PASS oauth:" .. self.access_token .. "\r\n")
	self.chatWebSocket:send("NICK " .. self.userinfo.login:lower() .. "\r\n")
end

function Instance:handleChatAuthorization(msg)

	if (msg:find(":tmi.twitch.tv NOTICE * :Login authentication failed", 1, true)) then
		log("[Chat] Authentication failed")
		self:tryRefreshToken()
	elseif (msg:find(":tmi.twitch.tv 001", 1, true)) then
		log("[Chat] Authentication succeeded")
		self.chatWebSocket:send("CAP REQ :twitch.tv/tags\r\n")
		self.chatWebSocket:send("CAP REQ :twitch.tv/commands\r\n")
		self.chatWebSocket:send("JOIN #" .. self.userinfo.login:lower() .. "\r\n")
		self.chatAuthorized = true
		self:_ChatCreatePingServer()
	end

end

function Instance:_ChatCreatePingServer()
	getAnimator():createTimer(self, self._ChatOnPingServer, seconds(60*(4.5+math.random()*0.4)))
end

function Instance:_ChatOnPingServer()
	log("[Chat] Pinging Twitch")
	self.chatWebSocket:send("PING :tmi.twitch.tv\r\n\r\n")
	getAnimator():createTimer(self, self._ChatOnNoPongResponse, seconds(10))
end

function Instance:_ChatOnNoPongResponse()
	log("[Chat] No ping response, reconnecting...")
	self.chatWebSocket:reconnect()	
end

function Instance:handlePONG(msg)
	
	local cmd = ":tmi.twitch.tv PONG"
	if (msg:sub(1, #cmd) == cmd) then
		log("[Chat] Twitch replied with PONG")
		getAnimator():stopTimer(self, self._ChatOnNoPongResponse)
		self:_ChatCreatePingServer()
	end

end

function Instance:handlePING(msg)
    
 	if (msg:sub(1, 4) == "PING") then
		log("[Chat] Responding to Twitch PING")
		self.chatWebSocket:send("PONG" .. msg:sub(5))
        return true
    else
        return false
    end
      
end

function parseBadges(badge_str)

    local tblBadges = {}
	if (badge_str) then
		local badges = split(badge_str, ",")    
		
		for i=1, #badges do
			
			local t = split(badges[i], "/")  
			table.insert(tblBadges, t[1])
			-- Founders are also subscribers
			if (t[1] == "founder") then
				table.insert(tblBadges, "subscriber")
			end

		end
	end
	
    return tblBadges
    
end

function parseTaggedMsg(msg)

	local tblTags = split(msg, ";")

	local tags = {}
    for i=1,#tblTags do
    
        local tag = tblTags[i]    
        local tblTag = split(tag, "=")
        if(tblTag[1]=="badges") then
            tags[tblTag[1]] = parseBadges(tblTag[2])
        else
            tags[tblTag[1]] = tblTag[2]
        end
    end	

	return tags

end

function Instance:handlePRIVMSG(msg)

    local cmd = "PRIVMSG #" .. self.userinfo.login .. " :"
    local i = msg:find(cmd, 1, true)
    if (not i) then
        return false
    end 
    
    local tbl = {}  
    tbl.msg = msg:sub(i+#cmd)

    local iUserStart = msg:find(" :", 1, true)
    local iUserEnd = msg:find("!", iUserStart+2, 1, true)
    tbl.user = msg:sub(iUserStart+2, iUserEnd-1)
	tbl.tags = parseTaggedMsg(msg:sub(1,iUserStart-1))

	-- Dispatch messages
	for k,v in pairs(self.tblChat) do
		v(k, tbl)
	end

    return true
    
end


function Instance:handleUSERNOTICE(msg)

    local cmd = ":tmi.twitch.tv USERNOTICE #" .. self.userinfo.login
    local i = msg:find(cmd, 1, true)
    if (not i) then
        return false
    end 
    
    local tags = msg:sub(1,i-1)
    local tblTags = split(tags, ";")

	local tbl = {}
	tbl.tags = parseTaggedMsg(msg:sub(1,i-1))

	-- Dispatch messages
	for k,v in pairs(self.tblChat) do
		v(k, tbl)
	end

    return true
    
end

function Instance:_onChatMessage(msg)

	if (not self.chatAuthorized) then
		self:handleChatAuthorization(msg)
		return
	end

	if (self:handlePING(msg)) then
		return
	end

	if (self:handlePONG(msg)) then
		return
	end

	if (self:handlePRIVMSG(msg)) then
		return
	end
	
	if (self:handleUSERNOTICE(msg)) then
		return
	end

end

function Instance:_ChatReset()

	if (exists(self.chatWebSocket)) then
		log("[Chat] Closing websocket")
		self.chatWebSocket:removeEventListener("onConnected", self, self._onChatConnected)
		self.chatWebSocket:removeEventListener("onDisconnected", self, self._onChatDisconnected)
		self.chatWebSocket:removeEventListener("onMessage", self, self._onChatMessage)
		self.chatWebSocket:disconnect()
		self:_onChatDisconnected()
	end
	self.tblChat = {}
	self.chatWebSocket = nil

end

