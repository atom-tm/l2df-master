--- Master server and NAT Facilitator
-- TODO: optimize the structure for clients (dequeue)
-- @author Abelidze
-- @copyright Atom-TM 2020

local md5 = require 'md5'
local enet = require 'enet'
local Lobby = require 'lobby'

local tostring = _G.tostring
local unpack = table.unpack or unpack
local max = math.max
local ceil = math.ceil
local strchar = string.char
local strbyte = string.byte
local strjoin = table.concat
local strmatch = string.match
local strgmatch = string.gmatch
local strformat = string.format
local mdsum = md5.sumhexa

-- Client message codes
local LOGIN = 1
local LIST = 2
local FIND = 3
local RELAY = 4
local LEAVE = 5
local INVITE = 7

local relayid = { }
local clients = { count = 0 }
local users = { }

local SEP = 29
local PEERS_MAX_COUNT = 1000
local RELAY_MAX_COUNT = 100
for i = 1, RELAY_MAX_COUNT do
	relayid[i] = RELAY_MAX_COUNT - i + 1
end

local NETRECORD_PATTERN = '([^' .. strchar(SEP) .. ']+)'
local function parse(payload)
	local arr, i = { }, 1
	for v in strgmatch(payload, NETRECORD_PATTERN) do
		arr[i] = v
		i = i + 1
	end
	return unpack(arr)
end

local function convertIP(ip)
	local num = 0
	for i in strgmatch(ip, '%d+') do
		num = num * 256 + assert(tonumber(i))
	end
	return num
end

local MasterEvents = {
	receive = function (self, event)
		local client = clients[event.peer:connect_id()]
		if not client then return end
		local relay = client.relays[event.channel]
		if relay then
			relay.peer:send(event.data, event.channel)
			return
		end
		local code, payload = strmatch(event.data, '^(.)(.*)')
		code = code and strbyte(code)
		if code and self[code] then
			self[code](self, event, client, payload)
		end
	end,

	connect = function (self, event)
		local id = event.peer:connect_id()
		if clients[id] then return end
		 local client = {
			id = mdsum(tostring(id)),
			ip = nil,
			name = nil,
			lobby = nil,
			relays = { },
			peer = event.peer
		}
		clients[id] = client
		users[client.id] = id
		clients.count = clients.count + 1
		print('CONNECT', client.id, 'Count:', clients.count)
	end,

	disconnect = function (self, event)
		local peer = event.peer
		for id, client in pairs(clients) do
			if id ~= 'count' and client.peer == peer then
				if client.name then
					print('LOGOUT', client.name)
				else
					print('D/C', id)
				end
				if client.lobby then
					client.lobby:remove(id)
				end
				for channel, relay in pairs(client.relays) do
					print('RDROP', strformat('%s <-> %s', client.name, relay.name))
					relay.peer:send(strformat('%c%s%c%s%c%s', RELAY, client.name, SEP, 0, SEP, channel))
					relay.relays[channel] = nil
					client.relays[channel] = nil
					relayid[#relayid + 1] = channel
				end
				clients[id] = nil
				users[client.id] = nil
				clients.count = clients.count - 1
				break
			end
		end
	end,

	[LOGIN] = function (self, event, client, payload)
		local ip, name = parse(payload)
		if not name or client.name then return end
		if users[mdsum(name)] then
			client.peer:disconnect(228)
			return
		end
		users[client.id] = nil
		client.id, client.ip, client.name = mdsum(name), ip, name
		users[client.id] = event.peer:connect_id()
		print('LOGIN', client.id, name)
	end,

	[LEAVE] = function (self, event, client, payload)
		if client.lobby then
			client.lobby:remove(event.peer:connect_id())
		end
	end,

	[FIND] = function (self, event, c1, payload)
		local id1 = event.peer:connect_id()
		local lobby = Lobby:get(payload)
		if lobby then
			if lobby:add(id1, c1) then
				print('ADD', lobby.id, c1.name)
			end
			return
		end
		local id2 = users[mdsum(payload)]
		local c2 = id2 and clients[id2]
		if not c2 then
			lobby = Lobby()
			print('LOBBY', lobby.id, c1.name)
			lobby:add(id1, c1)
		elseif c1.lobby then
			if c1.lobby:add(id2, c2) then
				print('ADD', c1.lobby.id, c2.name)
			end
		elseif c2.lobby then
			if c2.lobby:add(id1, c1) then
				print('ADD', c2.lobby.id, c1.name)
			end
		else
			lobby = Lobby()
			print('LOBBY', lobby.id, c1.name, c2.name)
			lobby:add(id1, c1)
			lobby:add(id2, c2)
		end
	end,

	[LIST] = function (self, event, client, payload)
		local lobbies = { }
		local max_count = tonumber(payload) or 1000
		for id, lobby in Lobby:all() do
			local players = { }
			for _, player in pairs(lobby.players) do
				players[#players + 1] = strformat('"%s"', player.name)
			end
			lobbies[#lobbies + 1] = strformat('{"id":"%s","players":[%s]}', lobby.id, strjoin(players, ','))
			if #lobbies >= max_count then
				break
			end
		end
		client.peer:send( strformat('%c%s', LIST, strjoin(lobbies, strchar(SEP))) )
	end,

	[RELAY] = function (self, e, c1, payload)
		local id = users[payload] or users[mdsum(payload)]
		local c2 = id and clients[id]
		if not c2 or #relayid == 0 then return end
		-- Save relay remapping and notify clients about successful connection
		local p1, p2 = c1.name or c1.id, c2.name or c2.id
		if e.channel == relayid[#relayid] then
			print('RACCEPT', strformat('%s <-> %s [%s]', p1, p2, e.channel))
			relayid[#relayid] = nil
			if not c2.relays[e.channel] then
				c2.relays[e.channel] = c1
				c2.peer:send(strformat('%c%s%c%s%c%s', RELAY, p1, SEP, max(1, ceil(c1.peer:round_trip_time() / 2)), SEP, e.channel), e.channel)
			end
			if not c1.relays[e.channel] then
				c1.relays[e.channel] = c2
				c1.peer:send(strformat('%c%s%c%s%c%s', RELAY, p2, SEP, max(1, ceil(c2.peer:round_trip_time() / 2)), SEP, e.channel), e.channel)
			end
			return
		-- Relay is only possible between directly connected peers
		elseif e.channel > 0 then
			print('RREJECT', strformat('%s <-> %s [%s]', p1, p2, e.channel))
			return
		end
		-- Reply for the first request with a free relay channel
		print('RELAY', strformat('%s <-> %s [%s]', p1, p2, relayid[#relayid]))
		c1.peer:send(strformat('%c%s%c%s%c%s', RELAY, payload, SEP, max(1, ceil(c2.peer:round_trip_time() / 2)), SEP, relayid[#relayid]))
	end,
}

local server = enet.host_create('*:12565', max(PEERS_MAX_COUNT, RELAY_MAX_COUNT * 2), RELAY_MAX_COUNT + 1)
math.randomseed(os.time())
print('MasterServer started:', server:get_socket_address())
while true do
	local event = server:service(50)
	while event do
		if MasterEvents[event.type] then
			MasterEvents[event.type](MasterEvents, event)
		end
		event = server:service()
	end
end
server:destroy()
