--- Master server and NAT Facilitator
-- TODO: optimize the structure for clients (dequeue)
-- @author Abelidze
-- @copyright Atom-TM 2020

local enet = require 'enet'
local Lobby = require 'lobby'

local max = math.max
local ceil = math.ceil
local strchar = string.char
local strbyte = string.byte
local strjoin = table.concat
local strmatch = string.match
local strgmatch = string.gmatch
local strformat = string.format

-- Client message codes
local INIT = 1
local LIST = 2
local FIND = 3
local RELAY = 4
local LEAVE = 5

local clients = { count = 0 }
local relayid = { }
local usernames = { }

local PEERS_MAX_COUNT = 1000
local RELAY_MAX_COUNT = 100
for i = 1, RELAY_MAX_COUNT do
	relayid[i] = RELAY_MAX_COUNT - i + 1
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
		if not clients[id] then
			clients[id] = {
				ip = nil,
				name = nil,
				lobby = nil,
				relays = { },
				peer = event.peer
			}
			clients.count = clients.count + 1
		end
	end,

	disconnect = function (self, event)
		local peer = event.peer
		for id, client in pairs(clients) do
			if id ~= 'count' and client.peer == peer then
				if client.name then
					usernames[client.name] = nil
					print('LOGOUT', client.name)
				end
				if client.lobby then
					client.lobby:remove(id)
				end
				for channel, relay in pairs(client.relays) do
					print('RDROP', strformat('%s <-> %s', client.name, relay.name))
					relay.peer:send(strformat('%c%s%c%s%c%s', RELAY, client.name, 29, 0, 29, channel))
					relay.relays[channel] = nil
					client.relays[channel] = nil
					relayid[#relayid + 1] = channel
				end
				clients[id] = nil
				clients.count = clients.count - 1
				break
			end
		end
	end,

	[LEAVE] = function (self, event, client, payload)
		if client.lobby then
			client.lobby:remove(event.peer:connect_id())
		end
	end,

	[INIT] = function (self, event, client, payload)
		client.ip, client.name = strmatch(payload, '^(%S*);(%S*)')
		if not client.name then return end
		if usernames[client.name] then
			client.peer:disconnect(228)
			return
		end
		usernames[client.name] = event.peer:connect_id()
		print('LOGIN', event.peer:connect_id(), client.name, 'Count:', clients.count)
	end,

	[LIST] = function (self, event, client, payload)
		local lobbies, i, c = { }
		for id, lobby in Lobby:all() do
			i, c = next(lobby.players)
			if c then
				lobbies[#lobbies + 1] = strformat('%s[%d]', c.name, lobby.size)
			end
		end
		client.peer:send( strformat('%c%s', LIST, strjoin(lobbies, strchar(29))) )
	end,

	[RELAY] = function (self, e, c1, payload)
		local id = usernames[payload]
		local c2 = id and clients[id]
		if not c2 or #relayid == 0 then return end
		-- Save relay remapping and notify clients about successful connection
		if e.channel == relayid[#relayid] then
			print('RACCEPT', strformat('%s <-> %s [%s]', c1.name, c2.name, e.channel))
			relayid[#relayid] = nil
			if not c2.relays[e.channel] then
				c2.relays[e.channel] = c1
				c2.peer:send(strformat('%c%s%c%s%c%s', RELAY, c1.name, 29, max(1, ceil(c1.peer:round_trip_time() / 2)), 29, e.channel), e.channel)
			end
			if not c1.relays[e.channel] then
				c1.relays[e.channel] = c2
				c1.peer:send(strformat('%c%s%c%s%c%s', RELAY, c2.name, 29, max(1, ceil(c2.peer:round_trip_time() / 2)), 29, e.channel), e.channel)
			end
			return
		-- Relay is only possible between directly connected peers
		elseif e.channel > 0 then
			print('RREJECT', strformat('%s <-> %s [%s]', c1.name, c2.name, e.channel))
			return
		end
		-- Reply for the first request with a free relay channel
		print('RELAY', strformat('%s <-> %s [%s]', c1.name, c2.name, relayid[#relayid]))
		c1.peer:send(strformat('%c%s%c%s%c%s', RELAY, payload, 29, max(1, ceil(c2.peer:round_trip_time() / 2)), 29, relayid[#relayid]))
	end,

	[FIND] = function (self, event, c1, payload)
		local id1 = event.peer:connect_id()
		local id2 = usernames[payload]
		local c2 = id2 and clients[id2]
		if not c2 then
			local lobby = Lobby()
			print('LOBBY', lobby.id, c1.name)
			lobby:add(id1, c1)
			return
		end
		if c1.lobby then
			print('ADD', c1.lobby.id, c2.name)
			c1.lobby:add(id2, c2)
		elseif c2.lobby then
			print('ADD', c2.lobby.id, c1.name)
			c2.lobby:add(id1, c1)
		else
			local lobby = Lobby()
			print('LOBBY', lobby.id, c1.name, c2.name)
			lobby:add(id1, c1)
			lobby:add(id2, c2)
		end
	end,
}

local server = enet.host_create('*:12565', max(PEERS_MAX_COUNT, RELAY_MAX_COUNT * 2), RELAY_MAX_COUNT + 1)
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
