Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/xenial64"

  config.vm.network "forwarded_port", guest: 80, host: 8080

  config.vm.provision "shell", inline: "mkdir -p /app"
  config.vm.synced_folder ".", "/app/repo"
  config.vm.provision "shell", path: "provision.sh"

  config.vm.provider :virtualbox do |vb, override|
    vb.customize ["modifyvm", :id, "--memory", "1024"]
    override.vm.network "private_network", ip: "192.168.2.100"
  end

  config.vm.provider :lxc do |lxc, override|
    lxc.customize 'cgroup.memory.limit_in_bytes', '2048M'
    override.vm.box = "developerinlondon/ubuntu_lxc_xenial_x64"
    override.vm.network "private_network", ip: "192.168.2.100", lxc__bridge_name: 'lxc_br'
  end

end