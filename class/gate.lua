local skynet = require "skynet"

local MAX_CACHE_MSG = 256


local function load_player(pid, ip)
	return {
		id = pid,
		gold = 100,
		ip = ip
	}
end


local function auth(msg, ip)
	assert(msg.id and msg.password == "123")
	return true, load_player(msg.id, ip)
end


local function newclient(conn, id, pid)

	local self = {
		connected = true,
		pid = pid,
		msgidx = 0,
		msgcache = {},
		token = string.random_str(8) 		-- for reconnect auth
	}

	function self.update(newconn)
		conn.client = nil
		conn.close()
		conn = newconn
	end

	function self.close()
		conn.client = nil
		conn.close()
	end

	function self.send(msg)
		self.msgidx = self.msgidx + 1
		self.msgcache[self.msgidx] = msg

		if self.msgidx > MAX_CACHE_MSG then
			self.msgcache[self.msgidx - MAX_CACHE_MSG] = nil
		end

		conn.send(msg)
	end

	function self.disconnect()
		self.connected = false
	end

	return self
end


return function (handle)

	local client_map = {}	-- pid -> client


	local self = {}

	function self:send_push(pid, msg)
		local c = client_map[pid]
		if c then
			c.send(msg)
		else
			skynet.error(string.format("Push error, can't found player %s", pid))
		end
	end

	function self.connect(conn)

		conn.verified = false

		local function login(msg)
			local ok, p = auth(msg, conn.ip)
			if ok then
				dump("Login OK", p)
				local old_c = client_map[p.id]
				if old_c then
					old_c.close()
				end

				handle(p.id, {"login", p})

				local c = newclient(conn, id, p.id)
				client_map[p.id] = c

				conn.verified = true
				conn.client = c
				conn.send{ok = true, token = c.token, p = p}
			else
				conn.send{ok = false, err = p}
			end
		end

		local function reconnect(msg)
			local pid = assert(msg.id)
			local msgidx = assert(msg.msgidx)
			local c = client_map[pid]
			if not c then
				conn.send{ok = false}
				return
			end
			if c.token ~= msg.token then
				conn.send{ok = false}
				return
			end
			if c.msgidx - msgidx > MAX_CACHE_MSG or msgidx > c.msgidx then
				conn.send{ok = false}
				return
			end

			c.update(conn)
			conn.verified = true
			conn.client = c

			conn.send{ok = true}
			for i=msgidx+1,c.msgidx do
				conn.send(c.msgcache[i])
			end
		end

		function conn.message(msg)
			if conn.verified == false then
				-- msg: {cmd = "login", id = "xx", password = "123"}
				if msg.cmd == "login" then
					login(msg)
				else
					-- msg: {cmd = "reconnect", id = "xx", token = "xxx", msgidx = 0}
					assert(msg.cmd == "reconnect")
					reconnect(msg)
				end
			else
				-- msg: {session = 1, request = {"playcard", "pid", ...}}
				local c = conn.client
				local r = handle(c.pid, msg.request)
				
				if session > 0 then
					r = r or {}
					r.session = msg.session
					c.send(r)
				end
			end
		end

		function conn.disconnect()
			if conn.client then
				conn.client.disconnect()
			end
		end
	end

	return self
end