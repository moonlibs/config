setup:
	tc qdisc add dev eth0 root handle 1: prio
	tc qdisc add dev eth0 parent 1:3 handle 10: netem loss 100%

offline-dport-%:
	tc filter add dev eth0 parent 1: protocol ip prio 1 u32 match ip dport $* 0xffff flowid 1:3

offline-dst-%:
	tc filter add dev eth0 parent 1: protocol ip prio 1 u32 match ip dst $(shell host -T4 $* | cut -f 4 -d' ') flowid 1:3

online:
	tc filter del dev eth0 parent 1: protocol ip pref 1 u32

filter:
	tc -s -d filter show dev eth0

qdisc:
	tc -d -s qdisc show dev eth0

clear:
	tc fliter del dev eth0 parent 1:
	tc qdisc del dev eth0 root
