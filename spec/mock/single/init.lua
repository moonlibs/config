#!/usr/bin/env tarantool
require 'package.reload'
require 'config' {
	mkdir = true,
	print_config = true,
	instance_name = os.getenv('TT_INSTANCE_NAME'),
	file = os.getenv('TT_CONFIG'),
	master_selection_policy = os.getenv('TT_MASTER_SELECTION_POLICY'),
	on_after_cfg = function()
		if not box.info.ro then
			box.schema.user.grant('guest', 'super', nil, nil, { if_not_exists = true })
		end
	end,
}
