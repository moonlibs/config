#!/usr/bin/env tarantool
local vshard = require 'vshard'
rawset(_G, 'vshard', vshard)

require 'package.reload'
require 'config' {
	mkdir = true,
	print_config = true,
	instance_name = os.getenv('TT_INSTANCE_NAME'),
	file = os.getenv('TT_CONFIG'),
	master_selection_policy = os.getenv('TT_MASTER_SELECTION_POLICY'),
	on_after_cfg = function(_,cfg)
		if cfg.cluster then
			vshard.storage.cfg({
				bucket_count = config.get('vshard.bucket_count'),
				sharding = config.sharding(),
				zone = config.get('vshard.zone'),
				weights = config.get('vshard.weights'),
				rebalancer_max_receiving = config.get('vshard.rebalancer_max_receiving'),
				rebalancer_max_sending = config.get('vshard.rebalancer_max_sending'),
				sync_timeout = config.get('vshard.sync_timeout'),
				discovery_mode = config.get('vshard.discovery_mode'),
				identification_mode = 'uuid_as_key',
			}, box.info.uuid)
		end
		if cfg.router then
			vshard.router.cfg({
				bucket_count = config.get('vshard.bucket_count'),
				sharding = config.sharding(),
				zone = config.get('vshard.zone'),
				zone_weights = config.get('vshard.zone_weights'),
			})
		end
	end,
}
