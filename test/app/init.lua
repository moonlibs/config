local fiber = require "fiber"

require 'package.reload'

require 'config' {
	mkdir = true,
	instance_name = os.getenv("TT_INSTANCE_NAME"),
	file = 'conf.lua',
	master_selection_policy = 'etcd.cluster.master',

	on_after_cfg = function()
		if not box.info.ro then
			box.schema.user.grant('guest', 'super', nil, nil, { if_not_exists = true })

			box.schema.space.create('T', {if_not_exists = true})
			box.space.T:create_index('I', { if_not_exists = true })
		end
	end,
}

fiber.create(function()
	fiber.name('pusher')

	while true do
		repeat
			pcall(box.ctl.wait_rw, 3)
			fiber.testcancel()
		until not box.info.ro

		local fibers = {}
		for _ = 1, 10 do
			local f = fiber.create(function()
				fiber.self():set_joinable(true)
				for _ = 1, 10 do
					box.space.T:insert{box.space.T:len(), box.info.id, box.info.vclock}
				end
				fiber.sleep(0.001)
			end)
			table.insert(fibers, f)
		end

		for _, f in ipairs(fibers) do
			f:join()
		end
	end
end)

