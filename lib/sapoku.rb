require 'redis'
require 'erb'

class Tadpole
	attr_accessor :container_ip, :local_port, :app_name, :userid, :ram, :stack
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
		tadpole.stack = $redis.hget(name, "stack")
		return tadpole
	end

	# returns an array of known Tadpoles - doesn't scale, obviously
	def self.all
		tadpoles = `sudo lxc-ls -1`.split(/\n/).uniq
		output = []
		for t in tadpoles do
			pole = self.find(t)
			output << pole if !pole.nil?
		end
		return output
	end

	# create a new container stub (then requires saving)
	def initialize(name, stack = "ruby")
		@container_ip = getfreeip
		@local_port = getlocalport
		@app_name = name
		@stack = stack
		@ram = 512
	end

	# creates and saves the new container
	def save
		$redis.hset(@app_name, "ip", @container_ip)
		$redis.hset(@app_name, "localport", @local_port)
		$redis.hset(@app_name, "userid", @userid)
		$redis.hset(@app_name, "ram", @ram)
		$redis.hset(@app_name, "stack", @stack)
	end

	# wipes a container from HDD and redis
	def destroy
		$redis.del(@app_name)
		`sudo lxc-stop -n #{@app_name}`
		`sudo lxc-destroy -n #{@app_name}`
	end

	# actually creates and initializes the container
	# returns the actual raw console output of the generated commands
	def bootstrap
		self.save
		output = "Creating new container for your app using the #{@stack} stack"
		output += `sudo lxc-clone -o #{@stack} -n #{@app_name}`
		output += "Applying new config file to container"
		create_lxc_config
		output += "Booting your new container"
		output += `sudo lxc-start -n #{@app_name} -d`
		create_iptables
		output += "Creating nginx configuration file"
		create_nginx_config
		output += "Rehashing nginx configuration"
		rehash_nginx
		return output
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

	def create_nginx_config
		@ip = self.container_ip
		@ram = self.ram
		@name = self.app_name

		template = %{
			server {
				listen 80;
				server_name #{@name}.sapoku.webreakstuff.com;
				access_log off;
				error_log off;

				location / {
					proxy_pass http://#{@ip}:8080;
					proxy_set_header X-Real-IP $remote_addr;
				}
			}
		}

		erb = ERB.new(template)

		File.open("#{@name}_nginx_config", 'w') do |f|
			f.write erb.result(self.get_binding)
		end

		system("sudo mv #{@name}_nginx_config /opt/nginx/conf/containers/#{@name}.conf")
	end

	# reload nginx configuration
	def rehash_nginx
		`sudo kill -HUP $(cat /opt/nginx/logs/nginx.pid)`
	end
	
	# generate a new config file
	def create_lxc_config
		@ip = self.container_ip
		@ram = self.ram
		@name = self.app_name

		template = %{
lxc.utsname = <%= @name %>
lxc.mount = /var/lib/lxc/<%= @name %>/fstab
lxc.rootfs = /var/lib/lxc/<%= @name %>/rootfs

# networking
lxc.network.type=veth
lxc.network.flags=up
lxc.network.link=lxcbr0
#lxc.network.hwaddr=00:16:3e:85:68:c1
lxc.network.name = eth0
lxc.network.ipv4=<%= @ip %>/24

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