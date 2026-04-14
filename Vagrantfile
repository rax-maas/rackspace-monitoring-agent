Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 2
  end

  config.vm.provision "file",
    source: "./dist/rackspace-monitoring-agent-2.6.23-amd64.deb",
    destination: "/tmp/rackspace-monitoring-agent-2.6.23-amd64.deb"

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update -qq
    apt-get install -y /tmp/rackspace-monitoring-agent-2.6.23-amd64.deb
    echo "=== Checking installed version ==="
    rackspace-monitoring-agent -v
  SHELL
end
