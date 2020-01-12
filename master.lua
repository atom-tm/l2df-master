-- NAT Facilitator
-- TODO: optimize the structure for clients (dequeue)

local enet = require 'enet'
local Lobby = require 'lobby'

local strbyte = string.byte
local strmatch = string.match
local strgmatch = string.gmatch
local strformat = string.format

-- Client message codes
local INIT = 1
local FIND = 2


local clients = { count = 0 }
local usernames = { }

local function convertIP(ip)
	local num = 0
	for i in strgmatch(ip, '%d+') do
		num = num * 256 + assert(tonumber(i))
	end
	return num
end

local MasterEvents = {
	receive = function (self, event)
		local code, payload = strmatch(event.data, '^(.)(.*)')
		code = code and strbyte(code)
		if code and self[code] then
			self[code](self, event, payload)
		end
	end,

	connect = function (self, event)
		local id = event.peer:connect_id()
		if not clients[id] then
			clients[id] = {
				ip = nil,
				name = nil,
				lobby = nil,
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
				end

				if client.lobby then
					print('LEAVE:', client.lobby.id, client.name)
					client.lobby:remove(id)
				end
				clients[id] = nil
				clients.count = clients.count - 1
				break
			end
		end
	end,

	[INIT] = function (self, event, payload)
		local id = event.peer:connect_id()
		local client = clients[id]
		if not client then return end

		client.ip, client.name = payload:match('^(%S*);(%S*)')
		if client.name then
			usernames[client.name] = id
			print('INIT:', id, client.name, 'Count:', clients.count)
		end
	end,

	[FIND] = function (self, event, payload)
		local id1 = event.peer:connect_id()
		local c1 = clients[id1]
		if not c1 then return end

		local id2 = usernames[payload]
		print(payload, id2)
		local c2 = id2 and clients[id2]

		if not c2 then
			local lobby = Lobby()
			print('LOBBY:', lobby.id, c1.name)
			lobby:add(id1, c1)
			return
		end

		if c1.lobby then
			print('ADD:', c1.lobby.id, c2.name)
			c1.lobby:add(id2, c2)
		elseif c2.lobby then
			print('ADD:', c2.lobby.id, c1.name)
			c2.lobby:add(id1, c1)
		else
			local lobby = Lobby()
			print('LOBBY:', lobby.id, c1.name, c2.name)
			lobby:add(id1, c1)
			lobby:add(id2, c2)
		end
	end,
}

local server = enet.host_create('*:12565')
print('MasterServer started:', server:get_socket_address())
while true do
	local event = server:service(50)
	while event do
		print(event.type, 'with', event.peer, 'Data:', event.data)

		if MasterEvents[event.type] then
			MasterEvents[event.type](MasterEvents, event)
		end
		event = server:service()
	end
end
server:destroy()
