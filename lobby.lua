-- Lobby Matchmaking Class
-- @author Abelidze
-- @copyright Atom-TM 2020

local next = _G.next
local print = _G.print
local pairs = _G.pairs
local tostring = _G.tostring
local random = math.random
local strjoin = table.concat
local strchar = string.char
local strbyte = string.byte
local strmatch = string.match
local strformat = string.format

-- Master message codes
local FLUSH = 1
local LIST = 2
local LINK = 3
local RELAY = 4
local LOBBY = 6

local SEP = 29
local lobbies = { }

local Lobby = { }

	local A, Z = strbyte('a'), strbyte('z')
	local function randomtext(min, max)
		local result = { }
		for i = 1, random(min, max) do
			result[i] = strchar(random(A, Z))
		end
		return strjoin(result)
	end

	local function genid()
		local id
		repeat
			id = strformat('%s#%03d', randomtext(3, 5), random(0, 999))
		until not lobbies[id]
		return id
	end

	function Lobby:all()
		return next, lobbies
	end

	function Lobby:new()
		local lobby = setmetatable({ id = genid(), players = { }, size = 0 }, self)
		self.__index = self
		self.__call = function (cls, ...) return cls:new(...) end
		lobbies[lobby.id] = lobby
		return lobby
	end

	function Lobby:get(id)
		return lobbies[id]
	end

	function Lobby:add(id, player)
		if self.players[id] then return end

		if player.lobby then
			print('MOVE', player.lobby.id, '->', self.id, player.name or player.id)
			player.lobby:remove(id)
			player.peer:send( strchar(FLUSH) )
		end
		player.lobby = self
		player.peer:send( strformat('%c%s', LOBBY, self.id) )
		local ip1, port1, ip2, port2
		for i, other in pairs(self.players) do
			ip1, port1 = strmatch(tostring(player.peer), '^(%S*):(%S*)')
			ip2, port2 = strmatch(tostring(other.peer), '^(%S*):(%S*)')
			print('LINK', strformat('%s:%s[%s] <-> %s:%s[%s]', ip1, port1, player.name or player.id, ip2, port2, other.name or other.id))
			player.peer:send( strformat('%c%s%c%s%c%s%c%s%c%s%c%s', LINK, ip1, SEP, other.id, SEP, other.name, SEP, other.ip, SEP, ip2, SEP, port2) )
			other.peer:send( strformat('%c%s%c%s%c%s%c%s%c%s%c%s', LINK, ip2, SEP, player.id, SEP, player.name, SEP, player.ip, SEP, ip1, SEP, port1) )
		end
		self.players[id] = player
		self.size = self.size + 1
		return true
	end

	function Lobby:remove(id)
		local player = self.players[id]
		if not player then return end
		print('LEAVE', self.id, player.name or player.id)
		player.lobby = nil
		self.players[id] = nil
		self.size = self.size - 1
		if self.size > 0 then return end
		print('DESTROY', self.id)
		self.players = { }
		lobbies[self.id] = nil
		return true
	end

return setmetatable(Lobby, {
	__index = Lobby,
	__call = function (cls, ...) return cls:new(...) end
})
