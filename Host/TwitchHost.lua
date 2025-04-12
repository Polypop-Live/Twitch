require "util"
require "fetch"
require "../hosts"

public_client_id = "hawpk393w7ctms9j5ex5jie3142yy0"
twitch_scope_tbl = {
	"channel:read:stream_key",
	"user:read:email",
	"channel:read:subscriptions",
	"channel:read:redemptions",
	"channel:manage:redemptions",
	"bits:read",
	"channel:edit:commercial",
	"moderator:read:chatters",
	"moderator:read:followers",
	"moderation:read",
	"channel:read:vips"
}
if (twitch_id:sub(1, 9) ~= "localhost" and twitch_id:sub(1, 9) ~= "127.0.0.1") then
	twitch_scope_tbl[#twitch_scope_tbl] = "chat:read"
	twitch_scope_tbl[#twitch_scope_tbl] = "user:read:chat"
end
table.sort(twitch_scope_tbl)
twitch_scope = table.concat(twitch_scope_tbl, " ")

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

-- Move to fetch later?
function table_to_query(table)
	query = ""
	for k, v in pairs(table) do
		query = query .. "&" .. encodeURIComponent(k) .. "=" .. encodeURIComponent(v)
	end
	return query:sub(2)
end

function Instance:onInit()
	log("[Debug] Init to " .. twitch_api)
	self.host = getNetwork():getHost(twitch_api)
	self.host:setName("Twitch")
	self.host.twitch = self
	self.es_host = getNetwork():getHost(twitch_api_es)
	for _, host in ipairs({self.host, self.es_host}) do
		host:setRateLimiterMode("TimeWindowWithSteadyState", "Global")
		host:setRequiresAuthentication(true)
		host:addEventListener("onAuthenticateRequest()", self, self.onAuthenticateRequest)
		host:addEventListener("onUnauthorizedRequest()", self, self.onUnauthorizedRequest)
		host:addEventListener("onRequestOAuthToken()", self, self.onRequestOAuthToken)
		host:addEventListener("onRevokeOAuthToken()", self, self.onRevokeOAuthToken)
	end

	self.id_host = getNetwork():getHost(twitch_id)
	self.id_host:setRateLimiterMode("TimeWindowWithSteadyState", "Global")
	self.id_host:setAsAuthorized(true)

	local cached_scope = self.host:readHostCache("scope", "")
	if (cached_scope == twitch_scope) then
		self.access_token = self.host:readHostCache("access_token", "")
	end

	if (self.access_token ~= "") then
		-- Sync these for localhost
		self.es_host:writeHostCache("access_token", self.access_token)
		self:setAsAuthorized(true)
	else
		self:setAsAuthorized(false)
	end

	local button_img = getEditor():createNewFromFile(self:getObjectKit(), "Static2DTexture", getLocalFolder() .. "TwitchSignIn.png")
	self:addCast(button_img)

end


------------ Twitch API
-- Helpers
function encodeURIComponent(s, spaceChar)
	if type(s) == "string" then
		return s:gsub("([^%w_.!~*'()-])", function (c)
			if spaceChar and c == " " then return spaceChar end
			return string.format("%%%02X", string.byte(c))
		end)
	end
	return tostring(s)
end

function decodeURI(s)
	if type(s) == "string" then
		return s:gsub("%%(%x%x)", function (x)
			return string.char(tonumber(x, 16))
		end)
	end
	return tostring(s)
end

function Instance:isLocalHost(host)
	local hostname = host:getHostName()
	local name_only = hostname:gsub(":.*", "")
	return name_only == "localhost" or name_only == "127.0.0.1"
end

function getURL(host, publicPathPrefix, localPathPrefix)
	local hostname = host:getHostName()
	local name_only = hostname:gsub(":.*", "")
	if name_only == "localhost" or name_only == "127.0.0.1" then
		return "http://" .. hostname .. localPathPrefix
	end
	return "https://" .. hostname .. publicPathPrefix
end

function extractQueryTable(tbl, ...)
	local queryTbl = {}
	local contains = {}
	for i, k in ipairs({...}) do contains[k] = true end
	for k, v in pairs(tbl) do
		if contains[k] then
			tbl[k] = nil
			k = encodeURIComponent(k)
			if type(v) == "table" then
				local value = ""
				for _, x in ipairs(v) do
					value = value .. "&" .. k .. "=" .. encodeURIComponent(x)
				end
				queryTbl[k] = value:sub(3 + #k)
			else
				queryTbl[k] = encodeURIComponent(v)
			end
		end
	end
	return queryTbl
end

function merge(tbl, key, subTable)
	if type(tbl[key]) == "table" then
		for k, v in pairs(subTable) do
			if type(k) == "number" then
				tbl[#tbl] = v
			else
				tbl[key][k] = v
			end
		end
	else
		tbl[key] = subTable
	end
end

-- Auth
function Instance:twitchImplicitGrant(owner, handler)
	log("[OAuth] Implicit grant login flow initiated")
	if self:isLocalHost(self.id_host) then
		return throw("Can't use implicit flow on local mock")
	end

	local client_id = self.host:readHostCache("client_id", public_client_id)
	local strState = generateGUID()
	local strURL = getURL(self.id_host, "/oauth2", "/auth") .. "/authorize?" .. table_to_query({
		client_id = client_id,
		force_verify = true,
		redirect_uri = "http://localhost:46500",
		response_type = "token",
		scope = twitch_scope,
		state = strState
	})
	self.host:enableLoopBackServer(46500, owner, function(owner, target, body)
		-- Fetch the hash by forwarding it in the query
		self.host:setLoopBackServerResponse(readLocalFile("hash.html"))
		self.host:disableLoopBackServer()
		self.host:enableLoopBackServer(46500, owner, function(owner, target, body)
			local qpos = target:find("?")
			handler(owner, queryStringToTable(target:sub(qpos + 1)))
		end)
	end)
	openWebLink(strURL)
end

function Instance:twitchAuthorizationCode(owner, handler)
	log("[OAuth] Authorization code login flow initiated")
	local client_id = self.host:readHostCache("client_id", public_client_id)
	local url = getURL(self.id_host, "/oauth2", "/auth") .. "/authorize"
	if self:isLocalHost(self.id_host) then
		log("[OAuth] localhost path")
		local user_id = self.host:readHostCache("user_id", "")
		if user_id == "" then
			return throw("user_id required to for authorization on local mock")
		end

		local client_secret = self.host:readHostCache("client_secret", "")
		if client_secret == "" then
			return throw("client_secret required to for authorization on local mock")
		end

		fetch(self, self.id_host, {
			url = url,
			method = "POST",
			query = {
				client_id = client_id,
				client_secret = client_secret,
				grant_type = "user_token",
				user_id = user_id,
				scope = encodeURIComponent(twitch_scope)
			}
		}):next(jsonify):next(function(obj)
			handler(owner, obj)
		end)
	else
		local strState = generateGUID()
		local strURL = url .. "?" .. table_to_query({
			client_id = client_id,
			force_verify = true,
			redirect_uri = "http://localhost:46500",
			response_type = "code",
			scope = twitch_scope,
			state = strState
		})
		self.host:enableLoopBackServer(46500, owner, function(owner, target, body)
			local qpos = target:find("?")
			handler(owner, queryStringToTable(target:sub(qpos + 1)))
		end)
		openWebLink(strURL)
	end
end

function Instance:twitchExchangeCode(code)
	log("[OAuth] Exhanging auth code for user token")
	local client_id = self.host:readHostCache("client_id", public_client_id)
	local client_secret = self.host:readHostCache("client_secret", "")
	return fetch(self, self.id_host, "/oauth2/token", {
		form = {
			code = code,
			client_id = client_id,
			client_secret = client_secret,
			redirect_uri = "http://localhost:46500",
			grant_type = "authorization_code"
		}
	}):next(jsonify)
end

function Instance:twitchRefreshToken(refresh_token)
	if self:isLocalHost(self.id_host) then
		return throw("Can't refresh on local mock")
	end

	local client_id = self.host:readHostCache("client_id", public_client_id)
	local client_secret = self.host:readHostCache("client_secret", "")
	if client_secret == "" then
		return throw("client_secret required to refresh")
	end

	return fetch(self, self.id_host, "/oauth2/token", {
		form = {
			client_id = client_id,
			client_secret = client_secret,
			grant_type = "refresh_token",
			refresh_token = refresh_token
		}
	}):next(jsonify)
end

function Instance:twitchRevokeToken()
	if self:isLocalHost(self.id_host) then
		return throw("Can't revoke on local mock")
	end

	local client_id = self.host:readHostCache("client_id", public_client_id)
	fetch(self, self.id_host, "/oauth2/revoke", {
		body="client_id=" .. client_id .. "&token=" .. self.access_token
	}):next(function(resp)
		log("[OAuth] Token revoked")
	end)

	self:setAsAuthorized(false)
	self.host:deleteHostCache()
	self.es_host:deleteHostCache()
end


-- API in order from https://dev.twitch.tv/docs/api/reference/
function Instance:twitchGetBitsLeaderboard(params)
	-- https://dev.twitch.tv/docs/api/reference/#get-bits-leaderboard
	params = params or {}
	params.query = extractQueryTable(params, "count", "period", "started_at", "user_id")
	params.url = getURL(self.host, "/helix", "/mock") .. "/bits/leaderboard"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchGetChannelInformation(broadcaster_id)
	-- https://dev.twitch.tv/docs/api/reference/#get-channel-information
	return fetch(self, self.host, {
		url = getURL(self.host, "/helix", "/mock") .. "/channels",
		query = { broadcaster_id = broadcaster_id }
	}):next(jsonify)
end

function Instance:twitchGetChannelFollowers(broadcaster_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-channel-followers
	params = params or {}
	params.query = extractQueryTable(params, "user_id", "first", "after")
	params.query.broadcaster_id = broadcaster_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/channels/followers"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchCreateCustomReward(broadcaster_id, body)
	-- https://dev.twitch.tv/docs/api/reference/#create-custom-reward
	return fetch(self, self.host, {
		method = "POST",
		url = getURL(self.host, "/helix", "/mock") .. "/channel_points/custom_rewards",
		query = { broadcaster_id = broadcaster_id },
		headers = {"Content-Type: application/json"},
		body = json.encode(body)
	}):next(jsonify)
end

function Instance:twitchGetCustomReward(broadcaster_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-custom-reward
	params = params or {}
	params.query = extractQueryTable(params, "id", "only_manageable_rewards")
	params.query.broadcaster_id = broadcaster_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/channel_points/custom_rewards"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchUpdateCustomReward(broadcaster_id, id, body)
	-- https://dev.twitch.tv/docs/api/reference/#update-custom-reward
	return fetch(self, self.host, {
		method = "PATCH",
		url = getURL(self.host, "/helix", "/mock") .. "/channel_points/custom_rewards",
		query = { broadcaster_id = broadcaster_id, id = id },
		headers = {"Content-Type: application/json"},
		body = json.encode(body)
	}):next(jsonify)
end

function Instance:twitchDeleteCustomReward(broadcaster_id, id)
	-- https://dev.twitch.tv/docs/api/reference/#delete-custom-reward
	return fetch(self, self.host, {
		method = "DELETE",
		url = getURL(self.host, "/helix", "/mock") .. "/channel_points/custom_rewards",
		query = { broadcaster_id = broadcaster_id, id = id },
	})
end

function Instance:twitchGetChatters(broadcaster_id, moderator_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-chatters
	params = params or {}
	params.query = extractQueryTable(params, "first", "after")
	params.query.broadcaster_id = broadcaster_id
	params.query.moderator_id = moderator_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/chat/chatters"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchCreateEventSubSubscription(body)
	-- https://dev.twitch.tv/docs/api/reference/#create-eventsub-subscription
	return fetch(self, self.es_host, {
		method = "POST",
		url = getURL(self.es_host, "/helix", "") .. "/eventsub/subscriptions",
		query = { broadcaster_id = broadcaster_id },
		headers = {"Content-Type: application/json"},
		body = json.encode(body)
	}):next(jsonify)
end

function Instance:twitchDeleteEventSubSubscription(id)
	-- https://dev.twitch.tv/docs/api/reference/#delete-eventsub-subscription
	return fetch(self, self.es_host, {
		method = "DELETE",
		url = getURL(self.es_host, "/helix", "") .. "/eventsub/subscriptions",
		query = { id = id },
	})
end

function Instance:twitchGetEventSubSubscriptions(params)
	-- https://dev.twitch.tv/docs/api/reference/#get-eventsub-subscriptions
	params = params or {}
	params.query = extractQueryTable(params, "status", "type", "user_id", "after")
	params.url = getURL(self.es_host, "/helix", "") .. "/eventsub/subscriptions"
	merge(params, "headers", {"Content-Type: application/json"})
	return fetch(self, self.es_host, params):next(jsonify)
end

function Instance:twitchGetModerators(broadcaster_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-moderators
	params = params or {}
	params.query = extractQueryTable(params, "user_id", "first", "after")
	params.query.broadcaster_id = broadcaster_id
	params.query.moderator_id = moderator_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/moderation/moderators"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchGetVIPs(broadcaster_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-vips
	params = params or {}
	params.query = extractQueryTable(params, "user_id", "first", "after")
	params.query.broadcaster_id = broadcaster_id
	params.query.moderator_id = moderator_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/channels/vips"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchStartRaid(from_broadcaster_id, to_broadcaster_id)
	-- https://dev.twitch.tv/docs/api/reference/#start-a-raid
	return fetch(self, self.host, {
		method = "POST",
		url = getURL(self.host, "/helix", "/mock") .. "/raids",
		query = {
			from_broadcaster_id = from_broadcaster_id,
			to_broadcaster_id = to_broadcaster_id
		},
		headers = {"Content-Type: application/json"},
		body = json.encode(body)
	}):next(jsonify)
end

function Instance:twitchCancelRaid(broadcaster_id)
	-- https://dev.twitch.tv/docs/api/reference/#cancel-a-raid
	return fetch(self, self.host, {
		method = "DELETE",
		url = getURL(self.host, "/helix", "/mock") .. "/raids",
		query = {
			broadcaster_id = broadcaster_id
		},
		headers = {"Content-Type: application/json"},
		body = json.encode(body)
	}):next(jsonify)
end

function Instance:twitchGetStreamKey(broadcaster_id)
	-- https://dev.twitch.tv/docs/api/reference/#get-stream-key
	return fetch(self, self.host, {
		url = getURL(self.host, "/helix", "/mock") .. "/streams/key",
		query = { broadcaster_id = broadcaster_id }
	}):next(jsonify)
end

function Instance:twitchGetBroadcasterSubscriptions(broadcaster_id, params)
	-- https://dev.twitch.tv/docs/api/reference/#get-broadcaster-subscriptions
	params = params or {}
	params.query = extractQueryTable(params, "user_id", "first", "after", "before")
	params.query.broadcaster_id = broadcaster_id
	params.url = getURL(self.host, "/helix", "/mock") .. "/subscriptions"
	return fetch(self, self.host, params):next(jsonify)
end

function Instance:twitchGetUsers(params)
	-- https://dev.twitch.tv/docs/api/reference/#get-users
	params = params or {}
	params.query = extractQueryTable(params, "id", "login")
	params.url = getURL(self.host, "/helix", "/mock") .. "/users"
	return fetch(self, self.host, params):next(jsonify)
end


-- Main instance code

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
	log("[Debug] setAsAuthorized(" .. tostring(bAuthorized) .. ")")
	self.host:setAsAuthorized(bAuthorized)
	self.es_host:setAsAuthorized(bAuthorized)

	if (not bAuthorized) then
		self:_EventSubReset()
		self.userinfo.id = 0
		self.userinfo.login = nil
		self:emitStatusUpdate()
		self:updateUtilities()
	else

		self:twitchGetUsers():next(
			function(obj)
				self.userinfo.id = obj.data[1].id
				self.userinfo.login = obj.data[1].login
				self.userinfo.broadcaster_type = obj.data[1].broadcaster_type
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

	log("[Debug] onAuthenticateRequest")
--	http:clearRequestHeaders()
	local client_id = self.host:readHostCache("client_id", public_client_id)
	http:addRequestHeader("Client-ID: " .. client_id)
	http:addRequestHeader("Authorization: Bearer " .. self.access_token)
	http:setAuthenticated(true)
end


function Instance:tryRefreshToken()

	if (self.isAuthenticating or self:isLocalHost(self.host)) then
		return
	end

	local refresh_token = self.host:readHostCache("refresh_token", "")
	if (refresh_token ~= "") then
		log("[OAuth] Refreshing Token")
		self.isAuthenticating = true

		-- Refresh token
		self:twitchRefreshToken(refresh_token):next(function(obj)
			self:onOAuthToken(obj)
		end)

	end

	self:setAsAuthorized(false)

end

function Instance:onUnauthorizedRequest()
	self:tryRefreshToken()
end

function Instance:onRequestOAuthToken()

	if (self.isAuthenticating) then
		return
	end

	self.isAuthenticating = true

	local client_secret = self.host:readHostCache("client_secret", "")
	if (client_secret == "") then
		self:twitchImplicitGrant(self, self.onLoopBackResponse)
	else
		self:twitchAuthorizationCode(self, self.onLoopBackResponse)
	end

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

function Instance:onLoopBackResponse(tblParams)

	if (type(tblParams["code"]) == "string") then

		self:twitchExchangeCode(tblParams["code"]):next(function(obj)
			self:onOAuthToken(obj, true)
		end):catch(function(obj)
			self:onOAuthToken(nil, true)
		end)

	else
		self:onOAuthToken(tblParams, true)
	end

end

function Instance:onOAuthToken(obj, close_loopback)

	self.isAuthenticating = false

	if (obj and type(obj.access_token) == "string") then

		self.access_token = obj.access_token
		self.host:writeHostCache("access_token", self.access_token)
		self.es_host:writeHostCache("access_token", self.access_token)

		local scope
		if not obj.scope then
			-- Not a good case
			scope = twitch_scope
		else
			if (type(obj.scope) == "string") then
				scope = split(obj.scope:gsub("%%3A", ":"), "+")
			else
				scope = obj.scope
			end
			table.sort(scope)
			scope = table.concat(scope, " ")
		end
		self.host:writeHostCache("scope", scope)

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

	self:twitchRevokeToken():next(function(resp)
		log("[OAuth] Token revoked")
	end)

	self:setAsAuthorized(false)
	local keep = {
		client_id = self.host:readHostCache("client_id", ""),
		client_secret = self.host:readHostCache("client_secret", ""),
		user_id = self.host:readHostCache("user_id", ""),
	}
	self.host:deleteHostCache()
	self.es_host:deleteHostCache()
	for k, v in pairs(keep) do
		if v ~= "" then
			self.host:writeHostCache(k, v)
		end
	end
end

--------------------------------------------------------------------------------
-- EventSub stuff
--------------------------------------------------------------------------------

Instance.tblEventSubListen = {}
Instance.eventSubWebSocket = nil

function Instance:eventSubListen(topic, version, condition, inst, fn)
	-- Gets list of current subscriptions
	--[[
	self:twitchGetEventSubSubscriptions():next(function (obj)
		log("[EventSub] Parse this list for an existing session id: " .. json.encode(obj))
	end)
	-- Twitch Discord says it isn't necessary to manually remove disconnected sessions
	]]

	if (self.tblEventSubListen[topic]) then
		return
	end

	if (type(condition) ~= "table") then
		-- Presume it's just a user_id
		condition = { broadcaster_user_id = tostring(condition) }
	end
	self.tblEventSubListen[topic] = {
		version = tostring(version),
		condition = condition,
		inst = inst,
		fn = fn
	}

	if (not self.eventSubWebSocket) then
		log("[EventSub] Connecting")
		-- Connect on first listen
		self:_EventSubConnect()
	end

end

function Instance:eventSubUnsubAll()

	if (self.eventSubWebSocket and self.eventSubWebSocket:isConnected()) then
		for k, v in pairs(self.tblEventSubListen) do
			if (v.id) then
				self:twitchDeleteEventSubSubscription(v.id)
				self.tblEventSubListen[k] = nil
			end
		end
	end

	self:_EventSubReset()

end


function Instance:_EventSubConnect(reconnect_url)
	log("[EventSub] Opening websocket")
	self.eventSubWebSocket = self.es_host:openWebSocket(reconnect_url or twitch_es)
	self.eventSubWebSocket:setAutoReconnect(true)
	self.eventSubWebSocket:addEventListener("onConnected", self, self._EventSubConnected)
	self.eventSubWebSocket:addEventListener("onDisconnected", self, self._onEventSubDisconnected)
	self.eventSubWebSocket:addEventListener("onMessage", self, self._EventSubMessage)
end

function Instance:_EventSubConnected()

	log("[EventSub] Websocket connected")

	--  log("[EventSub] We need to handle the response here.")
	if (self.eventSubSessionId) then
		log("[EventSub] Session ID: ".. self.eventSubSessionId)
	else
		log("[EventSub] Session ID not yet available.")
	end

end

function Instance:_EventSubRestartWatchDogTimer()
	getAnimator():createTimer(self, self._EventSubReconnect, seconds(self._esKeepaliveTimeoutSeconds+1))
end

function Instance:_EventSubReconnect()
	log("[EventSub] Attempting to reconnect")
	self.eventSubWebSocket:reconnect()
end

function Instance:_EventSubMessage(msg)

	getAnimator():stopTimer(self, self._EventSubReconnect)

	local obj, decodeError = json.decode(msg)

	if obj then

		if obj.metadata.message_type == "session_welcome" then
			log("[EventSub] Session welcome received")
			-- If we were forcibly reconnected, drop the previous connection
			if (self.reconnecting) then
				self:_EventSubReset(self.reconnecting)
			end

			-- Access the session ID from the payload
			self.eventSubSessionId = obj.payload.session.id
			self._esKeepaliveTimeoutSeconds = obj.payload.session.keepalive_timeout_seconds

			if (not self.reconnecting) then
				log("[EventSub] creating subscriptions for ".. self.eventSubSessionId)
				for k, v in pairs(self.tblEventSubListen) do
					self:twitchCreateEventSubSubscription({
						type = k,
						version = v.version,
						condition = v.condition,
						transport = {
							method = "websocket",
							session_id=self.eventSubSessionId
						}
					})
				end
			end
			self.reconnecting = nil
		elseif obj.metadata.message_type == "notification" then
			log("[EventSub] Notification received")
			log("[EventSub] Notification payload: ".. json.encode(obj.payload))

			local elem = self.tblEventSubListen[obj.payload.subscription.type]

			if (elem) then
				-- log("[EventSub] Calling Alert Function with payload: ".. json.encode(obj.payload.event))
				elem.fn(elem.inst, obj.payload.event)
			end
		elseif obj.metadata.message_type == "reconnect" then
			log("[EventSub] Reconnect received")
			self.reconnecting = self.eventSubWebSocket
			self._EventSubConnect(obj.payload.session.reconnect_url)
		else
			-- log("[EventSub] Message type is not a welcome: " .. obj.metadata.message_type)
		end
	else
		log("[EventSub] Error decoding message: " .. decodeError)
	end

	self:_EventSubRestartWatchDogTimer()

end

function Instance:_onEventSubDisconnected()
	getAnimator():stopTimer(self, self._EventSubReconnect)
end

function Instance:_EventSubReset(old_socket)
	socket = old_socket or self.eventSubWebSocket
	if (socket) then
		log("[EventSub] Closing EventSub websocket")
		self.eventSubWebSocket:removeEventListener("onConnected", self, self._EventSubConnected)
		self.eventSubWebSocket:removeEventListener("onDisconnected", self, self._onEventSubDisconnected)
		self.eventSubWebSocket:removeEventListener("onMessage", self, self._EventSubMessage)
		self.eventSubWebSocket:disconnect()
		self:_onEventSubDisconnected()
	end
	self.tblEventSubListen = {}
	self.eventSubWebSocket = nil

end
