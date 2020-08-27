-- Lobby Matchmaking Tool
-- @author Abelidze
-- @copyright Atom-TM 2020

local next = _G.next
local print = _G.print
local pairs = _G.pairs
local tostring = _G.tostring
local strchar = string.char
local strmatch = string.match
local strformat = string.format

-- Master message codes
local FLUSH = 1
local LIST = 2
local LINK = 3
local RELAY = 4

local counter = 0
local lobbies = { }
local Lobby = { }

	function Lobby:all()
		return next, lobbies
	end

	function Lobby:new()
		local lobby = setmetatable({ id = counter, players = { }, size = 0 }, self)
		self.__index = self
		self.__call = function (cls, ...) return cls:new(...) end
		counter = counter + 1
		lobbies[lobby.id] = lobby
		return lobby
	end

	function Lobby:add(id, player)
		if self.players[id] then return end

		if player.lobby then
			print('MOVE', player.lobby.id, '->', self.id, player.name)
			player.lobby:remove(id)
			player.peer:send( strchar(FLUSH) )
		end
		player.lobby = self

		local ip1, port1, ip2, port2
		for i, other in pairs(self.players) do
			ip1, port1 = strmatch(tostring(player.peer), '^(%S*):(%S*)')
			ip2, port2 = strmatch(tostring(other.peer), '^(%S*):(%S*)')
			print('LINK', strformat('%s:%s[%s] <-> %s:%s[%s]', player.name, ip1, port1, other.name, ip2, port2))
			player.peer:send( strformat('%c%s%c%s%c%s%c%s%c%s', LINK, ip1, 29, other.name, 29, other.ip, 29, ip2, 29, port2) )
			other.peer:send( strformat('%c%s%c%s%c%s%c%s%c%s', LINK, ip2, 29, player.name, 29, player.ip, 29, ip1, 29, port1) )
		end
		self.players[id] = player
		self.size = self.size + 1
	end

	function Lobby:remove(id)
		if not self.players[id] then return end
		print('LEAVE', self.id, self.players[id].name)
		self.players[id].lobby = nil
		self.players[id] = nil
		self.size = self.size - 1
		if self.size > 0 then return end
		print('DESTROY', self.id)
		self.players = { }
		lobbies[self.id] = nil
	end

return setmetatable(Lobby, {
	__index = Lobby,
	__call = function (cls, ...) return cls:new(...) end
})
