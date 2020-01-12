local strchar = string.char
local strmatch = string.match
local strformat = string.format

-- Master message codes
local FLUSH = 1
local JOIN = 2

local counter = 0
local lobbies = { }
local Lobby = { }

	function Lobby:all()
		return lobbies
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
			print('MOVE:', player.lobby.id, '->', self.id, player.name)
			player.lobby:remove(id)
			player.peer:send( strchar(FLUSH) )
		end
		player.lobby = self

		local ip1, ip2
		for i, other in pairs(self.players) do
			ip1, ip2 = tostring(player.peer), tostring(other.peer)
			print('LINK:', strformat('%s[%s]', player.name, ip1), strformat('%s[%s]', other.name, ip2))
			player.peer:send( strformat('%c%s;%s;%s;%s', JOIN, strmatch(ip1, '^(%S*):'), other.name, other.ip, ip2) )
			other.peer:send( strformat('%c%s;%s;%s;%s', JOIN, strmatch(ip2, '^(%S*):'), player.name, player.ip, ip1) )
		end
		self.players[id] = player
		self.size = self.size + 1
	end

	function Lobby:remove(id)
		if self.players[id] then
			print('REMOVE:', self.id, self.players[id].name)
			self.players[id].lobby = nil
			self.players[id] = nil
			self.size = self.size - 1
			if self.size == 0 then
				print('DESTROY:', self.id)
				self.players = { }
				lobbies[self.id] = nil
			end
		end
	end

return setmetatable(Lobby, {
	__index = Lobby,
	__call = function (cls, ...) return cls:new(...) end
})
