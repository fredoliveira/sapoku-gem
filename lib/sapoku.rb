require 'redis'
require 'erb'

class Tadpole
	attr_accessor :container_ip, :local_port, :app_name, :userid, :ram
	$redis = Redis.new

	# return an instance based on a given name, if it exists
	def self.find(name)
		# if this is false, return nil
		return nil if !$redis.hexists(name, "ip")

		tadpole = self.new(name)
		tadpole.container_ip = $redis.hget(name, "ip")
		tadpole.local_port = $redis.hget(name, "localport")
		tadpole.userid = $redis.hget(name, "userid")
		tadpole.ram = $redis.hget(name, "ram")
		return tadpole
	end

	# create a new container stub (then requires saving)
	def initialize(name)
		@container_ip = getfreeip
		@local_port = getlocalport
		@app_name = name
		@ram = 256
	end

	# creates and saves the new container
	def save
		$redis.hset(@app_name, "ip", @container_ip)
		$redis.hset(@app_name, "localport", @local_port)
		$redis.hset(@app_name, "userid", @userid)
		$redis.hset(@app_name, "ram", @ram)
	end

	# actually creates and initializes the container
	def bootstrap
		system("sudo lxc-clone -o frox -n #{@app_name}")
		create_config
		system("sudo lxc-start -n #{@app_name} -d")
		create_iptables
	end

	# returns a free IP to be used by the container being bootstrapped
	def getfreeip
		$redis.spop("sapoku:freeips")
	end
	
	# return a free port to be used to forward external->internal requests
	def getlocalport
		$redis.spop("sapoku:freeports")
	end

	def get_binding
		binding
	end
	
	# generate a new config file
	def create_config
		@ip = self.container_ip
		@ram = self.ram
		@name = self.app_name

		template = %{
lxc.network.type=veth
lxc.network.link=lxcbr0
lxc.network.flags=up
#lxc.network.hwaddr=00:16:3e:85:68:c1
lxc.network.ipv4=<%= @ip %>

lxc.devttydir = lxc
lxc.tty = 4
lxc.pts = 1024
lxc.arch = amd64
lxc.cap.drop = sys_module mac_admin
lxc.pivotdir = lxc_putold

lxc.cgroup.memory.limit_in_bytes = <%= @ram %>M

# uncomment the next line to run the container unconfined:
#lxc.aa_profile = unconfined

lxc.cgroup.devices.deny = a
# Allow any mknod (but not using the node)
lxc.cgroup.devices.allow = c *:* m
lxc.cgroup.devices.allow = b *:* m
# /dev/null and zero
lxc.cgroup.devices.allow = c 1:3 rwm
lxc.cgroup.devices.allow = c 1:5 rwm
# consoles
lxc.cgroup.devices.allow = c 5:1 rwm
lxc.cgroup.devices.allow = c 5:0 rwm
#lxc.cgroup.devices.allow = c 4:0 rwm
#lxc.cgroup.devices.allow = c 4:1 rwm
# /dev/{,u}random
lxc.cgroup.devices.allow = c 1:9 rwm
lxc.cgroup.devices.allow = c 1:8 rwm
lxc.cgroup.devices.allow = c 136:* rwm
lxc.cgroup.devices.allow = c 5:2 rwm
lxc.cgroup.devices.allow = c 254:0 rwm
lxc.cgroup.devices.allow = c 10:229 rwm
lxc.cgroup.devices.allow = c 10:200 rwm
lxc.cgroup.devices.allow = c 1:7 rwm
lxc.cgroup.devices.allow = c 10:228 rwm
lxc.cgroup.devices.allow = c 10:232 rwm

lxc.utsname = <%= @name %>
lxc.mount = /var/lib/lxc/<%= @name %>/fstab
lxc.rootfs = /var/lib/lxc/<%= @name %>/rootfs
}

		erb = ERB.new(template)

		File.open("#{@name}_config", 'w') do |f|
			f.write erb.result(self.get_binding)
		end

		system("sudo mv #{@name}_config /var/lib/lxc/#{@name}/config")
	end
	
	# create the new iptables rule to fwd accesses into the container
	def create_iptables
		system("sudo iptables -t nat -A PREROUTING -p tcp --dport #{@local_port} -j DNAT --to-destination #{@container_ip}:8080")
	end
end